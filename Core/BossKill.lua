-- Core/BossKill.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- =========================
-- Addon message prefix (broadcast boss kill to raid)
-- =========================
local ADDON_PREFIX = "RaidTrack"

local function RegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    end
end

local function BroadcastBossKill(ts)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    local payload = "BOSS_KILL:" .. tostring(ts or time())
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, payload, "RAID")
end

-- =========================
-- Helpers
-- =========================

local DIFF_LABELS = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "LFR",
}

local function NormalizeName(s)
    if not s or s == "" then return "" end
    s = s:gsub("’", "'")
    s = s:gsub("[%(%)]", " ")
    s = s:gsub(",", " ")
    s = s:gsub(":%s*.*$", "")            -- cut after colon
    s = s:gsub("%s+the%s+", " ")
    s = s:gsub("^the%s+", "")
    s = s:gsub("%s+the$", "")
    s = s:gsub("%s+", " ")
    s = s:match("^%s*(.-)%s*$")
    return s:lower()
end

local function ResolveBossKey(bossesTable, encounterName)
    if not bossesTable or not next(bossesTable) then return encounterName end
    local normEncounter = NormalizeName(encounterName)

    for key, _ in pairs(bossesTable) do
        if NormalizeName(key) == normEncounter then
            return key
        end
    end

    local bestKey, bestLen = nil, 0
    for key, _ in pairs(bossesTable) do
        local nk = NormalizeName(key)
        if nk:find(normEncounter, 1, true) or normEncounter:find(nk, 1, true) then
            if #nk > bestLen then
                bestKey = key
                bestLen = #nk
            end
        end
    end
    if bestKey then return bestKey end

    return encounterName
end

-- =========================
-- State & queue
-- =========================

RaidTrack._lastBossKill = RaidTrack._lastBossKill or { t = 0, key = "" }
RaidTrack._pendingBossKills = RaidTrack._pendingBossKills or {}

local function IsRaidLeaderStrict()
    return UnitIsGroupLeader("player")
end

local function Now() return GetServerTime and GetServerTime() or time() end

-- =========================
-- Core: award EP and broadcast
-- =========================

function RaidTrack.AddBossKill(encounterID, encounterName, difficultyID, groupSize, success)
    if success ~= 1 then return end
    if not IsInRaid() then return end
    if not IsRaidLeaderStrict() then
        RaidTrack.AddDebugMessage("[BossKill] Ignored (not RL).")
        return
    end

    local diffLabel = DIFF_LABELS[tonumber(difficultyID) or -1]
    if not diffLabel then
        RaidTrack.AddDebugMessage(("[BossKill] Unknown difficultyID=%s; abort."):format(tostring(difficultyID)))
        return
    end

    local key = (encounterID or "?") .. "|" .. (encounterName or "?") .. "|" .. diffLabel
    local now = Now()
    if RaidTrack._lastBossKill.key == key and (now - (RaidTrack._lastBossKill.t or 0)) < 8 then
        RaidTrack.AddDebugMessage("[BossKill] Duplicate kill detected within debounce window; ignoring.")
        return
    end
    RaidTrack._lastBossKill.key = key
    RaidTrack._lastBossKill.t = now

    -- set local lastBossKillTime (RL)
    RaidTrack._lastBossKillTime = now

    local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or RaidTrack.currentRaidConfig
    if not cfg then
        RaidTrack.AddDebugMessage("[BossKill] No active raid config; abort.")
        return
    end

    local bossKey = ResolveBossKey(cfg.bosses or {}, encounterName)
    local amount = 0

    if cfg.bosses and cfg.bosses[bossKey] then
        local byDiff = cfg.bosses[bossKey]
        amount = tonumber(byDiff[diffLabel] or 0) or 0
    end

    if amount == 0 and cfg.awardEP and cfg.awardEP.bossKill then
        amount = tonumber(cfg.awardEP.bossKill) or 0
    end

    if amount <= 0 then
        RaidTrack.AddDebugMessage(("[BossKill] %s (%s) matched '%s' but EP=0; nothing awarded.")
            :format(encounterName or "?", diffLabel, tostring(bossKey)))
        if RaidTrack.RegisterBossKill then
            RaidTrack.RegisterBossKill(encounterName)
        end
        -- still broadcast so AutoPass window works for everyone
        BroadcastBossKill(now)
        return
    end

    local reason = ("Boss: %s [%s]"):format(bossKey, diffLabel)
    RaidTrack.AddDebugMessage(("[BossKill] Awarding EP=%d for %s."):format(amount, reason))
    if RaidTrack.AwardEPToCurrentRaidMembers then
        RaidTrack.AwardEPToCurrentRaidMembers(amount, reason)
    else
        for i = 1, GetNumGroupMembers() do
            local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online and RaidTrack.LogEPGPChange then
                RaidTrack.LogEPGPChange(name, amount, 0, reason)
            end
        end
    end

    if RaidTrack.RegisterBossKill then
        RaidTrack.RegisterBossKill(encounterName)
    end

    -- 🔊 broadcast to the whole raid (clients will set their local lastBossKillTime)
    BroadcastBossKill(now)
end

local function FlushPendingBossKills()
    if not RaidTrack._pendingBossKills or #RaidTrack._pendingBossKills == 0 then return end
    for _, e in ipairs(RaidTrack._pendingBossKills) do
        pcall(RaidTrack.AddBossKill, e.id, e.name, e.diff, e.size, e.success)
    end
    RaidTrack._pendingBossKills = {}
end

-- =========================
-- Events
-- =========================

local f = CreateFrame("Frame", nil, parent)
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("BOSS_KILL")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        if RaidTrack.AddBossKill then
            RaidTrack.AddBossKill(encounterID, encounterName, difficultyID, groupSize, success)
        else
            RaidTrack._pendingBossKills = RaidTrack._pendingBossKills or {}
            table.insert(RaidTrack._pendingBossKills, {
                id = encounterID, name = encounterName, diff = difficultyID, size = groupSize, success = success
            })
            RaidTrack.AddDebugMessage("[BossKill] No AddBossKill API found; queued kill in RaidTrack._pendingBossKills.")
        end
    elseif event == "BOSS_KILL" then
        local encounterID, encounterName = ...
        local difficultyID = select(3, GetInstanceInfo())
        if RaidTrack.AddBossKill then
            RaidTrack.AddBossKill(encounterID, encounterName, difficultyID, GetNumGroupMembers() or 0, 1)
        else
            RaidTrack._pendingBossKills = RaidTrack._pendingBossKills or {}
            table.insert(RaidTrack._pendingBossKills, {
                id = encounterID, name = encounterName, diff = difficultyID, size = GetNumGroupMembers() or 0, success = 1
            })
            RaidTrack.AddDebugMessage("[BossKill] No AddBossKill API found; queued (BOSS_KILL).")
        end
    end
end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    RegisterPrefix()
    C_Timer.After(0.5, FlushPendingBossKills)
end)
