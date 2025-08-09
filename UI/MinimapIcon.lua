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
        menu:SetSize(140, 120)

        menu:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = {
                left = 4,
                right = 4,
                top = 4,
                bottom = 4
            }
        })
        menu:SetBackdropColor(0, 0, 0, 0.8)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetToplevel(true)

        local function CreateMenuButton(text, onClick, yOffset)
            local btn = CreateFrame("Button", nil, menu)
            btn:SetSize(120, 20)
            btn:SetPoint("TOP", 0, yOffset)

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

            return btn
        end

        -- Gating po randze gildii: EPGP zawsze, reszta tylko dla uprawnionych
        local gate = RaidTrack.IsPlayerAllowedByRank and RaidTrack.IsPlayerAllowedByRank()

        local y = -10
        local function Add(text, func)
            CreateMenuButton(text, func, y)
            y = y - 25
        end

        -- ZAWSZE dostępne: EPGP
        Add("Open EPGP", function()
            if RaidTrack.ShowMain then
                RaidTrack.ShowMain("epgp")
            else
                RaidTrack:ToggleMainWindow()
            end
        end)

        if gate then
            Add("Open Window", function()
                RaidTrack:ToggleMainWindow()
            end)

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

        Add("Hide Icon", function()
            RaidTrackDB.minimap.hide = true
            LibStub("LibDBIcon-1.0"):Hide("RaidTrack")
        end)

        -- Hide menu when clicking outside
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
    RaidTrackDB.minimap = RaidTrackDB.minimap or {
        minimapPos = 220,
        hide = false
    }

    if not icon:IsRegistered("RaidTrack") then
        icon:Register("RaidTrack", LDB, RaidTrackDB.minimap)
    end
end)
