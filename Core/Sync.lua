-- Core/Sync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local CHUNK_SIZE = 200
local SEND_DELAY = 0.25
local SYNC_PREFIX = "RaidTrackSync"

C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix("auction")

RaidTrack.pendingSends = {}
RaidTrack.chunkBuffer = {}
RaidTrack.syncTimer = nil

function RaidTrack.ScheduleSync()
    RaidTrack.AddDebugMessage("ScheduleSync() called")
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
    if not IsInGuild() then
        return
    end
    local me = UnitName("player")
    local epID = RaidTrackDB.epgpLog and RaidTrackDB.epgpLog.lastId or 0
    local lootID = 0
    for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
        if e.id and e.id > lootID then
            lootID = e.id
        end
    end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if name ~= me and online then
            local msg = string.format("REQ_SYNC|%d|%d", epID, lootID)
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, msg, "WHISPER", name)
        end
    end
end

function RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
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
        if maxEP == 0 and maxLoot == 0 then
            return
        end

        payload = {
            full = {
                epgp = RaidTrackDB.epgp,
                loot = RaidTrackDB.lootHistory,
                epgpLog = RaidTrackDB.epgpLog.changes,
                settings = RaidTrackDB.settings or {}
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
            lootDelta = lootDelta
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
        RaidTrack.AddDebugMessage("Sent settings to " .. name .. " with sync data.")
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
        RaidTrack.AddDebugMessage("Empty sync completed with " .. name)
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

function RaidTrack.BroadcastSettings()
    if not RaidTrack.IsOfficer() then
        return
    end
    local payload = {
        settings = {
            minSyncRank = RaidTrackDB.settings.minSyncRank,
            officerOnly = RaidTrackDB.settings.officerOnly,
            autoSync = RaidTrackDB.settings.autoSync
        }
    }
    local msg = RaidTrack.SafeSerialize(payload)
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "CFG|" .. msg, "GUILD")
end

local mf = CreateFrame("Frame")
mf:RegisterEvent("CHAT_MSG_ADDON")
mf:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    -- 🧩 Chunkowany odbiór aukcji
    if prefix == "auction" and sender ~= UnitName("player") then
        if msg:sub(1, 8) == "RTCHUNK^" then
            RaidTrack.HandleChunkedAuctionPiece(sender, msg)
        else
            RaidTrack.AddDebugMessage("Ignored non-chunked auction message: " .. msg)
        end
        return
    end

    -- 🔹 Dalej tylko jeśli to standardowy sync
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then
        return
    end
    local who = Ambiguate(sender, "none")

    -- 🔽 Obsługa starego systemu aukcyjnego (prefix RaidTrackSync)
    if msg:sub(1, 13) == "AUCTION_ITEM|" then
        local payload = msg:sub(14)
        RaidTrack.AddDebugMessage("Payload for AUCTION_ITEM: " .. payload)

        local ok, data = RaidTrack.SafeDeserialize(payload)
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

            RaidTrack.AddDebugMessage("Received AUCTION_ITEM for auctionID: " .. data.auctionID)
        else
            RaidTrack.AddDebugMessage("Failed to deserialize AUCTION_ITEM")
        end
        return
    end

    -- 🔽 (tu zostawiasz resztę: AUCTION_START|, PING, PONG, CFG, REQ_SYNC itd.)

    if msg:sub(1, 14) == "AUCTION_START|" then
        local payload = msg:sub(15)

        -- Logowanie przed deserializacją
        RaidTrack.AddDebugMessage("Payload for AUCTION_START: " .. payload)

        local ok, data = RaidTrack.SafeDeserialize(payload)

        -- Logowanie wyników deserializacji
        RaidTrack.AddDebugMessage("Payload ok: " .. tostring(ok))
        RaidTrack.AddDebugMessage("Data type: " .. type(data))

        if ok and data and data.auctionID then
            C_Timer.After(0.3, function()
                local auctionItems = RaidTrack.pendingAuctionItems and RaidTrack.pendingAuctionItems[data.auctionID] or
                                         {}
                data.items = auctionItems
                RaidTrack.ReceiveAuctionHeader(data)
                RaidTrack.pendingAuctionItems[data.auctionID] = nil
            end)
        else
            RaidTrack.AddDebugMessage("RaidTrack: Received invalid auction data from leader.")
        end
        return
    end

    if msg == "PING" then
        RaidTrack.AddDebugMessage("Received PING from " .. who)
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "PONG", "WHISPER", who)
        return
    elseif msg == "PONG" and RaidTrack.pendingSends[who] then
        RaidTrack.pendingSends[who].gotPong = true
        RaidTrack.SendChunkBatch(who)
        return
    elseif msg == "PONG" then
        RaidTrack.AddDebugMessage("Received PONG from " .. who)
        -- No data was pending, but PONG received -> treat as noop sync
        RaidTrack.lastSyncTime = time()
        RaidTrack.AddDebugMessage("Sync with " .. who .. " completed (no data).")
        return
    elseif msg:sub(1, 9) == "REQ_SYNC|" then
        local _, epStr, lootStr = strsplit("|", msg)
        local knownEP = tonumber(epStr) or 0
        local knownLoot = tonumber(lootStr) or 0
        RaidTrack.SendSyncDataTo(who, knownEP, knownLoot)
        return
    elseif msg:sub(1, 4) == "ACK|" then
        local idx = tonumber(msg:sub(5))
        local p = RaidTrack.pendingSends[who]
        if p and p.chunks[idx] then
            p.chunks[idx] = nil
        end
        return
    elseif msg:sub(1, 4) == "CFG|" then
        local cfgStr = msg:sub(5)
        local ok, data = RaidTrack.SafeDeserialize(cfgStr)
        if ok and data and data.settings then
            for k, v in pairs(data.settings) do
                if v ~= nil then
                    RaidTrackDB.settings[k] = v
                end
            end
            -- ⬇️ Dodaj to poniżej:
            if RaidTrack.UpdateSettingsTab then
                RaidTrack.UpdateSettingsTab()
            end
        end
        return
    end

    local i, t, d = msg:match("^(%d+)|(%d+)|(.+)$")
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
        buf.chunks[i] = d
        buf.received = buf.received + 1
    end
    if buf.received == buf.total then
        local full = table.concat(buf.chunks)
        RaidTrack.chunkBuffer[who] = nil
        local ok, data = RaidTrack.SafeDeserialize(full)
        if not ok then
            return
        end

        if data.full then
            RaidTrackDB.epgp = data.full.epgp or {}
            RaidTrackDB.lootHistory = data.full.loot or {}
            local maxLoot = 0
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > maxLoot then
                    maxLoot = e.id
                end
            end
            if data.full.settings then
                for k, v in pairs(data.full.settings) do
                    RaidTrackDB.settings[k] = v
                end
            end
            RaidTrackDB.epgpLog = {
                changes = data.full.epgpLog or {},
                lastId = (data.full.epgpLog[#data.full.epgpLog] and data.full.epgpLog[#data.full.epgpLog].id) or 0
            }
            local lastEP = RaidTrackDB.epgpLog.lastId or 0
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
            RaidTrack.lastSyncTime = time()
            if lastEP == 0 or maxLoot == 0 then
                C_Timer.After(2, function()
                    RaidTrack.RequestSyncFromGuild()
                end)
            end
            return
        end

        RaidTrack.MergeEPGPChanges(data.epgpDelta)
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
        local seen = {}
        for _, e in ipairs(RaidTrackDB.lootHistory) do
            seen[e.id] = true
        end
        local mx = RaidTrackDB.lootSyncStates[who] or 0
        for _, e in ipairs(data.lootDelta or {}) do
            if e.id and not seen[e.id] then
                table.insert(RaidTrackDB.lootHistory, e)
                seen[e.id] = true
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
    end
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

-- Jeśli masz funkcję zadeklarowaną bezpośrednio:
-- function RaidTrack.SendSyncData() ... end
-- to nic nie rób – już działa.

-- Ale jeśli nie masz jej wcale (a była wcześniej), dodaj ją z powrotem:

function RaidTrack.QueueChunkedSend(target, prefix, data)
    local chunks = {}
    local maxSize = 200 -- bezpieczny limit

    for i = 1, #data, maxSize do
        table.insert(chunks, data:sub(i, i + maxSize - 1))
    end

    for i, chunk in ipairs(chunks) do
        local marker = "RTCHUNK^" .. i .. "^" .. #chunks .. "^" .. chunk
        local channel = IsInRaid() and "RAID" or "GUILD"
        C_ChatInfo.SendAddonMessage(prefix, marker, channel, target or "")
    end
end

function RaidTrack.QueueAuctionChunkedSend(target, auctionID, messageType, input)
    local payloadTable
    if type(input) == "table" then
        payloadTable = input
    else
        error("QueueAuctionChunkedSend: input must be a table")
    end

    local fullPayload = {
        auctionID = auctionID,
        type = "auction",
        payload = payloadTable, -- <-- NIE SERIALIZUJ TUTAJ
        subtype = messageType
    }

    -- Serializujemy dopiero całość na końcu
    local serialized = RaidTrack.SafeSerialize(fullPayload)

    RaidTrack.AddDebugMessage("Sending auction data for auctionID: " .. auctionID)
    RaidTrack.AddDebugMessage("Subtype: " .. tostring(messageType))
    RaidTrack.AddDebugMessage("Serialized auction data: " .. tostring(serialized))

    RaidTrack.QueueChunkedSend(target, "auction", serialized)
end

function RaidTrack.SendSyncData()
    if RaidTrack.HandleSendSync then
        RaidTrack.HandleSendSync()
    else
        RaidTrack.AddDebugMessage("SendSyncData: Sync system not initialized")
    end
end

function RaidTrack.HandleSendSync()
    RaidTrack.SendSyncDeltaToEligible()
end

function RaidTrack.ReceiveAuctionChunked(sender, rawData)
    if rawData:sub(1, 8) == "RTCHUNK^" then
        RaidTrack.AddDebugMessage("ERROR: ReceiveAuctionChunked received raw RTCHUNK!")
        return
    end
    RaidTrack.AddDebugMessage("Raw auction chunk from " .. sender .. ": " .. tostring(rawData))

    -- 1. Deserializacja warstwy zewnętrznej
    local ok, data = RaidTrack.SafeDeserialize(rawData)

    -- Zabezpieczenie przed duplikatami z innych uczestników
    RaidTrack._receivedAuctions = RaidTrack._receivedAuctions or {}
    RaidTrack._receivedAuctionCounters = RaidTrack._receivedAuctionCounters or {}

    -- Inicjalizuj licznik dla tego typu
    RaidTrack._receivedAuctionCounters[data.auctionID] = RaidTrack._receivedAuctionCounters[data.auctionID] or {}
    local counter = RaidTrack._receivedAuctionCounters[data.auctionID]

    -- Unikalny klucz z licznikiem
    counter[data.subtype] = (counter[data.subtype] or 0) + 1
    local chunkKey = tostring(data.auctionID) .. "::" .. tostring(data.subtype) .. "::" .. tostring(counter[data.subtype])

    -- Zabezpieczenie przed kompletnymi duplikatami (na wypadek resendów)
    if RaidTrack._receivedAuctions[chunkKey] then
        RaidTrack.AddDebugMessage("Duplicate auction chunk received: " .. chunkKey)
        return
    end
    RaidTrack._receivedAuctions[chunkKey] = true

    if not ok then
        RaidTrack.AddDebugMessage("Failed to deserialize auction chunk!")
        return
    end

    -- Debug: logujemy co przyszło w chunku
    RaidTrack.AddDebugMessage("ReceiveAuctionChunked: subtype=" .. tostring(data.subtype) .. ", auctionID=" .. tostring(data.auctionID))

    -- Awaryjnie: jeśli nie ma subtype, nie przetwarzaj dalej
    if not data.subtype then
        RaidTrack.AddDebugMessage("ReceiveAuctionChunked: missing subtype! Dumping rawData:")
        RaidTrack.AddDebugMessage(tostring(rawData))
        return
    end

    -- 2. Sprawdzenie typu i subtype
    if data.type ~= "auction" then
        RaidTrack.AddDebugMessage("Invalid chunk type: " .. tostring(data.type))
        return
    end

    local auctionID = data.auctionID
    if not auctionID then
        RaidTrack.AddDebugMessage("Missing auctionID in chunk")
        return
    end

    -- 3. Inicjalizacja item buffer
    RaidTrack.pendingAuctionItems = RaidTrack.pendingAuctionItems or {}
    RaidTrack.pendingAuctionItems[auctionID] = RaidTrack.pendingAuctionItems[auctionID] or {}

    -- Zmienna globalna do śledzenia już wysłanych przedmiotów w aukcji
    RaidTrack.auctionSeenItems = RaidTrack.auctionSeenItems or {}

    -- 4. Obsługa itemów
    if data.subtype == "item" then
        -- Tworzymy tabelę, jeśli jej nie ma
        RaidTrack.pendingAuctionItems[auctionID] = RaidTrack.pendingAuctionItems[auctionID] or {}

        -- Wczytujemy dane przedmiotu
        local itemData = data.payload -- NIE deserialize — już zostało!
        if itemData and itemData.itemID then
            -- Unikalny identyfikator przedmiotu w tej aukcji
            local uniqueItemID = tostring(itemData.itemID) .. "_" .. (#RaidTrack.pendingAuctionItems[auctionID] + 1)

            -- Zabezpieczenie przed dodaniem duplikatów
            if RaidTrack.auctionSeenItems[uniqueItemID] then
                RaidTrack.AddDebugMessage("Duplicate item detected, skipping itemID: " .. itemData.itemID)
                return
            end

            -- Zapisz ten przedmiot, aby uniknąć duplikacji
            RaidTrack.auctionSeenItems[uniqueItemID] = true

            -- Dodajemy przedmiot do aukcji
            table.insert(RaidTrack.pendingAuctionItems[auctionID], {
                itemID = itemData.itemID,
                uniqueItemID = uniqueItemID, -- Dodajemy unikalny identyfikator
                gp = itemData.gp,
                link = select(2, GetItemInfo(itemData.itemID)) or "item:" .. itemData.itemID,
                responses = {}
            })
            RaidTrack.AddDebugMessage("Added auction item: " .. uniqueItemID)
        else
            RaidTrack.AddDebugMessage("Invalid auction item data!")
        end

    elseif data.subtype == "header" then
        local headerData = data.payload
        if headerData then
            local tries = 0
            local maxTries = 10

            local function tryOpenUI()
                tries = tries + 1
                local items = RaidTrack.pendingAuctionItems and RaidTrack.pendingAuctionItems[auctionID] or {}

                if type(items) == "table" and #items > 0 then
                    RaidTrack.AddDebugMessage("Header received. Items: " .. tostring(#items))
                    RaidTrack.AddDebugMessage("First itemID: " .. tostring(items[1].itemID))
                    RaidTrack.AddDebugMessage("Opening Auction UI for auctionID: " .. tostring(auctionID))

                    RaidTrack.OpenAuctionParticipantUI({
                        auctionID = auctionID,
                        leader = headerData.leader,
                        started = headerData.started,
                        duration = headerData.duration,
                        items = items
                    })

                    RaidTrack.pendingAuctionItems[auctionID] = nil
                elseif tries < maxTries then
                    C_Timer.After(0.5, tryOpenUI)
                else
                    RaidTrack.AddDebugMessage("Header received, but no items found after retries. AuctionID: " .. tostring(auctionID))
                    RaidTrack.pendingAuctionItems[auctionID] = nil
                end
            end

            tryOpenUI()
        else
            RaidTrack.AddDebugMessage("Invalid auction header data!")
        end
    end
end


function RaidTrack.HandleChunkedAuctionPiece(sender, msg)
    -- DEBUG: surowy chunk
    RaidTrack.AddDebugMessage("Raw auction chunk from: " .. msg)

    local index, total, chunk = msg:match("^RTCHUNK%^(%d+)%^(%d+)%^(.+)$")
    if not index or not total or not chunk then
        RaidTrack.AddDebugMessage("Invalid auction chunk format.")
        return
    end

    index = tonumber(index)
    total = tonumber(total)
    if not index or not total then
        return
    end

    RaidTrack._auctionChunks = RaidTrack._auctionChunks or {}
    RaidTrack._auctionChunks[sender] = RaidTrack._auctionChunks[sender] or {}
    local list = RaidTrack._auctionChunks[sender]

    list[index] = chunk

    -- DEBUG
    RaidTrack.AddDebugMessage("Received auction chunk " .. index .. "/" .. total .. " from " .. sender)

    -- Czy wszystko już mamy?
    for i = 1, total do
        if not list[i] then
            return -- jeszcze niekompletne
        end
    end

    -- Składamy dane
    local fullData = table.concat(list, "")
    RaidTrack._auctionChunks[sender] = nil
    RaidTrack.AddDebugMessage("All auction chunks received from " .. sender)

    -- Teraz dopiero deserializujemy
    RaidTrack.ReceiveAuctionChunked(sender, fullData)
end

