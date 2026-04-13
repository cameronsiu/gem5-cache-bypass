# SPEC CPU2017 Setup

This is the shortest path to get SPEC ready for the scripts in this repo.

## Install location

Put SPEC CPU2017 at:

```text
/workspace/spec2017
```

## Create the gem5 config

```bash
cd /workspace/spec2017
source shrc
cp config/Example-gcc-linux-x86.cfg config/gem5-x86.cfg
```

Edit `config/gem5-x86.cfg`:

1. Set:

```text
%   define  gcc_dir        /usr
```

2. Set:

```text
OPTIMIZE = -g -O3 -march=x86-64 -fno-unsafe-math-optimizations -fno-tree-loop-vectorize -static
```

Use `-static` because gem5 SE mode needs static binaries.

Use `-march=x86-64` instead of `-march=native` so gem5 does not hit unsupported host-only instructions.

## Build a benchmark

For each benchmark:

```bash
cd /workspace/spec2017
source shrc

runcpu --fake --config gem5-x86 <benchmark_name>
go <benchmark_name>
cd benchspec/CPU/<benchmark_name>/build/build_base_gem5-x86.0000
specmake
```

Copy the built binary into the run directory:

```bash
cp <binary_name> ../../run/run_base_refspeed_gem5-x86.0000/<binary_name>_base.gem5-x86
```

If you want to inspect the native SPEC command:

```bash
cd ../../run/run_base_refspeed_gem5-x86.0000
specinvoke -n
```

## Benchmarks used by the L3 scripts

- `603.bwaves_s`
- `605.mcf_s`
- `619.lbm_s`
- `620.omnetpp_s`
- `621.wrf_s`
- `623.xalancbmk_s`
- `625.x264_s`
- `627.cam4_s`
- `628.pop2_s`
- `631.deepsjeng_s`
- `638.imagick_s`
- `641.leela_s`
- `644.nab_s`
- `648.exchange2_s`
- `649.fotonik3d_s`
- `654.roms_s`
- `657.xz_s`
- `600.perlbench_s`
- `602.gcc_s`

## One known fix

`619.lbm_s` may fail because of the obstacle file size check under gem5 SE mode.

If that happens, comment out the file-size validation block in:

```text
benchspec/CPU/619.lbm_s/build/build_base_gem5-x86.0000/main.c
```

Then rebuild that benchmark:

```bash
specmake clean
specmake
```

Copy the rebuilt binary into the run directory again.

## After SPEC is ready

Go back to the repo root and run:

```bash
cd /workspace
bash scripts/build_dsb.sh
bash scripts/create_checkpoints.sh
POLICIES_OVERRIDE="lru brrip random tree_plru ship_mem" bash scripts/run_all_l3.sh
POLICIES_OVERRIDE="dsb_policy0 dsb_policy1" bash scripts/run_all_l3.sh
```
