# gem5-cache-bypass

CMPT 750 Project -- implementing DSB (Dueling Segmented LRU with adaptive Bypassing) in gem5 v23.0.0.1.

## Prerequisites

- gem5 v23.0.0.1 pre-built at `/opt/gem5`
- SPEC CPU2017 benchmarks installed at `/workspace/spec2017` (see [docs/SPEC_SETUP.md](docs/SPEC_SETUP.md))

## Quick start

```bash
# 1. Build DSB (copies source files + gem5 patches, then rebuilds gem5)
bash scripts/build_dsb.sh

# 2. Sanity test (1000 instructions, ~1 min)
MAXINST=1000 bash scripts/run_all.sh

# 3. Full run (per-benchmark instruction counts, ~1-2 hours)
bash scripts/run_all.sh

# 4. Visualize results
python3 scripts/visualize.py
```

## Building

DSB source lives in `src/replacement_policies/`. The build script copies these
into gem5's source tree along with patches to gem5 internals (for true bypass
support), then runs scons:

```bash
bash scripts/build_dsb.sh
```

**What gets copied:**
- `src/replacement_policies/dsb_rp.{hh,cc}`, `DSBRP.py`, `SConscript` -- DSB implementation
- `src/gem5_patches/*` -- modified gem5 files for bypass support (see [docs/TRUE_BYPASS_MODIFICATIONS.md](docs/TRUE_BYPASS_MODIFICATIONS.md))

The first build takes a while. Incremental rebuilds after editing source files are fast.

## Running benchmarks

`scripts/run_all.sh` runs all replacement policies across all benchmarks.
Policies run sequentially; benchmarks run in parallel (2 at a time by default).

```bash
# Full run with per-benchmark instruction counts
bash scripts/run_all.sh

# Quick sanity test (overrides all benchmarks to 1000 instructions)
MAXINST=1000 bash scripts/run_all.sh

# Run specific policies only
POLICIES_OVERRIDE="dsb lru" bash scripts/run_all.sh
```

### Per-benchmark configuration

| Benchmark | Fast-forward | Detailed insts | Why |
|---|---|---|---|
| mcf | 0 | 200M | Memory-intensive from the start |
| lbm | 300M | 200M | Skip grid initialization |
| deepsjeng | 500M | 100M | Skip board/opening book setup |
| xz | 500M | 100M | Skip file I/O setup |

Fast-forward runs in atomic mode (fast) to skip initialization, then switches
to detailed O3 simulation for the specified number of instructions.

### Replacement policies

| Short name | gem5 class | Description |
|---|---|---|
| `dsb` | DSBRP | Dueling Segmented LRU with Bypass (ours) |
| `lru` | LRURP | Least Recently Used (baseline) |
| `brrip` | BRRIPRP | Bimodal Re-Reference Interval Prediction |
| `random` | RandomRP | Random replacement |
| `fifo` | FIFORP | First-In First-Out |

### How the policy override works

`configs/run_spec.py` wraps gem5's `se.py` and adds a `--rp-type` flag.
It monkey-patches `CacheConfig.config_cache` to set `replacement_policy` on
**L2 only** (the LLC). L1I and L1D stay on default LRU for a fair LLC comparison.

The snoop filter is disabled on both `tol2bus` and `membus` since it is not
needed for single-core SE mode and conflicts with cache bypass.

### Results

Results are organized by policy, then benchmark:

```
results/
  <policy>/
    <benchmark>/
      stats.txt    -- gem5 statistics
      config.ini   -- full simulation config snapshot
      sim.log      -- stdout/stderr from the run
```

Re-running overwrites previous results for that policy/benchmark pair.

### Visualizing

```bash
python3 scripts/visualize.py                        # all policies & benchmarks
python3 scripts/visualize.py --policies dsb lru     # specific policies
python3 scripts/visualize.py --benchmarks lbm mcf   # specific benchmarks
python3 scripts/visualize.py --output custom.png    # custom output path
```

Output: `results/comparison.png`

## Project structure

```
/workspace/
  configs/
    run_spec.py                   -- gem5 config wrapper (adds --rp-type to se.py)
  scripts/
    build_dsb.sh                  -- copy files + gem5 patches + rebuild
    run_all.sh                    -- run all policies across all benchmarks
    visualize.py                  -- generate comparison charts
  src/
    replacement_policies/
      dsb_rp.hh                   -- DSB C++ header
      dsb_rp.cc                   -- DSB C++ implementation
      DSBRP.py                    -- gem5 SimObject wrapper
      SConscript                  -- gem5 build system registration
    gem5_patches/                 -- modified gem5 files for bypass support
  docs/
    SPEC_SETUP.md                 -- SPEC CPU2017 installation guide
    TRUE_BYPASS_MODIFICATIONS.md  -- detailed bypass implementation changes
  results/                        -- simulation output (gitignored)
```

## Iteration workflow

```bash
# 1. Edit DSB source
vim src/replacement_policies/dsb_rp.cc

# 2. Rebuild
bash scripts/build_dsb.sh

# 3. Run
bash scripts/run_all.sh

# 4. Visualize
python3 scripts/visualize.py
```

## Key stats

| Stat | Meaning |
|---|---|
| `system.switch_cpus.ipc` | IPC during detailed simulation (after fast-forward) |
| `system.cpu.ipc` | IPC (benchmarks without fast-forward) |
| `system.l2.demandMissRate::total` | L2 miss rate (lower = better) |
| `system.l2.demandHits::total` | L2 cache hits |
| `system.l2.demandMisses::total` | L2 cache misses |
| `system.l2.replacements` | L2 evictions |
| `system.l2.demandAvgMissLatency::total` | Average L2 miss penalty (ticks) |

Note: after fast-forward, the O3 CPU stats are under `system.switch_cpus`,
not `system.cpu`. Cache stats (`system.l2`, `system.cpu.dcache`) are shared
objects and report correctly under either prefix.
