-- UI/RaidCreateUI.lua
local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

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
    local presetList = {}
    for name, _ in pairs(RaidTrack.GetRaidPresets()) do
        presetList[name] = name
    end
    presetDD:SetList(presetList)
    container:AddChild(presetDD)

    local nameInput = AceGUI:Create("EditBox")
    nameInput:SetLabel("Raid Name")
    nameInput:SetFullWidth(true)
    nameInput:SetText("New Raid " .. date("%Y-%m-%d"))
    container:AddChild(nameInput)

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

        local raidID = time() + math.random(10000)
        RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

        table.insert(RaidTrackDB.raidInstances, {
            id = raidID,
            name = name,
            preset = preset,
            status = "created"
        })

        RaidTrack.AddDebugMessage("Raid created: " .. name)
        RaidTrack.RefreshRaidDropdown()
        RaidTrack.UpdateRaidTabStatus()
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

    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

    for _, raid in ipairs(RaidTrackDB.raidInstances) do
        local group = AceGUI:Create("SimpleGroup")
        group:SetLayout("Flow")
        group:SetFullWidth(true)

        local label = AceGUI:Create("Label")
        label:SetText(string.format("%s [%s]", raid.name or "Unnamed", raid.status or "unknown"))
        label:SetWidth(340)
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
                RaidTrack.activeRaidID = raid.id
                RaidTrackDB.activeRaidID = raid.id
                RaidTrack.CreateRaidInstance(raid.name, GetRealZoneText() or "Unknown Zone", raid.preset)
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


