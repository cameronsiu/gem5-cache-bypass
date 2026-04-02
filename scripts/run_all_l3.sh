#!/bin/bash
# run_all_l3.sh
# Runs all replacement policies across all SPEC CPU2017 speed benchmarks
# using the L3-enabled config.
#
# Fixed hierarchy:
#   L1I = 32kB, 8-way
#   L1D = 32kB, 8-way
#   L2  = 256kB, 8-way
#   L3  = configurable, default 2MB, 16-way
#
# Results go to: /workspace/results_l3/<L3_SIZE>/<policy>/<benchmark>/

set +e  # Don't exit on individual benchmark failures

GEM5=/opt/gem5/build/X86/gem5.opt
CONFIG=/workspace/configs/run_spec_l3.py
SPEC=/workspace/spec2017/benchspec/CPU
RESULTS=${RESULTS:-/workspace/results_l3}
MAXINST=${MAXINST:-0}
L3_SIZE=${L3_SIZE:-2MB}
L3_ASSOC=${L3_ASSOC:-16}
WARMUP=${WARMUP:-50000000}
CKPT_BASE=${CKPT_BASE:-/workspace/checkpoints}

POLICY_ORDER=(${POLICIES_OVERRIDE:-dsb lru brrip random fifo tree_plru dsb-bc0 dsb-bc2 dsb-bc4})

declare -A POLICY_MAP
POLICY_MAP=(
    [lru]=LRURP
    [brrip]=BRRIPRP
    [random]=RandomRP
    [fifo]=FIFORP
    [tree_plru]=TreePLRURP
    [dsb]=DSBRP
)

get_rp_class() {
    local policy=$1
    local base=${policy%%-*}
    if [ -n "${POLICY_MAP[$policy]+x}" ]; then
        echo "${POLICY_MAP[$policy]}"
    elif [ -n "${POLICY_MAP[$base]+x}" ]; then
        echo "${POLICY_MAP[$base]}"
    else
        echo "LRURP"
    fi
}

get_dsb_flags() {
    local policy=$1
    local base=${policy%%-*}
    local suffix=${policy#*-}

    if [ "$base" = "$policy" ]; then
        echo ""
        return
    fi

    case "$suffix" in
        bc[0-9]*)
            local val=${suffix#bc}
            echo "--dsb-bypass-counter=$val"
            ;;
        *)
            echo ""
            ;;
    esac
}

GEM5_COMMON=(
    --cpu-type=DerivO3CPU
    --caches --l2cache
    --l1d_size=32kB --l1i_size=32kB --l1d-assoc=8 --l1i-assoc=8 --l2_size=256kB --l2-assoc=8
)

declare -A BENCHMARKS
BENCHMARKS=(
    [mcf]="605.mcf_s|mcf_s_base.mytest-m64|inp.in|8GB|200000000|250000000"
    [deepsjeng]="631.deepsjeng_s|deepsjeng_s_base.mytest-m64|ref.txt|8GB|500000000|250000000"
    [xz]="657.xz_s|xz_s_base.mytest-m64|cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4|16GB|500000000|250000000"
    [perlbench]="600.perlbench_s|perlbench_s_base.mytest-m64|-I./lib checkspam.pl 2500 5 25 11 150 1 1 1 1|8GB|200000000|250000000"
    [omnetpp]="620.omnetpp_s|omnetpp_s_base.mytest-m64|-c General -r 0|8GB|200000000|250000000"
    [xalancbmk]="623.xalancbmk_s|xalancbmk_s_base.mytest-m64|-v t5.xml xalanc.xsl|8GB|200000000|250000000"
    [leela]="641.leela_s|leela_s_base.mytest-m64|ref.sgf|8GB|200000000|250000000"
    [exchange2]="648.exchange2_s|exchange2_s_base.mytest-m64|6|8GB|200000000|250000000"
    [lbm]="619.lbm_s|lbm_s_base.mytest-m64|2000 reference.dat 0 0 200_200_260_ldc.of|8GB|300000000|250000000"
    [imagick]="638.imagick_s|imagick_s_base.mytest-m64|-limit disk 0 refspeed_input.tga -resize 817% -rotate -2.76 -shave 540x375 -alpha remove -auto-level -contrast-stretch 1x1% -colorspace Lab -channel R -equalize +channel -colorspace sRGB -define histogram:unique-colors=false -adaptive-blur 0x5 -despeckle -auto-gamma -adaptive-sharpen 55 -enhance -brightness-contrast 10x10 -resize 30% refspeed_output.tga|8GB|200000000|250000000"
    [nab]="644.nab_s|nab_s_base.mytest-m64|3j1n 20140317 220|8GB|200000000|250000000"
)

BENCH_ORDER=(omnetpp mcf xalancbmk perlbench leela exchange2 deepsjeng xz lbm imagick nab)
MAX_PARALLEL=${MAX_PARALLEL:-2}

run_bench() {
    local policy=$1
    local rp_class=$2
    local name=$3

    local entry=${BENCHMARKS[$name]}
    IFS='|' read -r bench_dir binary options mem_size fast_forward bench_maxinst <<< "$entry"

    local inst=${MAXINST:-0}
    if [ "$inst" -eq 0 ] 2>/dev/null; then
        inst=$bench_maxinst
    fi

    local outdir=$RESULTS/$L3_SIZE/$policy/$name
    local rundir=$SPEC/$bench_dir/run/run_base_refspeed_mytest-m64.0000
    local ckpt_dir=$CKPT_BASE/$name/m5out

    if [ -s "$outdir/stats.txt" ]; then
        echo "SKIP [$L3_SIZE/$policy/$name] (already done)"
        return 0
    fi

    if [ ! -f "$rundir/$binary" ]; then
        echo "ERROR: binary not found: $rundir/$binary"
        return 1
    fi

    if ! ls "$ckpt_dir"/cpt.* 1>/dev/null 2>&1; then
        echo "ERROR [$name]: no checkpoint found in $ckpt_dir"
        return 1
    fi

    mkdir -p "$outdir"

    local dsb_flags
    dsb_flags=$(get_dsb_flags "$policy")

    local warmup_flags=()
    if [ "$WARMUP" -gt 0 ] 2>/dev/null; then
        warmup_flags=(--standard-switch=1 --warmup-insts="$WARMUP")
    fi

    echo "==> [$L3_SIZE/$policy/$name] Starting (maxinst=$inst, warmup=$WARMUP, mem=$mem_size, checkpoint=$ckpt_dir) ..."

    (cd "$rundir" && \
        $GEM5 --outdir="$outdir" \
            $CONFIG \
            --rp-type="$rp_class" \
            --l3-size="$L3_SIZE" \
            --l3-assoc="$L3_ASSOC" \
            --cmd="./$binary" \
            --options="$options" \
            --mem-size="$mem_size" \
            --maxinst="$inst" \
            "${GEM5_COMMON[@]}" \
            --checkpoint-restore=1 \
            --checkpoint-dir="$ckpt_dir" \
            --restore-with-cpu=AtomicSimpleCPU \
            "${warmup_flags[@]}" \
            $dsb_flags \
    ) > "$outdir/sim.log" 2>&1
    local rc=$?

    if [ $rc -gt 128 ]; then
        echo "==> [$L3_SIZE/$policy/$name] Killed by signal (exit code $rc). Aborting."
        exit $rc
    fi

    echo "==> [$L3_SIZE/$policy/$name] Done (exit code $rc)."
}

for policy in "${POLICY_ORDER[@]}"; do
    rp_class=$(get_rp_class "$policy")
    echo ""
    echo "========================================="
    echo " Policy: $policy ($rp_class) | L2: 256kB (assoc=8) | L3: $L3_SIZE (assoc=$L3_ASSOC)"
    echo "========================================="

    pids=()
    bench_names=()
    failed=()

    for name in "${BENCH_ORDER[@]}"; do
        outdir_check=$RESULTS/$L3_SIZE/$policy/$name
        if [ -s "$outdir_check/stats.txt" ]; then
            echo "SKIP [$L3_SIZE/$policy/$name] (already done)"
            continue
        fi

        run_bench "$policy" "$rp_class" "$name" &
        pids+=($!)
        bench_names+=("$name")

        if [ ${#pids[@]} -ge "$MAX_PARALLEL" ]; then
            for i in "${!pids[@]}"; do
                wait "${pids[$i]}"
                rc=$?
                if [ $rc -gt 128 ]; then
                    echo "Benchmark ${bench_names[$i]} killed by signal. Aborting all."
                    kill "${pids[@]}" 2>/dev/null
                    exit $rc
                elif [ $rc -ne 0 ]; then
                    failed+=("${bench_names[$i]}")
                fi
            done
            pids=()
            bench_names=()
        fi
    done

    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        rc=$?
        if [ $rc -gt 128 ]; then
            echo "Benchmark ${bench_names[$i]} killed by signal. Aborting all."
            kill "${pids[@]}" 2>/dev/null
            exit $rc
        elif [ $rc -ne 0 ]; then
            failed+=("${bench_names[$i]}")
        fi
    done

    if [ ${#failed[@]} -gt 0 ]; then
        echo "WARNING: Failed benchmarks for $policy: ${failed[*]}"
    fi

    echo ""
    echo "--- $policy results ---"
    for name in "${BENCH_ORDER[@]}"; do
        stats="$RESULTS/$L3_SIZE/$policy/$name/stats.txt"
        if [ -f "$stats" ]; then
            l2_mr=$(grep "system.l2.demandMissRate::total" "$stats" | awk '{print $2}')
            l2_rep=$(grep "system.l2.replacements " "$stats" | awk '{print $2}')
            echo "  $name:  L2 miss rate = $l2_mr   L2 replacements = $l2_rep"
        else
            echo "  $name:  (no stats)"
        fi
    done
done

echo ""
echo "========================================="
echo " All policies complete."
echo " Results in: $RESULTS/$L3_SIZE/"
echo "========================================="
