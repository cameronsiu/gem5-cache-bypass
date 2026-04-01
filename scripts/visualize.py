#!/usr/bin/env python3
"""
Create simple benchmark comparison plots from gem5 results.

Reads:
    /workspace/results/<l2_size>/<policy>/<benchmark>/stats.txt

Default output:
    /workspace/results/plots/<metric>/<l2_size>.png

Examples:
    python3 scripts/visualize.py
    python3 scripts/visualize.py --metric ipc
    python3 scripts/visualize.py --l2-size 1MB
    python3 scripts/visualize.py --dsb-policy dsb-bc2
"""

import argparse
import math
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = "/workspace/results"
PLOTS_DIR = os.path.join(RESULTS_DIR, "plots")
DEFAULT_BENCHMARK_ORDER = [
    "omnetpp",
    "mcf",
    "xalancbmk",
    "perlbench",
    "leela",
    "exchange2",
    "deepsjeng",
    "xz",
    "lbm",
    "imagick",
    "nab",
]
DEFAULT_L2_ORDER = ["512kB", "1MB", "2MB", "4MB"]

METRICS = {
    "ipc": {
        "label": "IPC",
        "folder": "ipc",
        "rate": False,
    },
    "miss-rate": {
        "label": "L2 Miss Rate",
        "folder": "miss_rate",
        "rate": True,
    },
    "mpki": {
        "label": "L2 MPKI",
        "folder": "mpki",
        "rate": False,
    },
    "l2-hits": {
        "label": "L2 Hits",
        "folder": "l2_hits",
        "rate": False,
    },
    "l2-total-accesses": {
        "label": "L2 Total Accesses",
        "folder": "l2_total_accesses",
        "rate": False,
    },
    "l2-replacements": {
        "label": "L2 Replacements",
        "folder": "l2_replacements",
        "rate": False,
    },
    "l1d-miss-rate": {
        "label": "L1D Miss Rate",
        "folder": "l1d_miss_rate",
        "rate": True,
    },
}

ALL_METRICS = list(METRICS.keys())

STAT_KEYS = {
    "ipc": "system.switch_cpus_1.ipc",
    "l2_misses": "system.l2.demandMisses::switch_cpus_1.data",
    "l2_miss_rate": "system.l2.demandMissRate::switch_cpus_1.data",
    "sim_insts": "system.switch_cpus_1.commitStats0.numInsts",
    "l2_hits": "system.l2.demandHits::switch_cpus_1.data",
    "l2_total_accesses": "system.l2.demandAccesses::switch_cpus_1.data",
    "l2_replacements": "system.l2.replacements",
    "l1d_miss_rate": "system.cpu.dcache.demandMissRate::switch_cpus_1.data",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Simple result plotter")
    parser.add_argument("--results-dir", default=RESULTS_DIR)
    parser.add_argument(
        "--plots-dir",
        default=None,
        help="Base output directory for generated plots. Default: <results_dir>/plots",
    )
    parser.add_argument(
        "--l2-size",
        default=None,
        help="Plot one L2 size only. Default: generate plots for all discovered sizes.",
    )
    parser.add_argument(
        "--metric",
        choices=ALL_METRICS,
        default=None,
        help="Plot one metric only. Default: generate all metrics.",
    )
    parser.add_argument("--dsb-policy", default="dsb")
    parser.add_argument("--benchmarks", nargs="+", default=None)
    parser.add_argument(
        "--output",
        default=None,
        help="Output path for a single metric and single L2 size only.",
    )
    return parser.parse_args()


def parse_stats(stats_path):
    needed_keys = set(STAT_KEYS.values())
    stats = {}

    if not os.path.isfile(stats_path) or os.path.getsize(stats_path) == 0:
        return stats

    with open(stats_path) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("---"):
                continue

            parts = line.split()
            if len(parts) < 2 or parts[0] not in needed_keys:
                continue

            try:
                value = float(parts[1])
            except ValueError:
                continue

            if math.isnan(value):
                continue

            stats[parts[0]] = value

    return stats


def get_metric_value(stats, metric):
    if metric == "ipc":
        return stats.get(STAT_KEYS["ipc"])

    if metric == "mpki":
        misses = stats.get(STAT_KEYS["l2_misses"])
        insts = stats.get(STAT_KEYS["sim_insts"])
        if misses is None or insts in (None, 0):
            return None
        return (misses * 1000.0) / insts

    if metric == "miss-rate":
        return stats.get(STAT_KEYS["l2_miss_rate"])

    if metric == "l2-hits":
        return stats.get(STAT_KEYS["l2_hits"])

    if metric == "l2-total-accesses":
        return stats.get(STAT_KEYS["l2_total_accesses"])

    if metric == "l2-replacements":
        return stats.get(STAT_KEYS["l2_replacements"])

    if metric == "l1d-miss-rate":
        return stats.get(STAT_KEYS["l1d_miss_rate"])

    return None


def benchmark_sort_key(name):
    try:
        return (0, DEFAULT_BENCHMARK_ORDER.index(name))
    except ValueError:
        return (1, name)


def l2_sort_key(name):
    try:
        return (0, DEFAULT_L2_ORDER.index(name))
    except ValueError:
        return (1, name)


def discover_l2_sizes(results_dir):
    sizes = []

    if not os.path.isdir(results_dir):
        return sizes

    for entry in os.listdir(results_dir):
        path = os.path.join(results_dir, entry)
        if not os.path.isdir(path):
            continue
        if entry == "plots":
            continue
        sizes.append(entry)

    return sorted(sizes, key=l2_sort_key)


def policy_color(policy):
    if policy.startswith("dsb"):
        return "tab:blue"
    if policy == "lru":
        return "tab:orange"
    if policy == "brrip":
        return "tab:green"
    return "tab:gray"


def load_data(results_dir, l2_size, policies, metric, benchmark_filter=None):
    size_dir = os.path.join(results_dir, l2_size)
    filter_set = set(benchmark_filter) if benchmark_filter else None
    data = {}

    for policy in policies:
        policy_dir = os.path.join(size_dir, policy)
        if not os.path.isdir(policy_dir):
            continue

        for bench in os.listdir(policy_dir):
            if filter_set and bench not in filter_set:
                continue

            stats_path = os.path.join(policy_dir, bench, "stats.txt")
            stats = parse_stats(stats_path)
            if not stats:
                continue

            value = get_metric_value(stats, metric)
            if value is None:
                continue

            data.setdefault(policy, {})[bench] = value

    return data


def save_plot(data, policies, metric, l2_size, output_path):
    benchmarks = sorted(
        {bench for policy_data in data.values() for bench in policy_data},
        key=benchmark_sort_key,
    )
    present_policies = [policy for policy in policies if policy in data]

    if not benchmarks or not present_policies:
        return False

    x = np.arange(len(benchmarks))
    width = 0.8 / len(present_policies)
    fig, ax = plt.subplots(figsize=(max(10, len(benchmarks) * 1.2), 5))

    for index, policy in enumerate(present_policies):
        offset = (index - (len(present_policies) - 1) / 2) * width
        values = [data.get(policy, {}).get(bench, np.nan) for bench in benchmarks]
        ax.bar(
            x + offset,
            values,
            width=width,
            label=policy.upper(),
            color=policy_color(policy),
        )

    ax.set_title(f"{METRICS[metric]['label']} Comparison ({l2_size})")
    ax.set_ylabel(METRICS[metric]["label"])
    ax.set_xticks(x)
    ax.set_xticklabels(benchmarks, rotation=45, ha="right")
    ax.legend()
    ax.grid(axis="y", alpha=0.2)

    if METRICS[metric]["rate"]:
        ax.set_ylim(bottom=0, top=1)
    else:
        ax.set_ylim(bottom=0)

    fig.tight_layout()

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    fig.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {metric} ({l2_size}) plot to {output_path}")
    return True


def default_output_path(plots_dir, metric, l2_size):
    return os.path.join(plots_dir, METRICS[metric]["folder"], f"{l2_size}.png")


def main():
    args = parse_args()
    plots_dir = args.plots_dir or os.path.join(args.results_dir, "plots")
    policies = list(dict.fromkeys([args.dsb_policy, "lru", "brrip"]))
    metrics = [args.metric] if args.metric else ALL_METRICS

    if args.l2_size:
        l2_sizes = [args.l2_size]
    else:
        l2_sizes = discover_l2_sizes(args.results_dir)

    if not l2_sizes:
        print(f"No L2 size directories found in {args.results_dir}")
        sys.exit(1)

    if args.output and (len(metrics) > 1 or len(l2_sizes) > 1):
        print("--output can only be used with one metric and one L2 size.")
        sys.exit(1)

    plots_created = 0

    for metric in metrics:
        for l2_size in l2_sizes:
            output_path = args.output or default_output_path(plots_dir, metric, l2_size)
            data = load_data(
                args.results_dir,
                l2_size,
                policies,
                metric,
                benchmark_filter=args.benchmarks,
            )

            if save_plot(data, policies, metric, l2_size, output_path):
                plots_created += 1
            else:
                print(f"No results found for {metric} in {args.results_dir}/{l2_size}/")

    if plots_created == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
