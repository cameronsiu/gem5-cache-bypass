#include "dsb_rp.hh"

#include <cassert>
#include <memory>

#include "params/DSBRP.hh"
#include "sim/cur_tick.hh"
#include "base/random.hh"

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
  // Reset last touch timestamp
  std::static_pointer_cast<DSBReplData>(
    replacement_data)->lastTouchTick = Tick(0);

  std::static_pointer_cast<DSBReplData>(
    replacement_data)->referenceBit = 0;
}

void
DSB::touch(const std::shared_ptr<ReplacementData>& replacement_data) const
{
  // Update last touch timestamp
  std::static_pointer_cast<DSBReplData>(
    replacement_data)->lastTouchTick = curTick();
  
  // Update reference
  std::static_pointer_cast<DSBReplData>(
    replacement_data)->referenceBit = 1;
}

void
DSB::reset(const std::shared_ptr<ReplacementData>& replacement_data) const
{
  // Set last touch timestamp
  std::static_pointer_cast<DSBReplData>(
    replacement_data)->lastTouchTick = curTick();
  
  std::static_pointer_cast<DSBReplData>(
    replacement_data)->referenceBit = 0;

  // Random promotion
  if (randomPromotion > 0 && random_mt.random<unsigned>(1, 2^randomPromotion) == 1) {
    std::static_pointer_cast<DSBReplData>(
      replacement_data)->referenceBit = 1;
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
  CompetitorInfo competitorInfo = competitorMap.at(victimSet);

  // How do I get incoming tag?
  // static_cast<TaggedEntry*>(victim)->getTag()
  // Update bypass probabilities
  // TODO: Need to modify gem5 to get more info

  
  // bypass
  if (random_mt.random<unsigned>(1, 2^bypass_counter) == 1) {
    // don't insert somehow
    // get the competitor info for the victim
    // start the bypass
    competitorInfo.competitorValid = true;
    // competitorInfo.competitorTag = inserted line
    competitorInfo.competitorWay = victimWay;
    competitorInfo.isVirtualBypass = false;
  } else {
    // virtual bypass
    if (random_mt.random<unsigned>(1, 2^virtual_bypass_counter) == 1) {
      competitorInfo.competitorValid = true;
      // competitorInfo.competitorTag = inserted line
      competitorInfo.competitorWay = victimWay;
      competitorInfo.isVirtualBypass = true;
    } else {
      // don't bypass nor virtual bypass
      // make sure victim's competitorInfo is set to competitor valid false
      competitorInfo.competitorValid = false;
    }
    
  }

  // How do we change the gem5 internals to bypass

  return victim;
}

std::shared_ptr<ReplacementData>
DSB::instantiateEntry()
{
  return std::shared_ptr<ReplacementData>(new DSBReplData());
}

} // namespace replacement_policy
} // namespace gem5
