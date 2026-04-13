#!/bin/bash
# sweep_l3.sh
# Generic L3 sweep wrapper for quick experiments.
#
# Defaults:
#   SIZES="1MB 2MB 4MB"
#   POLICIES="lru brrip"
#
# Supported policy tokens:
#   lru
#   brrip
#   dsb_policy0   -> policy0Config1 policy0Config2 policy0Config3
#   dsb_policy1   -> policy1Config1 policy1Config2 policy1Config3
#
# Examples:
#   bash scripts/sweep_l3.sh
#   POLICIES="dsb_policy0" bash scripts/sweep_l3.sh
#   POLICIES="lru brrip dsb_policy1" SIZES="1MB 2MB" bash scripts/sweep_l3.sh
#   MAX_PARALLEL=4 SIZES="2MB" POLICIES="brrip" bash scripts/sweep_l3.sh

trap 'echo "Sweep killed. Cleaning up..."; kill 0; exit 1' INT TERM

SIZE_LIST=(${SIZES:-4MB})
POLICIES=${POLICIES:-"lru brrip random tree_plru ship_mem ship_pc dsb_policy0 dsb_policy1"}
MAX_PARALLEL=${MAX_PARALLEL:-6}
RESULTS=${RESULTS:-/workspace/results_l3}

for size in "${SIZE_LIST[@]}"; do
    echo ""
    echo "############################################"
    echo " L3 SIZE: $size"
    echo " Policies: $POLICIES"
    echo "############################################"
    MAX_PARALLEL="$MAX_PARALLEL" \
    L3_SIZE="$size" \
    POLICIES_OVERRIDE="$POLICIES" \
    RESULTS="$RESULTS" \
    bash /workspace/scripts/run_all_l3.sh
    if [ $? -gt 128 ]; then
        echo "run_all_l3.sh was killed. Stopping sweep."
        exit 1
    fi
done

echo ""
echo "All L3 sweeps complete. Results in $RESULTS/"
