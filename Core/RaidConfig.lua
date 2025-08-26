-- Core/RaidConfig.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}


-- Zapisuje preset pod daną nazwą
function RaidTrack.SaveRaidPreset(name, config)
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
    RaidTrackDB._presetTombstones = RaidTrackDB._presetTombstones or {}

    -- sanitize nazwy
    if type(name) ~= "string" then
        RaidTrack.AddDebugMessage("SaveRaidPreset: invalid name type")
        return
    end
    -- trim tylko z brzegów (nie zmieniamy liter/spacji w środku, żeby nie psuć istniejących odwołań)
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        RaidTrack.AddDebugMessage("SaveRaidPreset: empty name after trim")
        return
    end
    name = trimmed

    if type(config) ~= "table" then
        RaidTrack.AddDebugMessage("SaveRaidPreset: invalid config type")
        return
    end

    -- Bezpieczna kopia: wycinamy funkcje/userdata/thread i metatabele, zostawiamy tylko {table,string,number,boolean}
    local function SanitizeTable(src, seen)
        if type(src) ~= "table" then return {} end
        seen = seen or {}
        if seen[src] then return {} end
        seen[src] = true

        local dst = {}
        -- zerknij czy była metatabela i ją ignoruj (AceSerializer nie lubi)
        setmetatable(dst, nil)

        for k, v in pairs(src) do
            local kt = type(k)
            local vt = type(v)
            -- klucze inne niż string/number zamieniamy na string (żeby serializacja nie poleciała)
            local key = (kt == "string" or kt == "number") and k or tostring(k)

            if vt == "table" then
                dst[key] = SanitizeTable(v, seen)
            elseif vt == "string" or vt == "number" or vt == "boolean" then
                dst[key] = v
            else
                -- pomijamy: function, userdata, thread, nil
                -- (nil i tak by nie został zapisany)
            end
        end
        return dst
    end

    local cleanConfig = SanitizeTable(config)

    -- zapis/aktualizacja
    RaidTrackDB.raidPresets[name] = cleanConfig

    -- jeśli wcześniej był tombstone po delete — usuń go
    if RaidTrackDB._presetTombstones[name] then
        RaidTrackDB._presetTombstones[name] = nil
    end

    -- (opcjonalnie) lekka diagnoza rozmiaru — pomoże gdyby kiedyś wlazło w limity
    if RaidTrack.SafeSerialize then
        local s = RaidTrack.SafeSerialize({test=cleanConfig})
        if s and type(s) == "string" then
            RaidTrack.AddDebugMessage(("Saved raid preset: %s (approx %d bytes)"):format(name, #s))
        else
            RaidTrack.AddDebugMessage("Saved raid preset: "..name)
        end
    else
        RaidTrack.AddDebugMessage("Saved raid preset: "..name)
    end

  -- odśwież UI
if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
-- batched flush (eliminuje spam przy serii zmian)
if RaidTrack.RequestRaidSyncFlush then
    RaidTrack.RequestRaidSyncFlush(0.35)
elseif RaidTrack.SendRaidSyncData then
    RaidTrack.SendRaidSyncData()
end

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
    RaidTrackDB._presetTombstones = RaidTrackDB._presetTombstones or {}

    if type(name) ~= "string" then
        RaidTrack.AddDebugMessage("DeleteRaidPreset: invalid name")
        return
    end
    -- TRIM nazwy jak w Save (unikniemy rozjazdów "Foo" vs "Foo ")
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        RaidTrack.AddDebugMessage("DeleteRaidPreset: empty name after trim")
        return
    end
    name = trimmed

    if RaidTrackDB.raidPresets[name] ~= nil then
        RaidTrackDB.raidPresets[name] = nil
        RaidTrack.AddDebugMessage("Deleted raid preset (local): " .. name)
    else
        RaidTrack.AddDebugMessage("Tombstoning non-existing preset (for propagation): " .. name)
    end

    -- ZAWSZE wystaw tombstone (żeby inni usunęli)
    RaidTrackDB._presetTombstones[name] = true

    -- Batch flush (unikamy floodu przy serii kasowań)
    if RaidTrack.RequestRaidSyncFlush then
        RaidTrack.RequestRaidSyncFlush(0.5)
    elseif RaidTrack.SendRaidSyncData then
        RaidTrack.SendRaidSyncData()
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
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.raidPresets   = RaidTrackDB.raidPresets   or {}
    RaidTrackDB.raidHistory   = RaidTrackDB.raidHistory   or {}
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

    local preset = RaidTrackDB.raidPresets[presetName]
    if not preset then
        RaidTrack.AddDebugMessage("CreateRaidInstance: preset not found: " .. tostring(presetName))
        return
    end

    local now = time()
    local id  = forcedId or now

    -- pełny wpis do historii (szczegóły do UI/EPGP)
    local raid = {
        id = id,
        name = name,
        zone = zone,
        date = date("%Y-%m-%d"),
        started = now,
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

    -- skrócony wpis do instancji (to leci w sync)
    table.insert(RaidTrackDB.raidInstances, {
        id = id,
        title = name,
        zone = zone,
        preset = presetName,
        status = "started",
        startAt = now,
        ended = nil,
        endAt = nil,
    })

    -- ustaw aktywny raid
    RaidTrack.activeRaidID = id
    RaidTrackDB.activeRaidID = id

    -- zaciągnij graczy z grupy
    for i = 1, GetNumGroupMembers() do
        local nm = GetRaidRosterInfo(i)
        if nm then
            table.insert(raid.players, nm)
        end
    end

    RaidTrack.AddDebugMessage("Created raid instance: " .. name .. " (" .. zone .. ") using preset " .. presetName)

    -- natychmiastowy sync (żeby każdy zobaczył nowy raid)
    if RaidTrack.SendRaidSyncData then
        RaidTrack.SendRaidSyncData()
    end
end


function RaidTrack.EndActiveRaid()
    local id = RaidTrack.activeRaidID or RaidTrackDB.activeRaidID
    if not id then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("No active raid to end.") end
        return
    end

    local now = time()
    local changedInstances, changedHistory = false, false

    -- One-time Full Attendance (before clearing active)
    if RaidTrack.AwardFullAttendanceIfNeededAtEnd then
        pcall(RaidTrack.AwardFullAttendanceIfNeededAtEnd)
    end

    -- Mark 'ended' in raidInstances (set both ended + endAt for consistency)
    if RaidTrackDB and RaidTrackDB.raidInstances then
        for _, r in ipairs(RaidTrackDB.raidInstances) do
            if tostring(r.id) == tostring(id) then
                if r.status ~= "ended" or not r.ended then
                    r.status = "ended"
                    r.ended  = r.ended  or now
                    r.endAt  = r.endAt  or r.ended
                    changedInstances = true
                end
                break
            end
        end
    end

    -- Mark 'ended' in raidHistory
    if RaidTrackDB and RaidTrackDB.raidHistory then
        for _, h in ipairs(RaidTrackDB.raidHistory) do
            if tostring(h.id) == tostring(id) then
                if h.status ~= "ended" or not h.ended then
                    h.status = "ended"
                    h.ended  = h.ended  or now
                    h.endAt  = h.endAt  or h.ended
                    changedHistory = true
                end
                break
            end
        end
    end

    -- Clear local active state
    RaidTrack.activeRaidID      = nil
    RaidTrackDB.activeRaidID    = nil
    RaidTrack.currentRaidConfig = nil
    RaidTrack.activeRaidConfig  = nil

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("Raid ended: " .. tostring(id))
    end

    -- UI refresh (protected)
    if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
    if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end

    -- Broadcast a dedicated "ended" snapshot on GUILD so offline clients learn about it on login
    if RaidTrack.BroadcastRaidEnded then
        pcall(RaidTrack.BroadcastRaidEnded, tostring(id), now)
    else
        -- fallback if helper not present
        if RaidTrack.BroadcastRaidSync then pcall(RaidTrack.BroadcastRaidSync) end
    end

    -- Always push a fresh sync so wszyscy od razu widzą status=ended
    if RaidTrack.SendRaidSyncData then
        pcall(RaidTrack.SendRaidSyncData)
    end

    return (changedInstances or changedHistory) and true or false
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

