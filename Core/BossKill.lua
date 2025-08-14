-- Core/BossKill.lua
local addonName, RaidTrack = ...
local offlineData = RaidTrack.OfflineRaidData or {}

-- =========================
-- Difficulty resolver (Classic -> TWW)
-- =========================

-- Kanoniczne klucze używane w presetach
local CANONICAL_KEYS = {"Mythic", "Heroic", "Normal", "LFR", "25 Player", "10 Player", "40 Player"}

-- Rozszerzona mapa ID -> label (wspiera logi/pierwsze zgadywanie)
-- Nie musi być perfekcyjnie kompletna; resolver i tak poradzi sobie fallbackami.
local DIFF_ID_HINT = {
    -- Retail
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "LFR", -- Raid Finder

    -- Classic/TBC/WotLK style
    [3] = "10 Player", -- 10N
    [4] = "25 Player", -- 25N (w klasykach bywało różnie, ale użyjemy resolvera)
    [5] = "10 Player", -- 10H
    [6] = "25 Player", -- 25H

    -- Legacy / edge IDs spotykane w różnych buildach
    [2] = "40 Player",
    [7] = "LFR", -- w niektórych buildach
    [33] = "Timewalking", -- na wszelki wypadek (nie używamy jako klucz EP)
    [39] = "Timewalking",
    [149] = "Timewalking",
    [150] = "Timewalking",
    [151] = "Timewalking"
}

-- Akceptowane aliasy nazw z API (GetDifficultyInfo) -> kanoniczne klucze presetów
local DIFF_ALIASES = {
    ["LFR"] = {"LFR", "Raid Finder", "Looking For Raid"},
    ["Normal"] = {"Normal"},
    ["Heroic"] = {"Heroic"},
    ["Mythic"] = {"Mythic"},
    ["10 Player"] = {"10 Player", "10-Player", "10 man", "10"},
    ["25 Player"] = {"25 Player", "25-Player", "25 man", "25"},
    ["40 Player"] = {"40 Player", "40-Player", "40 man", "40"}
}

local function keyExists(tab, key)
    return tab and tab[key] ~= nil
end

local function aliasToCanonical(bossTab, labelFromAPI)
    if type(labelFromAPI) ~= "string" or labelFromAPI == "" then
        return nil
    end
    for canon, list in pairs(DIFF_ALIASES) do
        for _, alias in ipairs(list) do
            if alias == labelFromAPI and keyExists(bossTab, canon) then
                return canon
            end
        end
    end
    return nil
end

-- Główny resolver klucza trudności do użycia z tabelą bossa (preset)
local function ResolveDifficultyKey(difficultyID, bossTab)
    -- 1) spróbuj nazwy z API Blizzarda (Retail/TWW)
    local apiName = GetDifficultyInfo and GetDifficultyInfo(difficultyID) or nil
    local canonViaAPI = aliasToCanonical(bossTab, apiName)
    if canonViaAPI then
        return canonViaAPI
    end

    -- 2) spróbuj „hint” po ID
    local hinted = DIFF_ID_HINT[difficultyID]
    if hinted and keyExists(bossTab, hinted) then
        return hinted
    end

    -- 3) jeżeli preset ma nowoczesne klucze — preferuj je
    for _, k in ipairs({"Mythic", "Heroic", "Normal", "LFR"}) do
        if keyExists(bossTab, k) then
            return k
        end
    end

    -- 4) klasyczne rozmiary: dopasuj po realnym rozmiarze instancji
    local _, _, _, _, _, _, _, _, maxPlayers = GetInstanceInfo()
    if maxPlayers and maxPlayers > 0 then
        local sizeKey = (maxPlayers >= 35 and "40 Player") or (maxPlayers > 10 and "25 Player") or "10 Player"
        if keyExists(bossTab, sizeKey) then
            return sizeKey
        end
    end

    -- 5) ostatnia deska ratunku: wybierz pierwszy kanoniczny klucz, który istnieje w presecie
    for _, k in ipairs(CANONICAL_KEYS) do
        if keyExists(bossTab, k) then
            return k
        end
    end

    -- 6) całkowity fallback: zwróć label/hint lub samo ID jako tekst (spowoduje „No EP configured”)
    return apiName or DIFF_ID_HINT[difficultyID] or tostring(difficultyID)
end

local function GetActiveRaidConfig()
    return RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
end

function RaidTrack.AwardEPForBossKill(bossName, difficultyID)
    -- Only RL awards automatically
    if not RaidTrack.IsRaidLeader or not RaidTrack.IsRaidLeader() then
        return
    end

    local config = (RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig()) or
                       (GetActiveRaidConfig and GetActiveRaidConfig())
    if not config or not config.bosses then
        print("[RaidTrack] No active raid/config or bosses table.")
        return
    end

    local bossTab = config.bosses[bossName]
    if not bossTab then
        print("[RaidTrack] Boss not found in preset: " .. tostring(bossName))
        return
    end

    local diffKey = ResolveDifficultyKey(difficultyID, bossTab)
    local bossEP = bossTab[diffKey]

    -- Fallback to global "Per Boss Kill" if per-boss EP is not set
    if (not bossEP or bossEP <= 0) then
        local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
        local fallback = cfg and cfg.awardEP and tonumber(cfg.awardEP.bossKill) or 0
        if fallback and fallback > 0 then
            bossEP = fallback
        end
    end

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(string.format("Boss kill registered: %s [%s] (diffID=%s) -> EP=%s",
            tostring(bossName), tostring(diffKey), tostring(difficultyID), tostring(bossEP)))
    end

    if not bossEP or bossEP <= 0 then
        print(string.format("[RaidTrack] No EP configured for %s [%s]", tostring(bossName), tostring(diffKey)))
        return
    end

    -- idempotent guard (unchanged)
    local raid = RaidTrack.GetActiveRaidEntry and RaidTrack.GetActiveRaidEntry()
    if not raid then
        return
    end
    raid.awardGuard = raid.awardGuard or {}
    local key = string.format("%s|%s", bossName, tostring(diffKey))
    if raid.awardGuard[key] then
        return
    end
    raid.awardGuard[key] = true

    -- award to online members (unchanged)
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
        if name and online then
            RaidTrack.LogEPGPChange(name, bossEP, 0, "Boss Kill: " .. bossName .. " [" .. tostring(diffKey) .. "]")
        end
    end
end

-- Track boss kill moment (for Auto-PASS filter)
RaidTrack._lastBossKillTime = RaidTrack._lastBossKillTime or 0

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:SetScript("OnEvent", function(_, _, _, encounterName, difficultyID, _, success)
    if success == 1 then
        RaidTrack._lastBossKillTime = time()
        RaidTrack.AwardEPForBossKill(encounterName, difficultyID)
    end
end)

-- Offline API passthroughs (leave as-is)
function RaidTrack.GetRaidDifficulties()
    return {"Normal", "Heroic", "Mythic"}
end

function RaidTrack.GetExpansions(callback)
    local result = {}
    for _, expansion in ipairs(offlineData) do
        table.insert(result, {
            id = expansion.id or expansion.expansionID,
            name = expansion.name
        })
    end
    callback(result)
end

function RaidTrack.GetInstancesForExpansion(expansionID, callback)
    for _, expansion in ipairs(offlineData) do
        if expansion.id == expansionID or expansion.expansionID == expansionID then
            local result = {}
            for _, instance in ipairs(expansion.instances or {}) do
                table.insert(result, {
                    id = instance.id,
                    name = instance.name
                })
            end
            callback(result)
            return
        end
    end
    callback({})
end

function RaidTrack.GetEncountersForInstance(instanceID, callback)
    for _, expansion in ipairs(offlineData) do
        for _, instance in ipairs(expansion.instances or {}) do
            if instance.id == instanceID then
                local result = {}
                for _, boss in ipairs(instance.bosses or {}) do
                    table.insert(result, {
                        id = boss.id,
                        name = boss.name
                    })
                end
                callback(result)
                return
            end
        end
    end
    callback({})
end
