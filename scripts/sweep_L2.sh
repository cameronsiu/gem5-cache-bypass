#!/bin/bash
# sweep_warmup.sh
# Run DSB, LRU, BRRIP across 512KB, 1MB, 2MB, 4MB L2 sizes.
# Results go to /workspace/results_warmup/<L2_SIZE>/<policy>/<benchmark>/

trap 'echo "Sweep killed. Cleaning up..."; kill 0; exit 1' INT TERM

# SIZES=(512kB 1MB 2MB 4MB)
# POLICIES="dsb lru brrip"
SIZES=(512kB 1MB 2MB)
POLICIES="brrip"

for size in "${SIZES[@]}"; do
    echo ""
    echo "############################################"
    echo " L2 SIZE: $size"
    echo "############################################"
    MAX_PARALLEL=6 L2_SIZE=$size POLICIES_OVERRIDE="$POLICIES" \
        bash /workspace/scripts/run_all.sh
    if [ $? -gt 128 ]; then
        echo "run_all.sh was killed. Stopping sweep."
        exit 1
    fi
done

echo ""
echo "All sweeps complete. Results in /workspace/results/"
