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

RAW_POLICY_ORDER=(${POLICIES_OVERRIDE:-lru brrip dsb_policy0 dsb_policy1})

declare -A POLICY_MAP
POLICY_MAP=(
    [lru]=LRURP
    [bip]=BIPRP
    [lfu]=LFURP
    [mru]=MRURP
    [brrip]=BRRIPRP
    [random]=RandomRP
    [fifo]=FIFORP
    [second_chance]=SecondChanceRP
    [ship_mem]=SHiPMemRP
    [ship_pc]=SHiPPCRP
    [weighted_lru]=WeightedLRURP
    [tree_plru]=TreePLRURP
    [dsb]=DSBRP
)

is_dsb_config() {
    local policy=$1
    case "$policy" in
        policy0Config1|policy0Config2|policy0Config3|policy1Config1|policy1Config2|policy1Config3)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

expand_policy_token() {
    local policy=$1
    case "$policy" in
        dsb_policy0)
            echo "policy0Config1 policy0Config2 policy0Config3"
            ;;
        dsb_policy1)
            echo "policy1Config1 policy1Config2 policy1Config3"
            ;;
        dsb_all)
            echo "policy0Config1 policy0Config2 policy0Config3 policy1Config1 policy1Config2 policy1Config3"
            ;;
        *)
            echo "$policy"
            ;;
    esac
}

POLICY_ORDER=()
for policy in "${RAW_POLICY_ORDER[@]}"; do
    read -r -a expanded <<< "$(expand_policy_token "$policy")"
    POLICY_ORDER+=("${expanded[@]}")
done

get_rp_class() {
    local policy=$1
    local base=${policy%%-*}
    if is_dsb_config "$policy"; then
        echo "DSBRP"
    elif [ -n "${POLICY_MAP[$policy]+x}" ]; then
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
        case "$policy" in
            policy0Config1)
                echo "--dsb-enable-bypass=true --dsb-enable-aging=false --dsb-bypass-counter=6 --dsb-virtual-bypass-counter=4 --dsb-random-promotion=0 --dsb-minimum-bypass-counter=8"
                ;;
            policy0Config2)
                echo "--dsb-enable-bypass=true --dsb-enable-aging=false --dsb-bypass-counter=6 --dsb-virtual-bypass-counter=3 --dsb-random-promotion=0 --dsb-minimum-bypass-counter=12"
                ;;
            policy0Config3)
                echo "--dsb-enable-bypass=true --dsb-enable-aging=false --dsb-bypass-counter=3 --dsb-virtual-bypass-counter=3 --dsb-random-promotion=0 --dsb-minimum-bypass-counter=12"
                ;;
            policy1Config1)
                echo "--dsb-enable-bypass=false --dsb-enable-aging=true --dsb-bypass-counter=6 --dsb-virtual-bypass-counter=4 --dsb-random-promotion=0 --dsb-minimum-bypass-counter=8"
                ;;
            policy1Config2)
                echo "--dsb-enable-bypass=true --dsb-enable-aging=true --dsb-bypass-counter=6 --dsb-virtual-bypass-counter=3 --dsb-random-promotion=0 --dsb-minimum-bypass-counter=12"
                ;;
            policy1Config3)
                echo "--dsb-enable-bypass=true --dsb-enable-aging=true --dsb-bypass-counter=3 --dsb-virtual-bypass-counter=3 --dsb-random-promotion=4 --dsb-minimum-bypass-counter=12"
                ;;
            *)
                echo ""
                ;;
        esac
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

CACHE_FLAGS=(
    --caches --l2cache
    --l1d_size=32kB --l1i_size=32kB --l1d_assoc=8 --l1i_assoc=8 --l2_size=256kB --l2_assoc=8
)

declare -A BENCHMARKS
# Format: spec_dir | binary | options | mem_size | maxinst | input_file (optional, for stdin)
BENCHMARKS=(
    [mcf]="605.mcf_s|mcf_s_base.gem5-x86|inp.in|8GB|250000000"
    [deepsjeng]="631.deepsjeng_s|deepsjeng_s_base.gem5-x86|ref.txt|8GB|250000000"
    [xz]="657.xz_s|xz_s_base.gem5-x86|cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4|16GB|250000000"
    [perlbench]="600.perlbench_s|perlbench_s_base.gem5-x86|-I./lib checkspam.pl 2500 5 25 11 150 1 1 1 1|8GB|250000000"
    [gcc]="602.gcc_s|sgcc_base.gem5-x86|gcc-pp.c -O5 -fipa-pta -o gcc-pp.opts-O5_-fipa-pta.s|8GB|250000000"
    [omnetpp]="620.omnetpp_s|omnetpp_s_base.gem5-x86|-c General -r 0|8GB|250000000"
    [xalancbmk]="623.xalancbmk_s|xalancbmk_s_base.gem5-x86|-v t5.xml xalanc.xsl|8GB|250000000"
    [x264]="625.x264_s|x264_s_base.gem5-x86|--pass 1 --stats x264_stats.log --bitrate 1000 --frames 1000 -o BuckBunny_New.264 BuckBunny.yuv 1280x720|8GB|250000000"
    [leela]="641.leela_s|leela_s_base.gem5-x86|ref.sgf|8GB|250000000"
    [exchange2]="648.exchange2_s|exchange2_s_base.gem5-x86|6|8GB|250000000"
    [cactuBSSN]="607.cactuBSSN_s|cactuBSSN_s_base.gem5-x86|spec_ref.par|8GB|250000000"
    [lbm]="619.lbm_s|lbm_s_base.gem5-x86|2000 reference.dat 0 0 200_200_260_ldc.of|8GB|250000000"
    [imagick]="638.imagick_s|imagick_s_base.gem5-x86|-limit disk 0 refspeed_input.tga -resize 817% -rotate -2.76 -shave 540x375 -alpha remove -auto-level -contrast-stretch 1x1% -colorspace Lab -channel R -equalize +channel -colorspace sRGB -define histogram:unique-colors=false -adaptive-blur 0x5 -despeckle -auto-gamma -adaptive-sharpen 55 -enhance -brightness-contrast 10x10 -resize 30% refspeed_output.tga|8GB|250000000"
    [nab]="644.nab_s|nab_s_base.gem5-x86|3j1n 20140317 220|8GB|250000000"
    [bwaves]="603.bwaves_s|speed_bwaves_base.gem5-x86|bwaves_1|16GB|250000000|bwaves_1.in"
    [wrf]="621.wrf_s|wrf_s_base.gem5-x86||8GB|250000000"
    [cam4]="627.cam4_s|cam4_s_base.gem5-x86||8GB|250000000"
    [pop2]="628.pop2_s|speed_pop2_base.gem5-x86||8GB|250000000"
    [fotonik3d]="649.fotonik3d_s|fotonik3d_s_base.gem5-x86||8GB|250000000"
    [roms]="654.roms_s|sroms_base.gem5-x86||16GB|250000000|ocean_benchmark3.in"
)

BENCH_ORDER=(xz omnetpp mcf gcc xalancbmk perlbench x264 leela exchange2 deepsjeng lbm imagick nab wrf cam4 pop2 fotonik3d roms bwaves)
MAX_PARALLEL=${MAX_PARALLEL:-5}

run_bench() {
    local policy=$1
    local rp_class=$2
    local name=$3

    local entry=${BENCHMARKS[$name]}
    IFS='|' read -r bench_dir binary options mem_size bench_maxinst input_file <<< "$entry"

    local inst=${MAXINST:-0}
    if [ "$inst" -eq 0 ] 2>/dev/null; then
        inst=$bench_maxinst
    fi

    local outdir=$RESULTS/$L3_SIZE/$policy/$name
    local rundir=$SPEC/$bench_dir/run/run_base_refspeed_gem5-x86.0000
    local ckpt_dir=$CKPT_BASE/$name/m5out
    local input_flags=()
    if [ -n "$input_file" ]; then
        input_flags=(--input="$input_file")
    fi

    if [ -s "$outdir/stats.txt" ]; then
        echo "SKIP [$L3_SIZE/$policy/$name] (already done)"
        return 0
    fi

    if [ ! -f "$rundir/$binary" ]; then
        echo "ERROR: binary not found: $rundir/$binary"
        return 1
    fi

    mkdir -p "$outdir"

    local dsb_flags
    dsb_flags=$(get_dsb_flags "$policy")

    local cpu_type=DerivO3CPU
    local run_mode_desc="checkpoint=$ckpt_dir"
    local warmup_flags=()
    if [ "$WARMUP" -gt 0 ] 2>/dev/null; then
        warmup_flags=(--standard-switch=1 --warmup-insts="$WARMUP")
    fi

    echo "==> [$L3_SIZE/$policy/$name] Starting (maxinst=$inst, warmup=$WARMUP, mem=$mem_size, $run_mode_desc) ..."

    (cd "$rundir" && \
        $GEM5 --outdir="$outdir" \
            $CONFIG \
            --rp-type="$rp_class" \
            --l3-size="$L3_SIZE" \
            --l3-assoc="$L3_ASSOC" \
            --cpu-type="$cpu_type" \
            --cmd="./$binary" \
            --options="$options" \
            --mem-size="$mem_size" \
            --maxinst="$inst" \
            "${CACHE_FLAGS[@]}" \
            --checkpoint-restore=1 \
            --checkpoint-dir="$ckpt_dir" \
            --restore-with-cpu=AtomicSimpleCPU \
            "${warmup_flags[@]}" \
            "${input_flags[@]}" \
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
            l3_mr=$(grep "system.l3.demandMissRate::total" "$stats" | awk '{print $2}')
            l3_rep=$(grep "system.l3.replacements " "$stats" | awk '{print $2}')
            echo "  $name:  L3 miss rate = $l3_mr   L3 replacements = $l3_rep"
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
