-- UI/RaidCreateUI.lua
local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- Helper: build preset dropdown list
local function BuildPresetList()
    local t = {}
    for name, _ in pairs(RaidTrack.GetRaidPresets()) do
        t[name] = name
    end
    return t
end

-- Helper: sort raids by status and time
local STATUS_ORDER = { started = 1, created = 2, ended = 3 }

local function SortRaids(list)
    table.sort(list, function(a, b)
        local sa = STATUS_ORDER[a.status or "created"] or 2
        local sb = STATUS_ORDER[b.status or "created"] or 2
        if sa ~= sb then return sa < sb end

        -- inside the same status group
        if a.status == "started" then
            -- newest started first
            local ta = tonumber(a.started or 0) or 0
            local tb = tonumber(b.started or 0) or 0
            if ta ~= tb then return ta > tb end
        elseif a.status == "created" then
            -- earliest planned first
            local ta = tonumber(a.scheduledAt or math.huge) or math.huge
            local tb = tonumber(b.scheduledAt or math.huge) or math.huge
            if ta ~= tb then return ta < tb end
        elseif a.status == "ended" then
            -- newest ended first
            local ta = tonumber(a.ended or 0) or 0
            local tb = tonumber(b.ended or 0) or 0
            if ta ~= tb then return ta > tb end
        end

        -- tie‑breakers
        return (a.name or "") < (b.name or "")
    end)
end

-- Public: allow other windows (Config) to refresh this dropdown live
function RaidTrack.RefreshCreateRaidPresetDropdown()
    if not RaidTrack._createPresetDD then return end
    local keep = RaidTrack._createPresetDD:GetValue()
    local list = BuildPresetList()
    RaidTrack._createPresetDD:SetList(list)
    if keep and list[keep] then
        RaidTrack._createPresetDD:SetValue(keep)
    else
        RaidTrack._createPresetDD:SetValue(nil)
    end
end

function RaidTrack:OpenRaidCreationWindow()
    if self.raidCreateWindow then
        self.raidCreateWindow:Show()
        return
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Create or Manage Raids")
    frame:SetStatusText("Create a new raid or manage existing ones")
    frame:SetLayout("Fill")
    frame:SetWidth(550)
    frame:SetHeight(600)
    frame:EnableResize(false)
    RaidTrack.RestoreWindowPosition("raidCreateWindow", frame)
    frame:SetCallback("OnClose", function(widget)
        RaidTrack.SaveWindowPosition("raidCreateWindow", widget)
    end)
    self.raidCreateWindow = frame

    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("List")
    container:SetFullWidth(true)
    container:SetFullHeight(true)
    frame:AddChild(container)

    -- === CREATE NEW RAID ===
    local presetDD = AceGUI:Create("Dropdown")
    presetDD:SetLabel("Select Preset")
    presetDD:SetFullWidth(true)
    presetDD:SetList(BuildPresetList())
    container:AddChild(presetDD)
    RaidTrack._createPresetDD = presetDD -- expose for live refresh from Config UI

    local nameInput = AceGUI:Create("EditBox")
    nameInput:SetLabel("Raid Name")
    nameInput:SetFullWidth(true)
    nameInput:SetText("New Raid " .. date("%Y-%m-%d"))
    container:AddChild(nameInput)

    -- Optional planned date/time (works if you fill scheduledAt later; safe if you don't)
    local dateInput = AceGUI:Create("EditBox")
    dateInput:SetLabel("Planned Date (YYYY-MM-DD)")
    dateInput:SetFullWidth(true)
    dateInput:SetText(date("%Y-%m-%d"))
    container:AddChild(dateInput)

    local timeInput = AceGUI:Create("EditBox")
    timeInput:SetLabel("Planned Time (HH:MM)")
    timeInput:SetFullWidth(true)
    timeInput:SetText(date("%H:%M"))
    container:AddChild(timeInput)

    local function ParseDateTime(dstr, tstr)
        local Y, M, D = tostring(dstr or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        local h, m    = tostring(tstr or ""):match("^(%d%d):(%d%d)$")
        Y,M,D,h,m = tonumber(Y),tonumber(M),tonumber(D),tonumber(h),tonumber(m)
        if not (Y and M and D and h and m) then return nil end
        return time({year=Y, month=M, day=D, hour=h, min=m, sec=0})
    end

    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Create Raid")
    confirmBtn:SetFullWidth(true)
    confirmBtn:SetCallback("OnClick", function()
        local preset = presetDD:GetValue()
        local name = nameInput:GetText()

        if not preset or preset == "" then
            RaidTrack.AddDebugMessage("Please select a preset.")
            return
        end
        if not name or name == "" then
            RaidTrack.AddDebugMessage("Please enter a raid name.")
            return
        end

        local scheduledAt = ParseDateTime(dateInput:GetText(), timeInput:GetText())

        local raidID = time() + math.random(10000)
        RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}
        table.insert(RaidTrackDB.raidInstances, {
            id = raidID,
            name = name,
            preset = preset,
            status = "created",
            scheduledAt = scheduledAt,
            scheduledDate = dateInput:GetText(),
            scheduledTime = timeInput:GetText()
        })

        RaidTrack.AddDebugMessage("Raid created: " .. name)
        RaidTrack.RefreshRaidDropdown()
        RaidTrack.UpdateRaidTabStatus()
        RaidTrack.BroadcastRaidSync()

        frame:Hide()
        RaidTrack.raidCreateWindow = nil
        RaidTrack:OpenRaidCreationWindow()
    end)
    container:AddChild(confirmBtn)

    -- === SEPARATOR ===
    local heading = AceGUI:Create("Heading")
    heading:SetText("Existing Raids")
    heading:SetFullWidth(true)
    container:AddChild(heading)

    -- === RAID LIST ===
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    -- Build + sort a shallow copy so we don't mutate SavedVariables order
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}
    local raids = {}
    for i, r in ipairs(RaidTrackDB.raidInstances) do
        raids[i] = r
    end
    SortRaids(raids)

    for _, raid in ipairs(raids) do
        local group = AceGUI:Create("SimpleGroup")
        group:SetLayout("Flow")
        group:SetFullWidth(true)

        local label = AceGUI:Create("Label")
        local extra = ""
        if raid.status == "created" then
            if raid.scheduledDate and raid.scheduledTime then
                extra = string.format(" | %s %s", raid.scheduledDate, raid.scheduledTime)
            end
        elseif raid.status == "started" and raid.started then
            extra = string.format(" | started %s", date("%Y-%m-%d %H:%M", raid.started))
        elseif raid.status == "ended" and raid.ended then
            extra = string.format(" | ended %s", date("%Y-%m-%d %H:%M", raid.ended))
        end
        label:SetText(string.format("%s [%s]%s", raid.name or "Unnamed", raid.status or "unknown", extra))
        label:SetWidth(360)
        group:AddChild(label)

        local actionDD = AceGUI:Create("Dropdown")
        actionDD:SetWidth(120)
        actionDD:SetList({ Edit = "Edit", Start = "Start", Delete = "Delete" })
        actionDD:SetText("Actions")

        actionDD:SetCallback("OnValueChanged", function(_, _, value)
            if value == "Edit" then
                RaidTrack:OpenRaidConfigWindow(raid)

            elseif value == "Start" then
                raid.status = "started"
                raid.started = time()
                RaidTrack.activeRaidID = raid.id
                RaidTrackDB.activeRaidID = raid.id

                -- keep history entry; if your CreateRaidInstance accepts id, pass it
                RaidTrack.CreateRaidInstance(raid.name, GetRealZoneText() or "Unknown Zone", raid.preset, raid.id)

                RaidTrack.RefreshRaidDropdown()
                RaidTrack.UpdateRaidTabStatus()
                frame:Hide()

            elseif value == "Delete" then
                for i, r in ipairs(RaidTrackDB.raidInstances) do
                    if r.id == raid.id then
                        table.remove(RaidTrackDB.raidInstances, i)
                        break
                    end
                end
                RaidTrack.RefreshRaidDropdown()
                RaidTrack.UpdateRaidTabStatus()
                frame:Hide()
                RaidTrack.raidCreateWindow = nil
                RaidTrack:OpenRaidCreationWindow()
            end
        end)

        group:AddChild(actionDD)
        scroll:AddChild(group)
    end
end
