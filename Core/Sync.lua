-- Core/Sync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrack.chunkHandlers = RaidTrack.chunkHandlers or {}

-- ========= STAŁE =========
local CHUNK_SIZE = 220
local SYNC_PREFIX = "RaidTrackSync" -- EPGP/loot FULL/DELTA (WHISPER)
local AU_PREFIX = "auction" -- aukcje (RAID broadcast)
local RTS_PREFIX = "RTSYNC" -- raid-presets (obsługiwane w RaidSync.lua)

C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(AU_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(RTS_PREFIX)

-- ========= DB GUARDS =========
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.settings = RaidTrackDB.settings or {}
RaidTrackDB.syncStates = RaidTrackDB.syncStates or {}
RaidTrackDB.lootSyncStates = RaidTrackDB.lootSyncStates or {}
RaidTrackDB.epgpLog = RaidTrackDB.epgpLog or {
    changes = {},
    lastId = 0
}
RaidTrackDB.epgp = RaidTrackDB.epgp or {}
RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}

RaidTrack.pendingSends = RaidTrack.pendingSends or {}
RaidTrack.chunkBuffer = RaidTrack.chunkBuffer or {}

-- ========= AceSerializer wrappers (bez kompresji) =========
local AceSer = LibStub and LibStub("AceSerializer-3.0", true)
if not AceSer then
    error("RaidTrack: AceSerializer-3.0 is required")
end

function RaidTrack.SafeSerialize(tbl)
    local ok, s = pcall(AceSer.Serialize, AceSer, tbl)
    if ok and type(s) == "string" then
        return s
    end
    return nil
end

function RaidTrack.SafeDeserialize(s)
    local ok, a, b, c, d, e, f = pcall(AceSer.Deserialize, AceSer, s)
    if not ok or not a then
        return false
    end
    -- AceSerializer zwraca: true, data
    return true, b
end

-- NO-OP kompresja (przywrócenie starego transportu)
RaidTrack.MaybeCompress = function(s)
    return s, false
end
RaidTrack.MaybeDecompress = function(s)
    return s, false
end

-- ========= ChatThrottle wrapper =========
local CTL = _G.ChatThrottleLib
local function SEND(prefix, msg, channel, target, prio)
    prio = prio or "NORMAL"
    if CTL and CTL.SendAddonMessage then
        CTL:SendAddonMessage(prio, prefix, msg, channel, target)
    else
        C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
    end
end

-- ========= Rejestr handlerów chunków =========
function RaidTrack.RegisterChunkHandler(prefix, handler)
    RaidTrack.chunkHandlers[prefix] = handler
end

local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    if not prefix or not message then
        return
    end
    local h = RaidTrack.chunkHandlers[prefix]
    if h then
        h(sender, message, channel)
    end
end)

-- Aukcje: rejestruj odbiornik chunków
RaidTrack.RegisterChunkHandler(AU_PREFIX, function(sender, message, channel)
    RaidTrack.HandleChunkedAuctionPiece(sender, message)
end)

-- ========= SYNC (harmonogram małych flushy) =========
function RaidTrack.ScheduleSync()
    if RaidTrack.syncTimer then
        RaidTrack.syncTimer:Cancel()
    end
    RaidTrack.syncTimer = C_Timer.NewTimer(0.10, function()
        RaidTrack.syncTimer = nil
        RaidTrack.SendSyncDeltaToEligible()
    end)
end

-- ========= SYNC DELTA do uprawnionych =========
function RaidTrack.SendSyncDeltaToEligible()
    if not IsInGuild() then
        return
    end

    local me = Ambiguate(UnitName("player"), "none")
    local minRank = tonumber(RaidTrackDB.settings.minSyncRank) or 1 -- 0=GM 1=Officer
    local myRank
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and Ambiguate(name, "none") == me then
            myRank = rankIndex;
            break
        end
    end
    if not myRank or myRank > minRank then
        return
    end

    local MAX_PER_RUN = 3
    local sent = 0

    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name and name ~= me and rankIndex <= minRank then
            local knownEP = RaidTrackDB.syncStates[name] or 0
            local knownLoot = RaidTrackDB.lootSyncStates[name] or 0
            -- nigdy nie pchamy FULL w ciemno
            if knownEP > 0 or knownLoot > 0 then
                local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP) or {}
                local lootDelta = {}
                for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                    if e.id and e.id > knownLoot then
                        table.insert(lootDelta, e)
                    end
                end
                if #epgpDelta > 0 or #lootDelta > 0 then
                    RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
                    sent = sent + 1;
                    if sent >= MAX_PER_RUN then
                        break
                    end
                end
            end
        end
    end
end

-- ========= REQ od nowego klienta =========
function RaidTrack.RequestSyncFromGuild()
    if not IsInGuild() then
        return
    end

    RaidTrack._lastReqSyncAt = RaidTrack._lastReqSyncAt or 0
    local now = (GetTime and GetTime()) or time()
    if (now - RaidTrack._lastReqSyncAt) < 15 then
        return
    end
    RaidTrack._lastReqSyncAt = now

    local me = Ambiguate(UnitName("player"), "none")
    local epID, lootID = (RaidTrackDB.epgpLog.lastId or 0), 0
    for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
        if e.id and e.id > lootID then
            lootID = e.id
        end
    end

    -- wybierz najlepszego oficera
    local minRank = tonumber(RaidTrackDB.settings.minSyncRank) or 1
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end

    local best, bestRank
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name ~= me and (not best or rankIndex < bestRank) and rankIndex <= minRank then
            best, bestRank = name, rankIndex
        end
    end
    if not best then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            name = name and Ambiguate(name, "none")
            if online and name ~= me then
                best = name;
                break
            end
        end
    end
    if not best then
        return
    end

    local msg = ("REQ_SYNC|%d|%d"):format(epID, lootID)
    SEND(SYNC_PREFIX, msg, "WHISPER", best, "NORMAL")
end

-- ========= Wysyłka FULL/DELTA (WHISPER) =========
function RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
    if not RaidTrack.IsPlayerInMyGuild(name) then
        return
    end

    RaidTrackDB.syncStates = RaidTrackDB.syncStates or {}
    RaidTrackDB.lootSyncStates = RaidTrackDB.lootSyncStates or {}

    local sendFull = (knownEP == 0 and knownLoot == 0)
    local payload, maxEP, maxLoot

    if sendFull then
        maxEP, maxLoot = 0, 0
        for _, e in ipairs(RaidTrackDB.epgpLog.changes or {}) do
            if e.id and e.id > maxEP then
                maxEP = e.id
            end
        end
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
            if e.id and e.id > maxLoot then
                maxLoot = e.id
            end
        end

        payload = {
            full = {
                epgp = RaidTrackDB.epgp,
                loot = RaidTrackDB.lootHistory,
                epgpLog = RaidTrackDB.epgpLog.changes,
                settings = RaidTrackDB.settings or {},
                epgpWipeID = RaidTrackDB.epgpWipeID
            }
        }
        RaidTrack.pendingSends[name] = {
            meta = {
                lastEP = maxEP,
                lastLoot = maxLoot
            },
            priority = "NORMAL",
            isFull = true
        }
        RaidTrackDB.syncStates[UnitName("player")] = maxEP
        RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
    else
        local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP) or {}
        local lootDelta = {}
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
            if e.id and e.id > knownLoot then
                table.insert(lootDelta, e)
            end
        end
        payload = {
            epgpDelta = epgpDelta,
            lootDelta = lootDelta,
            epgpWipeID = RaidTrackDB.epgpWipeID or 0
        }

        local mxEP, mxLoot = knownEP, knownLoot
        for _, e in ipairs(epgpDelta) do
            if e.id and e.id > mxEP then
                mxEP = e.id
            end
        end
        for _, e in ipairs(lootDelta) do
            if e.id and e.id > mxLoot then
                mxLoot = e.id
            end
        end

        RaidTrackDB.syncStates[name] = mxEP
        RaidTrackDB.lootSyncStates[name] = mxLoot
        RaidTrackDB.syncStates[UnitName("player")] = mxEP
        RaidTrackDB.lootSyncStates[UnitName("player")] = mxLoot

        RaidTrack.pendingSends[name] = RaidTrack.pendingSends[name] or {}
        RaidTrack.pendingSends[name].priority = "ALERT"
        RaidTrack.pendingSends[name].isFull = false
    end

    local str = RaidTrack.SafeSerialize(payload);
    if not str then
        return
    end
    local total = math.ceil(#str / CHUNK_SIZE)
    local chunks = {}
    for i = 1, total do
        chunks[i] = str:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
    end
    RaidTrack.pendingSends[name] = RaidTrack.pendingSends[name] or {}
    RaidTrack.pendingSends[name].chunks = chunks

    -- handshake
    SEND(SYNC_PREFIX, "PING", "WHISPER", name, "NORMAL")

    if sendFull then
        C_Timer.NewTimer(15, function()
            local p = RaidTrack.pendingSends[name]
            if p and not p.gotPong then
                RaidTrack.pendingSends[name] = nil
            end
        end)
    end

    -- drobny CFG osobno (mały payload)
    if RaidTrack.IsOfficer and RaidTrack.IsOfficer() then
        local cfg = RaidTrack.SafeSerialize({
            settings = {
                minSyncRank = RaidTrackDB.settings.minSyncRank,
                officerOnly = RaidTrackDB.settings.officerOnly,
                autoSync = RaidTrackDB.settings.autoSync,
                minUITabRankIndex = RaidTrackDB.settings.minUITabRankIndex
            }
        })
        if cfg then
            SEND(SYNC_PREFIX, "CFG|" .. cfg, "WHISPER", name, "NORMAL")
        end
    end

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(("[EGPPSync:prep] to=%s bytes=%d chunks=%d prio=%s"):format(tostring(name), #str,
            total, (RaidTrack.pendingSends[name] and RaidTrack.pendingSends[name].priority) or "?"))
    end
end

function RaidTrack.SendChunkBatch(name)
    local p = RaidTrack.pendingSends[name]
    if not p or not p.chunks then
        return
    end

    local prio = p.priority or ((#p.chunks > 5) and "BULK" or "NORMAL")
    if p.isFull and #p.chunks > 20 then
        prio = "BULK"
    end

    local any = false
    for idx, c in ipairs(p.chunks) do
        if c then
            any = true;
            SEND(SYNC_PREFIX, ("%d|%d|%s"):format(idx, #p.chunks, c), "WHISPER", name, prio)
        end
    end
    if not any then
        RaidTrack.pendingSends[name] = nil
        if p.meta and p.meta.lastEP and p.meta.lastLoot then
            RaidTrackDB.syncStates[UnitName("player")] = p.meta.lastEP
            RaidTrackDB.lootSyncStates[UnitName("player")] = p.meta.lastLoot
        end
        RaidTrack.lastSyncTime = time()
    end

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(("[EGPPSync:send] to=%s chunks=%d prio=%s"):format(tostring(name), #(p.chunks or {}),
            prio))
    end
end

-- ========= CFG broadcast (GUILD) =========
function RaidTrack.BroadcastSettings(opts)
    opts = opts or {}
    if not (RaidTrack.IsOfficer and RaidTrack.IsOfficer()) then
        return
    end
    local payload = {
        settings = {
            minSyncRank = RaidTrackDB.settings.minSyncRank,
            officerOnly = RaidTrackDB.settings.officerOnly,
            autoSync = RaidTrackDB.settings.autoSync,
            minUITabRankIndex = RaidTrackDB.settings.minUITabRankIndex,
            epgpWipeID = RaidTrackDB.epgpWipeID,
            wipe = opts.wipe == true
        }
    }
    local s = RaidTrack.SafeSerialize(payload);
    if not s then
        return
    end
    SEND(SYNC_PREFIX, "CFG|" .. s, "GUILD", nil, "ALERT")
end

-- ========= CFG apply / FULL apply =========
local function _hasNonEmptyEPGP(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for _ in pairs(tbl) do
        return true
    end
    return false
end

local function applyFull(full, from)
    if type(full) ~= "table" then
        return false
    end
    local incWipe = tostring(full.epgpWipeID or RaidTrackDB.epgpWipeID or "")
    local incLastEP, incMaxLoot = 0, 0
    for _, e in ipairs(full.epgpLog or {}) do
        if e.id and e.id > incLastEP then
            incLastEP = e.id
        end
    end
    for _, e in ipairs(full.loot or {}) do
        if e.id and e.id > incMaxLoot then
            incMaxLoot = e.id
        end
    end
    local sig = incWipe .. "|" .. incLastEP .. "|" .. incMaxLoot
    if not RaidTrack._pendingWipe and RaidTrack._lastAppliedFullSig == sig then
        return false
    end

    if RaidTrack._pendingWipe then
        if not _hasNonEmptyEPGP(full.epgp) then
            if from then
                SEND(SYNC_PREFIX, "REQ_SYNC|0|0", "WHISPER", from, "NORMAL")
            end
            return false
        end
        RaidTrackDB.epgp = type(full.epgp) == "table" and full.epgp or {}
        RaidTrackDB.lootHistory = type(full.loot) == "table" and full.loot or {}
        RaidTrackDB.epgpLog = type(full.epgpLog) == "table" and {
            changes = full.epgpLog,
            lastId = 0
        } or {
            changes = {},
            lastId = 0
        }
        RaidTrackDB.syncStates, RaidTrackDB.lootSyncStates = {}, {}
        if type(full.epgpWipeID) == "string" and full.epgpWipeID ~= "" then
            RaidTrackDB.epgpWipeID = full.epgpWipeID
        end
        RaidTrack._pendingWipe, RaidTrack._lastAppliedFullSig = false, sig
        return true
    else
        if type(full.epgp) == "table" and _hasNonEmptyEPGP(full.epgp) then
            RaidTrackDB.epgp = full.epgp
        end
        if type(full.loot) == "table" then
            RaidTrackDB.lootHistory = full.loot
        end
        if type(full.epgpLog) == "table" then
            RaidTrackDB.epgpLog = {
                changes = full.epgpLog,
                lastId = 0
            }
        end
        if type(full.settings) == "table" then
            for k, v in pairs(full.settings) do
                RaidTrackDB.settings[k] = v
            end
        end
        if type(full.epgpWipeID) == "string" and full.epgpWipeID ~= "" then
            RaidTrackDB.epgpWipeID = full.epgpWipeID
        end
        RaidTrack._lastAppliedFullSig = sig
        return true
    end
end

local function applyCfg(data, sender)
    if type(data) ~= "table" or type(data.settings) ~= "table" then
        return
    end
    RaidTrack._cfgSeen = true
    RaidTrack._lastCfgFrom = Ambiguate(sender or "", "none")
    local s = data.settings
    if type(s.minSyncRank) == "number" then
        RaidTrackDB.settings.minSyncRank = s.minSyncRank
    end
    if type(s.officerOnly) ~= "nil" then
        RaidTrackDB.settings.officerOnly = s.officerOnly
    end
    if type(s.autoSync) ~= "nil" then
        RaidTrackDB.settings.autoSync = s.autoSync
    end
    if type(s.minUITabRankIndex) == "number" then
        RaidTrackDB.settings.minUITabRankIndex = s.minUITabRankIndex
    end
    if type(s.epgpWipeID) == "string" and s.epgpWipeID ~= "" then
        RaidTrackDB.epgpWipeID = s.epgpWipeID
    end
    if s.wipe == true then
        RaidTrack._pendingWipe = true
    end
    if RaidTrack.ApplyUITabVisibility then
        pcall(RaidTrack.ApplyUITabVisibility)
    end
    if RaidTrack.RefreshMinimapMenu then
        pcall(RaidTrack.RefreshMinimapMenu)
    end
end

-- ========= GŁÓWNY ODBIORNIK SYNC_PREFIX =========
local mf = CreateFrame("Frame")
mf:RegisterEvent("CHAT_MSG_ADDON")
mf:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    if prefix == AU_PREFIX and sender ~= UnitName("player") then
        if msg:sub(1, 8) == "RTCHUNK^" then
            RaidTrack.HandleChunkedAuctionPiece(sender, msg)
        end
        return
    end
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then
        return
    end
    local who = Ambiguate(sender or "", "none")

    -- Legacy aukcji (stary klient)
    if msg:sub(1, 13) == "AUCTION_ITEM|" then
        local ok, data = RaidTrack.SafeDeserialize(msg:sub(14))
        if ok and data and data.auctionID and data.item then
            RaidTrack.partialAuction = RaidTrack.partialAuction or {}
            RaidTrack.partialAuction[data.auctionID] = RaidTrack.partialAuction[data.auctionID] or {
                items = {},
                leader = "",
                started = 0,
                duration = 0
            }
            table.insert(RaidTrack.partialAuction[data.auctionID].items, {
                link = data.item.link,
                gp = data.item.gp,
                responses = {}
            })
        end
        return
    elseif msg:sub(1, 14) == "AUCTION_START|" then
        local ok, data = RaidTrack.SafeDeserialize(msg:sub(15))
        if ok and data and data.auctionID then
            C_Timer.After(0.3, function()
                local items = RaidTrack.pendingAuctionItems and RaidTrack.pendingAuctionItems[data.auctionID] or {}
                data.items = items
                RaidTrack.ReceiveAuctionHeader(data)
                RaidTrack.pendingAuctionItems[data.auctionID] = nil
            end)
        end
        return
    end

    -- handshake
    if msg == "PING" then
        SEND(SYNC_PREFIX, "PONG", "WHISPER", who, "NORMAL");
        return
    end
    if msg == "PONG" and RaidTrack.pendingSends[who] then
        RaidTrack.pendingSends[who].gotPong = true;
        RaidTrack.SendChunkBatch(who);
        return
    end
    if msg == "PONG" then
        RaidTrack.lastSyncTime = time();
        return
    end

    if msg:sub(1, 9) == "REQ_SYNC|" then
        local _, epStr, lootStr = strsplit("|", msg)
        RaidTrack.SendSyncDataTo(who, tonumber(epStr) or 0, tonumber(lootStr) or 0)
        return
    end
    if msg:sub(1, 4) == "ACK|" then
        local idx = tonumber(msg:sub(5))
        local p = RaidTrack.pendingSends[who]
        if p and p.chunks[idx] then
            p.chunks[idx] = nil
        end
        return
    end
    if msg:sub(1, 4) == "CFG|" then
        local ok, data = RaidTrack.SafeDeserialize(msg:sub(5))
        if ok and data then
            applyCfg(data, who)
        end
        return
    end

    -- chunk: i|total|data
    local i, t, d = msg:match("^(%d+)|(%d+)|(.+)$");
    i, t = tonumber(i), tonumber(t)
    if not (i and t and d) then
        return
    end
    local buf = RaidTrack.chunkBuffer[who] or {
        chunks = {},
        total = t,
        received = 0
    }
    RaidTrack.chunkBuffer[who] = buf
    if not buf.chunks[i] then
        buf.chunks[i] = d;
        buf.received = buf.received + 1
    end
    if buf.received ~= buf.total then
        return
    end

    local full = table.concat(buf.chunks);
    RaidTrack.chunkBuffer[who] = nil
    local ok, data = RaidTrack.SafeDeserialize(full);
    if not ok or not data then
        return
    end

    if data.full then
        local applied = applyFull(data.full, who)
        if applied then
            local lastEP = 0;
            for _, e in ipairs(data.full.epgpLog or {}) do
                if e.id and e.id > lastEP then
                    lastEP = e.id
                end
            end
            local maxLoot = 0;
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > maxLoot then
                    maxLoot = e.id
                end
            end
            RaidTrackDB.syncStates[who] = lastEP
            RaidTrackDB.syncStates[UnitName("player")] = lastEP
            RaidTrackDB.lootSyncStates[who] = maxLoot
            RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
            RaidTrack.lastSyncTime = time()
            if RaidTrack.UpdateEPGPList then
                RaidTrack.UpdateEPGPList()
            end
            if RaidTrack.RefreshLootTab then
                RaidTrack.RefreshLootTab()
            end
        end
        return
    end

    if RaidTrack._pendingWipe then
        return
    end
    -- DELTA
    RaidTrack.MergeEPGPChanges(data.epgpDelta or {})

    -- EP last-id
    local newLastEP = 0
    for _, e in ipairs(data.epgpDelta or {}) do
        if e.id and e.id > newLastEP then
            newLastEP = e.id
        end
    end
    if newLastEP > 0 then
        RaidTrackDB.syncStates[who] = newLastEP
        RaidTrackDB.syncStates[UnitName("player")] = newLastEP
    end

    -- Loot last-id
    RaidTrackDB.lootSyncStates = RaidTrackDB.lootSyncStates or {}
    RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}

    local seen = {}
    local mx = RaidTrackDB.lootSyncStates[who] or 0

    for _, e in ipairs(RaidTrackDB.lootHistory) do
        if e.id then
            seen[e.id] = true
        end
    end

    for _, e in ipairs(data.lootDelta or {}) do
        if e.id and not seen[e.id] then
            table.insert(RaidTrackDB.lootHistory, e)
            if e.id > mx then
                mx = e.id
            end
        end
    end

    RaidTrackDB.lootSyncStates[who] = mx

    if RaidTrack.RefreshLootTab then
        RaidTrack.RefreshLootTab()
    end
    RaidTrack.lastSyncTime = time()
end)

-- ========= Login init =========
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" and RaidTrackDB.settings.autoSync ~= false then
        C_Timer.After(3, function()
            RaidTrack.RequestSyncFromGuild()
        end)
    end
    if RaidTrack.IsOfficer and RaidTrack.IsOfficer() then
        C_Timer.After(8, function()
            RaidTrack.BroadcastSettings()
        end)
    end
    if RaidTrack.BroadcastRaidSync then
        RaidTrack.BroadcastRaidSync()
    end
end)

-- ========= RTCHUNK sender (używane przez RTsync i aukcje) =========

function RaidTrack.QueueChunkedSend(msgId, prefix, payload, channel, target, priority)
    if type(prefix) ~= "string" or type(payload) ~= "string" or #payload == 0 then
        return
    end
    channel = channel or (IsInRaid() and "RAID" or "GUILD")
    priority = priority or "NORMAL"

    local MAX = 200
    local total = math.ceil(#payload / MAX);
    if total < 1 then
        total = 1
    end
    local useNew = (type(msgId) == "string" and msgId ~= "")
    local function build(i)
        local s = (i - 1) * MAX + 1
        local part = payload:sub(s, s + MAX - 1)
        if useNew then
            return ("RTCHUNK^%s^%d^%d^%s"):format(msgId, i, total, part)
        else
            return ("RTCHUNK^%d^%d^%s"):format(i, total, part)
        end
    end
    local prio = priority;
    if prio == "NORMAL" and total > 5 then
        prio = "BULK"
    end
    for i = 1, total do
        SEND(prefix, build(i), channel, target, prio)
    end
    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(("[QueueChunkedSend] pref=%s ch=%s chunks=%d prio=%s"):format(prefix, channel, total,
            prio))
    end
end

-- ========= Aukcje =========
local function AU_Channel()
    return IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or (IsInGuild() and "GUILD" or nil))
end

function RaidTrack.QueueAuctionBroadcastSend(prefix, data, channel)
    channel = "RAID" -- wymuszamy RAID
    if not channel then
        RaidTrack.AddDebugMessage("[Auction] No valid channel");
        return
    end
    local maxSize = 200;
    local chunks = {}
    for i = 1, #data, maxSize do
        table.insert(chunks, data:sub(i, i + maxSize - 1))
    end
    local prio = (#chunks > 5) and "BULK" or "NORMAL"
    for i, chunk in ipairs(chunks) do
        local marker = ("RTCHUNK^%d^%d^%s"):format(i, #chunks, chunk)
        SEND(prefix, marker, channel, nil, prio)
    end
    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(("[Auction:send] pref=%s ch=%s chunks=%d"):format(prefix, channel, #chunks))
    end
end

-- ZAMIANA: tylko RAID, bez party/guild
local function RT_AuctionChannel()
    if IsInRaid() then return "RAID" end
    return nil
end


-- Wyślij po JEDNYM itemie (new) + mirror legacy

function RaidTrack.QueueAuctionChunkedSend(target, auctionID, messageType, input)
    if type(input) ~= "table" then error("QueueAuctionChunkedSend: input must be a table") end

    if not auctionID or auctionID == "" then
        auctionID = RaidTrack.currentAuctionID or (tostring(time()) .. tostring(math.random(10000,99999)))
        RaidTrack.currentAuctionID = auctionID
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("[Auction] Generated auctionID="..tostring(auctionID)) end
    end

    local channel = RT_AuctionChannel()
    if not channel then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("[Auction] Not in raid; aborting broadcast") end
        return
    end

    -- helper do wysyłki jednego pakietu "auction"
    local function sendAuctionPacket(subtype, payload)
        local pkt = { auctionID = auctionID, type = "auction", subtype = subtype, payload = payload }
        local s = RaidTrack.SafeSerialize(pkt)
        RaidTrack.QueueAuctionBroadcastSend("auction", s, channel)
    end

    if messageType == "item" then
        -- weź tablicę itemów lub pojedynczy wpis i wyślij każdy osobno
        local list = (input.itemID and {input}) or input
        for _, it in ipairs(list) do
            sendAuctionPacket("item", { itemID = it.itemID, gp = it.gp, link = it.link })
        end
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(("[Auction:send] items=%d ch=%s"):format(#list, channel)) end

    elseif messageType == "header" then
        local now = time()
        local dur  = tonumber(input.duration) or 0
        local ends = tonumber(input.endsAt) or (now + dur)
        sendAuctionPacket("header", {
            auctionID = auctionID,
            leader    = Ambiguate(UnitName("player"), "none"),
            started   = now,
            duration  = dur,
            endsAt    = ends,
        })
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(("[Auction:send] header ch=%s"):format(channel)) end

    elseif messageType == "response" then
        sendAuctionPacket("response", input)
    end

    -- LEGACY mirror (na tym samym kanale RAID – dla starych klientów)
    if messageType == "item" then
        for _, it in ipairs((input.itemID and {input}) or input) do
            local legacyItem = { auctionID = auctionID, item = { itemID = it.itemID, link = it.link, gp = it.gp } }
            local s = RaidTrack.SafeSerialize(legacyItem)
            C_ChatInfo.SendAddonMessage("RaidTrackSync", "AUCTION_ITEM|" .. s, channel)
        end
    elseif messageType == "header" then
        local now = time()
        local dur  = tonumber(input.duration) or 0
        local ends = tonumber(input.endsAt) or (now + dur)
        local header = { auctionID = auctionID, leader = Ambiguate(UnitName("player"), "none"), started = now, duration = dur, endsAt = ends }
        local s = RaidTrack.SafeSerialize(header)
        C_ChatInfo.SendAddonMessage("RaidTrackSync", "AUCTION_START|" .. s, channel)
    end
end


-- mały helper do porównań nazw
local function _isMe(name)
    return Ambiguate(name or "", "none") == Ambiguate(UnitName("player"), "none")
end

function RaidTrack.ReceiveAuctionChunked(sender, rawData)
    if type(rawData) ~= "string" then return end
    if rawData:sub(1,8) == "RTCHUNK^" then return end

    local ok, data = RaidTrack.SafeDeserialize(rawData)
    if not ok or not data or data.type ~= "auction" then return end

    RaidTrack.pendingAuctionItems = RaidTrack.pendingAuctionItems or {}
    RaidTrack.pendingAuctionItems[data.auctionID] = RaidTrack.pendingAuctionItems[data.auctionID] or {}

    if data.subtype == "item" then
        local list = data.payload
        -- pozwól na array albo pojedynczy obiekt
        if list and not list.itemID and type(list) == "table" then
            for _, it in ipairs(list) do
                if it and it.itemID then
                    table.insert(RaidTrack.pendingAuctionItems[data.auctionID], {
                        itemID = it.itemID,
                        uniqueItemID = tostring(it.itemID) .. "_" .. data.auctionID,
                        gp = it.gp, link = it.link, responses = {}
                    })
                end
            end
            return
        end

        if list and list.itemID then
            local items = RaidTrack.pendingAuctionItems[data.auctionID]
            local exists = false
            for _, it in ipairs(items) do
                if tonumber(it.itemID) == tonumber(list.itemID) then exists = true; break end
            end
            if not exists then
                table.insert(items, {
                    itemID = list.itemID,
                    uniqueItemID = tostring(list.itemID) .. "_" .. data.auctionID,
                    gp = list.gp, link = list.link, responses = {}
                })
            end
        else
            if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Invalid auction item data!") end
        end

    elseif data.subtype == "header" then
        local h = data.payload
        if not h or not h.leader then
            if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Invalid auction header data!") end
            return
        end

        local items = RaidTrack.pendingAuctionItems[data.auctionID] or {}

        if _isMe(h.leader) and RaidTrack.OpenAuctionLeaderUI then
            RaidTrack:OpenAuctionLeaderUI()
        end

        if IsInRaid() and RaidTrack.OpenAuctionParticipantUI then
            RaidTrack.OpenAuctionParticipantUI({
                auctionID = data.auctionID,
                leader    = h.leader,
                started   = h.started,
                endsAt    = h.endsAt,
                duration  = h.duration,
                items     = items,
            })
        end

        RaidTrack.activeAuctions = RaidTrack.activeAuctions or {}
        RaidTrack.activeAuctions[data.auctionID] = {
            items = items, leader = h.leader, started = h.started, endsAt = h.endsAt, duration = h.duration
        }
        RaidTrack.pendingAuctionItems[data.auctionID] = nil

    elseif data.subtype == "response" then
        if data.payload then
            local auc = RaidTrack.activeAuctions and RaidTrack.activeAuctions[data.auctionID]
            if auc and _isMe(auc.leader) then
                RaidTrack.HandleAuctionResponse(data.auctionID, data.payload)
            end
        end
    end
end


-- Odbiór legacy chunków aukcji
function RaidTrack.HandleChunkedAuctionPiece(sender, msg)
    local idx, total, chunk = msg:match("^RTCHUNK%^(%d+)%^(%d+)%^(.+)$")
    if not idx or not total or not chunk then
        return
    end
    idx, total = tonumber(idx), tonumber(total)

    RaidTrack._auctionChunks = RaidTrack._auctionChunks or {}
    local list = RaidTrack._auctionChunks[sender] or {};
    RaidTrack._auctionChunks[sender] = list
    list[idx] = chunk
    for i = 1, total do
        if not list[i] then
            return
        end
    end

    local full = table.concat(list, "");
    RaidTrack._auctionChunks[sender] = nil
    RaidTrack.ReceiveAuctionChunked(sender, full)
end
