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

### 3. Install SPEC CPU2017 benchmarks

Install from option 2: https://polyarch.github.io/cs251a/resources/spec2017-gem5/

1. Mount the `.iso` and run `./install.sh`
2. Copy the installed `spec2017/` directory into the container at `/workspace/spec2017`
3. Create the gem5 build config:

```bash
cd /workspace/spec2017
source shrc
cp config/Example-gcc-linux-x86.cfg config/gem5-x86.cfg
```

4. Edit `config/gem5-x86.cfg` — two required changes:

   **Line ~138** — point `gcc_dir` at the system compiler:
   ```
   %   define  gcc_dir        /usr  # EDIT (see above)
   ```

   **Line ~237** — change the `OPTIMIZE` flags:
   ```
   OPTIMIZE = -g -O3 -march=x86-64 -fno-unsafe-math-optimizations -fno-tree-loop-vectorize -static
   ```

   Why `-static`: gem5's syscall-emulation (SE) mode does not emulate a dynamic
   linker, so all benchmarks must be statically linked or they crash on startup.

   Why `-march=x86-64` (not `-march=native`): the host CPU may support AVX/AVX2
   instructions, but gem5's X86 CPU model does not. Using `-march=native` produces
   AVX instructions (e.g. `VBROADCASTSD`) that cause a gem5 panic at runtime.

### 4. Build and prepare each benchmark

For each benchmark, the workflow is:

```bash
cd /workspace/spec2017 && source shrc

# Generate build/run directories (does not actually compile):
runcpu --fake --config gem5-x86 <benchmark_name>

# Compile:
go <benchmark_name>
cd build/build_base_mytest-m64.0000
specmake

# Copy binary to the run directory:
cp <binary_name> ../../run/run_base_refspeed_mytest-m64.0000/<binary_name>_base.mytest-m64

# See the native run command (for reference):
cd ../../run/run_base_refspeed_mytest-m64.0000
specinvoke -n
```

#### Fix for 619.lbm_s: obstacle file size check

lbm_s validates the obstacle input file size against compiled-in grid dimensions.
Under gem5 SE mode, `stat()` returns an incorrect file size (the simulated
filesystem doesn't match), causing the benchmark to exit before doing any work.

Comment out the size check in `main.c` (lines ~84-91 in the build directory)
and rebuild:

```c
// In benchspec/CPU/619.lbm_s/build/build_base_mytest-m64.0000/main.c
// Comment out the file size validation block (keep the stat() existence check):

        if( stat( param->obstacleFilename, &fileStat ) != 0 ) {
                printf( "MAIN_parseCommandLine: cannot stat obstacle file '%s'\n",
                         param->obstacleFilename );
                exit( 1 );
        }
/*      if( fileStat.st_size != SIZE_X*SIZE_Y*SIZE_Z+(SIZE_Y+1)*SIZE_Z ) {
                printf( "MAIN_parseCommandLine:\n"
                        "\tsize of file '%s' is %i bytes\n"
                                    "\texpected size is %i bytes\n",
                        param->obstacleFilename, (int) fileStat.st_size,
                        SIZE_X*SIZE_Y*SIZE_Z+(SIZE_Y+1)*SIZE_Z );
                exit( 1 );
        }*/
```

Then `specmake clean && specmake` and copy the binary to the run directory again.

---

## Benchmarks

Four benchmarks covering different cache access patterns:

| Benchmark | Type | Category | Why |
|---|---|---|---|
| 619.lbm_s | Lattice Boltzmann fluid sim | Streaming | Large arrays, sequential sweeps — benefits from bypass |
| 605.mcf_s | Vehicle scheduling (min-cost flow) | Pointer-chasing | Random access over large graph — high cache miss rate |
| 631.deepsjeng_s | Chess engine | Integer | Moderate working set, mix of hits and misses |
| 657.xz_s | LZMA compression | Mixed | Combination of sequential and random access patterns |

### Running benchmarks

Use `scripts/run_benchmarks.sh` to run simulations with a given replacement policy.
Results are saved to `/workspace/results/<policy>/<benchmark>/`.

```bash
# Run all 4 benchmarks with LRU (50M instructions each):
bash scripts/run_benchmarks.sh lru

# Run specific benchmarks:
bash scripts/run_benchmarks.sh lru lbm mcf

# Quick sanity test (1000 instructions, a few seconds):
MAXINST=1000 bash scripts/run_benchmarks.sh lru lbm

# Run with a different policy:
bash scripts/run_benchmarks.sh brrip
bash scripts/run_benchmarks.sh dsb          # after building DSB
```

| Short name | gem5 class | Description |
|---|---|---|
| `lru` | LRURP | Least Recently Used (baseline) |
| `brrip` | BRRIPRP | Bimodal Re-Reference Interval Prediction |
| `random` | RandomRP | Random replacement |
| `fifo` | FIFORP | First-In First-Out |
| `dsb` | DSBRP | Dueling Segmented LRU with Bypass (ours) |

Available benchmark names: `lbm`, `mcf`, `deepsjeng`, `xz`

A successful run ends with:
`Exiting @ tick ... because a thread reached the max instruction count`

If you see `panic: Unrecognized/invalid instruction`, the binary was compiled with
`-march=native` instead of `-march=x86-64` — rebuild it (see step 4).

### Where results go

Results are organized by policy, then benchmark:

```
/workspace/results/
├── lru/
│   ├── lbm/
│   │   ├── stats.txt    # all gem5 statistics
│   │   ├── config.ini   # full simulation config snapshot
│   │   └── sim.log      # stdout/stderr from the run
│   ├── mcf/
│   ├── deepsjeng/
│   └── xz/
├── brrip/
│   └── ...
└── dsb/
    └── ...
```

Re-running a benchmark overwrites previous results for that policy/benchmark
pair — copy or rename the directory first if you want to keep old results.

### Comparing results

```bash
# Miss rates for all benchmarks under one policy:
grep "demandMissRate::total" /workspace/results/lru/*/stats.txt

# Compare one benchmark across policies:
grep "system.cpu.dcache.demandMissRate::total" /workspace/results/*/lbm/stats.txt

# Full stats for a single run:
grep -E "demandMissRate|demandHits|demandMisses|replacements|demandAvgMissLatency" \
    /workspace/results/lru/lbm/stats.txt
```

### How the policy override works

`configs/run_spec.py` wraps gem5's `se.py` and adds a `--rp-type` flag.
It monkey-patches `CacheConfig.config_cache` to set `replacement_policy` on
L1D, L1I, and L2 after they are created. The bash script maps short policy
names (e.g. `lru`) to gem5 class names (e.g. `LRURP`) and passes `--rp-type`.

To add a new policy, register its gem5 class in the `POLICIES` array in
`scripts/run_benchmarks.sh`.

---

## Project structure

```
/workspace/
├── configs/
│   ├── run_spec.py                 # gem5 config wrapper (adds --rp-type to se.py)
│   └── run_dsb.py                  # standalone DSB sim config (hello world)
├── scripts/
│   ├── build_dsb.sh                # copy files + rebuild gem5
│   └── run_benchmarks.sh           # run SPEC benchmarks with any RP
├── src/replacement_policies/
│   ├── dsb_rp.hh                   # C++ header
│   ├── dsb_rp.cc                   # C++ source
│   ├── DSBRP.py                    # gem5 SimObject wrapper
│   └── SConscript                  # gem5 build system registration
└── results/
    └── <policy>/
        └── <benchmark>/
            ├── stats.txt           # gem5 statistics output
            ├── config.ini          # full sim config snapshot
            └── sim.log             # stdout/stderr from the run
```

---

## Iteration workflow

Edit source → rebuild → simulate → compare.

```bash
# 1. Edit DSB source
#    src/replacement_policies/dsb_rp.{hh,cc} and/or DSBRP.py

# 2. Rebuild gem5
bash /workspace/scripts/build_dsb.sh

# 3. Run baselines + DSB
bash scripts/run_benchmarks.sh lru
bash scripts/run_benchmarks.sh brrip
bash scripts/run_benchmarks.sh dsb

# 4. Compare DSB against baselines
grep "system.cpu.dcache.demandMissRate::total" /workspace/results/*/lbm/stats.txt
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
