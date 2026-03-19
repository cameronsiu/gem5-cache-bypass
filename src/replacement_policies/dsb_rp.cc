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
  if (random_mt.random<unsigned>(1, 32) == 1) {
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


  // competitor tag
  // competitor way
  // on a cache miss, do we bypass?
  // How do we change the gem5 internals to bypass


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

  return victim;
}

std::shared_ptr<ReplacementData>
DSB::instantiateEntry()
{
  return std::shared_ptr<ReplacementData>(new DSBReplData());
}

} // namespace replacement_policy
} // namespace gem5
