-- Core/RaidConfig.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}


-- Zapisuje preset pod daną nazwą
function RaidTrack.SaveRaidPreset(name, config)
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}

    if not name or type(config) ~= "table" then
        RaidTrack.AddDebugMessage("SaveRaidPreset: invalid name or config")
        return
    end

    RaidTrackDB.raidPresets[name] = config
    RaidTrack.AddDebugMessage("Saved raid preset: " .. name)
end

-- Zwraca listę presetów jako tabela: { ["name"] = config, ... }
function RaidTrack.GetRaidPresets()
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
    return RaidTrackDB.raidPresets
end

-- Usuwa preset
function RaidTrack.DeleteRaidPreset(name)
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}

    if RaidTrackDB.raidPresets[name] then
        RaidTrackDB.raidPresets[name] = nil
        RaidTrack.AddDebugMessage("Deleted raid preset: " .. name)
    end
end

-- Wczytuje preset i wywołuje callback z jego zawartością
function RaidTrack.LoadRaidPreset(name, callback)
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}

    local preset = RaidTrackDB.raidPresets[name]
    if preset and type(callback) == "function" then
        callback(preset)
    else
        RaidTrack.AddDebugMessage("LoadRaidPreset: preset not found or invalid callback")
    end
end

-- Tworzy instancję nowego raidu na podstawie wybranego presetu
function RaidTrack.CreateRaidInstance(name, zone, presetName)
    if not name or not zone then
        RaidTrack.AddDebugMessage("CreateRaidInstance: missing name or zone")
        return
    end

    local preset = RaidTrackDB.raidPresets[presetName]
    if not preset then
        RaidTrack.AddDebugMessage("CreateRaidInstance: preset not found: " .. tostring(presetName))
        return
    end

    RaidTrackDB.raidHistory = RaidTrackDB.raidHistory or {}
    local id = time()

    local raid = {
        id = id,
        name = name,
        zone = zone,
        date = date("%Y-%m-%d"),
        started = time(),
        ended = nil,
        presetName = presetName,
        settings = CopyTable(preset), -- zachowujemy oryginalne ustawienia
        bosses = {},
        players = {},
        epLog = {},
        loot = {}
    }

    RaidTrackDB.raidHistory[#RaidTrackDB.raidHistory + 1] = raid
    RaidTrack.activeRaidID = id

    -- zapisz aktualny skład raidu
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then
            table.insert(raid.players, name)
        end
    end

    RaidTrack.AddDebugMessage("Created raid instance: " .. name .. " (" .. zone .. ") using preset " .. presetName)
end

function RaidTrack.EndActiveRaid()
    if not RaidTrack.activeRaidID then
        return
    end

    for _, raid in ipairs(RaidTrackDB.raidHistory or {}) do
        if raid.id == RaidTrack.activeRaidID then
            raid.ended = time()
            RaidTrack.AddDebugMessage("Ended raid: " .. raid.name)
            break
        end
    end

    RaidTrack.activeRaidID = nil
end

function RaidTrack.RegisterBossKill(bossName)
    if not RaidTrack.activeRaidID then
        return
    end
    if not bossName then
        return
    end

    for _, raid in ipairs(RaidTrackDB.raidHistory or {}) do
        if raid.id == RaidTrack.activeRaidID then
            raid.bosses[#raid.bosses + 1] = {
                name = bossName,
                timestamp = time(),
                players = {}
            }

            for i = 1, GetNumGroupMembers() do
                local name = GetRaidRosterInfo(i)
                if name then
                    table.insert(raid.bosses[#raid.bosses].players, name)
                end
            end

            -- auto-award EP jeśli ustawione
            local ep = raid.settings and raid.settings.awardEP and raid.settings.awardEP.bossKill
            if ep and ep > 0 then
                for _, name in ipairs(raid.bosses[#raid.bosses].players) do
                    RaidTrack.LogEPGPChange(name, ep, 0, "Boss Kill: " .. bossName)
                    table.insert(raid.epLog, {
                        name = name,
                        ep = ep,
                        gp = 0,
                        source = bossName,
                        timestamp = time()
                    })
                end
            end

            RaidTrack.AddDebugMessage("Boss kill registered: " .. bossName)
            break
        end
    end
end
-- REJESTROWANIE BOSS KILLI
local encounterFrame = CreateFrame("Frame")
encounterFrame:RegisterEvent("ENCOUNTER_END")
encounterFrame:SetScript("OnEvent", function(_, _, encounterID, encounterName, difficultyID, groupSize, success)
    if success ~= 1 then
        return
    end
    if not RaidTrack.activeRaidID then
        return
    end

    -- Rejestracja bossa
    RaidTrack.RegisterBossKill(encounterName)
end)

function RaidTrack.GetRaidPresetNames()
    local names = {}
    for name, _ in pairs(RaidTrackDB.raidPresets or {}) do
        table.insert(names, name)
    end
    return names
end



