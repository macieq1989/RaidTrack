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
function RaidTrack.CreateRaidInstance(name, zone, presetName, forcedId)
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
    local id = forcedId or time()

    local raid = {
        id = id,
        name = name,
        zone = zone,
        date = date("%Y-%m-%d"),
        started = time(),
        ended = nil,
        presetName = presetName,
        settings = CopyTable(preset),
        bosses = {},
        players = {},
        epLog = {},
        loot = {},
        flags = {},
        status = "started"
    }

    table.insert(RaidTrackDB.raidHistory, raid)
    RaidTrack.activeRaidID = id
    RaidTrackDB.activeRaidID = id

    for i = 1, GetNumGroupMembers() do
        local nm = GetRaidRosterInfo(i)
        if nm then
            table.insert(raid.players, nm)
        end
    end

    RaidTrack.AddDebugMessage("Created raid instance: " .. name .. " (" .. zone .. ") using preset " .. presetName)
end

function RaidTrack.EndActiveRaid()
    local id = RaidTrack.activeRaidID
    if not id then
        RaidTrack.AddDebugMessage("No active raid to end.")
        return
    end

    -- Full Attendance (before we clear active)
    if RaidTrack.AwardFullAttendanceIfNeededAtEnd then
        RaidTrack.AwardFullAttendanceIfNeededAtEnd()
    end

    -- Mark 'ended' in raidInstances
    if RaidTrackDB and RaidTrackDB.raidInstances then
        for _, r in ipairs(RaidTrackDB.raidInstances) do
            if tostring(r.id) == tostring(id) then
                r.status = "ended"
                r.ended  = time()
                break
            end
        end
    end

    -- Mark 'ended' in raidHistory
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

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("Raid ended: " .. tostring(id))
    end

    if RaidTrack.RefreshRaidDropdown then RaidTrack.RefreshRaidDropdown() end
    if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end
    if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end
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

-- One-time On-Time award (RL only)
function RaidTrack.AwardOnTimeIfNeeded()
    if not (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) then
        return
    end
    local raid = RaidTrack.GetActiveRaidEntry and RaidTrack.GetActiveRaidEntry()
    if not raid then
        return
    end
    raid.flags = raid.flags or {}
    if raid.flags.onTimeAwarded then
        return
    end

    local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
    local amt = cfg and cfg.awardEP and tonumber(cfg.awardEP.onTime) or 0
    if amt and amt > 0 then
        RaidTrack.AwardEPToCurrentRaidMembers(amt, "On-Time Bonus")
        raid.flags.onTimeAwarded = true
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("On-Time awarded: EP=%s"):format(tostring(amt)))
        end
    end
end

-- One-time Full Attendance at raid end (RL only)
function RaidTrack.AwardFullAttendanceIfNeededAtEnd()
    if not (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) then
        return
    end
    local raid = RaidTrack.GetActiveRaidEntry and RaidTrack.GetActiveRaidEntry()
    if not raid then
        return
    end
    raid.flags = raid.flags or {}
    if raid.flags.fullAttendanceAwarded then
        return
    end

    local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
    local amt = cfg and cfg.awardEP and tonumber(cfg.awardEP.fullAttendance) or 0
    local minMin = cfg and tonumber(cfg.minTimeInRaid) or 0

    -- check minimum time in raid
    local started = tonumber(raid.started) or 0
    local okTime = (started > 0) and (time() - started >= (minMin * 60))

    if amt and amt > 0 and okTime then
        RaidTrack.AwardEPToCurrentRaidMembers(amt, "Full Attendance")
        raid.flags.fullAttendanceAwarded = true
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("Full Attendance awarded: EP=%s"):format(tostring(amt)))
        end
    elseif amt and amt > 0 and not okTime then
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("Full Attendance NOT awarded (raid too short, need %d min)"):format(minMin))
        end
    end
end

