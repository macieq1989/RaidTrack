local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:CreateMainFrame()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("RaidTrack")
    frame:SetLayout("Fill")
    frame:SetWidth(800)
    frame:SetHeight(600)
    frame:EnableResize(false)
    self.mainFrame = frame





    local tabs = {{
        text = "Raid",
        value = "raidTab"
    }, {
        text = "EPGP",
        value = "epgpTab",
        restricted = false
    }, {
        text = "Loot",
        value = "lootTab"
    }, {
        text = "Guild",
        value = "guildTab"
    }, {
        text = "Settings",
        value = "settingsTab"
    }}

    -- Zachowaj czystą (niemutowaną przez AceGUI) kopię tabów
    RaidTrack._all_tabs_source = {}
    for _, t in ipairs(tabs) do
        table.insert(RaidTrack._all_tabs_source, {
            text = t.text,
            value = t.value,
            restricted = t.restricted
        })
    end

    local tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetTabs(tabs)
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    tabGroup:SetLayout("Fill")

    RaidTrack._tabGroup = tabGroup
    C_Timer.After(0, function()
        if RaidTrack.ApplyUITabVisibility then
            RaidTrack.ApplyUITabVisibility()
        end
    end)

    tabGroup:SetCallback("OnGroupSelected", function(container, event, tabKey)
    RaidTrack.activeTab = tabKey

    -- Deactivate tabs we're leaving (prevent leaked highlights/frames)
    if tabKey ~= "raidTab" and RaidTrack.DeactivateRaidTab then
        RaidTrack.DeactivateRaidTab()
        RaidTrack.ClearRaidSelection()
    end
    if tabKey ~= "guildTab" and RaidTrack.DeactivateGuildTab then
        RaidTrack.DeactivateGuildTab()
    end

    -- Force-close any open pullouts / tooltips that can bleed across tabs
    if AceGUI and AceGUI.ClearFocus then AceGUI:ClearFocus() end
    GameTooltip:Hide()

    container:ReleaseChildren()
    if RaidTrack["Render_" .. tabKey] then
        RaidTrack["Render_" .. tabKey](RaidTrack, container)
    end
end)


    frame:AddChild(tabGroup)
    tabGroup:SelectTab("raidTab")

    -- Przycisk Refresh obok Close
    local refreshBtn = CreateFrame("Button", nil, frame.frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetPoint("TOPRIGHT", frame.frame, "TOPRIGHT", -40, -30)
    refreshBtn:SetScript("OnClick", function()
        local activeTab = RaidTrack.activeTab or ""
        if activeTab == "raidTab" and RaidTrack.UpdateRaidList then
            RaidTrack.UpdateRaidList()
        elseif activeTab == "epgpTab" and RaidTrack.UpdateEPGPList then
            RaidTrack.UpdateEPGPList()
        elseif activeTab == "lootTab" and RaidTrack.UpdateLootList then
            RaidTrack.UpdateLootList()
        elseif activeTab == "guildTab" and RaidTrack.UpdateGuildList then
            RaidTrack.UpdateGuildList()

        elseif activeTab == "settingsTab" then
            -- np. Settings tab nie potrzebuje refresh
        else
            RaidTrack.AddDebugMessage("Refresh: no known updater for tab: " .. tostring(activeTab))
        end

    end)
end

function RaidTrack:ToggleMainWindow()
    if self.mainFrame and self.mainFrame.frame and self.mainFrame.frame:IsShown() then
        self.mainFrame.frame:Hide()
    else
        if not self.mainFrame then
            self:CreateMainFrame()
        else
            self.mainFrame.frame:Show()
        end
    end
end

function RaidTrack._FilterTabsByRank(tabs)
    local allowed = {}
    local gate = RaidTrack.IsPlayerAllowedByRank()
    for _, t in ipairs(tabs) do
        local isRestricted = (t.restricted ~= false)
        if (not isRestricted) or gate then
            table.insert(allowed, t)
        end
    end
    return allowed
end

function RaidTrack.ApplyUITabVisibility()
    local tg = RaidTrack._tabGroup
    if not tg then return end

    -- Użyj czystej kopii tabów; jeśli jej nie ma (edge case), spróbuj odbudować z tg.tabs
    local source = RaidTrack._all_tabs_source
    if not source then
        source = {}
        if tg.tabs then
            for _, t in ipairs(tg.tabs) do
                local label
                if type(t.text) == "table" and t.text.GetText then
                    label = t.text:GetText()
                else
                    label = t.text
                end
                table.insert(source, { text = label, value = t.value, restricted = t.restricted })
            end
            RaidTrack._all_tabs_source = source
        else
            return
        end
    end

    local gate = RaidTrack.IsPlayerAllowedByRank and RaidTrack.IsPlayerAllowedByRank()
    local fresh = {}

    -- Buduj NOWE tablice (nie przekazuj referencji mutowanych przez AceGUI)
    for _, t in ipairs(source) do
        local isRestricted = (t.restricted ~= false)
        if (not isRestricted) or gate then
            table.insert(fresh, { text = t.text, value = t.value, restricted = t.restricted })
        end
    end

    -- Pobierz aktualnie wybraną zakładkę w sposób bezpieczny
    local current
    if tg.GetSelectedTab then
        current = tg:GetSelectedTab()
    else
        current = (tg.localstatus and tg.localstatus.selected) or (tg.status and tg.status.selected)
    end

    -- Sprawdź czy wybrana zakładka pozostaje po filtrze
    local exists = false
    for _, t in ipairs(fresh) do
        if t.value == current then exists = true break end
    end

    tg:SetTabs(fresh)
    if not exists then
        if tg.SelectTab then
            tg:SelectTab("epgpTab")
        else
            if tg.localstatus then tg.localstatus.selected = "epgpTab" end
        end
    end
end


SLASH_RAIDTRACK1 = "/raidtrack"
SlashCmdList["RAIDTRACK"] = function()
    RaidTrack:ToggleMainWindow()
end
