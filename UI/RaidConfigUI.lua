-- UI/RaidConfigUI.lua
local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

-- ===== Helpers =====
local function dmsg(msg)
    if RaidTrack and RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(msg) end
end

local function SafeCopyTable(src)
    if type(src) ~= "table" then return src end
    if type(CopyTable) == "function" then
        return CopyTable(src)
    end
    local function deep(t)
        local r = {}
        for k, v in pairs(t) do
            r[k] = (type(v) == "table") and deep(v) or v
        end
        return r
    end
    return deep(src)
end

-- Dopina/porządkuje klucze trudności dla bossów wg wybranej instancji
local function EnsureBossDifficultyKeys(config, instID)
    if not instID then return end
    local inst = RaidTrack.FindOfflineInstanceByID and RaidTrack.FindOfflineInstanceByID(tonumber(instID))
    if not (inst and inst.difficulties) then return end

    local diffs = {}
    for _, d in ipairs(inst.difficulties) do diffs[d] = true end

    config.bosses = config.bosses or {}
    for bossName, tab in pairs(config.bosses) do
        tab = tab or {}
        -- dodaj brakujące
        for k in pairs(diffs) do
            if tab[k] == nil then tab[k] = 0 end
        end
        -- usuń obce
        for k in pairs(tab) do
            if not diffs[k] then tab[k] = nil end
        end
        config.bosses[bossName] = tab
    end
end

-- Mapy dla dropdownów (string keys)
local function SKey(v) return tostring(v or "") end

local function MakeMapExpansions()
    local t = { [""] = "Select Expansion..." }
    for _, e in ipairs(RaidTrack.GetOfflineExpansions and (RaidTrack.GetOfflineExpansions() or {}) or {}) do
        t[SKey(e.expansionID)] = e.name
    end
    return t
end

local function MakeMapInstances(expID)
    local t = { [""] = "Select Raid Instance..." }
    for _, i in ipairs(RaidTrack.GetOfflineInstances and (RaidTrack.GetOfflineInstances(tonumber(expID)) or {}) or {}) do
        t[SKey(i.id)] = i.name
    end
    return t
end

local function MakeMapDifficulties(instID)
    local t = { [""] = "Select Difficulty..." }
    local inst = RaidTrack.FindOfflineInstanceByID and RaidTrack.FindOfflineInstanceByID(tonumber(instID))
    if inst and inst.difficulties then
        for _, d in ipairs(inst.difficulties) do t[d] = d end
    end
    return t
end

-- ===== Główne okno konfiguracji =====
function RaidTrack:OpenRaidConfigWindow(contextRaid)
    -- nie duplikuj okna
    if self.raidConfigWindow then
        self.raidConfigWindow:Show()
        return
    end

    -- Bieżący config (lokalna kopia, nie SV)
    local config = {
        autoPass      = true,
        minTimeInRaid = 60,
        awardEP       = { onTime = 5, bossKill = 0, fullAttendance = 15 },
        requirements  = { flask = true, enchants = true },
        bosses        = {},
        selectedInstance   = nil,
        selectedDifficulty = nil,
    }

    -- Jeśli mamy aktywny raid i jego snapshot, użyj go jako start
    if RaidTrack.currentRaidConfig then
        config = SafeCopyTable(RaidTrack.currentRaidConfig)
    end

    -- UI: okno główne
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

    -- LEWY panel (ustawienia ogólne)
    local leftPanel = AceGUI:Create("InlineGroup")
    leftPanel:SetTitle("General Settings")
    leftPanel:SetRelativeWidth(0.5)
    leftPanel:SetFullHeight(true)
    leftPanel:SetLayout("List")
    mainGroup:AddChild(leftPanel)

    -- PRAWY panel (instancja / trudność / bossy)
    local rightPanel = AceGUI:Create("InlineGroup")
    rightPanel:SetTitle("Boss EP Awards")
    rightPanel:SetRelativeWidth(0.5)
    rightPanel:SetFullHeight(true)
    rightPanel:SetLayout("List")
    mainGroup:AddChild(rightPanel)

    -- Kontrolki (lewy panel)
    local autoPassCB, flaskCB, enchCB
    local onTimeBox, bossKillBox, fullAttBox, minTimeBox

    local function AddCheckbox(label, value, setter)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetValue(value and true or false)
        cb:SetCallback("OnValueChanged", function(_, _, v) setter(v and true or false) end)
        leftPanel:AddChild(cb)
        return cb
    end

    autoPassCB = AddCheckbox("Auto-Pass for all players (except leader)", config.autoPass, function(v) config.autoPass = v end)
    flaskCB    = AddCheckbox("Require Flask",    config.requirements.flask,   function(v) config.requirements.flask = v end)
    enchCB     = AddCheckbox("Require Enchants", config.requirements.enchants,function(v) config.requirements.enchants = v end)

    onTimeBox = AceGUI:Create("EditBox")
    onTimeBox:SetLabel("EP: On Time Bonus")
    onTimeBox:SetText(tostring(config.awardEP.onTime or 0))
    onTimeBox:SetCallback("OnTextChanged", function(_, _, val) config.awardEP.onTime = tonumber(val) or 0 end)
    leftPanel:AddChild(onTimeBox)

    bossKillBox = AceGUI:Create("EditBox")
    bossKillBox:SetLabel("EP: Per Boss Kill")
    bossKillBox:SetText(tostring(config.awardEP.bossKill or 0))
    bossKillBox:SetCallback("OnTextChanged", function(_, _, val) config.awardEP.bossKill = tonumber(val) or 0 end)
    leftPanel:AddChild(bossKillBox)

    fullAttBox = AceGUI:Create("EditBox")
    fullAttBox:SetLabel("EP: Full Attendance")
    fullAttBox:SetText(tostring(config.awardEP.fullAttendance or 0))
    fullAttBox:SetCallback("OnTextChanged", function(_, _, val) config.awardEP.fullAttendance = tonumber(val) or 0 end)
    leftPanel:AddChild(fullAttBox)

    minTimeBox = AceGUI:Create("EditBox")
    minTimeBox:SetLabel("Min. Time in Raid (minutes)")
    minTimeBox:SetText(tostring(config.minTimeInRaid or 60))
    minTimeBox:SetCallback("OnTextChanged", function(_, _, val) config.minTimeInRaid = tonumber(val) or 0 end)
    leftPanel:AddChild(minTimeBox)

    -- Dropdown do ładowania presetów (lewy panel)
    local presetLoadDD = AceGUI:Create("Dropdown")
    presetLoadDD:SetLabel("Load Raid Preset")
    presetLoadDD:SetFullWidth(true)
    leftPanel:AddChild(presetLoadDD)
    RaidTrack.raidPresetDropdown = presetLoadDD  -- ułatwia zewn. odświeżenia (z innych okien)

    local function RefreshPresetList()
        local presets = RaidTrack.GetRaidPresetNames and RaidTrack.GetRaidPresetNames() or {}
        local map = {}
        for _, n in pairs(presets) do if n and n ~= "" then map[n] = n end end
        presetLoadDD:SetList(map)
    end
    RefreshPresetList()

    -- PRAWY: dropdowny exp/inst/diff (muszą być ZAINICJALIZOWANE zanim ustawimy callback presetu!)
    local expDD, instDD, diffDD

    expDD = AceGUI:Create("Dropdown")
    expDD:SetLabel("Expansion")
    expDD:SetFullWidth(true)
    rightPanel:AddChild(expDD)

    instDD = AceGUI:Create("Dropdown")
    instDD:SetLabel("Raid Instance")
    instDD:SetFullWidth(true)
    rightPanel:AddChild(instDD)

    diffDD = AceGUI:Create("Dropdown")
    diffDD:SetLabel("Difficulty")
    diffDD:SetFullWidth(true)
    rightPanel:AddChild(diffDD)

    -- Boss panel (wyskakujące okno listy bossów)
    local bossPanel
    local function TryRenderBossPanel(cfg)
        if bossPanel then bossPanel:Release(); bossPanel = nil end

        if not cfg.selectedInstance or not cfg.selectedDifficulty
           or cfg.selectedInstance == "" or cfg.selectedDifficulty == "" then
            dmsg("Select instance and difficulty first.")
            return
        end

        local bosses = RaidTrack.GetOfflineBosses and (RaidTrack.GetOfflineBosses(cfg.selectedInstance) or {}) or {}
        if #bosses == 0 then
            dmsg("No bosses found for instanceID: "..tostring(cfg.selectedInstance))
            return
        end

        bossPanel = AceGUI:Create("Frame")
        bossPanel:SetTitle("Boss EP - " .. cfg.selectedDifficulty)
        bossPanel:SetLayout("Fill")
        bossPanel:SetWidth(320)
        bossPanel:EnableResize(false)

        -- doklej obok okna głównego
        if RaidTrack.raidConfigWindow then
            local anchor = RaidTrack.raidConfigWindow.frame
            bossPanel:SetHeight(anchor:GetHeight())
            local f = bossPanel.frame
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
        end
        bossPanel:SetCallback("OnClose", function() bossPanel = nil end)

        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll:SetFullWidth(true)
        scroll:SetFullHeight(true)
        bossPanel:AddChild(scroll)

        -- zapewnij strukturę bossów i trudności
        cfg.bosses = cfg.bosses or {}
        for _, b in ipairs(bosses) do
            cfg.bosses[b.name] = cfg.bosses[b.name] or {}
        end
        EnsureBossDifficultyKeys(cfg, cfg.selectedInstance)

        for _, b in ipairs(bosses) do
            local bossName = b.name
            local diff = cfg.selectedDifficulty
            local epVal = cfg.bosses[bossName][diff] or 0

            local row = AceGUI:Create("EditBox")
            row:SetLabel(bossName)
            row:SetText(tostring(epVal))
            row:SetCallback("OnTextChanged", function(_, _, text)
                cfg.bosses[bossName][diff] = tonumber(text) or 0
            end)
            scroll:AddChild(row)
        end
    end

    -- CALLBACKI PRAWYCH DROPDOWNÓW
    expDD:SetCallback("OnValueChanged", function(_, _, expID)
        if expID == "" then
            instDD:SetList({ [""] = "Select Raid Instance..." }); instDD:SetValue("")
            diffDD:SetList({ [""] = "Select Difficulty..." });    diffDD:SetValue("")
            config.selectedInstance, config.selectedDifficulty = nil, nil
            return
        end
        instDD:SetList(MakeMapInstances(expID))
        instDD:SetValue("")
        diffDD:SetList({ [""] = "Select Difficulty..." }); diffDD:SetValue("")
        config.selectedInstance, config.selectedDifficulty = nil, nil
    end)

    instDD:SetCallback("OnValueChanged", function(_, _, instID)
        if instID == "" then
            diffDD:SetList({ [""] = "Select Difficulty..." }); diffDD:SetValue("")
            config.selectedInstance, config.selectedDifficulty = nil, nil
            return
        end
        config.selectedInstance = tonumber(instID)
        -- przygotuj strukturę bossów i klucze trudności
        local bosses = RaidTrack.GetOfflineBosses and RaidTrack.GetOfflineBosses(config.selectedInstance) or {}
        for _, b in ipairs(bosses) do
            config.bosses[b.name] = config.bosses[b.name] or {}
        end
        EnsureBossDifficultyKeys(config, config.selectedInstance)
        diffDD:SetList(MakeMapDifficulties(instID))
        diffDD:SetValue("")
        config.selectedDifficulty = nil
    end)

    diffDD:SetCallback("OnValueChanged", function(_, _, val)
        config.selectedDifficulty = (val ~= "" and val or nil)
    end)

    -- PRZYCISKI PRAWY PANEL
    local showBossesBtn = AceGUI:Create("Button")
    showBossesBtn:SetText("Show Boss List")
    showBossesBtn:SetCallback("OnClick", function()
        if not config.selectedInstance or not config.selectedDifficulty then
            dmsg("Select instance and difficulty first.")
            return
        end
        TryRenderBossPanel(config)
    end)
    rightPanel:AddChild(showBossesBtn)

    local addBossBtn = AceGUI:Create("Button")
    addBossBtn:SetText("Add Custom Boss")
    addBossBtn:SetCallback("OnClick", function()
        StaticPopupDialogs["RT_ADD_BOSS"] = {
            text = "Enter boss name:",
            button1 = "Add", button2 = "Cancel",
            hasEditBox = true,
            OnAccept = function(selfPopup)
                local boss = selfPopup.editBox:GetText()
                if not boss or boss == "" then return end
                config.bosses = config.bosses or {}
                config.bosses[boss] = config.bosses[boss] or { Normal = 0, Heroic = 0, Mythic = 0 }
                EnsureBossDifficultyKeys(config, config.selectedInstance)
                TryRenderBossPanel(config)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3
        }
        StaticPopup_Show("RT_ADD_BOSS")
    end)
    rightPanel:AddChild(addBossBtn)

    -- CALLBACK ŁADOWANIA PRESETU (PO utworzeniu expDD/instDD/diffDD!)
    presetLoadDD:SetCallback("OnValueChanged", function(_, _, val)
        if not val or val == "" then return end
        local preset = (RaidTrack.GetRaidPresets and RaidTrack.GetRaidPresets() or {})[val]
        if not preset then return end

        config = SafeCopyTable(preset)
        config.awardEP       = config.awardEP or { onTime = 0, bossKill = 0, fullAttendance = 0 }
        config.requirements  = config.requirements or { flask = false, enchants = false }
        config.bosses        = config.bosses or {}
        config.minTimeInRaid = tonumber(config.minTimeInRaid) or 60

        -- odśwież LEWY panel
        autoPassCB:SetValue(config.autoPass and true or false)
        flaskCB:SetValue(config.requirements.flask and true or false)
        enchCB:SetValue(config.requirements.enchants and true or false)
        onTimeBox:SetText(tostring(config.awardEP.onTime))
        bossKillBox:SetText(tostring(config.awardEP.bossKill))
        fullAttBox:SetText(tostring(config.awardEP.fullAttendance))
        minTimeBox:SetText(tostring(config.minTimeInRaid))

        -- odśwież PRAWY panel – krokami, z eventami
        expDD:SetList(MakeMapExpansions()); expDD:SetValue(nil)
        instDD:SetList({ [""] = "Select Raid Instance..." }); instDD:SetValue(nil)
        diffDD:SetList({ [""] = "Select Difficulty..." });    diffDD:SetValue(nil)

        local expID = RaidTrack.FindExpansionForInstance and RaidTrack.FindExpansionForInstance(config.selectedInstance)
        if expID then
            local expKey = SKey(expID)
            expDD:SetValue(expKey); expDD:Fire("OnValueChanged", expDD, expKey)

            local instKey = SKey(config.selectedInstance)
            local imap = MakeMapInstances(expKey)
            instDD:SetList(imap)
            if imap[instKey] then
                instDD:SetValue(instKey); instDD:Fire("OnValueChanged", instDD, instKey)
            end

            local dmap = MakeMapDifficulties(instKey)
            diffDD:SetList(dmap)
            local diff = config.selectedDifficulty or ""
            if dmap[diff] then
                diffDD:SetValue(diff); diffDD:Fire("OnValueChanged", diffDD, diff)
            end

            EnsureBossDifficultyKeys(config, config.selectedInstance)
        end

        dmsg("[RaidConfigUI] Preset loaded into UI: "..tostring(val))
    end)

    -- SAVE / DELETE PRESET (lewy panel)
    local presetInput = AceGUI:Create("EditBox")
    presetInput:SetLabel("Save as Preset (name)")
    leftPanel:AddChild(presetInput)

    local buttonGroup = AceGUI:Create("SimpleGroup")
    buttonGroup:SetFullWidth(true)
    buttonGroup:SetLayout("Flow")
    leftPanel:AddChild(buttonGroup)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save Preset")
    saveBtn:SetRelativeWidth(0.5)
    saveBtn:SetCallback("OnClick", function()
        local name = presetInput:GetText()
        if not name or name == "" then
            dmsg("Save Preset clicked but no valid name given")
            return
        end
        config.minTimeInRaid = tonumber(config.minTimeInRaid) or 60
        RaidTrack.SaveRaidPreset(name, config)
        RaidTrack.BroadcastRaidSync = RaidTrack.BroadcastRaidSync or function() end
        if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end
        RefreshPresetList()
        presetLoadDD:SetValue(name)
        presetLoadDD:Fire("OnValueChanged", presetLoadDD, name)
    end)
    buttonGroup:AddChild(saveBtn)

    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete Preset")
    deleteBtn:SetRelativeWidth(0.5)
    deleteBtn:SetCallback("OnClick", function()
        local name = presetLoadDD:GetValue()
        if not name or name == "" then return end
        RaidTrack.DeleteRaidPreset(name)
        if RaidTrack.BroadcastRaidSync then RaidTrack.BroadcastRaidSync() end
        RefreshPresetList()
        presetLoadDD:SetValue(nil)
    end)
    buttonGroup:AddChild(deleteBtn)

    -- Wstępne listy dla dropdownów po prawej
    expDD:SetList(MakeMapExpansions()); expDD:SetValue("")
    instDD:SetList({ [""] = "Select Raid Instance..." }); instDD:SetValue("")
    diffDD:SetList({ [""] = "Select Difficulty..." });    diffDD:SetValue("")

    -- Potwierdzenie – tylko aktualny config, bez zapisu presetu
    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Confirm")
    confirmBtn:SetFullWidth(true)
    confirmBtn:SetCallback("OnClick", function()
        RaidTrack.currentRaidConfig = SafeCopyTable(config)
        dmsg("Current raid config confirmed.")
        frame:Hide()
    end)
    frame:AddChild(confirmBtn)
end
