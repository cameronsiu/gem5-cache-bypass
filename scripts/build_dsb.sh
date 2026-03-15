#!/bin/bash
# build_dsb.sh
# Copies DSB source files into gem5 and rebuilds.
# Usage: bash scripts/build_dsb.sh

set -e  # exit immediately on any error

SRC=/workspace/src/replacement_policies
DEST=/opt/gem5/src/mem/cache/replacement_policies
GEM5=/opt/gem5

echo "==> Copying DSB files to gem5 source tree..."
cp "$SRC/dsb_rp.hh"   "$DEST/"
cp "$SRC/dsb_rp.cc"    "$DEST/"
cp "$SRC/DSBRP.py"     "$DEST/"
cp "$SRC/SConscript"   "$DEST/"

echo "==> Building gem5..."
cd "$GEM5"
scons build/X86/gem5.opt -j$(nproc)

echo ""
echo "Build complete. Run a simulation with:"
echo "  gem5 --outdir=/workspace/results/dsb /workspace/configs/run_dsb.py"
