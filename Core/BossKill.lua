-- Core/BossKill.lua

local addonName, RaidTrack = ...
local offlineData = RaidTrack.OfflineRaidData or {}

-- Mapy tylko do UI/debugu, nie do kluczy
local difficultyMap = {
    [4] = "40 Player",   -- Classic raids (MC, BWL, AQ, Naxx)
    [3] = "10 Player",   -- Kara, ZG, AQ20
    [5] = "25 Player",   -- TBC/WotLK 25ppl
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic"
}

-- Pobierz ustawienia aktywnego raidu
local function GetActiveRaidConfig()
    if not RaidTrackDB or not RaidTrack.activeRaidID then return nil end
    for _, raid in ipairs(RaidTrackDB.raidHistory or {}) do
        if raid.id == RaidTrack.activeRaidID then
            return raid.settings
        end
    end
    return nil
end

function RaidTrack.AwardEPForBossKill(bossName, difficultyID)
    local config = GetActiveRaidConfig()
    if not config then
        print("[RaidTrack] Brak aktywnego raidu lub ustawień.")
        return
    end
    if not config.bosses then
        print("[RaidTrack] Brak bossów w konfiguracji raidu!")
        return
    end

    -- MAPPING: id -> string
    local diffStr = difficultyMap[difficultyID] or tostring(difficultyID)

    -- DUMP na żywo
    print("DEBUG>> Boss szukany: " .. tostring(bossName))
    print("DEBUG>> Trudność szukana: " .. tostring(diffStr))
    print("DEBUG>> Dostępni bossowie:")
    for name, tab in pairs(config.bosses) do print("   > "..name) end

    -- NAJWAŻNIEJSZE!
    local bossTab = config.bosses[bossName]
    if not bossTab then
        print("[RaidTrack] Nie znaleziono bossa '"..tostring(bossName).."' w presetach.")
        return
    end

    -- Tu jest lookup
    local bossEP = bossTab[diffStr]
    print("DEBUG>> bossEP dla "..bossName.." ["..diffStr.."] = "..tostring(bossEP))

    if not bossEP or bossEP <= 0 then
        print("[RaidTrack] Brak EP dla bossa "..tostring(bossName).." w trudności "..diffStr)
        return
    end

    for _, unit in ipairs(RaidTrack.GetCurrentRaidMembers()) do
        RaidTrack.LogEPGPChange(unit.name, bossEP, 0, "Boss Kill: " .. bossName .. " [" .. diffStr .. "]")
    end
end


-- Event na zabicie bossa
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:SetScript("OnEvent", function(_, _, _, encounterName, difficultyID, _, success)
    if success == 1 then
        RaidTrack.AwardEPForBossKill(encounterName, difficultyID)
    end
end)

function RaidTrack.GetRaidDifficulties()
    return { "Normal", "Heroic", "Mythic" }
end

-- API offline
function RaidTrack.GetExpansions(callback)
    local result = {}
    for _, expansion in ipairs(offlineData) do
        table.insert(result, { id = expansion.id or expansion.expansionID, name = expansion.name })
    end
    callback(result)
end

function RaidTrack.GetInstancesForExpansion(expansionID, callback)
    for _, expansion in ipairs(offlineData) do
        if expansion.id == expansionID or expansion.expansionID == expansionID then
            local result = {}
            for _, instance in ipairs(expansion.instances or {}) do
                table.insert(result, { id = instance.id, name = instance.name })
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
                    table.insert(result, { id = boss.id, name = boss.name })
                end
                callback(result)
                return
            end
        end
    end
    callback({})
end
