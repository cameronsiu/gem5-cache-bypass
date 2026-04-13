# True Bypass Modifications

This file is just the direct version of what gets patched and how to use it.

## Build

```bash
cd /workspace
bash scripts/build_dsb.sh
```

`build_dsb.sh` copies the DSB files into gem5 and rebuilds `gem5.opt`.

## Files copied into gem5

DSB replacement policy files:
- `src/replacement_policies/dsb_rp.hh`
- `src/replacement_policies/dsb_rp.cc`
- `src/replacement_policies/DSBRP.py`
- `src/replacement_policies/SConscript`

gem5 internal patch files:
- `src/gem5_patches/replacement_policies_base.hh`
- `src/gem5_patches/tags_base.hh`
- `src/gem5_patches/tags_base_set_assoc.hh`
- `src/gem5_patches/cache_base.cc`

## What the patch changes

The true bypass support depends on three things:

1. The replacement policy can see the incoming tag during victim selection.
2. The policy can mark an insertion as `shouldBypass`.
3. The cache allocation path honors that flag and skips insertion.

That is the reason gem5 needs the internal patch files above.

## Rebuild rule

Re-run this any time you change DSB or the patch files:

```bash
bash scripts/build_dsb.sh
```

## Run baselines

```bash
POLICIES_OVERRIDE="lru brrip random tree_plru ship_mem" \
bash scripts/run_all_l3.sh
```

## Run DSB

Run all six DSB configs:

```bash
POLICIES_OVERRIDE="dsb_policy0 dsb_policy1" \
bash scripts/run_all_l3.sh
```

Run only specific configs:

```bash
POLICIES_OVERRIDE="policy1Config1 policy0Config1 policy1Config2 policy1Config3" \
bash scripts/run_all_l3.sh
```

## Results

```text
/workspace/results_l3/<L3_SIZE>/<policy>/<benchmark>/
```
