local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- fallback coords jeśli global nie istnieje
local CLASS_ICON_TCOORDS = _G.CLASS_ICON_TCOORDS or {
    WARRIOR = {0, 0.25, 0, 0.25},
    MAGE = {0.25, 0.49609375, 0, 0.25},
    ROGUE = {0.49609375, 0.7421875, 0, 0.25},
    DRUID = {0.7421875, 0.98828125, 0, 0.25},
    HUNTER = {0, 0.25, 0.25, 0.5},
    SHAMAN = {0.25, 0.49609375, 0.25, 0.5},
    PRIEST = {0.49609375, 0.7421875, 0.25, 0.5},
    WARLOCK = {0.7421875, 0.98828125, 0.25, 0.5},
    PALADIN = {0, 0.25, 0.5, 0.75},
    DEATHKNIGHT = {0.25, 0.49609375, 0.5, 0.75},
    MONK = {0.49609375, 0.7421875, 0.5, 0.75},
    DEMONHUNTER = {0.7421875, 0.98828125, 0.5, 0.75},
    EVOKER = {0, 0.25, 0.75, 1},
}

-- policz realne bidy (bez PASS)
local function CountRealBids(bids)
    local c = 0
    for _, b in ipairs(bids or {}) do
        local choice = (b.choice or b.response)
        if choice and choice ~= "PASS" then
            c = c + 1
        end
    end
    return c
end

-- bazowy itemID (ignoruje warianty/bonusy)
local function BaseItemIDFrom(any)
    if type(any) == "number" then return any end
    if not any then return nil end
    if type(any) == "string" and any:find("item:") then
        local id = select(1, GetItemInfoInstant(any))
        return id
    end
    -- nazwa albo id w stringu
    local id = tonumber(any)
    if id then return id end
    return select(1, GetItemInfoInstant(any))
end

-- normalizacja pojedynczego itemu pod aukcję
local function NormalizeItem(it)
    if not it then return nil end
    local itemID = it.itemID or BaseItemIDFrom(it.link or it.name)
    if not itemID then return nil end
    local link = it.link
    if not link then
        -- spróbuj pobrać link; może być nil jeśli nie ma w cache – to OK
        link = select(2, GetItemInfo(itemID))
    end
    return {
        itemID = itemID,
        gp     = tonumber(it.gp) or 0,
        link   = link,        -- opcjonalnie
        bids   = type(it.bids) == "table" and it.bids or {},
    }
end

local function NormalizeItems(list)
    local out = {}
    for _, it in ipairs(list or {}) do
        local n = NormalizeItem(it)
        if n then table.insert(out, n) end
    end
    return out
end

function RaidTrack.NotifyBidUpdate(auctionID)
    if RaidTrack.RefreshAuctionLeaderTabs then
        RaidTrack.RefreshAuctionLeaderTabs()
    end
end

function RaidTrack:OpenAuctionLeaderUI()
    -- init jednorazowy
    if not RaidTrack.auctionResponseWindows then
        RaidTrack.auctionResponseWindows = {}
        RaidTrack.AddDebugMessage("auctionResponseWindows initialized.")
    end

    if self.auctionWindow then
        if self.auctionWindow.frame and not self.auctionWindow.frame:IsShown() then
            self.auctionWindow.frame:Show()
        end
        return
    end

    self.currentAuctions = {}         -- lokalna lista (itemID,gp[,link][,bids])
    self._tabAuctionIDs = {}          -- map: index -> auctionID (solo aukcja)
    self._currentAllAuctionID = nil   -- auctionID dla „Start ALL”
    self._selectedTabValue = self._selectedTabValue or nil
    self._inRefreshTabs = false

    -- === UI ===
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Auction Leader Panel")
    frame:SetStatusText("Add items and configure auctions")
    frame:SetLayout("Fill")
    frame:SetWidth(520)
    frame:SetHeight(520)
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

    local durationInput = AceGUI:Create("EditBox")
    durationInput:SetLabel("Auction duration (sec)")
    durationInput:SetText("30")
    durationInput:SetFullWidth(true)
    durationInput:SetCallback("OnEnterPressed", function()
        local v = tonumber(durationInput:GetText())
        if not v or v <= 0 then durationInput:SetText("30") end
    end)

    local addItemBtn = AceGUI:Create("Button")
    addItemBtn:SetText("Add Item")
    addItemBtn:SetFullWidth(true)

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetHeight(260)
    tabGroup:SetTabs({})

    -- policz aktualne bidy dla taba (solo/all/fallback)
    local function GetLiveBidCountForIndex(idx)
        local tabItem = self.currentAuctions[idx]
        if not tabItem then return 0 end

        local wantedBase = BaseItemIDFrom(tabItem.link or ("item:" .. tostring(tabItem.itemID)))

        -- 1) SOLO aukcja tego taba
        local soloID = self._tabAuctionIDs[idx]
        if soloID and RaidTrack.activeAuctions and RaidTrack.activeAuctions[soloID] then
            local it = (RaidTrack.activeAuctions[soloID].items or {})[1]
            return CountRealBids(it and it.bids)
        end

        -- 2) ALL aukcja – dopasuj po bazowym ID
        local allID = self._currentAllAuctionID
        if allID and RaidTrack.activeAuctions and RaidTrack.activeAuctions[allID] then
            local items = RaidTrack.activeAuctions[allID].items or {}
            local chosen
            if wantedBase then
                for _, it in ipairs(items) do
                    local base = BaseItemIDFrom(it.link or ("item:" .. tostring(it.itemID)))
                    if base and base == wantedBase then chosen = it; break end
                end
            end
            if not chosen then chosen = items[idx] end
            return CountRealBids(chosen and chosen.bids)
        end

        -- 3) Przeszukaj wszystkie aktywne aukcje po bazowym ID
        if RaidTrack.activeAuctions and wantedBase then
            for _, auc in pairs(RaidTrack.activeAuctions) do
                for _, it in ipairs(auc.items or {}) do
                    local base = BaseItemIDFrom(it.link or ("item:" .. tostring(it.itemID)))
                    if base and base == wantedBase then
                        return CountRealBids(it.bids)
                    end
                end
            end
        end

        -- 4) Brak aktywnej aukcji – licz lokalne
        return CountRealBids(tabItem.bids)
    end

    local function RefreshTabs()
        if self._inRefreshTabs then return end
        self._inRefreshTabs = true

        local tabs = {}
        for idx, auction in ipairs(self.currentAuctions) do
            local itemID = auction.itemID
            local itemLink = auction.link or select(2, GetItemInfo(itemID)) or ("Item " .. tostring(idx))
            local bidCount = GetLiveBidCountForIndex(idx)
            table.insert(tabs, {
                text  = (itemLink or ("Item " .. idx)) .. " (Bids: " .. bidCount .. ")",
                value = tostring(idx),
            })
        end

        if #tabs == 0 then
            tabGroup:SetTabs({})
            if tabGroup.selected ~= nil then
                pcall(function() tabGroup:SelectTab(nil) end)
            end
            self._selectedTabValue = nil
            tabGroup:ReleaseChildren()
            self._inRefreshTabs = false
            return
        end

        tabGroup:SetTabs(tabs)

        local want = self._selectedTabValue
        local exists = false
        if want then
            for _, t in ipairs(tabs) do
                if t.value == want then exists = true; break end
            end
        end
        if exists then
            if tabGroup.selected ~= want then
                tabGroup:SelectTab(want)
            end
        else
            self._selectedTabValue = tabs[1].value
            if tabGroup.selected ~= self._selectedTabValue then
                tabGroup:SelectTab(self._selectedTabValue)
            end
        end

        self._inRefreshTabs = false
    end
    RaidTrack.RefreshAuctionLeaderTabs = RefreshTabs

    tabGroup:SetCallback("OnGroupSelected", function(container, _, group)
        container:ReleaseChildren()
        self._selectedTabValue = group

        local idx = tonumber(group)
        local auction = self.currentAuctions[idx]
        if not auction then return end

        local header = AceGUI:Create("Label")
        header:SetText("Selected item index: " .. idx)
        header:SetFullWidth(true)
        container:AddChild(header)

        local rowActions = AceGUI:Create("SimpleGroup")
        rowActions:SetLayout("Flow")
        rowActions:SetFullWidth(true)
        container:AddChild(rowActions)

        local startOneBtn = AceGUI:Create("Button")
        startOneBtn:SetText("Start THIS item")
        startOneBtn:SetRelativeWidth(0.5)
        startOneBtn:SetCallback("OnClick", function()
            local dur = tonumber(durationInput:GetText()) or 30
            if dur <= 0 then dur = 30 end

            local normalized = NormalizeItems({ auction })
            if #normalized == 0 then
                RaidTrack.AddDebugMessage("Start THIS: item failed to normalize (no itemID)")
                return
            end

            local auctionID = RaidTrack.StartAuction(normalized, dur) -- musi zwrócić ID
            if not auctionID then
                -- diagnostyka – jeśli implementacja zwróci nil
                RaidTrack.AddDebugMessage("Start THIS returned nil auctionID (check StartAuction)")
            end
            self._tabAuctionIDs[idx] = auctionID
            RaidTrack.AddDebugMessage("Started single-item auction idx=" .. idx .. " auctionID=" .. tostring(auctionID))
            RefreshTabs()
            if auctionID then RaidTrack.UpdateLeaderAuctionUI(auctionID) end
        end)
        rowActions:AddChild(startOneBtn)

        local removeBtn = AceGUI:Create("Button")
        removeBtn:SetText("Remove THIS item")
        removeBtn:SetRelativeWidth(0.5)
        removeBtn:SetCallback("OnClick", function()
            table.remove(self.currentAuctions, idx)
            local newMap = {}
            for i, id in pairs(self._tabAuctionIDs) do
                if i < idx then newMap[i] = id
                elseif i > idx then newMap[i-1] = id end
            end
            self._tabAuctionIDs = newMap
            RefreshTabs()
        end)
        rowActions:AddChild(removeBtn)
    end)

    local startAllBtn = AceGUI:Create("Button")
    startAllBtn:SetText("Start Auction for ALL items")
    startAllBtn:SetFullWidth(true)
    startAllBtn:SetCallback("OnClick", function()
        if #self.currentAuctions == 0 then return end
        local dur = tonumber(durationInput:GetText()) or 30
        if dur <= 0 then dur = 30 end

        local normalized = NormalizeItems(self.currentAuctions)
        if #normalized == 0 then
            RaidTrack.AddDebugMessage("Start ALL: no items normalized")
            return
        end

        local auctionID = RaidTrack.StartAuction(normalized, dur)
        if not auctionID then
            RaidTrack.AddDebugMessage("Started ALL-items auction but auctionID=nil (check StartAuction)")
        end
        self._currentAllAuctionID = auctionID
        RaidTrack.AddDebugMessage("Started ALL-items auction auctionID=" .. tostring(auctionID))
        RefreshTabs()
        if auctionID then RaidTrack.UpdateLeaderAuctionUI(auctionID) end
    end)

    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear All (list)")
    clearBtn:SetFullWidth(true)
    clearBtn:SetCallback("OnClick", function()
        self.currentAuctions = {}
        self._tabAuctionIDs = {}
        self._currentAllAuctionID = nil
        RefreshTabs()
        pcall(function() tabGroup:SelectTab(nil) end)
    end)

    addItemBtn:SetCallback("OnClick", function()
        local itemText = itemInput:GetText()
        local gpCost = tonumber(gpInput:GetText()) or 0
        if not itemText or itemText == "" then return end

        local itemID = BaseItemIDFrom(itemText) or tonumber(string.match(itemText, "item:(%d+)"))
        if not itemID then
            -- spróbuj nazwę rozwiązać – GetItemInfoInstant nie zawsze zwróci id po nazwie
            local _, _, _, _, _, _, _, _, _, _, idByInfo = GetItemInfo(itemText)
            itemID = idByInfo
        end
        if not itemID then
            RaidTrack.AddDebugMessage("Failed to extract/resolve itemID from input: " .. tostring(itemText))
            return
        end

        local link = select(2, GetItemInfo(itemID))
        table.insert(self.currentAuctions, { itemID = itemID, gp = gpCost, link = link, bids = {} })
        RaidTrack.AddDebugMessage("Adding item to auction: itemID=" .. tostring(itemID) .. ", gp=" .. tostring(gpCost))
        RefreshTabs()
        itemInput:SetText("")
    end)

    mainGroup:AddChild(itemInput)
    mainGroup:AddChild(gpInput)
    mainGroup:AddChild(durationInput)
    mainGroup:AddChild(addItemBtn)
    mainGroup:AddChild(tabGroup)
    mainGroup:AddChild(startAllBtn)
    mainGroup:AddChild(clearBtn)

    RefreshTabs()
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
        frame:SetStatusText("Auction ID: " .. tostring(auctionID))
        frame:SetLayout("Fill")
        frame:SetWidth(780)
        frame:SetHeight(560)
        frame:EnableResize(true)
        RaidTrack.auctionResponseWindows[auctionID] = frame

        if RaidTrack.auctionWindow then
            local anchor = RaidTrack.auctionWindow.frame or RaidTrack.auctionWindow
            if anchor and (anchor.frame or anchor).SetPoint then
                local A = anchor.frame or anchor
                frame.frame:ClearAllPoints()
                frame.frame:SetPoint("TOPRIGHT", A, "TOPLEFT", -10, 0)
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
        local header = AceGUI:Create("Label")
        header:SetFullWidth(true)
        if header.label and header.label.SetFontObject then
            header.label:SetFontObject(GameFontNormalLarge)
        end
        header:SetText(("%s  |cffaaaaaa(Bids: %d)|r"):format(itemLink, CountRealBids(item.bids)))
        scrollContainer:AddChild(header)

        -- sortuj odpowiedzi
        local sorted = {}
        for _, r in ipairs(item.bids or {}) do
            local choice = (r.choice or r.response)
            if choice ~= "PASS" then
                local ep, gp, pr = RaidTrack.GetEPGP(r.from)
                table.insert(sorted, { from = r.from, choice = choice, ep = ep, gp = gp, pr = pr })
            else
                RaidTrack.AddDebugMessage("Skipping response from " .. tostring(r.from) .. " (PASS)")
            end
        end

        local priorityOrder = { BIS = 1, UP = 2, OFF = 3, DIS = 4, TMOG = 5, PASS = 6 }
        table.sort(sorted, function(a, b)
            local ar = priorityOrder[a.choice] or 7
            local br = priorityOrder[b.choice] or 7
            if ar ~= br then return ar < br end
            return (a.pr or 0) > (b.pr or 0)
        end)

        for _, r in ipairs(sorted) do
            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")

            local _, class = UnitClass(r.from)
            local color = RAID_CLASS_COLORS[class or ""] or { r = 1, g = 1, b = 1 }
            local coloredName = string.format("|cff%02x%02x%02x%s|r",
                math.floor((color.r or 1) * 255),
                math.floor((color.g or 1) * 255),
                math.floor((color.b or 1) * 255),
                r.from)

            local icon = AceGUI:Create("Icon")
            icon:SetImageSize(18, 18)
            local coords = CLASS_ICON_TCOORDS[class or "WARRIOR"] or { 0, 1, 0, 1 }
            icon:SetImage("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", unpack(coords))
            icon:SetRelativeWidth(0.08)
            row:AddChild(icon)

            local nameLabel = AceGUI:Create("Label")
            nameLabel:SetText(coloredName)
            nameLabel:SetRelativeWidth(0.22)
            if nameLabel.label and nameLabel.label.SetFontObject then
                nameLabel.label:SetFontObject(GameFontNormal)
            end
            row:AddChild(nameLabel)

            local epLabel = AceGUI:Create("Label")
            epLabel:SetText(tostring(r.ep or 0))
            epLabel:SetRelativeWidth(0.1)
            if epLabel.label and epLabel.label.SetFontObject then
                epLabel.label:SetFontObject(GameFontNormal)
            end
            row:AddChild(epLabel)

            local gpLabel = AceGUI:Create("Label")
            gpLabel:SetText(tostring(r.gp or 0))
            gpLabel:SetRelativeWidth(0.1)
            if gpLabel.label and gpLabel.label.SetFontObject then
                gpLabel.label:SetFontObject(GameFontNormal)
            end
            row:AddChild(gpLabel)

            local prLabel = AceGUI:Create("Label")
            prLabel:SetText(string.format("%.2f", r.pr or 0))
            prLabel:SetRelativeWidth(0.1)
            if prLabel.label and prLabel.label.SetFontObject then
                prLabel.label:SetFontObject(GameFontNormal)
            end
            row:AddChild(prLabel)

            local respLabel = AceGUI:Create("Label")
            respLabel:SetText(r.choice or "?")
            respLabel:SetRelativeWidth(0.15)
            if respLabel.label and respLabel.label.SetFontObject then
                respLabel.label:SetFontObject(GameFontNormal)
            end
            row:AddChild(respLabel)

            local assignBtn = AceGUI:Create("Button")
            assignBtn:SetRelativeWidth(0.15)
            if assignBtn.text and assignBtn.text.SetFontObject then
                assignBtn.text:SetFontObject(GameFontNormal)
            end

            if item.assignedTo == r.from then
                assignBtn:SetText("Assigned")
                assignBtn:SetDisabled(true)
            else
                assignBtn:SetText("Assign")
                assignBtn:SetCallback("OnClick", function()
                    local player = r.from
                    local itemID = item.itemID
                    local link = item.link or ("item:" .. tostring(itemID))
                    local gp = tonumber(item.gp) or 0

                    if item.assignedTo then
                        local old = item.assignedTo
                        RaidTrack.AddDebugMessage("Reassigning " .. link .. " from " .. old .. " to " .. player)
                        -- usuń poprzedni wpis z lootHistory
                        RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}
                        for i = #RaidTrackDB.lootHistory, 1, -1 do
                            local e = RaidTrackDB.lootHistory[i]
                            if e and e.player == old and e.item == link and e.boss == "Auction" then
                                table.remove(RaidTrackDB.lootHistory, i)
                                break
                            end
                        end
                        -- oddaj GP poprzedniemu
                        RaidTrack.LogEPGPChange(old, 0, -gp, "Auction Revert")
                    else
                        RaidTrack.AddDebugMessage("Assigning " .. link .. " to " .. player .. " for " .. gp .. " GP")
                    end

                    item.assignedTo = player
                    item.awaitingTrade = true
                    item.delivered = false

                    RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}
                    local lastId = (#RaidTrackDB.lootHistory > 0) and RaidTrackDB.lootHistory[#RaidTrackDB.lootHistory].id or 0
                    table.insert(RaidTrackDB.lootHistory, {
                        id = lastId + 1,
                        time = date("%H:%M:%S"),
                        timestamp = time(),
                        player = player,
                        item = link,
                        boss = "Auction",
                        gp = gp
                    })

                    RaidTrack.LogEPGPChange(player, 0, gp, "Auction")

                    RaidTrack.UpdateLeaderAuctionUI(auctionID)
                    if RaidTrack.RefreshAuctionLeaderTabs then
                        RaidTrack.RefreshAuctionLeaderTabs()
                    end
                end)
            end

            row:AddChild(assignBtn)
            scrollContainer:AddChild(row)
        end
    end

    if RaidTrack.RefreshAuctionLeaderTabs then
        RaidTrack.RefreshAuctionLeaderTabs()
    end

    RaidTrack.AddDebugMessage("Combined UI updated for auctionID: " .. tostring(auctionID))
end
