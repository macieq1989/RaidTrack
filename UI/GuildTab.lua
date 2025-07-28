-- GuildTab.lua
local addonName, RaidTrack = ...

-- Ensure core structures exist
RaidTrack.tabs            = RaidTrack.tabs            or {}
RaidTrack.tabFrames       = RaidTrack.tabFrames       or {}
RaidTrack.selectedGuild   = RaidTrack.selectedGuild   or {}
RaidTrack.lastSelectedIdx = RaidTrack.lastSelectedIdx or nil
if not RaidTrack.mainFrame then return end

local GUILD_TAB_INDEX = 5

-- Create or retrieve the Guild tab frame
local frame = RaidTrack.tabFrames[GUILD_TAB_INDEX]
if not frame then
    frame = CreateFrame("Frame", nil, RaidTrack.mainFrame)
    frame:SetSize(960, 700)
    frame:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 20, -60)
    frame:Hide()
    RaidTrack.tabFrames[GUILD_TAB_INDEX] = frame
end
RaidTrack.guildTab = frame

-- Create Guild tab button
local btn = RaidTrack.tabs[GUILD_TAB_INDEX]
if not btn then
    btn = CreateFrame("Button", nil, RaidTrack.mainFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 25)
    btn:SetText("Guild")
    btn:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 10 + (GUILD_TAB_INDEX-1)*85, -30)
    btn:SetScript("OnClick", function() RaidTrack.ShowTab(GUILD_TAB_INDEX) end)
    RaidTrack.tabs[GUILD_TAB_INDEX] = btn
end

-- Controls: Show Offline and Search
local showOffline = false
local searchText  = ""

-- Selection helpers
local function ClearSelection() RaidTrack.selectedGuild = {} end
local function IsSelected(name) return RaidTrack.selectedGuild[name] end
local function SetSelectedRange(data, fromIdx, toIdx)
    local s, e = math.min(fromIdx, toIdx), math.max(fromIdx, toIdx)
    for i = s, e do RaidTrack.selectedGuild[data[i].name] = true end
end

-- Show Offline checkbox
local offlineCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
offlineCheckbox:SetPoint("TOPLEFT", 10, -10)
offlineCheckbox.text:SetText("Show Offline")
offlineCheckbox:SetScript("OnClick", function(self)
    showOffline = self:GetChecked()
    RaidTrack.UpdateGuildRoster()
end)

-- Search box
local searchBox do
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", offlineCheckbox, "BOTTOMLEFT", 0, -10)
    lbl:SetText("Search:")
    searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -2)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEnterPressed", function(self)
        searchText = self:GetText():lower()
        RaidTrack.UpdateGuildRoster()
        self:ClearFocus()
    end)
end

-- Scroll frame
local scroll = CreateFrame("ScrollFrame", "RaidTrackGuildScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -100)
scroll:SetSize(450, 600)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(450, 600)
scroll:SetScrollChild(content)

-- Right-side operations panel
local opsPanel = CreateFrame("Frame", nil, frame)
opsPanel:SetSize(240, 600)
opsPanel:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 20, 0)

-- Selected count label
local countLabel = opsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
countLabel:SetPoint("TOPLEFT", opsPanel, "TOPLEFT", 10, -20)
countLabel:SetText("Selected: 0")

-- EP input
local epLabel = opsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
epLabel:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -30)
epLabel:SetText("EP:")
local epInput = CreateFrame("EditBox", nil, opsPanel, "InputBoxTemplate")
epInput:SetSize(100, 20)
epInput:SetPoint("LEFT", epLabel, "RIGHT", 10, 0)
epInput:SetAutoFocus(false)

-- GP input
local gpLabel = opsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gpLabel:SetPoint("TOPLEFT", epLabel, "BOTTOMLEFT", 0, -30)
gpLabel:SetText("GP:")
local gpInput = CreateFrame("EditBox", nil, opsPanel, "InputBoxTemplate")
gpInput:SetSize(100, 20)
gpInput:SetPoint("LEFT", gpLabel, "RIGHT", 10, 0)
gpInput:SetAutoFocus(false)

-- Apply button with auto-sync
local applyBtn = CreateFrame("Button", nil, opsPanel, "UIPanelButtonTemplate")
applyBtn:SetSize(100, 25)
applyBtn:SetPoint("TOPLEFT", gpLabel, "BOTTOMLEFT", 0, -30)
applyBtn:SetText("Apply")
applyBtn:SetScript("OnClick", function()
    local epVal = tonumber(epInput:GetText()) or 0
    local gpVal = tonumber(gpInput:GetText()) or 0
    for _, d in ipairs(RaidTrack.currentGuildData or {}) do
        if RaidTrack.selectedGuild[d.name] then
            RaidTrack.LogEPGPChange(d.name, epVal, gpVal, "GuildTab Apply")
        end
    end
    RaidTrack.UpdateGuildRoster()
    RaidTrack.AddDebugMessage("Auto-sync: sending updated data...")
    RaidTrack.SendSyncData()
end)

-- Background grid
local gridBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
gridBg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -5, 5)
gridBg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 5, -5)
gridBg:SetFrameLevel(scroll:GetFrameLevel() - 1)
gridBg:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
})
gridBg:SetBackdropColor(0, 0, 0, 0.8)
gridBg:SetBackdropBorderColor(0, 0, 0, 0.6)

-- UI row storage and ClearUI
local uiRows = {}
local function ClearUI()
    for _, row in ipairs(uiRows) do
        for _, widget in pairs(row) do
            if type(widget) == "table" and widget.Hide then
                widget:Hide()
            end
        end
    end
    wipe(uiRows)
    local count = 0 for _ in pairs(RaidTrack.selectedGuild) do count = count + 1 end
    countLabel:SetText("Selected: " .. count)
    -- also clear all children from content frame to avoid leftovers
    for _, child in ipairs({ content:GetChildren() }) do
        if child.Hide then child:Hide() end
    end
end

-- Sorting helper
local function SortByPR(a, b) return a.pr > b.pr end

-- Column offsets
local COL = { name = 30, ep = 200, gp = 280, pr = 360 }
local COL_WIDTH = 60

-- Main update function
function RaidTrack.UpdateGuildRoster()
    ClearUI()
    if C_GuildInfo and C_GuildInfo.RequestGuildRoster then
        C_GuildInfo.RequestGuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end

    local total = (C_GuildInfo and C_GuildInfo.GetNumGuildMembers and C_GuildInfo.GetNumGuildMembers()) or GetNumGuildMembers()
    local data = {}
    local locToToken = {}
    for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do locToToken[localized] = token end
    for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE)   do locToToken[localized] = token end
    for i = 1, total do
        local name, _, _, _, classLoc, _, _, _, online = GetGuildRosterInfo(i)
        online = not not online
        if name and (online or showOffline) and (searchText == "" or name:lower():find(searchText, 1, true)) then
            local shortName = Ambiguate(name, "none")
            local classToken = locToToken[classLoc] or "UNKNOWN"
            if C_GuildInfo and C_GuildInfo.GetGuildRosterInfo then
                local info = C_GuildInfo.GetGuildRosterInfo(i)
                if info and info.classFileName then classToken = info.classFileName end
            end
            local epgp = RaidTrackDB.epgp[shortName] or { ep = 0, gp = 0 }
            tinsert(data, { name = shortName, class = classToken, ep = epgp.ep, gp = epgp.gp, pr = (epgp.gp > 0 and epgp.ep / epgp.gp or 0), online = online })
        end
    end
    table.sort(data, SortByPR)
    RaidTrack.currentGuildData = data

    local y = -10
    local headers = { "Name", "EP", "GP", "PR" }
    local xpos = { COL.name, COL.ep, COL.gp, COL.pr }
    for i, label in ipairs(headers) do
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", xpos[i], y)
        if i > 1 then fs:SetWidth(COL_WIDTH); fs:SetJustifyH("CENTER") end
        fs:SetText(label)
        fs:SetDrawLayer("OVERLAY", 2)
        tinsert(uiRows, { name = fs })
    end

    y = y - 20
    for idx, d in ipairs(data) do
        local function OnRowClick()
            if IsShiftKeyDown() and RaidTrack.lastSelectedIdx then
                ClearSelection()
                SetSelectedRange(data, RaidTrack.lastSelectedIdx, idx)
            elseif IsControlKeyDown() then
                RaidTrack.selectedGuild[d.name] = not RaidTrack.selectedGuild[d.name]
            else
                ClearSelection()
                RaidTrack.selectedGuild[d.name] = true
            end
            RaidTrack.lastSelectedIdx = idx
            RaidTrack.UpdateGuildRoster()
        end

        local bg = CreateFrame("Button", nil, content, "BackdropTemplate")
        bg:SetFrameStrata("BACKGROUND")
        bg:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y + 5)
        bg:SetSize(scroll:GetWidth(), 20)
        bg:SetBackdrop({ bgFile="Interface\\ChatFrame\\ChatFrameBackground" })
        local sel = IsSelected(d.name)
        bg:SetBackdropColor(sel and 0.1 or 0, sel and 0.1 or 0, sel and 0.5 or 0, sel and 0.5 or 0)
        bg:SetScript("OnClick", OnRowClick)

        local icon = content:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", content, "TOPLEFT", COL.name - 16, y)
        if CLASS_ICON_TCOORDS[d.class] then
            icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[d.class]))
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        icon:SetDrawLayer("OVERLAY", 1)

        local col = RAID_CLASS_COLORS[d.class] or { r=1, g=1, b=1 }
        if not d.online then col = { r=col.r*0.5, g=col.g*0.5, b=col.b*0.5 } end

        local nameFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", content, "TOPLEFT", COL.name, y)
        nameFS:SetText(d.name)
        nameFS:SetTextColor(col.r, col.g, col.b)
        nameFS:SetDrawLayer("OVERLAY", 2)
        tinsert(uiRows, { bg=bg, icon=icon, name=nameFS })

        local stats = { d.ep, d.gp, string.format("%.2f", d.pr) }
        for i, val in ipairs(stats) do
            local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", xpos[i+1], y)
            fs:SetWidth(COL_WIDTH); fs:SetJustifyH("CENTER")
            fs:SetText(val)
            fs:SetTextColor(col.r, col.g, col.b)
            fs:SetDrawLayer("OVERLAY", 2)
            tinsert(uiRows, { fs = fs })
        end

        y = y - 20
    end
end

-- Refresh button
local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
refresh:SetSize(80, 25)
refresh:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
refresh:SetText("Refresh")
refresh:SetScript("OnClick", RaidTrack.UpdateGuildRoster)

-- Auto-update on show
frame:SetScript("OnShow", RaidTrack.UpdateGuildRoster)