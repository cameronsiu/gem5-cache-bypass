#ifndef __MEM_CACHE_REPLACEMENT_POLICIES_DSB_RP_HH__
#define __MEM_CACHE_REPLACEMENT_POLICIES_DSB_RP_HH__

#include "mem/cache/replacement_policies/base.hh"

namespace gem5
{

struct DSBRPParams;

struct CompetitorInfo {
  bool     competitorValid; // whether a bypass episode is currently active
  bool     startBypass;     // whehter a bypass started
  Addr     competitorTag;   // tag of bypassed line (line that we would have inserted)
  uint32_t competitorWay;   // way of victim line (line that we would have replaced)
  bool     isVirtualBypass; // true if we did not bypass, false if we did not
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

        /**
         * Default constructor. Invalidate data.
         */
        DSBReplData() : lastTouchTick(0), referenceBit(0), entry(NULL) {}
    };

    std::unordered_map<uint32_t, CompetitorInfo&> competitorMap;

    // CONFIG 1
    const int randomPromotion = 0; // 2^0 = 1
    mutable int bypass_counter = 6; // 2^6 = 64 
    const int virtual_bypass_counter = 4; // 2^4 16

  public:
    typedef DSBRPParams Params;
    DSB(const Params &p);
    ~DSB() = default;

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
     * Instantiate a replacement data entry.
     *
     * @return A shared pointer to the new replacement data.
     */
    std::shared_ptr<ReplacementData> instantiateEntry() override;
};

} // namespace replacement_policy
} // namespace gem5

#endif // __MEM_CACHE_REPLACEMENT_POLICIES_LRU_RP_HH__
