local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- Lokalny stan i funkcje dla EPGPTab
local epgpTabData = {
    filter = "",
    currentData = {},
    epgpScrollContainer = nil,
}

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
    EVOKER = {0, 0.25, 0.75, 1},
}

local function GetClassIconTextureCoords(class)
    return unpack(CLASS_ICON_TCOORDS[class or "PRIEST"])
end

local function BuildEPGPData()
    local data = {}
    local filter = epgpTabData.filter:lower()

    for playerName, stats in pairs(RaidTrackDB.epgp) do
        local ep = stats.ep or 0
        local gp = stats.gp or 0
        local pr = (gp > 0) and (ep / gp) or 0

        if filter == "" or playerName:lower():find(filter, 1, true) then
            local _, classToken = UnitClass(playerName)
            table.insert(data, {
                name = playerName,
                ep = ep,
                gp = gp,
                pr = pr,
                class = classToken or "PRIEST",
            })
        end
    end

    table.sort(data, function(a, b) return a.pr > b.pr end)
    epgpTabData.currentData = data
end

local function BuildEPGPUI(scrollContainer)
    if not scrollContainer then return end
    scrollContainer:ReleaseChildren()

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

    local nameHeader = AceGUI:Create("Label")
    nameHeader:SetText("Name")
    nameHeader:SetFontObject(GameFontNormal)
    nameHeader:SetWidth(180)
    nameHeader:SetJustifyH("LEFT")
    header:AddChild(nameHeader)

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

    scrollContainer:AddChild(header)

    -- Data rows
    for _, d in ipairs(epgpTabData.currentData) do
        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        row:SetHeight(22)

        -- Class icon
        local icon = AceGUI:Create("Icon")
        icon:SetImage("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        icon:SetImageSize(14, 14)
        icon:SetWidth(20)
        icon:SetHeight(20)
        icon:SetLabel("")
        icon.image:SetTexCoord(GetClassIconTextureCoords(d.class))
        row:AddChild(icon)

        -- Player name with class color
        local nameLabel = AceGUI:Create("Label")
        local _, class = UnitClass(d.name)
        local color = RAID_CLASS_COLORS[class or ""] or { r = 1, g = 1, b = 1 }
        local coloredName = string.format("|cff%02x%02x%02x%s|r", color.r*255, color.g*255, color.b*255, d.name)
        nameLabel:SetText(coloredName)
        nameLabel:SetFontObject(GameFontNormal)
        nameLabel:SetWidth(180)
        nameLabel:SetJustifyH("LEFT")
        row:AddChild(nameLabel)

        -- EP
        local epLabel = AceGUI:Create("Label")
        epLabel:SetText(tostring(d.ep))
        epLabel:SetFontObject(GameFontNormal)
        epLabel:SetWidth(60)
        epLabel:SetJustifyH("CENTER")
        row:AddChild(epLabel)

        -- GP
        local gpLabel = AceGUI:Create("Label")
        gpLabel:SetText(tostring(d.gp))
        gpLabel:SetFontObject(GameFontNormal)
        gpLabel:SetWidth(60)
        gpLabel:SetJustifyH("CENTER")
        row:AddChild(gpLabel)

        -- PR
        local prLabel = AceGUI:Create("Label")
        prLabel:SetText(string.format("%.2f", d.pr))
        prLabel:SetFontObject(GameFontNormal)
        prLabel:SetWidth(60)
        prLabel:SetJustifyH("CENTER")
        row:AddChild(prLabel)

        scrollContainer:AddChild(row)
    end
end

local function UpdateEPGPList()
    BuildEPGPData()
    BuildEPGPUI(epgpTabData.epgpScrollContainer)
end

function RaidTrack:Render_epgpTab(container)
    container:SetLayout("Fill")
    container:SetFullHeight(true)

    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    mainGroup:SetLayout("List")
    container:AddChild(mainGroup)

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search Player")
    searchBox:SetFullWidth(true)
    searchBox:SetText(epgpTabData.filter or "")
    mainGroup:AddChild(searchBox)

    local outerGroup = AceGUI:Create("SimpleGroup")
    outerGroup:SetFullWidth(true)
    outerGroup:SetFullHeight(true)
    outerGroup:SetLayout("Fill")
    mainGroup:AddChild(outerGroup)

    local scrollContainer = AceGUI:Create("ScrollFrame")
    scrollContainer:SetLayout("List")
    scrollContainer:SetFullWidth(true)
    scrollContainer:SetFullHeight(true)
    outerGroup:AddChild(scrollContainer)

    epgpTabData.epgpScrollContainer = scrollContainer

    searchBox:SetCallback("OnTextChanged", function(_, _, text)
        epgpTabData.filter = text or ""
        UpdateEPGPList()
    end)

    UpdateEPGPList()
end
