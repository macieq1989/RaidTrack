local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:OpenRaidConfigWindow()
    if self.raidConfigWindow then
        self.raidConfigWindow:Show()
        return
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Raid Configuration")
    frame:SetStatusText("Configure raid settings")
    frame:SetLayout("List")
    frame:SetWidth(700)
    frame:SetHeight(600)
    frame:EnableResize(true)
    self.raidConfigWindow = frame

    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetHeight(540)
    mainGroup:SetLayout("Flow")
    frame:AddChild(mainGroup)

    local leftPanel = AceGUI:Create("InlineGroup")
    leftPanel:SetTitle("General Settings")
    leftPanel:SetRelativeWidth(0.5)
    leftPanel:SetFullHeight(true)
    leftPanel:SetLayout("List")
    mainGroup:AddChild(leftPanel)

    local config = {
        autoPass = true,
        lootMode = "auction",
        awardEP = {
            onTime = 5,
            bossKill = 10,
            fullAttendance = 15
        },
        requirements = {
            flask = true,
            enchants = true
        },
        bosses = {}
    }

    local function AddCheckbox(label, value, callback)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetValue(value)
        cb:SetCallback("OnValueChanged", function(_, _, val)
            callback(val)
        end)
        leftPanel:AddChild(cb)
    end

    AddCheckbox("Auto-Pass for all players (except leader)", config.autoPass, function(val)
        config.autoPass = val
    end)
    AddCheckbox("Require Flask", config.requirements.flask, function(val)
        config.requirements.flask = val
    end)
    AddCheckbox("Require Enchants", config.requirements.enchants, function(val)
        config.requirements.enchants = val
    end)

    -- Loot Mode Dropdown with validation
    local lootList = {
        manual = "Manual",
        auction = "Auction",
        softres = "Soft-reserve"
    }
    local lootMode = AceGUI:Create("Dropdown")
    lootMode:SetLabel("Loot Mode")
    lootMode:SetList(lootList)

    if config.lootMode and lootList[config.lootMode] then
        lootMode:SetValue(config.lootMode)
    else
        lootMode:SetValue("auction")
        config.lootMode = "auction"
    end

    lootMode:SetCallback("OnValueChanged", function(_, _, val)
        config.lootMode = val
    end)
    leftPanel:AddChild(lootMode)

    local function AddEPBox(label, field)
        local box = AceGUI:Create("EditBox")
        box:SetLabel(label)
        box:SetText(tostring(config.awardEP[field]))
        box:SetCallback("OnTextChanged", function(_, _, val)
            config.awardEP[field] = tonumber(val) or 0
        end)
        leftPanel:AddChild(box)
    end

    AddEPBox("EP: On Time Bonus", "onTime")
    AddEPBox("EP: Per Boss Kill", "bossKill")
    AddEPBox("EP: Full Attendance", "fullAttendance")

    -- Preset Dropdown
    RaidTrack.raidPresetDropdown = AceGUI:Create("Dropdown")
    RaidTrack.raidPresetDropdown:SetLabel("Load Raid Preset")
    RaidTrack.raidPresetDropdown:SetFullWidth(true)

    local presets = RaidTrack.GetRaidPresetNames() or {}
    local presetMap = {}

    for _, name in pairs(presets) do
        if name and name ~= "" then
            presetMap[name] = name
        end
    end

    if next(presetMap) then
        RaidTrack.raidPresetDropdown:SetList(presetMap)
        local firstKey = next(presetMap)
        RaidTrack.raidPresetDropdown:SetValue(firstKey)
    else
        RaidTrack.raidPresetDropdown:SetList({})
    end

    RaidTrack.raidPresetDropdown:SetCallback("OnValueChanged", function(_, _, val)
        local preset = RaidTrack.GetRaidPresets()[val]
        if preset then
            config = preset
            -- TODO: optionally refresh UI fields with preset data
        end
    end)

    leftPanel:AddChild(RaidTrack.raidPresetDropdown)

    -- Preset input + save
    local presetInput = AceGUI:Create("EditBox")
    presetInput:SetLabel("Save as Preset (name)")
    leftPanel:AddChild(presetInput)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save Preset")
    saveBtn:SetCallback("OnClick", function()
        local name = presetInput:GetText()
        if not name or name:trim() == "" then
            RaidTrack.AddDebugMessage("Save Preset clicked but no valid name given")
            return
        end

        RaidTrack.SaveRaidPreset(name, config)

        local presets = RaidTrack.GetRaidPresetNames()

        local presetMap = {}
        for _, presetName in pairs(presets) do
            if presetName and presetName ~= "" then
                presetMap[presetName] = presetName
            end
        end
        RaidTrack.raidPresetDropdown:SetList(presetMap)
        if presetMap[name] then
            RaidTrack.raidPresetDropdown:SetValue(name)
        end
    end)
    leftPanel:AddChild(saveBtn)

    -- Right panel
    local rightPanel = AceGUI:Create("InlineGroup")
    rightPanel:SetTitle("Boss EP Awards")
    rightPanel:SetRelativeWidth(0.5)
    rightPanel:SetFullHeight(true)
    rightPanel:SetLayout("List")
    mainGroup:AddChild(rightPanel)

    local expansionDD = AceGUI:Create("Dropdown")
    expansionDD:SetLabel("Expansion")
    expansionDD:SetFullWidth(true)
    rightPanel:AddChild(expansionDD)

    local instanceDD = AceGUI:Create("Dropdown")
    instanceDD:SetLabel("Raid Instance")
    instanceDD:SetFullWidth(true)
    rightPanel:AddChild(instanceDD)

    local bossList = AceGUI:Create("ScrollFrame")
    bossList:SetLayout("List")
    bossList:SetFullWidth(true)
    bossList:SetFullHeight(true)
    rightPanel:AddChild(bossList)

    local function RenderBossList()
        bossList:ReleaseChildren()
        for boss, diffs in pairs(config.bosses or {}) do
            local header = AceGUI:Create("Label")
            header:SetText(boss)
            header:SetFontObject(GameFontHighlight)
            bossList:AddChild(header)
            for diff, val in pairs(diffs) do
                local row = AceGUI:Create("EditBox")
                row:SetLabel(diff)
                row:SetText(tostring(val))
                row:SetCallback("OnTextChanged", function(_, _, text)
                    config.bosses[boss][diff] = tonumber(text) or 0
                end)
                bossList:AddChild(row)
            end
        end
    end

    -- Expansion list
    local expansions = RaidTrack.GetOfflineExpansions()
    local expMap = {}
    for _, e in ipairs(expansions) do
        expMap[e.expansionID] = e.name
    end
    expansionDD:SetList(expMap)

    expansionDD:SetCallback("OnValueChanged", function(_, _, expID)
        local instances = RaidTrack.GetOfflineInstances(expID)
        local instMap = {}
        for _, i in ipairs(instances) do
            instMap[i.id] = i.name
        end
        instanceDD:SetList(instMap)
        instanceDD:SetValue(nil)
    end)

    instanceDD:SetCallback("OnValueChanged", function(_, _, instID)
        local bosses = RaidTrack.GetOfflineBosses(instID)
        for _, b in ipairs(bosses) do
            config.bosses[b.name] = config.bosses[b.name] or {
                Normal = 0,
                Heroic = 0,
                Mythic = 0
            }
        end
        RenderBossList()
    end)

    local addBossBtn = AceGUI:Create("Button")
    addBossBtn:SetText("Add Boss")
    addBossBtn:SetCallback("OnClick", function()
        StaticPopupDialogs["RT_ADD_BOSS"] = {
            text = "Enter boss name:",
            button1 = "Add",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local boss = self.editBox:GetText()
                config.bosses[boss] = {
                    Normal = 0,
                    Heroic = 0,
                    Mythic = 0
                }
                RenderBossList()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3
        }
        StaticPopup_Show("RT_ADD_BOSS")
    end)
    rightPanel:AddChild(addBossBtn)

    if config.bosses then
        C_Timer.After(0.1, RenderBossList)
    end

    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Confirm")
    confirmBtn:SetFullWidth(true)
    confirmBtn:SetCallback("OnClick", function()
        RaidTrack.currentRaidConfig = config
        RaidTrack.AddDebugMessage("Current raid config confirmed.")
        frame:Hide()
    end)
    frame:AddChild(confirmBtn)
end
