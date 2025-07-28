-- UI/EPGPTab.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local i = 2
local frame = RaidTrack.tabFrames[i]
RaidTrack.epgpTab = frame

local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
refreshButton:SetSize(80, 25)
refreshButton:SetPoint("TOPLEFT", 10, -10)
refreshButton:SetText("Refresh")

local epgpList = {}

local function UpdateEPGPList()
    for _, row in ipairs(epgpList) do
        for _, v in pairs(row) do
            if v and v.Hide then v:Hide() end
        end
    end
    epgpList = {}
    if not RaidTrackDB.epgp then return end

    local index = 0
    for player, data in pairs(RaidTrackDB.epgp) do
        local yOffset = -50 - index * 30

        local nameFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", 10, yOffset)
        local pr = (data.gp and data.gp > 0) and (data.ep / data.gp) or 0
        nameFS:SetText(string.format("%s  |  EP: %d  GP: %d  PR: %.2f", player, data.ep or 0, data.gp or 0, pr))

        local epBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        epBtn:SetSize(30, 20)
        epBtn:SetPoint("LEFT", nameFS, "RIGHT", 10, 0)
        epBtn:SetText("+EP")
        epBtn:SetScript("OnClick", function()
            RaidTrack.LogEPGPChange(player, 10, 0, "EP Button")
            UpdateEPGPList()
            if RaidTrackDB.settings.autoSync then
                RaidTrack.SendSyncData()
            end
        end)

        local gpBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        gpBtn:SetSize(30, 20)
        gpBtn:SetPoint("LEFT", epBtn, "RIGHT", 5, 0)
        gpBtn:SetText("+GP")
        gpBtn:SetScript("OnClick", function()
            RaidTrack.LogEPGPChange(player, 0, 10, "GP Button")
            UpdateEPGPList()
            if RaidTrackDB.settings.autoSync then
                RaidTrack.SendSyncData()
            end
        end)

        table.insert(epgpList, { nameFS = nameFS, epBtn = epBtn, gpBtn = gpBtn })
        index = index + 1
    end
end

refreshButton:SetScript("OnClick", function()
    local ok, err = pcall(UpdateEPGPList)
    if not ok then
        RaidTrack.AddDebugMessage("UpdateEPGPList error: " .. tostring(err))
    end
end)

frame:SetScript("OnShow", function()
    local ok, err = pcall(UpdateEPGPList)
    if not ok then
        RaidTrack.AddDebugMessage("UpdateEPGPList error: " .. tostring(err))
    end
end)

RaidTrack.UpdateEPGPList = UpdateEPGPList