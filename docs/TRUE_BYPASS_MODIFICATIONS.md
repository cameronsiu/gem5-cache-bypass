# DSB True Bypass Implementation — Modification Guide

This document describes all changes made to enable true cache bypass in the DSB (Dueling Segmented LRU with Adaptive Bypassing) replacement policy on gem5 v23.0.0.1.

## Overview

Previously, DSB's bypass was a "soft bypass" — it set a flag (`startBypass`) and deferred learning the bypassed line's tag until `reset()`. But with true bypass, `reset()` is never called for the bypassed line (it goes to `tempBlock` instead), so competitor tracking was broken.

The fix uses gem5's existing `shouldBypass` mechanism on `ReplacementData` and adds a new `notifyBypass()` callback so the replacement policy can learn the bypassed line's tag.

## Files Modified

### 1. gem5 Internals (under `/opt/gem5/src/mem/cache/`)

These modified files are stored in `/workspace/src/gem5_patches/` and are automatically copied by `build_dsb.sh`.

#### `replacement_policies/base.hh` → `gem5_patches/replacement_policies_base.hh`

**Change:** Added a virtual `notifyBypass` method with an empty default body.

**Location:** In the `public` section of `class Base`, before `instantiateEntry()`.

```cpp
virtual void notifyBypass(
    const std::shared_ptr<ReplacementData>& replacement_data,
    Addr bypassedTag) {};
```

**Why:** Provides a hook for replacement policies to receive the bypassed line's tag. The empty default body means existing policies (LRU, FIFO, etc.) are unaffected.

---

#### `tags/base.hh` → `gem5_patches/tags_base.hh`

**Change:** Added a virtual `notifyBypass` method with an empty default body.

**Location:** In the `public` section of `class BaseTags`, before `anyBlk()`.

```cpp
virtual void notifyBypass(CacheBlk* victim, Addr addr) {}
```

**Why:** `BaseCache` holds a `BaseTags*` pointer. This virtual method allows `BaseCache::allocateBlock()` to call `tags->notifyBypass()` polymorphically, dispatching to `BaseSetAssoc`'s override.

---

#### `tags/base_set_assoc.hh` → `gem5_patches/tags_base_set_assoc.hh`

**Change:** Added `notifyBypass` override that extracts the tag and forwards to the replacement policy.

**Location:** Before `moveBlock()`.

```cpp
void notifyBypass(CacheBlk* victim, Addr addr) override
{
    Addr tag = indexingPolicy->extractTag(addr);
    replacementPolicy->notifyBypass(victim->replacementData, tag);
}
```

**Why:** `BaseSetAssoc` has access to both `indexingPolicy` (to extract the tag from the address) and `replacementPolicy` (to forward the notification). This bridges the gap between the cache (which knows the address) and the replacement policy (which needs the tag).

---

#### `base.cc` → `gem5_patches/cache_base.cc`

**Change:** Added one line inside the `shouldBypass` block of `allocateBlock()`.

**Location:** In `BaseCache::allocateBlock()`, inside the `if (victim->replacementData->shouldBypass)` block, before `return nullptr`.

```cpp
tags->notifyBypass(victim, addr);
```

**Why:** When bypass fires, the replacement policy needs to know the tag of the line that was bypassed (the incoming address). This call passes that information back through the tags layer.

---

### 2. DSB Files (under `/workspace/src/replacement_policies/`)

#### `dsb_rp.hh`

**Change:** Added `notifyBypass` override declaration.

```cpp
void notifyBypass(const std::shared_ptr<ReplacementData>& replacement_data,
                  Addr bypassedTag) override;
```

---

#### `dsb_rp.cc`

Four changes were made:

##### a) `getVictim()` — Set `shouldBypass` on real bypass

The bypass decision now sets `shouldBypass = true` on the victim's replacement data, which triggers gem5's built-in bypass mechanism in `allocateBlock()`. The nested `if/else` was flattened to `if/else if/else`.

```cpp
// bypass
if (random_mt.random<unsigned>(1, 1u << bypass_counter) == 1) {
    // True bypass: tell allocateBlock to skip insertion
    std::static_pointer_cast<DSBReplData>(
        victim->replacementData)->shouldBypass = true;

    competitorInfo.competitorValid = true;
    competitorInfo.startBypass = true;     // tag will arrive via notifyBypass()
    competitorInfo.competitorWay = victimWay;
    competitorInfo.isVirtualBypass = false;
} else if (random_mt.random<unsigned>(1, 1u << virtual_bypass_counter) == 1) {
    // Virtual bypass: normal insertion, but track as if bypassed
    competitorInfo.competitorValid = true;
    competitorInfo.startBypass = false;
    competitorInfo.competitorTag = static_cast<TaggedEntry*>(victim)->getTag();
    competitorInfo.competitorWay = victimWay;
    competitorInfo.isVirtualBypass = true;
} else {
    // No bypass, no tracking
    competitorInfo.competitorValid = false;
}
```

The `TODO: Change the gem5 internals to bypass` comment was removed.

##### b) `reset()` — Removed `startBypass` tag capture

The `startBypass` branch was removed from `reset()`. With true bypass, `reset()` is never called for the bypassed line — `notifyBypass()` handles the tag capture instead.

Before:
```cpp
if (competitorInfo.startBypass) {
    competitorInfo.competitorTag = tag;
    competitorInfo.startBypass = false;
} else if (tag == competitorInfo.competitorTag) { ... }
```

After:
```cpp
if (tag == competitorInfo.competitorTag) {
    // Resolution: bypassed/evicted line came back as a miss
    ...
}
```

##### c) `invalidate()` — Cancel stale tracking

Added logic to cancel an active competitor tracking episode if the tracked line (`competitorWay`) gets invalidated by some other mechanism before resolution.

```cpp
ReplaceableEntry* entry = replData->entry;
if (entry != NULL) {
    uint32_t set = entry->getSet();
    uint32_t way = entry->getWay();
    CompetitorInfo& info = competitorMap[set];
    if (info.competitorValid && way == info.competitorWay) {
        info.competitorValid = false;
    }
}
```

##### d) New `notifyBypass()` method

Receives the bypassed line's tag from `allocateBlock` and stores it in the competitor tracking info.

```cpp
void DSB::notifyBypass(
    const std::shared_ptr<ReplacementData>& replacement_data,
    Addr bypassedTag)
{
    auto replData = std::static_pointer_cast<DSBReplData>(replacement_data);
    ReplaceableEntry* entry = replData->entry;
    if (entry != NULL) {
        uint32_t set = entry->getSet();
        CompetitorInfo& info = competitorMap[set];
        if (info.competitorValid && info.startBypass) {
            info.competitorTag = bypassedTag;
            info.startBypass = false;
        }
    }
}
```

---

### 3. Build Script

#### `scripts/build_dsb.sh`

Updated to also copy the four gem5 patch files from `src/gem5_patches/` into the gem5 source tree before building.

---

### 4. Configuration

#### `DSBRP.py`

**Change:** Added runtime-configurable parameters as gem5 `Param.Int` fields.

```python
bypass_counter = Param.Int(6, "Initial bypass counter (log2 of denominator)")
virtual_bypass_counter = Param.Int(4, "Virtual bypass counter (log2)")
random_promotion = Param.Int(0, "Random promotion to referenced on insert (log2)")
```

**Why:** Allows sweeping DSB parameters without recompiling gem5.

#### `dsb_rp.hh`

**Additional change:** Hardcoded constants replaced with member variables initialized from params.

```cpp
const int randomPromotion;
mutable int bypass_counter;
const int virtual_bypass_counter;
```

#### `dsb_rp.cc`

**Additional change:** Constructor reads from params object.

```cpp
DSB::DSB(const Params &p)
  : Base(p),
    randomPromotion(p.random_promotion),
    bypass_counter(p.bypass_counter),
    virtual_bypass_counter(p.virtual_bypass_counter)
{
}
```

---

## Runtime Configuration

#### `configs/run_spec.py`

**Key behaviors:**
- Extracts `--dsb-bypass-counter`, `--dsb-virtual-bypass-counter`, `--dsb-random-promotion` flags from the command line and passes them as kwargs to the DSB SimObject constructor.
- Only applies the replacement policy to L2 (the LLC). L1I and L1D stay on default LRU for fair comparison.
- Disables snoop filters on both `tol2bus` and `membus` (required for true bypass, see below).

---

## Important Compatibility Notes

### Snoop Filter Incompatibility

True bypass causes `allocateBlock()` to return `nullptr`, sending data to `tempBlock` instead of the cache. However, gem5's snoop filter still tracks the cache as a holder of that address. When a snoop arrives for a bypassed line, `snoop_filter.cc:144` panics because it finds no matching entry.

**Fix:** Disable snoop filters in `run_spec.py`. This is safe because snoop filters are not needed in single-core SE (syscall emulation) mode:

```python
from m5.params import NULL
if hasattr(system, 'tol2bus'):
    system.tol2bus.snoop_filter = NULL
if hasattr(system, 'membus'):
    system.membus.snoop_filter = NULL
```

### L2-Only Policy Application

The replacement policy must only be applied to L2 (the LLC), not L1I or L1D. Applying DSB or other non-LRU policies to L1 causes catastrophic L1D miss rates (e.g., mcf L1D miss rate jumps from 0.6% to 5.6%), which inflates L2 traffic and distorts all downstream metrics.

### IPC Stats After Fast-Forward

After fast-forward, the O3 CPU stats are under `system.switch_cpus`, not `system.cpu`. The atomic fast-forward CPU's `system.cpu.ipc` shows `nan` because it had 0 cycles in the detailed simulation region. Use `system.switch_cpus.ipc` for benchmarks that use fast-forward.

---

## Files NOT Changed

- `CompetitorInfo` struct — `startBypass` field is retained (used as a flag that `notifyBypass` checks/clears)
- `touch()` — Logic remains correct for both real and virtual bypass
- `SConscript` — No new source files
- `replaceable_entry.hh` — `shouldBypass` field already existed

---

## How to Apply on Another Machine

1. Clone the workspace repository
2. Ensure gem5 v23.0.0.1 is installed at `/opt/gem5`
3. Run the build script:
   ```bash
   bash scripts/build_dsb.sh
   ```
   This copies both the DSB files and the gem5 patches, then rebuilds gem5.

## How to Verify

1. The build completes without errors
2. Run a simulation with the CacheRepl debug flag to see bypass events:
   ```bash
   /opt/gem5/build/X86/gem5.opt --debug-flags=CacheRepl ...
   grep "Bypassing insertion" m5out/debug.log
   ```
3. Check that stats show non-zero bypass events (lower L2 replacements compared to LRU)
4. Compare LLC miss rates against a pure LRU baseline
5. To sweep parameters without recompiling:
   ```bash
   bash scripts/sweep_dsb.sh
   ```
