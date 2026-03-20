#include "dsb_rp.hh"

#include <cassert>
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
  : Base(p)
{
}

void
DSB::invalidate(const std::shared_ptr<ReplacementData>& replacement_data)
{
  auto replData = std::static_pointer_cast<DSBReplData>(replacement_data);

  // Reset last touch timestamp
  replData->lastTouchTick = Tick(0);

  // Reset reference bit to non-reference list
  replData->referenceBit = 0;
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

    CompetitorInfo& competitorInfo = competitorMap.at(set);
    if (competitorInfo.competitorValid) {
      // Bypass was successful
      if (way == competitorInfo.competitorWay) {
        if (!competitorInfo.isVirtualBypass) {
          // way is the victim
          // this means that we should bypass
          bypass_counter -= 1;
        } else {
          // successful virtual bypass
          // inserted line got hit
          // way is the inserted line
          // this means that we shouldn't bypass
          bypass_counter += 1;
        }
        bypass_counter = std::max(0, std::min(bypass_counter, 6));
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
    CompetitorInfo& competitorInfo = competitorMap.at(set);
    Addr tag = static_cast<TaggedEntry*>(entry)->getTag();

    if (competitorInfo.competitorValid) {
      // Bypass was not successful
      if (competitorInfo.startBypass) {
        competitorInfo.competitorTag = tag;
        competitorInfo.startBypass = false;
      } else if (tag == competitorInfo.competitorTag) {
        if (!competitorInfo.isVirtualBypass) {
          // tag is the inserted line
          // we shouldn't bypass
          bypass_counter += 1;
        } else {
          // not successful virtual bypass
          // inserted line got hit
          // way is the inserted line
          // we should bypass
          bypass_counter -= 1;
        }
        bypass_counter = std::max(0, std::min(bypass_counter, 6));
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
  CompetitorInfo& competitorInfo = competitorMap.at(victimSet);

  // bypass
  if (random_mt.random<unsigned>(1, 1u << bypass_counter) == 1) {
    // don't insert somehow
    // get the competitor info for the victim
    // start the bypass
    competitorInfo.competitorValid = true;
    competitorInfo.startBypass = true;
    competitorInfo.competitorWay = victimWay;
    competitorInfo.isVirtualBypass = false;
    // set competitorTag in reset()
  } else {
    // virtual bypass
    if (random_mt.random<unsigned>(1, 1u << virtual_bypass_counter) == 1) {
      competitorInfo.competitorValid = true;
      // competitor tag is the victim now
      competitorInfo.startBypass = false;
      competitorInfo.competitorTag = static_cast<TaggedEntry*>(victim)->getTag();
      competitorInfo.competitorWay = victimWay;
      competitorInfo.isVirtualBypass = true;
    } else {
      // don't bypass nor virtual bypass
      // make sure victim's competitorInfo is set to competitor valid false
      competitorInfo.competitorValid = false;
    }
  }

  // TODO: Change the gem5 internals to bypass

  return victim;
}

std::shared_ptr<ReplacementData>
DSB::instantiateEntry()
{
  return std::shared_ptr<ReplacementData>(new DSBReplData());
}

} // namespace replacement_policy
} // namespace gem5
