#include "dsb_rp.hh"

#include <cassert>
#include <cstdio>
#include <memory>

#include "params/DSBRP.hh"
#include "sim/cur_tick.hh"
#include "base/random.hh"
#include "mem/cache/cache_blk.hh"

namespace gem5
{

namespace replacement_policy
{

DSB::DSB(const Params &p)
  : Base(p),
    randomPromotion(p.random_promotion),
    bypass_counter(p.bypass_counter),
    virtual_bypass_counter(p.virtual_bypass_counter)
{
}

DSB::~DSB()
{
  fprintf(stderr,
    "\n===== DSB INSTRUMENTATION SUMMARY =====\n"
    "getVictim calls:            %lu\n"
    "  Real bypass started:      %lu\n"
    "  Virtual bypass started:   %lu\n"
    "  No tracking:              %lu\n"
    "Touch resolutions:          %lu\n"
    "  Real bypass effective:    %lu  (victim survived hit -> bc--)\n"
    "  Virtual bypass ineffect:  %lu  (inserted line got hit -> bc++)\n"
    "Reset resolutions:          %lu\n"
    "  Real bypass ineffective:  %lu  (bypassed tag returned -> bc++)\n"
    "  Virtual bypass effective: %lu  (evicted tag returned -> bc--)\n"
    "bypass_counter increments:  %lu\n"
    "bypass_counter decrements:  %lu\n"
    "Invalidate cancellations:   %lu\n"
    "Final bypass_counter value: %d\n"
    "========================================\n",
    stat_getVictimCalls,
    stat_realBypassStarted,
    stat_virtualBypassStarted,
    stat_noTracking,
    stat_touchResolved,
    stat_touchRealBypassEffective,
    stat_touchVirtualBypassIneffective,
    stat_resetResolved,
    stat_resetRealBypassIneffective,
    stat_resetVirtualBypassEffective,
    stat_bcIncrements,
    stat_bcDecrements,
    stat_invalidateCancelled,
    bypass_counter);
}

void
DSB::invalidate(const std::shared_ptr<ReplacementData>& replacement_data)
{
  auto replData = std::static_pointer_cast<DSBReplData>(replacement_data);

  // Reset last touch timestamp
  replData->lastTouchTick = Tick(0);

  // Reset reference bit to non-reference list
  replData->referenceBit = 0;

  // Cancel any active tracking episode if this line was the competitor
  ReplaceableEntry* entry = replData->entry;
  if (entry != NULL) {
    uint32_t set = entry->getSet();
    uint32_t way = entry->getWay();
    CompetitorInfo& info = competitorMap[set];
    if (info.competitorValid && way == info.competitorWay) {
      info.competitorValid = false;
      stat_invalidateCancelled++;
    }
  }
}

void
DSB::touch(const std::shared_ptr<ReplacementData>& replacement_data) const
{
  auto replData = std::static_pointer_cast<DSBReplData>(replacement_data);

  // Update last touch timestamp
  replData->lastTouchTick = curTick();

  // Update reference
  replData->referenceBit = 1;

  ReplaceableEntry* entry = replData->entry;

  if (entry != NULL) {
    // resolve
    uint32_t set = entry->getSet();
    uint32_t way = entry->getWay();

    CompetitorInfo& competitorInfo = competitorMap[set];
    if (competitorInfo.competitorValid) {
      // Bypass was successful
      if (way == competitorInfo.competitorWay) {
        stat_touchResolved++;
        if (!competitorInfo.isVirtualBypass) {
          // way is the victim
          // this means that we should bypass
          bypass_counter -= 1;
          stat_bcDecrements++;
          stat_touchRealBypassEffective++;
        } else {
          // successful virtual bypass
          // inserted line got hit
          // way is the inserted line
          // this means that we shouldn't bypass
          bypass_counter += 1;
          stat_bcIncrements++;
          stat_touchVirtualBypassIneffective++;
        }
        bypass_counter = std::max(0, std::min(bypass_counter, 12));
        competitorInfo.competitorValid = false;
      }
    }
  }
}

void
DSB::reset(const std::shared_ptr<ReplacementData>& replacement_data) const
{
  auto replData = std::static_pointer_cast<DSBReplData>(replacement_data);
  
  // Set last touch timestamp
  replData->lastTouchTick = curTick();
  
  // Set to non-reference list
  replData->referenceBit = 0;

  // Random promotion
  if (randomPromotion > 0 && random_mt.random<unsigned>(1, 1u << randomPromotion) == 1) {
    replData->referenceBit = 1;
  }

  ReplaceableEntry* entry = replData->entry;
  if (entry != NULL) {
    // resolve
    uint32_t set = entry->getSet();
    CompetitorInfo& competitorInfo = competitorMap[set];
    Addr tag = static_cast<TaggedEntry*>(entry)->getTag();

    if (competitorInfo.competitorValid) {
      if (tag == competitorInfo.competitorTag) {
        stat_resetResolved++;
        // Resolution: bypassed/evicted line came back as a miss
        if (!competitorInfo.isVirtualBypass) {
          // Real bypass was ineffective, be less aggressive
          bypass_counter += 1;
          stat_bcIncrements++;
          stat_resetRealBypassIneffective++;
        } else {
          // Virtual bypass: evicted line missed, we should have bypassed
          bypass_counter -= 1;
          stat_bcDecrements++;
          stat_resetVirtualBypassEffective++;
        }
        bypass_counter = std::max(0, std::min(bypass_counter, 12));
        competitorInfo.competitorValid = false;
      }
    }
  }
}

ReplaceableEntry*
DSB::getVictim(const ReplacementCandidates& candidates) const
{
  // There must be at least one replacement candidate
  assert(candidates.size() > 0);

  // Aging
  // loop through each cache line
  // and set referenceBit to 0 for worst lastTouchTick
  // find first candidate with reference bit == 1
  ReplaceableEntry* referenceVictim = NULL; // victim to age
  ReplaceableEntry* nonReferenceVictim = NULL; // victim to evict
  for (const auto& candidate : candidates) {
    
    // Must save replacement entry into data 
    std::static_pointer_cast<DSBReplData>(
        candidate->replacementData)->entry = candidate;
    
    
    if (std::static_pointer_cast<DSBReplData>(
        candidate->replacementData)->referenceBit == 1) {
      // set first reference victim
      if (referenceVictim == NULL) {
        referenceVictim = candidate;
      } else {
        if (std::static_pointer_cast<DSBReplData>(
          candidate->replacementData)->lastTouchTick <
          std::static_pointer_cast<DSBReplData>(
            referenceVictim->replacementData)->lastTouchTick) {
          referenceVictim = candidate;
        }
      }
    } else {
      // set first non reference victim
      if (nonReferenceVictim == NULL) {
        nonReferenceVictim = candidate;
      } else {
        if (std::static_pointer_cast<DSBReplData>(
          candidate->replacementData)->lastTouchTick <
          std::static_pointer_cast<DSBReplData>(
            nonReferenceVictim->replacementData)->lastTouchTick) {
          nonReferenceVictim = candidate;
        }
      }
    }
  }

  // Choose victim
  ReplaceableEntry* victim = candidates[0];
  // Age
  if (referenceVictim != NULL) {
    std::static_pointer_cast<DSBReplData>(
            referenceVictim->replacementData)->referenceBit = 0;
    victim = referenceVictim;
  } 
  if (nonReferenceVictim != NULL) {
    victim = nonReferenceVictim;
  }

  // Decide whether to bypass
  // 1 Competitor Info per set
  uint32_t victimSet = victim->getSet();
  uint32_t victimWay = victim->getWay();
  CompetitorInfo& competitorInfo = competitorMap[victimSet];

  stat_getVictimCalls++;

  if (stat_getVictimCalls % 100000 == 0) {
    fprintf(stderr,
      "[DSB @ %lu calls] bc=%d | real=%lu virt=%lu notrack=%lu | "
      "touchRes=%lu(eff=%lu,ineff=%lu) resetRes=%lu(ineff=%lu,eff=%lu) | "
      "bc++=%lu bc--=%lu inv=%lu\n",
      stat_getVictimCalls, bypass_counter,
      stat_realBypassStarted, stat_virtualBypassStarted, stat_noTracking,
      stat_touchResolved, stat_touchRealBypassEffective,
      stat_touchVirtualBypassIneffective,
      stat_resetResolved, stat_resetRealBypassIneffective,
      stat_resetVirtualBypassEffective,
      stat_bcIncrements, stat_bcDecrements,
      stat_invalidateCancelled);
  }

  // bypass
  if (random_mt.random<unsigned>(1, 1u << bypass_counter) == 1) {
    // True bypass: tell allocateBlock to skip insertion
    std::static_pointer_cast<DSBReplData>(
        victim->replacementData)->shouldBypass = true;

    competitorInfo.competitorValid = true;
    competitorInfo.startBypass = true;     // tag will arrive via notifyBypass()
    competitorInfo.competitorWay = victimWay;
    competitorInfo.isVirtualBypass = false;
    stat_realBypassStarted++;
  } else if (random_mt.random<unsigned>(1, 1u << virtual_bypass_counter) == 1) {
    // Virtual bypass: normal insertion, but track as if bypassed
    competitorInfo.competitorValid = true;
    competitorInfo.startBypass = false;
    competitorInfo.competitorTag = static_cast<TaggedEntry*>(victim)->getTag();
    competitorInfo.competitorWay = victimWay;
    competitorInfo.isVirtualBypass = true;
    stat_virtualBypassStarted++;
  } else {
    // No bypass, no tracking
    competitorInfo.competitorValid = false;
    stat_noTracking++;
  }

  return victim;
}

void
DSB::notifyBypass(const std::shared_ptr<ReplacementData>& replacement_data,
                  Addr bypassedTag)
{
  auto replData = std::static_pointer_cast<DSBReplData>(replacement_data);
  ReplaceableEntry* entry = replData->entry;
  if (entry != NULL) {
    uint32_t set = entry->getSet();
    CompetitorInfo& info = competitorMap[set];
    if (info.competitorValid && info.startBypass) {
      info.competitorTag = bypassedTag;
      info.startBypass = false;
    }
  }
}

std::shared_ptr<ReplacementData>
DSB::instantiateEntry()
{
  return std::shared_ptr<ReplacementData>(new DSBReplData());
}

} // namespace replacement_policy
} // namespace gem5
