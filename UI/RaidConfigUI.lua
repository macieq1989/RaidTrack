local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- Ensure boss tables have keys for the actual difficulties of the selected instance
local function EnsureBossDifficultyKeys(config, instID)
    if not instID then
        return
    end
    local instance = RaidTrack.FindOfflineInstanceByID(instID)
    if not instance or not instance.difficulties then
        return
    end

    local diffs = {}
    for _, d in ipairs(instance.difficulties) do
        diffs[d] = true -- e.g., "25 Player", "40 Player", "Normal", "Heroic", "Mythic", "LFR"
    end

    -- Migrate existing bosses to contain ALL difficulty keys for this instance
    config.bosses = config.bosses or {}
    for bossName, tab in pairs(config.bosses) do
        tab = tab or {}
        for k in pairs(diffs) do
            if tab[k] == nil then
                tab[k] = 0
            end
        end
        -- opcjonalnie: usuń klucze trudności, które nie należą do tej instancji
        for k in pairs(tab) do
            if not diffs[k] then
                tab[k] = nil
            end
        end
        config.bosses[bossName] = tab
    end
end

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

        if not config.selectedInstance or config.selectedInstance == "" or not config.selectedDifficulty or
            config.selectedDifficulty == "" then

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
                config.bosses[b.name] = config.bosses[b.name] or {}
            end
            EnsureBossDifficultyKeys(config, config.selectedInstance)
        end

        for _, b in ipairs(bosses or {}) do

            local bossName = b.name
            local diff = config.selectedDifficulty
            config.bosses[bossName] = config.bosses[bossName] or {}
            EnsureBossDifficultyKeys(config, config.selectedInstance)

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
    if not flaskCB or not onTimeBox then
        C_Timer.After(0.1, function()
            RaidTrack.raidPresetDropdown:Fire("OnValueChanged", nil, val)
        end)
        return
    end

    local preset = RaidTrack.GetRaidPresets()[val]
    if not preset then
        return
    end

    -- odtwarzamy config z presetu
    config = preset
    config.selectedDifficulty = config.selectedDifficulty or "Normal"
    config.selectedInstance  = config.selectedInstance or nil
    config.minTimeInRaid     = config.minTimeInRaid or 15
    config.bosses            = config.bosses or {}

    -- odtwórz checkboxy / pola
    flaskCB:SetValue(config.requirements and config.requirements.flask or false)
    enchantsCB:SetValue(config.requirements and config.requirements.enchants or false)
    autoPassCB:SetValue(config.autoPass == nil and true or config.autoPass)

    onTimeBox:SetText(tostring(config.awardEP and config.awardEP.onTime or 0))
    bossKillBox:SetText(tostring(config.awardEP and config.awardEP.bossKill or 0))
    fullAttBox:SetText(tostring(config.awardEP and config.awardEP.fullAttendance or 0))
    minTimeBox:SetText(tostring(config.minTimeInRaid or 0))

    -- zresetuj listy
    expansionDD:SetList({ [""] = "Select Expansion..." }); expansionDD:SetValue("")
    instanceDD:SetList({ [""] = "Select Raid Instance..." }); instanceDD:SetValue("")
    difficultyDD:SetList({ [""] = "Select Difficulty..." }); difficultyDD:SetValue("")

    -- ustaw Expansion -> Instance -> Difficulty zgodnie z presetem
    local expansionID = RaidTrack.FindExpansionForInstance(config.selectedInstance)
    if not expansionID then
        -- jeżeli preset nie ma instancji, kończymy
        return
    end

    -- Expansion
    local expansions = RaidTrack.GetOfflineExpansions()
    local expMap = { [""] = "Select Expansion..." }
    for _, e in ipairs(expansions or {}) do expMap[e.expansionID] = e.name end
    expansionDD:SetList(expMap)
    expansionDD:SetValue(expansionID)
    expansionDD:Fire("OnValueChanged", expansionDD, expansionID)

    -- Instance
    local instances = RaidTrack.GetOfflineInstances(expansionID)
    local instMap = { [""] = "Select Raid Instance..." }
    for _, i in ipairs(instances or {}) do instMap[tostring(i.id)] = i.name end
    instanceDD:SetList(instMap)
    local instanceID = tostring(config.selectedInstance)
    if instMap[instanceID] then
        instanceDD:SetValue(instanceID)
        instanceDD:Fire("OnValueChanged", instanceDD, instanceID)
    end

    -- Difficulty
    local diffs = (function()
        local t = {}
        local inst = RaidTrack.FindOfflineInstanceByID(config.selectedInstance)
        if inst and inst.difficulties then
            for _, d in ipairs(inst.difficulties) do t[d] = d end
        end
        return t
    end)()
    local diffMap = { [""] = "Select Difficulty..." }
    for k, v in pairs(diffs) do diffMap[k] = v end
    difficultyDD:SetList(diffMap)
    local diff = config.selectedDifficulty or ""
    if diffMap[diff] then
        difficultyDD:SetValue(diff)
        difficultyDD:Fire("OnValueChanged", difficultyDD, diff)
    end

    -- 🔴 TU DOKŁADNIE: uzupełnij/napraw klucze trudności dla bossów z tego presetu
    EnsureBossDifficultyKeys(config, config.selectedInstance)

    -- odśwież panel bossów
    TryRenderBossPanel()
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
        RaidTrack.BroadcastRaidSync()

        -- po RaidTrack.BroadcastRaidSync() w Save Preset:
if RaidTrack.RefreshCreateRaidPresetDropdown then
    RaidTrack.RefreshCreateRaidPresetDropdown()
end


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
        RaidTrack.BroadcastRaidSync()

        -- po RaidTrack.BroadcastRaidSync() w Delete Preset:
if RaidTrack.RefreshCreateRaidPresetDropdown then
    RaidTrack.RefreshCreateRaidPresetDropdown()
end


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
        if instID == "" then
            difficultyDD:SetList({
                [""] = "Select Difficulty..."
            })
            difficultyDD:SetValue("")
            config.selectedInstance = nil
            config.selectedDifficulty = nil
            return
        end

        local numID = tonumber(instID)
        config.selectedInstance = numID

        -- Boss init (opcjonalnie)
        local bosses = RaidTrack.GetOfflineBosses(numID)
        if bosses then
    for _, b in ipairs(bosses) do
        config.bosses[b.name] = config.bosses[b.name] or {}
    end
    EnsureBossDifficultyKeys(config, tonumber(instID))
end


        -- Difficulty
        local diffs = GetDifficultiesForInstance(numID)
        local diffMap = {
            [""] = "Select Difficulty..."
        }
        for k, v in pairs(diffs) do
            diffMap[k] = v
        end
        difficultyDD:SetList(diffMap)
        difficultyDD:SetValue("")
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
    local expMap = {
        [""] = "Select Expansion..."
    } -- najpierw select
    for _, e in ipairs(expansions) do
        expMap[e.expansionID] = e.name
    end
    expansionDD:SetList(expMap)
    expansionDD:SetValue("") -- wybór domyślny to "Select Expansion..."

    -- Expansion Dropdown
    expansionDD:SetCallback("OnValueChanged", function(_, _, expID)
        if expID == "" then
            instanceDD:SetList({
                [""] = "Select Raid Instance..."
            })
            instanceDD:SetValue("")
            difficultyDD:SetList({
                [""] = "Select Difficulty..."
            })
            difficultyDD:SetValue("")
            config.selectedInstance = nil
            config.selectedDifficulty = nil
            return
        end

        local numID = tonumber(expID)
        local instances = RaidTrack.GetOfflineInstances(numID)
        if not instances or #instances == 0 then
            instanceDD:SetList({
                [""] = "Select Raid Instance..."
            })
            instanceDD:SetValue("")
            config.selectedInstance = nil
            config.selectedDifficulty = nil
            return
        end

        local instMap = {
            [""] = "Select Raid Instance..."
        }
        for _, i in ipairs(instances) do
            instMap[tostring(i.id)] = i.name
        end
        instanceDD:SetList(instMap)
        instanceDD:SetValue("")
        difficultyDD:SetList({
            [""] = "Select Difficulty..."
        })
        difficultyDD:SetValue("")
        config.selectedInstance = nil
        config.selectedDifficulty = nil
    end)

    -- Difficulty Dropdown callback
    difficultyDD:SetCallback("OnValueChanged", function(_, _, val)
        if val == "" then
            config.selectedDifficulty = nil
        else
            config.selectedDifficulty = val
        end
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

        local expMap = {
            [""] = "Select Expansion..."
        }
        for _, e in ipairs(expansions) do
            expMap[e.expansionID] = e.name
        end
        expansionDD:SetList(expMap)
        expansionDD:SetValue("") -- default "Select"

        instanceDD:SetList({
            [""] = "Select Raid Instance..."
        })
        instanceDD:SetValue("")

        difficultyDD:SetList({
            [""] = "Select Difficulty..."
        })
        difficultyDD:SetValue("")

        isConfigReady = true
    end)

end
