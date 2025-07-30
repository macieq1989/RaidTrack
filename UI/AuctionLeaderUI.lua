local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:OpenAuctionLeaderUI()
    if self.auctionWindow then
        self.auctionWindow:Show()
        return
    end

    self.currentAuctions = {}

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

    local itemInput = AceGUI:Create("EditBox")
    itemInput:SetLabel("Item Link or Name")
    itemInput:SetFullWidth(true)

    local gpInput = AceGUI:Create("EditBox")
    gpInput:SetLabel("GP Cost")
    gpInput:SetText("100")
    gpInput:SetFullWidth(true)

    local addItemBtn = AceGUI:Create("Button")
    addItemBtn:SetText("Add Item")
    addItemBtn:SetFullWidth(true)

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("List")
    tabGroup:SetFullWidth(true)
    tabGroup:SetHeight(200)
    tabGroup:SetTabs({})

    local function RefreshTabs()
    local tabs = {}
    for idx, auction in ipairs(self.currentAuctions) do
        local itemID = auction.itemID
        local itemLink = itemID and select(2, GetItemInfo(itemID)) or "Item " .. tostring(idx)
        table.insert(tabs, { text = itemLink or "Unknown Item", value = tostring(idx) })
    end
    tabGroup:SetTabs(tabs)
end


    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        container:ReleaseChildren()
        local idx = tonumber(group)
        local auction = self.currentAuctions[idx]
        if not auction then return end

        local label = AceGUI:Create("Label")
        label:SetText("Bids:")
        container:AddChild(label)

        for _, bid in ipairs(auction.bids or {}) do
            local bidLabel = AceGUI:Create("Label")
            bidLabel:SetFullWidth(true)
            bidLabel:SetText(bid.player .. ": " .. bid.response .. " (EP: " .. bid.ep .. ", GP: " .. bid.gp .. ")")
            container:AddChild(bidLabel)
        end

        local removeBtn = AceGUI:Create("Button")
        removeBtn:SetText("Remove Item")
        removeBtn:SetCallback("OnClick", function()
            table.remove(self.currentAuctions, idx)
            RefreshTabs()
            tabGroup:SelectTab(nil)
        end)
        container:AddChild(removeBtn)
    end)

    local startBtn = AceGUI:Create("Button")
    startBtn:SetText("Start Auction for All")
    startBtn:SetFullWidth(true)
    startBtn:SetCallback("OnClick", function()
        if #self.currentAuctions == 0 then return end
        local duration = 30 -- czas trwania aukcji w sekundach
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
end
