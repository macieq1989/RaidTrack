local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:CreateMainFrame()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("RaidTrack")
    frame:SetLayout("Fill")
    frame:SetWidth(800)
    frame:SetHeight(600)
    frame:EnableResize(false)
    self.mainFrame = frame

    local tabs = {
        { text = "Raid", value = "raidTab" },
        { text = "EPGP", value = "epgpTab" },
        { text = "Loot", value = "lootTab" },
        { text = "Guild", value = "guildTab" },
        { text = "Settings", value = "settingsTab" },
    }

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetTabs(tabs)
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetLayout("Fill")

tabGroup:SetCallback("OnGroupSelected", function(container, event, tabKey)
    if tabKey ~= "raidTab" and RaidTrack.DeactivateRaidTab then
        RaidTrack.DeactivateRaidTab()
        RaidTrack.ClearRaidSelection()
    end

    container:ReleaseChildren()
    if RaidTrack["Render_" .. tabKey] then
        RaidTrack["Render_" .. tabKey](RaidTrack, container)
    end
end)


    frame:AddChild(tabGroup)
    tabGroup:SelectTab("raidTab")

    -- Przycisk Refresh obok Close
    local refreshBtn = CreateFrame("Button", nil, frame.frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetPoint("TOPRIGHT", frame.frame, "TOPRIGHT", -40, -30)
    refreshBtn:SetScript("OnClick", function()
        RaidTrack.UpdateRaidList()
    end)
end

function RaidTrack:ToggleMainWindow()
    if self.mainFrame and self.mainFrame.frame and self.mainFrame.frame:IsShown() then
        self.mainFrame.frame:Hide()
    else
        if not self.mainFrame then
            self:CreateMainFrame()
        else
            self.mainFrame.frame:Show()
        end
    end
end

SLASH_RAIDTRACK1 = "/raidtrack"
SlashCmdList["RAIDTRACK"] = function()
    RaidTrack:ToggleMainWindow()
end
