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
    RaidTrack.AddDebugMessage("StartAuction called by: " .. tostring(UnitName("player")) .. " | Officer status: " .. tostring(RaidTrack.IsOfficer()))
    print("=== DEBUG: StartAuction WYWOŁANA ===")
    RaidTrack.AddDebugMessage("=== DEBUG: StartAuction WYWOŁANA ===")
    print("Dostałem items: ", items, "liczba:", items and #items or 0)
    print("duration: ", duration)

    if not RaidTrack.IsOfficer() then
        RaidTrack.AddDebugMessage("Only officers can start auctions.")
        return
    end

    if activeAuction then
        RaidTrack.AddDebugMessage("Auction already in progress.")
        return
    end

    local auctionID = tostring(time())
    RaidTrack.AddDebugMessage("Generated auction ID: " .. auctionID)

    activeAuction = {
        auctionID = auctionID,
        items = {},
        leader = UnitName("player"),
        started = time(),
        duration = duration
    }
    RaidTrack.auctionsByID = RaidTrack.auctionsByID or {}
RaidTrack.auctionsByID[auctionID] = activeAuction

    -- Rejestrujemy lokalnie dane w activeAuctions dla lidera (ważne!)
    RaidTrack.activeAuctions = RaidTrack.activeAuctions or {}
    RaidTrack.activeAuctions[auctionID] = {
        items = {},
        leader = UnitName("player"),
        started = time(),
        duration = duration
    }

    for _, item in ipairs(items) do
        RaidTrack.AddDebugMessage("Adding item to auction: itemID=" .. tostring(item.itemID) .. ", gp=" .. tostring(item.gp))
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
                    link = select(2, GetItemInfo(item.itemID)) or "item:" .. item.itemID,
                    responses = {}
                }
                table.insert(activeAuction.items, itemEntry)
                table.insert(RaidTrack.activeAuctions[auctionID].items, itemEntry)

                -- Wyślij przez sync
                RaidTrack.QueueAuctionChunkedSend(nil, auctionID, "item", {
                    auctionID = auctionID,
                    itemID = item.itemID,
                    gp = item.gp,
                    epgpChanges = {}
                })
            else
                RaidTrack.AddDebugMessage("Duplicate item skipped: itemID=" .. tostring(item.itemID))
            end
        else
            RaidTrack.AddDebugMessage("Invalid item skipped in StartAuction: " .. tostring(item.itemID) .. ", GP: " .. tostring(item.gp))
        end
    end

    RaidTrack.QueueAuctionChunkedSend(nil, auctionID, "header", {
        leader = UnitName("player"),
        started = time(),
        duration = duration
    })

    RaidTrack.AddDebugMessage("Auction started with ID: " .. auctionID)

    C_Timer.After(0.5, function()
        RaidTrack.OpenAuctionParticipantUI({
            auctionID = auctionID,
            leader = UnitName("player"),
            started = time(),
            duration = duration,
            items = activeAuction.items
        })
    end)

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

    RaidTrack.AddDebugMessage("Serialized EPGP changes: " .. payload)
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, payload, "GUILD")
end

function RaidTrack.SendAuctionData(data)
    local serializedData = RaidTrack.SafeSerialize(data)
    local totalChunks = math.ceil(#serializedData / CHUNK_SIZE)
    local chunks = {}

    for i = 1, totalChunks do
        chunks[i] = serializedData:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
    end

    -- Wysyłamy dane aukcji do wszystkich graczy
    for idx, chunk in ipairs(chunks) do
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, string.format("%d|%d|%s", idx, totalChunks, chunk), "GUILD")
    end

    RaidTrack.AddDebugMessage("Auction data sent with " .. totalChunks .. " chunk(s).")
end

function RaidTrack.ReceiveAuctionData(sender, rawData)
    -- Logowanie surowych danych przed deserializacją
    RaidTrack.AddDebugMessage("Raw data received from " .. sender .. ": " .. rawData)

    -- Deserializujemy dane
    local ok, data = RaidTrack.SafeDeserialize(rawData)
    if not ok then
        RaidTrack.AddDebugMessage("Failed to deserialize auction chunk from " .. sender)
        return
    end

    -- Logowanie, co dokładnie zostało zdeserializowane
    RaidTrack.AddDebugMessage("Deserialized auction data: " .. tostring(data))
    RaidTrack.AddDebugMessage("Auction ID: " .. tostring(data.auctionID))
    RaidTrack.AddDebugMessage("Items: " .. tostring(data.items))
    RaidTrack.AddDebugMessage("Received auction data: auctionID = " .. data.auctionID .. ", items count = " ..
                                  #data.items)

    -- Jeśli brak danych aukcji lub itemów, wyświetl komunikat
    if not data or not data.auctionID or not data.items then
        RaidTrack.AddDebugMessage("Invalid auction data received. Missing auctionID or items.")
        return
    end

    -- Obsługujemy dane EPGP jeśli są obecne
    if data.epgpDelta then
        RaidTrack.AddDebugMessage("Received EPGP delta changes.")
        RaidTrack.MergeEPGPChanges(data.epgpDelta)
    end

    -- Sprawdzamy, czy już istnieje częściowa aukcja w pamięci
    RaidTrack.partialAuction = RaidTrack.partialAuction or {}
    local auction = RaidTrack.partialAuction[data.auctionID]
    if not auction then
        -- Tworzymy nową aukcję, jeśli nie istnieje
        auction = {
            items = {},
            leader = "",
            started = 0,
            duration = 0
        }
        RaidTrack.partialAuction[data.auctionID] = auction
    end

    -- Dodajemy elementy do aukcji
    for _, item in ipairs(data.items) do
        local itemID = item.itemID
        local gp = item.gp
        table.insert(auction.items, {
            itemID = itemID,
            gp = gp,
            link = select(2, GetItemInfo(itemID)) or "ItemID: " .. itemID,
            responses = {}
        })
    end

    -- Jeśli to ostatni przedmiot (po zebraniu wszystkich chunków), otwieramy UI
    if #auction.items == #data.items then
        RaidTrack.AddDebugMessage("All auction items received, opening UI for auctionID: " .. data.auctionID)
        RaidTrack.OpenAuctionParticipantUI({
            auctionID = data.auctionID,
            leader = data.leader,
            started = data.started,
            duration = data.duration,
            items = auction.items
        })
        -- Zwalniamy pamięć po zakończeniu aukcji
        RaidTrack.partialAuction[data.auctionID] = nil
    end
end

RaidTrack.partialAuction = RaidTrack.partialAuction or {}

function RaidTrack.ReceiveAuctionItem(data)
    if not data.auctionID or not data.item or not data.item.itemID then
        return
    end

    local auctionID = data.auctionID
    local itemID = tonumber(data.item.itemID)
    local gp = tonumber(data.item.gp) or 0

    -- Get or initialize auction data
    RaidTrack.partialAuction = RaidTrack.partialAuction or {}
    local entry = RaidTrack.partialAuction[auctionID] or {
        items = {}
    }
    RaidTrack.partialAuction[auctionID] = entry

    local function TryInsertItem(attemptsLeft)
        -- Sprawdzamy, czy przedmiot już istnieje w liście aukcji
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
            RaidTrack.AddDebugMessage("Link do przedmiotu rozwiązany: " .. itemLink)
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

-- Submit response
function RaidTrack.SubmitAuctionResponse(choice)
    if not activeAuction then
        return
    end
    local payload = RaidTrack.SafeSerialize({
        response = {
            from = UnitName("player"),
            choice = choice,
            item = activeAuction.item
        }
    })
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, payload, "WHISPER", activeAuction.leader)
    RaidTrack.HideAuctionPopup()
end

function RaidTrack.ShowAuctionResults()
    if not activeAuction then
        return
    end

    RaidTrack.AddDebugMessage("Auction Results:")
    for _, item in ipairs(activeAuction.items) do
        RaidTrack.AddDebugMessage("Item: " .. (item.link or ("item:" .. tostring(item.itemID))))
        for name, choice in pairs(item.responses or {}) do
            local responseText = string.format(
                " - %s: Response=%s, EP=%d, GP=%d, PR=%.2f",
                name,
                choice.response or "N/A",
                choice.ep or 0,
                choice.gp or 0,
                choice.pr or 0
            )
            RaidTrack.AddDebugMessage(responseText)
        end
    end
end


-- Event handler
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then
        return
    end

    local ok, data = RaidTrack.SafeDeserialize(msg)
    if not ok then
        return
    end

    if data.auction then
        RaidTrack.ReceiveAuction(data)
    elseif data.response then
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
        items = {},
        leader = data.leader,
        started = data.started,
        duration = data.duration
    }

    local attempt = 0
    local maxAttempts = 10

    local function tryShowAuction()
        local entry = RaidTrack.partialAuction[auctionID]
        attempt = attempt + 1

        if entry and type(entry.items) == "table" and #entry.items > 0 then
            RaidTrack.OpenAuctionParticipantUI({
                auctionID = auctionID,
                leader = entry.leader,
                started = entry.started,
                duration = entry.duration,
                items = entry.items
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
        itemID = selectedItemID,  -- Używamy itemID z UI
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
        RaidTrack.AddDebugMessage("Opening Auction UI for auctionID: " .. auctionID)
        -- Otwieramy UI z danymi aukcji
        RaidTrack.OpenAuctionParticipantUI({
            auctionID = auctionID,
            leader = "", -- Możesz tu dodać lidera jeśli masz
            started = 0, -- Możesz tu dodać czas startu jeśli masz
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
            for _, bid in ipairs(item.bids) do
                if bid.from == responseData.from then
                    bid.choice = responseData.choice
                    RaidTrack.AddDebugMessage("Updated leader response locally: " .. responseData.choice .. " for itemID " .. tostring(item.itemID))
                    break
                end
            end
            break
        end
    end

    -- Zaktualizowanie UI lidera
    RaidTrack.UpdateAuctionLeaderUI(auctionID)
end
