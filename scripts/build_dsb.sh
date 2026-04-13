#!/bin/bash
# build_dsb.sh
# Copies DSB source files and gem5 bypass patches into gem5, then rebuilds.
# Usage: bash scripts/build_dsb.sh

set -e  # exit immediately on any error

SRC=/workspace/src/replacement_policies
PATCHES=/workspace/src/gem5_patches
DEST=/opt/gem5/src/mem/cache/replacement_policies
GEM5=/opt/gem5

echo "==> Copying DSB files to gem5 source tree..."
cp "$SRC/dsb_rp.hh"   "$DEST/"
cp "$SRC/dsb_rp.cc"    "$DEST/"
cp "$SRC/DSBRP.py"     "$DEST/"
cp "$SRC/SConscript"   "$DEST/"

echo "==> Applying gem5 bypass patches..."
cp "$PATCHES/replacement_policies_base.hh" "$GEM5/src/mem/cache/replacement_policies/base.hh"
cp "$PATCHES/tags_base.hh"                 "$GEM5/src/mem/cache/tags/base.hh"
cp "$PATCHES/tags_base_set_assoc.hh"       "$GEM5/src/mem/cache/tags/base_set_assoc.hh"
cp "$PATCHES/cache_base.cc"                "$GEM5/src/mem/cache/base.cc"

echo "==> Building gem5..."
cd "$GEM5"
scons build/X86/gem5.opt -j$(nproc)

echo ""
echo "Build complete."
