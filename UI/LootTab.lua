-- LootTab.lua
local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

RaidTrack.lootTab = RaidTrack.lootTab or {}

local lastItemLink
local historyRows = {}

local raidBosses = {
    ["Nerub’ar Palace"] = {"Rasha’nan", "The Pale Serpent", "Queen Ansurek", "The Silkshaper", "Skittering Horror",
                             "The Burrower Below", "Anub’ikkaj", "Xal’Zix"},
    ["Liberation of Undermine"] = {"Mogul Razdunk", "Underboss Greasetooth", "Trade Prince Gallywix", "King Drekaz",
                                   "Mechanical Maw", "Vault Guardian V-300", "Sparkfuse Syndicate", "Smoglord Throg"}
}

function RaidTrack:Render_lootTab(container)

    -- choose a safe parent for everything in this tab
local parent = (container and container.frame)
    or (RaidTrack.mainFrame and RaidTrack.mainFrame.frame)
    or UIParent

    container:SetLayout("Fill")

    local mainGroup = AceGUI:Create("SimpleGroup")
    mainGroup:SetFullWidth(true)
    mainGroup:SetFullHeight(true)
    mainGroup:SetLayout("Flow")
    container:AddChild(mainGroup)

    local leftPanel = AceGUI:Create("InlineGroup")
    leftPanel:SetTitle("Loot Entry")
    leftPanel:SetRelativeWidth(0.4)
    leftPanel:SetLayout("Flow")
    leftPanel:SetFullHeight(true)
    mainGroup:AddChild(leftPanel)

    local raidDD = AceGUI:Create("Dropdown")
    raidDD:SetLabel("Select Raid")
    raidDD:SetFullWidth(true)
    leftPanel:AddChild(raidDD)

    local playerDD = AceGUI:Create("Dropdown")
    playerDD:SetLabel("Select Player")
    playerDD:SetFullWidth(true)
    leftPanel:AddChild(playerDD)

    local bossDD = AceGUI:Create("Dropdown")
    bossDD:SetLabel("Select Boss")
    bossDD:SetFullWidth(true)
    leftPanel:AddChild(bossDD)

    local itemEB = AceGUI:Create("EditBox")
    itemEB:SetLabel("Item Link")
    itemEB:SetFullWidth(true)
    leftPanel:AddChild(itemEB)

    local gpEB = AceGUI:Create("EditBox")
    gpEB:SetLabel("GP Cost")
    gpEB:SetWidth(80)
    leftPanel:AddChild(gpEB)

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetLayout("Flow")
    btnGroup:SetFullWidth(true)
    leftPanel:AddChild(btnGroup)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save loot")
    saveBtn:SetWidth(120)
    btnGroup:AddChild(saveBtn)

    local pasteBtn = AceGUI:Create("Button")
    pasteBtn:SetText("Paste item")
    pasteBtn:SetWidth(120)
    btnGroup:AddChild(pasteBtn)

    local infoLabel = AceGUI:Create("Label")
    infoLabel:SetText("")
    infoLabel:SetFullWidth(true)
    leftPanel:AddChild(infoLabel)

    local rightPanel = AceGUI:Create("InlineGroup")
    rightPanel:SetTitle("Loot History (last 50 entries)")
    rightPanel:SetRelativeWidth(0.58)
    rightPanel:SetLayout("Fill")
    rightPanel:SetFullHeight(true)
    mainGroup:AddChild(rightPanel)

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    rightPanel:AddChild(scroll)

   local function UpdatePlayerDropdown()
    local players = {}
    local num = GetNumGroupMembers()
    for i = 1, num do
        local name = GetRaidRosterInfo(i)
        if name then
            players[name] = name -- ← poprawione
        end
    end
    playerDD:SetList(players)
    playerDD:SetValue(nil)
end

    local function DebugPrint(msg)
        RaidTrack.AddDebugMessage("[LOOTTAB DEBUG] " .. tostring(msg))
    end

   local function UpdateBossDropdown()
    local raidSelected = raidDD:GetValue()
    DebugPrint("UpdateBossDropdown called, selected raid: " .. tostring(raidSelected))

    if raidSelected and raidBosses[raidSelected] then
        local bosses = raidBosses[raidSelected]
        DebugPrint("Boss list found for raid: " .. raidSelected .. ", count: " .. #bosses)

        local mapped = {}
        for _, boss in ipairs(bosses) do
            mapped[boss] = boss -- ← mapowanie klucz = wartość
        end
        bossDD:SetList(mapped)
        bossDD:SetValue(nil)
    else
        DebugPrint("No bosses found for selected raid!")
        bossDD:SetList({})
        bossDD:SetValue(nil)
    end
end


    local function UpdateRaidDropdown()
        DebugPrint("UpdateRaidDropdown called")

        local raids = {}
        local raidList = {}
        for raidName, _ in pairs(raidBosses) do
            raidList[raidName] = raidName -- ważne: key == value
        end
        raidDD:SetList(raidList)

        if #raids > 0 then
            local first = next(raidList)

            DebugPrint("Setting raid dropdown to: " .. first)
            raidDD:SetValue(first)
            UpdateBossDropdown()
        else
            DebugPrint("No raids found in raidBosses table")
        end
    end

    raidDD:SetCallback("OnValueChanged", function()
        UpdateBossDropdown()
    end)

    saveBtn:SetCallback("OnClick", function()
        local pl = playerDD:GetValue()
        local bs = bossDD:GetValue()
        local it = itemEB:GetText()
        local gp = tonumber(gpEB:GetText()) or 0
        if not (pl and bs and it ~= "") then
            infoLabel:SetText("Fill all fields!")
            return
        end
        RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}
        local lastId = (#RaidTrackDB.lootHistory > 0) and RaidTrackDB.lootHistory[#RaidTrackDB.lootHistory].id or 0
        local entry = {
            id = lastId + 1,
            time = date("%H:%M:%S"),
            timestamp = time(),
            player = pl,
            item = it,
            boss = bs,
            gp = gp
        }
        table.insert(RaidTrackDB.lootHistory, entry)
        RaidTrack.LogEPGPChange(pl, 0, gp, "Loot Save")
        infoLabel:SetText("Saved!")
        itemEB:SetText("")
        gpEB:SetText("")
        raidDD:SetValue(nil)
        playerDD:SetValue(nil)
        bossDD:SetValue(nil)
        UpdateLootHistory()

        if RaidTrackDB.settings.autoSync ~= false then
            RaidTrack.SendSyncData()
            RaidTrack.RequestSyncFromGuild()
        end
    end)

    pasteBtn:SetCallback("OnClick", function()
        if lastItemLink then
            itemEB:SetText(lastItemLink)
            infoLabel:SetText("Pasted.")
        else
            infoLabel:SetText("No link.")
        end
    end)

    function UpdateLootHistory()
        scroll:ReleaseChildren()
        historyRows = {}

        local data = RaidTrackDB.lootHistory or {}
        local maxEntries = 50
        local count = math.min(#data, maxEntries)

        for i = #data, #data - count + 1, -1 do

            local e = data[i]
            local row = AceGUI:Create("Label")
            local classToken
            if type(e.player) == "string" and UnitExists(e.player) then
                _, classToken = UnitClass(e.player)
            end
            classToken = classToken or "PRIEST"
            local col = RAID_CLASS_COLORS[classToken] or {
                r = 1,
                g = 1,
                b = 1
            }

            local hex = string.format("%02x%02x%02x", col.r * 255, col.g * 255, col.b * 255)
            local _, _, q = GetItemInfo(e.item)
            local qc = ITEM_QUALITY_COLORS[q] or {
                r = 1,
                g = 1,
                b = 1
            }
            local qh = string.format("%02x%02x%02x", qc.r * 255, qc.g * 255, qc.b * 255)
            local text = string.format("|cff%s%s|r - looted |cff%s%s|r from %s (GP:%d) [%s]", hex, e.player, qh, e.item,
                e.boss or "Unknown", e.gp, e.time or date("%H:%M:%S", e.timestamp))
            row:SetText(text)
            row:SetFullWidth(true)
            scroll:AddChild(row)
            table.insert(historyRows, row)
        end
    end

    RaidTrack.UpdateLootList = UpdateLootHistory

    local chatFrameListener = CreateFrame("Frame")
    chatFrameListener:RegisterEvent("CHAT_MSG_LOOT")
    chatFrameListener:RegisterEvent("CHAT_MSG_RAID")
    chatFrameListener:RegisterEvent("CHAT_MSG_PARTY")
    chatFrameListener:RegisterEvent("CHAT_MSG_SAY")
    chatFrameListener:RegisterEvent("CHAT_MSG_WHISPER")
    chatFrameListener:SetScript("OnEvent", function(_, _, msg)
        local link = msg:match("|Hitem:.-|h.-|h|r")
        if link then
            lastItemLink = link
        end
    end)

    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not frame:IsShown() then
            return
        end
        if type(link) == "string" and IsShiftKeyDown() then
            local itemString = link:match("|Hitem:.-|h.-|h") or link
            lastItemLink = itemString
            itemEB:SetText(itemString)
            infoLabel:SetText("Auto-pasted item")
        end
    end)

    -- Init dropdowns
    UpdateRaidDropdown()
    UpdatePlayerDropdown()
    UpdateLootHistory()
end
