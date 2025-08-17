-- Core/Auction.lua
local addonName, RaidTrack = ...
RaidTrack.auction = RaidTrack.auction or {}
RaidTrack.pendingAuctionItems = RaidTrack.pendingAuctionItems or {}

local SYNC_PREFIX = "RaidTrackAuction"

local activeAuction = nil
local auctionResponses = {}

-- Auction Types
local AUCTION_TYPES = {
    MAIN_SPEC = "MS",
    OFF_SPEC = "OS",
    TRANSMOG = "TM",
    PASS = "PASS"
}

-- Start an auction (only leader/officer)
-- Funkcja wysyłająca dane aukcji
-- Wysyłanie danych aukcji
-- Start an auction (only leader/officer)
function RaidTrack.StartAuction(items, duration)
    if not RaidTrack.IsRaidLeadOrAssist or not RaidTrack.IsRaidLeadOrAssist() then
        RaidTrack.AddDebugMessage("Only raid leader/assist can start auctions.")
        return
    end

    if activeAuction then
        RaidTrack.AddDebugMessage("Auction already in progress.")
        return
    end

    local serverNow = GetServerTime()
    local endsAt = serverNow + (tonumber(duration) or 0)
    local auctionID = tostring(serverNow) -- stabilniejsze niż local time() przy odpaleniu wielu jednocześnie
    RaidTrack.AddDebugMessage("Generated auction ID: " .. auctionID)

    activeAuction = {
        auctionID = auctionID,
        items = {},
        leader = UnitName("player"),
        started = serverNow,   -- server epoch
        endsAt  = endsAt,      -- KLUCZ: absolutny czas końca wg serwera
        duration = duration
    }

    RaidTrack.auctionsByID = RaidTrack.auctionsByID or {}
    RaidTrack.auctionsByID[auctionID] = activeAuction

    RaidTrack.activeAuctions = RaidTrack.activeAuctions or {}
    RaidTrack.activeAuctions[auctionID] = {
        items = {},
        leader = UnitName("player"),
        started = serverNow,
        endsAt  = endsAt,
        duration = duration
    }

    for _, item in ipairs(items) do
        if item.itemID and item.gp then
            local duplicate = false
            for _, existingItem in ipairs(activeAuction.items) do
                if existingItem.itemID == item.itemID then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                local itemEntry = {
                    itemID = item.itemID,
                    gp = item.gp,
                    link = select(2, GetItemInfo(item.itemID)) or ("item:" .. item.itemID),
                    responses = {}
                }
                table.insert(activeAuction.items, itemEntry)
                table.insert(RaidTrack.activeAuctions[auctionID].items, itemEntry)

                -- item chunk bez zmian (opcjonalnie możesz dodać endsAt, ale nagłówek i tak niesie endsAt)
                RaidTrack.QueueAuctionChunkedSend(nil, auctionID, "item", {
                    auctionID = auctionID,
                    itemID = item.itemID,
                    gp = item.gp,
                    epgpChanges = {}
                })
            end
        end
    end

    -- NAGŁÓWEK: wysyłamy endsAt (server epoch)
    RaidTrack.QueueAuctionChunkedSend(nil, auctionID, "header", {
        leader  = UnitName("player"),
        started = serverNow,
        endsAt  = endsAt,
        duration = duration
    })

    -- Otwórz UI także u lidera (lokalnie), używaj endsAt
    C_Timer.After(0.2, function()
        RaidTrack.OpenAuctionParticipantUI({
            auctionID = auctionID,
            leader = UnitName("player"),
            started = serverNow,
            endsAt  = endsAt,
            duration = duration,
            items = activeAuction.items
        })
    end)

    -- Harmonogram końca według duration (lokalnie u lidera i tak kończymy o czasie)
    C_Timer.After(duration, function()
        RaidTrack.EndAuction()
    end)

    C_Timer.After(duration + 1, function()
        local epgpChanges = {}
        RaidTrack.SendEPGPChanges(epgpChanges)
    end)
end



function RaidTrack.SendEPGPChanges(changes)
    -- Zapewnienie, że changes to tabela
    if type(changes) ~= "table" then
        RaidTrack.AddDebugMessage("SendEPGPChanges: changes is not a table! (" .. tostring(changes) .. ")")
        return
    end

    -- Logowanie przed wysyłką
    RaidTrack.AddDebugMessage("Sending EPGP changes:")
    for _, change in ipairs(changes) do
        RaidTrack.AddDebugMessage("  Player: " .. tostring(change.player) .. ", ItemID: " .. tostring(change.itemID) ..
                                      ", GP: " .. tostring(change.gp) .. ", Choice: " .. tostring(change.choice))
    end

    -- Serializowanie danych
    local payload = RaidTrack.SafeSerialize({
        epgpChanges = changes
    })

    
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, payload, "GUILD")
end

RaidTrack.partialAuction = RaidTrack.partialAuction or {}

function RaidTrack.ReceiveAuctionItem(data)
    if not data.auctionID or not data.item or not data.item.itemID then
        return
    end

    local auctionID = data.auctionID
    local itemData = data.item
    RaidTrack.pendingAuctionItems[auctionID] = RaidTrack.pendingAuctionItems[auctionID] or {}

    local function TryInsertItem(attemptsLeft)
        for _, existingItem in ipairs(RaidTrack.pendingAuctionItems[auctionID]) do
            if existingItem.itemID == itemData.itemID then
                RaidTrack.AddDebugMessage("Duplikat przedmiotu, pomijam: itemID=" .. tostring(itemData.itemID))
                return
            end
        end

        -- Próba pobrania informacji o przedmiocie
        local itemName, itemLink = GetItemInfo(itemData.itemID)
        if itemLink then
            -- Dodajemy przedmiot do listy aukcji, jeśli link został rozwiązany
            table.insert(RaidTrack.pendingAuctionItems[auctionID], {
                itemID = itemData.itemID,
                gp = itemData.gp,
                link = itemLink,
                responses = {}
            })
           
        elseif attemptsLeft > 0 then
            -- Jeśli link nie został rozwiązany, próbujemy ponownie po 0.5s
            C_Timer.After(0.5, function()
                TryInsertItem(attemptsLeft - 1)
            end)
        else
            -- Jeśli po próbach nadal nie udało się rozwiązać linku, logujemy błąd
            RaidTrack.AddDebugMessage("Nie udało się rozwiązać linku do przedmiotu o itemID " ..
                                          tostring(itemData.itemID))
        end
    end

    -- Uruchomienie funkcji z maksymalną liczbą prób
    TryInsertItem(5)
end

function RaidTrack.EndAuction()
    if not activeAuction then
        return
    end

    for _, item in ipairs(activeAuction.items) do
        RaidTrack.AddDebugMessage("Auction ended for item: " .. (item.link or "nil"))

    end

    RaidTrack.ShowAuctionResults()
    activeAuction = nil
    auctionResponses = {}
end

function RaidTrack.ShowAuctionResults()
    if not activeAuction then
        return
    end

    RaidTrack.AddDebugMessage("Auction Results:")
    for _, item in ipairs(activeAuction.items) do
        RaidTrack.AddDebugMessage("Item: " .. (item.link or ("item:" .. tostring(item.itemID))))
        for name, choice in pairs(item.responses or {}) do
            local responseText = string.format(" - %s: Response=%s, EP=%d, GP=%d, PR=%.2f", name,
                choice.response or "N/A", choice.ep or 0, choice.gp or 0, choice.pr or 0)
            RaidTrack.AddDebugMessage(responseText)
        end
    end
end

-- Event handler
local f = CreateFrame("Frame", nil, parent)
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then
        return
    end

    local ok, data = RaidTrack.SafeDeserialize(msg)
    if not ok then
        return
    end

    
    if data.response then
        RaidTrack.ReceiveAuctionResponse(data)
    end
end)

function RaidTrack.ReceiveAuctionResponse(data)
    -- Sprawdzamy, czy dane odpowiedzi są poprawne
    if not data.response or not data.response.from or not data.response.choice or not data.response.itemID then
        RaidTrack.AddDebugMessage("Invalid auction response received.")
        return
    end

    local player = data.response.from
    local choice = data.response.choice
    local itemID = tonumber(data.response.itemID)

    -- Jeśli nie ma aktywnej aukcji lub brak przedmiotów, kończymy
    if not activeAuction or not activeAuction.items then
        RaidTrack.AddDebugMessage("No active auction or items.")
        return
    end

    -- Przeszukujemy listę przedmiotów w aukcji
    for _, item in ipairs(activeAuction.items) do
        if item.itemID == itemID then
            -- Jeśli znaleziono item, zapisujemy odpowiedź gracza
            item.responses[player] = choice
            RaidTrack.AddDebugMessage("Received response from " .. player .. ": " .. choice .. " for itemID " .. itemID)

            -- **Wywołanie HandleAuctionResponse, aby przetworzyć odpowiedź**
            RaidTrack.HandleAuctionResponse(activeAuction.auctionID, item.link, player, choice)

            -- Teraz możemy dokonać zmiany EPGP po zakończeniu aukcji
            if choice == "MS" or choice == "OS" or choice == "TMOG" then
                local epgpChange = {
                    player = player,
                    itemID = itemID,
                    choice = choice,
                    gp = item.gp, -- Dodajemy cenę GP przedmiotu
                    epgpChanges = {} -- Będziemy tu wstawiać zmiany EPGP
                }

                -- Dodajemy zmiany EPGP do tabeli
                -- Na razie epgpChanges jest pustą tabelą, ale możesz wprowadzić konkretne zmiany w zależności od "choice"
                if choice == "MS" then
                    epgpChange.epgpChanges = {
                        ep = 10,
                        gp = item.gp
                    } -- Przykładowe zmiany dla Main Spec
                elseif choice == "OS" then
                    epgpChange.epgpChanges = {
                        ep = 5,
                        gp = item.gp
                    } -- Przykładowe zmiany dla Off Spec
                elseif choice == "TMOG" then
                    epgpChange.epgpChanges = {
                        ep = 0,
                        gp = item.gp
                    } -- Przykładowe zmiany dla Transmog
                end

                -- Wysyłamy zmiany EPGP
                RaidTrack.SendEPGPChanges({epgpChange})
            end
            return
        end
    end

    RaidTrack.AddDebugMessage("ItemID " .. tostring(itemID) .. " not found in active auction.")
end

function RaidTrack.ReceiveAuctionHeader(data)
    local auctionID = data.auctionID
    if not auctionID then
        return
    end

    RaidTrack.partialAuction = RaidTrack.partialAuction or {}
    RaidTrack.partialAuction[auctionID] = RaidTrack.partialAuction[auctionID] or {
        items = {}
    }

    local entry = RaidTrack.partialAuction[auctionID]
    entry.leader   = data.leader
    entry.started  = tonumber(data.started) or 0      -- może się przydać jako fallback
    entry.duration = tonumber(data.duration) or 0
    entry.endsAt   = tonumber(data.endsAt) or 0       -- KLUCZ: absolutny koniec wg serwera

    local attempt = 0
    local maxAttempts = 10

    local function tryShowAuction()
        attempt = attempt + 1
        local e = RaidTrack.partialAuction[auctionID]

        if e and type(e.items) == "table" and #e.items > 0 then
            RaidTrack.OpenAuctionParticipantUI({
                auctionID = auctionID,
                leader    = e.leader,
                started   = e.started,
                endsAt    = e.endsAt,      -- przekazujemy endsAt do UI
                duration  = e.duration,
                items     = e.items
            })
            RaidTrack.partialAuction[auctionID] = nil
        elseif attempt < maxAttempts then
            C_Timer.After(0.5, tryShowAuction)
        else
            RaidTrack.AddDebugMessage("No items received for auction " .. auctionID .. " after waiting.")
            RaidTrack.partialAuction[auctionID] = nil
        end
    end

    tryShowAuction()
end


function RaidTrack.SendAuctionResponse(auctionID, responseType)
    -- Pobieramy itemID z aktywnego okna aukcji (UI)
    local selectedItemID = RaidTrack.GetSelectedItemID()

    if not selectedItemID then
        RaidTrack.AddDebugMessage("Error: No item selected in the auction UI!")
        return
    end

    -- Zbieramy dane odpowiedzi
    local responseData = {
        auctionID = auctionID,
        itemID = selectedItemID, -- Używamy itemID z UI
        from = UnitName("player"),
        choice = responseType
    }

    -- Wysyłamy odpowiedź do lidera aukcji
    local payload = RaidTrack.SafeSerialize(responseData)
    RaidTrack.QueueAuctionChunkedSend(UnitName("player"), auctionID, "response", payload)
end

function RaidTrack.ReceiveAuctionBidChunked(data)
    if not data.auctionID or not data.itemID or not data.from or not data.choice then
        RaidTrack.AddDebugMessage("Invalid auction bid chunk received.")
        return
    end

    if not activeAuction or activeAuction.auctionID ~= data.auctionID then
        RaidTrack.AddDebugMessage("Bid received for unknown or inactive auction: " .. data.auctionID)
        return
    end

    for _, item in ipairs(activeAuction.items) do
        if tonumber(item.itemID) == tonumber(data.itemID) then
            item.responses[data.from] = data.choice
            RaidTrack.AddDebugMessage(string.format("%s bid %s on itemID %s", data.from, data.choice, data.itemID))
            return
        end
    end

    RaidTrack.AddDebugMessage("Matching item not found for received bid: itemID=" .. tostring(data.itemID))
end
local OPEN_AUCTION_PREFIX = "OPEN_AUCTION"

-- Funkcja obsługująca odebraną wiadomość OPEN_AUCTION
local function OnOpenAuctionMessageReceived(msg)
    local auctionID = msg
    RaidTrack.AddDebugMessage("Received OPEN_AUCTION message for auctionID: " .. tostring(auctionID))
    if not auctionID then
        return
    end

    local items = RaidTrack.pendingAuctionItems and RaidTrack.pendingAuctionItems[auctionID]
    if items and #items > 0 then
        
        -- Otwieramy UI z danymi aukcji
        RaidTrack.OpenAuctionParticipantUI({
            auctionID = auctionID,
            leader = "", -- Możesz tu dodać lidera jeśli masz
            started = GetServerTime(), -- Możesz tu dodać czas startu jeśli masz
            endsAt = (GetServerTime() + 30),
            duration = 0, -- Możesz tu dodać czas trwania jeśli masz
            items = items
        })
    else
        RaidTrack.AddDebugMessage("No auction items found for auctionID: " .. auctionID)
    end
end

-- Rejestracja eventu do nasłuchiwania na wiadomości OPEN_AUCTION
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix == OPEN_AUCTION_PREFIX and sender ~= UnitName("player") then
        OnOpenAuctionMessageReceived(message)
    end
end)
function RaidTrack.UpdateLeaderResponseLocally(auctionID, responseData)
    local auctionData = RaidTrack.activeAuctions[auctionID]
    if not auctionData then
        RaidTrack.AddDebugMessage("Auction not found for auctionID: " .. tostring(auctionID))
        return
    end

    -- Przeszukiwanie przedmiotów w aukcji i aktualizacja odpowiedzi lidera
    for _, item in ipairs(auctionData.items) do
        if item.itemID == responseData.itemID then
            for name, response in pairs(item.responses or {}) do
                if name == responseData.from then
                    response.choice = responseData.choice
                    
                    break
                end
            end

            break
        end
    end

    -- Zaktualizowanie UI lidera
    RaidTrack.UpdateAuctionLeaderUI(auctionID)
end
