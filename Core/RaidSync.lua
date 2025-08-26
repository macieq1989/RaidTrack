-- Core/RaidSync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local SYNC_PREFIX = "RTSYNC"
local CHUNK_SIZE = 200
C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)

RaidTrack.lastRaidSyncID = nil

-- ==== DB guards ====
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.raidPresets   = RaidTrackDB.raidPresets   or {}
RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}
-- ====================

-----------------------------------------------------
-- ID generator for sync payload
-----------------------------------------------------
function RaidTrack.GenerateRaidSyncID()
    return tostring(time()) .. tostring(math.random(10000, 99999))
end

-----------------------------------------------------
-- Helpers: raid lookup + reconcile for DC guard
-----------------------------------------------------
local function findInstanceById(id)
    if not id then return nil end
    for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
        if tostring(r.id) == tostring(id) then
            return r
        end
    end
    return nil
end

local function isInstanceEnded(inst)
    if not inst then return false end
    if tonumber(inst.endAt) then return true end
    if tostring(inst.status or ""):lower() == "ended" then return true end
    return false
end

-- Czyść lokalny activeRaidID, jeśli odpowiadająca instancja jest zakończona.
function RaidTrack.ReconcileActiveRaidDCGuard()
    local active = RaidTrack.activeRaidID or RaidTrackDB.activeRaidID
    if not active then return end
    local inst = findInstanceById(active)
    if isInstanceEnded(inst) then
        RaidTrack.activeRaidID   = nil
        RaidTrackDB.activeRaidID = nil
        if RaidTrack.OnRaidEnded then
            pcall(RaidTrack.OnRaidEnded, tostring(inst.id), tonumber(inst.endAt) or time(), "reconcile")
        end
        if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end
        if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
    end
end

-----------------------------------------------------
-- Send: build and broadcast RTSYNC payload
-----------------------------------------------------
function RaidTrack.SendRaidSyncData(opts)
    opts = opts or {}

    local inGuild   = IsInGuild()
    local canRaid   = IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
    local isOfficer = RaidTrack.IsOfficer and RaidTrack.IsOfficer() or false

    -- Upserty presetów/instancji może wysłać każdy członek gildii (GUILD).
    -- RAID tylko gdy RL/Assist i allowRaid.
    if not inGuild and not (opts.allowRaid and canRaid) then
        return
    end

    local function keyCount(tbl)
        local n = 0
        if type(tbl) ~= "table" then return 0 end
        for _ in pairs(tbl) do n = n + 1 end
        return n
    end

    -- aktywny raid (dla wygody UI u odbiorców)
    local activeID, activePreset, activeConfig = nil, nil, nil
    for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
        if tostring(r.status or ""):lower() == "started" and not tonumber(r.endAt) then
            activeID     = r.id
            activePreset = r.preset
            break
        end
    end
    if activeID and activePreset and RaidTrackDB.raidPresets then
        activeConfig = RaidTrackDB.raidPresets[activePreset]
    end

    -- tombstony (kasowania – tylko oficer)
    local removedPresets, removedInstances = {}, {}
    if isOfficer then
        for k, v in pairs(RaidTrackDB._presetTombstones or {}) do
            if v then table.insert(removedPresets, k) end
        end
        for k, v in pairs(RaidTrackDB._instanceTombstones or {}) do
            if v then table.insert(removedInstances, k) end
        end
    end

    local payload = {
        raidSyncID        = RaidTrack.GenerateRaidSyncID(),
        presets           = RaidTrackDB.raidPresets or {},
        instances         = RaidTrackDB.raidInstances or {},
        presetsCount      = keyCount(RaidTrackDB.raidPresets),
        instancesCount    = keyCount(RaidTrackDB.raidInstances),
        removedPresets    = (isOfficer and #removedPresets > 0) and removedPresets or nil,
        removedInstances  = (isOfficer and #removedInstances > 0) and removedInstances or nil,
        activeID          = activeID,
        activePreset      = activePreset,
        activeConfig      = activeConfig,
    }

    RaidTrack.lastRaidSyncID = payload.raidSyncID

    local serialized = RaidTrack.SafeSerialize(payload)
    if not serialized then return end

    -- Kanał: aktywny → RAID; inaczej → GUILD (dla każdego w gildii)
    local channel = activeID and "RAID" or (inGuild and "GUILD" or "RAID")
    RaidTrack.QueueChunkedSend(nil, "RTSYNC", serialized, channel)

    if isOfficer then
        if #removedPresets > 0 then RaidTrackDB._presetTombstones = {} end
        if #removedInstances > 0 then RaidTrackDB._instanceTombstones = {} end
    end
end







-- Szybki publiczny helper do broadcastu (np. po end raidu)
function RaidTrack.BroadcastRaidSync()
    RaidTrack.SendRaidSyncData({ allowRaid = true })
end

-- Wywołaj to po faktycznym zakończeniu raidu (gdy zaktualizujesz instances/endAt/status):
-- * kanał pójdzie na GUILD (bo activeID już nie istnieje), więc inni dowiedzą się, że raid jest skończony
function RaidTrack.BroadcastRaidEnded(raidId, endTs)
    raidId = raidId or (RaidTrack.activeRaidID or RaidTrackDB.activeRaidID)
    if raidId then
        local inst = findInstanceById(raidId)
        if inst then
            inst.endAt = tonumber(endTs) or inst.endAt or time()
            inst.status = "ended"
        end
    end
    -- wyślij najnowszy obraz (bez activeID)
    RaidTrack.SendRaidSyncData({ allowRaid = true })
end

-----------------------------------------------------
-- Receive: apply RTSYNC payload safely
-----------------------------------------------------
function RaidTrack.ApplyRaidSyncData(data, sender)
    if not data or type(data) ~= "table" then return end

    local function keyCount(tbl)
        local n = 0
        if type(tbl) ~= "table" then return 0 end
        for _ in pairs(tbl) do n = n + 1 end
        return n
    end
    local function upsertAll(dst, src)
        if type(dst) ~= "table" or type(src) ~= "table" then return false end
        local changed = false
        for k, v in pairs(src) do
            if dst[k] ~= v then
                dst[k] = v
                changed = true
            end
        end
        return changed
    end
    local function removeKeys(dst, toRemove)
        if type(dst) ~= "table" or type(toRemove) ~= "table" then return false end
        local changed = false
        for _, k in ipairs(toRemove) do
            if dst[k] ~= nil then
                dst[k] = nil
                changed = true
            end
        end
        return changed
    end

    -- init
    RaidTrackDB.raidPresets   = RaidTrackDB.raidPresets   or {}
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

    local localPresetsCount   = keyCount(RaidTrackDB.raidPresets)
    local localInstancesCount = keyCount(RaidTrackDB.raidInstances)

    local incomingPresetsCount   = tonumber(data.presetsCount)   or keyCount(data.presets)
    local incomingInstancesCount = tonumber(data.instancesCount) or keyCount(data.instances)

    local hasRemovals = (type(data.removedPresets) == "table" and #data.removedPresets > 0)
                     or (type(data.removedInstances) == "table" and #data.removedInstances > 0)

    local changed = false

    -- Jeśli nie ma jawnych usunięć i snapshot jest mniejszy niż lokalny → ignorujemy merge (chroni przed pustką)
    if not hasRemovals
       and (incomingPresetsCount   < localPresetsCount
         or incomingInstancesCount < localInstancesCount) then
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("[RaidSync] Ignored smaller snapshot from %s (P:%d<%d, I:%d<%d)")
                :format(tostring(sender or "?"), incomingPresetsCount, localPresetsCount, incomingInstancesCount, localInstancesCount))
        end
    else
        -- Merge + ewentualne kasowania (TYLKO jawne)
        changed = upsertAll(RaidTrackDB.raidPresets,   data.presets   or {}) or changed
        changed = upsertAll(RaidTrackDB.raidInstances, data.instances or {}) or changed
        changed = removeKeys(RaidTrackDB.raidPresets,   data.removedPresets   or {}) or changed
        changed = removeKeys(RaidTrackDB.raidInstances, data.removedInstances or {}) or changed
    end

    -- Aktywny raid tylko jeśli jesteśmy w raidzie i instancja nie jest zakończona
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end
    local instForActive = data.activeID and findInstanceById(data.activeID) or nil
    if instForActive and isInstanceEnded(instForActive) then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end

    if data.activeID then
        RaidTrack.activeRaidID   = data.activeID
        RaidTrackDB.activeRaidID = data.activeID

        local cfg = data.activeConfig
        if not cfg and data.activePreset and RaidTrackDB.raidPresets then
            cfg = RaidTrackDB.raidPresets[data.activePreset]
        end
        if not cfg then
            local inst = findInstanceById(data.activeID)
            if inst and inst.preset and RaidTrackDB.raidPresets then
                cfg = RaidTrackDB.raidPresets[inst.preset]
            end
        end
        RaidTrack.currentRaidConfig = cfg or nil

        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("[RaidSync] applied from %s: activeID=%s preset=%s cfg=%s")
                :format(tostring(sender or "?"), tostring(data.activeID), tostring(data.activePreset),
                        RaidTrack.currentRaidConfig and "OK" or "nil"))
        end
    end

    -- DC guard
    RaidTrack.ReconcileActiveRaidDCGuard()

    -- UI
    if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
    if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end

    -- Rebroadcast tylko jeśli coś się zmieniło ORAZ nie jest to nasz własny pakiet (echo guard)
    if changed and RaidTrack.SendRaidSyncData and data.raidSyncID ~= RaidTrack.lastRaidSyncID then
        -- tylko jeśli mamy uprawnienia i/lub w raidu (SendRaidSyncData samo to sprawdza)
        pcall(RaidTrack.SendRaidSyncData)
    end
end


-----------------------------------------------------
-- Chunk handler registration
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

    -- complete?
    for i = 1, total do
        if not buf[i] then
            return
        end
    end

    local full = table.concat(buf)
    RaidTrack._chunkBuffers[sender] = nil

    local ok, data = RaidTrack.SafeDeserialize(full)
    if ok then
        RaidTrack.ApplyRaidSyncData(data, sender)
    else
        RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from " .. tostring(sender))
    end
end)

-----------------------------------------------------
-- Legacy compatibility shim (was in your file)
-- Ensure no duplicate logic diverges.
-----------------------------------------------------

function RaidTrack.MergeRaidSyncData(data, sender)
    -- wsteczna kompatybilność nazwy
    if RaidTrack.ApplyRaidSyncData then
        RaidTrack.ApplyRaidSyncData(data, sender)
    end
end


-----------------------------------------------------
-- Startup: reconcile DC guard on login (in case no sync arrives)
-----------------------------------------------------
local _rt_login = CreateFrame("Frame")
_rt_login:RegisterEvent("PLAYER_LOGIN")
_rt_login:SetScript("OnEvent", function()
    C_Timer.After(0.2, function()
        if RaidTrack.ReconcileActiveRaidDCGuard then
            RaidTrack.ReconcileActiveRaidDCGuard()
        end
    end)
end)
