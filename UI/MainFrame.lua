-- UI/MainFrame.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- Create main frame
if not RaidTrack.mainFrame then
    local f = CreateFrame("Frame", "RaidTrackFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(1000, 800)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetResizable(true)
    if f.SetMinResize then
    f:SetMinResize(800, 600)
    f:SetMaxResize(1600, 1200)
end
    -- Inicjalizacja zakończona, przypisanie i ukrycie
    RaidTrack.mainFrame = f
    f:Hide()  -- 

    f:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then self:StartSizing() end
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then self:StopMovingOrSizing() end
    end)

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFontObject("GameFontHighlight")
    f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 10, 0)
    f.title:SetText("RaidTrack")

    f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT")

    RaidTrack.mainFrame = f
end

-- Tab button logic
RaidTrack.tabs = RaidTrack.tabs or {}
RaidTrack.tabFrames = RaidTrack.tabFrames or {}

local tabNames = {"Raid", "EPGP", "Loot", "Settings", "Guild"}
for i, name in ipairs(tabNames) do
    local btn = CreateFrame("Button", nil, RaidTrack.mainFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 25)
    btn:SetText(name)
    btn:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 10 + (i - 1) * 85, -30)
    btn:SetScript("OnClick", function() RaidTrack.ShowTab(i) end)
    RaidTrack.tabs[i] = btn

    local pane = CreateFrame("Frame", nil, RaidTrack.mainFrame)
    pane:SetSize(960, 700)
    pane:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 20, -60)
    pane:Hide()
    RaidTrack.tabFrames[i] = pane
end

function RaidTrack.ShowTab(index)
    for i, frame in pairs(RaidTrack.tabFrames) do
        if frame then frame:Hide() end
    end
    for i, btn in pairs(RaidTrack.tabs) do
        if btn then btn:UnlockHighlight() end
    end
    if RaidTrack.tabFrames[index] then
        RaidTrack.tabFrames[index]:Show()
    end
    if RaidTrack.tabs[index] then
        RaidTrack.tabs[index]:LockHighlight()
    end
end

-- Slash command to toggle UI
SLASH_RAIDTRACK1 = "/raidtrack"
SlashCmdList["RAIDTRACK"] = function()
    if RaidTrack.mainFrame:IsShown() then
        RaidTrack.mainFrame:Hide()
    else
        RaidTrack.mainFrame:Show()
        RaidTrack.ShowTab(1)
    end
end

function RaidTrack.ToggleMainFrame()
    if not RaidTrack.mainFrame then return end
    if RaidTrack.mainFrame:IsShown() then
        RaidTrack.mainFrame:Hide()
    else
        RaidTrack.mainFrame:Show()
    end
end
