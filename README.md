Repo is here: `https://github.com/cameronsiu/gem5-cache-bypass`

# gem5-cache-bypass

This repo contains the DSB replacement policy and the gem5 patches needed for true bypass.

The current workflow in this workspace is the L3 flow:
- build gem5 with the DSB patches
- create checkpoints
- run L3 baselines
- run L3 DSB policies

## Requirements

- gem5 source and build at `/opt/gem5`
- this repo at `/workspace`
- SPEC CPU2017 at `/workspace/spec2017`

If SPEC is not ready yet, use [docs/SPEC_SETUP.md](docs/SPEC_SETUP.md).

## 1. Build gem5

```bash
bash scripts/build_dsb.sh
```

Run this again any time you change:
- `src/replacement_policies/*`
- `src/gem5_patches/*`

## 2. Create checkpoints

The run script restores from checkpoints in `/workspace/checkpoints`.

```bash
bash scripts/create_checkpoints.sh
```

Useful overrides:

```bash
CKPT_INSTS=25000000000 bash scripts/create_checkpoints.sh
MAX_PARALLEL=2 bash scripts/create_checkpoints.sh
```

Output:

```text
/workspace/checkpoints/<benchmark>/m5out/
```

## 3. Run the baselines

This runs the baseline policies you have been comparing against:
- `lru`
- `brrip`
- `random`
- `tree_plru`
- `ship_mem`

```bash
POLICIES_OVERRIDE="lru brrip random tree_plru ship_mem" \
bash scripts/run_all_l3.sh
```

## 4. Run the DSB policies

This runs all six DSB configs:

```bash
POLICIES_OVERRIDE="dsb_policy0 dsb_policy1" \
bash scripts/run_all_l3.sh
```

If you only want a subset:

```bash
POLICIES_OVERRIDE="policy1Config1 policy0Config1 policy1Config2 policy1Config3" \
bash scripts/run_all_l3.sh
```

## Common overrides

```bash
L3_SIZE=1MB bash scripts/run_all_l3.sh
L3_SIZE=2MB bash scripts/run_all_l3.sh
L3_SIZE=4MB bash scripts/run_all_l3.sh

MAX_PARALLEL=5 bash scripts/run_all_l3.sh
MAXINST=1000000 bash scripts/run_all_l3.sh
RESULTS=/workspace/results_l3_test bash scripts/run_all_l3.sh
```

The script restores checkpoints from `/workspace/checkpoints`, warms up, then runs the detailed interval.

## Results

Results are written to:

```text
/workspace/results_l3/<L3_SIZE>/<policy>/<benchmark>/
```

## Plotting

```bash
python3 scripts/visualize_l3.py
```

You can also plot one metric or one size:

```bash
python3 scripts/visualize_l3.py --metric ipc
python3 scripts/visualize_l3.py --l3-size 2MB
```
