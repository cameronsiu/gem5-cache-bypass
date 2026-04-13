#!/bin/bash
# create_checkpoints.sh
# Creates gem5 checkpoints by fast-forwarding each SPEC CPU2017 benchmark
# in AtomicSimpleCPU mode for a configurable number of instructions.
#
# Usage:
#   bash scripts/create_checkpoints.sh              # 25B instructions (default)
#   CKPT_INSTS=5000000000 bash scripts/create_checkpoints.sh  # 5B instructions
#   MAX_PARALLEL=4 bash scripts/create_checkpoints.sh          # 4 benchmarks at once
#   MAX_PARALLEL=6 PROG_INTERVAL=10Hz bash scripts/create_checkpoints.sh

set +e  # Don't exit on individual benchmark failures

GEM5=/opt/gem5/build/X86/gem5.opt
SE_PY=/opt/gem5/configs/deprecated/example/se.py
SPEC=/workspace/spec2017/benchspec/CPU
CKPT_BASE=${CKPT_BASE:-/workspace/checkpoints}
CKPT_INSTS=${CKPT_INSTS:-25000000000}   # 25 billion instructions
PROG_INTERVAL=${PROG_INTERVAL:-10Hz}    # gem5 CPU progress message interval

# Benchmark definitions: spec_dir | binary | options | mem_size | input_file (optional, for stdin)
# (same benchmarks as run_all.sh, minus commented-out ones)
declare -A BENCHMARKS
BENCHMARKS=(
    [mcf]="605.mcf_s|mcf_s_base.gem5-x86|inp.in|8GB"
    [deepsjeng]="631.deepsjeng_s|deepsjeng_s_base.gem5-x86|ref.txt|8GB"
    [xz]="657.xz_s|xz_s_base.gem5-x86|cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4|16GB"
    [perlbench]="600.perlbench_s|perlbench_s_base.gem5-x86|-I./lib checkspam.pl 2500 5 25 11 150 1 1 1 1|8GB"
    [gcc]="602.gcc_s|sgcc_base.gem5-x86|gcc-pp.c -O5 -fipa-pta -o gcc-pp.opts-O5_-fipa-pta.s|8GB"
    [omnetpp]="620.omnetpp_s|omnetpp_s_base.gem5-x86|-c General -r 0|8GB"
    [xalancbmk]="623.xalancbmk_s|xalancbmk_s_base.gem5-x86|-v t5.xml xalanc.xsl|8GB"
    [x264]="625.x264_s|x264_s_base.gem5-x86|--pass 1 --stats x264_stats.log --bitrate 1000 --frames 1000 -o BuckBunny_New.264 BuckBunny.yuv 1280x720|8GB"
    [leela]="641.leela_s|leela_s_base.gem5-x86|ref.sgf|8GB"
    [exchange2]="648.exchange2_s|exchange2_s_base.gem5-x86|6|8GB"
    [lbm]="619.lbm_s|lbm_s_base.gem5-x86|2000 reference.dat 0 0 200_200_260_ldc.of|8GB"
    [imagick]="638.imagick_s|imagick_s_base.gem5-x86|-limit disk 0 refspeed_input.tga -resize 817% -rotate -2.76 -shave 540x375 -alpha remove -auto-level -contrast-stretch 1x1% -colorspace Lab -channel R -equalize +channel -colorspace sRGB -define histogram:unique-colors=false -adaptive-blur 0x5 -despeckle -auto-gamma -adaptive-sharpen 55 -enhance -brightness-contrast 10x10 -resize 30% refspeed_output.tga|8GB"
    [nab]="644.nab_s|nab_s_base.gem5-x86|3j1n 20140317 220|8GB"
    [bwaves]="603.bwaves_s|speed_bwaves_base.gem5-x86|bwaves_1|16GB|bwaves_1.in"
    [wrf]="621.wrf_s|wrf_s_base.gem5-x86||8GB"
    [cam4]="627.cam4_s|cam4_s_base.gem5-x86||8GB"
    [pop2]="628.pop2_s|speed_pop2_base.gem5-x86||8GB"
    [fotonik3d]="649.fotonik3d_s|fotonik3d_s_base.gem5-x86||8GB"
    [roms]="654.roms_s|sroms_base.gem5-x86||16GB|ocean_benchmark3.in"
)

BENCH_ORDER=(xz omnetpp mcf gcc xalancbmk perlbench x264 leela exchange2 deepsjeng lbm imagick nab wrf cam4 pop2 fotonik3d roms bwaves)
MAX_PARALLEL=${MAX_PARALLEL:-2}

create_checkpoint() {
    local name=$1
    local entry=${BENCHMARKS[$name]}
    IFS='|' read -r bench_dir binary options mem_size input_file <<< "$entry"

    local rundir=$SPEC/$bench_dir/run/run_base_refspeed_gem5-x86.0000
    local ckpt_dir=$CKPT_BASE/$name
    local outdir=$ckpt_dir/m5out
    local effective_options="$options"
    local input_flags=()
    if [ -n "$input_file" ]; then
        input_flags=(--input="$input_file")
    fi

    if [ ! -f "$rundir/$binary" ]; then
        echo "ERROR [$name]: binary not found: $rundir/$binary"
        return 1
    fi

    mkdir -p "$outdir"

    # Skip only if the existing checkpoint looks valid for this target.
    if ls "$outdir"/cpt.* 1>/dev/null 2>&1; then
        local existing_stats="$outdir/stats.txt"
        local existing_sim_insts=""
        if [ -f "$existing_stats" ]; then
            existing_sim_insts=$(awk '$1=="simInsts" { print $2; exit }' "$existing_stats")
        fi

        if grep -q "Simulated exit code not 0!" "$ckpt_dir/sim.log" 2>/dev/null; then
            echo "ERROR [$name]: existing checkpoint looks stale or invalid (non-zero simulated exit). Remove $ckpt_dir and rerun."
            return 1
        fi

        if [ -n "$existing_sim_insts" ] && [ "$existing_sim_insts" -lt "$CKPT_INSTS" ]; then
            echo "ERROR [$name]: existing checkpoint only reached $existing_sim_insts instructions. Remove $ckpt_dir and rerun."
            return 1
        fi

        echo "SKIP [$name] (valid checkpoint already exists)"
        return 0
    fi

    echo "==> [$name] Creating checkpoint after ${CKPT_INSTS} instructions (atomic mode, progress every ${PROG_INTERVAL}) ..."
    echo "==> [$name] Log: $ckpt_dir/sim.log"

    (
        start_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        start_epoch=$(date +%s)
        echo "==> [$name] Start: $start_ts"
        echo "==> [$name] Run dir: $rundir"
        echo "==> [$name] Out dir: $outdir"

        cd "$rundir" || exit 1

        if [ "$name" = "x264" ] && [ ! -f "BuckBunny.yuv" ]; then
            if [ ! -x "./ldecod_s_base.gem5-x86" ]; then
                echo "==> [$name] ERROR: missing input generator: $rundir/ldecod_s_base.gem5-x86"
                exit 1
            fi
            echo "==> [$name] Generating BuckBunny.yuv with ldecod_s_base.gem5-x86 ..."
            ./ldecod_s_base.gem5-x86 -i BuckBunny.264 -o BuckBunny.yuv
            gen_rc=$?
            echo "==> [$name] Input generation exit code: $gen_rc"
            if [ $gen_rc -ne 0 ] || [ ! -f "BuckBunny.yuv" ]; then
                echo "==> [$name] ERROR: failed to generate BuckBunny.yuv"
                exit 1
            fi
        fi

        if [ "$name" = "gcc" ]; then
            # The SPEC input is already preprocessed; disabling standard include
            # probing avoids a gem5 SE directory-handling bug on /usr/include.
            effective_options="-nostdinc $options"
            echo "==> [$name] NOTE: adding -nostdinc for checkpoint creation because gem5 SE mis-handles /usr/include directories."
        fi

        echo "==> [$name] Command: $GEM5 --outdir=$outdir $SE_PY --cpu-type=AtomicSimpleCPU --mem-size=$mem_size --maxinsts=$CKPT_INSTS --prog-interval=$PROG_INTERVAL --checkpoint-at-end --cmd=./$binary --options=$effective_options"

        $GEM5 --outdir="$outdir" \
            $SE_PY \
            --cpu-type=AtomicSimpleCPU \
            --mem-size="$mem_size" \
            --maxinsts="$CKPT_INSTS" \
            --prog-interval="$PROG_INTERVAL" \
            --checkpoint-at-end \
            --cmd="./$binary" \
            --options="$effective_options" \
            "${input_flags[@]}"
        rc=$?

        end_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        end_epoch=$(date +%s)
        echo "==> [$name] End: $end_ts"
        echo "==> [$name] Host elapsed: $((end_epoch - start_epoch)) seconds"
        echo "==> [$name] Exit code: $rc"
        exit $rc
    ) > "$ckpt_dir/sim.log" 2>&1
    local rc=$?

    if [ $rc -gt 128 ]; then
        echo "==> [$name] Killed by signal (exit code $rc). Aborting."
        exit $rc
    fi

    # Verify checkpoint was created
    if ls "$outdir"/cpt.* 1>/dev/null 2>&1; then
        local stats_file="$outdir/stats.txt"
        local sim_insts=""
        if [ -f "$stats_file" ]; then
            sim_insts=$(awk '$1=="simInsts" { print $2; exit }' "$stats_file")
        fi

        if grep -q "Simulated exit code not 0!" "$ckpt_dir/sim.log"; then
            echo "==> [$name] WARNING: checkpoint exists, but the simulated program exited with a non-zero status. Check $ckpt_dir/sim.log"
            return 1
        fi

        if [ -n "$sim_insts" ] && [ "$sim_insts" -lt "$CKPT_INSTS" ]; then
            echo "==> [$name] WARNING: checkpoint exists, but the benchmark ended after $sim_insts instructions before reaching the $CKPT_INSTS target."
            return 1
        fi

        echo "==> [$name] Checkpoint created successfully (simInsts=${sim_insts:-unknown}, exit code $rc)."
    else
        echo "==> [$name] WARNING: No checkpoint directory found (exit code $rc). Check $ckpt_dir/sim.log"
        return 1
    fi
}

# --- Main: run benchmarks in parallel ---
echo "========================================="
echo " Creating checkpoints (${CKPT_INSTS} instructions each)"
echo " Output: $CKPT_BASE/<benchmark>/"
echo "========================================="
echo ""

pids=()
bench_names=()
failed=()

for name in "${BENCH_ORDER[@]}"; do
    create_checkpoint "$name" &
    pids+=($!)
    bench_names+=("$name")

    # Limit parallelism
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

# Wait for remaining
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

echo ""
echo "========================================="
echo " Checkpoint creation complete."
if [ ${#failed[@]} -gt 0 ]; then
    echo " FAILED: ${failed[*]}"
fi
echo " Checkpoints in: $CKPT_BASE/"
echo "========================================="

# List what was created
echo ""
for name in "${BENCH_ORDER[@]}"; do
    ckpt_dir=$CKPT_BASE/$name/m5out
    if ls "$ckpt_dir"/cpt.* 1>/dev/null 2>&1; then
        ckpt_tick=$(ls -d "$ckpt_dir"/cpt.* | head -1 | sed 's/.*cpt\.//')
        echo "  $name: checkpoint at tick $ckpt_tick"
    else
        echo "  $name: (no checkpoint)"
    fi
done
