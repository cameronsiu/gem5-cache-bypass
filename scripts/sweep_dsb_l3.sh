#!/bin/bash
# sweep_dsb_l3.sh
# Sweep DSB bypass_counter across all benchmarks using the L3-enabled config.
#
# Fixed hierarchy:
#   L1I = 32kB, 8-way
#   L1D = 32kB, 8-way
#   L2  = 256kB, 8-way
#   L3  = configurable, default 2MB, 16-way

set +e

GEM5=/opt/gem5/build/X86/gem5.opt
CONFIG=/workspace/configs/run_spec_l3.py
SPEC=/workspace/spec2017/benchspec/CPU
RESULTS=${RESULTS:-/workspace/results_l3}
MAX_PARALLEL=${MAX_PARALLEL:-1}
L3_SIZE=${L3_SIZE:-2MB}
L3_ASSOC=${L3_ASSOC:-16}

CONFIGS=(
    "dsb-bc0|0|4|0"
    "dsb-bc2|2|4|0"
    "dsb-bc4|4|4|0"
)

declare -A BENCHMARKS_MAP
BENCHMARKS_MAP=(
    [mcf]="605.mcf_s|mcf_s_base.mytest-m64|inp.in|8GB|0|50000000"
    [deepsjeng]="631.deepsjeng_s|deepsjeng_s_base.mytest-m64|ref.txt|8GB|500000000|100000000"
    [xz]="657.xz_s|xz_s_base.mytest-m64|cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4|16GB|500000000|100000000"
    [perlbench]="600.perlbench_s|perlbench_s_base.mytest-m64|-I./lib checkspam.pl 2500 5 25 11 150 1 1 1 1|8GB|200000000|50000000"
    [gcc]="602.gcc_s|sgcc_base.mytest-m64|gcc-pp.c -O5 -fipa-pta -o gcc-pp.opts-O5_-fipa-pta.s|8GB|1000000000|50000000"
    [omnetpp]="620.omnetpp_s|omnetpp_s_base.mytest-m64|-c General -r 0|8GB|200000000|50000000"
    [xalancbmk]="623.xalancbmk_s|xalancbmk_s_base.mytest-m64|-v t5.xml xalanc.xsl|8GB|200000000|50000000"
    [x264]="625.x264_s|x264_s_base.mytest-m64|--pass 1 --stats x264_stats.log --bitrate 1000 --frames 100 -o BuckBunny_New.264 BuckBunny.yuv 1280x720|8GB|200000000|50000000"
    [leela]="641.leela_s|leela_s_base.mytest-m64|ref.sgf|8GB|200000000|50000000"
    [exchange2]="648.exchange2_s|exchange2_s_base.mytest-m64|6|8GB|200000000|50000000"
    [cactuBSSN]="607.cactuBSSN_s|cactuBSSN_s_base.mytest-m64|spec_ref.par|8GB|1000000000|50000000"
    [lbm]="619.lbm_s|lbm_s_base.mytest-m64|2000 reference.dat 0 0 200_200_260_ldc.of|8GB|300000000|200000000"
    [imagick]="638.imagick_s|imagick_s_base.mytest-m64|-limit disk 0 refspeed_input.tga -resize 817% -rotate -2.76 -shave 540x375 -alpha remove -auto-level -contrast-stretch 1x1% -colorspace Lab -channel R -equalize +channel -colorspace sRGB -define histogram:unique-colors=false -adaptive-blur 0x5 -despeckle -auto-gamma -adaptive-sharpen 55 -enhance -brightness-contrast 10x10 -resize 30% refspeed_output.tga|8GB|200000000|50000000"
    [nab]="644.nab_s|nab_s_base.mytest-m64|3j1n 20140317 220|8GB|200000000|50000000"
)

BENCH_ORDER=(${BENCHMARKS:-omnetpp mcf gcc xalancbmk perlbench x264 leela exchange2 deepsjeng xz cactuBSSN lbm imagick nab})

GEM5_COMMON=(
    --cpu-type=DerivO3CPU
    --caches --l2cache
    --l1d_size=32kB --l1i_size=32kB --l1d-assoc=8 --l1i-assoc=8 --l2_size=256kB --l2-assoc=8
)

run_one() {
    local config_label=$1
    local bc=$2
    local vbc=$3
    local rp=$4
    local bench_name=$5

    local entry=${BENCHMARKS_MAP[$bench_name]}
    IFS='|' read -r bench_dir binary options mem_size fast_forward bench_maxinst <<< "$entry"

    local inst=${MAXINST:-0}
    if [ "$inst" -eq 0 ] 2>/dev/null; then
        inst=$bench_maxinst
    fi

    local outdir=$RESULTS/$L3_SIZE/$config_label/$bench_name
    local rundir=$SPEC/$bench_dir/run/run_base_refspeed_mytest-m64.0000

    if [ -s "$outdir/stats.txt" ]; then
        echo "SKIP [$L3_SIZE/$config_label/$bench_name]"
        return 0
    fi

    if [ ! -f "$rundir/$binary" ]; then
        echo "ERROR: binary not found: $rundir/$binary"
        return 1
    fi

    mkdir -p "$outdir"

    local ff_flags=()
    if [ "$fast_forward" -gt 0 ] 2>/dev/null; then
        ff_flags=(--fast-forward="$fast_forward")
    fi

    echo "==> [$L3_SIZE/$config_label/$bench_name] Starting (bc=$bc vbc=$vbc rp=$rp maxinst=$inst) ..."

    (cd "$rundir" && \
        $GEM5 --outdir="$outdir" \
            $CONFIG \
            --rp-type=DSBRP \
            --l3-size="$L3_SIZE" \
            --l3-assoc="$L3_ASSOC" \
            --dsb-bypass-counter="$bc" \
            --dsb-virtual-bypass-counter="$vbc" \
            --dsb-random-promotion="$rp" \
            --cmd="./$binary" \
            --options="$options" \
            --mem-size="$mem_size" \
            --maxinst="$inst" \
            "${GEM5_COMMON[@]}" \
            "${ff_flags[@]}" \
    ) > "$outdir/sim.log" 2>&1

    echo "==> [$L3_SIZE/$config_label/$bench_name] Done."
}

for config_entry in "${CONFIGS[@]}"; do
    IFS='|' read -r label bc vbc rp <<< "$config_entry"
    echo ""
    echo "========================================="
    echo " Config: $label (bc=$bc vbc=$vbc rp=$rp) | L2: 256kB | L3: $L3_SIZE"
    echo "========================================="

    pids=()
    bench_names=()
    failed=()

    for name in "${BENCH_ORDER[@]}"; do
        outdir_check=$RESULTS/$L3_SIZE/$label/$name
        if [ -s "$outdir_check/stats.txt" ]; then
            echo "SKIP [$L3_SIZE/$label/$name]"
            continue
        fi

        run_one "$label" "$bc" "$vbc" "$rp" "$name" &
        pids+=($!)
        bench_names+=("$name")

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

    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            failed+=("${bench_names[$i]}")
        fi
    done

    if [ ${#failed[@]} -gt 0 ]; then
        echo "WARNING: Failed benchmarks for $label: ${failed[*]}"
    fi

    echo ""
    echo "--- $label results ---"
    for name in "${BENCH_ORDER[@]}"; do
        stats="$RESULTS/$L3_SIZE/$label/$name/stats.txt"
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
echo " Sweep complete. Results in: $RESULTS/$L3_SIZE/"
echo "========================================="
