-- Core/RaidSync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local SYNC_PREFIX = "RTSYNC"
C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)

RaidTrack.lastRaidSyncID = nil

-- === helpers / safety ===
local function TableNonEmpty(t)
    return type(t) == "table" and next(t) ~= nil
end

local function short(name)
    return (name and Ambiguate and Ambiguate(name, "none")) or name
end

-- rankIndex konkretnego gracza (0 = GM, 1 = officer, ...)
function RaidTrack.GetGuildRankIndex(name)
    name = short(name)
    if not name or not IsInGuild() then return nil end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local fullname, _, rankIndex = GetGuildRosterInfo(i)
        if fullname and short(fullname) == name then
            return tonumber(rankIndex)
        end
    end
    return nil
end

-- czy nadawca spełnia minSyncRank?
function RaidTrack.IsSenderAllowedSync(sender)
    local minRank = tonumber(RaidTrackDB and RaidTrackDB.settings and RaidTrackDB.settings.minSyncRank) or 1
    local ri = RaidTrack.GetGuildRankIndex(sender)
    return ri ~= nil and ri <= minRank
end

-- unikalne ID paczki (po czasie)
function RaidTrack.GenerateRaidSyncID()
    return tostring(time()) .. tostring(math.random(10000, 99999))
end

-- =========================
-- WYSYŁKA DANYCH RAIDOWYCH
-- =========================
function RaidTrack.SendRaidSyncData(opts)
    opts = opts or {}

    local canGuild = RaidTrack.IsOfficer and RaidTrack.IsOfficer() or false
    local canRaid  = IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))

    -- GUILD: tylko oficer; RAID: RL/Assist jeśli allowRaid
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
        presets      = RaidTrackDB.raidPresets   or {},
        instances    = RaidTrackDB.raidInstances or {},
        activeID     = activeID,
        activePreset = activePreset,
        activeConfig = activeConfig,   -- migawka aktywnego configu
        syncTs       = time(),         -- świeżość paczki
    }

    RaidTrack.lastRaidSyncID = payload.raidSyncID

    local serialized = RaidTrack.SafeSerialize(payload)

    -- Jeżeli aktywny raid -> tylko RAID (żeby nie “aktywować” u osób poza raidem)
    local channel = activeID and "RAID" or ((canGuild and "GUILD") or "RAID")

    RaidTrack.QueueChunkedSend(nil, SYNC_PREFIX, serialized, channel)
end

-- broadcast do całego raidu (RL/Assist)
function RaidTrack.BroadcastRaidSync()
    RaidTrack.SendRaidSyncData({ allowRaid = true })
end

-- =========================
-- ODBIÓR I MERGE DANYCH
-- =========================
function RaidTrack.ApplyRaidSyncData(data, sender)
    if type(data) ~= "table" then return end
    sender = short(sender)

    -- 0) autoryzacja nadawcy wg minSyncRank
    if RaidTrack.IsSenderAllowedSync and sender and not RaidTrack.IsSenderAllowedSync(sender) then
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("[RaidSync] rejected from " .. tostring(sender) .. " (insufficient rank)")
        end
        return
    end

    -- 0.1) anty-rollback: ignoruj starsze paczki
    local incomingTs = tonumber(data.syncTs)
                    or tonumber(tostring(data.raidSyncID or ""):match("^(%d+)"))
                    or 0
    RaidTrack._lastAppliedRaidSyncTs = RaidTrack._lastAppliedRaidSyncTs or 0
    if incomingTs < RaidTrack._lastAppliedRaidSyncTs then
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(("[RaidSync] stale packet ignored (ts=%s < last=%s)")
                :format(incomingTs, RaidTrack._lastAppliedRaidSyncTs))
        end
        return
    end

    -- 1) bezpieczny merge bazy (NIE nadpisuj pustką / nil)
    if TableNonEmpty(data.presets)   then RaidTrackDB.raidPresets   = data.presets   end
    if TableNonEmpty(data.instances) then RaidTrackDB.raidInstances = data.instances end

    -- 2) nie aktywuj raidu spoza grupy
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end

    -- 3) ustaw aktywny raid + config (jeśli przyszły)
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

    -- 4) UI refresh
    if RaidTrack.RefreshRaidDropdown then RaidTrack.RefreshRaidDropdown() end
    if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end

    -- 5) zapamiętaj świeżość przyjętej paczki
    RaidTrack._lastAppliedRaidSyncTs = incomingTs
end

-- Handler składania chunków (eksportujemy nazwę, żeby Sync.lua mógł jej użyć)
function RaidTrack.HandleChunkedRaidPiece(sender, msg)
    if not msg:find("^RTCHUNK") then return end

    local _, idx, total, chunk = string.match(msg, "^(RTCHUNK)%^(%d+)%^(%d+)%^(.+)$")
    if not idx or not total or not chunk then return end
    idx, total = tonumber(idx), tonumber(total)
    local who  = short(sender)

    RaidTrack._chunkBuffers = RaidTrack._chunkBuffers or {}
    local key = (who or "unknown") .. "_RTSYNC"
    local buf = RaidTrack._chunkBuffers[key] or {}
    RaidTrack._chunkBuffers[key] = buf

    buf[idx] = chunk

    -- sprawdź kompletność
    for i = 1, total do
        if not buf[i] then return end
    end

    -- mamy komplet
    local full = table.concat(buf, "")
    RaidTrack._chunkBuffers[key] = nil

    local ok, data = RaidTrack.SafeDeserialize(full)
    if ok and data then
        RaidTrack.ApplyRaidSyncData(data, who)
    else
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from " .. tostring(who or "?"))
        end
    end
end

-- Rejestracja handlera: tylko jeśli nikt tego jeszcze nie zrobił
if RaidTrack.RegisterChunkHandler then
    RaidTrack.chunkHandlers = RaidTrack.chunkHandlers or {}
    if not RaidTrack.chunkHandlers[SYNC_PREFIX] then
        RaidTrack.RegisterChunkHandler(SYNC_PREFIX, function(sender, message)
            RaidTrack.HandleChunkedRaidPiece(sender, message)
        end)
    end
end

-- Back-compat dla ewentualnych wywołań
function RaidTrack.MergeRaidSyncData(data, sender)
    RaidTrack.ApplyRaidSyncData(data, sender)
end
