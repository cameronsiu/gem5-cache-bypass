#!/bin/bash
# run_all.sh
# Runs all replacement policies across all benchmarks.
# Policies run sequentially; benchmarks run in parallel within each policy.
#
# Usage:
#   bash scripts/run_all.sh                 # uses per-benchmark instruction counts
#   MAXINST=1000 bash scripts/run_all.sh    # override all benchmarks (quick sanity test)
#
# Results go to: /workspace/results/<policy>/<benchmark>/

set -e

GEM5=/opt/gem5/build/X86/gem5.opt
CONFIG=/workspace/configs/run_spec.py
SPEC=/workspace/spec2017/benchspec/CPU
RESULTS=/workspace/results
MAXINST=${MAXINST:-0}

POLICY_ORDER=(${POLICIES_OVERRIDE:-lru brrip random fifo dsb})

declare -A POLICY_MAP
POLICY_MAP=(
    [lru]=LRURP
    [brrip]=BRRIPRP
    [random]=RandomRP
    [fifo]=FIFORP
    [dsb]=DSBRP
)

GEM5_COMMON=(
    --cpu-type=DerivO3CPU
    --caches --l2cache
    --l1d_size=32kB --l1i_size=32kB --l2_size=2MB
)

# Benchmark definitions: spec_dir | binary | options | mem_size | fast_forward | maxinst
# fast_forward skips init (memset/buffer alloc) in atomic mode before detailed O3
# maxinst is per-benchmark; overridden by MAXINST env var if set (non-zero)
declare -A BENCHMARKS
BENCHMARKS=(
    [mcf]="605.mcf_s|mcf_s_base.mytest-m64|inp.in|8GB|0|200000000"
    [deepsjeng]="631.deepsjeng_s|deepsjeng_s_base.mytest-m64|ref.txt|8GB|500000000|100000000"
    [lbm]="619.lbm_s|lbm_s_base.mytest-m64|2000 reference.dat 0 0 200_200_260_ldc.of|8GB|300000000|200000000"
    [xz]="657.xz_s|xz_s_base.mytest-m64|cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4|16GB|500000000|100000000"
)

BENCH_ORDER=(mcf deepsjeng lbm xz)
MAX_PARALLEL=${MAX_PARALLEL:-2}

run_bench() {
    local policy=$1
    local rp_class=$2
    local name=$3

    local entry=${BENCHMARKS[$name]}
    IFS='|' read -r bench_dir binary options mem_size fast_forward bench_maxinst <<< "$entry"

    # MAXINST env var overrides per-benchmark value if set (non-zero)
    local inst=${MAXINST:-0}
    if [ "$inst" -eq 0 ] 2>/dev/null; then
        inst=$bench_maxinst
    fi

    local outdir=$RESULTS/$policy/$name
    local rundir=$SPEC/$bench_dir/run/run_base_refspeed_mytest-m64.0000

    if [ ! -f "$rundir/$binary" ]; then
        echo "ERROR: binary not found: $rundir/$binary"
        return 1
    fi

    mkdir -p "$outdir"

    local ff_flags=()
    if [ "$fast_forward" -gt 0 ] 2>/dev/null; then
        ff_flags=(--fast-forward="$fast_forward")
    fi

    echo "==> [$policy/$name] Starting (maxinst=$inst, mem=$mem_size, ff=$fast_forward) ..."

    (cd "$rundir" && \
        $GEM5 --outdir="$outdir" \
            $CONFIG \
            --rp-type="$rp_class" \
            --cmd="./$binary" \
            --options="$options" \
            --mem-size="$mem_size" \
            --maxinst="$inst" \
            "${GEM5_COMMON[@]}" \
            "${ff_flags[@]}" \
    ) > "$outdir/sim.log" 2>&1

    echo "==> [$policy/$name] Done."
}

# --- Main loop: policies sequential, benchmarks parallel ---
for policy in "${POLICY_ORDER[@]}"; do
    rp_class=${POLICY_MAP[$policy]}
    echo ""
    echo "========================================="
    echo " Policy: $policy ($rp_class)"
    echo "========================================="

    pids=()
    bench_names=()
    failed=()

    for name in "${BENCH_ORDER[@]}"; do
        run_bench "$policy" "$rp_class" "$name" &
        pids+=($!)
        bench_names+=("$name")

        # Limit parallelism: when we hit MAX_PARALLEL, wait for current batch
        if [ ${#pids[@]} -ge "$MAX_PARALLEL" ]; then
            for i in "${!pids[@]}"; do
                if ! wait "${pids[$i]}"; then
                    failed+=("${bench_names[$i]}")
                fi
            done
            pids=()
            bench_names=()
        fi
    done

    # Wait for any remaining benchmarks
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            failed+=("${bench_names[$i]}")
        fi
    done

    if [ ${#failed[@]} -gt 0 ]; then
        echo "WARNING: Failed benchmarks for $policy: ${failed[*]}"
    fi

    # Print quick stats for this policy
    echo ""
    echo "--- $policy results ---"
    for name in "${BENCH_ORDER[@]}"; do
        stats="$RESULTS/$policy/$name/stats.txt"
        if [ -f "$stats" ]; then
            dcache_mr=$(grep "system.cpu.dcache.demandMissRate::total" "$stats" | awk '{print $2}')
            l2_mr=$(grep "system.l2.demandMissRate::total" "$stats" | awk '{print $2}')
            echo "  $name:  L1D miss rate = $dcache_mr   L2 miss rate = $l2_mr"
        else
            echo "  $name:  (no stats)"
        fi
    done
done

echo ""
echo "========================================="
echo " All policies complete."
echo " Results in: $RESULTS/"
echo "========================================="
