local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- helper: policz realne bidy (bez PASS)
local function CountRealBids(bids)
    local c = 0
    for _, b in ipairs(bids or {}) do
        if (b.choice or b.response) ~= "PASS" then
            c = c + 1
        end
    end
    return c
end

-- Zwraca bazowe itemID niezależnie od bonusów/variantów
local function BaseItemIDFrom(any)
    if type(any) == "number" then return any end
    if not any then return nil end
    local itemID = nil
    if type(any) == "string" and any:find("item:") then
        itemID = select(1, GetItemInfoInstant(any))
    else
        -- nazwa lub ID w stringu
        itemID = tonumber(any) or select(1, GetItemInfoInstant(any))
    end
    return itemID
end

local function CountRealBids(bids)
    local c = 0
    for _, b in ipairs(bids or {}) do
        if (b.choice or b.response) ~= "PASS" then c = c + 1 end
    end
    return c
end

function RaidTrack.NotifyBidUpdate(auctionID)
    -- wywołuj to, gdy zapisujesz/aktualizujesz bid (np. w handlerze wiadomości z klienta)
    if RaidTrack.RefreshAuctionLeaderTabs then
        RaidTrack.RefreshAuctionLeaderTabs()
    end
end


function RaidTrack:OpenAuctionLeaderUI()
    -- init
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

    self.currentAuctions = {}
    self._tabAuctionIDs = {}          -- map: local index -> auctionID (Start THIS item)
    self._currentAllAuctionID = nil   -- auctionID dla Start ALL

    -- UI: main frame
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

    -- Inputs
    local itemInput = AceGUI:Create("EditBox")
    itemInput:SetLabel("Item Link or Name")
    itemInput:SetFullWidth(true)

    local gpInput = AceGUI:Create("EditBox")
    gpInput:SetLabel("GP Cost")
    gpInput:SetText("100")
    gpInput:SetFullWidth(true)

    -- czas aukcji (sekundy)
    local durationInput = AceGUI:Create("EditBox")
    durationInput:SetLabel("Auction duration (sec)")
    durationInput:SetText("30")
    durationInput:SetFullWidth(true)
    durationInput:SetCallback("OnEnterPressed", function()
        local v = tonumber(durationInput:GetText())
        if not v or v <= 0 then durationInput:SetText("30") end
    end)

    -- add item
    local addItemBtn = AceGUI:Create("Button")
    addItemBtn:SetText("Add Item")
    addItemBtn:SetFullWidth(true)

    -- tabs for items
    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetHeight(260)
    tabGroup:SetTabs({})

    -- stan selekcji i blokada re-entrancy
    self._selectedTabValue = self._selectedTabValue or nil
    self._inRefreshTabs = false

    -- live count z aktywnych aukcji (solo -> all -> lokalne)
    local function GetLiveBidCountForIndex(idx)
    local tabItem = self.currentAuctions[idx]
    if not tabItem then return 0 end

    -- bazowy ID z pozycji w tabie
    local wantedBase = BaseItemIDFrom(tabItem.link or ("item:"..tostring(tabItem.itemID)))

    -- 1) SOLO aukcja tego taba?
    local soloID = self._tabAuctionIDs[idx]
    if soloID and RaidTrack.activeAuctions and RaidTrack.activeAuctions[soloID] then
        local it = (RaidTrack.activeAuctions[soloID].items or {})[1]
        return CountRealBids(it and it.bids)
    end

    -- 2) ALL aukcja – spróbuj dopasować po bazowym ID; jak nie znajdziesz, użyj indeksu
    local allID = self._currentAllAuctionID
    if allID and RaidTrack.activeAuctions and RaidTrack.activeAuctions[allID] then
        local items = RaidTrack.activeAuctions[allID].items or {}
        local chosen = nil

        -- najpierw po bazowym ID (pewniejsze niż indeks)
        if wantedBase then
            for _, it in ipairs(items) do
                local base = BaseItemIDFrom(it.link or ("item:"..tostring(it.itemID)))
                if base and base == wantedBase then chosen = it; break end
            end
        end
        -- fallback: po indeksie (gdy struktura się zgadza)
        if not chosen then chosen = items[idx] end

        return CountRealBids(chosen and chosen.bids)
    end

    -- 3) Fallback: przeszukaj WSZYSTKIE aktywne aukcje po bazowym ID (gdy np. okno odpowiedzi otwarte dla innego ID)
    if RaidTrack.activeAuctions and wantedBase then
        for _, auc in pairs(RaidTrack.activeAuctions) do
            for _, it in ipairs(auc.items or {}) do
                local base = BaseItemIDFrom(it.link or ("item:"..tostring(it.itemID)))
                if base and base == wantedBase then
                    return CountRealBids(it.bids)
                end
            end
        end
    end

    -- 4) Nie ma aktywnej aukcji – licz lokalne (przed startem)
    return CountRealBids(tabItem.bids)
end


local function RefreshTabs()
    if self._inRefreshTabs then return end
    self._inRefreshTabs = true

    -- zbuduj listę tabów
    local tabs = {}
    for idx, auction in ipairs(self.currentAuctions) do
        local itemID = auction.itemID
        local itemLink = itemID and select(2, GetItemInfo(itemID)) or ("Item " .. tostring(idx))
        local bidCount = GetLiveBidCountForIndex(idx)
        table.insert(tabs, {
            text  = (itemLink or ("Item "..idx)) .. " (Bids: " .. bidCount .. ")",
            value = tostring(idx)
        })
    end

    -- brak tabów: wyczyść wszystko i wyjdź
    if #tabs == 0 then
        tabGroup:SetTabs({})
        if tabGroup.selected ~= nil then
            tabGroup:SelectTab(nil)        -- bezpieczne: nie wywoła naszego callbacku z zawartością
        end
        self._selectedTabValue = nil
        tabGroup:ReleaseChildren()          -- usuń "Start/Remove" ducha
        self._inRefreshTabs = false
        return
    end

    -- są taby: ustaw i spróbuj zachować dotychczasowy wybór
    tabGroup:SetTabs(tabs)

    local want   = self._selectedTabValue
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


    tabGroup:SetCallback("OnGroupSelected", function(container, event, group)
        container:ReleaseChildren()
        self._selectedTabValue = group

        local idx = tonumber(group)
        local auction = self.currentAuctions[idx]
        if not auction then return end

        -- header + akcje dla pojedynczego itemu
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
            local items = {{
                itemID = auction.itemID,
                gp     = auction.gp,
                link   = select(2, GetItemInfo(auction.itemID)),
                bids   = {}
            }}
            local auctionID = RaidTrack.StartAuction(items, dur)
            self._tabAuctionIDs[idx] = auctionID
            RaidTrack.AddDebugMessage("Started single-item auction idx="..idx.." auctionID="..tostring(auctionID))
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

        -- UWAGA: brak sekcji "Live Bids" i BRAK wywołania RefreshTabs() tutaj.
    end)

    -- start all
    local startAllBtn = AceGUI:Create("Button")
    startAllBtn:SetText("Start Auction for ALL items")
    startAllBtn:SetFullWidth(true)
    startAllBtn:SetCallback("OnClick", function()
        if #self.currentAuctions == 0 then return end
        local dur = tonumber(durationInput:GetText()) or 30
        if dur <= 0 then dur = 30 end
        local auctionID = RaidTrack.StartAuction(self.currentAuctions, dur)
        self._currentAllAuctionID = auctionID
        RaidTrack.AddDebugMessage("Started ALL-items auction auctionID="..tostring(auctionID))
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
        tabGroup:SelectTab(nil)
    end)

    addItemBtn:SetCallback("OnClick", function()
        local itemText = itemInput:GetText()
        local gpCost = tonumber(gpInput:GetText()) or 0
        if itemText == "" then return end

        local itemID = tonumber(string.match(itemText, "item:(%d+)"))
        if not itemID then
            local _, _, _, _, _, _, _, _, _, _, id = GetItemInfo(itemText)
            itemID = id
        end
        if not itemID then
            RaidTrack.AddDebugMessage("Failed to extract/resolve itemID from input: " .. itemText)
            return
        end

        table.insert(self.currentAuctions, { itemID = itemID, gp = gpCost, bids = {} })
        RaidTrack.AddDebugMessage("Adding item to auction: itemID=" .. tostring(itemID) .. ", gp=" .. tostring(gpCost))
        RefreshTabs()
        itemInput:SetText("")
    end)

    -- layout
    mainGroup:AddChild(itemInput)
    mainGroup:AddChild(gpInput)
    mainGroup:AddChild(durationInput)
    mainGroup:AddChild(addItemBtn)
    mainGroup:AddChild(tabGroup)
    mainGroup:AddChild(startAllBtn)
    mainGroup:AddChild(clearBtn)

    RaidTrack.RefreshAuctionLeaderTabs = RefreshTabs
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
        frame:SetStatusText("Auction ID: " .. auctionID)
        frame:SetLayout("Fill")
        frame:SetWidth(780)
        frame:SetHeight(560)
        frame:EnableResize(true)
        RaidTrack.auctionResponseWindows[auctionID] = frame

        if RaidTrack.auctionWindow then
            local anchor = RaidTrack.auctionWindow.frame or RaidTrack.auctionWindow
            if anchor.SetPoint then
                frame.frame:ClearAllPoints()
                frame.frame:SetPoint("TOPRIGHT", anchor.frame or anchor, "TOPLEFT", -10, 0)
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

    for itemIndex, item in ipairs(auctionData.items) do
        local itemLink = item.link or ("ItemID: " .. tostring(item.itemID))
        local header = AceGUI:Create("Label")
        header:SetFullWidth(true)
        header.label:SetFontObject(GameFontNormalLarge)
        header:SetText(("%s  |cffaaaaaa(Bids: %d)|r"):format(itemLink, CountRealBids(item.bids)))
        scrollContainer:AddChild(header)

        -- sort odpowiedzi
        local sortedResponses = {}
        for _, response in ipairs(item.bids or {}) do
            if (response.choice or response.response) ~= "PASS" then
                local ep, gp, pr = RaidTrack.GetEPGP(response.from)
                table.insert(sortedResponses, {
                    from = response.from,
                    choice = (response.choice or response.response),
                    ep = ep,
                    gp = gp,
                    pr = pr
                })
            else
                RaidTrack.AddDebugMessage("Skipping response from " .. tostring(response.from) .. " (PASS)")
            end
        end

        local priorityOrder = {
            BIS = 1,
            UP = 2,
            OFF = 3,
            DIS = 4,
            TMOG = 5,
            PASS = 6
        }
        table.sort(sortedResponses, function(a, b)
            local aRank = priorityOrder[a.choice] or 7
            local bRank = priorityOrder[b.choice] or 7
            if aRank ~= bRank then
                return aRank < bRank
            else
                return (a.pr or 0) > (b.pr or 0)
            end
        end)

        for _, r in ipairs(sortedResponses) do
            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")

            local _, class = UnitClass(r.from)
            local color = RAID_CLASS_COLORS[class or ""] or {
                r = 1,
                g = 1,
                b = 1
            }
            local coloredName = string.format("|cff%02x%02x%02x%s|r", (color.r or 1) * 255, (color.g or 1) * 255,
                (color.b or 1) * 255, r.from)

            local icon = AceGUI:Create("Icon")
            icon:SetImageSize(18, 18)
            local coords = CLASS_ICON_TCOORDS[class or "WARRIOR"] or {0, 1, 0, 1}
            icon:SetImage("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES", unpack(coords))
            icon:SetRelativeWidth(0.08)
            row:AddChild(icon)

            local nameLabel = AceGUI:Create("Label")
            nameLabel:SetText(coloredName)
            nameLabel:SetRelativeWidth(0.22)
            nameLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(nameLabel)

            local epLabel = AceGUI:Create("Label")
            epLabel:SetText(tostring(r.ep or 0))
            epLabel:SetRelativeWidth(0.1)
            epLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(epLabel)

            local gpLabel = AceGUI:Create("Label")
            gpLabel:SetText(tostring(r.gp or 0))
            gpLabel:SetRelativeWidth(0.1)
            gpLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(gpLabel)

            local prLabel = AceGUI:Create("Label")
            prLabel:SetText(string.format("%.2f", r.pr or 0))
            prLabel:SetRelativeWidth(0.1)
            prLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(prLabel)

            local respLabel = AceGUI:Create("Label")
            respLabel:SetText(r.choice or "?")
            respLabel:SetRelativeWidth(0.15)
            respLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(respLabel)

            local assignBtn = AceGUI:Create("Button")
            assignBtn:SetRelativeWidth(0.15)
            if assignBtn.text then
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
                    local link = item.link or "item:" .. itemID
                    local gp = item.gp or 0

                    if item.assignedTo then
                        local old = item.assignedTo
                        RaidTrack.AddDebugMessage("Reassigning " .. link .. " from " .. old .. " to " .. player)
                        for i = #RaidTrackDB.lootHistory, 1, -1 do
                            local e = RaidTrackDB.lootHistory[i]
                            if e and e.player == old and e.item == link and e.boss == "Auction" then
                                table.remove(RaidTrackDB.lootHistory, i)
                                break
                            end
                        end
                        RaidTrack.LogEPGPChange(old, 0, -gp, "Auction Revert")
                    else
                        RaidTrack.AddDebugMessage("Assigning " .. link .. " to " .. player .. " for " .. gp .. " GP")
                    end

                    item.assignedTo = player
                    item.awaitingTrade = true
                    item.delivered = false

                    RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}
                    local lastId = (#RaidTrackDB.lootHistory > 0) and
                                       RaidTrackDB.lootHistory[#RaidTrackDB.lootHistory].id or 0
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

    -- odśwież taby w panelu lidera (licznik bidów)
    if RaidTrack.RefreshAuctionLeaderTabs then
        RaidTrack.RefreshAuctionLeaderTabs()
    end

    RaidTrack.AddDebugMessage("Combined UI updated for auctionID: " .. tostring(auctionID))
end
