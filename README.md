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

### gem5 commands

All benchmarks use the same gem5 configuration. Run from each benchmark's
`run/run_base_refspeed_mytest-m64.0000/` directory.

**619.lbm_s** (streaming fluid dynamics):
```bash
/opt/gem5/build/X86/gem5.opt \
  /opt/gem5/configs/deprecated/example/se.py \
  --cmd=./lbm_s_base.mytest-m64 \
  --options="2000 reference.dat 0 0 200_200_260_ldc.of" \
  --mem-size=8GB \
  --cpu-type=DerivO3CPU \
  --caches --l2cache \
  --l1d_size=32kB --l1i_size=32kB --l2_size=2MB \
  --maxinst=50000000
```

**605.mcf_s** (pointer-chasing graph optimization):
```bash
/opt/gem5/build/X86/gem5.opt \
  /opt/gem5/configs/deprecated/example/se.py \
  --cmd=./mcf_s_base.mytest-m64 \
  --options="inp.in" \
  --mem-size=8GB \
  --cpu-type=DerivO3CPU \
  --caches --l2cache \
  --l1d_size=32kB --l1i_size=32kB --l2_size=2MB \
  --maxinst=50000000
```

**631.deepsjeng_s** (integer chess engine):
```bash
/opt/gem5/build/X86/gem5.opt \
  /opt/gem5/configs/deprecated/example/se.py \
  --cmd=./deepsjeng_s_base.mytest-m64 \
  --options="ref.txt" \
  --mem-size=8GB \
  --cpu-type=DerivO3CPU \
  --caches --l2cache \
  --l1d_size=32kB --l1i_size=32kB --l2_size=2MB \
  --maxinst=50000000
```

**657.xz_s** (LZMA compression):
```bash
/opt/gem5/build/X86/gem5.opt \
  /opt/gem5/configs/deprecated/example/se.py \
  --cmd=./xz_s_base.mytest-m64 \
  --options="cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4" \
  --mem-size=8GB \
  --cpu-type=DerivO3CPU \
  --caches --l2cache \
  --l1d_size=32kB --l1i_size=32kB --l2_size=2MB \
  --maxinst=50000000
```

### Quick sanity test

Before running a full 50M-instruction simulation, verify the binary works with
a short run (1000 instructions, takes a few seconds):

```bash
# Replace <cmd> and <options> with the benchmark's values from above
/opt/gem5/build/X86/gem5.opt \
  /opt/gem5/configs/deprecated/example/se.py \
  --cmd=./<binary> \
  --options="<args>" \
  --mem-size=8GB \
  --cpu-type=DerivO3CPU \
  --caches --l2cache \
  --l1d_size=32kB --l1i_size=32kB --l2_size=2MB \
  --maxinst=1000
```

You should see `Exiting @ tick ... because a thread reached the max instruction count`.
If you see `panic: Unrecognized/invalid instruction`, the binary was compiled with
`-march=native` instead of `-march=x86-64` — rebuild it.

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
