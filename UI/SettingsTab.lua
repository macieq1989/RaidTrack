local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

RaidTrack.settingsTabData = RaidTrack.settingsTabData or {}

function RaidTrack:Render_settingsTab(container)
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

    -- SCROLL LOG (no wrapper!)
    local dbgScroll = AceGUI:Create("ScrollFrame")
    dbgScroll:SetLayout("Fill")
    dbgScroll:SetFullWidth(true)
    dbgScroll:SetFullHeight(true)
    mainGroup:AddChild(dbgScroll)

    dbgEdit = AceGUI:Create("MultiLineEditBox")
    dbgEdit:SetLabel("")
    dbgEdit:SetFullWidth(true)
    dbgEdit:SetFullHeight(true)
    dbgEdit:SetText(table.concat(RaidTrack.debugMessages or {}, "\n"))
    dbgEdit:SetCallback("OnEscapePressed", function() dbgEdit:ClearFocus() end)
    dbgEdit:SetCallback("OnTextChanged", function() dbgEdit:ClearFocus() end)
    if dbgEdit.editBox and dbgEdit.editBox.SetFontObject then
        dbgEdit.editBox:SetFontObject(GameFontNormal)
    end
    if dbgEdit.button and dbgEdit.button.Hide then
        dbgEdit.button:Hide()
    end
    dbgScroll:AddChild(dbgEdit)

    -- Hook aktualizacji loga
    local origAddDebug = RaidTrack.AddDebugMessage
    function RaidTrack.AddDebugMessage(msg)
        origAddDebug(msg)
        if dbgEdit and dbgEdit.SetText then
            dbgEdit:SetText(table.concat(RaidTrack.debugMessages or {}, "\n"))
            dbgEdit:ClearFocus()
        end
    end

    -- Disable if not officer
    if not RaidTrack.IsOfficer() then
        officerOnlyCB:Disable()
        autoSyncCB:Disable()
        debugCB:Disable()
        verboseCB:Disable()
        rankDD:Disable()
        syncBtn:Disable()
        clearBtn:Disable()
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
