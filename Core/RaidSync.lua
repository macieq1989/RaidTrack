-- Core/RaidSync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local SYNC_PREFIX = "RTSYNC"
local CHUNK_SIZE = 200
C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)

RaidTrack.lastRaidSyncID = nil

-- ==== DB guards ====
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
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
local TOMBSTONE_TTL = 7 * 24 * 60 * 60 -- 7 dni; zmień wg potrzeb

local function _isTombstonedPreset(name)
    local ts = RaidTrackDB._presetTombstones and RaidTrackDB._presetTombstones[name]
    return type(ts) == "number" and (time() - ts) <= TOMBSTONE_TTL
end

local function _isTombstonedInstance(id)
    id = tostring(id)
    local ts = RaidTrackDB._instanceTombstones and RaidTrackDB._instanceTombstones[id]
    return type(ts) == "number" and (time() - ts) <= TOMBSTONE_TTL
end

local function _pruneTombstones()
    local now = time()
    if RaidTrackDB._presetTombstones then
        for k, ts in pairs(RaidTrackDB._presetTombstones) do
            if type(ts) ~= "number" or (now - ts) > TOMBSTONE_TTL then
                RaidTrackDB._presetTombstones[k] = nil
            end
        end
    end
    if RaidTrackDB._instanceTombstones then
        for k, ts in pairs(RaidTrackDB._instanceTombstones) do
            if type(ts) ~= "number" or (now - ts) > TOMBSTONE_TTL then
                RaidTrackDB._instanceTombstones[k] = nil
            end
        end
    end
end

local function findInstanceById(id)
    if not id then
        return nil
    end
    for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
        if tostring(r.id) == tostring(id) then
            return r
        end
    end
    return nil
end

local function isInstanceEnded(inst)
    if not inst then
        return false
    end
    if tonumber(inst.endAt) then
        return true
    end
    if tostring(inst.status or ""):lower() == "ended" then
        return true
    end
    return false
end

-- Czyść lokalny activeRaidID, jeśli odpowiadająca instancja jest zakończona.
function RaidTrack.ReconcileActiveRaidDCGuard()
    local active = RaidTrack.activeRaidID or RaidTrackDB.activeRaidID
    if not active then
        return
    end
    local inst = findInstanceById(active)
    if isInstanceEnded(inst) then
        RaidTrack.activeRaidID = nil
        RaidTrackDB.activeRaidID = nil
        if RaidTrack.OnRaidEnded then
            pcall(RaidTrack.OnRaidEnded, tostring(inst.id), tonumber(inst.endAt) or time(), "reconcile")
        end
        if RaidTrack.UpdateRaidTabStatus then
            pcall(RaidTrack.UpdateRaidTabStatus)
        end
        if RaidTrack.RefreshRaidDropdown then
            pcall(RaidTrack.RefreshRaidDropdown)
        end
    end
end
-- Throttle'owane odświeżenie UI po sync
RaidTrack._uiRefreshPending = false
function RaidTrack.RequestUIRefresh(reason)
    if RaidTrack._uiRefreshPending then
        return
    end
    RaidTrack._uiRefreshPending = true
    C_Timer.After(0.15, function()
        RaidTrack._uiRefreshPending = false
        -- Odśwież to, co masz w addon'ie (pcall = bezpiecznie jeśli czegoś nie ma)
        if RaidTrack.RefreshRaidDropdown then
            pcall(RaidTrack.RefreshRaidDropdown)
        end
        if RaidTrack.UpdateRaidTabStatus then
            pcall(RaidTrack.UpdateRaidTabStatus)
        end
        if RaidTrack.RefreshRaidTab then
            pcall(RaidTrack.RefreshRaidTab)
        end
        if RaidTrack.RefreshPresetDropdown then
            pcall(RaidTrack.RefreshPresetDropdown)
        end
        if RaidTrack.RefreshBossesView then
            pcall(RaidTrack.RefreshBossesView)
        end
    end)
end

-- Debounce/Batch flush RTSYNC (żeby nie floodować serwera)
RaidTrack._rs_flushScheduled = false
function RaidTrack.RequestRaidSyncFlush(delay)
    delay = tonumber(delay) or 0.4 -- 400 ms ok do “złapania” serii delete/save
    if RaidTrack._rs_flushScheduled then
        return
    end
    RaidTrack._rs_flushScheduled = true
    C_Timer.After(delay, function()
        RaidTrack._rs_flushScheduled = false
        if RaidTrack.SendRaidSyncData then
            pcall(RaidTrack.SendRaidSyncData)
        end
    end)
end

-----------------------------------------------------
-- Send: build and broadcast RTSYNC payload
-----------------------------------------------------
function RaidTrack.SendRaidSyncData(opts)
    opts = opts or {}
    _pruneTombstones()

    local inGuild = IsInGuild()
    local canRaid = IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
    if not inGuild and not (opts.allowRaid and canRaid) then
        return
    end

    -- aktywny raid (ID + preset; bez activeConfig)
    local activeID, activePreset = nil, nil
    for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
        if tostring(r.status or ""):lower() == "started" and not tonumber(r.endAt) then
            activeID = r.id
            activePreset = r.preset
            break
        end
    end

    -- ZBIERZ tombstony (od każdego, nie tylko oficera)
    local removedPresets, removedInstances = {}, {}
    for k, v in pairs(RaidTrackDB._presetTombstones or {}) do
        if v then
            table.insert(removedPresets, k)
        end
    end
    for k, v in pairs(RaidTrackDB._instanceTombstones or {}) do
        if v then
            table.insert(removedInstances, k)
        end
    end
    if #removedPresets == 0 then
        removedPresets = nil
    end
    if #removedInstances == 0 then
        removedInstances = nil
    end

    local payload = {
        raidSyncID = RaidTrack.GenerateRaidSyncID(),
        presets = RaidTrackDB.raidPresets or {},
        instances = RaidTrackDB.raidInstances or {},
        removedPresets = removedPresets,
        removedInstances = removedInstances,
        activeID = activeID,
        activePreset = activePreset
    }

    RaidTrack.lastRaidSyncID = payload.raidSyncID

    local serialized = RaidTrack.SafeSerialize(payload)
    if not serialized then
        return
    end

    -- Kanał: aktywny -> RAID, inaczej -> GUILD (jeśli w gildii)
    local hasDeletes = (removedPresets ~= nil) or (removedInstances ~= nil)
    local channel = activeID and "RAID" or (inGuild and "GUILD" or "RAID")

    RaidTrack.QueueChunkedSend(payload.raidSyncID, SYNC_PREFIX, serialized, channel)

    -- DODAJ TO: jeżeli trwa raid i są delet’y, doślij też na GUILD
    if activeID and hasDeletes and inGuild then
        RaidTrack.QueueChunkedSend(payload.raidSyncID, SYNC_PREFIX, serialized, "GUILD")
    end

end

-- Szybki publiczny helper do broadcastu (np. po end raidu)
function RaidTrack.BroadcastRaidSync()
    RaidTrack.SendRaidSyncData({
        allowRaid = true
    })
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
    RaidTrack.SendRaidSyncData({
        allowRaid = true
    })
end

-----------------------------------------------------
-- Receive: apply RTSYNC payload safely
-----------------------------------------------------
function RaidTrack.ApplyRaidSyncData(data, sender)
    if type(data) ~= "table" then
        return
    end

    -- === helpers ===
    local function upsertPresets(dst, src)
        if type(dst) ~= "table" or type(src) ~= "table" then
            return false
        end
        local changed = false
        for k, v in pairs(src) do
            if dst[k] ~= v then
                dst[k] = v
                changed = true
            end
        end
        return changed
    end

    local function indexInstancesById(list)
        local map = {}
        if type(list) ~= "table" then
            return map
        end
        for i = 1, #list do
            local it = list[i]
            local id = it and it.id
            if id ~= nil then
                map[tostring(id)] = i
            end
        end
        return map
    end

    local function upsertInstances(dstList, srcList)
        if type(dstList) ~= "table" or type(srcList) ~= "table" then
            return false
        end
        local changed = false
        local idx = indexInstancesById(dstList)
        for _, s in ipairs(srcList) do
            local sid = s and s.id
            if sid ~= nil then
                local key = tostring(sid)
                local pos = idx[key]
                if pos then
                    local localInst = dstList[pos]
                    local localEnded = (tonumber(localInst.endAt) ~= nil) or
                                           (tostring(localInst.status or ""):lower() == "ended")
                    local incomingEnded = (tonumber(s.endAt) ~= nil) or (tostring(s.status or ""):lower() == "ended")
                    -- sticky: nie cofaj ended -> started
                    if localEnded and not incomingEnded then
                        -- nic
                    else
                        if dstList[pos] ~= s then
                            dstList[pos] = s
                            changed = true
                        end
                    end
                else
                    table.insert(dstList, s)
                    idx[key] = #dstList
                    changed = true
                end

            end
        end
        return changed
    end

    local function removePresets(dst, names)
        if type(dst) ~= "table" or type(names) ~= "table" then
            return false
        end
        local changed = false
        for _, name in ipairs(names) do
            if dst[name] ~= nil then
                dst[name] = nil
                changed = true
            end
        end
        return changed
    end

    local function removeInstances(dstList, ids)
        if type(dstList) ~= "table" or type(ids) ~= "table" then
            return false
        end
        local set = {}
        for _, id in ipairs(ids) do
            set[tostring(id)] = true
        end
        local changed = false
        for i = #dstList, 1, -1 do
            local it = dstList[i]
            if it and set[tostring(it.id)] then
                table.remove(dstList, i)
                changed = true
            end
        end
        return changed
    end

    local function findInstanceLocal(id)
        if not id then
            return nil
        end
        for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
            if tostring(r.id) == tostring(id) then
                return r
            end
        end
        return nil
    end

    local function isEnded(inst)
        if not inst then
            return false
        end
        if tonumber(inst.endAt) then
            return true
        end
        return tostring(inst.status or ""):lower() == "ended"
    end

    -- === init bazy ===
    RaidTrackDB.raidPresets = RaidTrackDB.raidPresets or {}
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

    local srcPresets = (type(data.presets) == "table") and data.presets or {}
    local srcInstances = (type(data.instances) == "table") and data.instances or {}
    local removedPres = (type(data.removedPresets) == "table") and data.removedPresets or {}
    local removedInst = (type(data.removedInstances) == "table") and data.removedInstances or {}
    -- 🔒 Odrzuć wszystko, co lokalnie jest skasowane (świeży tombstone)
    for name in pairs(srcPresets) do
        if _isTombstonedPreset(name) then
            srcPresets[name] = nil
        end
    end
    for i = #srcInstances, 1, -1 do
        local it = srcInstances[i]
        if it and _isTombstonedInstance(it.id) then
            table.remove(srcInstances, i)
        end
    end

    -- === guard: zupełnie pusty snapshot bez jawnych usunięć -> ignoruj ===
    if next(srcPresets) == nil and #srcInstances == 0 and #removedPres == 0 and #removedInst == 0 then
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("[RaidSync] Ignored empty snapshot from %s"):format(tostring(sender or "?")))
        end
        return
    end

    -- === jawne kasowania ===
    if #removedPres > 0 then
        changed = removePresets(RaidTrackDB.raidPresets, removedPres) or changed
    end
    if #removedInst > 0 then
        changed = removeInstances(RaidTrackDB.raidInstances, removedInst) or changed
    end

    -- === aktywny raid tylko dla osób w raidzie i gdy instancja nie jest zakończona ===
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset = nil, nil
    end
    local instForActive = data.activeID and findInstanceLocal(data.activeID) or nil
    if instForActive and isEnded(instForActive) then
        data.activeID, data.activePreset = nil, nil
    end

    -- === merge ===
    local changed = false
    changed = upsertPresets(RaidTrackDB.raidPresets, srcPresets) or changed
    changed = upsertInstances(RaidTrackDB.raidInstances, srcInstances) or changed
    -- 🔒 Nie aktywuj raidu, który lokalnie jest oznaczony do usunięcia
    if data.activeID and _isTombstonedInstance(data.activeID) then
        data.activeID, data.activePreset = nil, nil
    end

    if data.activeID then
        RaidTrack.activeRaidID = data.activeID
        RaidTrackDB.activeRaidID = data.activeID

        local cfg = nil
        if data.activePreset and RaidTrackDB.raidPresets then
            cfg = RaidTrackDB.raidPresets[data.activePreset]
        end
        if not cfg then
            local inst = findInstanceLocal(data.activeID)
            if inst and inst.preset and RaidTrackDB.raidPresets then
                cfg = RaidTrackDB.raidPresets[inst.preset]
            end
        end
        RaidTrack.currentRaidConfig = cfg or nil

        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("[RaidSync] applied from %s: activeID=%s preset=%s cfg=%s"):format(tostring(
                sender or "?"), tostring(data.activeID), tostring(data.activePreset), RaidTrack.currentRaidConfig and
                "OK" or "nil"))
        end
    end

    -- DC guard
    if RaidTrack.ReconcileActiveRaidDCGuard then
        pcall(RaidTrack.ReconcileActiveRaidDCGuard)
    end

    -- UI
    -- UI (throttle'owane)
    if RaidTrack.RequestUIRefresh then
        RaidTrack.RequestUIRefresh("RaidSync.Apply")
    else
        -- fallback gdyby helpera nie było
        if RaidTrack.RefreshRaidDropdown then
            pcall(RaidTrack.RefreshRaidDropdown)
        end
        if RaidTrack.UpdateRaidTabStatus then
            pcall(RaidTrack.UpdateRaidTabStatus)
        end
    end

    -- UWAGA: brak rebroadcastu z Apply (eliminuje echo/ping-pong)
    return changed and true or false
end

-----------------------------------------------------
-- Chunk handler registration
-----------------------------------------------------
-- Rejestr odbiornika RTsync (obsługa NEW i LEGACY headera, bufor per msgId/sender)
RaidTrack.RegisterChunkHandler(SYNC_PREFIX, function(sender, msg)
    if type(msg) ~= "string" or msg:sub(1, 8) ~= "RTCHUNK^" then
        return
    end

    local msgId, idx, total, chunk

    -- NOWY: RTCHUNK^<msgId>^<idx>^<total>^<data>
    do
        local a = msg:find("^", 8, true)
        if a then
            local b = msg:find("^", a + 1, true)
            local c = b and msg:find("^", b + 1, true) or nil
            local d = c and msg:find("^", c + 1, true) or nil
            if a and b and c and d then
                msgId = msg:sub(a + 1, b - 1)
                idx = tonumber(msg:sub(b + 1, c - 1))
                total = tonumber(msg:sub(c + 1, d - 1))
                chunk = msg:sub(d + 1)
            end
        end
    end

    -- LEGACY: RTCHUNK^<idx>^<total>^<data>
    if not (msgId and idx and total and chunk) then
        local a = msg:find("^", 8, true)
        local b = a and msg:find("^", a + 1, true) or nil
        local c = b and msg:find("^", b + 1, true) or nil
        if a and b and c then
            msgId = nil
            idx = tonumber(msg:sub(a + 1, b - 1))
            total = tonumber(msg:sub(b + 1, c - 1))
            chunk = msg:sub(c + 1)
        end
    end
    if not (idx and total and chunk) then
        return
    end

    -- Bufor: NEW -> per msgId, LEGACY -> per sender
    RaidTrack._chunkBuffers = RaidTrack._chunkBuffers or {}
    local key = msgId and ("RT@" .. tostring(msgId)) or ("RT@" .. tostring(sender or "UNKNOWN"))
    local buf = RaidTrack._chunkBuffers[key] or {}
    buf[idx] = chunk
    RaidTrack._chunkBuffers[key] = buf

    for i = 1, total do
        if not buf[i] then
            return
        end
    end

    local full = table.concat(buf, "")
    RaidTrack._chunkBuffers[key] = nil

    local ok, data = RaidTrack.SafeDeserialize(full)
    if not ok or not data then
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from " .. tostring(sender or "?"))
        end
        return
    end

    -- Bezpiecznik aktywnego raidu
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset = nil, nil
    end

    if RaidTrack.ApplyRaidSyncData then
        RaidTrack.ApplyRaidSyncData(data, sender)
    elseif RaidTrack.MergeRaidSyncData then
        RaidTrack.MergeRaidSyncData(data, sender)
    end

    -- Throttle'owany refresh UI
    if RaidTrack.RequestUIRefresh then
        RaidTrack.RequestUIRefresh("RTSYNC-Recv")
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
