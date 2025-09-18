-- Core/RaidConfig.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.raidPresets  = RaidTrackDB.raidPresets  or {}
RaidTrackDB.raidHistory  = RaidTrackDB.raidHistory  or {}
RaidTrackDB.raidInstances= RaidTrackDB.raidInstances or {}

-- === utils ===
local function dmsg(msg)
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(msg) end
end

local function deepcopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            t[k] = deepcopy(v)
        else
            t[k] = v
        end
    end
    return t
end

local function copytbl(tbl)
    -- WoW ma CopyTable; jeśli nie ma, fallback na deepcopy
    if type(CopyTable) == "function" then
        return CopyTable(tbl)
    else
        return deepcopy(tbl)
    end
end

-- === API: Presety ===

-- Zapisuje/aktualizuje preset pod daną nazwą (z defensywnym kopiowaniem)
function RaidTrack.SaveRaidPreset(name, config)
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}

    if not name or name == "" or type(config) ~= "table" then
        dmsg("SaveRaidPreset: invalid name or config")
        return
    end

    -- Defensywnie normalizujemy ważne pola
    local cfg = copytbl(config)
    cfg.awardEP = cfg.awardEP or { onTime = 0, bossKill = 0, fullAttendance = 0 }
    cfg.requirements = cfg.requirements or { flask = false, enchants = false }
    cfg.bosses = cfg.bosses or {}
    if cfg.minTimeInRaid ~= nil then
        cfg.minTimeInRaid = tonumber(cfg.minTimeInRaid) or 0
    end

    RaidTrackDB.raidPresets[name] = cfg
    dmsg("Saved raid preset: " .. name)
end

-- Zwraca tablicę presetów { ["nazwa"] = config, ... }
function RaidTrack.GetRaidPresets()
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
    return RaidTrackDB.raidPresets
end

-- Wygodna lista nazw (używane w UI)
function RaidTrack.GetRaidPresetNames()
    local names = {}
    for n, _ in pairs(RaidTrackDB.raidPresets or {}) do
        table.insert(names, n)
    end
    return names
end

-- Usuwa preset
function RaidTrack.DeleteRaidPreset(name)
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}

    if RaidTrackDB.raidPresets[name] then
        RaidTrackDB.raidPresets[name] = nil
        dmsg("Deleted raid preset: " .. name)
    end
end

-- Wczytuje preset i wywołuje callback z jego zawartością (kopią)
function RaidTrack.LoadRaidPreset(name, callback)
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}

    local preset = RaidTrackDB.raidPresets[name]
    if preset and type(callback) == "function" then
        callback(copytbl(preset))
    else
        dmsg("LoadRaidPreset: preset not found or invalid callback")
    end
end

-- === API: Aktywny raid / config (gettery) ===

-- Zwraca rekord aktywnego raidu z raidHistory (jeśli istnieje)
function RaidTrack.GetActiveRaidEntry()
    local id = RaidTrack.activeRaidID or RaidTrackDB.activeRaidID
    if not id then return nil end

    for _, r in ipairs(RaidTrackDB.raidHistory or {}) do
        if tostring(r.id) == tostring(id) then
            return r
        end
    end
    return nil
end

-- Zwraca aktualny config raidu:
-- 1) RaidTrack.currentRaidConfig (snapshot),
-- 2) settings aktywnego wpisu w raidHistory,
-- 3) config z presetu wskazanego przez aktywną instancję (fallback).
function RaidTrack.GetActiveRaidConfig()
    if RaidTrack.currentRaidConfig and type(RaidTrack.currentRaidConfig) == "table" then
        return RaidTrack.currentRaidConfig
    end

    local entry = RaidTrack.GetActiveRaidEntry()
    if entry and type(entry.settings) == "table" then
        return entry.settings
    end

    -- fallback: z instancji
    local act = RaidTrackDB.activeRaidID
    if act and RaidTrackDB.raidInstances then
        local presetName
        for _, inst in ipairs(RaidTrackDB.raidInstances) do
            if tostring(inst.id) == tostring(act) then
                presetName = inst.preset
                break
            end
        end
        if presetName and RaidTrackDB.raidPresets and RaidTrackDB.raidPresets[presetName] then
            return RaidTrackDB.raidPresets[presetName]
        end
    end

    return nil
end

-- === API: Tworzenie/Zamykanie raidów ===

-- Tworzy instancję aktywnego raidu (snapshot ustawień z presetu)
-- Uwaga: to tworzy wpis w raidHistory (log), a stan w raidInstances jest
-- ustawiany w UI (Start), więc tutaj go nie zmieniamy.
function RaidTrack.CreateRaidInstance(name, zone, presetName, forcedId)
    if not name or name == "" or not zone or zone == "" then
        dmsg("CreateRaidInstance: missing name or zone")
        return
    end
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
    local preset = RaidTrackDB.raidPresets[presetName]
    if not preset then
        dmsg("CreateRaidInstance: preset not found: " .. tostring(presetName))
        return
    end

    RaidTrackDB.raidHistory = RaidTrackDB.raidHistory or {}
    local id = forcedId or time()

    local raid = {
        id         = id,
        name       = name,
        zone       = zone,
        date       = date("%Y-%m-%d"),
        started    = time(),
        ended      = nil,
        presetName = presetName,
        settings   = copytbl(preset), -- snapshot!
        bosses     = {},
        players    = {},
        epLog      = {},
        loot       = {},
        flags      = {},
        status     = "started",
    }

    table.insert(RaidTrackDB.raidHistory, raid)
    RaidTrack.activeRaidID   = id
    RaidTrackDB.activeRaidID = id
    RaidTrack.currentRaidConfig = raid.settings -- snapshot, by nie zależeć od live presetu

    -- Zrzut listy graczy z grupy w momencie startu
    local n = GetNumGroupMembers() or 0
    for i = 1, n do
        local nm = GetRaidRosterInfo(i)
        if nm then table.insert(raid.players, nm) end
    end

    dmsg(("Created raid instance: %s (%s) using preset %s"):format(name, zone, tostring(presetName)))

    -- Rozgłoś aktualny stan raidowy (tylko jeśli mamy nadać; funkcja sama sprawdzi uprawnienia)
    if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end
end

function RaidTrack.EndActiveRaid()
    local id = RaidTrack.activeRaidID
    if not id then
        dmsg("No active raid to end.")
        return
    end

    -- One-shot Full Attendance (zależnie od configu)
    if RaidTrack.AwardFullAttendanceIfNeededAtEnd then
        RaidTrack.AwardFullAttendanceIfNeededAtEnd()
    end

    -- Oznacz 'ended' w raidInstances (lista zarządcza)
    if RaidTrackDB and RaidTrackDB.raidInstances then
        for _, r in ipairs(RaidTrackDB.raidInstances) do
            if tostring(r.id) == tostring(id) then
                r.status = "ended"
                r.ended  = time()
                break
            end
        end
    end

    -- Oznacz 'ended' w raidHistory (log)
    if RaidTrackDB and RaidTrackDB.raidHistory then
        for _, h in ipairs(RaidTrackDB.raidHistory) do
            if tostring(h.id) == tostring(id) then
                h.status = "ended"
                h.ended  = time()
                break
            end
        end
    end

    RaidTrack.activeRaidID      = nil
    RaidTrackDB.activeRaidID    = nil
    RaidTrack.currentRaidConfig = nil

    dmsg("Raid ended: " .. tostring(id))

    if RaidTrack.RefreshRaidDropdown then RaidTrack.RefreshRaidDropdown() end
    if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end
    if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end
end

-- === Zdarzenia bojowe: boss kill ===

function RaidTrack.RegisterBossKill(bossName)
    if not RaidTrack.activeRaidID or not bossName or bossName == "" then return end

    for _, raid in ipairs(RaidTrackDB.raidHistory or {}) do
        if tostring(raid.id) == tostring(RaidTrack.activeRaidID) then
            raid.bosses[#raid.bosses + 1] = {
                name      = bossName,
                timestamp = time(),
                players   = {}
            }

            local idx = #raid.bosses
            local n = GetNumGroupMembers() or 0
            for i = 1, n do
                local nm = GetRaidRosterInfo(i)
                if nm then table.insert(raid.bosses[idx].players, nm) end
            end

            -- auto-award EP jeśli ustawione
            local ep = raid.settings and raid.settings.awardEP and tonumber(raid.settings.awardEP.bossKill) or 0
            if ep and ep > 0 then
                for _, nm in ipairs(raid.bosses[idx].players) do
                    RaidTrack.LogEPGPChange(nm, ep, 0, "Boss Kill: " .. bossName)
                    table.insert(raid.epLog, {
                        name      = nm,
                        ep        = ep,
                        gp        = 0,
                        source    = bossName,
                        timestamp = time()
                    })
                end
            end

            dmsg("Boss kill registered: " .. bossName)
            break
        end
    end
end

-- REJESTROWANIE BOSS KILLI
local encounterFrame = CreateFrame("Frame")
encounterFrame:RegisterEvent("ENCOUNTER_END")
encounterFrame:SetScript("OnEvent", function(_, _, encounterID, encounterName, difficultyID, groupSize, success)
    if success ~= 1 or not RaidTrack.activeRaidID then return end
    RaidTrack.RegisterBossKill(encounterName)
end)

-- === Jednorazowe nagrody (RL only) ===

function RaidTrack.AwardOnTimeIfNeeded()
    if not (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) then return end
    local raid = RaidTrack.GetActiveRaidEntry()
    if not raid then return end
    raid.flags = raid.flags or {}
    if raid.flags.onTimeAwarded then return end

    local cfg = RaidTrack.GetActiveRaidConfig()
    local amt = cfg and cfg.awardEP and tonumber(cfg.awardEP.onTime) or 0
    if amt and amt > 0 then
        RaidTrack.AwardEPToCurrentRaidMembers(amt, "On-Time Bonus")
        raid.flags.onTimeAwarded = true
        dmsg(("On-Time awarded: EP=%s"):format(tostring(amt)))
    end
end

function RaidTrack.AwardFullAttendanceIfNeededAtEnd()
    if not (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) then return end
    local raid = RaidTrack.GetActiveRaidEntry()
    if not raid then return end
    raid.flags = raid.flags or {}
    if raid.flags.fullAttendanceAwarded then return end

    local cfg    = RaidTrack.GetActiveRaidConfig()
    local amt    = cfg and cfg.awardEP and tonumber(cfg.awardEP.fullAttendance) or 0
    local minMin = cfg and tonumber(cfg.minTimeInRaid) or 0

    local started = tonumber(raid.started) or 0
    local okTime  = (started > 0) and (time() - started >= (minMin * 60))

    if amt and amt > 0 and okTime then
        RaidTrack.AwardEPToCurrentRaidMembers(amt, "Full Attendance")
        raid.flags.fullAttendanceAwarded = true
        dmsg(("Full Attendance awarded: EP=%s"):format(tostring(amt)))
    elseif amt and amt > 0 and not okTime then
        dmsg(("Full Attendance NOT awarded (raid too short, need %d min)"):format(minMin))
    end
end
