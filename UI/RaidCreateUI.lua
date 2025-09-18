-- UI/RaidCreateUI.lua
local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- Helpers
local function dmsg(msg)
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(msg) end
end

local function BuildPresetList()
    local t = {}
    for name, _ in pairs(RaidTrack.GetRaidPresets()) do
        t[name] = name
    end
    return t
end

-- Sort order: started → created → ended
local STATUS_ORDER = { started = 1, created = 2, ended = 3 }

local function SortRaids(list)
    table.sort(list, function(a, b)
        local sa = STATUS_ORDER[a.status or "created"] or 2
        local sb = STATUS_ORDER[b.status or "created"] or 2
        if sa ~= sb then return sa < sb end

        if a.status == "started" then
            local ta = tonumber(a.started or 0) or 0
            local tb = tonumber(b.started or 0) or 0
            if ta ~= tb then return ta > tb end
        elseif a.status == "created" then
            local ta = tonumber(a.scheduledAt or math.huge) or math.huge
            local tb = tonumber(b.scheduledAt or math.huge) or math.huge
            if ta ~= tb then return ta < tb end
        elseif a.status == "ended" then
            local ta = tonumber(a.ended or 0) or 0
            local tb = tonumber(b.ended or 0) or 0
            if ta ~= tb then return ta > tb end
        end

        return (a.name or "") < (b.name or "")
    end)
end

-- Public: allow Config window to refresh the preset dropdown live
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

-- Internal: rebuild the raids list UI without closing the window
local function RebuildRaidsList(scroll, frame)
    if not scroll then return end
    scroll:ReleaseChildren()

    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}
    local raids = {}
    for i, r in ipairs(RaidTrackDB.raidInstances) do raids[i] = r end
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
                if RaidTrack.OpenRaidConfigWindow then
                    RaidTrack:OpenRaidConfigWindow(raid)
                else
                    dmsg("OpenRaidConfigWindow missing (check .toc order).")
                end

            elseif value == "Start" then
                -- block starting another when one is active
                if RaidTrack.activeRaidID and tostring(RaidTrack.activeRaidID) ~= tostring(raid.id) then
                    dmsg("Another raid is currently active. End it first.")
                    actionDD:SetText("Actions"); actionDD:SetValue(nil)
                    return
                end

                raid.status  = "started"
                raid.started = time()
                RaidTrack.activeRaidID   = raid.id
                RaidTrackDB.activeRaidID = raid.id

                -- if history already has this id as started → don't duplicate
                local existsStarted = false
                for _, h in ipairs(RaidTrackDB.raidHistory or {}) do
                    if tostring(h.id) == tostring(raid.id) and (h.status == "started" or (h.started and not h.ended)) then
                        existsStarted = true
                        if h.settings then RaidTrack.currentRaidConfig = h.settings end
                        break
                    end
                end

                if not existsStarted then
                    RaidTrack.CreateRaidInstance(
                        raid.name,
                        GetRealZoneText() or "Unknown Zone",
                        raid.preset,
                        raid.id
                    )
                else
                    if RaidTrack.RefreshRaidDropdown then RaidTrack.RefreshRaidDropdown() end
                    if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end
                    if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end
                end

                RebuildRaidsList(scroll, frame)

            elseif value == "Delete" then
                if raid.status == "started" or (RaidTrack.activeRaidID and tostring(RaidTrack.activeRaidID) == tostring(raid.id)) then
                    dmsg("Cannot delete a started/active raid. End it first.")
                    actionDD:SetText("Actions"); actionDD:SetValue(nil)
                    return
                end

                for i, r in ipairs(RaidTrackDB.raidInstances) do
                    if r.id == raid.id then
                        table.remove(RaidTrackDB.raidInstances, i)
                        break
                    end
                end

                if RaidTrack.RefreshRaidDropdown then RaidTrack.RefreshRaidDropdown() end
                if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end
                if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end

                RebuildRaidsList(scroll, frame)
            end

            -- reset dropdown label after action
            actionDD:SetText("Actions"); actionDD:SetValue(nil)
        end)

        group:AddChild(actionDD)
        scroll:AddChild(group)
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
    RaidTrack._createPresetDD = presetDD

    local nameInput = AceGUI:Create("EditBox")
    nameInput:SetLabel("Raid Name")
    nameInput:SetFullWidth(true)
    nameInput:SetText("New Raid " .. date("%Y-%m-%d"))
    container:AddChild(nameInput)

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

    -- Button: Create Raid
    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Create Raid")
    confirmBtn:SetFullWidth(true)
    confirmBtn:SetCallback("OnClick", function()
        local preset = presetDD:GetValue()
        local name = nameInput:GetText()

        if not preset or preset == "" then
            dmsg("Please select a preset.")
            return
        end
        if not name or name == "" then
            dmsg("Please enter a raid name.")
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

        dmsg("Raid created: " .. name)

        -- odśwież dropdown w zakładce, status, broadcast
        if RaidTrack.RefreshRaidDropdown then RaidTrack.RefreshRaidDropdown() end
        if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end
        if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end

        -- wyczyść pola i ODNAWIA listę “Existing Raids”
        presetDD:SetValue(nil)
        nameInput:SetText("New Raid " .. date("%Y-%m-%d"))

        -- rebuild listy w tym samym oknie
        RebuildRaidsList(RaidTrack._raidCreateScroll, frame)
    end)
    container:AddChild(confirmBtn)

    -- === Existing Raids ===
    local heading = AceGUI:Create("Heading")
    heading:SetText("Existing Raids")
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    container:AddChild(scroll)

    -- zapamiętaj referencję, by dać się odbudować z innych callbacków
    RaidTrack._raidCreateScroll = scroll

    -- initial build
    RebuildRaidsList(scroll, frame)
end
