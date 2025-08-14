local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local icon = LibStub("LibDBIcon-1.0")
local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("RaidTrack", {
    type = "data source",
    text = "RaidTrack",
    icon = "Interface\\ICONS\\inv_helmet_06",
    OnClick = function(_, button)
        if button == "LeftButton" then
            if RaidTrack.ToggleMainFrame then
                RaidTrack:ToggleMainWindow()
            end
        elseif button == "RightButton" then
            if RaidTrack.menu and RaidTrack.menu:IsShown() then
                RaidTrack.menu:Hide()
                GameTooltip:Hide()
            else
                GameTooltip:Hide()
                RaidTrack.ShowContextMenu()
            end
        end
    end,

    OnTooltipShow = function(tt)
        if RaidTrack.menu and RaidTrack.menu:IsShown() then
            return
        end -- Don't show tooltip when menu is visible
        tt:AddLine("RaidTrack")
        if RaidTrack.GetSyncTimeAgo then
            tt:AddLine("Last sync: " .. RaidTrack.GetSyncTimeAgo())
        end
    end
})

function RaidTrack.ShowContextMenu()
    if not RaidTrack.menu then
        local menu = CreateFrame("Frame", "RaidTrackMinimapMenu", UIParent, "BackdropTemplate")

        -- Layout constants
        local MENU_WIDTH       = 140
        local PADDING          = 10
        local BUTTON_HEIGHT    = 20
        local BUTTON_SPACING   = 5  -- visual gap between buttons
        local STEP             = BUTTON_HEIGHT + BUTTON_SPACING

        -- Backdrop & behavior
        menu:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        menu:SetBackdropColor(0, 0, 0, 0.8)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetToplevel(true)

        local buttons = {}

        local function CreateMenuButton(text, onClick, index)
            local btn = CreateFrame("Button", nil, menu)
            btn:SetSize(MENU_WIDTH - 2*PADDING, BUTTON_HEIGHT)
            -- Top anchored, each next button goes lower by STEP
            btn:SetPoint("TOP", 0, -PADDING - (index-1)*STEP)

            local fontString = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fontString:SetPoint("CENTER")
            fontString:SetText(text)
            btn.text = fontString

            btn:SetScript("OnEnter", function()
                fontString:SetTextColor(1, 0.8, 0.2)
            end)
            btn:SetScript("OnLeave", function()
                fontString:SetTextColor(1, 1, 1)
            end)

            btn:SetScript("OnClick", function()
                menu:Hide()
                onClick()
            end)

            table.insert(buttons, btn)
            return btn
        end

        -- Rank gate: only some options for authorized ranks
        local gate = RaidTrack.IsPlayerAllowedByRank and RaidTrack.IsPlayerAllowedByRank()

        local idx = 1
        local function Add(text, func)
            CreateMenuButton(text, func, idx)
            idx = idx + 1
        end

        -- ZAWSZE dostępne: jedno "Open Window"
        Add("Open Window", function()
            if RaidTrack.ShowMain then
                RaidTrack.ShowMain("epgp") -- jeśli masz routing po zakładkach, zostawiam to jak było
            else
                RaidTrack:ToggleMainWindow()
            end
        end)

        -- Dla uprawnionych: Manual Sync i Auction Panel
        if gate then
            Add("Manual Sync", function()
                local ok, err = pcall(RaidTrack.SendSyncData)
                if not ok then
                    RaidTrack.AddDebugMessage("Sync error: " .. tostring(err))
                else
                    RaidTrack.AddDebugMessage("Manual sync triggered.")
                end
            end)

            Add("Auction Panel", function()
                if RaidTrack.OpenAuctionLeaderUI then
                    RaidTrack:OpenAuctionLeaderUI()
                else
                    RaidTrack.AddDebugMessage("Auction window not available.")
                end
            end)
        end

        -- Auto-size wysokości na podstawie liczby przycisków
        local count = #buttons
        if count < 1 then count = 1 end
        local contentHeight = PADDING + (count * BUTTON_HEIGHT) + ((count - 1) * BUTTON_SPACING) + PADDING
        menu:SetSize(MENU_WIDTH, contentHeight)

        -- Klik poza menu chowa je
        local listener = CreateFrame("Frame", nil, UIParent)
        listener:SetAllPoints(UIParent)
        listener:EnableMouse(true)
        listener:SetFrameStrata("TOOLTIP")
        listener:SetScript("OnMouseDown", function()
            menu:Hide()
            listener:Hide()
        end)

        menu:SetScript("OnHide", function()
            listener:Hide()
        end)

        RaidTrack.menu = menu
        RaidTrack.menuListener = listener
    end

    local menu = RaidTrack.menu
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x / scale, y / scale - 5)
    menu:Show()
    RaidTrack.menuListener:Show()
end

-- Initialization
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name ~= addonName then
        return
    end
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.minimap = RaidTrackDB.minimap or { minimapPos = 220, hide = false }

    if not icon:IsRegistered("RaidTrack") then
        icon:Register("RaidTrack", LDB, RaidTrackDB.minimap)
    end
end)
