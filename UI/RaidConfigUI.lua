local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:OpenRaidConfigWindow()
    local bossPanel -- placeholder na dynamiczny panel z listą bossów
    local isConfigReady = false
    local flaskCB, enchantsCB, autoPassCB = nil, nil, nil
    local onTimeBox, bossKillBox, fullAttBox, minTimeBox = nil, nil, nil, nil
    local difficultyDD, expansionDD, instanceDD = nil, nil, nil -- ⬅ dodaj to tutaj!

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
        minTimeInRaid = 60,
        awardEP = {
            onTime = 5,
            bossKill = 0,
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

    autoPassCB = AceGUI:Create("CheckBox")
    autoPassCB:SetLabel("Auto-Pass for all players (except leader)")
    autoPassCB:SetValue(config.autoPass)
    autoPassCB:SetCallback("OnValueChanged", function(_, _, val)
        config.autoPass = val
    end)
    leftPanel:AddChild(autoPassCB)

    flaskCB = AceGUI:Create("CheckBox")
    flaskCB:SetLabel("Require Flask")
    flaskCB:SetValue(config.requirements.flask)
    flaskCB:SetCallback("OnValueChanged", function(_, _, val)
        config.requirements.flask = val
    end)
    leftPanel:AddChild(flaskCB)

    enchantsCB = AceGUI:Create("CheckBox")
    enchantsCB:SetLabel("Require Enchants")
    enchantsCB:SetValue(config.requirements.enchants)
    enchantsCB:SetCallback("OnValueChanged", function(_, _, val)
        config.requirements.enchants = val
    end)
    leftPanel:AddChild(enchantsCB)

    onTimeBox = AceGUI:Create("EditBox")
    onTimeBox:SetLabel("EP: On Time Bonus")
    onTimeBox:SetText(tostring(config.awardEP.onTime))
    onTimeBox:SetCallback("OnTextChanged", function(_, _, val)
        config.awardEP.onTime = tonumber(val) or 0
    end)
    leftPanel:AddChild(onTimeBox)

    bossKillBox = AceGUI:Create("EditBox")
    bossKillBox:SetLabel("EP: Per Boss Kill")
    bossKillBox:SetText(tostring(config.awardEP.bossKill))
    bossKillBox:SetCallback("OnTextChanged", function(_, _, val)
        config.awardEP.bossKill = tonumber(val) or 0
    end)
    leftPanel:AddChild(bossKillBox)

    fullAttBox = AceGUI:Create("EditBox")
    fullAttBox:SetLabel("EP: Full Attendance")
    fullAttBox:SetText(tostring(config.awardEP.fullAttendance))
    fullAttBox:SetCallback("OnTextChanged", function(_, _, val)
        config.awardEP.fullAttendance = tonumber(val) or 0
    end)
    leftPanel:AddChild(fullAttBox)

    local bossEPWindow -- zapamiętujemy okno, by nie otwierać wiele razy

    local function GetDifficultiesForInstance(instID)
        local instance = RaidTrack.FindOfflineInstanceByID(instID)
        if not instance then
            return {}
        end

        local list = {}
        for _, diff in ipairs(instance.difficulties or {}) do
            list[diff] = diff
        end
        return list
    end

    local function TryRenderBossPanel()
        if bossEPWindow then
            bossEPWindow:Release()
            bossEPWindow = nil
        end

        if not (config.selectedInstance and config.selectedDifficulty) then
            print("|cffff0000RaidTrack:|r Select instance and difficulty first.")
            return
        end

        local bosses = config.selectedInstance and RaidTrack.GetOfflineBosses(config.selectedInstance) or {}
        if not bosses or #bosses == 0 then
            print("|cffff0000RaidTrack:|r No bosses found for this instanceID: " .. tostring(config.selectedInstance))
            return
        end

        bossEPWindow = AceGUI:Create("Frame")
        bossEPWindow:SetTitle("Boss EP - " .. config.selectedDifficulty)
        bossEPWindow:SetLayout("Fill")
        bossEPWindow:SetWidth(300)
        bossEPWindow:EnableResize(false)

        -- Dopasuj wysokość i przypnij
        if RaidTrack.raidConfigWindow then
            local anchor = RaidTrack.raidConfigWindow.frame
            local height = anchor:GetHeight()
            bossEPWindow:SetHeight(height)

            local f = bossEPWindow.frame
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
        end

        bossEPWindow:SetCallback("OnClose", function()
            bossEPWindow = nil
        end)

        -- Scrollframe wewnątrz okna
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll:SetFullWidth(true)
        scroll:SetFullHeight(true)
        bossEPWindow:AddChild(scroll)

        if bosses then
            for _, b in ipairs(bosses) do
                config.bosses[b.name] = config.bosses[b.name] or {
                    Normal = 0,
                    Heroic = 0,
                    Mythic = 0
                }
            end
        end

        for _, b in ipairs(bosses or {}) do

            local bossName = b.name
            local diff = config.selectedDifficulty
            config.bosses[bossName] = config.bosses[bossName] or {
                Normal = 0,
                Heroic = 0,
                Mythic = 0
            }

            local epValue = config.bosses[bossName][diff] or 0

            local row = AceGUI:Create("EditBox")
            row:SetLabel(bossName)
            row:SetText(tostring(epValue))
            row:SetCallback("OnTextChanged", function(_, _, text)
                config.bosses[bossName][diff] = tonumber(text) or 0
            end)
            scroll:AddChild(row)
        end

    end

    -- Min. Time in Raid
    local minTimeBox = AceGUI:Create("EditBox")
    minTimeBox:SetLabel("Min. Time in Raid (minutes)")
    minTimeBox:SetText(tostring(config.minTimeInRaid))
    minTimeBox:SetCallback("OnTextChanged", function(_, _, val)
        config.minTimeInRaid = tonumber(val) or 0
    end)
    leftPanel:AddChild(minTimeBox)

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
        -- Bezpiecznik: odczekaj aż UI się w pełni zbuduje
        if not flaskCB or not onTimeBox then
            C_Timer.After(0.1, function()
                RaidTrack.raidPresetDropdown:Fire("OnValueChanged", nil, val)
            end)
            return
        end

        local preset = RaidTrack.GetRaidPresets()[val]
        if preset then
            config = preset
            config.selectedDifficulty = config.selectedDifficulty or "Normal"
            config.selectedInstance = config.selectedInstance or nil
            config.minTimeInRaid = config.minTimeInRaid or 15

            -- Odtwórz checkboxy
            flaskCB:SetValue(config.requirements.flask)
            enchantsCB:SetValue(config.requirements.enchants)
            autoPassCB:SetValue(config.autoPass)

            -- Odtwórz pola EP
            onTimeBox:SetText(tostring(config.awardEP.onTime))
            bossKillBox:SetText(tostring(config.awardEP.bossKill))
            fullAttBox:SetText(tostring(config.awardEP.fullAttendance))
            minTimeBox:SetText(tostring(config.minTimeInRaid))

            -- Ustaw dropdowny
            if config.selectedInstance then
                local foundExp = RaidTrack.FindExpansionForInstance(config.selectedInstance)
                if foundExp then
                    expansionDD:SetValue(foundExp)
                    expansionDD:Fire("OnValueChanged", expansionDD, foundExp)

                    C_Timer.After(0.1, function()
                        local instances = RaidTrack.GetOfflineInstances(foundExp)
                        local instMap = {}
                        for _, i in ipairs(instances or {}) do
                            instMap[tostring(i.id)] = i.name
                        end
                        instanceDD:SetList(instMap)

                        if instMap[tostring(config.selectedInstance)] then
                            instanceDD:SetValue(nil) -- reset najpierw, żeby trigger był pewny
C_Timer.After(0, function()
    instanceDD:SetValue(tostring(config.selectedInstance))
    instanceDD:Fire("OnValueChanged", instanceDD, config.selectedInstance)
end)


                            -- Difficulty
                            local diffs = GetDifficultiesForInstance(config.selectedInstance)
                            difficultyDD:SetList(diffs)
                            local diffToSet = config.selectedDifficulty or next(diffs)
                            if diffToSet then
                                difficultyDD:SetValue(diffToSet)
                                difficultyDD:Fire("OnValueChanged", difficultyDD, diffToSet)
                            end
                        end
                    end)
                end
            end

            TryRenderBossPanel()
        end
    end)

    leftPanel:AddChild(RaidTrack.raidPresetDropdown)

    local presetInput = AceGUI:Create("EditBox")
    presetInput:SetLabel("Save as Preset (name)")
    leftPanel:AddChild(presetInput)
    -- Kontener na przyciski w poziomie
    local buttonGroup = AceGUI:Create("SimpleGroup")
    buttonGroup:SetFullWidth(true)
    buttonGroup:SetLayout("Flow")
    leftPanel:AddChild(buttonGroup)

    -- Save Preset
    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save Preset")
    saveBtn:SetRelativeWidth(0.5)
    saveBtn:SetCallback("OnClick", function()
        local name = presetInput:GetText()
        if not name or name:trim() == "" then
            RaidTrack.AddDebugMessage("Save Preset clicked but no valid name given")
            return
        end

        config.minTimeInRaid = config.minTimeInRaid or 60

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
    buttonGroup:AddChild(saveBtn)

    -- Delete Preset
    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete Preset")
    deleteBtn:SetRelativeWidth(0.5)
    deleteBtn:SetCallback("OnClick", function()
        local name = RaidTrack.raidPresetDropdown:GetValue()
        if not name then
            return
        end

        RaidTrack.DeleteRaidPreset(name)

        local presets = RaidTrack.GetRaidPresetNames()
        local presetMap = {}
        for _, presetName in pairs(presets) do
            if presetName and presetName ~= "" then
                presetMap[presetName] = presetName
            end
        end
        RaidTrack.raidPresetDropdown:SetList(presetMap)
        RaidTrack.raidPresetDropdown:SetValue(nil)
    end)
    buttonGroup:AddChild(deleteBtn)

    local rightPanel = AceGUI:Create("InlineGroup")
    rightPanel:SetTitle("Boss EP Awards")
    rightPanel:SetRelativeWidth(0.5)
    rightPanel:SetFullHeight(true)
    rightPanel:SetLayout("List")
    mainGroup:AddChild(rightPanel)

    expansionDD = AceGUI:Create("Dropdown")
    expansionDD:SetLabel("Expansion")
    expansionDD:SetFullWidth(true)
    rightPanel:AddChild(expansionDD)

    instanceDD = AceGUI:Create("Dropdown")
    instanceDD:SetLabel("Raid Instance")
    instanceDD:SetFullWidth(true)

    -- Instance Dropdown
    instanceDD:SetCallback("OnValueChanged", function(_, _, instID)
        local numID = tonumber(instID)
        config.selectedInstance = numID

        -- Bosses
        local bosses = RaidTrack.GetOfflineBosses(numID)
        if bosses then
            for _, b in ipairs(bosses) do
                config.bosses[b.name] = config.bosses[b.name] or {
                    Normal = 0,
                    Heroic = 0,
                    Mythic = 0
                }
            end
        end

        -- 🔁 Ustawienia dropdownu Difficulty na podstawie instancji
        local diffs = GetDifficultiesForInstance(numID)
        difficultyDD:SetList(diffs)
        local defaultDiff = next(diffs)
        if defaultDiff then
            difficultyDD:SetValue(defaultDiff)
            config.selectedDifficulty = defaultDiff
        end
    end)

    rightPanel:AddChild(instanceDD)

    difficultyDD = AceGUI:Create("Dropdown")
    difficultyDD:SetLabel("Difficulty")
    difficultyDD:SetFullWidth(true)

    local defaultDiff = config.selectedDifficulty or "Normal"
    difficultyDD:SetValue(defaultDiff)
    difficultyDD:Fire("OnValueChanged", difficultyDD, defaultDiff)

    config.selectedDifficulty = config.selectedDifficulty or "Normal"

    rightPanel:AddChild(difficultyDD)

    local expansions = RaidTrack.GetOfflineExpansions()
    local expMap = {}
    for _, e in ipairs(expansions) do
        expMap[e.expansionID] = e.name
    end
    expansionDD:SetList(expMap)

    -- Expansion Dropdown
    expansionDD:SetCallback("OnValueChanged", function(_, _, expID)
        local numID = tonumber(expID)
        local instances = RaidTrack.GetOfflineInstances(numID)
        if not instances or #instances == 0 then
            instanceDD:SetList({})
            instanceDD:SetValue(nil)
            config.selectedInstance = nil
            return
        end

        -- Zbuduj listę instancji
        local instMap = {}
        for _, i in ipairs(instances) do
            instMap[tostring(i.id)] = i.name
        end
        instanceDD:SetList(instMap)

        -- Ustaw pierwszą instancję
        local firstInst = instances[1]
        if firstInst then
            instanceDD:SetValue(tostring(firstInst.id)) -- To odpali OnValueChanged
        end
    end)

    -- Difficulty Dropdown callback
    difficultyDD:SetCallback("OnValueChanged", function(_, _, val)
        config.selectedDifficulty = val
    end)

    local showBossesBtn = AceGUI:Create("Button")
    showBossesBtn:SetText("Show Boss List")
    showBossesBtn:SetCallback("OnClick", function()
        if not isConfigReady then
            print("|cffff0000RaidTrack:|r Configuration is still loading, please wait a moment.")
            return
        end
        if not config.selectedInstance or not config.selectedDifficulty then
            print("|cffff0000RaidTrack:|r Select instance and difficulty first.")
            return
        end
        TryRenderBossPanel()
    end)

    rightPanel:AddChild(showBossesBtn)

    local addBossBtn = AceGUI:Create("Button")
    addBossBtn:SetText("Add Custom Boss")
    addBossBtn:SetCallback("OnClick", function()
        StaticPopupDialogs["RT_ADD_BOSS"] = {
            text = "Enter boss name:",
            button1 = "Add",
            button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(self)
                local boss = self.editBox:GetText()
                if not boss or boss:trim() == "" then
                    return
                end

                config.bosses[boss] = config.bosses[boss] or {
                    Normal = 0,
                    Heroic = 0,
                    Mythic = 0
                }
                TryRenderBossPanel()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3
        }
        StaticPopup_Show("RT_ADD_BOSS")
    end)
    rightPanel:AddChild(addBossBtn)

    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Confirm")
    confirmBtn:SetFullWidth(true)
    confirmBtn:SetCallback("OnClick", function()
        RaidTrack.currentRaidConfig = config
        RaidTrack.AddDebugMessage("Current raid config confirmed.")
        frame:Hide()
    end)
    frame:AddChild(confirmBtn)
    -- Wymuszenie ustawienia domyślnych wartości dropdownów po pełnym załadowaniu
    C_Timer.After(0.2, function()
        local expansions = RaidTrack.GetOfflineExpansions()
        if not expansions or #expansions == 0 then
            return
        end

        local firstExp = expansions[1]
        if not firstExp then
            return
        end

        expansionDD:SetValue(firstExp.expansionID)

        -- RĘCZNIE załaduj instancje dla tego expansion
        local instances = RaidTrack.GetOfflineInstances(firstExp.expansionID)
        if not instances or #instances == 0 then
            return
        end

        local firstInst = instances[1]
        if not firstInst then
            return
        end

        local instMap = {}
        for _, i in ipairs(instances) do
            instMap[tostring(i.id)] = i.name
        end
        instanceDD:SetList(instMap)
        instanceDD:SetValue(tostring(firstInst.id))
        config.selectedInstance = firstInst.id

        -- RĘCZNIE załaduj difficulty dla tej instancji
        local diffs = GetDifficultiesForInstance(firstInst.id)
        difficultyDD:SetList(diffs)

        local defaultDiff = next(diffs)
        if defaultDiff then
            difficultyDD:SetValue(defaultDiff)
            config.selectedDifficulty = defaultDiff
        end

        isConfigReady = true
    end)

end
