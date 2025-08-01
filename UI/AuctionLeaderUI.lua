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


function RaidTrack.UpdateLeaderAuctionUI(auctionID)
    RaidTrack.AddDebugMessage("Updating combined leader auction UI for auctionID: " .. tostring(auctionID))

    if not RaidTrack.auctionResponseWindows then
        RaidTrack.auctionResponseWindows = {}
    end

    local frame = RaidTrack.auctionResponseWindows[auctionID]
    if not frame then
        frame = AceGUI:Create("Frame")
        frame:SetTitle("Auction Responses")
        frame:SetStatusText("Auction ID: " .. auctionID)
        frame:SetLayout("Fill")
        frame:SetWidth(600)
        frame:SetHeight(500)
        frame:EnableResize(true)
        RaidTrack.auctionResponseWindows[auctionID] = frame

        -- ⬅ przypięcie z lewej
        if RaidTrack.auctionWindow then
            local anchor = RaidTrack.auctionWindow.frame or RaidTrack.auctionWindow
            if anchor.SetPoint then
                frame:SetPoint("TOPRIGHT", anchor.frame or anchor, "TOPLEFT", -10, 0)
            end
        end
    else
        frame:ReleaseChildren()
    end

    local scrollContainer = AceGUI:Create("ScrollFrame")
    scrollContainer:SetLayout("List")
    frame:AddChild(scrollContainer)

    local auctionData = RaidTrack.activeAuctions and RaidTrack.activeAuctions[auctionID]
    if not auctionData or not auctionData.items then
        RaidTrack.AddDebugMessage("No auction data found for auctionID: " .. tostring(auctionID))
        return
    end

    for _, item in ipairs(auctionData.items) do
        local itemLink = item.link or ("ItemID: " .. tostring(item.itemID))
        local header = AceGUI:Create("Heading")
        header:SetFullWidth(true)
        header:SetText(itemLink)
        scrollContainer:AddChild(header)

        RaidTrack.AddDebugMessage("Displaying responses for itemID: " .. tostring(item.itemID))

        for _, response in ipairs(item.bids or {}) do
            local ep, gp, pr = GetEPGP(response.from)
            local label = AceGUI:Create("Label")
            label:SetFullWidth(true)
            local _, class = UnitClass(response.from)
local color = (RAID_CLASS_COLORS[class] or { r = 1, g = 1, b = 1 })
local coloredName = string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, response.from)
label:SetText(coloredName .. " - EP: " .. ep .. ", GP: " .. gp .. ", PR: " .. string.format("%.2f", pr) .. ", Response: " .. response.choice)
            scrollContainer:AddChild(label)
        end
    end

    RaidTrack.AddDebugMessage("Combined UI updated for auctionID: " .. tostring(auctionID))
end

