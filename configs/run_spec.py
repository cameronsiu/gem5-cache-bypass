"""
Wrapper around gem5's se.py that adds --rp-type for replacement policy selection.

Usage:
    gem5.opt configs/run_spec.py --rp-type=LRURP [all normal se.py flags]

Supported policies (run with --list-rp-types to see all):
    LRURP, BRRIPRP, RandomRP, FIFORP, DSBRP (after building), etc.

If --rp-type is omitted, defaults to LRURP.
"""
import os
import sys

# --- Extract our custom flags before se.py sees them ---
rp_type = "LRURP"
dsb_params = {}
new_argv = []
for arg in sys.argv:
    if arg.startswith("--rp-type="):
        rp_type = arg.split("=", 1)[1]
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

# --- Patch CacheConfig to inject the chosen replacement policy ---
# We pre-add the configs/ dir so "from common import ..." works before exec
configs_dir = os.path.join(se_dir, "..", "..")
sys.path.insert(0, os.path.realpath(configs_dir))

from common import CacheConfig, ObjectList

_orig_config_cache = CacheConfig.config_cache

def _config_cache_with_rp(options, system):
    """Call the original config_cache, then override replacement policies."""
    _orig_config_cache(options, system)
    rp_class = ObjectList.rp_list.get(rp_type)
    print(f"Replacement policy: {rp_type}")
    # Only apply the replacement policy to L2 (the LLC).
    # L1I and L1D stay on default LRU for a fair LLC comparison.
    if hasattr(system, 'l2'):
        system.l2.replacement_policy = rp_class(**dsb_params)
    # Disable snoop filters. Not needed for single-core SE mode, and they
    # panic when combined with cache bypass (shouldBypass skips insertion
    # but the snoop filter still tracks the line as present).
    from m5.params import NULL
    if hasattr(system, 'tol2bus'):
        system.tol2bus.snoop_filter = NULL
    if hasattr(system, 'membus'):
        system.membus.snoop_filter = NULL

CacheConfig.config_cache = _config_cache_with_rp

# --- Execute se.py in this namespace ---
# compile() with se_py path so addToPath("../../") resolves relative to se.py
sys.path[0] = se_dir
exec(compile(open(se_py).read(), se_py, 'exec'))
