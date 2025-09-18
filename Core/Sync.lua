-- Core/Sync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrack.chunkHandlers = RaidTrack.chunkHandlers or {}

-- ===== Version gating (ADDON/PROTO) =====
local function GetAddonVersion()
    local function meta(key)
        if C_AddOns and C_AddOns.GetAddOnMetadata then
            local v = C_AddOns.GetAddOnMetadata(addonName, key)
            if v and v ~= "" then return v end
        end
        if GetAddOnMetadata then
            local v = GetAddOnMetadata(addonName, key)
            if v and v ~= "" then return v end
        end
    end

    local v = meta("Version") or meta("X-RT-Version") or meta("X-Curse-Project-Version") or ""
    -- odfiltruj placeholdery typu @project-version@ / wowi:version
    if v:find("@") or v:find("wowi:version") or v:find("project%-version") then
        v = ""
    end
    -- wyciągnij pierwszy semver z napisu (działa dla v3.3.2, 3.3.2-beta, 3.3, 3)
    local sem = (v:match("%d[%d%.]*") or ""):gsub("%.+$", "")
    if sem == "" then sem = "0.0.0" end
    return sem
end

RaidTrack.VERSION  = GetAddonVersion()
RaidTrack.PROTOCOL = 1
-- Jeśli chcesz wymuszać update do swojej wersji:
-- RaidTrack.MIN_PEER_VERSION = RaidTrack.VERSION

-- porównanie semver (odporne na sufiksy typu "3.3.2-beta", "v3.3.2+meta")
local function semver_cmp(a, b)
    local function parts(s)
        s = tostring(s or "")
        s = s:match("%d[%d%.]*") or "0"      -- weź pierwszy fragment typu 1.2.3
        local x,y,z = s:match("^(%d+)%.?(%d*)%.?(%d*)$")
        return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    end
    local ax,ay,az = parts(a)
    local bx,by,bz = parts(b)
    if ax ~= bx then return ax > bx and 1 or -1 end
    if ay ~= by then return ay > by and 1 or -1 end
    if az ~= bz then return az > bz and 1 or -1 end
    return 0
end

RaidTrack.MIN_PEER_VERSION = RaidTrack.MIN_PEER_VERSION or "0.0.0"  -- stała domyślna

local function required_min_version()
    local dbmin = RaidTrackDB and RaidTrackDB.settings and RaidTrackDB.settings.minAddonVersion or "0.0.0"
    local v1 = RaidTrack.VERSION or "0.0.0"
    local v2 = RaidTrack.MIN_PEER_VERSION or "0.0.0"
    local function pick_max(a,b) return semver_cmp(a,b) >= 0 and a or b end
    return pick_max(v1, pick_max(dbmin, v2))
end

local function peer_meets_my_min(v)
    return semver_cmp(v or "0.0.0", required_min_version()) >= 0
end

-- wersjonowany PING
local function send_ping(name)
    local need = required_min_version()
    local ping = string.format("PING|%s|%d|%s", RaidTrack.VERSION, RaidTrack.PROTOCOL, need)
    C_ChatInfo.SendAddonMessage("RaidTrackSync", ping, "WHISPER", name)
end

-- — (opcjonalny) user messaging dla legacy (anty-spam)
RaidTrack._notifiedLegacy = RaidTrack._notifiedLegacy or {}
local function notifyLegacy(who, need, reason)
    if not who or who == "" then return end
    if RaidTrack._notifiedLegacy[who] then return end
    RaidTrack._notifiedLegacy[who] = true
    local suffix = reason and (" ("..reason..")") or ""
    local text = ("[RaidTrack] Your addon is incompatible%s. Please update to %s+ to sync."):format(suffix, tostring(need))
    SendChatMessage(text, "WHISPER", nil, who)
end
-- === koniec sekcji version gating ===

local CHUNK_SIZE = 200
local SEND_DELAY = 0.25
local SYNC_PREFIX = "RaidTrackSync"

C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix("auction")
C_ChatInfo.RegisterAddonMessagePrefix("RTSYNC")

RaidTrack.pendingSends   = RaidTrack.pendingSends   or {}   -- who => {chunks=..., gotPong=..., meta={...}}
RaidTrack.chunkBuffer    = RaidTrack.chunkBuffer    or {}   -- odbiór chunków
RaidTrack.syncTimer      = RaidTrack.syncTimer      or nil
RaidTrack.peerCaps       = RaidTrack.peerCaps       or {}   -- who => {ver, proto, ok}
RaidTrack._pendingReqs   = RaidTrack._pendingReqs   or {}   -- who => {knownEP=..., knownLoot=...} (REQ_SYNC oczekujące na handshake)
RaidTrack.chunkHandlers  = RaidTrack.chunkHandlers  or {}

if not C_ChatInfo.IsAddonMessagePrefixRegistered("auction") then
    C_ChatInfo.RegisterAddonMessagePrefix("auction")
end

-- helper: aktualny wipeId (numer)
local function CurWipe()
    if RaidTrack.GetWipeId then
        return tonumber(RaidTrack.GetWipeId()) or 0
    end
    return tonumber(RaidTrackDB and RaidTrackDB.epgpWipeID or 0) or 0
end

local function dbg(msg)
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(msg) end
end

function RaidTrack.RegisterChunkHandler(prefix, handler)
    RaidTrack.chunkHandlers = RaidTrack.chunkHandlers or {}
    RaidTrack.chunkHandlers[prefix] = handler
end

RaidTrack.RegisterChunkHandler("RTSYNC", function(sender, message)
    RaidTrack.HandleChunkedRaidPiece(sender, message)
end)

local genericCommFrame = CreateFrame("Frame")
genericCommFrame:RegisterEvent("CHAT_MSG_ADDON")
genericCommFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    if not prefix or not message then return end
    if RaidTrack.chunkHandlers and RaidTrack.chunkHandlers[prefix] then
        RaidTrack.chunkHandlers[prefix](sender, message)
    end
end)

RaidTrack.RegisterChunkHandler("auction", function(sender, message)
    RaidTrack.HandleChunkedAuctionPiece(sender, message)
end)

function RaidTrack.ScheduleSync()
    if RaidTrack.syncTimer then
        RaidTrack.syncTimer:Cancel()
    end
    RaidTrack.syncTimer = C_Timer.NewTimer(0.5, function()
        RaidTrack.syncTimer = nil
        RaidTrack.SendSyncDeltaToEligible()
    end)
end

function RaidTrack.SendSyncDeltaToEligible()
    if not IsInGuild() then return end
    local me = UnitName("player")
    local minRank = RaidTrackDB.settings.minSyncRank or 0
    local myRank
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and Ambiguate(name, "none") == me then
            myRank = rankIndex
            break
        end
    end
    if not myRank or myRank > minRank then return end

    local sent = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name ~= me and rankIndex <= minRank and not sent[name] then
            sent[name] = true
            local knownEP   = RaidTrackDB.syncStates[name] or 0
            local knownLoot = RaidTrackDB.lootSyncStates[name] or 0
            local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP)
            local lootDelta = {}
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > knownLoot then table.insert(lootDelta, e) end
            end
            if #epgpDelta > 0 or #lootDelta > 0 then
                RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
            end
        end
    end
end

function RaidTrack.RequestSyncFromGuild()
    if not IsInGuild() then return end
    local me = UnitName("player")
    local epID = RaidTrackDB.epgpLog and RaidTrackDB.epgpLog.lastId or 0
    local lootID = 0
    for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
        if e.id and e.id > lootID then lootID = e.id end
    end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if name ~= me and online then
            -- legacy-safe: REQ_SYNC|<ep>|<loot> (handshake i tak wymusimy osobno)
            local msg = string.format("REQ_SYNC|%d|%d", epID, lootID)
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, msg, "WHISPER", name)
        end
    end
end

function RaidTrack.SendSyncData()
    if RaidTrack.HandleSendSync then
        RaidTrack.HandleSendSync()
    else
        -- noop
    end
end

function RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
    if not RaidTrack.IsPlayerInMyGuild(name) then return end
    RaidTrackDB.lootSyncStates = RaidTrackDB.lootSyncStates or {}

    -- GATE: nie wysyłamy danych (ani wipeID) do niezweryfikowanych/za starych klientów
    local caps = RaidTrack.peerCaps[name]
    if not (caps and caps.ok) then
        send_ping(name)  -- zainicjuj handshake
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("[Sync] Blocked send to " .. tostring(name) .. " (no caps/too old). Sent versioned PING.")
        end
        -- zapamiętaj intencję jeśli to przyszło z REQ_SYNC
        if knownEP ~= nil and knownLoot ~= nil then
            RaidTrack._pendingReqs[name] = { knownEP = knownEP, knownLoot = knownLoot }
        end
        return
    end

    local sendFull = (knownEP == 0 and knownLoot == 0)
    local payload, maxEP, maxLoot

    if sendFull then
        maxEP, maxLoot = 0, 0
        for _, e in ipairs(RaidTrackDB.epgpLog.changes or {}) do
            if e.id and e.id > maxEP then maxEP = e.id end
        end
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
            if e.id and e.id > maxLoot then maxLoot = e.id end
        end
        if maxEP == 0 and maxLoot == 0 then return end

        payload = {
            full = {
                epgp        = RaidTrackDB.epgp,
                loot        = RaidTrackDB.lootHistory,
                epgpLog     = RaidTrackDB.epgpLog.changes,
                settings    = RaidTrackDB.settings or {},
                epgpWipeID  = CurWipe(),  -- aktualny wipeId
            }
        }

        RaidTrack.pendingSends[name] = { meta = { lastEP = maxEP, lastLoot = maxLoot } }
        RaidTrackDB.syncStates[UnitName("player")]      = maxEP
        RaidTrackDB.lootSyncStates[UnitName("player")]  = maxLoot
    else
        local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP or 0)
        local lootDelta = {}
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
            if e.id and e.id > (knownLoot or 0) then table.insert(lootDelta, e) end
        end
        payload = {
            epgpDelta   = epgpDelta,
            lootDelta   = lootDelta,
            epgpWipeID  = CurWipe(),  -- niosą też wipeId
        }

        local maxEP2, maxLoot2 = knownEP or 0, knownLoot or 0
        for _, e in ipairs(epgpDelta) do if e.id and e.id > maxEP2  then maxEP2  = e.id end end
        for _, e in ipairs(lootDelta) do if e.id and e.id > maxLoot2 then maxLoot2 = e.id end end

        RaidTrackDB.syncStates[name]                   = maxEP2
        RaidTrackDB.lootSyncStates[name]               = maxLoot2
        RaidTrackDB.syncStates[UnitName("player")]     = maxEP2
        RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot2
    end

    local str = RaidTrack.SafeSerialize(payload)
    local total = math.ceil(#str / CHUNK_SIZE)
    local chunks = {}
    for i = 1, total do
        chunks[i] = str:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
    end
    RaidTrack.pendingSends[name] = RaidTrack.pendingSends[name] or {}
    RaidTrack.pendingSends[name].chunks = chunks

    -- nie wysyłamy nic więcej – chunks wyśle się po PONG tylko jeśli ktoś oczekiwał (poniżej w handlerze)
    -- tutaj peer już jest validated, więc możemy od razu odpalić batch:
    RaidTrack.SendChunkBatch(name)
end

function RaidTrack.SendChunkBatch(name)
    local p = RaidTrack.pendingSends[name]
    if not p or not p.chunks then return end

    if not p.chunks or #p.chunks == 0 then
        if p.timer then p.timer:Cancel() end
        RaidTrack.pendingSends[name] = nil
        RaidTrack.lastSyncTime = time()
        return
    end

    local any = false
    for idx, c in ipairs(p.chunks) do
        if c then
            any = true
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, string.format("%d|%d|%s", idx, #p.chunks, c), "WHISPER", name)
        end
    end
    if not any then
        if p.timer then p.timer:Cancel() end
        RaidTrack.pendingSends[name] = nil
        if p.meta and p.meta.lastEP and p.meta.lastLoot then
            RaidTrackDB.syncStates[UnitName("player")]     = p.meta.lastEP
            RaidTrackDB.lootSyncStates[UnitName("player")] = p.meta.lastLoot
        end
        RaidTrack.lastSyncTime = time()
    end
end

-- Lekki broadcast do gildii (bez ujawniania wipeID) + pełny tylko do zweryfikowanych peerów
function RaidTrack.BroadcastSettings()
    if not RaidTrack.IsOfficer() then return end

    if RaidTrack.ApplyUITabVisibility then RaidTrack.ApplyUITabVisibility() end
    if RaidTrack.RefreshMinimapMenu then RaidTrack.RefreshMinimapMenu() end

    -- 1) Lekki broadcast do GUILD (bez epgpWipeID)
    local light = {
        settings = {
            minSyncRank       = RaidTrackDB.settings.minSyncRank,
            officerOnly       = RaidTrackDB.settings.officerOnly,
            autoSync          = RaidTrackDB.settings.autoSync,
            minUITabRankIndex = RaidTrackDB.settings.minUITabRankIndex,
        }
    }
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "CFG_LIGHT|" .. RaidTrack.SafeSerialize(light), "GUILD")

    -- 2) Pełny CFG (z wipeID) tylko do klientów spełniających minimum
    local full = {
        settings   = light.settings,
        epgpWipeID = CurWipe(),
    }
    local sFull = "CFG|" .. RaidTrack.SafeSerialize(full)

    local me = Ambiguate(UnitName("player"), "none")
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name and name ~= me then
            local caps = RaidTrack.peerCaps[name]
            if caps and caps.ok then
                C_ChatInfo.SendAddonMessage(SYNC_PREFIX, sFull, "WHISPER", name)
            else
                send_ping(name)
            end
        end
    end
end

-- Broadcast wipe (CFG z wipe=true) tylko do zweryfikowanych peerów
function RaidTrack.BroadcastWipeToValidatedPeers(newWipeId, reason)
    if not RaidTrack.IsOfficer() then return end
    local payload = { wipe = true, epgpWipeID = newWipeId, reason = tostring(reason or "") }
    local msg = "CFG|" .. RaidTrack.SafeSerialize(payload)

    local me = Ambiguate(UnitName("player"), "none")
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name and name ~= me then
            local caps = RaidTrack.peerCaps[name]
            if caps and caps.ok then
                C_ChatInfo.SendAddonMessage(SYNC_PREFIX, msg, "WHISPER", name)
            else
                local need = required_min_version()
                C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "ERR|UPGRADE|"..need, "WHISPER", name)
                send_ping(name)
            end
        end
    end
end

-- główny handler
local mf = CreateFrame("Frame")
mf:RegisterEvent("CHAT_MSG_ADDON")
mf:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    -- aukcje (chunkowane innym prefiksem)
    if prefix == "auction" and sender ~= UnitName("player") then
        if msg:sub(1, 8) == "RTCHUNK^" then
            RaidTrack.HandleChunkedAuctionPiece(sender, msg)
        end
        return
    end

    -- tylko nasz sync
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then return end
    local who = Ambiguate(sender, "none")

    -- === legacy auction (zostawione dla wstecznej kompatybilności) ===
    if msg:sub(1, 13) == "AUCTION_ITEM|" then
        local payload = msg:sub(14)
        local ok, data = RaidTrack.SafeDeserialize(payload)
        if ok and data and data.auctionID and data.item then
            RaidTrack.partialAuction = RaidTrack.partialAuction or {}
            RaidTrack.partialAuction[data.auctionID] = RaidTrack.partialAuction[data.auctionID] or {
                items = {}, leader = "", started = 0, duration = 0
            }
            table.insert(RaidTrack.partialAuction[data.auctionID].items, {
                link = data.item.link, gp = data.item.gp, responses = {}
            })
        else
            dbg("Failed to deserialize AUCTION_ITEM")
        end
        return
    end

    if msg:sub(1, 14) == "AUCTION_START|" then
        local payload = msg:sub(15)
        local ok, data = RaidTrack.SafeDeserialize(payload)
        if ok and data and data.auctionID then
            C_Timer.After(0.3, function()
                local auctionItems = RaidTrack.pendingAuctionItems and RaidTrack.pendingAuctionItems[data.auctionID] or {}
                data.items = auctionItems
                RaidTrack.ReceiveAuctionHeader(data)
                RaidTrack.pendingAuctionItems[data.auctionID] = nil
            end)
        else
            dbg("RaidTrack: Received invalid auction data from leader.")
        end
        return
    end
    -- === koniec legacy auction ===

    -- === wersjonowany handshake ===
    if msg:sub(1,4) == "PING" then
        local v, p, min = msg:match("^PING|([^|]+)|(%d+)|([^|]+)$")
        if v and p and min then
            if tonumber(p) ~= RaidTrack.PROTOCOL then
                C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "ERR|PROTO|"..RaidTrack.PROTOCOL, "WHISPER", who)
                notifyLegacy(who, required_min_version(), "protocol mismatch")
                return
            end
            if semver_cmp(RaidTrack.VERSION, min) < 0 then
                C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "ERR|UPGRADE|"..min, "WHISPER", who)
                notifyLegacy(who, min, "handshake")
                return
            end
            local pong = string.format("PONG|%s|%d", RaidTrack.VERSION, RaidTrack.PROTOCOL)
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, pong, "WHISPER", who)
            return
        else
            -- legacy ping
            local need = required_min_version()
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "ERR|UPGRADE|"..need, "WHISPER", who)
            notifyLegacy(who, need, "handshake")
            return
        end

    elseif msg:sub(1,4) == "PONG" then
        local v, p = msg:match("^PONG|([^|]+)|(%d+)$")
        if v and p then
            if tonumber(p) ~= RaidTrack.PROTOCOL then
                RaidTrack.peerCaps[who] = { ver = v, proto = tonumber(p), ok = false }
                dbg("[Sync] PONG proto mismatch from " .. tostring(who))
                return
            end
            local ok = peer_meets_my_min(v)
            RaidTrack.peerCaps[who] = { ver = v, proto = tonumber(p), ok = ok }
            if not ok then
                dbg("[Sync] PONG too old from " .. tostring(who) .. " v="..tostring(v))
                return
            end
            -- jeśli był REQ_SYNC oczekujący na handshake -> dokończ wysyłkę
            local pend = RaidTrack._pendingReqs[who]
            if pend then
                RaidTrack._pendingReqs[who] = nil
                RaidTrack.SendSyncDataTo(who, pend.knownEP or 0, pend.knownLoot or 0)
                return
            end
            -- jeśli ktoś czeka na PONG do wysłania chunków:
            if RaidTrack.pendingSends[who] and RaidTrack.pendingSends[who].chunks then
                RaidTrack.pendingSends[who].gotPong = true
                RaidTrack.SendChunkBatch(who)
                return
            end
            RaidTrack.lastSyncTime = time()
            return
        else
            -- legacy PONG → ignorujemy
            RaidTrack.peerCaps[who] = { ver = "0.0.0", proto = 0, ok = false }
            dbg("[Sync] Legacy PONG from " .. tostring(who))
            return
        end

    elseif msg:sub(1,10) == "ERR|PROTO|" then
        dbg("[Sync] Peer protocol mismatch: "..tostring(who))
        return

    elseif msg:sub(1,12) == "ERR|UPGRADE|" then
        dbg("[Sync] Peer needs upgrade: "..tostring(who))
        return
    end
    -- === koniec wersjonowanego handshake ===

    -- REQ_SYNC|<ep>|<loot> (legacy-safe). Wysyłamy dopiero po walidacji.
    if msg:sub(1, 9) == "REQ_SYNC|" then
        local ep, loot = msg:match("^REQ_SYNC|(%d+)|(%d+)$")
        if not ep or not loot then
            -- fallback dla dziwnych payloadów
            local parts = { strsplit("|", msg) }
            ep   = tonumber(parts[2] or 0) or 0
            loot = tonumber(parts[3] or 0) or 0
        else
            ep   = tonumber(ep) or 0
            loot = tonumber(loot) or 0
        end

        local caps = RaidTrack.peerCaps[who]
        if not (caps and caps.ok) then
            RaidTrack._pendingReqs[who] = { knownEP = ep, knownLoot = loot }
            send_ping(who)
            dbg("[Sync] REQ_SYNC queued (await handshake) from "..tostring(who))
            return
        end

        RaidTrack.SendSyncDataTo(who, ep, loot)
        return
    end

    if msg:sub(1, 4) == "ACK|" then
        local idx = tonumber(msg:sub(5))
        local p = RaidTrack.pendingSends[who]
        if p and p.chunks and p.chunks[idx] then p.chunks[idx] = nil end
        return
    end

    if msg:sub(1, 10) == "CFG_LIGHT|" then
        local cfgStr = msg:sub(11)
        local ok, data = RaidTrack.SafeDeserialize(cfgStr)
        if ok and data and data.settings then
            for k, v in pairs(data.settings) do
                if v ~= nil then RaidTrackDB.settings[k] = v end
            end
            if RaidTrack.UpdateSettingsTab   then RaidTrack.UpdateSettingsTab() end
            if RaidTrack.ApplyUITabVisibility then RaidTrack.ApplyUITabVisibility() end
            if RaidTrack.RefreshMinimapMenu then RaidTrack.RefreshMinimapMenu() end
        end
        return
    end

    if msg:sub(1, 4) == "CFG|" then
        local cfgStr = msg:sub(5)
        local ok, data = RaidTrack.SafeDeserialize(cfgStr)
        if not ok then return end

        -- nie przyjmuj wipe/epgpWipeID od niezweryfikowanego nadawcy
        if (data.wipe or data.epgpWipeID) and not (RaidTrack.peerCaps[who] and RaidTrack.peerCaps[who].ok) then
            dbg("[Sync] Ignored CFG wipe from non-validated peer: "..tostring(who))
            data.wipe, data.epgpWipeID = nil, nil
        end

        local localWipe = CurWipe()

        -- WIPE announcement → jeśli wyższy: adoptuj, wyczyść i poproś NADAWCĘ o FULL
        if data.wipe and tonumber(data.epgpWipeID or 0) then
            local incoming = tonumber(data.epgpWipeID) or 0
            if incoming > localWipe and RaidTrack.TryAdoptRemoteWipeId and RaidTrack.TryAdoptRemoteWipeId(incoming, who) then
                RaidTrackDB.epgp, RaidTrackDB.lootHistory = {}, {}
                RaidTrackDB.epgpLog = { changes = {}, lastId = 0 }
                RaidTrackDB.syncStates, RaidTrackDB.lootSyncStates = {}, {}
                RaidTrackDB.epgpWipeID = tostring(incoming)
                if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
                if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end
                C_Timer.After(0.2, function()
                    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "REQ_SYNC|0|0", "WHISPER", who)
                end)
            end
            return
        end

        -- CFG z epgpWipeID (bez wipe=true) → adoptuj i poproś o FULL
        if data.epgpWipeID and tonumber(data.epgpWipeID) then
            local incoming = tonumber(data.epgpWipeID) or 0
            if incoming > localWipe and RaidTrack.TryAdoptRemoteWipeId and RaidTrack.TryAdoptRemoteWipeId(incoming, who) then
                RaidTrackDB.epgpWipeID = tostring(incoming)
                C_Timer.After(0.2, function()
                    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "REQ_SYNC|0|0", "WHISPER", who)
                end)
            end
        end

        -- zwykłe ustawienia
        if data.settings then
            for k, v in pairs(data.settings) do
                if v ~= nil then RaidTrackDB.settings[k] = v end
            end
            if RaidTrack.UpdateSettingsTab   then RaidTrack.UpdateSettingsTab() end
            if RaidTrack.ApplyUITabVisibility then RaidTrack.ApplyUITabVisibility() end
            if RaidTrack.RefreshMinimapMenu then RaidTrack.RefreshMinimapMenu() end
        end
        return
    end

    -- === Chunk łączenie (FULL/DELTA) ===
    local i, t, d = msg:match("^(%d+)|(%d+)|(.+)$")
    i, t = tonumber(i), tonumber(t)
    if not (i and t and d) then return end

    local buf = RaidTrack.chunkBuffer[who] or { chunks = {}, total = t, received = 0 }
    RaidTrack.chunkBuffer[who] = buf
    if not buf.chunks[i] then
        buf.chunks[i] = d
        buf.received = buf.received + 1
    end
    if buf.received == buf.total then
        local full = table.concat(buf.chunks)
        RaidTrack.chunkBuffer[who] = nil
        local ok, data = RaidTrack.SafeDeserialize(full)
        if not ok then return end

        -- FULL od niezweryfikowanego peera? Nie przyjmujemy.
        if data.full and not (RaidTrack.peerCaps[who] and RaidTrack.peerCaps[who].ok) then
            dbg("[Sync] Ignored FULL from non-validated peer: "..tostring(who))
            return
        end
        -- DELTA od niezweryfikowanego peera? Nie przyjmujemy.
        if (data.epgpDelta or data.lootDelta or data.epgpWipeID) and not (RaidTrack.peerCaps[who] and RaidTrack.peerCaps[who].ok) then
            dbg("[Sync] Ignored DELTA from non-validated peer: "..tostring(who))
            return
        end

        -- === FULL ===
        if data.full then
            local incomingWipe = tonumber(data.full.epgpWipeID or 0) or 0
            local localWipe    = CurWipe()

            if incomingWipe > localWipe then
                if not (RaidTrack.TryAdoptRemoteWipeId and RaidTrack.TryAdoptRemoteWipeId(incomingWipe, who)) then
                    dbg("[Sync] Ignored FULL from " .. tostring(who) .. " (adoption refused)")
                    return
                end
                RaidTrackDB.epgp, RaidTrackDB.lootHistory = {}, {}
                RaidTrackDB.epgpLog = { changes = {}, lastId = 0 }
                RaidTrackDB.syncStates, RaidTrackDB.lootSyncStates = {}, {}
            elseif incomingWipe < localWipe then
                dbg("[Sync] Ignored FULL from " .. tostring(who) ..
                    " (older wipe: incoming=" .. tostring(incomingWipe) .. ", local=" .. tostring(localWipe) .. ")")
                return
            end

            -- przyjmij bazę
            RaidTrackDB.epgp        = data.full.epgp or {}
            RaidTrackDB.lootHistory = data.full.loot or {}

            local maxLoot = 0
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > maxLoot then maxLoot = e.id end
            end

            if data.full.settings then
                for k, v in pairs(data.full.settings) do RaidTrackDB.settings[k] = v end
            end

            RaidTrackDB.epgpWipeID = tostring(CurWipe())

            RaidTrackDB.epgpLog = {
                changes = data.full.epgpLog or {},
                lastId  = (data.full.epgpLog[#(data.full.epgpLog or {})] and data.full.epgpLog[#data.full.epgpLog].id) or 0
            }
            local lastEP = RaidTrackDB.epgpLog.lastId or 0

            RaidTrackDB.syncStates[who]                    = lastEP
            RaidTrackDB.syncStates[UnitName("player")]     = lastEP
            RaidTrackDB.lootSyncStates[who]                = maxLoot
            RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot

            RaidTrack.lastSyncTime = time()
            if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
            if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end

            if lastEP == 0 or maxLoot == 0 then
                C_Timer.After(2, function() RaidTrack.RequestSyncFromGuild() end)
            end
            return
        end

        -- === DELTA ===
        local incomingWipeDelta = tonumber(data.epgpWipeID or 0) or 0
        local localWipe         = CurWipe()

        if incomingWipeDelta > localWipe then
            if RaidTrack.TryAdoptRemoteWipeId and RaidTrack.TryAdoptRemoteWipeId(incomingWipeDelta, who) then
                C_Timer.After(0.2, function()
                    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "REQ_SYNC|0|0", "WHISPER", who)
                end)
            end
            return
        elseif incomingWipeDelta < localWipe then
            dbg("[Sync] Ignored DELTA from " .. tostring(who) ..
                " (older wipe: incoming=" .. tostring(incomingWipeDelta) .. ", local=" .. tostring(localWipe) .. ")")
            return
        end

        -- normalny merge delty
        RaidTrack.MergeEPGPChanges(data.epgpDelta or {})
        local newLastEP = 0
        for _, e in ipairs(data.epgpDelta or {}) do
            if e.id and e.id > newLastEP then newLastEP = e.id end
        end
        if newLastEP > 0 then
            RaidTrackDB.syncStates[who]                = newLastEP
            RaidTrackDB.syncStates[UnitName("player")] = newLastEP
        end

        local seen = {}
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do seen[e.id] = true end
        local mx = RaidTrackDB.lootSyncStates[who] or 0
        for _, e in ipairs(data.lootDelta or {}) do
            if e.id and not seen[e.id] then
                table.insert(RaidTrackDB.lootHistory, e)
                seen[e.id] = true
                if e.id > mx then mx = e.id end
            end
        end
        RaidTrackDB.lootSyncStates[who] = mx
        if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end
        RaidTrack.lastSyncTime = time()
    end
end)

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" and RaidTrackDB.settings.autoSync ~= false then
        C_Timer.After(5, function() RaidTrack.RequestSyncFromGuild() end)
    end
    if RaidTrack.IsOfficer() then
        C_Timer.After(10, function() RaidTrack.BroadcastSettings() end)
    end
    if RaidTrack.BroadcastRaidSync then
        RaidTrack.BroadcastRaidSync()
    end
end)

-- === auction chunk (bez zmian logiki, tylko drobne sanity) ===
local af = CreateFrame("Frame")
af:RegisterEvent("CHAT_MSG_ADDON")
af:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    if prefix == "auction" and sender ~= UnitName("player") then
        if msg:sub(1, 8) == "RTCHUNK^" then
            RaidTrack.HandleChunkedAuctionPiece(sender, msg)
        else
            RaidTrack.AddDebugMessage("Ignored non-chunked auction message: " .. tostring(msg))
        end
        return
    end
end)

function RaidTrack.QueueChunkedSend(target, prefix, data, channelOverride)
    local chunks = {}
    local maxSize = 200
    for i = 1, #data, maxSize do
        table.insert(chunks, data:sub(i, i + maxSize - 1))
    end
    local channel = channelOverride or (IsInRaid() and "RAID" or "GUILD")
    for i, chunk in ipairs(chunks) do
        local marker = "RTCHUNK^" .. i .. "^" .. #chunks .. "^" .. chunk
        C_ChatInfo.SendAddonMessage(prefix, marker, channel, target or "")
    end
end

function RaidTrack.QueueAuctionBroadcastSend(prefix, data)
    local chunks = {}
    local maxSize = 200
    for i = 1, #data, maxSize do
        table.insert(chunks, data:sub(i, i + maxSize - 1))
    end
    for i, chunk in ipairs(chunks) do
        local marker = "RTCHUNK^" .. i .. "^" .. #chunks .. "^" .. chunk
        C_ChatInfo.SendAddonMessage(prefix, marker, "RAID")
    end
end

function RaidTrack.QueueAuctionChunkedSend(target, auctionID, messageType, input)
    if type(input) ~= "table" then error("QueueAuctionChunkedSend: input must be a table") end

    local payloadTable = input
    for idx, item in ipairs(payloadTable) do
        if item.itemID then
            item.uniqueItemID = item.itemID .. "_" .. auctionID
        else
            RaidTrack.AddDebugMessage("Error: itemID is nil for item at index " .. tostring(idx))
            return
        end
        if item.responses then
            for player, response in pairs(item.responses) do
                local ep, gp, pr = RaidTrack.GetEPGP(player)
                response.ep = ep; response.gp = gp; response.pr = pr
            end
        end
    end

    local fullPayload = {
        auctionID = auctionID,
        type      = "auction",
        payload   = payloadTable,
        subtype   = messageType
    }

    local serialized = RaidTrack.SafeSerialize(fullPayload)
    RaidTrack.QueueAuctionBroadcastSend("auction", serialized)
end

function RaidTrack.ReceiveAuctionChunked(sender, rawData)
    if rawData:sub(1, 8) == "RTCHUNK^" then return end

    local ok, data = RaidTrack.SafeDeserialize(rawData)
    if not ok then return end
    if data.type ~= "auction" then return end

    RaidTrack.pendingAuctionItems = RaidTrack.pendingAuctionItems or {}
    RaidTrack.pendingAuctionItems[data.auctionID] = RaidTrack.pendingAuctionItems[data.auctionID] or {}

    if data.subtype == "item" then
        local itemData = data.payload
        if itemData and itemData.itemID then
            local itemExists = false
            for _, item in ipairs(RaidTrack.pendingAuctionItems[data.auctionID]) do
                if item.itemID == itemData.itemID then itemExists = true; break end
            end
            if not itemExists then
                local uniqueItemID = tostring(itemData.itemID) .. "_" .. data.auctionID
                table.insert(RaidTrack.pendingAuctionItems[data.auctionID], {
                    itemID = itemData.itemID, uniqueItemID = uniqueItemID, gp = itemData.gp, responses = {}
                })
            else
                RaidTrack.AddDebugMessage("Item with itemID=" .. tostring(itemData.itemID) .. " already exists, skipping.")
            end
        else
            RaidTrack.AddDebugMessage("Invalid auction item data!")
        end

    elseif data.subtype == "header" then
        local headerData = data.payload
        if headerData then
            local items = RaidTrack.pendingAuctionItems[data.auctionID] or {}

            if UnitIsUnit(headerData.leader, "player") then
                RaidTrack:OpenAuctionLeaderUI()
            end

            if IsInRaid() and IsInGuild() then
                RaidTrack.OpenAuctionParticipantUI({
                    auctionID = data.auctionID,
                    leader    = headerData.leader,
                    started   = headerData.started,
                    endsAt    = headerData.endsAt,
                    duration  = headerData.duration,
                    items     = items
                })
            else
                RaidTrack.AddDebugMessage("Blocked auction popup (not in raid or not in guild)")
            end

            RaidTrack.activeAuctions = RaidTrack.activeAuctions or {}
            RaidTrack.activeAuctions[data.auctionID] = {
                items    = items,
                leader   = headerData.leader,
                started  = headerData.started,
                endsAt   = headerData.endsAt,
                duration = headerData.duration
            }
            RaidTrack.pendingAuctionItems[data.auctionID] = nil
        else
            RaidTrack.AddDebugMessage("Invalid auction header data!")
        end

    elseif data.subtype == "response" then
        if data.payload then
            local auction = RaidTrack.activeAuctions[data.auctionID]
            if auction and auction.leader and UnitIsUnit("player", auction.leader) then
                RaidTrack.HandleAuctionResponse(data.auctionID, data.payload)
            else
                RaidTrack.AddDebugMessage("Not the leader or auction missing, skipping.")
            end
        else
            RaidTrack.AddDebugMessage("Missing payload in auction response chunk!")
        end
    end
end

function RaidTrack.HandleAuctionResponse(auctionID, responseData)
    if type(auctionID) ~= "string" and type(auctionID) ~= "number" then
        RaidTrack.AddDebugMessage("ERROR: Invalid auctionID in responseData (type=" .. type(auctionID) .. ")"); return
    end
    if not responseData or not responseData.itemID or not responseData.from or not responseData.choice then
        RaidTrack.AddDebugMessage("ERROR: Incomplete responseData"); return
    end
    auctionID = tostring(auctionID)

    local auctionData = RaidTrack.activeAuctions and RaidTrack.activeAuctions[auctionID]
    local auctionItems = auctionData and auctionData.items
    if not auctionItems then
        RaidTrack.AddDebugMessage("ERROR: No auction items found for auctionID " .. auctionID); return
    end

    local matched = false
    for _, item in ipairs(auctionItems) do
        local itemID = tonumber(item.itemID)
        local responseItemID = tonumber(responseData.itemID)
        if itemID == responseItemID then
            matched = true
            item.bids = item.bids or {}
            local responseExists = false
            for _, bid in ipairs(item.bids) do
                if bid.from == responseData.from then
                    bid.choice = responseData.choice
                    responseExists = true
                    break
                end
            end
            if not responseExists and responseData.choice ~= "PASS" then
                table.insert(item.bids, responseData)
            end
            if responseData.from == auctionData.leader then
                RaidTrack.UpdateLeaderAuctionUI(auctionID, item)
            end
            RaidTrack.UpdateLeaderAuctionUI(auctionID)
            RaidTrack.DebugPrintResponses(item)
            break
        else
            RaidTrack.AddDebugMessage("ItemID " .. tostring(itemID) .. " does not match response itemID " .. tostring(responseItemID))
        end
    end

    if matched then
        if RaidTrack.RefreshAuctionLeaderTabs then RaidTrack.RefreshAuctionLeaderTabs() end
    else
        RaidTrack.AddDebugMessage("WARNING: No matching item found for response itemID " .. tostring(responseData.itemID))
    end
end

-- RAID SYNC (RTSYNC) chunki
function RaidTrack.HandleChunkedRaidPiece(sender, message)
    if not message:find("^RTCHUNK") then return end

    local parts = { strsplit("^", message) }
    local _, chunkNum, totalChunks, chunkData = unpack(parts)

    chunkNum    = tonumber(chunkNum)
    totalChunks = tonumber(totalChunks)

    local key = sender .. "_RTSYNC"
    RaidTrack._chunkBuffers = RaidTrack._chunkBuffers or {}
    RaidTrack._chunkBuffers[key] = RaidTrack._chunkBuffers[key] or {}
    RaidTrack._chunkBuffers[key][chunkNum] = chunkData

    local buffer = RaidTrack._chunkBuffers[key]
    local count = 0
    for i = 1, totalChunks do if buffer[i] then count = count + 1 end end

    if count == totalChunks then
        local full = table.concat(buffer, "")
        RaidTrack._chunkBuffers[key] = nil

        local ok, data = RaidTrack.SafeDeserialize(full)
        if ok and data then
            if data.activeID and not IsInRaid() then
                data.activeID = nil
            end
            RaidTrack.MergeRaidSyncData(data, sender)
        else
            RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from " .. sender)
        end
    end
end

function RaidTrack.HandleChunkedAuctionPiece(sender, msg)
    if not sender or sender == "" then
        sender = UnitName("player")
    end
    local index, total, chunk = msg:match("^RTCHUNK%^(%d+)%^(%d+)%^(.+)$")
    if not index or not total or not chunk then return end

    index = tonumber(index); total = tonumber(total)
    if not index or not total then
        RaidTrack.AddDebugMessage("Error: invalid index or total.")
        return
    end

    RaidTrack._auctionChunks = RaidTrack._auctionChunks or {}
    RaidTrack._auctionChunks[sender] = RaidTrack._auctionChunks[sender] or {}
    local list = RaidTrack._auctionChunks[sender]
    list[index] = chunk

    for i = 1, total do
        if not list[i] then return end
    end

    local fullData = table.concat(list, "")
    RaidTrack._auctionChunks[sender] = nil
    RaidTrack.ReceiveAuctionChunked(sender, fullData)
end
