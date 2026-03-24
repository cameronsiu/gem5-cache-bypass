from m5.objects.ReplacementPolicies import BaseReplacementPolicy
from m5.params import *

class DSBRP(BaseReplacementPolicy):
    # The name gem5 uses internally and in config.ini
    type = "DSBRP"
    # Must match the C++ class name in dsb_rp.hh + dsb_rp.cc
    cxx_class = "gem5::replacement_policy::DSB"
    # The header gem5 uses to generate params/DSBRP.hh
    cxx_header = "mem/cache/replacement_policies/dsb_rp.hh"

    # Initial bypass aggressiveness: probability = 1 / 2^bypass_counter
    bypass_counter = Param.Int(6, "Initial bypass counter (log2 of denominator)")
    # Virtual bypass sampling rate: probability = 1 / 2^virtual_bypass_counter
    virtual_bypass_counter = Param.Int(4, "Virtual bypass counter (log2)")
    # Random promotion chance on insert: probability = 1 / 2^random_promotion
    # 0 means disabled (new lines always start unreferenced)
    random_promotion = Param.Int(0, "Random promotion to referenced on insert (log2)")