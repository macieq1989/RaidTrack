-- Core/BossKill.lua

local addonName, RaidTrack = ...
local offlineData = RaidTrack.OfflineRaidData or {}

-- difficultyMap: num -> name
local difficultyMap = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic"
}

function RaidTrack.AwardEPForBossKill(bossName, difficultyID)
    local difficulty = difficultyMap[difficultyID] or "Unknown"
    local config = RaidTrack.GetActiveRaidConfig()
    if not config then return end

    local bossEP = config.bosses and config.bosses[bossName] and config.bosses[bossName][difficulty]
    if not bossEP or bossEP <= 0 then return end

    for _, unit in ipairs(RaidTrack.GetCurrentRaidMembers()) do
        RaidTrack.LogEPGPChange(unit.name, bossEP, 0, "Boss Kill: " .. bossName .. " [" .. difficulty .. "]")
    end
end

-- Rejestracja eventu do śledzenia zabitych bossów
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

-- OFFLINE API zamiast Encounter Journal
function RaidTrack.GetExpansions(callback)
    local result = {}
    for _, expansion in ipairs(offlineData) do
        table.insert(result, { id = expansion.id, name = expansion.name })
    end
    callback(result)
end

function RaidTrack.GetInstancesForExpansion(expansionID, callback)
    for _, expansion in ipairs(offlineData) do
        if expansion.id == expansionID then
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
