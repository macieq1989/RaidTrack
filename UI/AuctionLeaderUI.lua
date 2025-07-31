local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:OpenAuctionLeaderUI()
    -- Inicjalizacja tablicy okien odpowiedzi, jeśli jeszcze nie istnieje
    if not RaidTrack.auctionResponseWindows then
        RaidTrack.auctionResponseWindows = {}
        RaidTrack.AddDebugMessage("auctionResponseWindows initialized.")
    end

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

    local function RefreshTabs()
        RaidTrack.AddDebugMessage("Refreshing tabs...")
        local tabs = {}
        for idx, auction in ipairs(self.currentAuctions) do
            local itemID = auction.itemID
            local itemLink = itemID and select(2, GetItemInfo(itemID)) or "Item " .. tostring(idx)
            local bidCount = #auction.bids
            table.insert(tabs, {
                text = itemLink .. " (Bids: " .. bidCount .. ")",
                value = tostring(idx)
            })
        end
        tabGroup:SetTabs(tabs)
        RaidTrack.AddDebugMessage("Tabs refreshed")
    end

    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        container:ReleaseChildren()
        local idx = tonumber(group)
        local auction = self.currentAuctions[idx]
        if not auction then return end

        local label = AceGUI:Create("Label")
        label:SetText("Bids:")
        container:AddChild(label)

        RaidTrack.AddDebugMessage("Auction Item: " .. auction.itemID .. " Bids: " .. tostring(#auction.bids))

        for _, bid in ipairs(auction.bids or {}) do
            local ep, gp, pr = GetEPGP(bid.from)
            local bidLabel = AceGUI:Create("Label")
            bidLabel:SetFullWidth(true)
            bidLabel:SetText(bid.from .. ": " .. bid.response .. " (EP: " .. ep .. ", GP: " .. gp .. ", PR: " .. string.format("%.2f", pr) .. ")")
            container:AddChild(bidLabel)
        end

        RefreshTabs()
    end)

    local startBtn = AceGUI:Create("Button")
    startBtn:SetText("Start Auction for All")
    startBtn:SetFullWidth(true)
    startBtn:SetCallback("OnClick", function()
        if #self.currentAuctions == 0 then return end
        local duration = 30
        RaidTrack.StartAuction(self.currentAuctions, duration)
    end)

    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear All")
    clearBtn:SetFullWidth(true)
    clearBtn:SetCallback("OnClick", function()
        self.currentAuctions = {}
        RefreshTabs()
        tabGroup:SelectTab(nil)
    end)

    addItemBtn:SetCallback("OnClick", function()
        local itemText = itemInput:GetText()
        local gpCost = tonumber(gpInput:GetText()) or 0
        if itemText == "" then return end

        local itemID = tonumber(string.match(itemText, "item:(%d+)"))
        if not itemID then
            RaidTrack.AddDebugMessage("Failed to extract itemID from input: " .. itemText)
            return
        end

        RaidTrack.AddDebugMessage("Adding item to auction: itemID=" .. tostring(itemID) .. ", gp=" .. tostring(gpCost))

        table.insert(self.currentAuctions, {
            itemID = itemID,
            gp = gpCost,
            bids = {}
        })

        RefreshTabs()
        itemInput:SetText("")
    end)

    mainGroup:AddChild(itemInput)
    mainGroup:AddChild(gpInput)
    mainGroup:AddChild(addItemBtn)
    mainGroup:AddChild(tabGroup)
    mainGroup:AddChild(startBtn)
    mainGroup:AddChild(clearBtn)
    RaidTrack.RefreshAuctionLeaderTabs = RefreshTabs
end


function RaidTrack.UpdateItemResponseInUI(auctionID, item)
    RaidTrack.AddDebugMessage("Updating UI for auctionID " .. tostring(auctionID) .. " and itemID " .. tostring(item.itemID))

    -- Sprawdzenie i utworzenie okna, jeśli nie istnieje
    if not RaidTrack.auctionResponseWindows then
        RaidTrack.auctionResponseWindows = {}
    end

    local frame = RaidTrack.auctionResponseWindows[auctionID]
    if not frame then
        RaidTrack.AddDebugMessage("Creating new auction response window for auctionID " .. tostring(auctionID))
        frame = AceGUI:Create("Frame")
        frame:SetTitle("Responses for Item: " .. (item.link or "Item " .. item.itemID))
        frame:SetStatusText("Auction ID: " .. auctionID)
        frame:SetLayout("List")
        frame:SetWidth(500)
        frame:SetHeight(400)
        frame:EnableResize(true)
        RaidTrack.auctionResponseWindows[auctionID] = frame
    else
        frame:ReleaseChildren()  -- 🔁 Usuwa wszystkie dzieci, bezpiecznie
    end

    -- Nagłówek
    local header = AceGUI:Create("Label")
    header:SetFullWidth(true)
    header:SetText("Responses for: " .. (item.link or "ItemID: " .. tostring(item.itemID)))
    frame:AddChild(header)

    -- Wyświetlenie ofert (zakładamy że to tablica `bids`)
    RaidTrack.AddDebugMessage("Displaying bids for itemID " .. tostring(item.itemID))

    for _, response in ipairs(item.bids or {}) do
        local ep, gp, pr = GetEPGP(response.from)

        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText(response.from .. " - EP: " .. ep .. ", GP: " .. gp .. ", PR: " .. string.format("%.2f", pr) .. ", Response: " .. response.choice)
        frame:AddChild(label)
    end

    RaidTrack.AddDebugMessage("UI updated for itemID " .. tostring(item.itemID))
end

function RaidTrack.UpdateLeaderAuctionUI(auctionID, item)
    RaidTrack.AddDebugMessage("Updating leader auction UI for auctionID: " .. tostring(auctionID))

    -- Sprawdzamy, czy okno odpowiedzi lidera już istnieje
    if not RaidTrack.auctionResponseWindows then
        RaidTrack.auctionResponseWindows = {}
    end

    -- Jeśli okno odpowiedzi lidera już istnieje, aktualizujemy je
    local frame = RaidTrack.auctionResponseWindows[auctionID]
    if not frame then
        RaidTrack.AddDebugMessage("Creating new auction response window for auctionID " .. tostring(auctionID))

        -- Tworzymy nowe okno odpowiedzi lidera
        frame = AceGUI:Create("Frame")
        frame:SetTitle("Responses for Item: " .. (item.link or "Item " .. item.itemID))
        frame:SetStatusText("Auction ID: " .. auctionID)
        frame:SetLayout("List")
        frame:SetWidth(500)
        frame:SetHeight(400)
        frame:EnableResize(true)
        RaidTrack.auctionResponseWindows[auctionID] = frame
    else
        -- Jeśli okno już istnieje, usuwamy dzieci i aktualizujemy je
        frame:ReleaseChildren()  -- Bezpiecznie usuwamy wszystkie dzieci
    end

    -- Nagłówek
    local header = AceGUI:Create("Label")
    header:SetFullWidth(true)
    header:SetText("Responses for: " .. (item.link or "ItemID: " .. tostring(item.itemID)))
    frame:AddChild(header)

    -- Wyświetlenie ofert (bids)
    RaidTrack.AddDebugMessage("Displaying bids for itemID " .. tostring(item.itemID))

    -- Dodajemy odpowiedzi lidera do okna
    for _, response in ipairs(item.bids or {}) do
        local ep, gp, pr = GetEPGP(response.from)

        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText(response.from .. " - EP: " .. ep .. ", GP: " .. gp .. ", PR: " .. string.format("%.2f", pr) .. ", Response: " .. response.choice)
        frame:AddChild(label)
    end

    RaidTrack.AddDebugMessage("UI updated for itemID " .. tostring(item.itemID))
end


