local AceGUI = LibStub("AceGUI-3.0")
local addonPrefix = "RaidTrackAuction"

function RaidTrack.OpenAuctionParticipantUI(auctionData)
    if not auctionData or type(auctionData) ~= "table" or not auctionData.items or #auctionData.items == 0 then
        RaidTrack.AddDebugMessage("Invalid auctionData received by participant UI.")
        return
    end

    RaidTrack.AddDebugMessage("OpenAuctionParticipantUI() called")
    print("==== OpenAuctionParticipantUI CALLED ====")

    local updatedItems = {}
    local auctionEndTime = (auctionData.started or time()) + (auctionData.duration or 0)
    local frame
    local isWindowOpen = false

    -- Load item link from cache if available; don't overwrite with "ItemID: X"
    local function UpdateItemData(item)
        local itemLink = select(2, GetItemInfo(item.itemID))
        item.link = itemLink -- may be nil if not yet cached
    end

    local function UpdateAuctionTime()
        if not frame then return end
        local remainingTime = math.max(0, auctionEndTime - time())
        if remainingTime <= 0 then
            frame:SetTitle("RaidTrack Auction - Time's up!")
        else
            local minutes = math.floor(remainingTime / 60)
            local seconds = remainingTime % 60
            frame:SetTitle(string.format("RaidTrack Auction - Time remaining: %02d:%02d", minutes, seconds))
        end
    end

    local function OpenAuctionWindowIfReady()
        if isWindowOpen then return end
        isWindowOpen = true

        -- Window
        frame = AceGUI:Create("Frame")
        frame:SetTitle("RaidTrack Auction")
        frame:SetStatusText("Select your response for each item")
        frame:SetLayout("List")
        frame:SetWidth(520)
        frame:SetHeight(400)
        frame:EnableResize(false)
        RaidTrack.auctionParticipantWindow = frame

        -- Anchor to right
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)

        -- Scroll
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll:SetFullWidth(true)
        scroll:SetFullHeight(true)
        frame:AddChild(scroll)

        -- Build items
        local maxVisibleItems = 5
        local itemHeight = 84
        local scrollHeight = math.min(#updatedItems, maxVisibleItems) * itemHeight
        frame:SetHeight(scrollHeight + 90)

        for i, item in ipairs(updatedItems) do
            RaidTrack.AddDebugMessage(string.format(
                "ParticipantUI item %d: id=%s, gp=%s, link=%s",
                i, tostring(item.itemID), tostring(item.gp), tostring(item.link)
            ))

            local itemGroup = AceGUI:Create("InlineGroup")
            itemGroup:SetFullWidth(true)
            itemGroup:SetLayout("Flow")
            scroll:AddChild(itemGroup)

            -- Interactive title (hoverable)
            local titleText = item.link or ("ItemID: " .. tostring(item.itemID))
            local titleLabel = AceGUI:Create("InteractiveLabel")
            titleLabel:SetText(titleText)
            titleLabel:SetFullWidth(true)
            titleLabel:SetFontObject(GameFontHighlight)

            -- Tooltip on hover: prefer link, fallback to ID
            titleLabel:SetCallback("OnEnter", function(widget)
                local thing = item.link or item.itemID
                if not thing then return end

                GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                local shown = false
                if type(thing) == "number" then
                    GameTooltip:SetItemByID(thing)
                    shown = true
                elseif type(thing) == "string" then
                    if thing:find("|Hitem:", 1, true) then
                        GameTooltip:SetHyperlink(thing)
                        shown = true
                    else
                        local asNum = tonumber(thing)
                        if asNum then
                            GameTooltip:SetItemByID(asNum)
                            shown = true
                        end
                    end
                end

                if shown then
                    GameTooltip:Show()
                    if (IsModifiedClick and IsModifiedClick("COMPAREITEM")) or (GetCVarBool and GetCVarBool("alwaysCompareItems")) then
                        GameTooltip_ShowCompareItem(GameTooltip)
                    end
                else
                    GameTooltip:Hide()
                end
            end)

            titleLabel:SetCallback("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
                if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
                if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
            end)

            itemGroup:AddChild(titleLabel)

            -- GP label
            local gpLabel = AceGUI:Create("Label")
            gpLabel:SetText("GP: " .. tostring(item.gp or "?"))
            gpLabel:SetWidth(60)
            itemGroup:AddChild(gpLabel)

            -- Buttons
            local function CreateResponseButton(label, responseType, allButtonsTable)
                local btn = AceGUI:Create("Button")
                btn:SetText(label)
                btn:SetWidth(64)
                btn:SetCallback("OnClick", function()
                    if time() > auctionEndTime then
                        RaidTrack.AddDebugMessage("Auction expired, response ignored.")
                        return
                    end

                    local ep, gp, pr = RaidTrack.GetEPGP(UnitName("player"))
                    item.responses = item.responses or {}
                    item.responses[UnitName("player")] = {
                        player = UnitName("player"),
                        response = responseType,
                        ep = ep, gp = gp, pr = pr
                    }

                    for _, otherBtn in ipairs(allButtonsTable) do
                        otherBtn:SetDisabled(false)
                    end
                    btn:SetDisabled(true)

                    RaidTrack.SendAuctionResponseChunked(auctionData.auctionID, item.itemID, responseType)
                end)
                return btn
            end

            local buttons = {}
            table.insert(buttons, CreateResponseButton("BIS",  "BIS",  buttons))
            table.insert(buttons, CreateResponseButton("UP",   "UP",   buttons))
            table.insert(buttons, CreateResponseButton("Off",  "OFF",  buttons))
            table.insert(buttons, CreateResponseButton("Dis",  "DIS",  buttons))
            table.insert(buttons, CreateResponseButton("Tmog", "TMOG", buttons))
            table.insert(buttons, CreateResponseButton("Pass", "PASS", buttons))

            for _, btn in ipairs(buttons) do
                itemGroup:AddChild(btn)
            end
        end

        -- start ticker AFTER frame exists
        C_Timer.NewTicker(1, UpdateAuctionTime)
        UpdateAuctionTime()
    end

    -- Preload items
    for _, item in ipairs(auctionData.items) do
        if item.itemID and item.itemID ~= 0 then
            RaidTrack.AddDebugMessage("Loading data for item ID: " .. tostring(item.itemID))
            UpdateItemData(item)
            table.insert(updatedItems, item)
        else
            RaidTrack.AddDebugMessage("Invalid itemID=" .. tostring(item.itemID) .. ", skipping.")
        end
    end

    OpenAuctionWindowIfReady()
end
