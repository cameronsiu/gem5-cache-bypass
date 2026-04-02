"""
Wrapper around gem5's se.py that adds a fixed 3-level cache hierarchy and
--rp-type for replacement policy selection.

Hierarchy:
    L1I: 32kB, 8-way
    L1D: 32kB, 8-way
    L2 : 256kB, 8-way
    L3 : configurable (default 2MB), 8-way

Usage:
    gem5.opt configs/run_spec_l3.py --rp-type=LRURP --l3-size=1MB [se.py flags]

If --rp-type is omitted, defaults to LRURP and is applied to L3 only.
"""
import os
import sys

import m5
from m5.params import NULL
from m5.objects import Cache, L2XBar

# --- Extract our custom flags before se.py sees them ---
rp_type = "LRURP"
l3_size = "2MB"
l3_assoc = 16
dsb_params = {}
new_argv = []
for arg in sys.argv:
    if arg.startswith("--rp-type="):
        rp_type = arg.split("=", 1)[1]
    elif arg.startswith("--l3-size="):
        l3_size = arg.split("=", 1)[1]
    elif arg.startswith("--l3-assoc="):
        l3_assoc = int(arg.split("=", 1)[1])
    elif arg.startswith("--dsb-bypass-counter="):
        dsb_params["bypass_counter"] = int(arg.split("=", 1)[1])
    elif arg.startswith("--dsb-virtual-bypass-counter="):
        dsb_params["virtual_bypass_counter"] = int(arg.split("=", 1)[1])
    elif arg.startswith("--dsb-random-promotion="):
        dsb_params["random_promotion"] = int(arg.split("=", 1)[1])
    else:
        new_argv.append(arg)
sys.argv = new_argv

# --- Setup paths so se.py's relative imports resolve correctly ---
se_py = "/opt/gem5/configs/deprecated/example/se.py"
se_dir = os.path.dirname(se_py)
sys.path.insert(0, se_dir)

# We pre-add the configs/ dir so "from common import ..." works before exec
configs_dir = os.path.join(se_dir, "..", "..")
sys.path.insert(0, os.path.realpath(configs_dir))

from common import CacheConfig, ObjectList


class L3Cache(Cache):
    assoc = 16
    tag_latency = 30
    data_latency = 30
    response_latency = 30
    mshrs = 32
    tgts_per_mshr = 16
    write_buffers = 16


_orig_config_cache = CacheConfig.config_cache


def _config_cache_with_l3(options, system):
    """Build the normal cache hierarchy, then insert an L3 between L2 and DRAM."""
    options.l1i_size = "32kB"
    options.l1d_size = "32kB"
    options.l1i_assoc = 8
    options.l1d_assoc = 8
    options.l2_size = "256kB"
    options.l2_assoc = 8

    _orig_config_cache(options, system)

    rp_class = ObjectList.rp_list.get(rp_type)
    print(f"Replacement policy: {rp_type}")
    print("L1I size: 32kB, assoc: 8")
    print("L1D size: 32kB, assoc: 8")
    print("L2 size: 256kB, assoc: 8")
    print(f"L3 size: {l3_size}, L3 assoc: {l3_assoc}")

    if not hasattr(system, "l2"):
        raise RuntimeError("run_spec_l3.py requires --l2cache so an L3 can be inserted")

    # Insert an additional shared cache level between the existing L2 and membus.
    old_mem_side = system.l2.mem_side
    system.toL3bus = L2XBar(clk_domain=system.cpu_clk_domain)
    system.l3 = L3Cache(
        clk_domain=system.cpu_clk_domain,
        size=l3_size,
        assoc=l3_assoc,
        replacement_policy=rp_class(**dsb_params),
    )

    system.l2.mem_side = system.toL3bus.cpu_side_ports
    system.l3.cpu_side = system.toL3bus.mem_side_ports
    system.l3.mem_side = old_mem_side

    # Disable snoop filters. Not needed for single-core SE mode, and they can
    # conflict with bypass-style replacement policies.
    if hasattr(system, "tol2bus"):
        system.tol2bus.snoop_filter = NULL
    if hasattr(system, "toL3bus"):
        system.toL3bus.snoop_filter = NULL
    if hasattr(system, "membus"):
        system.membus.snoop_filter = NULL


CacheConfig.config_cache = _config_cache_with_l3

# --- Execute se.py in this namespace ---
sys.path[0] = se_dir
exec(compile(open(se_py).read(), se_py, "exec"))
