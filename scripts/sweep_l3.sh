#!/bin/bash
# sweep_L3.sh
# Run one or more replacement policies across a fixed 3-level hierarchy while
# varying the shared L3 size.
#
# Defaults:
#   L1I = 32kB 8-way
#   L1D = 32kB 8-way
#   L2  = 256kB 8-way
#   L3  = 1MB, 2MB, 4MB, 16-way

trap 'echo "Sweep killed. Cleaning up..."; kill 0; exit 1' INT TERM

SIZES=(1MB 2MB 4MB)
POLICIES=${POLICIES:-"lru brrip random fifo lfu mru bip second_chance weighted_lru tree_plru ship_mem ship_pc"}

for size in "${SIZES[@]}"; do
    echo ""
    echo "############################################"
    echo " L3 SIZE: $size"
    echo "############################################"
    MAX_PARALLEL=${MAX_PARALLEL:-6} \
    L3_SIZE="$size" \
    POLICIES_OVERRIDE="$POLICIES" \
    bash /workspace/scripts/run_all_l3.sh
    if [ $? -gt 128 ]; then
        echo "run_all.sh was killed. Stopping sweep."
        exit 1
    fi
done

echo ""
echo "All L3 sweeps complete. Results in /workspace/results_l3/"
