#!/bin/bash
# run_benchmarks.sh
# Runs gem5 simulations for SPEC CPU2017 benchmarks using se.py.
#
# Usage:
#   bash scripts/run_benchmarks.sh              # run all benchmarks
#   bash scripts/run_benchmarks.sh lbm mcf      # run specific benchmarks
#
# Results go to: /workspace/results/<benchmark>/
#   stats.txt   — gem5 statistics
#   config.ini  — full simulation config snapshot
#   sim.log     — stdout/stderr from the run

set -e

GEM5=/opt/gem5/build/X86/gem5.opt
SE_PY=/opt/gem5/configs/deprecated/example/se.py
SPEC=/workspace/spec2017/benchspec/CPU
RESULTS=/workspace/results
MAXINST=${MAXINST:-50000000}

# Common gem5 flags
GEM5_COMMON=(
    --mem-size=8GB
    --cpu-type=DerivO3CPU
    --caches --l2cache
    --l1d_size=32kB --l1i_size=32kB --l2_size=2MB
    --maxinst="$MAXINST"
)

run_bench() {
    local name=$1
    local bench_dir=$2
    local binary=$3
    local options=$4
    local outdir=$RESULTS/$name

    local rundir=$SPEC/$bench_dir/run/run_base_refspeed_mytest-m64.0000

    if [ ! -f "$rundir/$binary" ]; then
        echo "ERROR: binary not found: $rundir/$binary"
        echo "       Build the benchmark first (see README.md step 4)"
        return 1
    fi

    echo "==> [$name] Starting (maxinst=$MAXINST) ..."
    mkdir -p "$outdir"

    (cd "$rundir" && \
        $GEM5 --outdir="$outdir" \
            $SE_PY \
            --cmd="./$binary" \
            --options="$options" \
            "${GEM5_COMMON[@]}" \
    ) 2>&1 | tee "$outdir/sim.log"

    echo "==> [$name] Done. Stats: $outdir/stats.txt"
    echo ""
}

# Benchmark definitions: name, spec_dir, binary, options
declare -A BENCHMARKS
BENCHMARKS=(
    [lbm]="619.lbm_s|lbm_s_base.mytest-m64|2000 reference.dat 0 0 200_200_260_ldc.of"
    [mcf]="605.mcf_s|mcf_s_base.mytest-m64|inp.in"
    [deepsjeng]="631.deepsjeng_s|deepsjeng_s_base.mytest-m64|ref.txt"
    [xz]="657.xz_s|xz_s_base.mytest-m64|cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4"
)

# Decide which benchmarks to run
if [ $# -gt 0 ]; then
    SELECTED=("$@")
else
    SELECTED=(lbm mcf deepsjeng xz)
fi

for name in "${SELECTED[@]}"; do
    entry=${BENCHMARKS[$name]}
    if [ -z "$entry" ]; then
        echo "ERROR: unknown benchmark '$name'"
        echo "       Available: ${!BENCHMARKS[*]}"
        exit 1
    fi

    IFS='|' read -r bench_dir binary options <<< "$entry"
    run_bench "$name" "$bench_dir" "$binary" "$options"
done

echo "All done. Results in $RESULTS/"
echo ""
echo "Quick comparison:"
grep -E "demandMissRate::total|demandAvgMissLatency::total" \
    $RESULTS/*/stats.txt 2>/dev/null | grep "system.cpu.dcache\|system.l2" || true
