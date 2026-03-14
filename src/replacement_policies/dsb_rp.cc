#include "bypass_rp.hh"

#include <cassert>
#include <memory>

#include "DSBRP.hh"
#include "sim/cur_tick.hh"

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
}

void
DSB::touch(const std::shared_ptr<ReplacementData>& replacement_data) const
{
  // Update last touch timestamp
  std::static_pointer_cast<DSBReplData>(
    replacement_data)->lastTouchTick = curTick();
}

void
DSB::reset(const std::shared_ptr<ReplacementData>& replacement_data) const
{
  // Set last touch timestamp
  std::static_pointer_cast<DSBReplData>(
    replacement_data)->lastTouchTick = curTick();
}

ReplaceableEntry*
DSB::getVictim(const ReplacementCandidates& candidates) const
{
  // There must be at least one replacement candidate
  assert(candidates.size() > 0);

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
