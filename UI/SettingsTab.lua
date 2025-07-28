-- SettingsTab.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

RaidTrack.tabs      = RaidTrack.tabs      or {}
RaidTrack.tabFrames = RaidTrack.tabFrames or {}

if not RaidTrack.mainFrame then return end

local i = 4

local frame = RaidTrack.tabFrames[i]
if not frame then
    frame = CreateFrame("Frame", nil, RaidTrack.mainFrame)
    frame:SetSize(960, 700)
    frame:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 20, -60)
    frame:Hide()
    RaidTrack.tabFrames[i] = frame
end
RaidTrack.settingsTab = frame

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOPLEFT", 10, -10)
title:SetText("Sync Settings")

RaidTrackDB.settings = RaidTrackDB.settings or {
    debug = false,
    debugVerbose = false,
}

-- Officer only checkbox
local officerOnlyCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
officerOnlyCheck:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
officerOnlyCheck.text:SetText("Officers only")
officerOnlyCheck:SetScript("OnClick", function(self)
    if not RaidTrack.IsOfficer() then
        RaidTrack.AddDebugMessage("Only officers can change sync settings.")
        self:SetChecked(not self:GetChecked())
        return
    end
    RaidTrackDB.settings.officerOnly = self:GetChecked()
    RaidTrack.BroadcastSettings()
end)

-- Auto-sync checkbox
local autoSyncCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
autoSyncCheck:SetPoint("TOPLEFT", officerOnlyCheck, "BOTTOMLEFT", 0, -20)
autoSyncCheck.text:SetText("Auto-accept from officers")
autoSyncCheck:SetScript("OnClick", function(self)
    if not RaidTrack.IsOfficer() then
        RaidTrack.AddDebugMessage("Only officers can change sync settings.")
        self:SetChecked(not self:GetChecked())
        return
    end
    RaidTrackDB.settings.autoSync = self:GetChecked()
    RaidTrack.BroadcastSettings()
end)

-- Debug enabled checkbox
local debugCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
debugCB.text:SetText("Enable debug log")
debugCB:SetPoint("TOPLEFT", autoSyncCheck, "BOTTOMLEFT", 0, -25)
debugCB:SetScript("OnClick", function(self)
    RaidTrackDB.settings.debug = self:GetChecked()
end)

-- Verbose debug checkbox
local verboseCB = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
verboseCB:SetPoint("TOPLEFT", debugCB, "BOTTOMLEFT", 0, -5)
verboseCB.text:SetText("Verbose debug (include args/returns)")
verboseCB:SetScript("OnClick", function(self)
    RaidTrackDB.settings.debugVerbose = self:GetChecked()
end)

-- Min rank dropdown label
local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
lbl:SetPoint("TOPLEFT", verboseCB, "BOTTOMLEFT", 0, -20)
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
                        RaidTrack.AddDebugMessage("You don't have permission to change sync rank.")
                        return
                    end
                    RaidTrackDB.settings.minSyncRank = self.value
                    UIDropDownMenu_SetSelectedValue(rankDD, self.value)
                    RaidTrack.BroadcastSettings()
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
dbgScroll:SetSize(940, 390)
dbgScroll:SetPoint("TOPLEFT", dbgLabel, "BOTTOMLEFT", 0, -5)
dbgScroll.ScrollBar.ThumbTexture:SetWidth(16)

local dbgEdit = CreateFrame("EditBox", nil, dbgScroll)
dbgEdit:SetMultiLine(true)
dbgEdit:SetFontObject("ChatFontNormal")
dbgEdit:SetWidth(940)
dbgEdit:SetAutoFocus(false)
dbgEdit:SetScript("OnEscapePressed", dbgEdit.ClearFocus)
dbgScroll:SetScrollChild(dbgEdit)

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
syncBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -20)
syncBtn:SetText("Manual Sync")
syncBtn:SetScript("OnClick", function()
    local ok, err = pcall(RaidTrack.SendSyncData)
    if not ok then
        RaidTrack.AddDebugMessage("Sync error: " .. tostring(err))
    else
        RaidTrack.AddDebugMessage("Manual sync triggered.")
    end
end)

-- OnShow
frame:SetScript("OnShow", function()
     if RaidTrackDB.settings.minSyncRank == nil then
        RaidTrackDB.settings.minSyncRank = 1
        RaidTrack.AddDebugMessage("Default minSyncRank set to 1 (fallback in OnShow)")
    end
    local s = RaidTrackDB.settings
    officerOnlyCheck:SetChecked(s.officerOnly ~= false)
    autoSyncCheck:SetChecked(s.autoSync ~= false)
    debugCB:SetChecked(s.debug == true)
    verboseCB:SetChecked(s.debugVerbose == true)
    UpdateRankDropdown()
    if s.minSyncRank then
        UIDropDownMenu_SetSelectedValue(rankDD, s.minSyncRank)
        -- Odśwież nazwę rangi w dropdownie
        for j = 1, GetNumGuildMembers() do
            local _, rankName, ridx = GetGuildRosterInfo(j)
            if ridx == s.minSyncRank then
                UIDropDownMenu_SetText(rankDD, rankName)
                break
            end
        end
    end
RaidTrackDB.settings = RaidTrackDB.settings or {}
RaidTrackDB.settings.minSyncRank = RaidTrackDB.settings.minSyncRank or 1


    if not RaidTrack.IsOfficer() then
        autoSyncCheck:Disable()
        rankDD:Disable()
        officerOnlyCheck:Disable()
    end
end)
function RaidTrack.UpdateSettingsTab()
    if not RaidTrack.settingsTab then return end
    local s = RaidTrackDB.settings
    if RaidTrack.settingsTab:IsShown() then
        -- Jeśli otwarte, zresetuj dropdown
        UIDropDownMenu_SetSelectedValue(RTRankDD, s.minSyncRank)
        -- Odśwież nazwę
        for j = 1, GetNumGuildMembers() do
            local _, rankName, ridx = GetGuildRosterInfo(j)
            if ridx == s.minSyncRank then
                UIDropDownMenu_SetText(RTRankDD, rankName)
                break
            end
        end
    end
end
