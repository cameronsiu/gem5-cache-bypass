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
}

void
DSB::touch(const std::shared_ptr<ReplacementData>& replacement_data) const
{
}

void
DSB::reset(const std::shared_ptr<ReplacementData>& replacement_data) const
{
}

ReplaceableEntry*
DSB::getVictim(const ReplacementCandidates& candidates) const
{
}

std::shared_ptr<ReplacementData>
DSB::instantiateEntry()
{
    return std::shared_ptr<ReplacementData>(new DSBReplData());
}

} // namespace replacement_policy
} // namespace gem5
