local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:OpenAuctionLeaderUI()
    -- Sprawdzamy, czy okno aukcji już istnieje, jeśli tak, to je pokazujemy
    if self.auctionWindow then
        self.auctionWindow:Show()
        return
    end

    self.currentAuctions = {}

    -- Tworzymy główne okno aukcji
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Auction Leader Panel")
    frame:SetStatusText("Add items and configure auctions")
    frame:SetLayout("Fill")
    frame:SetWidth(500)
    frame:SetHeight(500)
    frame:EnableResize(false)
    self.auctionWindow = frame

    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetLayout("List")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    frame:AddChild(mainGroup)

    -- Input dla nazwy przedmiotu oraz ceny GP
    local itemInput = AceGUI:Create("EditBox")
    itemInput:SetLabel("Item Link or Name")
    itemInput:SetFullWidth(true)

    local gpInput = AceGUI:Create("EditBox")
    gpInput:SetLabel("GP Cost")
    gpInput:SetText("100")
    gpInput:SetFullWidth(true)

    -- Przycisk dodawania przedmiotu do aukcji
    local addItemBtn = AceGUI:Create("Button")
    addItemBtn:SetText("Add Item")
    addItemBtn:SetFullWidth(true)

    -- Tworzymy TabGroup, w którym będziemy wyświetlać przedmioty aukcji
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("List")
    tabGroup:SetFullWidth(true)
    tabGroup:SetHeight(200)
    tabGroup:SetTabs({})

    -- Funkcja odświeżająca listę przedmiotów w TabGroup
    local function RefreshTabs()
        local tabs = {}
        for idx, auction in ipairs(self.currentAuctions) do
            local itemID = auction.itemID
            local itemLink = itemID and select(2, GetItemInfo(itemID)) or "Item " .. tostring(idx)
            table.insert(tabs, {
                text = itemLink or "Unknown Item",
                value = tostring(idx)
            })
        end
        tabGroup:SetTabs(tabs)
    end

    -- Callback dla kliknięcia na zakładkę przedmiotu
    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        container:ReleaseChildren()
        local idx = tonumber(group)
        local auction = self.currentAuctions[idx]
        if not auction then
            return
        end

        local label = AceGUI:Create("Label")
        label:SetText("Bids:")
        container:AddChild(label)

        -- Debugowanie ofert
        RaidTrack.AddDebugMessage("Auction Item: " .. auction.itemID .. " Bids: " .. tostring(#auction.bids))

        -- Wyświetlanie ofert dla danego przedmiotu
        for _, bid in ipairs(auction.bids or {}) do
            -- Wyciąganie EP, GP, PR dla gracza
            local ep, gp, pr = GetEPGP(bid.player)

            -- Wyświetlanie oferty gracza
            local bidLabel = AceGUI:Create("Label")
            bidLabel:SetFullWidth(true)
            bidLabel:SetText(bid.player .. ": " .. bid.response .. " (EP: " .. ep .. ", GP: " .. gp .. ", PR: " ..
                                 string.format("%.2f", pr) .. ")")
            container:AddChild(bidLabel)
        end

        -- Przycisk do usuwania przedmiotu z aukcji
        local removeBtn = AceGUI:Create("Button")
        removeBtn:SetText("Remove Item")
        removeBtn:SetCallback("OnClick", function()
            table.remove(self.currentAuctions, idx)
            RefreshTabs()
            tabGroup:SelectTab(nil)
        end)
        container:AddChild(removeBtn)
    end)

    -- Przycisk do rozpoczęcia aukcji dla wszystkich przedmiotów
    local startBtn = AceGUI:Create("Button")
    startBtn:SetText("Start Auction for All")
    startBtn:SetFullWidth(true)
    startBtn:SetCallback("OnClick", function()
        if #self.currentAuctions == 0 then
            return
        end
        local duration = 30 -- Czas trwania aukcji w sekundach
        RaidTrack.StartAuction(self.currentAuctions, duration)
    end)

    -- Przycisk do wyczyszczenia wszystkich przedmiotów z aukcji
    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear All")
    clearBtn:SetFullWidth(true)
    clearBtn:SetCallback("OnClick", function()
        self.currentAuctions = {}
        RefreshTabs()
        tabGroup:SelectTab(nil)
    end)

    -- Callback dla przycisku "Add Item"
    addItemBtn:SetCallback("OnClick", function()
        local itemText = itemInput:GetText()
        local gpCost = tonumber(gpInput:GetText()) or 0
        if itemText == "" then
            return
        end

        -- Ekstrakcja itemID z tekstu
        local itemID = tonumber(string.match(itemText, "item:(%d+)"))

        if not itemID then
            RaidTrack.AddDebugMessage("Failed to extract itemID from input: " .. itemText)
            return
        end

        -- Debugowanie: Sprawdzamy, czy itemID zostało poprawnie przypisane
        RaidTrack.AddDebugMessage("Adding item to auction: itemID=" .. tostring(itemID) .. ", gp=" .. tostring(gpCost))

        -- Dodawanie przedmiotu do aukcji
        table.insert(self.currentAuctions, {
            itemID = itemID,
            gp = gpCost,
            bids = {} -- Inicjalizowanie pustej tabeli dla ofert
        })

        -- Odświeżenie zakładek
        RefreshTabs()
        itemInput:SetText("") -- Czyszczenie inputu
    end)

    -- Dodanie wszystkich elementów do okna aukcji
    mainGroup:AddChild(itemInput)
    mainGroup:AddChild(gpInput)
    mainGroup:AddChild(addItemBtn)
    mainGroup:AddChild(tabGroup)
    mainGroup:AddChild(startBtn)
    mainGroup:AddChild(clearBtn)
end

