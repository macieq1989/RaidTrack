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

    -- przygotuj listy usuniętych (tombstony)
    local removedPresets, removedInstances = {}, {}
    for k, v in pairs(RaidTrackDB._presetTombstones or {}) do
        if v then table.insert(removedPresets, k) end
    end
    for k, v in pairs(RaidTrackDB._instanceTombstones or {}) do
        if v then table.insert(removedInstances, k) end
    end

    -- liczniki (bezpiecznik po stronie odbiorcy)
    local function keyCount(tbl)
        local n = 0
        if type(tbl) ~= "table" then return 0 end
        for _ in pairs(tbl) do n = n + 1 end
        return n
    end

    local payload = {
        raidSyncID        = RaidTrack.GenerateRaidSyncID(),
        presets           = RaidTrackDB.raidPresets or {},
        instances         = RaidTrackDB.raidInstances or {},
        presetsCount      = keyCount(RaidTrackDB.raidPresets),
        instancesCount    = keyCount(RaidTrackDB.raidInstances),
        removedPresets    = (#removedPresets > 0) and removedPresets or nil,
        removedInstances  = (#removedInstances > 0) and removedInstances or nil,
        activeID          = activeID,
        activePreset      = activePreset,
        activeConfig      = activeConfig
    }

    local msg = RaidTrack.SafeSerialize(payload)
    if not msg then return end

    -- guild broadcast
    C_ChatInfo.SendAddonMessage("RTSYNC", msg, IsInGuild() and "GUILD" or "RAID")

    -- jeśli udało się wysłać, wyczyść lokalne tombstony (założenie: rozgłoszone)
    RaidTrackDB._presetTombstones   = {}
    RaidTrackDB._instanceTombstones = {}
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

    -- helpers
    local function keyCount(tbl)
        local n = 0
        if type(tbl) ~= "table" then return 0 end
        for _ in pairs(tbl) do n = n + 1 end
        return n
    end
    local function upsertAll(dst, src)
        if type(dst) ~= "table" then return end
        if type(src) ~= "table" then return end
        for k, v in pairs(src) do
            dst[k] = v
        end
    end
    local function removeKeys(dst, toRemove)
        if type(dst) ~= "table" then return end
        if type(toRemove) ~= "table" then return end
        for _, k in ipairs(toRemove) do
            dst[k] = nil
        end
    end

    -- upewnij się, że bazy istnieją
    RaidTrackDB.raidPresets   = RaidTrackDB.raidPresets   or {}
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

    -- 1) Bezpieczniki przed pustym/mniejszym snapshotem (bez jawnych usunięć)
    local hasRemovals = (type(data.removedPresets) == "table" and #data.removedPresets > 0)
                     or (type(data.removedInstances) == "table" and #data.removedInstances > 0)

    local localPresetsCount   = keyCount(RaidTrackDB.raidPresets)
    local localInstancesCount = keyCount(RaidTrackDB.raidInstances)

    local incomingPresetsCount   = tonumber(data.presetsCount)   or keyCount(data.presets)
    local incomingInstancesCount = tonumber(data.instancesCount) or keyCount(data.instances)

    if not hasRemovals then
        -- jeśli nadawca ma mniej wpisów (np. świeża/pusta baza), ignorujemy jego snapshot – niech najpierw pobierze
        if incomingPresetsCount   < localPresetsCount
        or incomingInstancesCount < localInstancesCount then
            RaidTrack.AddDebugMessage(("[RaidSync] Ignored smaller snapshot from %s (P:%d<%d, I:%d<%d)")
                :format(tostring(sender), incomingPresetsCount, localPresetsCount, incomingInstancesCount, localInstancesCount))
            -- mimo to obrobimy jeszcze sekcję aktywnego raidu niżej (żeby nie blokować UI)
        else
            -- 2) Merge (upsert) – nigdy nie nadpisujemy całej tabeli
            upsertAll(RaidTrackDB.raidPresets,   data.presets   or {})
            upsertAll(RaidTrackDB.raidInstances, data.instances or {})
        end
    else
        -- 3) Jeżeli są jawne usunięcia, najpierw upserty, potem kasowania tylko z listy
        upsertAll(RaidTrackDB.raidPresets,   data.presets   or {})
        upsertAll(RaidTrackDB.raidInstances, data.instances or {})
        removeKeys(RaidTrackDB.raidPresets,   data.removedPresets   or {})
        removeKeys(RaidTrackDB.raidInstances, data.removedInstances or {})
    end

    -- 4) Nie aktywuj raidu spoza grupy
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end

    -- 5) Ustaw aktywny raid + config (bez zmian względem Twojej logiki)
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

        RaidTrack.activeRaidConfig = cfg
    end

    if RaidTrack.RefreshRaidDropdown then
        RaidTrack.RefreshRaidDropdown()
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
RaidTrack.ApplyRaidSyncData(data, sender)

    if RaidTrack.RefreshRaidDropdown then
        RaidTrack.RefreshRaidDropdown()
    end
end

