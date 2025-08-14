-- BossKill.lua
-- Robust boss kill tracker using Encounter Journal driven events.
-- Handles multi-boss fights (e.g., The Primal Council) and bosses with titles (e.g., Sennarth, the Cold Breath)
-- without relying on unit names in the combat log.

local addonName, RaidTrack = ...

local BossKill = {}
RaidTrack.BossKill = BossKill

local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
local frame

-- ===== Utility / Safe Logging =====
local function Debug(msg)
    if RaidTrack and RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("[BossKill] " .. tostring(msg))
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff9acd32[RaidTrack:BossKill]|r " .. tostring(msg))
    end
end

-- ===== Normalization Helpers =====
local function SafeEJEncounterName(encounterID, fallback)
    if not encounterID then return fallback end
    local name = nil
    if type(EJ_GetEncounterInfo) == "function" then
        -- Retail / Wrath EJ API
        name = EJ_GetEncounterInfo(encounterID)
    elseif C_EncounterJournal and C_EncounterJournal.GetEncounterInfo then
        local info = C_EncounterJournal.GetEncounterInfo(encounterID)
        if info and info.name then name = info.name end
    end
    -- Fallback to provided name
    return name or fallback
end

local function NormalizeDifficulty(difficultyID)
    -- Map Blizzard difficulty IDs to readable strings
    local map = {
        [14] = "Normal",  -- Raid Normal
        [15] = "Heroic",  -- Raid Heroic
        [16] = "Mythic",  -- Raid Mythic
        [17] = "LFR",     -- Raid Finder
        [1]  = "Normal",  -- 5ppl
        [2]  = "Heroic",  -- 5ppl
        [23] = "Mythic",  -- 5ppl
        [8]  = "Mythic+", -- CM
        [3]  = "10N", [4] = "25N", [5] = "10H", [6] = "25H" -- legacy
    }
    return map[difficultyID] or tostring(difficultyID or "?")
end

local function MakeKillPayload(encounterID, ejName, difficultyID, size, extra)
    local now = GetServerTime and GetServerTime() or time()
    return {
        ts = now,
        encounterID = encounterID,
        name = ejName,
        difficultyID = difficultyID,
        difficulty = NormalizeDifficulty(difficultyID),
        size = size,
        source = extra and extra.source or "ENCOUNTER_END",
        duration = extra and extra.duration or nil,
        fromBossKillEvent = extra and extra.fromBossKillEvent or false,
        instanceID = extra and extra.instanceID or nil,
        zone = GetRealZoneText and GetRealZoneText() or nil,
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil,
    }
end

-- ===== State =====
local current = nil  -- { id, name, difficultyID, size, startTs }
local lastKillKey = nil  -- "id#difficulty#ts-bucket" to debounce

local function makeKillKey(encounterID, difficultyID)
    local bucket = math.floor((GetServerTime() or time()) / 5) -- 5s bucket to avoid dupes
    return string.format("%s#%s#%d", tostring(encounterID or "?"), tostring(difficultyID or "?"), bucket)
end

-- ===== Persistence Adapter =====
local function PersistKill(kill)
    -- Try known APIs in your addon, else queue.
    if RaidTrack.Database and type(RaidTrack.Database.AddBossKill) == "function" then
        RaidTrack.Database.AddBossKill(kill)
        return true
    elseif type(RaidTrack.AddBossKill) == "function" then
        RaidTrack.AddBossKill(kill)
        return true
    end
    -- Queue if no API available
    RaidTrack._pendingBossKills = RaidTrack._pendingBossKills or {}
    table.insert(RaidTrack._pendingBossKills, kill)
    Debug("No AddBossKill API found; queued kill in RaidTrack._pendingBossKills.")
    return false
end

-- ===== Event Handlers =====
local function OnEncounterStart(_, encounterID, encounterName, difficultyID, size)
    local ejName = SafeEJEncounterName(encounterID, encounterName)
    current = {
        id = encounterID,
        name = ejName,
        difficultyID = difficultyID,
        size = size,
        startTs = GetServerTime and GetServerTime() or time(),
    }
    Debug(("ENCOUNTER_START id=%s name=%s diff=%s size=%s"):format(
        tostring(encounterID), tostring(ejName), tostring(difficultyID), tostring(size)))
end

local function OnEncounterEnd(_, encounterID, encounterName, difficultyID, size, success)
    local ejName = SafeEJEncounterName(encounterID, encounterName)
    Debug(("ENCOUNTER_END id=%s name=%s diff=%s size=%s success=%s"):format(
        tostring(encounterID), tostring(ejName), tostring(difficultyID), tostring(size), tostring(success)))

    if success == 1 then
        local duration = nil
        if current and current.id == encounterID and current.startTs then
            duration = (GetServerTime and GetServerTime() or time()) - current.startTs
        end

        local key = makeKillKey(encounterID, difficultyID)
        if key == lastKillKey then
            Debug("Duplicate kill detected within debounce window; ignoring.")
        else
            lastKillKey = key
            local payload = MakeKillPayload(encounterID, ejName, difficultyID, size, { duration = duration })
            PersistKill(payload)
        end
    end

    -- Clear current if it matches
    if current and current.id == encounterID then
        current = nil
    end
end

-- Some raids also fire BOSS_KILL(id, name) — keep as a fallback if ENCOUNTER_* missed for any reason.
local function OnBossKill(_, bossID, bossName)
    -- Prefer current encounter context if present
    local encounterID, difficultyID, size, ejName = nil, nil, nil, nil
    if current then
        encounterID = current.id
        difficultyID = current.difficultyID
        size = current.size
        ejName = current.name
    end

    -- If no current encounter (rare), use bossID/name as-is
    local displayName = ejName or bossName
    local key = makeKillKey(encounterID or bossID, difficultyID or 0)
    if key == lastKillKey then
        Debug("Duplicate kill (BOSS_KILL) within debounce window; ignoring.")
        return
    end
    lastKillKey = key

    local payload = MakeKillPayload(encounterID or bossID, displayName, difficultyID or 0, size, {
        fromBossKillEvent = true,
        source = "BOSS_KILL",
    })
    PersistKill(payload)
    Debug(("BOSS_KILL id=%s name=%s (mapped encounter=%s)"):format(
        tostring(bossID), tostring(bossName), tostring(encounterID or "n/a")))
end

-- ===== Init / Teardown =====
function BossKill:Enable()
    if frame then return end
    frame = CreateFrame("Frame")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterEvent("BOSS_KILL")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ENCOUNTER_START" then
            OnEncounterStart(event, ...)
        elseif event == "ENCOUNTER_END" then
            OnEncounterEnd(event, ...)
        elseif event == "BOSS_KILL" then
            OnBossKill(event, ...)
        end
    end)

    Debug("BossKill enabled (listening to ENCOUNTER_* and BOSS_KILL).")
end

function BossKill:Disable()
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    frame = nil
    current = nil
    Debug("BossKill disabled.")
end

-- Auto-enable on load
local onLoadFrame = CreateFrame("Frame")
onLoadFrame:RegisterEvent("PLAYER_LOGIN")
onLoadFrame:SetScript("OnEvent", function()
    onLoadFrame:UnregisterEvent("PLAYER_LOGIN")
    BossKill:Enable()
end)
