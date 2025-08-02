-- SettingsTab.lua (AceGUI version)
local addonName, RaidTrack = ...

local AceGUI = LibStub("AceGUI-3.0")

RaidTrack.settingsTabData = RaidTrack.settingsTabData or {}

function RaidTrack:Render_settingsTab(container)
    container:SetLayout("Fill")
    container:SetFullHeight(true)

    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    mainGroup:SetLayout("Flow")
    container:AddChild(mainGroup)

    local title = AceGUI:Create("Label")
    title:SetText("Sync Settings")
    title:SetFontObject(GameFontHighlightLarge)
    title:SetFullWidth(true)
    mainGroup:AddChild(title)

    -- Checkbox helper
    local function CreateCheckBox(label, initial, onChange)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetValue(initial)
        cb:SetFullWidth(true)
        cb:SetCallback("OnValueChanged", onChange)
        mainGroup:AddChild(cb)
        return cb
    end

    local s = RaidTrackDB.settings or {}
    RaidTrackDB.settings = s

    -- Officer only checkbox
    local officerOnlyCB = CreateCheckBox("Officers only", s.officerOnly ~= false, function(_, _, val)
        if not RaidTrack.IsOfficer() then
            RaidTrack.AddDebugMessage("Only officers can change sync settings.")
            officerOnlyCB:SetValue(not val)
            return
        end
        s.officerOnly = val
        RaidTrack.BroadcastSettings()
    end)

    -- Auto-sync checkbox
    local autoSyncCB = CreateCheckBox("Auto-accept from officers", s.autoSync ~= false, function(_, _, val)
        if not RaidTrack.IsOfficer() then
            RaidTrack.AddDebugMessage("Only officers can change sync settings.")
            autoSyncCB:SetValue(not val)
            return
        end
        s.autoSync = val
        RaidTrack.BroadcastSettings()
    end)

    -- Debug checkboxes
    local debugCB = CreateCheckBox("Enable debug log", s.debug == true, function(_, _, val)
        s.debug = val
    end)

    local verboseCB = CreateCheckBox("Verbose debug (include args/returns)", s.debugVerbose == true, function(_, _, val)
        s.debugVerbose = val
    end)

    -- Rank dropdown label
    local rankLabel = AceGUI:Create("Label")
    rankLabel:SetText("Min guild rank:")
    rankLabel:SetFullWidth(true)
    rankLabel:SetHeight(20)
    mainGroup:AddChild(rankLabel)

    -- Rank dropdown
    local rankDD = AceGUI:Create("Dropdown")
    rankDD:SetFullWidth(true)
    mainGroup:AddChild(rankDD)

RaidTrack.settingsTabData.rankDD = rankDD 

 local ranks = {}
local seenRanks = {}
for i = 1, GetNumGuildMembers() do
    local _, rankName, rankIndex = GetGuildRosterInfo(i)
    if rankName and not seenRanks[rankIndex] then
        seenRanks[rankIndex] = true
        ranks[tostring(rankIndex)] = rankName  -- ✅ poprawna forma: ["1"] = "Officer"
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


    mainGroup:AddChild(rankDD)

    -- Debug log label
    local dbgLabel = AceGUI:Create("Label")
    dbgLabel:SetText("Debug log:")
    dbgLabel:SetFullWidth(true)
    dbgLabel:SetHeight(20)
    mainGroup:AddChild(dbgLabel)

    -- Debug log (multi-line editbox inside scroll container)
    local dbgScroll = AceGUI:Create("ScrollFrame")
    dbgScroll:SetFullWidth(true)
    dbgScroll:SetFullHeight(true)
    dbgScroll:SetLayout("Fill")
    mainGroup:AddChild(dbgScroll)

    local dbgEdit = AceGUI:Create("MultiLineEditBox")
dbgEdit:SetLabel("")
dbgEdit:SetFullWidth(true)
dbgEdit:SetFullHeight(true)
dbgEdit:SetText(table.concat(RaidTrack.debugMessages or {}, "\n"))
dbgEdit:SetCallback("OnEscapePressed", function() dbgEdit:ClearFocus() end)
dbgEdit:SetCallback("OnTextChanged", function() dbgEdit:ClearFocus() end) -- readonly

if dbgEdit.editBox and dbgEdit.editBox.SetFontObject then
    dbgEdit.editBox:SetFontObject(GameFontNormal)
end

    dbgScroll:AddChild(dbgEdit)

    -- Hook to update debug log when new messages come
    local origAddDebug = RaidTrack.AddDebugMessage
    function RaidTrack.AddDebugMessage(msg)
        origAddDebug(msg)
        if dbgEdit and dbgEdit.SetText then
            dbgEdit:SetText(table.concat(RaidTrack.debugMessages or {}, "\n"))
            dbgEdit:ClearFocus()
        end
    end

    -- Manual Sync button
    local syncBtn = AceGUI:Create("Button")
    syncBtn:SetText("Manual Sync")
    syncBtn:SetWidth(160)
    syncBtn:SetCallback("OnClick", function()
        local ok, err = pcall(RaidTrack.SendSyncData)
        if not ok then
            RaidTrack.AddDebugMessage("Sync error: " .. tostring(err))
        else
            RaidTrack.AddDebugMessage("Manual sync triggered.")
        end
    end)
    mainGroup:AddChild(syncBtn)

    -- Disable controls if not officer
    if not RaidTrack.IsOfficer() then
        officerOnlyCB:Disable()
        autoSyncCB:Disable()
        debugCB:Disable()
        verboseCB:Disable()
        rankDD:Disable()
        syncBtn:Disable()
    end
end

function RaidTrack.UpdateSettingsTab()
    if RaidTrack.settingsTab and RaidTrack.settingsTab:IsShown() then
        local s = RaidTrackDB.settings or {}
        local rankDD = RaidTrack.settingsTabData.rankDD
        if rankDD then
            -- ustawiamy wybraną wartość, np. minSyncRank (liczba)
            rankDD:SetValue(s.minSyncRank or 1)
        end
    end
end


