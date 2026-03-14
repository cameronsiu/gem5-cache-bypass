#!/bin/bash
# run_benchmarks.sh
# Runs gem5 simulations for SPEC CPU2017 benchmarks with a given replacement policy.
#
# Usage:
#   bash scripts/run_benchmarks.sh <policy> [benchmarks...]
#
# Examples:
#   bash scripts/run_benchmarks.sh lru                  # all benchmarks with LRU
#   bash scripts/run_benchmarks.sh lru lbm mcf          # specific benchmarks
#   MAXINST=1000 bash scripts/run_benchmarks.sh lru lbm # quick sanity test
#
# Policies: lru, brrip, random, fifo, dsb (after building)
# Benchmarks: lbm, mcf, deepsjeng, xz
#
# Results go to: /workspace/results/<policy>/<benchmark>/

set -e

GEM5=/opt/gem5/build/X86/gem5.opt
CONFIG=/workspace/configs/run_spec.py
SPEC=/workspace/spec2017/benchspec/CPU
RESULTS=/workspace/results
MAXINST=${MAXINST:-50000000}

# Map short policy names to gem5 class names
declare -A POLICIES
POLICIES=(
    [lru]=LRURP
    [brrip]=BRRIPRP
    [random]=RandomRP
    [fifo]=FIFORP
    [dsb]=DSBRP
)

# Common gem5 flags
GEM5_COMMON=(
    --mem-size=8GB
    --cpu-type=DerivO3CPU
    --caches --l2cache
    --l1d_size=32kB --l1i_size=32kB --l2_size=2MB
    --maxinst="$MAXINST"
)

# Benchmark definitions: spec_dir | binary | options
declare -A BENCHMARKS
BENCHMARKS=(
    [lbm]="619.lbm_s|lbm_s_base.mytest-m64|2000 reference.dat 0 0 200_200_260_ldc.of"
    [mcf]="605.mcf_s|mcf_s_base.mytest-m64|inp.in"
    [deepsjeng]="631.deepsjeng_s|deepsjeng_s_base.mytest-m64|ref.txt"
    [xz]="657.xz_s|xz_s_base.mytest-m64|cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4"
)

# --- Parse arguments ---
if [ $# -lt 1 ]; then
    echo "Usage: bash scripts/run_benchmarks.sh <policy> [benchmarks...]"
    echo ""
    echo "Policies:   ${!POLICIES[*]}"
    echo "Benchmarks: ${!BENCHMARKS[*]}"
    exit 1
fi

POLICY=$1
shift

RP_CLASS=${POLICIES[$POLICY]}
if [ -z "$RP_CLASS" ]; then
    echo "ERROR: unknown policy '$POLICY'"
    echo "       Available: ${!POLICIES[*]}"
    exit 1
fi

if [ $# -gt 0 ]; then
    SELECTED=("$@")
else
    SELECTED=(lbm mcf deepsjeng xz)
fi

# --- Run benchmarks ---
run_bench() {
    local name=$1
    local bench_dir=$2
    local binary=$3
    local options=$4
    local outdir=$RESULTS/$POLICY/$name
    local rundir=$SPEC/$bench_dir/run/run_base_refspeed_mytest-m64.0000

    if [ ! -f "$rundir/$binary" ]; then
        echo "ERROR: binary not found: $rundir/$binary"
        echo "       Build the benchmark first (see README.md step 4)"
        return 1
    fi

    echo "==> [$POLICY/$name] Starting (maxinst=$MAXINST) ..."
    mkdir -p "$outdir"

    (cd "$rundir" && \
        $GEM5 --outdir="$outdir" \
            $CONFIG \
            --rp-type="$RP_CLASS" \
            --cmd="./$binary" \
            --options="$options" \
            "${GEM5_COMMON[@]}" \
    ) 2>&1 | tee "$outdir/sim.log"

    echo "==> [$POLICY/$name] Done. Stats: $outdir/stats.txt"
    echo ""
}

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

echo "========================================="
echo "All done. Results in $RESULTS/$POLICY/"
echo ""
echo "Quick comparison:"
echo "-----------------------------------------"
for name in "${SELECTED[@]}"; do
    stats="$RESULTS/$POLICY/$name/stats.txt"
    if [ -f "$stats" ]; then
        dcache_mr=$(grep "system.cpu.dcache.demandMissRate::total" "$stats" | awk '{print $2}')
        l2_mr=$(grep "system.l2.demandMissRate::total" "$stats" | awk '{print $2}')
        echo "  $name:  L1D miss rate = $dcache_mr   L2 miss rate = $l2_mr"
    fi
done
echo "-----------------------------------------"
