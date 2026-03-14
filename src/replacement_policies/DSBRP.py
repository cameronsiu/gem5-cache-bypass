from m5.objects.ReplacementPolicies import BaseReplacementPolicy
from m5.params import *

class DSBRP(BaseReplacementPolicy):
    # The name gem5 uses internally and in config.ini
    type = "DSBRP"
    # Must match the C++ class name in dsb_rp.hh + dsb_rp.cc
    cxx_class = "gem5::replacement_policy::DSB"
    # The header gem5 uses to generate params/DSBRP.hh
    cxx_header = "mem/cache/replacement_policies/dsb_rp.hh"