#!/bin/bash
# run_baselines.sh
# Runs gem5 simulations for baseline replacement policies and saves stats to /workspace/results/.
# Usage: bash scripts/run_baselines.sh [binary]
#
# Results land in:
#   /workspace/results/<policy>/stats.txt
#   /workspace/results/<policy>/config.ini

GEM5=/opt/gem5/build/X86/gem5.opt
GEM5_CONFIGS=/opt/gem5/configs
BINARY=${1:-/opt/gem5/tests/test-progs/hello/bin/x86/linux/hello}
RESULTS=/workspace/results

run_sim() {
    local policy=$1
    local rp_class=$2
    local outdir=$RESULTS/$policy

    echo "==> Running $policy ..."
    mkdir -p "$outdir"

    $GEM5 --outdir="$outdir" \
        $GEM5_CONFIGS/learning_gem5/part1/two_level.py \
        "$BINARY" \
        2>&1 | tee "$outdir/sim.log"

    echo "    Stats: $outdir/stats.txt"
}

# Baselines (using default LRU policy built into two_level.py for now)
# TODO: add --param flags or a custom config once BypassRP is wired up
run_sim "lru"    "LRURP"
# run_sim "random" "RandomRP"
# run_sim "brrip"  "BRRIPRP"
# run_sim "dsb"    "DSBRP"      # uncomment after implementing DSBRP

echo ""
echo "All done. Results in $RESULTS/"
echo "Key stats to compare:"
echo "  grep -E 'demandMissRate|demandHits|demandMisses|replacements|demandAvgMissLatency' $RESULTS/*/stats.txt"
