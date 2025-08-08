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
function RaidTrack.SendRaidSyncData()
    if not RaidTrack.IsOfficer() then return end

    local function GetMyGuildRank()
        local me = UnitName("player")
        for i = 1, GetNumGuildMembers() do
            local name, _, rankIndex = GetGuildRosterInfo(i)
            if name and Ambiguate(name, "short") == me then
                return rankIndex
            end
        end
        return nil
    end

    local rank = GetMyGuildRank()
    if not rank or rank > (RaidTrackDB.settings.minSyncRank or 1) then return end

    local syncID = RaidTrack.GenerateRaidSyncID()
    RaidTrack.lastRaidSyncID = syncID

    local payload = {
        raidSyncID = syncID,
        presets = RaidTrackDB.raidPresets or {},
        instances = RaidTrackDB.raidInstances or {},
        activeID = RaidTrack.activeRaidID
    }

    local serialized = RaidTrack.SafeSerialize(payload)
    RaidTrack.AddDebugMessage("📨 Broadcasting RTSYNC via " .. (IsInRaid() and "RAID" or "GUILD"))
    RaidTrack.QueueChunkedSend(nil, "RTSYNC", serialized, IsInRaid() and "RAID" or "GUILD")
end


-----------------------------------------------------
-- Funkcja: Broadcast danych do całego raidu
-----------------------------------------------------
function RaidTrack.BroadcastRaidSync()
    RaidTrack.AddDebugMessage("📣 BroadcastRaidSync() wywołany!")
    RaidTrack.SendRaidSyncData()
end


-----------------------------------------------------
-- Funkcja: Odbierz i zastosuj dane raidowe
-----------------------------------------------------
function RaidTrack.ApplyRaidSyncData(data)
    if type(data) ~= "table" then
        return
    end

    if data.raidSyncID and RaidTrack.lastRaidSyncID and data.raidSyncID == RaidTrack.lastRaidSyncID then
        RaidTrack.AddDebugMessage("🔁 Duplicate RaidSync ignored.")
        return
    end

    RaidTrack.lastRaidSyncID = data.raidSyncID
    RaidTrackDB.raidPresets = data.presets or {}
    RaidTrackDB.raidInstances = data.instances or {}
    RaidTrack.activeRaidID = data.activeID

    -- Apply active config
    if data.activeID then
        for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
            if r.id == data.activeID and r.preset then
                RaidTrack.currentRaidConfig = RaidTrackDB.raidPresets[r.preset]
                break
            end
        end
    end

    -- Odśwież UI
    if RaidTrack.RefreshRaidDropdown then
        RaidTrack.RefreshRaidDropdown()
    end
    if RaidTrack.UpdateRaidTabStatus then
        RaidTrack.UpdateRaidTabStatus()
    end

    RaidTrack.AddDebugMessage("✅ Applied RaidSync from syncID: " .. tostring(data.raidSyncID))
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
            RaidTrack.AddDebugMessage("📡 Received RaidSync from: " .. tostring(sender))
            RaidTrack.ApplyRaidSyncData(data)
        else
            RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from " .. tostring(sender))
        end
    end
end)

function RaidTrack.MergeRaidSyncData(data, sender)
    RaidTrack.AddDebugMessage("🔄 MergeRaidSyncData called from " .. tostring(sender))

    RaidTrackDB.raidPresets = data.presets or {}
    RaidTrackDB.raidInstances = data.instances or {}
    RaidTrack.activeRaidID = data.activeID

    RaidTrack.AddDebugMessage("✅ RaidSync merged successfully from " .. tostring(sender))
    if RaidTrack.RefreshRaidDropdown then
        RaidTrack.RefreshRaidDropdown()
    end
end

