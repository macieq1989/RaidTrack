-- UI/EPGPLogTab.lua
local addonName, ns = ...
_G.RaidTrack = _G.RaidTrack or ns or {}
local RaidTrack = _G.RaidTrack

_G.RaidTrackDBV2 = _G.RaidTrackDBV2 or {}
_G.RaidTrackDB   = _G.RaidTrackDBV2
local RaidTrackDB = _G.RaidTrackDBV2


local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI then
    print("|cff00ffff[RaidTrack]|r EPGP Log tab requires AceGUI-3.0")
    return
end

_G.RaidTrackDB = _G.RaidTrackDB or {}
local RaidTrackDB = _G.RaidTrackDB
RaidTrackDB.epgpLog = RaidTrackDB.epgpLog or { changes = {}, lastId = 0 }

-- State
local logTab = {
    filter = "",
    typeFilter = "ALL",   -- ALL / EP / GP
    rowPoolSize = 100,
    scroll = nil,
    countLabel = nil,
}
local searchDebounce

-- utils
local function asNumber(v) return tonumber(v) or 0 end
local function safeLower(s) return type(s) == "string" and s:lower() or "" end
local function fmtTime(ts) return date("%Y-%m-%d %H:%M:%S", ts or time()) end

-- Normalize entry to common shape
local function normalizeEntry(e)
    if type(e) ~= "table" then return nil end
    local id   = asNumber(e.id)
    local ts   = asNumber(e.ts or e.time or e.timestamp)
    if ts <= 0 then ts = time() end
    local name = e.player or e.name or "?"
    local epd  = asNumber(e.ep or e.epDelta or e.deltaEP)
    local gpd  = asNumber(e.gp or e.gpDelta or e.deltaGP)
    local by   = e.by or e.author or e.source or ""
    local why  = e.reason or e.note or e.msg or ""
    return { id = id, ts = ts, player = name, ep = epd, gp = gpd, by = by, reason = why }
end

-- Build filtered/sorted data
local function buildData()
    local src = (RaidTrackDB and RaidTrackDB.epgpLog and RaidTrackDB.epgpLog.changes) or {}
    local out, filt = {}, safeLower(logTab.filter)
    local tf = logTab.typeFilter

    for _, raw in ipairs(src) do
        local e = normalizeEntry(raw)
        if e then
            local passType = (tf == "ALL") or (tf == "EP" and e.ep ~= 0) or (tf == "GP" and e.gp ~= 0)
            if passType then
                if filt == "" or
                   safeLower(e.player):find(filt, 1, true) or
                   safeLower(e.reason):find(filt, 1, true) or
                   safeLower(e.by):find(filt, 1, true)
                then
                    out[#out+1] = e
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.id ~= b.id and a.id > 0 and b.id > 0 then
            return a.id > b.id
        else
            return (a.ts or 0) > (b.ts or 0)
        end
    end)
    return out
end

local function addHeader(scroll)
    local header = AceGUI:Create("SimpleGroup")
    header:SetLayout("Flow")
    header:SetFullWidth(true)
    header:SetHeight(22)

    local cols = {
        {"Time", 150}, {"Player", 140}, {"ΔEP", 60}, {"ΔGP", 60}, {"Reason", 220}, {"By", 120},
    }
    for _, c in ipairs(cols) do
        local lbl = AceGUI:Create("Label")
        lbl:SetText(c[1])
        lbl:SetFontObject(GameFontNormal)
        lbl:SetWidth(c[2])
        lbl:SetJustifyH("LEFT")
        header:AddChild(lbl)
    end
    scroll:AddChild(header)
end

local function colorDelta(v, kind) -- kind = "EP"|"GP"
    local sign = (v >= 0) and "+" or ""
    if kind == "EP" then
        return (v >= 0) and ("|cff33ff33"..sign..v.."|r") or ("|cffff5555"..v.."|r")
    else
        return (v >= 0) and ("|cffffdd00"..sign..v.."|r") or ("|cffff5555"..v.."|r")
    end
end

local function buildUI(scroll)
    if not scroll then return end
    scroll:ReleaseChildren()

    addHeader(scroll)

    local data = buildData()
    local shown = 0
    local limit = logTab.rowPoolSize or 100

    for i = 1, math.min(#data, limit) do
        local e = data[i]
        shown = i

        local row = AceGUI:Create("SimpleGroup")
        row:SetLayout("Flow")
        row:SetFullWidth(true)
        row:SetHeight(20)

        local lblTime = AceGUI:Create("Label")
        lblTime:SetText(fmtTime(e.ts))
        lblTime:SetWidth(150)
        row:AddChild(lblTime)

        local lblName = AceGUI:Create("Label")
        lblName:SetText(tostring(e.player))
        lblName:SetWidth(140)
        row:AddChild(lblName)

        local lblEP = AceGUI:Create("Label")
        lblEP:SetText(colorDelta(e.ep, "EP"))
        lblEP:SetWidth(60)
        lblEP:SetJustifyH("CENTER")
        row:AddChild(lblEP)

        local lblGP = AceGUI:Create("Label")
        lblGP:SetText(colorDelta(e.gp, "GP"))
        lblGP:SetWidth(60)
        lblGP:SetJustifyH("CENTER")
        row:AddChild(lblGP)

        local lblWhy = AceGUI:Create("Label")
        lblWhy:SetText(tostring(e.reason or ""))
        lblWhy:SetJustifyH("LEFT")
        lblWhy:SetWidth(220)
        row:AddChild(lblWhy)

        local lblBy = AceGUI:Create("Label")
        lblBy:SetText(tostring(e.by or ""))
        lblBy:SetJustifyH("LEFT")
        lblBy:SetWidth(120)
        row:AddChild(lblBy)

        scroll:AddChild(row)
    end

    if shown < #data then
        local more = AceGUI:Create("Button")
        more:SetText("Load More")
        more:SetFullWidth(true)
        more:SetCallback("OnClick", function()
            logTab.rowPoolSize = (logTab.rowPoolSize or 100) + 150
            RaidTrack.RefreshEPGPLogTab()
        end)
        scroll:AddChild(more)
    end

    if logTab.countLabel then
        logTab.countLabel:SetText(("Displaying: %d / %d"):format(math.min(shown, #data), #data))
    end
end

-- CSV export
local function exportCSV()
    local data = buildData()
    local lines = { "id,time,player,delta_ep,delta_gp,reason,by" }
    local limit = math.min(#data, logTab.rowPoolSize or #data)
    for i = 1, limit do
        local e = data[i]
        local function esc(s)
            s = tostring(s or ""):gsub("\"", "\"\"")
            if s:find("[,\"\n]") then return "\"" .. s .. "\"" end
            return s
        end
        lines[#lines+1] = table.concat({
            esc(e.id), esc(fmtTime(e.ts)), esc(e.player), esc(e.ep), esc(e.gp), esc(e.reason), esc(e.by)
        }, ",")
    end
    return table.concat(lines, "\n")
end

-- Public refresh
function RaidTrack.RefreshEPGPLogTab()
    if logTab.scroll then buildUI(logTab.scroll) end
end

-- Renderer
function RaidTrack:Render_epgpLogTab(container)
    container:SetLayout("Fill")

    local main = AceGUI:Create("SimpleGroup")
    main:SetFullWidth(true)
    main:SetFullHeight(true)
    main:SetLayout("Flow")
    container:AddChild(main)

    -- List
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetRelativeWidth(0.70)
    scroll:SetFullHeight(true)
    main:AddChild(scroll)
    logTab.scroll = scroll

    -- Right panel
    local right = AceGUI:Create("InlineGroup")
    right:SetTitle("Controls")
    right:SetRelativeWidth(0.30)
    right:SetFullHeight(true)
    right:SetLayout("Flow")
    main:AddChild(right)

    -- Count
    local count = AceGUI:Create("Label")
    count:SetText("")
    count:SetFullWidth(true)
    right:AddChild(count)
    logTab.countLabel = count

    -- Filter
    local search = AceGUI:Create("EditBox")
    search:SetLabel("Filter (player/reason/by)")
    search:SetFullWidth(true)
    search:SetText(logTab.filter or "")
    search:SetCallback("OnTextChanged", function(_, _, txt)
        logTab.filter = txt or ""
        logTab.rowPoolSize = 100
        if searchDebounce then searchDebounce:Cancel() end
        searchDebounce = C_Timer.NewTimer(0.25, function()
            RaidTrack.RefreshEPGPLogTab()
        end)
    end)
    right:AddChild(search)

    -- Type dropdown
    local typeDD = AceGUI:Create("Dropdown")
    typeDD:SetLabel("Change type")
    typeDD:SetFullWidth(true)
    typeDD:SetList({ ALL="ALL", EP="Only EP", GP="Only GP" })
    typeDD:SetValue(logTab.typeFilter or "ALL")
    typeDD:SetCallback("OnValueChanged", function(_, _, val)
        logTab.typeFilter = val or "ALL"
        logTab.rowPoolSize = 100
        RaidTrack.RefreshEPGPLogTab()
    end)
    right:AddChild(typeDD)

    -- Reset
    local resetBtn = AceGUI:Create("Button")
    resetBtn:SetText("Reset filters")
    resetBtn:SetFullWidth(true)
    resetBtn:SetCallback("OnClick", function()
        logTab.filter = ""
        logTab.typeFilter = "ALL"
        logTab.rowPoolSize = 100
        search:SetText("")
        typeDD:SetValue("ALL")
        RaidTrack.RefreshEPGPLogTab()
    end)
    right:AddChild(resetBtn)

    -- CSV export
    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("Copy CSV")
    exportBtn:SetFullWidth(true)
    exportBtn:SetCallback("OnClick", function()
        local csv = exportCSV()
        local pop = AceGUI:Create("Frame")
        pop:SetTitle("EPGP Log CSV")
        pop:SetLayout("Fill")
        pop:SetWidth(650)
        pop:SetHeight(420)
        pop:EnableResize(true)
        local ml = AceGUI:Create("MultiLineEditBox")
        ml:SetLabel("Select all (Ctrl+A), copy (Ctrl+C)")
        ml:SetFullWidth(true)
        ml:SetFullHeight(true)
        ml:SetText(csv)
        pop:AddChild(ml)
    end)
    right:AddChild(exportBtn)

    RaidTrack.RefreshEPGPLogTab()
end
