-- Core/AutoPass.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- Auto-PASS only for non-leader, within X seconds after a boss kill
local BOSS_LOOT_WINDOW = 60  -- seconds

local f = CreateFrame("Frame")
f:RegisterEvent("START_LOOT_ROLL")
f:SetScript("OnEvent", function(_, _, rollID, rollTime)
    local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
    if not cfg or not cfg.autoPass then return end

    -- Leader NEVER auto-passes
    if RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader() then return end

    -- Only treat recent boss loot as eligible (prevents affecting random rolls)
    if not RaidTrack._lastBossKillTime or (time() - RaidTrack._lastBossKillTime) > BOSS_LOOT_WINDOW then
        return
    end

    if type(rollID) == "number" and RollOnLoot then
        RollOnLoot(rollID, 0) -- 0 = PASS
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("Auto-PASS rollID=" .. tostring(rollID))
        end
    end
end)
