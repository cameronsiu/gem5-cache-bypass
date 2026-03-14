#ifndef __PARAMS__DSBRP__
#define __PARAMS__DSBRP__

namespace gem5 {
namespace replacement_policy {
class DSB;
} // namespace replacement_policy
} // namespace gem5

#include "params/BaseReplacementPolicy.hh"

namespace gem5
{
struct DSBRPParams
    : public BaseReplacementPolicyParams
{
    gem5::replacement_policy::DSB * create() const;
};

} // namespace gem5

#endif // __PARAMS__DSBRP__
