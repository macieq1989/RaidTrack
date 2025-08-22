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

    local canGuild = RaidTrack.IsOfficer and RaidTrack.IsOfficer() or false
    local canRaid  = IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))

    if not canGuild and not (opts.allowRaid and canRaid) then
        return
    end

    -- znajdź aktywny raid i jego preset
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

    local payload = {
        raidSyncID   = RaidTrack.GenerateRaidSyncID(),
        presets      = RaidTrackDB.raidPresets or {},
        instances    = RaidTrackDB.raidInstances or {},
        activeID     = activeID,              -- NULL jeśli raid zakończony
        activePreset = activePreset,
        activeConfig = activeConfig,          -- migawka – ważne dla UI
    }

    RaidTrack.lastRaidSyncID = payload.raidSyncID

    local serialized = RaidTrack.SafeSerialize(payload)

    -- Jeśli jest aktywny raid → TYLKO kanał RAID (żeby nie „aktywować” u osób spoza raidu)
    -- Jeśli nie ma aktywnego (po end) → wyślij na GUILD (oficer), aby rozpropagować „end” szeroko.
    local channel
    if activeID then
        channel = "RAID"
    else
        channel = (canGuild and "GUILD") or "RAID"
    end

    RaidTrack.QueueChunkedSend(nil, SYNC_PREFIX, serialized, channel)
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

    -- 1) merge bazy (migawka, nie agresywne czyszczenie)
    RaidTrackDB.raidPresets   = data.presets   or RaidTrackDB.raidPresets   or {}
    RaidTrackDB.raidInstances = data.instances or RaidTrackDB.raidInstances or {}

    -- 2) nie aktywuj raidu, jeśli nie jesteś w raidzie
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end

    -- 3) nie aktywuj raidu, jeśli instancja ma endAt/ended (nawet jeśli nadawca podał activeID)
    local instForActive = data.activeID and findInstanceById(data.activeID) or nil
    if instForActive and isInstanceEnded(instForActive) then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end

    -- 4) ustaw aktywny raid + config (tylko jeśli spełnia warunki jw.)
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

    -- 5) krytyczny krok: jeśli lokalny DC guard trzymał aktywny raid, a instancja ma endAt → wyczyść
    RaidTrack.ReconcileActiveRaidDCGuard()

    -- 6) UI
    if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
    if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end
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
    -- Przekieruj do nowej, bezpiecznej ścieżki
    RaidTrack.ApplyRaidSyncData(data, sender)
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
