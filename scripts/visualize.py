#!/usr/bin/env python3
"""
Visualize gem5 benchmark results across replacement policies.

Usage:
    python3 scripts/visualize.py                        # all policies & benchmarks at 2MB
    python3 scripts/visualize.py --l2-size 1MB          # results for 1MB L2
    python3 scripts/visualize.py --policies lru brrip   # specific policies
    python3 scripts/visualize.py --benchmarks lbm mcf   # specific benchmarks
    python3 scripts/visualize.py --output results.png   # custom output path

    # Cross-size comparison: given policy(ies) across all available L2 sizes
    python3 scripts/visualize.py --cross-size --policies dsb lru --benchmarks mcf omnetpp

Reads from: /workspace/results/<l2_size>/<policy>/<benchmark>/stats.txt
Outputs:    /workspace/results/<l2_size>/comparison.png (default)
"""

import argparse
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


RESULTS_DIR = "/workspace/results"

# Stats to extract -- (stat_name_in_file, display_label, higher_is_better)
# After fast-forward, the O3 CPU is "system.switch_cpus" not "system.cpu".
# Cache stats (dcache, l2) are shared objects and work with either prefix.
STATS = [
    ("system.cpu.ipc",                              "IPC",                  True),
    ("system.cpu.dcache.demandMissRate::total",      "L1D Miss Rate",        False),
    ("system.l2.demandMissRate::total",              "L2 Miss Rate",         False),
    ("system.cpu.dcache.demandAvgMissLatency::total","L1D Avg Miss Latency", False),
    ("system.l2.demandAvgMissLatency::total",        "L2 Avg Miss Latency",  False),
    ("system.l2.replacements",                       "L2 Replacements",      False),
]

# When fast-forward is used, some stats move to system.switch_cpus.
# Map canonical stat name -> fallback stat name.
_FALLBACKS = {
    "system.cpu.ipc": "system.switch_cpus.ipc",
}


def parse_stats(stats_path):
    """Parse a gem5 stats.txt and return a dict of stat_name -> float value."""
    import math
    results = {}
    stat_names = {s[0] for s in STATS}
    fallback_names = set(_FALLBACKS.values())
    all_names = stat_names | fallback_names
    raw = {}
    try:
        with open(stats_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or line.startswith("---"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[0] in all_names:
                    try:
                        val = float(parts[1])
                        if not math.isnan(val):
                            raw[parts[0]] = val
                    except ValueError:
                        pass
    except FileNotFoundError:
        pass
    # Resolve: prefer primary stat, fall back to switch_cpus variant
    for stat_name, _, _ in STATS:
        if stat_name in raw:
            results[stat_name] = raw[stat_name]
        elif stat_name in _FALLBACKS and _FALLBACKS[stat_name] in raw:
            results[stat_name] = raw[_FALLBACKS[stat_name]]
    return results


def discover_results(results_dir, l2_size, filter_policies=None, filter_benchmarks=None):
    """Scan results/<l2_size>/ and return {policy: {benchmark: {stat: value}}}."""
    data = {}
    size_dir = os.path.join(results_dir, l2_size)
    if not os.path.isdir(size_dir):
        return data

    for policy in sorted(os.listdir(size_dir)):
        policy_dir = os.path.join(size_dir, policy)
        if not os.path.isdir(policy_dir):
            continue
        if filter_policies and policy not in filter_policies:
            continue

        for bench in sorted(os.listdir(policy_dir)):
            bench_dir = os.path.join(policy_dir, bench)
            stats_path = os.path.join(bench_dir, "stats.txt")
            if not os.path.isfile(stats_path):
                continue
            if filter_benchmarks and bench not in filter_benchmarks:
                continue

            parsed = parse_stats(stats_path)
            if parsed:
                data.setdefault(policy, {})[bench] = parsed

    return data


def discover_all_sizes(results_dir):
    """Return list of L2 size directories found under results/."""
    sizes = []
    if not os.path.isdir(results_dir):
        return sizes
    for entry in sorted(os.listdir(results_dir)):
        entry_path = os.path.join(results_dir, entry)
        if os.path.isdir(entry_path) and not entry.startswith("."):
            # Check if it looks like a size dir (contains policy subdirs with stats)
            for sub in os.listdir(entry_path):
                sub_path = os.path.join(entry_path, sub)
                if os.path.isdir(sub_path):
                    sizes.append(entry)
                    break
    return sizes


def plot_results(data, output_path, l2_size):
    """Create a multi-panel bar chart comparing policies across benchmarks."""
    if not data:
        print("No results found to plot.")
        sys.exit(1)

    policies = sorted(data.keys())
    # Collect all benchmarks that appear in any policy
    all_benchmarks = sorted({b for p in data.values() for b in p.keys()})

    if not all_benchmarks:
        print("No benchmark data found.")
        sys.exit(1)

    # Filter to stats that have at least some data
    active_stats = []
    for stat_key, label, hib in STATS:
        has_data = False
        for pol in policies:
            for bench in all_benchmarks:
                if stat_key in data.get(pol, {}).get(bench, {}):
                    has_data = True
                    break
            if has_data:
                break
        if has_data:
            active_stats.append((stat_key, label, hib))

    n_stats = len(active_stats)
    if n_stats == 0:
        print("No matching stats found in results.")
        sys.exit(1)

    fig, axes = plt.subplots(n_stats, 1, figsize=(max(8, len(all_benchmarks) * 2.5), 4 * n_stats))
    if n_stats == 1:
        axes = [axes]

    colors = plt.cm.Set2(np.linspace(0, 1, max(len(policies), 3)))
    bar_width = 0.8 / len(policies)

    for ax_idx, (stat_key, label, higher_is_better) in enumerate(active_stats):
        ax = axes[ax_idx]
        x = np.arange(len(all_benchmarks))

        for pol_idx, policy in enumerate(policies):
            values = []
            for bench in all_benchmarks:
                val = data.get(policy, {}).get(bench, {}).get(stat_key, 0)
                values.append(val)

            offset = (pol_idx - len(policies) / 2 + 0.5) * bar_width
            bars = ax.bar(x + offset, values, bar_width,
                         label=policy.upper(), color=colors[pol_idx],
                         edgecolor="white", linewidth=0.5)

            # Add value labels on bars
            for bar, val in zip(bars, values):
                if val == 0:
                    continue
                if val >= 1_000_000:
                    text = f"{val/1_000_000:.1f}M"
                elif val >= 1000:
                    text = f"{val/1000:.1f}K"
                elif val < 0.01:
                    text = f"{val:.4f}"
                elif val < 1:
                    text = f"{val:.3f}"
                else:
                    text = f"{val:.2f}"
                ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(),
                       text, ha="center", va="bottom", fontsize=7, rotation=0)

        ax.set_ylabel(label, fontsize=10)
        ax.set_xticks(x)
        ax.set_xticklabels(all_benchmarks, fontsize=10)
        ax.legend(fontsize=8, loc="upper right")
        ax.grid(axis="y", alpha=0.3)

        direction = "higher is better" if higher_is_better else "lower is better"
        ax.set_title(f"{label}  ({direction})", fontsize=11, fontweight="bold")

    fig.suptitle(f"gem5 Benchmark Results \u2014 {l2_size} LLC",
                 fontsize=14, fontweight="bold", y=1.01)
    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight", facecolor="white")
    print(f"Saved plot to {output_path}")

    print_table(data, policies, all_benchmarks, active_stats)


def plot_cross_size(results_dir, filter_policies, filter_benchmarks, output_path):
    """Plot metrics across L2 sizes for given policies and benchmarks."""
    sizes = discover_all_sizes(results_dir)
    if not sizes:
        print(f"No L2 size directories found under {results_dir}/")
        sys.exit(1)

    # Collect data for all sizes
    all_data = {}  # {size: {policy: {bench: {stat: val}}}}
    for sz in sizes:
        data = discover_results(results_dir, sz, filter_policies, filter_benchmarks)
        if data:
            all_data[sz] = data

    if not all_data:
        print("No results found for cross-size comparison.")
        sys.exit(1)

    available_sizes = sorted(all_data.keys(), key=_size_sort_key)
    policies = sorted({p for d in all_data.values() for p in d.keys()})
    benchmarks = sorted({b for d in all_data.values() for p in d.values() for b in p.keys()})

    if not benchmarks:
        print("No benchmark data found.")
        sys.exit(1)

    # Focus on IPC and L2 miss rate for cross-size
    cross_stats = [
        ("system.cpu.ipc", "IPC", True),
        ("system.l2.demandMissRate::total", "L2 Miss Rate", False),
    ]

    n_benchmarks = len(benchmarks)
    n_stats = len(cross_stats)
    fig, axes = plt.subplots(n_stats, n_benchmarks,
                             figsize=(5 * n_benchmarks, 4 * n_stats),
                             squeeze=False)

    colors = plt.cm.Set2(np.linspace(0, 1, max(len(policies), 3)))

    for stat_idx, (stat_key, label, higher_is_better) in enumerate(cross_stats):
        for bench_idx, bench in enumerate(benchmarks):
            ax = axes[stat_idx][bench_idx]

            for pol_idx, policy in enumerate(policies):
                x_vals = []
                y_vals = []
                for sz in available_sizes:
                    val = all_data.get(sz, {}).get(policy, {}).get(bench, {}).get(stat_key)
                    if val is not None:
                        x_vals.append(sz)
                        y_vals.append(val)

                if x_vals:
                    ax.plot(range(len(x_vals)), y_vals, 'o-',
                           label=policy.upper(), color=colors[pol_idx],
                           markersize=6, linewidth=2)
                    ax.set_xticks(range(len(x_vals)))
                    ax.set_xticklabels(x_vals, fontsize=9)

            ax.set_xlabel("L2 Size", fontsize=9)
            ax.set_ylabel(label, fontsize=9)
            direction = "\u2191" if higher_is_better else "\u2193"
            ax.set_title(f"{bench} \u2014 {label} ({direction})", fontsize=10, fontweight="bold")
            ax.legend(fontsize=8)
            ax.grid(alpha=0.3)

    fig.suptitle("Cross-Size Comparison", fontsize=14, fontweight="bold", y=1.02)
    fig.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches="tight", facecolor="white")
    print(f"Saved cross-size plot to {output_path}")


def _size_sort_key(s):
    """Sort size strings numerically: 512kB < 1MB < 2MB < 4MB."""
    s_lower = s.lower()
    if s_lower.endswith("kb"):
        return float(s_lower[:-2]) / 1024
    elif s_lower.endswith("mb"):
        return float(s_lower[:-2])
    elif s_lower.endswith("gb"):
        return float(s_lower[:-2]) * 1024
    return 0


def print_table(data, policies, benchmarks, stats):
    """Print a text summary table."""
    print("\n" + "=" * 80)
    print("RESULTS SUMMARY")
    print("=" * 80)

    for stat_key, label, _ in stats:
        print(f"\n{label}:")
        header = f"  {'Benchmark':<14}" + "".join(f"{p.upper():>14}" for p in policies)
        print(header)
        print("  " + "-" * (14 + 14 * len(policies)))
        for bench in benchmarks:
            row = f"  {bench:<14}"
            for pol in policies:
                val = data.get(pol, {}).get(bench, {}).get(stat_key)
                if val is None:
                    row += f"{'N/A':>14}"
                elif val >= 1_000_000:
                    row += f"{val/1_000_000:>13.2f}M"
                elif val >= 1000:
                    row += f"{val/1000:>13.1f}K"
                elif val < 1:
                    row += f"{val:>14.6f}"
                else:
                    row += f"{val:>14.2f}"
            print(row)
    print()


def main():
    parser = argparse.ArgumentParser(description="Visualize gem5 benchmark results")
    parser.add_argument("--policies", nargs="+", default=None,
                       help="Policies to include (default: all found)")
    parser.add_argument("--benchmarks", nargs="+", default=None,
                       help="Benchmarks to include (default: all found)")
    parser.add_argument("--results-dir", default=RESULTS_DIR,
                       help=f"Results directory (default: {RESULTS_DIR})")
    parser.add_argument("--l2-size", default="2MB",
                       help="L2 size subdirectory to read (default: 2MB)")
    parser.add_argument("--output", default=None,
                       help="Output image path (default: <results_dir>/<l2_size>/comparison.png)")
    parser.add_argument("--cross-size", action="store_true",
                       help="Cross-size comparison mode: plot metrics across L2 sizes")
    args = parser.parse_args()

    if args.cross_size:
        output_path = args.output or os.path.join(args.results_dir, "cross_size_comparison.png")
        plot_cross_size(args.results_dir, args.policies, args.benchmarks, output_path)
        return

    output_path = args.output or os.path.join(args.results_dir, args.l2_size, "comparison.png")
    data = discover_results(args.results_dir, args.l2_size, args.policies, args.benchmarks)

    if not data:
        print(f"No results found in {args.results_dir}/{args.l2_size}/")
        print("Expected structure: <results_dir>/<l2_size>/<policy>/<benchmark>/stats.txt")
        sys.exit(1)

    print(f"L2 size: {args.l2_size}")
    print(f"Found policies: {', '.join(sorted(data.keys()))}")
    for pol in sorted(data.keys()):
        print(f"  {pol}: {', '.join(sorted(data[pol].keys()))}")

    plot_results(data, output_path, args.l2_size)


if __name__ == "__main__":
    main()
