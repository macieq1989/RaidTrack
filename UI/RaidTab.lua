local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

local raidTabData = {
    selected = {},
    filter = "",
    currentData = {},
    lastRaidIdx = nil,
    raidScrollContainer = nil
}

local classMap = {}
for token, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
    classMap[loc] = token
end
for token, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
    classMap[loc] = token
end

local CLASS_ICON_TCOORDS = {
    WARRIOR = {0, 0.25, 0, 0.25},
    MAGE = {0.25, 0.49609375, 0, 0.25},
    ROGUE = {0.49609375, 0.7421875, 0, 0.25},
    DRUID = {0.7421875, 0.98828125, 0, 0.25},
    HUNTER = {0, 0.25, 0.25, 0.5},
    SHAMAN = {0.25, 0.49609375, 0.25, 0.5},
    PRIEST = {0.49609375, 0.7421875, 0.25, 0.5},
    WARLOCK = {0.7421875, 0.98828125, 0.25, 0.5},
    PALADIN = {0, 0.25, 0.5, 0.75},
    DEATHKNIGHT = {0.25, 0.49609375, 0.5, 0.75},
    MONK = {0.49609375, 0.7421875, 0.5, 0.75},
    DEMONHUNTER = {0.7421875, 0.98828125, 0.5, 0.75},
    EVOKER = {0, 0.25, 0.75, 1}
}

local function GetClassIconTextureCoords(class)
    return unpack(CLASS_ICON_TCOORDS[class or "PRIEST"])
end
function RaidTrack.UpdateRaidTabStatus()
    if not RaidTrack.raidTabStatusLabel then
        return
    end

    local id = RaidTrack.activeRaidID
    if not id then
        RaidTrack.raidTabStatusLabel:SetText("|cffffccccRaid Status: INACTIVE|r")
        return
    end

    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

   for _, raid in ipairs(RaidTrackDB.raidInstances) do
    
    if tostring(raid.id) == tostring(id) then
        RaidTrack.activeRaidID = id

        local elapsed = raid.started and SecondsToTime(time() - raid.started) or "N/A"
        local status = raid.status or "unknown"
        RaidTrack.raidTabStatusLabel:SetText(string.format("|cffccffccRaid Status: %s - %s [%s]|r",
            status:upper(), elapsed, raid.name or "Unnamed"))
        return
    end
end


    RaidTrack.raidTabStatusLabel:SetText("|cffffccccRaid Status: INACTIVE|r")
end


local function ClearSelection()
    raidTabData.selected = {}
    raidTabData.lastRaidIdx = nil
end

local function IsSelected(name)
    return raidTabData.selected[name]
end

local function SetSelectedRange(data, fromIdx, toIdx)
    if type(fromIdx) ~= "number" or type(toIdx) ~= "number" then
        return -- jeśli któryś indeks jest nil lub nie jest liczbą, po prostu zwróć
    end
    local s, e = math.min(fromIdx, toIdx), math.max(fromIdx, toIdx)
    for i = s, e do
        raidTabData.selected[data[i].name] = true
    end
end

local function BuildData()
    local dataRows = {}
    local n = GetNumGroupMembers() or 0
    local filter = raidTabData.filter or ""
    for i = 1, n do
        local name, _, _, _, classLoc = GetRaidRosterInfo(i)
        if name then
            local classToken = classMap[classLoc] or classLoc:upper()
            local st = RaidTrackDB.epgp[name] or {
                ep = 0,
                gp = 0
            }
            local pr = (st.gp > 0) and (st.ep / st.gp) or 0
            local unit = "raid" .. i
            local role = (UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or "NONE"
            if filter == "" or name:lower():find(filter, 1, true) or classToken:lower():find(filter, 1, true) then
                table.insert(dataRows, {
                    name = name,
                    ep = st.ep,
                    gp = st.gp,
                    pr = pr,
                    class = classToken,
                    role = role
                })
            end
        end
    end
    table.sort(dataRows, function(a, b)
        return a.pr > b.pr
    end)
    raidTabData.currentData = dataRows
end

local function UpdateRaidList()
    if not raidTabData.skipRebuild then
        BuildData()
    end
    if raidTabData.raidScrollContainer then
        raidTabData.raidScrollContainer:ReleaseChildren()

        -- Header row
        local header = AceGUI:Create("SimpleGroup")
        header:SetLayout("Flow")
        header:SetFullWidth(true)
        header:SetHeight(22)

        local classHeader = AceGUI:Create("Label")
        classHeader:SetText("C")
        classHeader:SetFontObject(GameFontNormal)
        classHeader:SetWidth(20)
        classHeader:SetJustifyH("CENTER")
        header:AddChild(classHeader)

        local roleHeader = AceGUI:Create("Label")
        roleHeader:SetText("R")
        roleHeader:SetFontObject(GameFontNormal)
        roleHeader:SetWidth(20)
        roleHeader:SetJustifyH("CENTER")
        header:AddChild(roleHeader)

        local nameHeader = AceGUI:Create("Label")
        nameHeader:SetText("Name")
        nameHeader:SetFontObject(GameFontNormal)
        nameHeader:SetWidth(130)
        nameHeader:SetJustifyH("LEFT")
        header:AddChild(nameHeader)

        local spacer = AceGUI:Create("Label")
        spacer:SetText("")
        spacer:SetWidth(30)
        header:AddChild(spacer)

        local epHeader = AceGUI:Create("Label")
        epHeader:SetText("EP")
        epHeader:SetFontObject(GameFontNormal)
        epHeader:SetWidth(60)
        epHeader:SetJustifyH("CENTER")
        header:AddChild(epHeader)

        local gpHeader = AceGUI:Create("Label")
        gpHeader:SetText("GP")
        gpHeader:SetFontObject(GameFontNormal)
        gpHeader:SetWidth(60)
        gpHeader:SetJustifyH("CENTER")
        header:AddChild(gpHeader)

        local prHeader = AceGUI:Create("Label")
        prHeader:SetText("PR")
        prHeader:SetFontObject(GameFontNormal)
        prHeader:SetWidth(60)
        prHeader:SetJustifyH("CENTER")
        header:AddChild(prHeader)

        raidTabData.raidScrollContainer:AddChild(header)

        -- Data rows
        for idx, d in ipairs(raidTabData.currentData or {}) do
            local row = AceGUI:Create("SimpleGroup")
            row:SetLayout("Flow")
            row:SetFullWidth(true)
            row:SetHeight(22)

            -- Safe highlight using per-frame cleanup
            RaidTrack.ApplyHighlight(row, IsSelected(d.name))

            -- Class icon
            local icon = AceGUI:Create("Icon")
            icon:SetImage("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            icon:SetImageSize(14, 14)
            icon:SetWidth(20)
            icon:SetHeight(20)
            icon:SetLabel("")
            icon.image:SetTexCoord(GetClassIconTextureCoords(d.class))
            row:AddChild(icon)

            -- Role icon
            local roleIcon = AceGUI:Create("Icon")
            roleIcon:SetImageSize(14, 14)
            roleIcon:SetWidth(20)
            roleIcon:SetHeight(20)
            roleIcon:SetLabel("")
            if d.role == "TANK" then
                roleIcon:SetImage("Interface\\LFGFrame\\UI-LFG-ICON-ROLES", 0.00, 0.25, 0.25, 0.50)
            elseif d.role == "HEALER" then
                roleIcon:SetImage("Interface\\LFGFrame\\UI-LFG-ICON-ROLES", 0.25, 0.5, 0, 0.25)
            elseif d.role == "DAMAGER" then
                roleIcon:SetImage("Interface\\LFGFrame\\UI-LFG-ICON-ROLES", 0.25, 0.50, 0.25, 0.50)
            else
                roleIcon:SetImage("Interface\\LFGFrame\\UI-LFG-ICON-ROLES", 0.50, 0.75, 0.25, 0.50)
            end
            row:AddChild(roleIcon)

            -- Player name label
            local nameLabel = AceGUI:Create("Label")
            local _, class = UnitClass(d.name)
            local color = RAID_CLASS_COLORS[class or ""] or {
                r = 1,
                g = 1,
                b = 1
            }
            local coloredName = string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255,
                d.name)
            nameLabel:SetText(coloredName)
            nameLabel:SetFontObject(GameFontNormal)
            nameLabel:SetWidth(130)
            nameLabel:SetJustifyH("LEFT")
            row:AddChild(nameLabel)

            local spacer2 = AceGUI:Create("Label")
            spacer2:SetText("")
            spacer2:SetWidth(30)
            row:AddChild(spacer2)

            -- EP label
            local epLabel = AceGUI:Create("Label")
            epLabel:SetText(tostring(d.ep))
            epLabel:SetFontObject(GameFontNormal)
            epLabel:SetWidth(60)
            epLabel:SetJustifyH("CENTER")
            row:AddChild(epLabel)

            -- GP label
            local gpLabel = AceGUI:Create("Label")
            gpLabel:SetText(tostring(d.gp))
            gpLabel:SetFontObject(GameFontNormal)
            gpLabel:SetWidth(60)
            gpLabel:SetJustifyH("CENTER")
            row:AddChild(gpLabel)

            -- PR label
            local prLabel = AceGUI:Create("Label")
            prLabel:SetText(string.format("%.2f", d.pr))
            prLabel:SetFontObject(GameFontNormal)
            prLabel:SetWidth(60)
            prLabel:SetJustifyH("CENTER")
            row:AddChild(prLabel)

            -- Click handler
            local function CreateRowClickHandler(rowIndex)
                return function()
                    local data = raidTabData.currentData[rowIndex]
                    if not data then
                        return
                    end

                    if IsShiftKeyDown() and raidTabData.lastRaidIdx then
                        SetSelectedRange(raidTabData.currentData, raidTabData.lastRaidIdx, rowIndex)
                    elseif IsControlKeyDown() then
                        raidTabData.selected[data.name] = not raidTabData.selected[data.name]
                    else
                        ClearSelection()
                        raidTabData.selected[data.name] = true
                    end

                    raidTabData.lastRaidIdx = rowIndex

                    raidTabData.skipRebuild = true
                    UpdateRaidList()
                    raidTabData.skipRebuild = false
                end
            end

            row.frame:SetScript("OnMouseDown", CreateRowClickHandler(idx))

            raidTabData.raidScrollContainer:AddChild(row)
        end
    end
    if raidTabData.countLabel then
        local selectedCount = 0
        for _ in pairs(raidTabData.selected) do
            selectedCount = selectedCount + 1
        end
        local total = #raidTabData.currentData or 0
        raidTabData.countLabel:SetText("Selected: " .. selectedCount .. " / " .. total)
    end

end

function RaidTrack.ClearRaidSelection()
    ClearSelection()
end

function RaidTrack.DeactivateRaidTab()
    -- Usuń callbacki, odłącz eventy, wyczyść UI raidTab aby nie działał gdy nie jest aktywny
    if raidTabData.raidScrollContainer then
        -- PRE-CLEAN highlight textures
        for _, child in ipairs(raidTabData.raidScrollContainer.children or {}) do
            if child._highlightTexture then
                child._highlightTexture:SetColorTexture(0, 0, 0, 0)
                child._highlightTexture:Hide()
                child._highlightTexture:SetParent(nil)
                child._highlightTexture = nil
            end
        end
        raidTabData.raidScrollContainer:ReleaseChildren()

        raidTabData.raidScrollContainer = nil
    end
    ClearSelection()
    raidTabData.lastRaidIdx = nil
end
function RaidTrack.RefreshRaidDropdown()
    -- Jeśli dropdown nie istnieje lub nie ma pullout, to go pomijamy
    if not RaidTrack.raidSelectDropdown 
       or not RaidTrack.raidSelectDropdown.pullout 
       or not RaidTrack._tabGroup 
       or (RaidTrack._tabGroup.GetSelectedTab 
           and RaidTrack._tabGroup:GetSelectedTab() ~= "raidTab") then
        return
    end

    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

    local values = {}
    for _, r in ipairs(RaidTrackDB.raidInstances) do
        if r.status ~= "ended" then
            local label = string.format("%s [%s]", r.name or "Unnamed", r.status or "unknown")
            values[r.id] = label
        end
    end

    RaidTrack.raidSelectDropdown:SetList(values)
end



function RaidTrack:Render_raidTab(container)
    container:SetLayout("Fill")
    container:SetFullHeight(true)
    RaidTrack.activeTab = "raidTab"


    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    mainGroup:SetLayout("Fill")

    local rowGroup = AceGUI:Create("SimpleGroup")
    rowGroup:SetFullWidth(true)
    rowGroup:SetFullHeight(true)
    rowGroup:SetLayout("Flow")
    mainGroup:AddChild(rowGroup)

    local leftPanel = AceGUI:Create("InlineGroup")
    leftPanel:SetTitle("Raid Roster")
    leftPanel:SetRelativeWidth(0.68)
    leftPanel:SetFullHeight(true)
    leftPanel:SetLayout("Fill")
    rowGroup:AddChild(leftPanel)

    raidTabData.raidScrollContainer = AceGUI:Create("ScrollFrame")
    raidTabData.raidScrollContainer:SetLayout("List")
    raidTabData.raidScrollContainer:SetFullWidth(true)
    raidTabData.raidScrollContainer:SetFullHeight(true)
    leftPanel:AddChild(raidTabData.raidScrollContainer)

    local rightPanel = AceGUI:Create("InlineGroup")
    rightPanel:SetTitle("Controls")
    rightPanel:SetRelativeWidth(0.32)
    rightPanel:SetFullHeight(true)
    rightPanel:SetLayout("List")
    rowGroup:AddChild(rightPanel)

    local controlsScroll = AceGUI:Create("SimpleGroup")
    controlsScroll:SetFullWidth(true)
    controlsScroll:SetFullHeight(true)
    controlsScroll:SetLayout("List")
    rightPanel:AddChild(controlsScroll)

    container:AddChild(mainGroup)

    -- === RAID CONTROL SECTION ===

    -- STATUS LABEL
    local statusLabel = AceGUI:Create("Label")
    statusLabel:SetFullWidth(true)
    RaidTrack.raidTabStatusLabel = statusLabel
    controlsScroll:AddChild(statusLabel)
    

    -- SELECT RAID DROPDOWN
    local raidSelectDD = AceGUI:Create("Dropdown")
    raidSelectDD:SetLabel("Select Raid")
    raidSelectDD:SetFullWidth(true)
    RaidTrack.raidSelectDropdown = raidSelectDD

    C_Timer.After(0.1, function()
        if RaidTrack.RefreshRaidDropdown then
            RaidTrack.RefreshRaidDropdown()
        end
    end)

    controlsScroll:AddChild(raidSelectDD)

    -- CREATE RAID BUTTON
    local createRaidBtn = AceGUI:Create("Button")
    createRaidBtn:SetText("Create Raid")
    createRaidBtn:SetFullWidth(true)
    createRaidBtn:SetCallback("OnClick", function()
        RaidTrack:OpenRaidCreationWindow() -- lub inna dedykowana funkcja
    end)
    controlsScroll:AddChild(createRaidBtn)

    -- CONFIGURE BUTTON
    local configBtn = AceGUI:Create("Button")
    configBtn:SetText("Configure Raid")
    configBtn:SetFullWidth(true)
    configBtn:SetCallback("OnClick", function()
        RaidTrack:OpenRaidConfigWindow()
    end)
    controlsScroll:AddChild(configBtn)

    -- START RAID BUTTON
    local startBtn = AceGUI:Create("Button")
    startBtn:SetText("Start Raid")
    startBtn:SetFullWidth(true)
 startBtn:SetCallback("OnClick", function()
    local selectedRaidID = raidSelectDD:GetValue()
    if not selectedRaidID then
        RaidTrack.AddDebugMessage("No raid selected.")
        return
    end

    local raidInstance = nil
    for _, r in ipairs(RaidTrackDB.raidInstances or {}) do
        if r.id == selectedRaidID then
            r.status = "started"
            r.started = time()

            raidInstance = r
            break
        end
    end

    if not raidInstance then
        RaidTrack.AddDebugMessage("Invalid raid selected.")
        return
    end

    -- Ustaw aktywny raid
    RaidTrack.activeRaidID = raidInstance.id
    RaidTrackDB.activeRaidID = raidInstance.id

    -- Zapisz stan
    RaidTrack.AddDebugMessage("Raid started: " .. raidInstance.name .. " [" .. raidInstance.id .. "]")

    -- Strefa
    local zone = GetRealZoneText() or "Unknown Zone"

    -- Stwórz instancję jeśli trzeba
    RaidTrack.CreateRaidInstance(raidInstance.name, zone, raidInstance.preset)

    RaidTrack.activeRaidID = raidInstance.id
RaidTrackDB.activeRaidID = raidInstance.id

       -- Odśwież dropdown, label i lista graczy
    RaidTrack.RefreshRaidDropdown()
    raidSelectDD:SetValue(raidInstance.id)
    RaidTrack.UpdateRaidTabStatus() -- <- ręczne wywołanie natychmiast
    UpdateRaidList()
    RaidTrack.BroadcastRaidSync()


    -- Start odświeżania co sekundę tylko jeśli aktywna zakładka
    if RaidTrack.activeTab == "raidTab" and not RaidTrack._raidTabTicker then
        RaidTrack._raidTabTicker = C_Timer.NewTicker(1, function()
            if RaidTrack.activeTab == "raidTab" then
                RaidTrack.UpdateRaidTabStatus()
            end
        end)
    end

end)


    controlsScroll:AddChild(startBtn)

    -- END RAID BUTTON
    local endBtn = AceGUI:Create("Button")
    endBtn:SetText("End Raid")
    endBtn:SetFullWidth(true)
    endBtn:SetCallback("OnClick", function()
        RaidTrack.EndActiveRaid()
        RaidTrack.RefreshRaidDropdown()

        RaidTrack.UpdateRaidTabStatus()
        RaidTrack.BroadcastRaidSync()

    end)
    controlsScroll:AddChild(endBtn)

    local countLabel = AceGUI:Create("Label")
    countLabel:SetText("Selected: 0 / 0")
    countLabel:SetFullWidth(true)
    controlsScroll:AddChild(countLabel)
    raidTabData.countLabel = countLabel

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search")
    searchBox:SetFullWidth(true)
    searchBox:SetText(raidTabData.filter or "")
    searchBox:SetCallback("OnTextChanged", function(_, _, text)
        raidTabData.filter = text:lower()
        UpdateRaidList()
    end)
    controlsScroll:AddChild(searchBox)

    local applyGroup = AceGUI:Create("InlineGroup")
    applyGroup:SetTitle("Apply EP/GP")
    applyGroup:SetFullWidth(true)
    applyGroup:SetLayout("Flow")
    controlsScroll:AddChild(applyGroup)

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
        for _, d in ipairs(raidTabData.currentData or {}) do
            if raidTabData.selected[d.name] then
                RaidTrack.LogEPGPChange(d.name, epv, gpv, "RaidTab")
            end
        end
        UpdateRaidList()
        RaidTrack.SendSyncData()
    end)
    applyGroup:AddChild(applyBtn)

    UpdateRaidList()
 if not RaidTrack._raidTabTicker then
    RaidTrack._raidTabTicker = C_Timer.NewTicker(1, function()
        if RaidTrack.activeTab == "raidTab" then
            RaidTrack.UpdateRaidTabStatus()
        end
    end)
end



end
RaidTrack.UpdateRaidList = UpdateRaidList
