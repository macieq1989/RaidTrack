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
        if self.auctionWindow.frame and not self.auctionWindow.frame:IsShown() then
            self.auctionWindow.frame:Show()
        end
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
        if not auction then
            return
        end

        local label = AceGUI:Create("Label")
        label:SetText("Bids:")
        container:AddChild(label)

        RaidTrack.AddDebugMessage("Auction Item: " .. auction.itemID .. " Bids: " .. tostring(#auction.bids))

        for _, bid in ipairs(auction.bids or {}) do
            local ep, gp, pr = GetEPGP(bid.from)
            local bidLabel = AceGUI:Create("Label")
            bidLabel:SetFullWidth(true)
            bidLabel:SetText(bid.from .. ": " .. bid.response .. " (EP: " .. ep .. ", GP: " .. gp .. ", PR: " ..
                                 string.format("%.2f", pr) .. ")")
            container:AddChild(bidLabel)
        end

        RefreshTabs()
    end)

    local startBtn = AceGUI:Create("Button")
    startBtn:SetText("Start Auction for All")
    startBtn:SetFullWidth(true)
    startBtn:SetCallback("OnClick", function()
        if #self.currentAuctions == 0 then
            return
        end
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
        if itemText == "" then
            return
        end

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
        frame:SetWidth(700)
        frame:SetHeight(550)
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

    for _, item in ipairs(auctionData.items) do
        local itemLink = item.link or ("ItemID: " .. tostring(item.itemID))
        local header = AceGUI:Create("Label")
        header:SetFullWidth(true)
        header.label:SetFontObject(GameFontNormal)
        header:SetText(itemLink)
        scrollContainer:AddChild(header)

        local sortedResponses = {}
        for _, response in ipairs(item.bids or {}) do
            if response.choice ~= "PASS" then
                local ep, gp, pr = GetEPGP(response.from)
                table.insert(sortedResponses, {
                    from = response.from,
                    choice = response.choice,
                    ep = ep,
                    gp = gp,
                    pr = pr
                })
            else
                RaidTrack.AddDebugMessage("Skipping response from " .. response.from .. " (PASS)")
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
                return a.pr > b.pr
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
            local coloredName = string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255,
                r.from)

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
            epLabel:SetText(tostring(r.ep))
            epLabel:SetRelativeWidth(0.1)
            epLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(epLabel)

            local gpLabel = AceGUI:Create("Label")
            gpLabel:SetText(tostring(r.gp))
            gpLabel:SetRelativeWidth(0.1)
            gpLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(gpLabel)

            local prLabel = AceGUI:Create("Label")
            prLabel:SetText(string.format("%.2f", r.pr))
            prLabel:SetRelativeWidth(0.1)
            prLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(prLabel)

            local respLabel = AceGUI:Create("Label")
            respLabel:SetText(r.choice)
            respLabel:SetRelativeWidth(0.15)
            respLabel.label:SetFontObject(GameFontNormal)
            row:AddChild(respLabel)

            assignBtn = AceGUI:Create("Button")
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
                end)
            end

            row:AddChild(assignBtn)
            scrollContainer:AddChild(row)
        end
    end

    RaidTrack.AddDebugMessage("Combined UI updated for auctionID: " .. tostring(auctionID))
end

