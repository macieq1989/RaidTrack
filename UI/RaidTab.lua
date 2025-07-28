-- UI/RaidTab.lua
local addonName, RaidTrack = ...

-- Ensure core structures exist
RaidTrack.tabs         = RaidTrack.tabs        or {}
RaidTrack.tabFrames    = RaidTrack.tabFrames   or {}
RaidTrack.selectedRaid = RaidTrack.selectedRaid or {}
RaidTrack.lastRaidIdx  = RaidTrack.lastRaidIdx or nil
RaidTrack.searchFilter = RaidTrack.searchFilter or ""
if not RaidTrack.mainFrame then return end

local RAID_TAB_INDEX = 1

-- Create or retrieve the Raid tab frame
local frame = RaidTrack.tabFrames[RAID_TAB_INDEX]
if not frame then
    frame = CreateFrame("Frame", nil, RaidTrack.mainFrame)
    frame:SetSize(960, 700)
    frame:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 20, -60)
    frame:Hide()
    RaidTrack.tabFrames[RAID_TAB_INDEX] = frame
end
RaidTrack.raidTab = frame

-- Create Raid tab button
local btn = RaidTrack.tabs[RAID_TAB_INDEX]
if not btn then
    btn = CreateFrame("Button", nil, RaidTrack.mainFrame, "UIPanelButtonTemplate")
    btn:SetSize(80, 25)
    btn:SetText("Raid")
    btn:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 10 + (RAID_TAB_INDEX-1)*85, -30)
    btn:SetScript("OnClick", function() RaidTrack.ShowTab(RAID_TAB_INDEX) end)
    RaidTrack.tabs[RAID_TAB_INDEX] = btn
end

-- Search input
local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
searchLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
searchLabel:SetText("Search:")

local searchInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
searchInput:SetSize(200, 20)
searchInput:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
searchInput:SetAutoFocus(false)
searchInput:SetScript("OnTextChanged", function(self)
    RaidTrack.searchFilter = self:GetText():lower()
    RaidTrack.UpdateRaidList()
end)
-- Scroll frame and background
local scroll = CreateFrame("ScrollFrame", "RaidTrackRaidScroll", frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -60)
scroll:SetSize(450, 600)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(450, 600)
scroll:SetScrollChild(content)

local gridBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
gridBg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -5, 5)
gridBg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 5, -5)
gridBg:SetFrameLevel(scroll:GetFrameLevel() - 1)
gridBg:SetBackdrop({
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left=2, right=2, top=2, bottom=2 },
})
gridBg:SetBackdropColor(0, 0, 0, 0.8)
gridBg:SetBackdropBorderColor(0, 0, 0, 0.6)

-- Operations panel on the right
local ops = CreateFrame("Frame", nil, frame)
ops:SetSize(240, 600)
ops:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 20, 0)
local countLabel = ops:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
countLabel:SetPoint("TOPLEFT", 10, -20)
countLabel:SetText("Selected: 0")

local epLbl = ops:CreateFontString(nil, "OVERLAY", "GameFontNormal")
epLbl:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -30)
epLbl:SetText("EP:")
local epInput = CreateFrame("EditBox", nil, ops, "InputBoxTemplate")
epInput:SetSize(100, 20)
epInput:SetPoint("LEFT", epLbl, "RIGHT", 10, 0)
epInput:SetAutoFocus(false)

local gpLbl = ops:CreateFontString(nil, "OVERLAY", "GameFontNormal")
gpLbl:SetPoint("TOPLEFT", epLbl, "BOTTOMLEFT", 0, -30)
gpLbl:SetText("GP:")
local gpInput = CreateFrame("EditBox", nil, ops, "InputBoxTemplate")
gpInput:SetSize(100, 20)
gpInput:SetPoint("LEFT", gpLbl, "RIGHT", 10, 0)
gpInput:SetAutoFocus(false)

local applyBtn = CreateFrame("Button", nil, ops, "UIPanelButtonTemplate")
applyBtn:SetSize(100, 25)
applyBtn:SetPoint("TOPLEFT", gpLbl, "BOTTOMLEFT", 0, -30)
applyBtn:SetText("Apply")
applyBtn:SetScript("OnClick", function()
    local epv = tonumber(epInput:GetText()) or 0
    local gpv = tonumber(gpInput:GetText()) or 0
  for _, d in ipairs(RaidTrack.currentRaidData or {}) do
    if RaidTrack.selectedRaid[d.name] then
        RaidTrack.LogEPGPChange(d.name, epv, gpv, "RaidTab")
    end
end

    RaidTrack.UpdateRaidList()
    RaidTrack.AddDebugMessage("Auto-sync: sending updated data...")
    RaidTrack.SendSyncData()
end)

-- Data/UI storage
local dataRows, uiRows = {}, {}

-- Column offsets
local COL = { name=40, ep=200, gp=280, pr=360 }
local COLW = 60

-- Sort helper
local function SortByPR(a, b) return a.pr > b.pr end

-- Selection helpers
local function ClearSelection()
    RaidTrack.selectedRaid = {}
end
local function IsSelected(name)
    return RaidTrack.selectedRaid[name]
end
local function SetSelectedRange(data, fromIdx, toIdx)
    local s, e = math.min(fromIdx, toIdx), math.max(fromIdx, toIdx)
    for i = s, e do RaidTrack.selectedRaid[data[i].name] = true end
end

-- ClearUI hides rows
local function ClearUI()
    for _, row in ipairs(uiRows) do
        if row.bg then row.bg:Hide() end
        if row.icon then row.icon:Hide() end
        if row.name then row.name:Hide() end
        if row.epFS then row.epFS:Hide() end
        if row.gpFS then row.gpFS:Hide() end
        if row.prFS then row.prFS:Hide() end
        if row.role then row.role:Hide() end
    end
    wipe(uiRows)
    local cnt = 0
    for _ in pairs(RaidTrack.selectedRaid) do cnt = cnt + 1 end
    countLabel:SetText("Selected: " .. cnt)
end

-- BuildData from raid roster
local classMap = {}
for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do classMap[loc] = token end
for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do classMap[loc] = token end

local function BuildData()
    wipe(dataRows)
    local n = GetNumGroupMembers() or 0
    for i = 1, n do
        local name, _, _, _, classLoc = GetRaidRosterInfo(i)
        if name then
            local classToken = classMap[classLoc] or classLoc:upper()
            local st = RaidTrackDB.epgp[name] or { ep=0, gp=0 }
            local pr = (st.gp > 0) and (st.ep / st.gp) or 0
            local unit = "raid" .. i
            local role = (UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "NONE"
            -- Apply search filter: name or class matches
            if RaidTrack.searchFilter == "" 
               or string.find(name:lower(), RaidTrack.searchFilter, 1, true) 
               or string.find(classToken:lower(), RaidTrack.searchFilter, 1, true) then
                tinsert(dataRows, { name = name, ep = st.ep, gp = st.gp, pr = pr, class = classToken, role = role })
            end
        end
    end
    table.sort(dataRows, SortByPR)
    RaidTrack.currentRaidData = dataRows
end

-- BuildUI renders rows
local function BuildUI()
    ClearUI()
    local y = -10
    -- Headers
    local hdrs = { "Name", "EP", "GP", "PR" }
    local xpos = { COL.name, COL.ep, COL.gp, COL.pr }
    for i, h in ipairs(hdrs) do
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", xpos[i], y)
        if i > 1 then fs:SetWidth(COLW); fs:SetJustifyH("CENTER") end
        fs:SetText(h)
        tinsert(uiRows, { bg = fs, name = fs, epFS = fs, gpFS = fs, prFS = fs, role = fs })
    end
    y = y - 20
    for idx, d in ipairs(dataRows) do
        -- Row background
        local bgRow = CreateFrame("Button", nil, content, "BackdropTemplate")
        bgRow:SetFrameStrata("BACKGROUND")
        bgRow:SetFrameLevel(gridBg:GetFrameLevel() + 1)
        bgRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y + 5)
        bgRow:SetSize(scroll:GetWidth(), 20)
        bgRow:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
        bgRow:SetBackdropColor(
            IsSelected(d.name) and 0.1 or 0,
            IsSelected(d.name) and 0.1 or 0,
            IsSelected(d.name) and 0.5 or 0,
            IsSelected(d.name) and 0.5 or 0
        )
        bgRow:SetScript("OnClick", function()
            if IsShiftKeyDown() and RaidTrack.lastRaidIdx then
                ClearSelection()
                SetSelectedRange(dataRows, RaidTrack.lastRaidIdx, idx)
            elseif IsControlKeyDown() then
                RaidTrack.selectedRaid[d.name] = not RaidTrack.selectedRaid[d.name]
            else
                ClearSelection()
                RaidTrack.selectedRaid[d.name] = true
            end
            RaidTrack.lastRaidIdx = idx
            RaidTrack.UpdateRaidList()
        end)
        tinsert(uiRows, { bg = bgRow })
        -- Class icon
        local icon = content:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", content, "TOPLEFT", COL.name - 20, y + 2)
        local coord = CLASS_ICON_TCOORDS[d.class]
        if coord then
            icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            icon:SetTexCoord(unpack(coord))
        else
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetTexCoord(0, 1, 0, 1)
        end
        tinsert(uiRows, { icon = icon })
        -- Name text
        local nameFS = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", content, "TOPLEFT", COL.name, y + 2)
        local colc = RAID_CLASS_COLORS[d.class] or { r=1, g=1, b=1 }
        nameFS:SetText(d.name)
        nameFS:SetTextColor(colc.r, colc.g, colc.b)
        nameFS:SetDrawLayer("OVERLAY", 2)
        tinsert(uiRows, { name = nameFS })
        -- Role icon
        local roleIcon = content:CreateTexture(nil, "OVERLAY")
        roleIcon:SetSize(12, 12)
        roleIcon:SetPoint("LEFT", nameFS, "RIGHT", 4, 0)
        local roleCoords = {
            TANK    = {0.00,0.25,0.25,0.50},
            HEALER  = {0.25,0.5,0,0.25},
            DAMAGER = {0.25,0.50,0.25,0.50},
            NONE    = {0.50,0.75,0.25,0.50},
        }
        roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
        roleIcon:SetTexCoord(unpack(roleCoords[d.role] or roleCoords.NONE))
        tinsert(uiRows, { role = roleIcon })
        -- EP, GP, PR columns
        local vals = { d.ep, d.gp, string.format("%.2f", d.pr) }
        for i, v in ipairs(vals) do
            local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOPLEFT", content, "TOPLEFT", xpos[i+1], y + 2)
            fs:SetWidth(COLW)
            fs:SetJustifyH("CENTER")
            fs:SetText(v)
            fs:SetTextColor(colc.r, colc.g, colc.b)
            tinsert(uiRows, { epFS = fs, gpFS = fs, prFS = fs })
        end
        y = y - 20
    end
end

-- Main update function
function RaidTrack.UpdateRaidList()
    BuildData()
    BuildUI()
end

-- Refresh button
local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
refresh:SetSize(80, 25)
-- Place at bottom-left, offset 10px from edges
refresh:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
refresh:SetText("Refresh")
refresh:SetScript("OnClick", RaidTrack.UpdateRaidList)

-- Auto-update on show
frame:SetScript("OnShow", RaidTrack.UpdateRaidList)