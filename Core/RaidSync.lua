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

    local activeIDToSend = nil
    for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
        if r.status == "started" then
            activeIDToSend = r.id
            break
        end
    end

    local payload = {
        raidSyncID = RaidTrack.GenerateRaidSyncID(),
        presets    = RaidTrackDB.raidPresets or {},
        instances  = RaidTrackDB.raidInstances or {},
        activeID   = activeIDToSend
    }

    RaidTrack.lastRaidSyncID = payload.raidSyncID

    local serialized = RaidTrack.SafeSerialize(payload)

    -- 🔒 Jeśli jest aktywny raid -> wyślij TYLKO na RAID
    --    (presety nadal polecą też GUILD, gdy nie ma activeID)
    local channel
    if activeIDToSend then
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
    -- Spróbuj do gildii (jeśli wolno), a jak nie – to przynajmniej do RAIDu od RL/Assist
    RaidTrack.SendRaidSyncData({ allowRaid = true })
end


-----------------------------------------------------
-- Funkcja: Odbierz i zastosuj dane raidowe
-----------------------------------------------------
function RaidTrack.ApplyRaidSyncData(data)
    if type(data) ~= "table" then
        return
    end

    if data.raidSyncID and RaidTrack.lastRaidSyncID and data.raidSyncID == RaidTrack.lastRaidSyncID then

        return
    end

    RaidTrack.lastRaidSyncID = data.raidSyncID
    RaidTrackDB.raidPresets = data.presets or {}
    RaidTrackDB.raidInstances = data.instances or {}

    -- Validate incoming activeID: accept only if that raid is actually "started"
    local incomingActive = data.activeID
    if incomingActive ~= nil then
        local valid = false
        for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
            if r.id == incomingActive and r.status == "started" then
                valid = true
                break
            end
        end
        if not valid then
            incomingActive = nil
        end
    end

    RaidTrack.activeRaidID = incomingActive

    -- Apply active config only if we have a valid started raid
    if RaidTrack.activeRaidID then
        for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
            if r.id == RaidTrack.activeRaidID and r.preset then
                RaidTrack.currentRaidConfig = RaidTrackDB.raidPresets[r.preset]
                break
            end
        end
    else
        -- No active raid -> clear currentRaidConfig to avoid stale UI state
        RaidTrack.currentRaidConfig = nil
    end

    -- Odśwież UI
    if RaidTrack.RefreshRaidDropdown then
        RaidTrack.RefreshRaidDropdown()
    end
    if RaidTrack.UpdateRaidTabStatus then
        RaidTrack.UpdateRaidTabStatus()
    end

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

