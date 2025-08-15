local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

RaidTrack.settingsTabData = RaidTrack.settingsTabData or {}

function RaidTrack:Render_settingsTab(container)

    GameTooltip:Hide()
    if AceGUI and AceGUI.ClearFocus then
        AceGUI:ClearFocus()
    end

    container:SetLayout("Fill")
    container:SetFullHeight(true)

    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    mainGroup:SetLayout("List")
    container:AddChild(mainGroup)

    -- TOP GROUP (checkboxy, dropdown, buttons)
    local topGroup = AceGUI:Create("SimpleGroup")
    topGroup:SetFullWidth(true)
    topGroup:SetLayout("Flow")
    mainGroup:AddChild(topGroup)

    -- Access control (UI gating) — stacked label + dropdown
    do
        -- Section header
        local acTitle = AceGUI:Create("Label")
        acTitle:SetText("Access control")
        acTitle:SetFontObject(GameFontHighlightLarge)
        acTitle:SetFullWidth(true)
        topGroup:AddChild(acTitle)

        -- Spacer
        local spacer1 = AceGUI:Create("Label")
        spacer1:SetText(" ")
        spacer1:SetFullWidth(true)
        spacer1:SetHeight(4)
        topGroup:AddChild(spacer1)

        -- Label for dropdown
        local acLabel = AceGUI:Create("Label")
        acLabel:SetText("Minimum guild rank to unlock features")
        acLabel:SetFullWidth(true)
        acLabel:SetHeight(20)
        topGroup:AddChild(acLabel)

        -- Dropdown itself
        local dd = AceGUI:Create("Dropdown")
        dd:SetWidth(200)
        local values, order = RaidTrack.GetGuildRanks()
        dd:SetList(values, order)
        dd:SetValue(RaidTrack.GetMinUITabRank())

        dd:SetCallback("OnValueChanged", function(_, _, key)
            key = tonumber(key)
            -- (opcjonalnie) tylko oficer może zmieniać
            if not (RaidTrack.IsOfficer and RaidTrack.IsOfficer()) then
                RaidTrack.AddDebugMessage("Only officers can change access control.")
                dd:SetValue(RaidTrack.GetMinUITabRank())
                return
            end

            RaidTrackDB.settings = RaidTrackDB.settings or {}
            RaidTrackDB.settings.minUITabRankIndex = key

            if RaidTrack.ApplyUITabVisibility then
                RaidTrack.ApplyUITabVisibility()
            end
            if RaidTrack.RefreshMinimapMenu then
                RaidTrack.RefreshMinimapMenu()
            end

            if RaidTrack.BroadcastSettings then
                RaidTrack.BroadcastSettings()
            end
        end)

        topGroup:AddChild(dd)

        RaidTrack.settingsTabData = RaidTrack.settingsTabData or {}
        RaidTrack.settingsTabData.accessDD = dd

        -- Spacer under control
        local spacer2 = AceGUI:Create("Label")
        spacer2:SetText(" ")
        spacer2:SetFullWidth(true)
        spacer2:SetHeight(6)
        topGroup:AddChild(spacer2)
    end

    local title = AceGUI:Create("Label")
    title:SetText("Sync Settings")
    title:SetFontObject(GameFontHighlightLarge)
    title:SetFullWidth(true)
    topGroup:AddChild(title)

    local function CreateCheckBox(label, initial, onChange)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetValue(initial)
        cb:SetFullWidth(true)
        cb:SetCallback("OnValueChanged", onChange)
        topGroup:AddChild(cb)
        return cb
    end

    local s = RaidTrackDB.settings or {}
    RaidTrackDB.settings = s

    local officerOnlyCB = CreateCheckBox("Officers only", s.officerOnly ~= false, function(_, _, val)
        if not RaidTrack.IsOfficer() then
            RaidTrack.AddDebugMessage("Only officers can change sync settings.")
            officerOnlyCB:SetValue(not val)
            return
        end
        s.officerOnly = val
        RaidTrack.BroadcastSettings()
    end)

    local autoSyncCB = CreateCheckBox("Auto-accept from officers", s.autoSync ~= false, function(_, _, val)
        if not RaidTrack.IsOfficer() then
            RaidTrack.AddDebugMessage("Only officers can change sync settings.")
            autoSyncCB:SetValue(not val)
            return
        end
        s.autoSync = val
        RaidTrack.BroadcastSettings()
    end)

    local debugCB = CreateCheckBox("Enable debug log", s.debug == true, function(_, _, val)
        s.debug = val
    end)

    local verboseCB = CreateCheckBox("Verbose debug (include args/returns)", s.debugVerbose == true, function(_, _, val)
        s.debugVerbose = val
    end)

    local rankLabel = AceGUI:Create("Label")
    rankLabel:SetText("Min guild rank:")
    rankLabel:SetFullWidth(true)
    rankLabel:SetHeight(20)
    topGroup:AddChild(rankLabel)

    local rankDD = AceGUI:Create("Dropdown")
    rankDD:SetWidth(200)
    topGroup:AddChild(rankDD)

    RaidTrack.settingsTabData.rankDD = rankDD

    local ranks, seenRanks = {}, {}
    for i = 1, GetNumGuildMembers() do
        local _, rankName, rankIndex = GetGuildRosterInfo(i)
        if rankName and not seenRanks[rankIndex] then
            seenRanks[rankIndex] = true
            ranks[tostring(rankIndex)] = rankName
        end
    end

    local selectedRank = tostring(s.minSyncRank or 1)
    rankDD:SetList(ranks)
    rankDD:SetValue(selectedRank)

    rankDD:SetCallback("OnValueChanged", function(_, _, val)
        val = tonumber(val) or 1
        if not RaidTrack.IsOfficer() then
            RaidTrack.AddDebugMessage("Only officers can change sync rank.")
            rankDD:SetValue(tostring(s.minSyncRank or 1))
            return
        end
        s.minSyncRank = val
        RaidTrack.BroadcastSettings()
    end)

    -- BUTTONS: Manual Sync + Clear Log
    local buttonGroup = AceGUI:Create("SimpleGroup")
    buttonGroup:SetWidth(1)
    buttonGroup:SetLayout("Flow")
    buttonGroup:SetFullWidth(true)
    topGroup:AddChild(buttonGroup)

    local syncBtn = AceGUI:Create("Button")
    syncBtn:SetText("Manual Sync")
    syncBtn:SetWidth(120)
    syncBtn:SetCallback("OnClick", function()
        local ok, err = pcall(RaidTrack.SendSyncData)
        if not ok then
            RaidTrack.AddDebugMessage("Sync error: " .. tostring(err))
        else
            RaidTrack.AddDebugMessage("Manual sync triggered.")
        end
    end)
    buttonGroup:AddChild(syncBtn)

    local clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear Log")
    clearBtn:SetWidth(120)
    clearBtn:SetCallback("OnClick", function()
        RaidTrack.debugMessages = {}
        if dbgEdit and dbgEdit.SetText then
            dbgEdit:SetText("")
        end
    end)
    buttonGroup:AddChild(clearBtn)

    -- LOG area - full height to the bottom of the window (no extra ScrollFrame)
    local spacerUnderButtons = AceGUI:Create("Label")
    spacerUnderButtons:SetText(" ")
    spacerUnderButtons:SetFullWidth(true)
    spacerUnderButtons:SetHeight(6)
    mainGroup:AddChild(spacerUnderButtons)

    local logGroup = AceGUI:Create("SimpleGroup")
    logGroup:SetFullWidth(true)
    logGroup:SetFullHeight(true) -- this is key: the last child gets all remaining height
    logGroup:SetLayout("Fill")
    mainGroup:AddChild(logGroup)

    dbgEdit = AceGUI:Create("MultiLineEditBox")
    dbgEdit:SetLabel("")
    dbgEdit:SetFullWidth(true)
    dbgEdit:SetFullHeight(true) -- expand inside Fill

    -- optional: ensure a reasonable baseline if Fill momentarily fails
    if dbgEdit.SetNumLines then
        dbgEdit:SetNumLines(18)
    end

    dbgEdit:SetText(table.concat(RaidTrack.debugMessages or {}, "\n"))
    dbgEdit:SetCallback("OnEscapePressed", function()
        dbgEdit:ClearFocus()
    end)
    dbgEdit:SetCallback("OnTextChanged", function()
        dbgEdit:ClearFocus()
    end)
    if dbgEdit.editBox and dbgEdit.editBox.SetFontObject then
        dbgEdit.editBox:SetFontObject(GameFontNormal)
    end
    if dbgEdit.button and dbgEdit.button.Hide then
        dbgEdit.button:Hide()
    end
    logGroup:AddChild(dbgEdit)

-- when you create your editbox for the log:
--   dbgEdit = AceGUI:Create("MultiLineEditBox")  -- przykładowo
RaidTrack._debugEditBox = dbgEdit

-- install UI hook once (idempotent, bez rekurencji)
if not RaidTrack._AddDebugMessageHookInstalled then
    local _core = RaidTrack._AddDebugMessageCore
    RaidTrack.AddDebugMessage = function(msg, opts)
        _core(msg, opts)  -- zapis + ewentualny echo

        local edit = RaidTrack._debugEditBox
        if edit and edit.SetText then
            edit:SetText(table.concat(RaidTrack.debugMessages or {}, "\n"))
            edit:ClearFocus()
        end
    end
    RaidTrack._AddDebugMessageHookInstalled = true
end


    -- Disable if not officer
    -- Disable if not officer
    if not (RaidTrack.IsOfficer and RaidTrack.IsOfficer()) then
        if officerOnlyCB and officerOnlyCB.SetDisabled then
            officerOnlyCB:SetDisabled(true)
        end
        if autoSyncCB and autoSyncCB.SetDisabled then
            autoSyncCB:SetDisabled(true)
        end
        if debugCB and debugCB.SetDisabled then
            debugCB:SetDisabled(true)
        end
        if verboseCB and verboseCB.SetDisabled then
            verboseCB:SetDisabled(true)
        end
        if rankDD and rankDD.SetDisabled then
            rankDD:SetDisabled(true)
        end
        if syncBtn and syncBtn.SetDisabled then
            syncBtn:SetDisabled(true)
        end
        if clearBtn and clearBtn.SetDisabled then
            clearBtn:SetDisabled(true)
        end

        -- Access Control dropdown (stored earlier)
        local accessDD = RaidTrack.settingsTabData and RaidTrack.settingsTabData.accessDD
        if accessDD and accessDD.SetDisabled then
            accessDD:SetDisabled(true)
        end
    end

end

function RaidTrack.UpdateSettingsTab()
    if RaidTrack.settingsTab and RaidTrack.settingsTab:IsShown() then
        local s = RaidTrackDB.settings or {}
        local rankDD = RaidTrack.settingsTabData.rankDD
        if rankDD then
            rankDD:SetValue(s.minSyncRank or 1)
        end
    end
end
