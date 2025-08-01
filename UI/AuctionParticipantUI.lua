local AceGUI = LibStub("AceGUI-3.0")
local addonPrefix = "RaidTrackAuction"

local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack.OpenAuctionParticipantUI(auctionData)
    if not auctionData or type(auctionData) ~= "table" or not auctionData.items or #auctionData.items == 0 then
        RaidTrack.AddDebugMessage("Invalid auctionData received by participant UI.")
        return
    end

    RaidTrack.AddDebugMessage("OpenAuctionParticipantUI() called")
    print("==== OpenAuctionParticipantUI CALLED ====")

    -- Tablica do przechowywania zaktualizowanych przedmiotów
    local updatedItems = {}
    local totalItems = #auctionData.items
    local auctionEndTime = auctionData.started + auctionData.duration
    local frame
    local isWindowOpen = false -- Flaga, aby upewnić się, że okno nie otworzy się ponownie

    -- Funkcja, która zaktualizuje dane przedmiotu
    local function UpdateItemData(item)
        -- Pobieramy link przedmiotu z cache
        local itemLink = select(2, GetItemInfo(item.itemID))

        -- Jeśli link jest dostępny, użyj go, jeśli nie, ustaw itemID
        if itemLink then
            item.link = itemLink
        else
            item.link = "ItemID: " .. tostring(item.itemID) -- Jeśli nie ma linku, wyświetlamy tylko ID
        end
    end

    -- Funkcja do aktualizacji tytułu okna z pozostałym czasem
    local function UpdateAuctionTime()
        local remainingTime = auctionEndTime - time()
        if remainingTime <= 0 then
            frame:SetTitle("RaidTrack Auction - Time's up!")
        else
            local minutes = math.floor(remainingTime / 60)
            local seconds = remainingTime % 60
            frame:SetTitle(string.format("RaidTrack Auction - Time remaining: %02d:%02d", minutes, seconds))
        end
    end

    -- Co sekundę odświeżamy tytuł z pozostałym czasem
    C_Timer.NewTicker(1, UpdateAuctionTime)

    -- Funkcja otwierająca okno aukcji, jeśli wszystkie przedmioty zostały załadowane
    local function OpenAuctionWindowIfReady()
        -- Upewniamy się, że okno aukcji nie zostało jeszcze otwarte
        if not isWindowOpen then
            isWindowOpen = true

            -- Tworzymy okno dla uczestnika aukcji
            frame = AceGUI:Create("Frame")
            frame:SetTitle("RaidTrack Auction")
            frame:SetStatusText("Select your response for each item")
            frame:SetLayout("List")
            frame:SetWidth(500)
            frame:SetHeight(400)
            frame:EnableResize(false)
            RaidTrack.auctionParticipantWindow = frame

            -- Ustawiamy pozycję okna na prawą stronę ekranu
            frame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0) -- Ustawi okno po prawej stronie ekranu

            -- Tworzymy ScrollFrame, by dodać suwak
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll:SetFullWidth(true)
            scroll:SetFullHeight(true)
            frame:AddChild(scroll)

            -- Liczymy ilość przedmiotów
            local itemCount = #updatedItems
            local maxVisibleItems = 5 -- Limit widocznych przedmiotów
            local itemHeight = 80 -- Wysokość pojedynczego przedmiotu (dostosuj do rzeczywistego rozmiaru)
            local scrollHeight = math.min(itemCount, maxVisibleItems) * itemHeight
            frame:SetHeight(scrollHeight + 80) -- +80 dla paddingu lub miejsca na przyciski

            -- Iteracja przez przedmioty w aukcji
            for i, item in ipairs(updatedItems) do
                RaidTrack.AddDebugMessage(string.format("ParticipantUI item %d: id=%s, gp=%s, link=%s", i,
                    tostring(item.itemID), tostring(item.gp), tostring(item.link)))

                local itemGroup = AceGUI:Create("InlineGroup")
                itemGroup:SetFullWidth(true)
                itemGroup:SetLayout("Flow")

                -- Wyświetl link przedmiotu
                local title = item.link or ("ItemID: " .. tostring(item.itemID)) -- Wyświetlanie ItemID, jeśli nie mamy linku
                itemGroup:SetTitle(title)

                local gpLabel = AceGUI:Create("Label")
                gpLabel:SetText("GP: " .. tostring(item.gp or "?"))
                gpLabel:SetWidth(60)
                itemGroup:AddChild(gpLabel)

                -- Funkcja do tworzenia przycisków odpowiedzi
               local function CreateResponseButton(label, responseType, allButtonsTable)
    local btn = AceGUI:Create("Button")
    btn:SetText(label)
    btn:SetWidth(80)

    btn:SetCallback("OnClick", function()
        -- ⛔ Zabezpieczenie: aukcja już się zakończyła
        if time() > auctionEndTime then
            RaidTrack.AddDebugMessage("Auction expired, response ignored.")
            return
        end

        local isLeader = UnitName("player") == auctionData.leader
        local ep, gp, pr = RaidTrack.GetEPGP(UnitName("player"))

        local responseData = {
            player = UnitName("player"),
            response = responseType,
            ep = ep,
            gp = gp,
            pr = pr
        }

        if not item.responses then
            item.responses = {}
        end

        item.responses[UnitName("player")] = responseData

        -- 🔁 Resetujemy wszystkie przyciski (z danej grupy) do aktywnych
        for _, otherBtn in ipairs(allButtonsTable) do
            otherBtn:SetDisabled(false)
        end

        -- 🔒 Dezaktywujemy tylko aktualny
        btn:SetDisabled(true)

        -- Wyślij odpowiedź
        RaidTrack.SendAuctionResponseChunked(auctionData.auctionID, item.itemID, responseType)
    end)

    return btn
end


                -- Dodanie przycisków wyboru odpowiedzi
                local buttons = {}

table.insert(buttons, CreateResponseButton("Main Spec", "MS", buttons))
table.insert(buttons, CreateResponseButton("Off Spec", "OS", buttons))
table.insert(buttons, CreateResponseButton("Transmog", "TMOG", buttons))
table.insert(buttons, CreateResponseButton("Pass", "PASS", buttons))

for _, btn in ipairs(buttons) do
    itemGroup:AddChild(btn)
end


                -- Dodanie przedmiotu do okna aukcji
                scroll:AddChild(itemGroup)
            end
        end
    end

    -- Iteracja przez przedmioty, aby załadować linki
    for i, item in ipairs(auctionData.items) do
        -- Sprawdzamy, czy itemID jest poprawny i nie jest pusty
        if item.itemID and item.itemID ~= 0 then
            RaidTrack.AddDebugMessage("Loading data for item ID: " .. tostring(item.itemID)) -- Debug: Loading data for each item

            -- Używamy funkcji, aby załadować dane o przedmiocie
            UpdateItemData(item)

            -- Dodajemy przedmiot do zaktualizowanej listy
            table.insert(updatedItems, item)
        else
            RaidTrack.AddDebugMessage("Invalid itemID=" .. tostring(item.itemID) .. ", skipping.")
        end
    end

    -- Po załadowaniu wszystkich danych otwieramy okno
    OpenAuctionWindowIfReady()
end
