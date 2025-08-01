-- UI/MainFrame.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- MainFrame.lua (AceGUI)
local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:CreateMainFrame()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("RaidTrack")
    frame:SetLayout("Fill")
    frame:SetWidth(800)
    frame:SetHeight(600)
    frame:EnableResize(false)
    self.mainFrame = frame

    local tabs = {{
        text = "Raid",
        value = "raidTab"
    }, {
        text = "EPGP",
        value = "epgpTab"
    }, {
        text = "Loot",
        value = "lootTab"
    }, {
        text = "Settings",
        value = "settingsTab"
    }, {
        text = "Guild",
        value = "guildTab"
    }}

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetTabs(tabs)
    tabGroup:SetFullWidth(true) -- dodane
    tabGroup:SetFullHeight(true) -- dodane
    tabGroup:SetLayout("Fill") -- dodane
    tabGroup:SetCallback("OnGroupSelected", function(container, _, tabKey)
        container:ReleaseChildren()
        if RaidTrack["Render_" .. tabKey] then
            RaidTrack["Render_" .. tabKey](RaidTrack, container)
        end
    end)

    frame:AddChild(tabGroup)

    tabGroup:SelectTab("raidTab")
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
