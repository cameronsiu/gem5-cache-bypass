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

  // Random promotion
  if (random_mt.random<unsigned>(1, 32) == 1) {
    std::static_pointer_cast<DSBReplData>(
      replacement_data)->referenceBit = 1;
  }

  // Aging
  // loop through each cache line
  // and set referenceBit to 0 for worst lastTouchTick
  /*
  
  ReplaceableEntry* referenceLine = referenceList[0];
  for (const auto& rL : referenceList) {
    if (std::static_pointer_cast<LRUReplData>(
        rL->replacementData)->lastTouchTick <
        std::static_pointer_cast<LRUReplData>(
          victim->replacementData)->lastTouchTick) {
      referenceLine = rL;
    }
  }
  std::static_pointer_cast<DSBReplData>(
      replacement_data)->referenceBit = 0;
  
  */
}

ReplaceableEntry*
DSB::getVictim(const ReplacementCandidates& candidates) const
{
  // There must be at least one replacement candidate
  assert(candidates.size() > 0);

  // 


  // competitor tag
  // competitor way
  // on a cache miss, do we bypass?
  // How do we change the gem5 internals to bypass

  // Visit all candidates to find victim
  ReplaceableEntry* victim = candidates[0];
  for (const auto& candidate : candidates) {
    // Update victim entry if necessary
    if (std::static_pointer_cast<DSBReplData>(
      candidate->replacementData)->lastTouchTick <
      std::static_pointer_cast<DSBReplData>(
        victim->replacementData)->lastTouchTick) {
      victim = candidate;
    }
  }

  return victim;
}

std::shared_ptr<ReplacementData>
DSB::instantiateEntry()
{
  return std::shared_ptr<ReplacementData>(new DSBReplData());
}

} // namespace replacement_policy
} // namespace gem5
