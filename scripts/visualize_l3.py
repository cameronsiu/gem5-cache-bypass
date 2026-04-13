#!/usr/bin/env python3
"""
Create simple benchmark comparison plots from gem5 L3 results.

Reads:
    /workspace/results_l3/<l3_size>/<policy>/<benchmark>/stats.txt

Default output:
    /workspace/results_l3/plots/<metric>/<l3_size>.png
    /workspace/results_l3/plots/<metric>/summary.csv

Examples:
    python3 scripts/visualize_l3.py
    python3 scripts/visualize_l3.py --metric ipc
    python3 scripts/visualize_l3.py --l3-size 2MB
    python3 scripts/visualize_l3.py --dsb-policy dsb-bc2
"""

import argparse
import csv
import math
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = "/workspace/results_l3"
PLOTS_DIR = os.path.join(RESULTS_DIR, "plots")
DEFAULT_BENCHMARK_ORDER = [
    "xalancbmk",
    "roms",
    "wrf",
    "omnetpp",
    "mcf",
    "imagick",
    "cam4",
    "gcc",
    "pop2",
    "lbm", 
    "perlbench",
    "nab",
    "x264",
    "leela",
    "deepsjeng",
    "exchange2",
    "xz",
    "fotonik3d",
    "bwaves",
]
DEFAULT_L3_ORDER = ["1MB", "2MB", "4MB"]

METRICS = {
    "ipc": {
        "label": "IPC",
        "folder": "ipc",
        "rate": False,
    },
    "miss-rate": {
        "label": "L3 Miss Rate",
        "folder": "miss_rate",
        "rate": True,
    },
    "mpki": {
        "label": "L3 MPKI",
        "folder": "mpki",
        "rate": False,
    },
    "l3-hits": {
        "label": "L3 Hits",
        "folder": "l3_hits",
        "rate": False,
    },
    "l3-total-accesses": {
        "label": "L3 Total Accesses",
        "folder": "l3_total_accesses",
        "rate": False,
    },
    "l3-replacements": {
        "label": "L3 Replacements",
        "folder": "l3_replacements",
        "rate": False,
    },
    "l2-miss-rate": {
        "label": "L2 Miss Rate",
        "folder": "l2_miss_rate",
        "rate": True,
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
    "sim_insts": "system.switch_cpus_1.commitStats0.numInsts",
    "l3_misses": "system.l3.demandMisses::switch_cpus_1.data",
    "l3_miss_rate": "system.l3.demandMissRate::switch_cpus_1.data",
    "l3_hits": "system.l3.demandHits::switch_cpus_1.data",
    "l3_total_accesses": "system.l3.demandAccesses::switch_cpus_1.data",
    "l3_replacements": "system.l3.replacements",
    "l2_miss_rate": "system.l2.demandMissRate::switch_cpus_1.data",
    "l1d_miss_rate": "system.cpu.dcache.demandMissRate::switch_cpus_1.data",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Simple L3 result plotter")
    parser.add_argument("--results-dir", default=RESULTS_DIR)
    parser.add_argument(
        "--plots-dir",
        default=None,
        help="Base output directory for generated plots. Default: <results_dir>/plots",
    )
    parser.add_argument(
        "--l3-size",
        default=None,
        help="Plot one L3 size only. Default: generate plots for all discovered sizes.",
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
        help="Output path for a single metric and single L3 size only.",
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
        misses = stats.get(STAT_KEYS["l3_misses"])
        insts = stats.get(STAT_KEYS["sim_insts"])
        if misses is None or insts in (None, 0):
            return None
        return (misses * 1000.0) / insts

    if metric == "miss-rate":
        return stats.get(STAT_KEYS["l3_miss_rate"])

    if metric == "l3-hits":
        return stats.get(STAT_KEYS["l3_hits"])

    if metric == "l3-total-accesses":
        return stats.get(STAT_KEYS["l3_total_accesses"])

    if metric == "l3-replacements":
        return stats.get(STAT_KEYS["l3_replacements"])

    if metric == "l2-miss-rate":
        return stats.get(STAT_KEYS["l2_miss_rate"])

    if metric == "l1d-miss-rate":
        return stats.get(STAT_KEYS["l1d_miss_rate"])

    return None


def benchmark_sort_key(name):
    try:
        return (0, DEFAULT_BENCHMARK_ORDER.index(name))
    except ValueError:
        return (1, name)


def l3_sort_key(name):
    try:
        return (0, DEFAULT_L3_ORDER.index(name))
    except ValueError:
        return (1, name)


def discover_l3_sizes(results_dir):
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

    return sorted(sizes, key=l3_sort_key)


def policy_color(policy):
    policy_colors = {
        "lru": "#92A3B3",
        "brrip": "#69FD52",
        "random": "#FFA1A1",
        "tree_plru": "#FFE1B8",
        "ship_mem": "#F8B0FF",
        "fifo": "tab:purple",
        "lfu": "tab:brown",
        "mru": "tab:pink",
        "bip": "tab:gray",
        "second_chance": "tab:olive",
        "weighted_lru": "tab:cyan",
        "ship_pc": "#c5b0d5",
        "policy1Config1": "#1D4ED8",  # strongest blue
        "policy0Config1": "#2563EB",
        "policy1Config2": "#60A5FA",
        "policy1Config3": "#93C5FD",  # lightest blue
        "policy0Config2": "#8fbaff",
        "policy0Config3": "#003488",
    }

    if policy.startswith("dsb"):
        return "tab:blue"

    return policy_colors.get(policy, "tab:gray")


def load_data(results_dir, l3_size, policies, metric, benchmark_filter=None):
    size_dir = os.path.join(results_dir, l3_size)
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


def get_present_data(data, policies):
    benchmarks = sorted(
        {bench for policy_data in data.values() for bench in policy_data},
        key=benchmark_sort_key,
    )
    present_policies = [policy for policy in policies if policy in data]

    return benchmarks, present_policies


def save_metric_csv(metric_data, policies, output_path):
    present_policies = [
        policy
        for policy in policies
        if any(policy in data for data in metric_data.values())
    ]

    if not metric_data or not present_policies:
        return False

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    with open(output_path, "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["l3_size", "benchmark", *present_policies])

        for l3_size in sorted(metric_data, key=l3_sort_key):
            benchmarks, _ = get_present_data(metric_data[l3_size], policies)
            for bench in benchmarks:
                row = [l3_size, bench]
                for policy in present_policies:
                    value = metric_data[l3_size].get(policy, {}).get(bench)
                    row.append("" if value is None else value)
                writer.writerow(row)

    print(f"Saved CSV to {output_path}")
    return True


def save_plot(data, policies, metric, l3_size, output_path):
    benchmarks, present_policies = get_present_data(data, policies)

    if not benchmarks or not present_policies:
        return False

    x = np.arange(len(benchmarks))
    width = 0.8 / len(present_policies)
    fig, ax = plt.subplots(figsize=(max(10, len(benchmarks) * 1.2), 5))

    for index, policy in enumerate(present_policies):
        offset = (index - (len(present_policies) - 1) / 2) * width
        values = [data.get(policy, {}).get(bench, np.nan) for bench in benchmarks]
        policy_label = policy
        if policy == "lru":
            policy_label = "LRU"
        elif policy == "brrip":
            policy_label = "BRRIP"
        elif policy == "random":
            policy_label = "Random"
        elif policy == "ship_mem":
            policy_label = "SHiP"
        elif policy == "tree_plru":
            policy_label = "Pseudo-LRU"
        elif policy == "policy0Config1":
            policy_label = "Bypassing"
        # elif policy == "policy0Config2":
            # policy_label = "Policy0 Config2"
        # elif policy == "policy0Config3":
            # policy_label = "Policy0 Config3"
        elif policy == "policy1Config1":
            policy_label = "Aging"
        elif policy == "policy1Config2":
            policy_label = "Bypassing|Aging"
        elif policy == "policy1Config3":
            policy_label = "Bypassing|Aging|RandomPromotion"
        ax.bar(
            x + offset,
            values,
            width=width,
            label=policy_label,
            color=policy_color(policy),
        )

    ax.set_title(f"{METRICS[metric]['label']} Comparison ({l3_size})")
    ax.set_ylabel(METRICS[metric]["label"])
    ax.set_xticks(x)
    ax.set_xticklabels(benchmarks, rotation=45, ha="right")
    ax.legend(
        loc="upper right",
        bbox_to_anchor=(0.98, 0.98),
        borderaxespad=0.2,
    )
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
    print(f"Saved {metric} ({l3_size}) plot to {output_path}")
    return True


def default_output_path(plots_dir, metric, l3_size):
    return os.path.join(plots_dir, METRICS[metric]["folder"], f"{l3_size}.png")


def default_metric_csv_path(plots_dir, metric):
    return os.path.join(plots_dir, METRICS[metric]["folder"], "summary.csv")


def csv_path_for_output(output_path):
    base, _ = os.path.splitext(output_path)
    return f"{base}.csv"


def main():
    args = parse_args()
    plots_dir = args.plots_dir or os.path.join(args.results_dir, "plots")
    policies = list(
        dict.fromkeys(
            [
                args.dsb_policy,
                "lru",
                "brrip",
                "random",
                # "fifo",
                # "lfu",
                # "mru",
                # "bip",
                # "second_chance",
                # "weighted_lru",
                "tree_plru",
                "ship_mem",
                # "ship_pc",
                "policy1Config1", # Aging
                "policy0Config1", # Bypassing
                # "policy0Config2", # Dup
                # "policy0Config3", # Dup
                "policy1Config2", # Bypassing Aging
                "policy1Config3", # Bypassing Aging Random promotion
            ]
        )
    )
    metrics = [args.metric] if args.metric else ALL_METRICS

    if args.l3_size:
        l3_sizes = [args.l3_size]
    else:
        l3_sizes = discover_l3_sizes(args.results_dir)

    if not l3_sizes:
        print(f"No L3 size directories found in {args.results_dir}")
        sys.exit(1)

    if args.output and (len(metrics) > 1 or len(l3_sizes) > 1):
        print("--output can only be used with one metric and one L3 size.")
        sys.exit(1)

    plots_created = 0

    for metric in metrics:
        metric_data = {}

        for l3_size in l3_sizes:
            output_path = args.output or default_output_path(plots_dir, metric, l3_size)
            data = load_data(
                args.results_dir,
                l3_size,
                policies,
                metric,
                benchmark_filter=args.benchmarks,
            )
            if data:
                metric_data[l3_size] = data

            if save_plot(data, policies, metric, l3_size, output_path):
                plots_created += 1
            else:
                print(f"No results found for {metric} in {args.results_dir}/{l3_size}/")

        if args.output:
            csv_path = csv_path_for_output(args.output)
        else:
            csv_path = default_metric_csv_path(plots_dir, metric)

        save_metric_csv(metric_data, policies, csv_path)

    if plots_created == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
