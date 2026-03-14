# gem5-cache-bypass
CMPT 750 Project — implementing DSB (Dueling Segmented LRU with adaptive Bypassing) in gem5.

---

## Setup on a new machine

gem5 is pre-built at `/opt/gem5`. Do these steps once after cloning or rebuilding the container.

### 1. Shell shortcuts

```bash
echo 'export GEM5=/opt/gem5' >> ~/.bashrc
echo "alias gem5='/opt/gem5/build/X86/gem5.opt'" >> ~/.bashrc
source ~/.bashrc
```

### 2. Register DSB in gem5's build system

Copy the workspace files into gem5's source tree (this also handles the SConscript):

```bash
bash /workspace/scripts/build_dsb.sh
```

The script copies `dsb_rp.hh`, `dsb_rp.cc`, `DSBRP.py`, and `SConscript` into
`/opt/gem5/src/mem/cache/replacement_policies/` and runs a full build.

The `SConscript` registers DSB with two entries gem5 needs:
```python
SimObject('DSBRP.py', sim_objects=['DSBRP'])  # exposes DSB to Python configs
Source('dsb_rp.cc')                            # compiles the C++ implementation
```

The first build takes a while. Incremental rebuilds (after editing source files)
are fast — scons only recompiles what changed.

---

## Project structure

```
/workspace/
├── configs/
│   └── run_dsb.py                  # sim config for DSB (fill this in)
├── scripts/
│   ├── build_dsb.sh                # copy files + rebuild gem5
│   └── run_baselines.sh            # run baseline policies, save stats
├── src/replacement_policies/
│   ├── dsb_rp.hh                   # C++ header
│   ├── dsb_rp.cc                   # C++ source
│   ├── DSBRP.py                    # gem5 SimObject wrapper
│   └── SConscript                  # gem5 build system registration
└── results/
    └── <policy>/
        ├── stats.txt               # gem5 statistics output
        ├── config.ini              # full sim config snapshot
        └── sim.log                 # stdout/stderr from the run
```

---

## Iteration workflow

Edit source → rebuild → simulate → read stats.

### Edit and rebuild

```bash
# edit src/replacement_policies/dsb_rp.{hh,cc} and/or DSBRP.py, then:
bash /workspace/scripts/build_dsb.sh
```

### Simulate

```bash
# Run DSB
gem5 --outdir=/workspace/results/dsb /workspace/configs/run_dsb.py

# Run a baseline for comparison
gem5 --outdir=/workspace/results/lru \
    /opt/gem5/configs/learning_gem5/part1/two_level.py
```

### Run all baselines at once

```bash
bash /workspace/scripts/run_baselines.sh
```

### Compare stats across policies

```bash
grep -E "demandMissRate|demandHits|demandMisses|replacements|demandAvgMissLatency" \
    /workspace/results/*/stats.txt
```

---

## Key stats

| Stat | Meaning |
|---|---|
| `demandMissRate::total` | Miss rate (lower = better) |
| `demandHits::total` | Total cache hits |
| `demandMisses::total` | Total cache misses |
| `replacements` | Number of evictions |
| `demandAvgMissLatency::total` | Average miss penalty in ticks |

Stats file: `/workspace/results/<policy>/stats.txt`

---

## gem5 replacement policy interface

Every policy inherits from `Base` and implements 4 methods:

| Method | Called when | Notes |
|---|---|---|
| `invalidate()` | line is invalidated | reset your per-line state |
| `touch()` | cache hit | update reuse predictor |
| `reset()` | new line inserted | bypass decision goes here |
| `getVictim()` | eviction needed | pick which line to evict |

Reference implementation: `/opt/gem5/src/mem/cache/replacement_policies/lru_rp.{hh,cc}`

### LRU reference stats (hello world, two-level cache)

```
system.cpu.dcache.demandMissRate::total       0.064096
system.cpu.dcache.demandHits::total           1942
system.cpu.dcache.demandMisses::total         133
system.cpu.dcache.replacements                0
system.cpu.dcache.demandAvgMissLatency::total 106714
```
