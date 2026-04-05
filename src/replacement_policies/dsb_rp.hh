#ifndef __MEM_CACHE_REPLACEMENT_POLICIES_DSB_RP_HH__
#define __MEM_CACHE_REPLACEMENT_POLICIES_DSB_RP_HH__

#include "mem/cache/replacement_policies/base.hh"

namespace gem5
{

struct DSBRPParams;

struct CompetitorInfo {
  bool     competitorValid = false; // whether a bypass episode is currently active
  bool     startBypass = false;     // whether a bypass started
  Addr     competitorTag = 0;   // tag of bypassed line (line that we would have inserted)
  uint32_t competitorWay = 0;   // way of victim line (line that we would have replaced)
  bool     isVirtualBypass = false; // true if we did not bypass, false if we did not
  bool     skipNextInvalidate = false;
};

namespace replacement_policy
{

class DSB : public Base
{
  protected:
    /** DSB-specific implementation of replacement data. */
    struct DSBReplData : ReplacementData
    {
        /** Tick on which the entry was last touched. */
        Tick lastTouchTick;

        // SLRU
        // Referenced-list and non-referenced-list
        // The point of the reference bit is to separate
        // cache lines that have been hit before and have never been hit
        // These unreferenced cache lines will be looked at first to be victims
        // if all lines are referenced, we fall back to LRU
        bool referenceBit;

        ReplaceableEntry* entry;

        bool shouldBypass;
        
        /**
         * Default constructor. Invalidate data.
         */
        DSBReplData() : lastTouchTick(0), referenceBit(0), entry(NULL), shouldBypass(false) {}
    };

    mutable std::unordered_map<uint32_t, CompetitorInfo> competitorMap;

    const int randomPromotion;
    const bool enableBypass;
    const bool enableAging;
    mutable int bypass_counter;
    const int virtual_bypass_counter;
    const int minimum_bypass_counter; // 8, 12, 12 (256, 4096, 4096)
    
    // bypass on or off (true initially)
    mutable bool bypass = true;

    // Instrumentation counters
    mutable uint64_t stat_getVictimCalls = 0;
    mutable uint64_t stat_realBypassStarted = 0;
    mutable uint64_t stat_virtualBypassStarted = 0;
    mutable uint64_t stat_noTracking = 0;
    mutable uint64_t stat_episodeProtected = 0;
    mutable uint64_t stat_touchResolved = 0;
    mutable uint64_t stat_touchRealBypassEffective = 0;   // hit to victim way during real bypass
    mutable uint64_t stat_touchVirtualBypassIneffective = 0; // hit to inserted line during virtual
    mutable uint64_t stat_resetResolved = 0;
    mutable uint64_t stat_resetRealBypassIneffective = 0; // bypassed tag came back (real)
    mutable uint64_t stat_resetVirtualBypassEffective = 0; // evicted tag came back (virtual)
    mutable uint64_t stat_bcIncrements = 0;
    mutable uint64_t stat_bcDecrements = 0;
    mutable uint64_t stat_invalidateCancelled = 0;

  public:
    typedef DSBRPParams Params;
    DSB(const Params &p);
    ~DSB();

    /**
     * Invalidate replacement data to set it as the next probable victim.
     * Sets its last touch tick as the starting tick.
     *
     * @param replacement_data Replacement data to be invalidated.
     */
    void invalidate(const std::shared_ptr<ReplacementData>& replacement_data)
                                                                    override;

    /**
     * Touch an entry to update its replacement data.
     * Sets its last touch tick as the current tick.
     *
     * @param replacement_data Replacement data to be touched.
     */
    void touch(const std::shared_ptr<ReplacementData>& replacement_data) const
                                                                     override;

    /**
     * Reset replacement data. Used when an entry is inserted.
     * Sets its last touch tick as the current tick.
     *
     * @param replacement_data Replacement data to be reset.
     */
    void reset(const std::shared_ptr<ReplacementData>& replacement_data) const
                                                                     override;

    /**
     * Find replacement victim using LRU timestamps.
     *
     * @param candidates Replacement candidates, selected by indexing policy.
     * @return Replacement entry to be replaced.
     */
    ReplaceableEntry* getVictim(const ReplacementCandidates& candidates) const
                                                                     override;

    /**
     * Notify DSB that a bypass occurred, providing the bypassed line's tag.
     *
     * @param replacement_data Replacement data of the victim that survived.
     * @param bypassedTag The tag of the line that was bypassed.
     */
    void notifyBypass(const std::shared_ptr<ReplacementData>& replacement_data,
                      Addr bypassedTag) override;

    /**
     * Instantiate a replacement data entry.
     *
     * @return A shared pointer to the new replacement data.
     */
    std::shared_ptr<ReplacementData> instantiateEntry() override;
};

} // namespace replacement_policy
} // namespace gem5

#endif // __MEM_CACHE_REPLACEMENT_POLICIES_DSB_RP_HH__
