-- SettingsTab.lua
local addonName, RaidTrack = ...

-- Ensure core structures exist
RaidTrack.tabs      = RaidTrack.tabs      or {}
RaidTrack.tabFrames = RaidTrack.tabFrames or {}

-- Abort if main frame is missing
if not RaidTrack.mainFrame then return end

-- Tab index for Settings
local i = 4

-- Get or create the Settings tab frame
local frame = RaidTrack.tabFrames[i]
if not frame then
    frame = CreateFrame("Frame", nil, RaidTrack.mainFrame)
    frame:SetSize(960, 700)
    frame:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 20, -60)
    frame:Hide()
    RaidTrack.tabFrames[i] = frame
end
RaidTrack.settingsTab = frame

-- Title
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOPLEFT", 10, -10)
title:SetText("Sync Settings")

-- Ensure settings table exists
RaidTrackDB.settings = RaidTrackDB.settings or {}

-- Officer only checkbox
local offCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
offCB:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
offCB.text:SetText("Officers only")
offCB:SetScript("OnClick", function(self)
    RaidTrackDB.settings.officerOnly = self:GetChecked()
end)

-- Auto-sync checkbox
local autoCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
autoCB:SetPoint("TOPLEFT", offCB, "BOTTOMLEFT", 0, -20)
autoCB.text:SetText("Auto-accept from officers")
autoCB:SetScript("OnClick", function(self)
    RaidTrackDB.settings.autoSync = self:GetChecked()
end)

-- Min rank dropdown label
local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
lbl:SetPoint("TOPLEFT", autoCB, "BOTTOMLEFT", 0, -30)
lbl:SetText("Min guild rank:")

-- Min rank dropdown
local rankDD = CreateFrame("Frame", "RTRankDD", frame, "UIDropDownMenuTemplate")
rankDD:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", -15, -5)
UIDropDownMenu_SetWidth(rankDD, 180)
UIDropDownMenu_SetText(rankDD, "Select rank")

local function UpdateRankDropdown()
    UIDropDownMenu_Initialize(rankDD, function(self, level)
        local seen = {}
        for j = 1, GetNumGuildMembers() do
            local _, rankName, ridx = GetGuildRosterInfo(j)
            if rankName and not seen[rankName] then
                seen[rankName] = true
                local info = UIDropDownMenu_CreateInfo()
                info.text  = rankName
                info.value = ridx
                info.func = function(self)
    if not RaidTrack.IsOfficer() then
        RaidTrack.AddDebugMessage("Only officers can change sync rank.")
        return
    end
    UIDropDownMenu_SetSelectedValue(rankDD, ridx)
    UIDropDownMenu_SetText(rankDD, rankName)
    RaidTrackDB.settings.minSyncRank = ridx
    RaidTrack.BroadcastSettings() -- nowa funkcja
end

                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
end


-- Debug log label
local dbgLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
dbgLabel:SetPoint("TOPLEFT", rankDD, "BOTTOMLEFT", 15, -30)
dbgLabel:SetText("Debug log:")

-- Debug log scrollframe and editbox
local dbgScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
dbgScroll:SetSize(960, 400)
dbgScroll:SetPoint("TOPLEFT", dbgLabel, "BOTTOMLEFT", 0, -5)
dbgScroll.ScrollBar.ThumbTexture:SetWidth(16)

local dbgEdit = CreateFrame("EditBox", nil, dbgScroll)
dbgEdit:SetMultiLine(true)
dbgEdit:SetFontObject("ChatFontNormal")
dbgEdit:SetWidth(940)
dbgEdit:SetAutoFocus(false)
dbgEdit:SetScript("OnEscapePressed", dbgEdit.ClearFocus)
dbgScroll:SetScrollChild(dbgEdit)

-- Patch AddDebugMessage to update UI
do
    local orig = RaidTrack.AddDebugMessage
    function RaidTrack.AddDebugMessage(msg)
        orig(msg)
        dbgEdit:SetText(table.concat(RaidTrack.debugMessages or {}, "\n"))
    end
end

-- Manual Sync button
local syncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
syncBtn:SetSize(160, 25)
syncBtn:SetPoint("TOPLEFT", dbgScroll, "BOTTOMLEFT", 0, -10)
syncBtn:SetText("Manual Sync")
syncBtn:SetScript("OnClick", function()
    local ok, err = pcall(RaidTrack.SendSyncData)
    if not ok then
        RaidTrack.AddDebugMessage("Sync error: " .. tostring(err))
    else
        RaidTrack.AddDebugMessage("Manual sync triggered.")
    end
end)

-- OnShow: initialize controls
frame:SetScript("OnShow", function()
    local s = RaidTrackDB.settings
    offCB:SetChecked(s.officerOnly ~= false)
    autoCB:SetChecked(s.autoSync ~= false)
    UpdateRankDropdown()
    if s.minSyncRank then
        UIDropDownMenu_SetSelectedValue(rankDD, s.minSyncRank)
        -- Znajdź i wyświetl nazwę rangi odpowiadającą temu indeksowi
        for j = 1, GetNumGuildMembers() do
            local _, rankName, ridx = GetGuildRosterInfo(j)
            if ridx == s.minSyncRank then
                UIDropDownMenu_SetText(rankDD, rankName)
                break
            end
        end
    end
end)

