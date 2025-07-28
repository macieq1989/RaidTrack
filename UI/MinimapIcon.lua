local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local LDB = LibStub("LibDataBroker-1.1"):NewDataObject("RaidTrack", {
    type = "data source",
    text = "RaidTrack",
    icon = "Interface\\ICONS\\inv_helmet_06",
    OnClick = function()
        if RaidTrack.ToggleMainFrame then
            RaidTrack.ToggleMainFrame()
        end
    end,
    OnTooltipShow = function(tt)
        tt:AddLine("RaidTrack")
        if RaidTrack.GetSyncTimeAgo then
            tt:AddLine("Last sync: " .. RaidTrack.GetSyncTimeAgo())
        end
    end
})

local icon = LibStub("LibDBIcon-1.0")
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, name)
    if name ~= addonName then return end

    RaidTrackDB.minimap = RaidTrackDB.minimap or {
        minimapPos = 220,
        hide = false
    }

    if not icon:IsRegistered("RaidTrack") then
        icon:Register("RaidTrack", LDB, RaidTrackDB.minimap)
    end
end)
