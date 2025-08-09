-- GuildTab.lua (AceGUI version, cache-only model with manual "Load More" pagination)
local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- Lokalny stan
guildTabData = guildTabData or {
    selected = {},
    filter = "",
    currentData = {},
    lastSelectedIdx = nil,
    scrollFrame = nil,
    showOffline = false,
    forceRefresh = true,
    countLabel = nil,
    visibleRows = {},
    rowPoolSize = 75
}
local guildSearchDebounceTimer = nil

local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or {
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
    return unpack(CLASS_ICON_TCOORDS[class] or {0, 1, 0, 1})
end

local function ClearSelection()
    guildTabData.selected = {}
end

local function IsSelected(name)
    return guildTabData.selected[name]
end

local function SetSelectedRange(data, fromIdx, toIdx)
    local s, e = math.min(fromIdx, toIdx), math.max(fromIdx, toIdx)
    for i = s, e do
        guildTabData.selected[data[i].name] = true
    end
end

local function UpdateHighlighting()
    for idx, row in ipairs(guildTabData.visibleRows or {}) do
        local data = guildTabData.currentData[idx]
        if row.bg and data then
            row.bg:SetShown(IsSelected(data.name))
        end
    end
end

function RaidTrack.UpdateGuildRoster()
    local total = GetNumGuildMembers()
    local data = {}
    local filter = guildTabData.filter or ""
    local showOffline = guildTabData.showOffline

    for i = 1, total do
        local name, _, _, _, classLocalized, _, _, _, online = GetGuildRosterInfo(i)
        if name and classLocalized then
            local shortName = Ambiguate(name, "none")
            local classToken = RaidTrack.GetClassTokenFromLocalized(classLocalized)
            local epgp = RaidTrackDB.epgp[shortName] or { ep = 0, gp = 0 }
            local lowerName = shortName:lower()
            local lowerClass = classToken:lower()
            if (online or showOffline) and (filter == "" or lowerName:find(filter, 1, true) or lowerClass:find(filter, 1, true)) then
                local pr = (epgp.gp > 0 and epgp.ep / epgp.gp or 0)
                table.insert(data, {
                    name = shortName,
                    class = classToken,
                    ep = epgp.ep,
                    gp = epgp.gp,
                    pr = pr,
                    online = online
                })
            end
        end
    end

    table.sort(data, function(a, b) return a.pr > b.pr end)
    guildTabData.currentData = data
    guildTabData.rowPoolSize = 75
    ClearSelection()
    guildTabData.lastSelectedIdx = nil

    if guildTabData.countLabel then
        local displayed = math.min(guildTabData.rowPoolSize, #guildTabData.currentData)
        local selectedCount = 0
        for _ in pairs(guildTabData.selected) do selectedCount = selectedCount + 1 end
        guildTabData.countLabel:SetText("Displaying: " .. displayed .. " / " .. #guildTabData.currentData .. " | Selected: " .. selectedCount)
    end

    RaidTrack.RenderGuildRows()
end
function RaidTrack.RenderGuildRows()
    if not guildTabData.scrollFrame then
        return
    end
    -- Safe cleanup of highlight textures before recycling rows
for _, child in ipairs(guildTabData.scrollFrame.children or {}) do
    if child._highlightTexture then
        child._highlightTexture:SetColorTexture(0, 0, 0, 0)
        child._highlightTexture:Hide()
        child._highlightTexture:SetParent(nil)
        child._highlightTexture = nil
    end
end

guildTabData.scrollFrame:ReleaseChildren()
guildTabData.visibleRows = {}


    local header = AceGUI:Create("SimpleGroup")
    header:SetLayout("Flow")
    header:SetFullWidth(true)
    header:SetHeight(24)
    for _, h in ipairs({{"C", 20}, {"Name", 140}, {"EP", 60}, {"GP", 60}, {"PR", 60}}) do

    local lbl = AceGUI:Create("Label")
    lbl:SetText(h[1])
    lbl:SetWidth(h[2])
    lbl:SetJustifyH("CENTER")
    lbl:SetFontObject(GameFontNormal)
    header:AddChild(lbl)
end

    guildTabData.scrollFrame:AddChild(header)

    for i = 1, math.min(guildTabData.rowPoolSize, #guildTabData.currentData) do
        local d = guildTabData.currentData[i]
        local row = AceGUI:Create("SimpleGroup")
        

        row:SetLayout("Flow")
        row:SetFullWidth(true)
        row:SetHeight(24)
        -- Add highlight texture
RaidTrack.ApplyHighlight(row, IsSelected(d.name))



        local icon = AceGUI:Create("Icon")
        icon:SetImage("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        icon:SetImageSize(16, 16)
        icon:SetWidth(20)
        icon:SetHeight(20)
        icon.image:SetTexCoord(GetClassIconTextureCoords(d.class))
        row:AddChild(icon)

        local col = RAID_CLASS_COLORS[d.class] or {
            r = 1,
            g = 1,
            b = 1
        }
        if not d.online then
            col = {
                r = col.r * 0.5,
                g = col.g * 0.5,
                b = col.b * 0.5
            }
        end

        local fields = {{
            text = d.name,
            width = 140
        }, {
            text = d.ep,
            width = 60
        }, {
            text = d.gp,
            width = 60
        }, {
            text = string.format("%.2f", d.pr),
            width = 60
        }}
        for _, field in ipairs(fields) do
    local lbl = AceGUI:Create("Label")
    lbl:SetText(tostring(field.text))
    lbl:SetWidth(field.width)
    lbl:SetJustifyH("CENTER")
    lbl:SetFontObject(GameFontNormal)
    lbl:SetColor(col.r, col.g, col.b)
    row:AddChild(lbl)
end


        row.frame:SetScript("OnMouseDown", function()
            local idx = i
            local d = guildTabData.currentData[idx]
            if not d then
                return
            end

            if IsShiftKeyDown() and guildTabData.lastSelectedIdx then
                ClearSelection()
                SetSelectedRange(guildTabData.currentData, guildTabData.lastSelectedIdx, idx)
            elseif IsControlKeyDown() then
                guildTabData.selected[d.name] = not guildTabData.selected[d.name]
            else
                ClearSelection()
                guildTabData.selected[d.name] = true
            end
            guildTabData.lastSelectedIdx = idx

            local selectedCount = 0
            for _ in pairs(guildTabData.selected) do
                selectedCount = selectedCount + 1
            end
            if guildTabData.countLabel then
                local displayed = math.min(guildTabData.rowPoolSize, #guildTabData.currentData)
                guildTabData.countLabel:SetText("Displaying: " .. displayed .. " / " .. #guildTabData.currentData ..
                                                    " | Selected: " .. selectedCount)
            end

            RaidTrack.RenderGuildRows()
        end)

        guildTabData.scrollFrame:AddChild(row)
        table.insert(guildTabData.visibleRows, row)
    end

    if guildTabData.rowPoolSize < #guildTabData.currentData then
        local btn = AceGUI:Create("Button")
        btn:SetText("Load More")
        btn:SetFullWidth(true)
        btn:SetCallback("OnClick", function()
            guildTabData.rowPoolSize = guildTabData.rowPoolSize + 100
            RaidTrack.RenderGuildRows()
        end)
        guildTabData.scrollFrame:AddChild(btn)
    end
end

function RaidTrack:Render_guildTab(container)
    container:SetLayout("Fill")
    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    mainGroup:SetLayout("Flow")
    container:AddChild(mainGroup)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetRelativeWidth(0.68)
    scroll:SetFullHeight(true)
    mainGroup:AddChild(scroll)
    guildTabData.scrollFrame = scroll

    local rightPanel = AceGUI:Create("InlineGroup")
    rightPanel:SetTitle("Controls")
    rightPanel:SetRelativeWidth(0.32)
    rightPanel:SetFullHeight(true)
    rightPanel:SetLayout("Flow")
    mainGroup:AddChild(rightPanel)

    local countLabel = AceGUI:Create("Label")
    countLabel:SetText("Displaying: ?")
    countLabel:SetFullWidth(true)
    rightPanel:AddChild(countLabel)
    guildTabData.countLabel = countLabel

    local showOfflineCheck = AceGUI:Create("CheckBox")
    showOfflineCheck:SetLabel("Show Offline")
    showOfflineCheck:SetValue(guildTabData.showOffline)
    showOfflineCheck:SetCallback("OnValueChanged", function(_, _, val)
        guildTabData.showOffline = val
        guildTabData.forceRefresh = true
        RaidTrack.UpdateGuildRoster()
    end)
    rightPanel:AddChild(showOfflineCheck)

    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("Search")
    searchBox:SetText(guildTabData.filter)
    searchBox:SetCallback("OnTextChanged", function(_, _, text)
    guildTabData.filter = text:lower()
    guildTabData.forceRefresh = true

    if guildSearchDebounceTimer then
        guildSearchDebounceTimer:Cancel()
    end

    guildSearchDebounceTimer = C_Timer.NewTimer(0.3, function()
        RaidTrack.UpdateGuildRoster()
    end)
end)

    rightPanel:AddChild(searchBox)

    local epInput = AceGUI:Create("EditBox")
    epInput:SetLabel("EP")
    rightPanel:AddChild(epInput)

    local gpInput = AceGUI:Create("EditBox")
    gpInput:SetLabel("GP")
    rightPanel:AddChild(gpInput)

    local applyBtn = AceGUI:Create("Button")
    applyBtn:SetText("Apply")
    applyBtn:SetCallback("OnClick", function()
        local epv = tonumber(epInput:GetText()) or 0
        local gpv = tonumber(gpInput:GetText()) or 0
        for _, d in ipairs(guildTabData.currentData or {}) do
            if guildTabData.selected[d.name] then
                RaidTrack.LogEPGPChange(d.name, epv, gpv, "GuildTab")
            end
        end
        RaidTrack.UpdateGuildRoster()
        RaidTrack.SendSyncData()
    end)
    rightPanel:AddChild(applyBtn)

    RaidTrack.UpdateGuildRoster()
    

end
RaidTrack.UpdateGuildList = function()
    if RaidTrack.UpdateGuildRoster then
        RaidTrack.UpdateGuildRoster()
    end
end
function RaidTrack.DeactivateGuildTab()
    -- Close any AceGUI dropdown pullouts created by Guild tab
    if RaidTrack.guildRankDropdown and RaidTrack.guildRankDropdown.pullout then
        RaidTrack.guildRankDropdown.pullout:Close()
    end
    if RaidTrack.guildFilterDropdown and RaidTrack.guildFilterDropdown.pullout then
        RaidTrack.guildFilterDropdown.pullout:Close()
    end

    -- Hide any custom highlight/overlay frames created by Guild tab
    if RaidTrack.guildHighlightFrame then
        RaidTrack.guildHighlightFrame:Hide()
    end

    -- Safety: hide tooltip
    GameTooltip:Hide()
end
