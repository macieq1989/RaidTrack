-- Core/RaidSync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local SYNC_PREFIX = "RTSYNC"
local CHUNK_SIZE = 200
C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)

RaidTrack.lastRaidSyncID = nil

-----------------------------------------------------
-- Funkcja: Wygeneruj unikalny ID dla paczki sync
-----------------------------------------------------
function RaidTrack.GenerateRaidSyncID()
    return tostring(time()) .. tostring(math.random(10000, 99999))
end

-----------------------------------------------------
-- Funkcja: Wyślij dane raidowe do targeta
-----------------------------------------------------

-- Core/RaidSync.lua
function RaidTrack.SendRaidSyncData(opts)
    opts = opts or {}

    local canGuild = RaidTrack.IsOfficer and RaidTrack.IsOfficer() or false
    local canRaid  = IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))

    if not canGuild and not (opts.allowRaid and canRaid) then
        return
    end

    -- znajdź aktywny raid i jego preset
    local activeID, activePreset, activeConfig = nil, nil, nil
    for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
        if r.status == "started" then
            activeID     = r.id
            activePreset = r.preset
            break
        end
    end

    if activeID and activePreset and RaidTrackDB.raidPresets then
        activeConfig = RaidTrackDB.raidPresets[activePreset]
    end

    local payload = {
        raidSyncID   = RaidTrack.GenerateRaidSyncID(),
        presets      = RaidTrackDB.raidPresets or {},
        instances    = RaidTrackDB.raidInstances or {},
        activeID     = activeID,
        activePreset = activePreset,
        activeConfig = activeConfig,   -- migawka – kluczowe!
    }

    RaidTrack.lastRaidSyncID = payload.raidSyncID

    local serialized = RaidTrack.SafeSerialize(payload)

    -- Jeśli jest aktywny raid → TYLKO kanał RAID (żeby nie „aktywować” u osób spoza raidu)
    local channel
    if activeID then
        channel = "RAID"
    else
        channel = (canGuild and "GUILD") or "RAID"
    end

    RaidTrack.QueueChunkedSend(nil, "RTSYNC", serialized, channel)
end



-----------------------------------------------------
-- Funkcja: Broadcast danych do całego raidu
-----------------------------------------------------
function RaidTrack.BroadcastRaidSync()
    -- pozwól przynajmniej RL/Assist nadawać do RAID
    RaidTrack.SendRaidSyncData({ allowRaid = true })
end



-----------------------------------------------------
-- Funkcja: Odbierz i zastosuj dane raidowe
-----------------------------------------------------
function RaidTrack.ApplyRaidSyncData(data, sender)
    if not data or type(data) ~= "table" then return end

    -- 1) merge bazy
    RaidTrackDB.raidPresets   = data.presets   or RaidTrackDB.raidPresets   or {}
    RaidTrackDB.raidInstances = data.instances or RaidTrackDB.raidInstances or {}

    -- 2) nie aktywuj raidu spoza grupy
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end

    -- 3) ustaw aktywny raid + config
    if data.activeID then
        RaidTrack.activeRaidID   = data.activeID
        RaidTrackDB.activeRaidID = data.activeID

        local cfg = data.activeConfig
        if not cfg and data.activePreset and RaidTrackDB.raidPresets then
            cfg = RaidTrackDB.raidPresets[data.activePreset]
        end
        if not cfg then
            for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
                if tostring(r.id) == tostring(data.activeID) and r.preset then
                    cfg = RaidTrackDB.raidPresets and RaidTrackDB.raidPresets[r.preset]
                    break
                end
            end
        end

        RaidTrack.currentRaidConfig = cfg or nil

        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("[RaidSync] applied from %s: activeID=%s preset=%s cfg=%s")
                :format(tostring(sender or "?"), tostring(data.activeID), tostring(data.activePreset),
                        RaidTrack.currentRaidConfig and "OK" or "nil"))
        end
    end

    -- 4) odśwież UI
    if RaidTrack.RefreshRaidDropdown then RaidTrack.RefreshRaidDropdown() end
    if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end
end


-----------------------------------------------------
-- Rejestracja handlera
-----------------------------------------------------

RaidTrack.RegisterChunkHandler(SYNC_PREFIX, function(sender, msg)
    local index, total, chunk = msg:match("^RTCHUNK%^(%d+)%^(%d+)%^(.+)$")
    if not index or not total or not chunk then
        return
    end
    index = tonumber(index)
    total = tonumber(total)

    RaidTrack._chunkBuffers = RaidTrack._chunkBuffers or {}
    RaidTrack._chunkBuffers[sender] = RaidTrack._chunkBuffers[sender] or {}
    local buf = RaidTrack._chunkBuffers[sender]

    buf[index] = chunk

    -- check if all chunks received
    local complete = true
    for i = 1, total do
        if not buf[i] then
            complete = false
            break
        end
    end

    if complete then
        local full = table.concat(buf)
        RaidTrack._chunkBuffers[sender] = nil
        local ok, data = RaidTrack.SafeDeserialize(full)
        if ok then

            RaidTrack.ApplyRaidSyncData(data)
        else
            RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from " .. tostring(sender))
        end
    end
end)

function RaidTrack.MergeRaidSyncData(data, sender)

    RaidTrackDB.raidPresets = data.presets or {}
    RaidTrackDB.raidInstances = data.instances or {}
    RaidTrack.activeRaidID = data.activeID

    if RaidTrack.RefreshRaidDropdown then
        RaidTrack.RefreshRaidDropdown()
    end
end

