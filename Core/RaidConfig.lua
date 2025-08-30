-- Core/RaidConfig.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}

-- DB guards
RaidTrackDB.raidPresets         = RaidTrackDB.raidPresets         or {}
RaidTrackDB._presetTombstones   = RaidTrackDB._presetTombstones   or {}
RaidTrackDB._presetRevisions    = RaidTrackDB._presetRevisions    or {}
RaidTrackDB.raidHistory         = RaidTrackDB.raidHistory         or {}
RaidTrackDB.raidInstances       = RaidTrackDB.raidInstances       or {}
RaidTrackDB._instanceTombstones = RaidTrackDB._instanceTombstones or {}

-----------------------------------------------------------------------
-- Zapisuje preset pod daną nazwą (z wersjonowaniem + tombstone cleanup)
-----------------------------------------------------------------------
function RaidTrack.SaveRaidPreset(name, config)
    RaidTrackDB.raidPresets       = RaidTrackDB.raidPresets       or {}
    RaidTrackDB._presetTombstones = RaidTrackDB._presetTombstones or {}
    RaidTrackDB._presetRevisions  = RaidTrackDB._presetRevisions  or {}

    -- sanitize nazwy
    if type(name) ~= "string" then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("SaveRaidPreset: invalid name type") end
        return
    end
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("SaveRaidPreset: empty name after trim") end
        return
    end
    name = trimmed

    if type(config) ~= "table" then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("SaveRaidPreset: invalid config type") end
        return
    end

    -- Bezpieczna kopia (no functions/userdata/threads)
    local function SanitizeTable(src, seen)
        if type(src) ~= "table" then return {} end
        seen = seen or {}
        if seen[src] then return {} end
        seen[src] = true
        local dst = {}
        setmetatable(dst, nil)
        for k, v in pairs(src) do
            local kt, vt = type(k), type(v)
            local key = (kt == "string" or kt == "number") and k or tostring(k)
            if vt == "table" then
                dst[key] = SanitizeTable(v, seen)
            elseif vt == "string" or vt == "number" or vt == "boolean" then
                dst[key] = v
            end
        end
        return dst
    end

    local cleanConfig = SanitizeTable(config)

    -- zapis/aktualizacja
    RaidTrackDB.raidPresets[name] = cleanConfig
    -- ustaw rewizję (używamy timestampu -> łatwe porównanie po stronie odbiorcy)
    RaidTrackDB._presetRevisions[name]  = time()
    -- jeśli był tombstone, usuń go (reanimacja)
    if RaidTrackDB._presetTombstones[name] then
        RaidTrackDB._presetTombstones[name] = nil
    end

    -- diagnostyka rozmiaru
    if RaidTrack.SafeSerialize then
        local s = RaidTrack.SafeSerialize({ test = cleanConfig })
        if s and type(s) == "string" then
            if RaidTrack.AddDebugMessage then
                RaidTrack.AddDebugMessage(("Saved raid preset: %s (approx %d bytes)"):format(name, #s))
            end
        else
            if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Saved raid preset: " .. name) end
        end
    elseif RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("Saved raid preset: " .. name)
    end

    -- odśwież UI i wyślij sync batched
    -- odśwież UI
if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end

-- natychmiast wyślij na GUILD (i RAID jeśli jesteś w raidzie)
if RaidTrack.SendRaidSyncData then
    RaidTrack.SendRaidSyncData({ alwaysGuild = true })
elseif RaidTrack.RequestRaidSyncFlush then
    -- fallback gdyby powyższe nie istniało
    RaidTrack.RequestRaidSyncFlush(0.35)
end

end

----------------------------------------------
-- Zwraca listę presetów: { ["name"] = cfg }
----------------------------------------------
function RaidTrack.GetRaidPresets()
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
    return RaidTrackDB.raidPresets
end

-------------------
-- Usuwa preset
-------------------
function RaidTrack.DeleteRaidPreset(name)
    RaidTrackDB.raidPresets         = RaidTrackDB.raidPresets         or {}
    RaidTrackDB._presetTombstones   = RaidTrackDB._presetTombstones   or {}
    RaidTrackDB._presetRevisions    = RaidTrackDB._presetRevisions    or {}

    if type(name) ~= "string" then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("DeleteRaidPreset: invalid name") end
        return
    end
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("DeleteRaidPreset: empty name after trim") end
        return
    end
    name = trimmed

    if RaidTrackDB.raidPresets[name] ~= nil then
        RaidTrackDB.raidPresets[name] = nil
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Deleted raid preset (local): " .. name) end
    else
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Tombstoning non-existing preset (for propagation): " .. name) end
    end

    -- tombstone = timestamp; wyczyść rewizję
    RaidTrackDB._presetTombstones[name] = time()
    RaidTrackDB._presetRevisions[name]  = nil

    -- batch flush
   -- natychmiast wyślij na GUILD (i RAID jeśli jesteś w raidzie)
if RaidTrack.SendRaidSyncData then
    RaidTrack.SendRaidSyncData({ alwaysGuild = true })
elseif RaidTrack.RequestRaidSyncFlush then
    RaidTrack.RequestRaidSyncFlush(0.25)
end

end

----------------------------------------------
-- Usuwa instancję raidu (z tombstonem)
----------------------------------------------
function RaidTrack.DeleteRaidInstance(id)
    if not id then return end
    id = tostring(id)

    RaidTrackDB.raidInstances       = RaidTrackDB.raidInstances       or {}
    RaidTrackDB._instanceTombstones = RaidTrackDB._instanceTombstones or {}

    for idx, inst in ipairs(RaidTrackDB.raidInstances) do
        if tostring(inst.id) == id then
            table.remove(RaidTrackDB.raidInstances, idx)
            break
        end
    end

    RaidTrackDB._instanceTombstones[id] = time()

    if RaidTrack.RequestRaidSyncFlush then
        RaidTrack.RequestRaidSyncFlush(0.5)
    elseif RaidTrack.SendRaidSyncData then
        RaidTrack.SendRaidSyncData()
    end
end

----------------------------------------------------
-- Wczytuje preset i wywołuje callback(config)
----------------------------------------------------
function RaidTrack.LoadRaidPreset(name, callback)
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
    local preset = RaidTrackDB.raidPresets[name]
    if preset and type(callback) == "function" then
        callback(preset)
    else
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("LoadRaidPreset: preset not found or invalid callback") end
    end
end

-----------------------------------------------------------------------
-- Tworzy instancję nowego raidu na podstawie wybranego presetu
-----------------------------------------------------------------------
function RaidTrack.CreateRaidInstance(name, zone, presetName, forcedId)
    if not name or not zone then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("CreateRaidInstance: missing name or zone") end
        return
    end

    RaidTrackDB.raidPresets   = RaidTrackDB.raidPresets   or {}
    RaidTrackDB.raidHistory   = RaidTrackDB.raidHistory   or {}
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

    local preset = RaidTrackDB.raidPresets[presetName]
    if not preset then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("CreateRaidInstance: preset not found: " .. tostring(presetName)) end
        return
    end

    local now = time()
    local id  = forcedId or now

    local raid = {
        id         = id,
        name       = name,
        zone       = zone,
        date       = date("%Y-%m-%d"),
        started    = now,
        ended      = nil,
        presetName = presetName,
        settings   = CopyTable(preset),
        bosses     = {},
        players    = {},
        epLog      = {},
        loot       = {},
        flags      = {},
        status     = "started",
    }
    table.insert(RaidTrackDB.raidHistory, raid)

    table.insert(RaidTrackDB.raidInstances, {
        id      = id,
        title   = name,
        zone    = zone,
        preset  = presetName,
        status  = "started",
        startAt = now,
        ended   = nil,
        endAt   = nil,
    })

    RaidTrack.activeRaidID   = id
    RaidTrackDB.activeRaidID = id

    for i = 1, GetNumGroupMembers() do
        local nm = GetRaidRosterInfo(i)
        if nm then table.insert(raid.players, nm) end
    end

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(("Created raid instance: %s (%s) using preset %s"):format(name, zone, presetName))
    end

    if RaidTrack.SendRaidSyncData then
        RaidTrack.SendRaidSyncData()
    end
end

-----------------------------------------------------------------------
-- Zakończenie aktywnego raidu
-----------------------------------------------------------------------
function RaidTrack.EndActiveRaid()
    local id = RaidTrack.activeRaidID or RaidTrackDB.activeRaidID
    if not id then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("No active raid to end.") end
        return
    end

    local now = time()
    local changedInstances, changedHistory = false, false

    if RaidTrack.AwardFullAttendanceIfNeededAtEnd then
        pcall(RaidTrack.AwardFullAttendanceIfNeededAtEnd)
    end

    if RaidTrackDB and RaidTrackDB.raidInstances then
        for _, r in ipairs(RaidTrackDB.raidInstances) do
            if tostring(r.id) == tostring(id) then
                if r.status ~= "ended" or not r.ended then
                    r.status = "ended"
                    r.ended  = r.ended or now
                    r.endAt  = r.endAt or r.ended
                    changedInstances = true
                end
                break
            end
        end
    end

    if RaidTrackDB and RaidTrackDB.raidHistory then
        for _, h in ipairs(RaidTrackDB.raidHistory) do
            if tostring(h.id) == tostring(id) then
                if h.status ~= "ended" or not h.ended then
                    h.status = "ended"
                    h.ended  = h.ended or now
                    h.endAt  = h.endAt or h.ended
                    changedHistory = true
                end
                break
            end
        end
    end

    RaidTrack.activeRaidID      = nil
    RaidTrackDB.activeRaidID    = nil
    RaidTrack.currentRaidConfig = nil
    RaidTrack.activeRaidConfig  = nil

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("Raid ended: " .. tostring(id))
    end

    if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
    if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end

    if RaidTrack.BroadcastRaidEnded then
        pcall(RaidTrack.BroadcastRaidEnded, tostring(id), now)
    elseif RaidTrack.BroadcastRaidSync then
        pcall(RaidTrack.BroadcastRaidSync)
    end

    if RaidTrack.SendRaidSyncData then
        pcall(RaidTrack.SendRaidSyncData)
    end

    return (changedInstances or changedHistory) and true or false
end

-----------------------------------------------------------------------
-- Rejestracja zabicia bossa + auto-award EP (jeśli ustawione)
-----------------------------------------------------------------------
function RaidTrack.RegisterBossKill(bossName)
    if not RaidTrack.activeRaidID or not bossName then return end

    for _, raid in ipairs(RaidTrackDB.raidHistory or {}) do
        if raid.id == RaidTrack.activeRaidID then
            raid.bosses[#raid.bosses + 1] = { name = bossName, timestamp = time(), players = {} }

            for i = 1, GetNumGroupMembers() do
                local name = GetRaidRosterInfo(i)
                if name then table.insert(raid.bosses[#raid.bosses].players, name) end
            end

            local ep = raid.settings and raid.settings.awardEP and raid.settings.awardEP.bossKill
            if ep and ep > 0 then
                for _, name in ipairs(raid.bosses[#raid.bosses].players) do
                    RaidTrack.LogEPGPChange(name, ep, 0, "Boss Kill: " .. bossName)
                    table.insert(raid.epLog, { name = name, ep = ep, gp = 0, source = bossName, timestamp = time() })
                end
            end

            if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Boss kill registered: " .. bossName) end
            break
        end
    end
end

-- Auto-hook zdarzenia ENCOUNTER_END
local encounterFrame = CreateFrame("Frame")
encounterFrame:RegisterEvent("ENCOUNTER_END")
encounterFrame:SetScript("OnEvent", function(_, _, encounterID, encounterName, difficultyID, groupSize, success)
    if success == 1 and RaidTrack.activeRaidID then
        RaidTrack.RegisterBossKill(encounterName)
    end
end)

--------------------------------
-- Utils dla UI/EPGP/awards
--------------------------------
function RaidTrack.GetRaidPresetNames()
    local names = {}
    for n in pairs(RaidTrackDB.raidPresets or {}) do
        table.insert(names, n)
    end
    return names
end

-- One-time On-Time award (RL only)
function RaidTrack.AwardOnTimeIfNeeded()
    if not (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) then return end
    local raid = RaidTrack.GetActiveRaidEntry and RaidTrack.GetActiveRaidEntry()
    if not raid then return end
    raid.flags = raid.flags or {}
    if raid.flags.onTimeAwarded then return end

    local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
    local amt = cfg and cfg.awardEP and tonumber(cfg.awardEP.onTime) or 0
    if amt and amt > 0 then
        RaidTrack.AwardEPToCurrentRaidMembers(amt, "On-Time Bonus")
        raid.flags.onTimeAwarded = true
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(("On-Time awarded: EP=%s"):format(tostring(amt))) end
    end
end

-- One-time Full Attendance at raid end (RL only)
function RaidTrack.AwardFullAttendanceIfNeededAtEnd()
    if not (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) then return end
    local raid = RaidTrack.GetActiveRaidEntry and RaidTrack.GetActiveRaidEntry()
    if not raid then return end
    raid.flags = raid.flags or {}
    if raid.flags.fullAttendanceAwarded then return end

    local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
    local amt = cfg and cfg.awardEP and tonumber(cfg.awardEP.fullAttendance) or 0
    local minMin = cfg and tonumber(cfg.minTimeInRaid) or 0

    local started = tonumber(raid.started) or 0
    local okTime  = (started > 0) and (time() - started >= (minMin * 60))

    if amt and amt > 0 and okTime then
        RaidTrack.AwardEPToCurrentRaidMembers(amt, "Full Attendance")
        raid.flags.fullAttendanceAwarded = true
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(("Full Attendance awarded: EP=%s"):format(tostring(amt))) end
    elseif amt and amt > 0 and not okTime then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(("Full Attendance NOT awarded (raid too short, need %d min)"):format(minMin)) end
    end
end
