import csv
import os
import re

RESULTS_DIR = "/workspace/results_warmup"
SIZES = ["512kB", "1MB", "2MB", "4MB"]
POLICIES = ["dsb", "lru", "brrip"]
BENCHMARKS = ["omnetpp", "mcf", "xalancbmk", "perlbench", "leela", "exchange2",
              "deepsjeng", "xz", "lbm", "imagick", "nab"]

def parse_stats(path):
    stats = {}
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return None
    with open(path) as f:
        for line in f:
            for key in ["system.l2.demandMissRate::total", "system.l2.replacements ",
                        "system.l2.demandHits::total", "system.l2.demandMisses::total",
                        "simInsts", "hostSeconds"]:
                if key in line:
                    parts = line.split()
                    if len(parts) >= 2:
                        stats[key.strip()] = parts[1]
    return stats

# Generate CSV
csv_path = "/workspace/results_warmup/all_results_warmup.csv"
with open(csv_path, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["l2_size", "policy", "benchmark", "miss_rate", "replacements",
                     "demand_hits", "demand_misses", "sim_insts", "host_seconds"])
    for size in SIZES:
        for policy in POLICIES:
            for bench in BENCHMARKS:
                stats = parse_stats(f"{RESULTS_DIR}/{size}/{policy}/{bench}/stats.txt")
                if stats:
                    writer.writerow([
                        size, policy, bench,
                        stats.get("system.l2.demandMissRate::total", ""),
                        stats.get("system.l2.replacements", ""),
                        stats.get("system.l2.demandHits::total", ""),
                        stats.get("system.l2.demandMisses::total", ""),
                        stats.get("simInsts", ""),
                        stats.get("hostSeconds", ""),
                    ])
print(f"CSV written to {csv_path}")

# Generate visualization
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# Parse data into structure
data = {}  # data[size][policy][bench] = miss_rate
for size in SIZES:
    data[size] = {}
    for policy in POLICIES:
        data[size][policy] = {}
        for bench in BENCHMARKS:
            stats = parse_stats(f"{RESULTS_DIR}/{size}/{policy}/{bench}/stats.txt")
            if stats and "system.l2.demandMissRate::total" in stats:
                data[size][policy][bench] = float(stats["system.l2.demandMissRate::total"])

# Filter out benchmarks with MR=1.0 across all (thrashing)
useful_benchmarks = []
for bench in BENCHMARKS:
    all_one = all(
        data.get(s, {}).get(p, {}).get(bench, 1.0) >= 0.99
        for s in SIZES for p in POLICIES
    )
    if not all_one:
        useful_benchmarks.append(bench)

colors = {"dsb": "#2196F3", "lru": "#FF9800", "brrip": "#4CAF50"}

# Plot 1: Grouped bar chart per L2 size
fig, axes = plt.subplots(2, 2, figsize=(18, 12))
fig.suptitle("L2 Demand Miss Rate by Policy and Cache Size (with warmup)", fontsize=16, fontweight="bold")

for idx, size in enumerate(SIZES):
    ax = axes[idx // 2][idx % 2]
    x = np.arange(len(useful_benchmarks))
    width = 0.25
    
    for i, policy in enumerate(POLICIES):
        rates = [data[size][policy].get(b, 0) for b in useful_benchmarks]
        bars = ax.bar(x + i * width, rates, width, label=policy.upper(), color=colors[policy], alpha=0.85)
    
    ax.set_xlabel("Benchmark")
    ax.set_ylabel("L2 Miss Rate")
    ax.set_title(f"L2 = {size}")
    ax.set_xticks(x + width)
    ax.set_xticklabels(useful_benchmarks, rotation=45, ha="right", fontsize=9)
    ax.legend()
    ax.set_ylim(0, 1.05)
    ax.grid(axis="y", alpha=0.3)

plt.tight_layout()
fig.savefig("/workspace/results_warmup/miss_rate_by_size.png", dpi=150, bbox_inches="tight")
print("Plot 1 saved: miss_rate_by_size.png")

# Plot 2: Miss rate vs cache size for each benchmark
fig2, axes2 = plt.subplots(3, 3, figsize=(16, 14))
fig2.suptitle("L2 Miss Rate vs Cache Size per Benchmark (with warmup)", fontsize=16, fontweight="bold")

size_labels = SIZES
for idx, bench in enumerate(useful_benchmarks):
    if idx >= 9:
        break
    ax = axes2[idx // 3][idx % 3]
    for policy in POLICIES:
        rates = [data[s][policy].get(bench, None) for s in SIZES]
        ax.plot(size_labels, rates, "o-", label=policy.upper(), color=colors[policy], linewidth=2, markersize=6)
    ax.set_title(bench, fontweight="bold")
    ax.set_xlabel("L2 Size")
    ax.set_ylabel("Miss Rate")
    ax.legend(fontsize=8)
    ax.grid(alpha=0.3)

# Hide unused subplots
for idx in range(len(useful_benchmarks), 9):
    axes2[idx // 3][idx % 3].set_visible(False)

plt.tight_layout()
fig2.savefig("/workspace/results_warmup/miss_rate_vs_size.png", dpi=150, bbox_inches="tight")
print("Plot 2 saved: miss_rate_vs_size.png")

# Plot 3: DSB improvement over LRU
fig3, ax3 = plt.subplots(figsize=(14, 6))
x = np.arange(len(useful_benchmarks))
width = 0.2

for i, size in enumerate(SIZES):
    improvements = []
    for bench in useful_benchmarks:
        lru_mr = data[size]["lru"].get(bench, 0)
        dsb_mr = data[size]["dsb"].get(bench, 0)
        if lru_mr > 0:
            imp = (lru_mr - dsb_mr) / lru_mr * 100
        else:
            imp = 0
        improvements.append(imp)
    ax3.bar(x + i * width, improvements, width, label=f"L2={size}", alpha=0.85)

ax3.set_xlabel("Benchmark")
ax3.set_ylabel("Miss Rate Reduction vs LRU (%)")
ax3.set_title("DSB Improvement over LRU (positive = DSB better)", fontsize=14, fontweight="bold")
ax3.set_xticks(x + 1.5 * width)
ax3.set_xticklabels(useful_benchmarks, rotation=45, ha="right")
ax3.axhline(y=0, color="black", linewidth=0.8)
ax3.legend()
ax3.grid(axis="y", alpha=0.3)

plt.tight_layout()
fig3.savefig("/workspace/results_warmup/dsb_vs_lru.png", dpi=150, bbox_inches="tight")
print("Plot 3 saved: dsb_vs_lru.png")
