# SPEC CPU2017 Setup for gem5

Instructions for installing and building SPEC CPU2017 benchmarks for use with gem5 SE mode.

## 1. Install SPEC CPU2017

Install from option 2: https://polyarch.github.io/cs251a/resources/spec2017-gem5/

1. Mount the `.iso` and run `./install.sh`
2. Copy the installed `spec2017/` directory into the container at `/workspace/spec2017`
3. Create the gem5 build config:

```bash
cd /workspace/spec2017
source shrc
cp config/Example-gcc-linux-x86.cfg config/gem5-x86.cfg
```

4. Edit `config/gem5-x86.cfg` -- two required changes:

   **Line ~138** -- point `gcc_dir` at the system compiler:
   ```
   %   define  gcc_dir        /usr  # EDIT (see above)
   ```

   **Line ~237** -- change the `OPTIMIZE` flags:
   ```
   OPTIMIZE = -g -O3 -march=x86-64 -fno-unsafe-math-optimizations -fno-tree-loop-vectorize -static
   ```

   Why `-static`: gem5's syscall-emulation (SE) mode does not emulate a dynamic
   linker, so all benchmarks must be statically linked or they crash on startup.

   Why `-march=x86-64` (not `-march=native`): the host CPU may support AVX/AVX2
   instructions, but gem5's X86 CPU model does not. Using `-march=native` produces
   AVX instructions (e.g. `VBROADCASTSD`) that cause a gem5 panic at runtime.

## 2. Build each benchmark

For each benchmark, the workflow is:

```bash
cd /workspace/spec2017 && source shrc

# Generate build/run directories (does not actually compile):
runcpu --fake --config gem5-x86 <benchmark_name>

# Compile:
go <benchmark_name>
cd build/build_base_gem5-x86.0000
specmake

# Copy binary to the run directory:
cp <binary_name> ../../run/run_base_refspeed_gem5-x86.0000/<binary_name>_base.gem5-x86

# See the native run command (for reference):
cd ../../run/run_base_refspeed_gem5-x86.0000
specinvoke -n
```

### Fix for 619.lbm_s: obstacle file size check

lbm_s validates the obstacle input file size against compiled-in grid dimensions.
Under gem5 SE mode, `stat()` returns an incorrect file size (the simulated
filesystem doesn't match), causing the benchmark to exit before doing any work.

Comment out the size check in `main.c` (lines ~84-91 in the build directory)
and rebuild:

```c
// In benchspec/CPU/619.lbm_s/build/build_base_gem5-x86.0000/main.c
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

## Benchmarks used

| Benchmark | Type | Category | Why |
|---|---|---|---|
| 619.lbm_s | Lattice Boltzmann fluid sim | Streaming | Large arrays, sequential sweeps -- benefits from bypass |
| 605.mcf_s | Vehicle scheduling (min-cost flow) | Pointer-chasing | Random access over large graph -- high cache miss rate |
| 631.deepsjeng_s | Chess engine | Integer | Moderate working set, mix of hits and misses |
| 657.xz_s | LZMA compression | Mixed | Combination of sequential and random access patterns |

## Troubleshooting

If you see `panic: Unrecognized/invalid instruction`, the binary was compiled with
`-march=native` instead of `-march=x86-64` -- rebuild it (see step 2).
