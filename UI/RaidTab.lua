local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

RaidTrack.tabs = RaidTrack.tabs or {}
RaidTrack.selectedRaid = RaidTrack.selectedRaid or {}
RaidTrack.searchFilter = ""
RaidTrack.currentRaidData = RaidTrack.currentRaidData or {}

local RAID_TAB_INDEX = 1

-- Main container
local frame = AceGUI:Create("SimpleGroup")
frame:SetFullWidth(true)
frame:SetFullHeight(true)
frame:SetLayout("Fill")
RaidTrack.tabFrames = RaidTrack.tabFrames or {}
RaidTrack.tabFrames[RAID_TAB_INDEX] = frame
RaidTrack.raidTab = frame

-- Lock resizing to prevent crashes
if RaidTrack.mainFrame and RaidTrack.mainFrame.SetResizable then
    RaidTrack.mainFrame:SetResizable(false)
end

-- Content group with vertical layout
local contentGroup = AceGUI:Create("SimpleGroup")
contentGroup:SetFullWidth(true)
contentGroup:SetFullHeight(true)
contentGroup:SetLayout("Fill")
frame:AddChild(contentGroup)

-- Horizontal row group for left and right panels
local rowGroup = AceGUI:Create("SimpleGroup")
rowGroup:SetFullWidth(true)
rowGroup:SetFullHeight(true)
rowGroup:SetLayout("Flow")
contentGroup:AddChild(rowGroup)

-- Left panel
local leftPanel = AceGUI:Create("InlineGroup")
leftPanel:SetTitle("Raid Roster")
leftPanel:SetRelativeWidth(0.68)
leftPanel:SetFullHeight(true)

leftPanel:SetLayout("Fill")
rowGroup:AddChild(leftPanel)

-- Right panel
local rightPanel = AceGUI:Create("InlineGroup")
rightPanel:SetTitle("Controls")
rightPanel:SetRelativeWidth(0.32)
rightPanel:SetFullHeight(true)
rightPanel:SetLayout("Fill")
rowGroup:AddChild(rightPanel)

-- Outer group inside leftPanel
local outerGroup = AceGUI:Create("SimpleGroup")
outerGroup:SetLayout("Fill")
outerGroup:SetFullWidth(true)
outerGroup:SetFullHeight(true)
leftPanel:AddChild(outerGroup)

-- ScrollFrame inside leftPanel (will scroll if needed)
local scrollContainer = AceGUI:Create("ScrollFrame")
scrollContainer:SetLayout("List")
scrollContainer:SetFullWidth(true)
scrollContainer:SetFullHeight(true)
outerGroup:AddChild(scrollContainer)

-- Outer group inside rightPanel
local outerRightGroup = AceGUI:Create("SimpleGroup")
outerRightGroup:SetLayout("Fill")
outerRightGroup:SetFullWidth(true)
outerRightGroup:SetFullHeight(true)
rightPanel:AddChild(outerRightGroup)

-- Controls group inside rightPanel
local controlsScroll = AceGUI:Create("SimpleGroup")
controlsScroll:SetLayout("List")
controlsScroll:SetFullWidth(true)
controlsScroll:SetFullHeight(true)
outerRightGroup:AddChild(controlsScroll)

-- Search input
local searchBox = AceGUI:Create("EditBox")
searchBox:SetLabel("Search")
searchBox:SetFullWidth(true)
searchBox:SetCallback("OnTextChanged", function(_, _, text)
    RaidTrack.searchFilter = text:lower()
    RaidTrack.UpdateRaidList()
end)
controlsScroll:AddChild(searchBox)

-- EP/GP apply panel
local applyGroup = AceGUI:Create("InlineGroup")
applyGroup:SetTitle("Apply EP/GP")
applyGroup:SetFullWidth(true)
applyGroup:SetLayout("Flow")

local epInput = AceGUI:Create("EditBox")
epInput:SetLabel("EP")
epInput:SetWidth(100)
applyGroup:AddChild(epInput)

local gpInput = AceGUI:Create("EditBox")
gpInput:SetLabel("GP")
gpInput:SetWidth(100)
applyGroup:AddChild(gpInput)

local applyBtn = AceGUI:Create("Button")
applyBtn:SetText("Apply")
applyBtn:SetWidth(100)
applyBtn:SetCallback("OnClick", function()
    local epv = tonumber(epInput:GetText()) or 0
    local gpv = tonumber(gpInput:GetText()) or 0
    for _, d in ipairs(RaidTrack.currentRaidData or {}) do
        if RaidTrack.selectedRaid[d.name] then
            RaidTrack.LogEPGPChange(d.name, epv, gpv, "RaidTab")
        end
    end
    RaidTrack.UpdateRaidList()
    RaidTrack.SendSyncData()
end)
applyGroup:AddChild(applyBtn)
controlsScroll:AddChild(applyGroup)

-- Selection logic
local function ClearSelection() RaidTrack.selectedRaid = {} end
local function IsSelected(name) return RaidTrack.selectedRaid[name] end
local function SetSelectedRange(data, fromIdx, toIdx)
    local s, e = math.min(fromIdx, toIdx), math.max(fromIdx, toIdx)
    for i = s, e do RaidTrack.selectedRaid[data[i].name] = true end
end

-- Class translation
local classMap = {}
for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do classMap[loc] = token end
for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do classMap[loc] = token end

local function BuildData()
    local dataRows = {}
    local n = GetNumGroupMembers() or 0
    local filter = RaidTrack.searchFilter or ""
    for i = 1, n do
        local name, _, _, _, classLoc = GetRaidRosterInfo(i)
        if name then
            local classToken = classMap[classLoc] or classLoc:upper()
            local st = RaidTrackDB.epgp[name] or { ep = 0, gp = 0 }
            local pr = (st.gp > 0) and (st.ep / st.gp) or 0
            local unit = "raid" .. i
            local role = (UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "NONE"
            if filter == "" or name:lower():find(filter, 1, true) or classToken:lower():find(filter, 1, true) then
                table.insert(dataRows, { name = name, ep = st.ep, gp = st.gp, pr = pr, class = classToken, role = role })
            end
        end
    end
    table.sort(dataRows, function(a, b) return a.pr > b.pr end)
    RaidTrack.currentRaidData = dataRows
end

local function BuildUI()
    scrollContainer:ReleaseChildren()
    for idx, d in ipairs(RaidTrack.currentRaidData or {}) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("List")
        row:SetFullWidth(true)
        row:SetHeight(20)

        local _, class = UnitClass(d.name)
        local color = RAID_CLASS_COLORS[class or ""] or { r = 1, g = 1, b = 1 }
        local coloredName = string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, d.name)

        local label = AceGUI:Create("Label")
        label:SetText(coloredName .. " - EP: " .. d.ep .. " GP: " .. d.gp .. " PR: " .. string.format("%.2f", d.pr))
        label:SetFullWidth(true)

        row:AddChild(label)
        row.frame:SetScript("OnMouseDown", function()
            if IsShiftKeyDown() and RaidTrack.lastRaidIdx then
                ClearSelection()
                SetSelectedRange(RaidTrack.currentRaidData, RaidTrack.lastRaidIdx, idx)
            elseif IsControlKeyDown() then
                RaidTrack.selectedRaid[d.name] = not RaidTrack.selectedRaid[d.name]
            else
                ClearSelection()
                RaidTrack.selectedRaid[d.name] = true
            end
            RaidTrack.lastRaidIdx = idx
            RaidTrack.UpdateRaidList()
        end)

        scrollContainer:AddChild(row)
    end
end

function RaidTrack.UpdateRaidList()
    BuildData()
    BuildUI()
end

function RaidTrack:Render_raidTab(container)
    container:SetLayout("Fill")
    container:SetFullHeight(true)
    container:AddChild(RaidTrack.raidTab)

    RaidTrack.raidTab.frame:ClearAllPoints()
    RaidTrack.raidTab.frame:SetPoint("TOPLEFT", container.content, "TOPLEFT", 0, 0)
    RaidTrack.raidTab.frame:SetPoint("BOTTOMRIGHT", container.content, "BOTTOMRIGHT", 0, 0)

    C_Timer.After(0.1, function()
        RaidTrack.UpdateRaidList()
        container:DoLayout()
        RaidTrack.raidTab:DoLayout()
    end)
end




frame.frame:SetScript("OnShow", function()
    C_Timer.After(0.1, function()
        RaidTrack.UpdateRaidList()
        RaidTrack.raidTab:DoLayout()
    end)
end)
