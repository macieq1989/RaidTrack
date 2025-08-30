-- Core/Auction.lua
local addonName, RaidTrack = ...
RaidTrack.auction = RaidTrack.auction or {}
RaidTrack.pendingAuctionItems = RaidTrack.pendingAuctionItems or {}

-- Aktywna aukcja (po stronie lidera)
local activeAuction = nil

-- === Pomocnicze ===
local function _baseLink(itemID)
    local link = select(2, GetItemInfo(itemID))
    return link or ("item:" .. tostring(itemID))
end

local function _isLeadOrAssist()
    return RaidTrack.IsRaidLeadOrAssist and RaidTrack.IsRaidLeadOrAssist()
end

-- === Start aukcji (lider/assistant) ===
function RaidTrack.StartAuction(items, duration)
    if not _isLeadOrAssist() then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Only raid leader/assist can start auctions.") end
        return
    end
    if activeAuction then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Auction already in progress.") end
        return
    end

    local serverNow = GetServerTime()
    local dur = tonumber(duration) or 30
    if dur <= 0 then dur = 30 end

    -- uniknij kolizji ID (ta sama sekunda)
    local auctionID = tostring(serverNow) .. tostring(math.random(1000, 9999))
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Generated auction ID: " .. auctionID) end

    activeAuction = {
        auctionID = auctionID,
        items     = {},
        leader    = UnitName("player"),
        started   = serverNow,
        endsAt    = serverNow + dur,
        duration  = dur,
    }

    RaidTrack.activeAuctions = RaidTrack.activeAuctions or {}
    RaidTrack.activeAuctions[auctionID] = {
        items    = {},
        leader   = activeAuction.leader,
        started  = activeAuction.started,
        endsAt   = activeAuction.endsAt,
        duration = activeAuction.duration,
    }

    -- Wyślij każdy item (NEW: prefix "auction" + RTCHUNK; QUEUE robi też legacy mirror AUCTION_ITEM|)
    for _, it in ipairs(items or {}) do
        local itemID = tonumber(it.itemID)
        local gp     = tonumber(it.gp) or 0
        if itemID then
            local entry = {
                itemID    = itemID,
                gp        = gp,
                link      = _baseLink(itemID),
                responses = {},
            }
            table.insert(activeAuction.items, entry)
            table.insert(RaidTrack.activeAuctions[auctionID].items, entry)

            RaidTrack.QueueAuctionChunkedSend(nil, auctionID, "item", {
                itemID = itemID,
                gp     = gp,
                link   = entry.link,
            })
        end
    end

    -- NAGŁÓWEK (NEW + legacy AUCTION_START|) – ważne: używamy endsAt (server epoch)
    RaidTrack.QueueAuctionChunkedSend(nil, auctionID, "header", {
        leader   = activeAuction.leader,
        started  = activeAuction.started,
        endsAt   = activeAuction.endsAt,
        duration = activeAuction.duration,
    })

    -- Lokalne otwarcie UI u lidera
    C_Timer.After(0.2, function()
        if RaidTrack.OpenAuctionParticipantUI then
            RaidTrack.OpenAuctionParticipantUI({
                auctionID = auctionID,
                leader    = activeAuction.leader,
                started   = activeAuction.started,
                endsAt    = activeAuction.endsAt,
                duration  = activeAuction.duration,
                items     = activeAuction.items,
            })
        end
    end)

    -- Planowane zakończenie
    C_Timer.After(dur, function()
        if RaidTrack.EndAuction then RaidTrack.EndAuction() end
    end)
end

-- === Zakończenie aukcji (lider) ===
function RaidTrack.EndAuction()
    if not activeAuction then return end

    if RaidTrack.AddDebugMessage then
        for _, item in ipairs(activeAuction.items or {}) do
            RaidTrack.AddDebugMessage("Auction ended for item: " .. (item.link or ("item:" .. tostring(item.itemID))))
        end
        RaidTrack.AddDebugMessage("Auction Results:")
        for _, item in ipairs(activeAuction.items or {}) do
            RaidTrack.AddDebugMessage("Item: " .. (item.link or ("item:" .. tostring(item.itemID))))
            if item.bids then
                for _, bid in ipairs(item.bids) do
                    RaidTrack.AddDebugMessage(("  - %s: %s"):format(tostring(bid.from), tostring(bid.choice)))
                end
            end
        end
    end

    activeAuction = nil
end

-- === Odpowiedź uczestnika ===
-- Zakładamy, że UI woła to z prawidłowym auctionID i ma wybrany item.
function RaidTrack.SendAuctionResponse(auctionID, responseType)
    local selectedItemID = RaidTrack.GetSelectedItemID and RaidTrack.GetSelectedItemID()
    if not selectedItemID then
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("SendAuctionResponse: no selected item in UI") end
        return
    end

    local resp = {
        from   = UnitName("player"),
        itemID = tonumber(selectedItemID),
        choice = tostring(responseType or "PASS"),
    }

    -- ważne: input to TABELA (QueueAuctionChunkedSend zrobi serializację)
    RaidTrack.QueueAuctionChunkedSend(nil, tostring(auctionID), "response", resp)

    -- opcjonalnie – lokalny podgląd
    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(("Sent response: auc=%s item=%s from=%s choice=%s")
            :format(tostring(auctionID), tostring(resp.itemID), resp.from, resp.choice))
    end
end

-- === Legacy helpers używane przez Sync.lua (AUCTION_ITEM| / AUCTION_START| ścieżka) ===
RaidTrack.partialAuction = RaidTrack.partialAuction or {}

function RaidTrack.ReceiveAuctionItem(data)
    -- data = { auctionID=..., item = { itemID=..., gp=..., link=... } }
    if not data or not data.auctionID or not data.item or not data.item.itemID then return end
    local auctionID = tostring(data.auctionID)
    local it        = data.item

    RaidTrack.pendingAuctionItems[auctionID] = RaidTrack.pendingAuctionItems[auctionID] or {}

    -- uniknij duplikatów
    for _, ex in ipairs(RaidTrack.pendingAuctionItems[auctionID]) do
        if tonumber(ex.itemID) == tonumber(it.itemID) then return end
    end

    local link = it.link or _baseLink(it.itemID)
    table.insert(RaidTrack.pendingAuctionItems[auctionID], {
        itemID    = tonumber(it.itemID),
        gp        = tonumber(it.gp) or 0,
        link      = link,
        responses = {},
    })
end

-- flagi anty-duplikacji
RaidTrack._auctionUIsOpen = RaidTrack._auctionUIsOpen or {}
RaidTrack._auctionHeaderScheduled = RaidTrack._auctionHeaderScheduled or {}

function RaidTrack.ReceiveAuctionHeader(data)
    -- data = { auctionID, leader, started, duration, endsAt }
    local auctionID = data and data.auctionID and tostring(data.auctionID)
    if not auctionID then return end

    -- jeśli już otwarte – nic nie rób
    if RaidTrack._auctionUIsOpen[auctionID] then return end

    RaidTrack.partialAuction = RaidTrack.partialAuction or {}
    RaidTrack.partialAuction[auctionID] = RaidTrack.partialAuction[auctionID] or { items = {} }
    local entry = RaidTrack.partialAuction[auctionID]

    entry.leader   = data.leader
    entry.started  = tonumber(data.started)  or GetServerTime()
    entry.duration = tonumber(data.duration) or 30
    entry.endsAt   = tonumber(data.endsAt)   or (entry.started + entry.duration)

    -- harmonogram pokazania UI: pozwól zarejestrować TYLKO jeden harmonogram
    if RaidTrack._auctionHeaderScheduled[auctionID] then
        return
    end
    RaidTrack._auctionHeaderScheduled[auctionID] = true

    local tries, maxTries = 0, 12 -- ~6s czekania na itemy
    local function tryOpen()
        if RaidTrack._auctionUIsOpen[auctionID] then
            RaidTrack._auctionHeaderScheduled[auctionID] = nil
            return
        end
        tries = tries + 1
        local items = RaidTrack.pendingAuctionItems and RaidTrack.pendingAuctionItems[auctionID]
        if items and #items > 0 then
            if RaidTrack.OpenAuctionParticipantUI then
                RaidTrack.OpenAuctionParticipantUI({
                    auctionID = auctionID,
                    leader    = entry.leader,
                    started   = entry.started,
                    endsAt    = entry.endsAt,
                    duration  = entry.duration,
                    items     = items,
                })
            end
            RaidTrack._auctionUIsOpen[auctionID] = true
            RaidTrack._auctionHeaderScheduled[auctionID] = nil
            RaidTrack.partialAuction[auctionID] = nil
            return
        end
        if tries < maxTries then
            C_Timer.After(0.5, tryOpen)
        else
            if RaidTrack.AddDebugMessage then
                RaidTrack.AddDebugMessage("No items received for auction " .. auctionID .. " after waiting.")
            end
            RaidTrack._auctionHeaderScheduled[auctionID] = nil
            RaidTrack.partialAuction[auctionID] = nil
        end
    end

    tryOpen()
end

