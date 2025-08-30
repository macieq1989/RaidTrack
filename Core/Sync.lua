-- Core/Sync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrack.chunkHandlers = RaidTrack.chunkHandlers or {}

local CHUNK_SIZE = 200
local SEND_DELAY = 0.25
local SYNC_PREFIX = "RaidTrackSync"

C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix("auction")
C_ChatInfo.RegisterAddonMessagePrefix("RTSYNC")

RaidTrack.pendingSends = {}
RaidTrack.chunkBuffer = {}
RaidTrack.syncTimer = nil

RaidTrack.chunkHandlers = RaidTrack.chunkHandlers or {}

-- ===== Wipe / CFG state =====
RaidTrack._cfgSeen = RaidTrack._cfgSeen or false -- mamy już jakieś CFG od oficera
RaidTrack._pendingWipe = RaidTrack._pendingWipe or false -- czekamy na FULL z nie-pustym EPGP
RaidTrack._lastCfgFrom = RaidTrack._lastCfgFrom or nil -- kto ostatnio wysłał CFG
-- ostatni zastosowany snapshot FULL (podpis: wipeID|lastEP|maxLoot)
RaidTrack._lastAppliedFullSig = RaidTrack._lastAppliedFullSig or ""


if not C_ChatInfo.IsAddonMessagePrefixRegistered("auction") then
    C_ChatInfo.RegisterAddonMessagePrefix("auction")
end

function RaidTrack.RegisterChunkHandler(prefix, handler)
    RaidTrack.chunkHandlers = RaidTrack.chunkHandlers or {}
    RaidTrack.chunkHandlers[prefix] = handler
end

local genericCommFrame = CreateFrame("Frame")
genericCommFrame:RegisterEvent("CHAT_MSG_ADDON")
genericCommFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)

    if not prefix or not message then
        return
    end
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
    if not IsInGuild() then
        return
    end
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
    if not myRank or myRank > minRank then
        return
    end

    local sent = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name ~= me and rankIndex <= minRank and not sent[name] then
            sent[name] = true
            local knownEP = RaidTrackDB.syncStates[name] or 0
            local knownLoot = RaidTrackDB.lootSyncStates[name] or 0
            local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP)
            local lootDelta = {}
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > knownLoot then
                    table.insert(lootDelta, e)
                end
            end
            if #epgpDelta > 0 or #lootDelta > 0 then
                RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
            end
        end
    end
end

function RaidTrack.RequestSyncFromGuild()
    if not IsInGuild() then return end

    -- cooldown 15s, żeby nie spamować przy wielokrotnych wywołaniach
    RaidTrack._lastReqSyncAt = RaidTrack._lastReqSyncAt or 0
    local now = (GetTime and GetTime()) or time()
    if (now - RaidTrack._lastReqSyncAt) < 15 then return end
    RaidTrack._lastReqSyncAt = now

    local me = Ambiguate(UnitName("player"), "none")
    local epID = (RaidTrackDB.epgpLog and RaidTrackDB.epgpLog.lastId) or 0
    local lootID = 0
    for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
        if e.id and e.id > lootID then lootID = e.id end
    end

    -- wybierz JEDNEGO najlepszego kandydata: najniższy rankIndex (GM/officer)
    local minRank = tonumber(RaidTrackDB.settings.minSyncRank) or 1
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end

    local best, bestRank = nil, 99
    for i = 1, (GetNumGuildMembers() or 0) do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name ~= me then
            if rankIndex <= minRank and rankIndex < bestRank then
                best, bestRank = name, rankIndex
            end
        end
    end
    -- fallback: pierwszy lepszy online, jeśli brak oficera
    if not best then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            name = name and Ambiguate(name, "none")
            if online and name ~= me then best = name; break end
        end
    end
    if not best then return end

    local msg = string.format("REQ_SYNC|%d|%d", epID, lootID)
    C_ChatInfo.SendAddonMessage("RaidTrackSync", msg, "WHISPER", best)
end


function RaidTrack.SendSyncData()
    if RaidTrack.HandleSendSync then
        RaidTrack.HandleSendSync()
    else

    end
end

function RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
    if not RaidTrack.IsPlayerInMyGuild(name) then

        return
    end
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
            }
        }
        RaidTrackDB.syncStates[UnitName("player")] = maxEP
        RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
    else
        local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP)
        local lootDelta = {}
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
            if e.id and e.id > knownLoot then
                table.insert(lootDelta, e)
            end
        end
        payload = {
            epgpDelta = epgpDelta,
            lootDelta = lootDelta,
            epgpWipeID = RaidTrackDB.epgpWipeID or 0 -- ⬅ dorzucamy wipeID także w deltach
        }

        local maxEP, maxLoot = knownEP, knownLoot
        for _, e in ipairs(epgpDelta) do
            if e.id and e.id > maxEP then
                maxEP = e.id
            end
        end
        for _, e in ipairs(lootDelta) do
            if e.id and e.id > maxLoot then
                maxLoot = e.id
            end
        end

        RaidTrackDB.syncStates[name] = maxEP
        RaidTrackDB.lootSyncStates[name] = maxLoot
        RaidTrackDB.syncStates[UnitName("player")] = maxEP
        RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
    end

    local str = RaidTrack.SafeSerialize(payload)
    local total = math.ceil(#str / CHUNK_SIZE)
    local chunks = {}
    for i = 1, total do
        chunks[i] = str:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
    end
    RaidTrack.pendingSends[name] = RaidTrack.pendingSends[name] or {}
    RaidTrack.pendingSends[name].chunks = chunks

    -- Send initial ping to begin chunk transfer
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "PING", "WHISPER", name)

    if sendFull then
        C_Timer.NewTimer(15, function()
            local p = RaidTrack.pendingSends[name]
            if p and not p.gotPong then
                RaidTrack.pendingSends[name] = nil
            end
        end)
    end

    -- ✅ Always send settings as separate message
    if RaidTrack.IsOfficer() then
        local cfgPayload = {
            settings = {
                minSyncRank = RaidTrackDB.settings.minSyncRank,
                officerOnly = RaidTrackDB.settings.officerOnly,
                autoSync = RaidTrackDB.settings.autoSync
            }
        }
        local cfgStr = RaidTrack.SafeSerialize(cfgPayload)
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "CFG|" .. cfgStr, "WHISPER", name)

    end
end

function RaidTrack.SendChunkBatch(name)
    local p = RaidTrack.pendingSends[name]
    if not p or not p.chunks then
        return
    end

    -- ✅ Dodane: jeśli nie ma chunków, to też zaliczamy sync
    if not p.chunks or #p.chunks == 0 then
        if p.timer then
            p.timer:Cancel()
        end
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
        if p.timer then
            p.timer:Cancel()
        end
        RaidTrack.pendingSends[name] = nil
        if p.meta and p.meta.lastEP and p.meta.lastLoot then
            RaidTrackDB.syncStates[UnitName("player")] = p.meta.lastEP
            RaidTrackDB.lootSyncStates[UnitName("player")] = p.meta.lastLoot
        end
        RaidTrack.lastSyncTime = time()
    end
end

function RaidTrack.BroadcastSettings(opts)
    opts = opts or {}
    if not RaidTrack.IsOfficer or not RaidTrack.IsOfficer() then
        return
    end

    local payload = {
        settings = {
            minSyncRank = RaidTrackDB.settings.minSyncRank,
            officerOnly = RaidTrackDB.settings.officerOnly,
            autoSync = RaidTrackDB.settings.autoSync,
            minUITabRankIndex = RaidTrackDB.settings.minUITabRankIndex,
            epgpWipeID = RaidTrackDB.epgpWipeID, -- JUŻ NIE generujemy „z powietrza”
            wipe = opts.wipe == true -- jawny sygnał wipe (domyślnie false)
        }
    }

    local msg = RaidTrack.SafeSerialize(payload)
    C_ChatInfo.SendAddonMessage("RaidTrackSync", "CFG|" .. msg, "GUILD")
end

function RaidTrack.StartGuildWipe()
    if not RaidTrack.IsOfficer or not RaidTrack.IsOfficer() then
        print("|cffff5555RaidTrack:|r Only officers can wipe EPGP.")
        return
    end

    -- wygeneruj NOWY gildiowy wipeID
    local newID = RaidTrack._GenerateGuildWipeID and RaidTrack._GenerateGuildWipeID() or
                      (tostring(time()) .. tostring(math.random(10000, 99999)))
    RaidTrackDB.epgpWipeID = newID

    -- 1) ogłoś CFG z wipe=true
    RaidTrack.BroadcastSettings({
        wipe = true
    })

    -- 2) natychmiast wyślij FULL (żeby odbiorcy mieli nie-pusty stan do przyjęcia)
    --    - używamy istniejącej ścieżki SendSyncDataTo(...) w trybie pełnym dla wszystkich online officerów/członków gildii
    --    - tu, dla prostoty, po prostu poproś o rozgłoszenie pełnych danych:
    if RaidTrack.SendSyncDataTo then
        -- wyślij FULL „na skróty” do całej gildii: poproś każdego online o REQ_SYNC, albo pętla po rosterze i wyślij full
        -- Masz już w kodzie mechanizm REQ_SYNC; najprościej:
        C_Timer.After(0.2, function()
            if RaidTrack.RequestSyncFromGuild then
                RaidTrack.RequestSyncFromGuild()
            end
        end)
    end

    print("|cff00ff88RaidTrack:|r Guild wipe announced. Full sync will follow.")
end

local function ApplyIncomingCfg(data, sender)
    -- data = { settings = { ..., epgpWipeID = "...", wipe = bool } }
    if type(data) ~= "table" or type(data.settings) ~= "table" then
        return
    end
    RaidTrack._cfgSeen = true
    RaidTrack._lastCfgFrom = Ambiguate(sender or "", "none")

    local s = data.settings
    -- aktualizuj ustawienia UI / uprawnień jak dotychczas
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

    -- stabilizacja wipeID (bez auto-wipe’u!)
    if type(s.epgpWipeID) == "string" and s.epgpWipeID ~= "" then
        -- przyjmij „źródło prawdy”, ale NIE czyść niczego tutaj
        RaidTrackDB.epgpWipeID = s.epgpWipeID
    end

    -- jawny wipe? TYLKO ustaw flagę i czekaj na FULL z EPGP
    if s.wipe == true then
        RaidTrack._pendingWipe = true
        RaidTrack.AddDebugMessage("CFG: wipe requested; waiting for FULL with non-empty EPGP")
    end

    -- lokalne odświeżenie UI (jak u Ciebie wcześniej)
    if RaidTrack.ApplyUITabVisibility then
        RaidTrack.ApplyUITabVisibility()
    end
    if RaidTrack.RefreshMinimapMenu then
        RaidTrack.RefreshMinimapMenu()
    end
end

local function _hasNonEmptyEPGP(tbl)
    if type(tbl) ~= "table" then return false end
    for _ in pairs(tbl) do return true end
    return false
end

local function _applyFullSnapshot(full, from)
    -- full = { epgp = {...}, loot = {...}, epgpLog = {...}, settings = {...}, epgpWipeID = "..." }
    if type(full) ~= "table" then return false end

    -- Zbuduj sygnaturę snapshotu, aby ignorować duplikaty FULL bez zmian
    local incWipe = tostring(full.epgpWipeID or RaidTrackDB.epgpWipeID or "")
    local incLastEP = 0
    for _, e in ipairs(full.epgpLog or {}) do
        if e.id and e.id > incLastEP then incLastEP = e.id end
    end
    local incMaxLoot = 0
    for _, e in ipairs(full.loot or {}) do
        if e.id and e.id > incMaxLoot then incMaxLoot = e.id end
    end
    local sig = incWipe .. "|" .. incLastEP .. "|" .. incMaxLoot

    -- Jeżeli to NIE jest pending wipe i sygnatura się nie zmieniła, zignoruj FULL
    if not RaidTrack._pendingWipe and RaidTrack._lastAppliedFullSig == sig then
        return false
    end

    -- jeśli mamy czekać na wipe, to wymagamy nie-pustego EPGP:
    if RaidTrack._pendingWipe then
        if not _hasNonEmptyEPGP(full.epgp) then
            RaidTrack.AddDebugMessage("FULL refused: pending wipe but EPGP is empty; requesting resend.")
            if C_ChatInfo and from then
                C_ChatInfo.SendAddonMessage("RaidTrackSync", "REQ_SYNC|0|0", "WHISPER", from)
            end
            return false
        end
        -- jasny wipe: czyścimy i wgrywamy snapshot
        RaidTrackDB.epgp           = type(full.epgp) == "table" and full.epgp or {}
        RaidTrackDB.lootHistory    = type(full.loot) == "table" and full.loot or {}
        RaidTrackDB.epgpLog        = type(full.epgpLog) == "table" and { changes = full.epgpLog, lastId = 0 } or { changes = {}, lastId = 0 }
        -- podbij stany sync
        RaidTrackDB.syncStates     = {}
        RaidTrackDB.lootSyncStates = {}
        -- ustaw ID z FULL-a (jeśli jest), inaczej zostaw to z CFG
        if type(full.epgpWipeID) == "string" and full.epgpWipeID ~= "" then
            RaidTrackDB.epgpWipeID = full.epgpWipeID
        end
        RaidTrack._pendingWipe = false
        RaidTrack._lastAppliedFullSig = sig
        RaidTrack.AddDebugMessage("FULL applied with wipe.")
        return true
    else
        -- brak wipe: po prostu przyjmij snapshot, ale NIE czyść lokalnych jeśli brakuje epgp
        if type(full.epgp) == "table" and _hasNonEmptyEPGP(full.epgp) then
            RaidTrackDB.epgp = full.epgp
        end
        if type(full.loot) == "table" then
            RaidTrackDB.lootHistory = full.loot
        end
        if type(full.epgpLog) == "table" then
            RaidTrackDB.epgpLog = { changes = full.epgpLog, lastId = 0 }
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
        RaidTrack.AddDebugMessage("FULL applied (no wipe).")
        return true
    end
end


-- (opcjonalnie) slash:
SLASH_RTWIPEEPGP1 = "/rtwipeepgp"
SlashCmdList["RTWIPEEPGP"] = function()
    RaidTrack.StartGuildWipe()
end

local mf = CreateFrame("Frame")
mf:RegisterEvent("CHAT_MSG_ADDON")
mf:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    -- 🧩 Aukcje (pozostaje jak było)
    if prefix == "auction" and sender ~= UnitName("player") then
        if msg:sub(1, 8) == "RTCHUNK^" then
            RaidTrack.HandleChunkedAuctionPiece(sender, msg)
        end
        return
    end

    -- 🔹 Dalej tylko nasz sync EPGP/loot
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then
        return
    end
    local who = Ambiguate(sender or "", "none")

    -- 🔽 Stare AUCTION_* (legacy) – bez zmian
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
            RaidTrack.AddDebugMessage("Failed to deserialize AUCTION_ITEM")
        end
        return
    elseif msg:sub(1, 14) == "AUCTION_START|" then
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
            RaidTrack.AddDebugMessage("RaidTrack: Received invalid auction data from leader.")
        end
        return
    end

    -- 🔽 PING/PONG/REQ_SYNC/ACK
    if msg == "PING" then
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "PONG", "WHISPER", who)
        return
    elseif msg == "PONG" and RaidTrack.pendingSends[who] then
        RaidTrack.pendingSends[who].gotPong = true
        RaidTrack.SendChunkBatch(who)
        return
    elseif msg == "PONG" then
        RaidTrack.lastSyncTime = time()
        return
    elseif msg:sub(1,9) == "REQ_SYNC|" then
        local _, epStr, lootStr = strsplit("|", msg)
        local knownEP   = tonumber(epStr)  or 0
        local knownLoot = tonumber(lootStr) or 0
        RaidTrack.SendSyncDataTo(who, knownEP, knownLoot)
        return
    elseif msg:sub(1,4) == "ACK|" then
        local idx = tonumber(msg:sub(5))
        local p = RaidTrack.pendingSends[who]
        if p and p.chunks[idx] then p.chunks[idx] = nil end
        return
    elseif msg:sub(1,4) == "CFG|" then
        local cfgStr = msg:sub(5)
        local ok, data = RaidTrack.SafeDeserialize(cfgStr)
        if ok and data then
            ApplyIncomingCfg(data, who)   -- ✅ nowy jawny CFG (może ustawić _pendingWipe)
        else
            RaidTrack.AddDebugMessage("CFG: invalid or failed to deserialize")
        end
        return
    end

    -- 🔽 Chunkowany FULL/DELTA
    local i, t, d = msg:match("^(%d+)|(%d+)|(.+)$")
    i, t = tonumber(i), tonumber(t)
    if not (i and t and d) then return end

    local buf = RaidTrack.chunkBuffer[who] or { chunks = {}, total = t, received = 0 }
    RaidTrack.chunkBuffer[who] = buf
    if not buf.chunks[i] then
        buf.chunks[i] = d
        buf.received = buf.received + 1
    end
    if buf.received ~= buf.total then return end

    local full = table.concat(buf.chunks)
    RaidTrack.chunkBuffer[who] = nil
    local ok, data = RaidTrack.SafeDeserialize(full)
    if not ok or not data then return end

    -- ===== FULL snapshot =====
    if data.full then
        local applied = _applyFullSnapshot(data.full, who)  -- ✅ zero implicit wipe
        if applied then
            -- uzupełnij stany i UI
            local lastEP = 0
            local ch = (data.full.epgpLog or {})
            for _, e in ipairs(ch) do
                if e.id and e.id > lastEP then lastEP = e.id end
            end
            local maxLoot = 0
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > maxLoot then maxLoot = e.id end
            end

            RaidTrackDB.syncStates[who]              = lastEP
            RaidTrackDB.syncStates[UnitName("player")] = lastEP
            RaidTrackDB.lootSyncStates[who]            = maxLoot
            RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot

            RaidTrack.lastSyncTime = time()
            if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
            if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end

            
        end
        return
    end

    -- ===== DELTA =====
    if RaidTrack._pendingWipe then
        RaidTrack.AddDebugMessage("Delta ignored: pending wipe; waiting for FULL")
        return
    end

    -- brak implicit-wipe po wipeID w delcie – po prostu stosuj delty
    RaidTrack.MergeEPGPChanges(data.epgpDelta or {})
    local newLastEP = 0
    for _, e in ipairs(data.epgpDelta or {}) do
        if e.id and e.id > newLastEP then newLastEP = e.id end
    end
    if newLastEP > 0 then
        RaidTrackDB.syncStates[who] = newLastEP
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
end)


local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" and RaidTrackDB.settings.autoSync ~= false then
        C_Timer.After(5, function()
            RaidTrack.RequestSyncFromGuild()
        end)
    end
    if RaidTrack.IsOfficer() then
        C_Timer.After(10, function()
            RaidTrack.BroadcastSettings()
        end)
    end
    if RaidTrack.BroadcastRaidSync then
        RaidTrack.BroadcastRaidSync()
    end
end)

-- Auction chunk handler registration
local af = CreateFrame("Frame")
af:RegisterEvent("CHAT_MSG_ADDON")
af:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    if prefix == "auction" and sender ~= UnitName("player") then
        if msg:sub(1, 8) == "RTCHUNK^" then
            RaidTrack.HandleChunkedAuctionPiece(sender, msg)
        else
            RaidTrack.AddDebugMessage("Ignored non-chunked auction message: " .. msg)
        end
        return
    end

end)

-- Jeśli msgId==nil -> LEGACY: RTCHUNK^<idx>^<total>^<chunk>
-- Jeśli msgId  jest -> NOWY:   RTCHUNK^<msgId>^<idx>^<total>^<chunk>
function RaidTrack.QueueChunkedSend(msgId, prefix, payload, channel)
    if type(prefix) ~= "string" or type(payload) ~= "string" or #payload == 0 then
        return
    end
    channel = channel or (IsInRaid() and "RAID" or "GUILD")

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    end

    local MAX = 200
    local total = math.ceil(#payload / MAX)
    if total < 1 then
        total = 1
    end

    local useNew = (type(msgId) == "string" and msgId ~= "")
    local CTL = _G.ChatThrottleLib -- użyj jeśli jest

    local function build(i)
        local s = (i - 1) * MAX + 1
        local part = payload:sub(s, s + MAX - 1)
        if useNew then
            return ("RTCHUNK^%s^%d^%d^%s"):format(msgId, i, total, part)
        else
            return ("RTCHUNK^%d^%d^%s"):format(i, total, part)
        end
    end

    if CTL and CTL.SendAddonMessage then
        -- Użyj biblioteki throttlingu: BULK dla >5 chunków
        local prio = (total > 5) and "BULK" or "NORMAL"
        for i = 1, total do
            CTL:SendAddonMessage(prio, prefix, build(i), channel)
        end
    else
        -- Awaryjnie: rozłóż wysyłkę w czasie (eliminuje burst)
        local gap = (total > 5) and 0.05 or 0.0
        for i = 1, total do
            local msg = build(i)
            if gap > 0 then
                C_Timer.After((i - 1) * gap, function()
                    C_ChatInfo.SendAddonMessage(prefix, msg, channel)
                end)
            else
                C_ChatInfo.SendAddonMessage(prefix, msg, channel)
            end
        end
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
    -- Debugowanie danych wejściowych
    if type(input) ~= "table" then

        error("QueueAuctionChunkedSend: input must be a table")
    end

    -- Ustawienie payloadTable na input
    local payloadTable = input

    -- Unikalne przypisanie identyfikatorów do przedmiotów i dodanie odpowiedzi graczy
    for idx, item in ipairs(payloadTable) do
        -- Nadaj unikalny identyfikator dla każdego przedmiotu
        if item.itemID then
            item.uniqueItemID = item.itemID .. "_" .. auctionID
        else
            RaidTrack.AddDebugMessage("Error: itemID is nil for item at index " .. tostring(idx))
            return
        end

        -- Dodanie odpowiedzi graczy (responses) do danych
        if item.responses then
            for player, response in pairs(item.responses) do
                -- Dodanie danych o EP, GP, PR dla gracza do odpowiedzi
                local ep, gp, pr = RaidTrack.GetEPGP(player)
                response.ep = ep
                response.gp = gp
                response.pr = pr
            end
        end
    end

    local fullPayload = {
        auctionID = auctionID,
        type = "auction",
        payload = payloadTable, -- Dodajemy tabelę przedmiotów z odpowiedziami
        subtype = messageType -- Typ wiadomości (np. "item" lub "response")
    }

    -- Serializowanie całości na końcu
    local serialized = RaidTrack.SafeSerialize(fullPayload)

    -- Wywołanie funkcji wysyłania chunków
    RaidTrack.QueueAuctionBroadcastSend("auction", serialized)

end

function RaidTrack.ReceiveAuctionChunked(sender, rawData)
    if rawData:sub(1, 8) == "RTCHUNK^" then

        return
    end

    -- 1. Deserializacja danych
    local ok, data = RaidTrack.SafeDeserialize(rawData)
    if not ok then

        return
    end

    if data.type ~= "auction" then

        return
    end

    RaidTrack.pendingAuctionItems = RaidTrack.pendingAuctionItems or {}
    RaidTrack.pendingAuctionItems[data.auctionID] = RaidTrack.pendingAuctionItems[data.auctionID] or {}

    if data.subtype == "item" then
        local itemData = data.payload
        if itemData and itemData.itemID then

            local itemExists = false
            for _, item in ipairs(RaidTrack.pendingAuctionItems[data.auctionID]) do
                if item.itemID == itemData.itemID then
                    itemExists = true
                    break
                end
            end

            if not itemExists then
                local uniqueItemID = tostring(itemData.itemID) .. "_" .. data.auctionID

                table.insert(RaidTrack.pendingAuctionItems[data.auctionID], {
                    itemID = itemData.itemID,
                    uniqueItemID = uniqueItemID,
                    gp = itemData.gp,
                    responses = {}
                })
            else
                RaidTrack.AddDebugMessage("Item with itemID=" .. tostring(itemData.itemID) ..
                                              " already exists, skipping.")
            end
        else
            RaidTrack.AddDebugMessage("Invalid auction item data!")
        end

    elseif data.subtype == "header" then
        local headerData = data.payload
        if headerData then
            local items = RaidTrack.pendingAuctionItems[data.auctionID] or {}

            -- 🧠 Tylko lider odpala okno lidera
            if UnitIsUnit(headerData.leader, "player") then
                RaidTrack:OpenAuctionLeaderUI()
            end

            -- Otwórz okno uczestnika aukcji
            -- Sprawdzenie czy gracz jest w GILDII i w RAIDZIE
            if IsInRaid() and IsInGuild() then
                RaidTrack.OpenAuctionParticipantUI({
                    auctionID = data.auctionID,
                    leader = headerData.leader,
                    started = headerData.started,
                    endsAt = headerData.endsAt,
                    duration = headerData.duration,
                    items = items
                })
            else
                RaidTrack.AddDebugMessage("Blocked auction popup (not in raid or not in guild)")
            end

            -- Przenieś do activeAuctions
            RaidTrack.activeAuctions = RaidTrack.activeAuctions or {}
            RaidTrack.activeAuctions[data.auctionID] = {
                items = items,
                leader = headerData.leader,
                started = headerData.started,
                endsAt = headerData.endsAt,
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

-- Funkcja do rejestrowania odpowiedzi
function RaidTrack.HandleAuctionResponse(auctionID, responseData)
    -- Typowe zabezpieczenie
    if type(auctionID) ~= "string" and type(auctionID) ~= "number" then
        RaidTrack.AddDebugMessage("ERROR: Invalid auctionID in responseData (type=" .. type(auctionID) .. ")")
        return
    end

    if not responseData or not responseData.itemID or not responseData.from or not responseData.choice then
        RaidTrack.AddDebugMessage("ERROR: Incomplete responseData")
        return
    end

    auctionID = tostring(auctionID) -- zawsze string, bo klucze w activeAuctions są stringami

    local auctionData = RaidTrack.activeAuctions and RaidTrack.activeAuctions[auctionID]
    local auctionItems = auctionData and auctionData.items

    if not auctionItems then
        RaidTrack.AddDebugMessage("ERROR: No auction items found for auctionID " .. auctionID)
        return
    end

    local matched = false

    for _, item in ipairs(auctionItems) do
        local itemID = tonumber(item.itemID)
        local responseItemID = tonumber(responseData.itemID)

        if itemID == responseItemID then
            matched = true

            if not item.bids then
                item.bids = {}

            end

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

            elseif responseData.choice == "PASS" then

            end

            if responseData.from == auctionData.leader then

                RaidTrack.UpdateLeaderAuctionUI(auctionID, item)
            end

            RaidTrack.UpdateLeaderAuctionUI(auctionID)

            RaidTrack.DebugPrintResponses(item)

            break
        else
            RaidTrack.AddDebugMessage("ItemID " .. tostring(itemID) .. " does not match response itemID " ..
                                          tostring(responseItemID))
        end
    end

    if matched then
        if RaidTrack.RefreshAuctionLeaderTabs then
            RaidTrack.RefreshAuctionLeaderTabs()
        end

    else
        RaidTrack.AddDebugMessage("WARNING: No matching item found for response itemID " ..
                                      tostring(responseData.itemID))
    end
end

-- Funkcja obsługująca odebrane chunki RAID SYNC
-- Odbiór chunków: NOWY (z msgId) i LEGACY (bez msgId)
function RaidTrack.HandleChunkedRaidPiece(sender, message)
    if type(message) ~= "string" or message:sub(1, 8) ~= "RTCHUNK^" then
        return
    end
    -- Legacy nagłówek: RTCHUNK^<idx>^<total>^<chunkData>
    local idx, total, chunkData = message:match("^RTCHUNK%^(%d+)%^(%d+)%^(.+)$")
    if not idx or not total or not chunkData then
        return
    end
    idx = tonumber(idx)
    total = tonumber(total)

    sender = (sender and sender ~= "") and sender or "UNKNOWN"
    RaidTrack._chunkBuffers = RaidTrack._chunkBuffers or {}
    local key = sender .. "_RTSYNC"
    if idx == 1 or type(RaidTrack._chunkBuffers[key]) ~= "table" then
        RaidTrack._chunkBuffers[key] = {}
    end
    local buf = RaidTrack._chunkBuffers[key]
    buf[idx] = chunkData

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
            RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from " .. tostring(sender))
        end
        return
    end

    -- Bezpiecznik: nie aktywuj raidu osobom spoza raid group
    if data.activeID and not IsInRaid() then
        data.activeID, data.activePreset, data.activeConfig = nil, nil, nil
    end

    if RaidTrack.ApplyRaidSyncData then
        RaidTrack.ApplyRaidSyncData(data, sender)
    elseif RaidTrack.MergeRaidSyncData then
        RaidTrack.MergeRaidSyncData(data, sender)
    end
end

function RaidTrack.HandleChunkedAuctionPiece(sender, msg)

    if not sender or sender == "" then
        sender = UnitName("player") -- nadawca lokalny
    end

    -- Próba dopasowania chunku
    local index, total, chunk = msg:match("^RTCHUNK%^(%d+)%^(%d+)%^(.+)$")
    if not index or not total or not chunk then

        return
    end

    index = tonumber(index)
    total = tonumber(total)
    if not index or not total then
        RaidTrack.AddDebugMessage("Error: invalid index or total.")
        return
    end

    -- Inicjalizacja bufora chunków
    RaidTrack._auctionChunks = RaidTrack._auctionChunks or {}
    RaidTrack._auctionChunks[sender] = RaidTrack._auctionChunks[sender] or {}
    local list = RaidTrack._auctionChunks[sender]

    -- Przechowywanie chunku
    list[index] = chunk

    -- Sprawdzamy, czy otrzymaliśmy wszystkie części
    for i = 1, total do
        if not list[i] then
            return -- Czekamy na brakujące części
        end
    end

    -- Łączymy wszystkie części
    local fullData = table.concat(list, "")
    RaidTrack._auctionChunks[sender] = nil

    -- Deserializujemy pełne dane
    RaidTrack.ReceiveAuctionChunked(sender, fullData)
end

