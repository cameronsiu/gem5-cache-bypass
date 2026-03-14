# gem5-cache-bypass
CMPT 750 Project — implementing a cache bypass replacement policy in gem5.

---

## Environment

gem5 is pre-built and lives at `/opt/gem5`. The workspace (`/workspace`) holds
all project source, configs, scripts, and results.

### One-time shell setup

Add gem5 shortcuts to your shell (already done on the dev container, but redo
this if you switch machines or rebuild the container):

```bash
echo 'export GEM5=/opt/gem5' >> ~/.bashrc
echo "alias gem5='/opt/gem5/build/X86/gem5.opt'" >> ~/.bashrc
source ~/.bashrc
```

After this you can run `gem5` from anywhere instead of using the full path.

---

## Project structure

```
/workspace/
├── configs/
│   └── run_dsb.py             # sim config for DSBRP (fill this in)
├── scripts/
│   └── run_baselines.sh       # runs baseline policies, saves stats to results/
├── src/replacement_policies/
│   ├── dsb_rp.hh              # C++ header  (your implementation)
│   ├── dsb_rp.cc              # C++ source  (your implementation)
│   └── DSBRP.py               # gem5 SimObject wrapper (your implementation)
└── results/
    └── <policy>/
        ├── stats.txt           # gem5 statistics output
        ├── config.ini          # full sim config snapshot
        └── sim.log             # stdout/stderr from the run
```

---

## Iteration workflow

Every implementation cycle:

```
1. Edit src/replacement_policies/bypass_rp.{hh,cc} and BypassRP.py
2. Copy files into gem5 source tree and rebuild
3. Run simulation from /workspace
4. Read stats from /workspace/results/
```

### 1. Copy your files into gem5 and rebuild

```bash
cp /workspace/src/replacement_policies/dsb_rp.hh  /opt/gem5/src/mem/cache/replacement_policies/
cp /workspace/src/replacement_policies/dsb_rp.cc   /opt/gem5/src/mem/cache/replacement_policies/
cp /workspace/src/replacement_policies/DSBRP.py    /opt/gem5/src/mem/cache/replacement_policies/

# Register in SConscript and ReplacementPolicies.py (one-time, see Milestone 1 notes below)

cd /opt/gem5
scons build/X86/gem5.opt -j$(nproc)
```

### 2. Run a simulation from /workspace

```bash
# Run with your DSB policy, output to /workspace/results/dsb/
gem5 --outdir=/workspace/results/dsb /workspace/configs/run_dsb.py

# Or run a baseline for comparison
gem5 --outdir=/workspace/results/lru \
    /opt/gem5/configs/learning_gem5/part1/two_level.py
```

### 3. Run all baselines at once

```bash
bash /workspace/scripts/run_baselines.sh
```

Results land in `/workspace/results/<policy>/stats.txt`.

### 4. Compare stats across policies

```bash
grep -E "demandMissRate|demandHits|demandMisses|replacements|demandAvgMissLatency" \
    /workspace/results/*/stats.txt
```

---

## Key stats to track

| Stat | Meaning |
|---|---|
| `demandMissRate::total` | Miss rate (lower = better cache use) |
| `demandHits::total` | Total cache hits |
| `demandMisses::total` | Total cache misses |
| `replacements` | Number of evictions |
| `demandAvgMissLatency::total` | Average miss penalty in ticks |

Stats file location after a run: `/workspace/results/<policy>/stats.txt`

---

## Milestone 1 Notes

### How gem5 replacement policies work

Every replacement policy inherits from `Base` and implements 4 methods:

| Method | Called when | Notes |
|---|---|---|
| `invalidate()` | line is invalidated | reset your state |
| `touch()` | cache hit | update reuse predictor |
| `reset()` | **new line inserted** | bypass decision goes here |
| `getVictim()` | eviction needed | pick who to evict |

### LRU (baseline reference)

- Tracks `lastTouchTick` per cache line
- `touch()` / `reset()` set `lastTouchTick = curTick()`
- `getVictim()` evicts the candidate with the smallest `lastTouchTick`
- Source: `/opt/gem5/src/mem/cache/replacement_policies/lru_rp.{hh,cc}`

### Registering a new policy (one-time steps)

1. Add to `/opt/gem5/src/mem/cache/replacement_policies/SConscript`:
   ```python
   Source('dsb_rp.cc')
   ```
   And add `'DSBRP'` to the `SimObject(...)` list.

2. Add `DSBRP` class to `ReplacementPolicies.py` (or keep it in the
   separate `DSBRP.py` and import it).

3. Rebuild: `cd /opt/gem5 && scons build/X86/gem5.opt -j$(nproc)`

### Hello world baseline stats (LRU, two-level cache)

```
system.cpu.dcache.demandMissRate::total       0.064096   # miss rate
system.cpu.dcache.demandHits::total           1942        # hits
system.cpu.dcache.demandMisses::total         133         # misses
system.cpu.dcache.replacements                0           # evictions
system.cpu.dcache.demandAvgMissLatency::total 106714      # avg miss latency (ticks)
```
