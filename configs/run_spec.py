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

# --- Extract --rp-type before se.py sees it ---
rp_type = "LRURP"
new_argv = []
for arg in sys.argv:
    if arg.startswith("--rp-type="):
        rp_type = arg.split("=", 1)[1]
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
    if hasattr(system, 'l2'):
        system.l2.replacement_policy = rp_class()
    for cpu in system.cpu:
        if hasattr(cpu, 'icache'):
            cpu.icache.replacement_policy = rp_class()
        if hasattr(cpu, 'dcache'):
            cpu.dcache.replacement_policy = rp_class()

CacheConfig.config_cache = _config_cache_with_rp

# --- Execute se.py in this namespace ---
# compile() with se_py path so addToPath("../../") resolves relative to se.py
sys.path[0] = se_dir
exec(compile(open(se_py).read(), se_py, 'exec'))
