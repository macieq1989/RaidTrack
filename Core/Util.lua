-- Core/Util.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}

local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
assert(AceSerializer, "AceSerializer-3.0 not found!")

-- Serialization
function RaidTrack.SafeSerialize(tbl) return AceSerializer:Serialize(tbl) end
function RaidTrack.SafeDeserialize(str)
    local ok, payload = AceSerializer:Deserialize(str)
    if not ok then
        RaidTrack.AddDebugMessage("Deserialize failed: " .. tostring(payload))
        return false, nil
    end
    return true, payload
end




-- define once (idempotent)
if not RaidTrack._AddDebugMessageCore then
    local function _maxLogLines()
        RaidTrackDB.settings = RaidTrackDB.settings or {}
        -- domyślnie 1000, można zmienić w /rtlogsize
        return tonumber(RaidTrackDB.settings.debugMaxLines) or 1000
    end

    function RaidTrack._AddDebugMessageCore(msg, opts)
        if msg == nil then return end
        opts = opts or {}
        RaidTrackDB.settings = RaidTrackDB.settings or {}
        local toChat = (RaidTrackDB.settings.debugToChat == true) or (opts.forceEcho == true)

        RaidTrack.debugMessages = RaidTrack.debugMessages or {}
        local line = date("%H:%M:%S") .. " - " .. tostring(msg)
        table.insert(RaidTrack.debugMessages, 1, line)

        local cap = _maxLogLines()
        while #RaidTrack.debugMessages > cap do
            table.remove(RaidTrack.debugMessages, #RaidTrack.debugMessages)
        end

        if toChat then
            print("|cff00ffff[RaidTrack]|r " .. tostring(msg))
        end
    end
end


-- public alias (can be wrapped later by UI)
RaidTrack.AddDebugMessage = RaidTrack._AddDebugMessageCore

-- Officer check (cache + fallback)
function RaidTrack.IsOfficer()
    if not IsInGuild() then return false end
    RaidTrack._officerCache = RaidTrack._officerCache or { verdict = false, ts = 0 }
    local now = (GetTime and GetTime()) or time()
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote and C_GuildInfo.CanEditOfficerNote() then
        RaidTrack._officerCache.verdict = true
        RaidTrack._officerCache.ts = now
        return true
    end
    if (now - (RaidTrack._officerCache.ts or 0)) < 10 then
        return RaidTrack._officerCache.verdict and true or false
    end
    local myFull = (GetUnitName and GetUnitName("player", true)) or UnitName("player") or ""
    if myFull == "" then return false end
    local minRank = tonumber(RaidTrackDB and RaidTrackDB.settings and RaidTrackDB.settings.minSyncRank) or 1
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    local n = GetNumGuildMembers() or 0
    if n == 0 then
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end end)
        end
        return RaidTrack._officerCache.verdict and true or false
    end
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name == myFull then
            local verdict = (tonumber(rankIndex) or 99) <= minRank
            RaidTrack._officerCache.verdict = verdict
            RaidTrack._officerCache.ts = now
            return verdict
        end
    end
    RaidTrack._officerCache.verdict = false
    RaidTrack._officerCache.ts = now
    return false
end

-- dodatkowy cache eventowy (bez zmian funkcjonalnych)
RaidTrack._officerCache = RaidTrack._officerCache or { ready = false, isOfficer = false, lastCheck = 0 }
function RaidTrack._UpdateOfficerCache()
    if not IsInGuild() then RaidTrack._officerCache.ready = true; RaidTrack._officerCache.isOfficer = false; return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    local myFull = (GetUnitName and GetUnitName("player", true)) or UnitName("player") or ""
    if myFull == "" then RaidTrack._officerCache.ready = false; RaidTrack._officerCache.isOfficer = false; return end
    local minRank = tonumber(RaidTrackDB and RaidTrackDB.settings and RaidTrackDB.settings.minSyncRank) or 1
    local found, isOfficer = false, false
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name == myFull then found = true; isOfficer = (tonumber(rankIndex) or 99) <= minRank; break end
    end
    RaidTrack._officerCache.ready = found
    RaidTrack._officerCache.isOfficer = isOfficer
end

if not RaidTrack._guildEvtFrame then
    local f = CreateFrame("Frame", nil, UIParent)  -- albo po prostu CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_LOGIN" or evt == "PLAYER_GUILD_UPDATE" then
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        end
        if RaidTrack._UpdateOfficerCache then RaidTrack._UpdateOfficerCache() end
    end)
    RaidTrack._guildEvtFrame = f
end

-- Status helpers
function RaidTrack.GetSyncStatus()
    local count = RaidTrack.lastDeltaCount or 0
    return (count == 0) and "Idle" or string.format("Pending (%d events)", count)
end
function RaidTrack.GetSyncTimeAgo()
    if not RaidTrack.lastSyncTime then return "never" end
    local elapsed = time() - RaidTrack.lastSyncTime
    local min = math.floor(elapsed / 60)
    local sec = elapsed % 60
    return string.format("%d min %d sec ago", min, sec)
end
function RaidTrack.DebugTableToString(tbl)
    if type(tbl) ~= "table" then return tostring(tbl) end
    local str = ""
    for k, v in pairs(tbl) do str = str .. tostring(k) .. "=" .. tostring(v) .. "; " end
    return str
end

-- EPGP helpers (twoje bez zmian)
function RaidTrack.AddLootToLog(player, itemID, gp)
    local lootEntry = { player = player, itemID = itemID, gp = gp, timestamp = time() }
    table.insert(RaidTrackDB.lootHistory, lootEntry)
    RaidTrack.AddDebugMessage("Loot added for " .. player .. ": ItemID " .. itemID .. " with GP " .. gp)
end
function RaidTrack.AssignPointsToPlayer(player, gp)
    local epgp = RaidTrackDB.epgp[player] or { ep = 0, gp = 0 }
    epgp.gp = epgp.gp + gp
    RaidTrackDB.epgp[player] = epgp
    RaidTrack.AddDebugMessage("Assigned " .. gp .. " GP to player " .. player)
end
function RaidTrack.GetSelectedItemID()
    local selectedItem = RaidTrack.auctionParticipantWindow and RaidTrack.auctionParticipantWindow.selectedItem
    return selectedItem and selectedItem.itemID or nil
end
function RaidTrack.GetEPGP(player)
    local playerEP, playerGP = 0, 0
    if RaidTrackDB.epgp[player] then
        playerEP = RaidTrackDB.epgp[player].ep or 0
        playerGP = RaidTrackDB.epgp[player].gp or 0
    end
    local playerPR = (playerGP > 0) and (playerEP / playerGP) or 0
    return playerEP, playerGP, playerPR
end

function RaidTrack.SendAuctionResponseChunked(auctionID, itemID, choice)
    local from = UnitName("player")
    local payload = { auctionID = tostring(auctionID), itemID = tonumber(itemID), choice = choice, from = from }
    RaidTrack.QueueAuctionChunkedSend(nil, payload.auctionID, "response", payload)
    RaidTrack.AddDebugMessage("Locally handling own response for " .. from)
    C_Timer.After(0.05, function() RaidTrack.HandleAuctionResponse(payload.auctionID, payload) end)
end

function RaidTrack.IsLeader()
    local playerName = UnitName("player")
    local leaderName = RaidTrack.auction and RaidTrack.auction.leader
    return leaderName == playerName
end

function RaidTrack.IsPlayerInMyGuild(name)
    for i = 1, GetNumGuildMembers() do
        local fullName = GetGuildRosterInfo(i)
        if fullName and strsplit("-", fullName) == name then return true end
    end
    return false
end
function RaidTrack.IsPlayerInMyRaid(name)
    for i = 1, GetNumGroupMembers() do
        local raidName = GetRaidRosterInfo(i)
        if raidName and strsplit("-", raidName) == name then return true end
    end
    return false
end

function RaidTrack.FindItemInBags(itemID)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id == itemID then return bag, slot end
        end
    end
    return nil, nil
end

function RaidTrack.ApplyHighlight(row, isSelected)
    if not row or not row.frame then return end
    if not row._highlightTexture then
        local tex = row.frame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        row._highlightTexture = tex
    end
    if isSelected then
        row._highlightTexture:SetColorTexture(0.1, 0.1, 0.3, 0.4)
        row._highlightTexture:Show()
    else
        row._highlightTexture:SetColorTexture(0, 0, 0, 0)
        row._highlightTexture:Hide()
    end
end

function RaidTrack.GetClassTokenFromLocalized(classLocalized)
    for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do if localized == classLocalized then return token end end
    for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do if localized == classLocalized then return token end end
    return classLocalized
end

-- Toasty (bez zmian merytorycznych)
local function CreateEPGPToastFrame()
    local frame = CreateFrame("Frame", "RaidTrackEPGPToast", UIParent)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    frame:SetSize(300, 60)
    frame.bgTex = frame:CreateTexture(nil, "BACKGROUND"); frame.bgTex:SetAllPoints(); frame.bgTex:SetColorTexture(0, 0.4, 0, 0.6)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); frame.text:SetPoint("CENTER"); frame.text:SetText("")
    frame:SetScript("OnShow", function(self) C_Timer.After(4, function() self:Hide() end) end)
    return frame
end

function RaidTrack:ShowEPGPToast(amount, playerName, type)
    if not amount or not playerName or not type then return end
    local color = "|cffffffff"
    if type == "EP" then color = (amount >= 0) and "|cff00ff00" or "|cffff0000"
    elseif type == "GP" then color = (amount >= 0) and "|cffffcc00" or "|cffff0000" end
    local prefix = (amount >= 0) and "+" or ""
    local text = string.format("%s%s %s -> %s|r", color, type, prefix .. amount, playerName)
    local frame = RaidTrack.epgpAlertFrame or CreateFrame("Frame", nil, UIParent)
    RaidTrack.epgpAlertFrame = frame
    frame:SetSize(300, 64); frame:SetPoint("TOP", UIParent, "TOP", 0, -200); frame:Show()
    if not frame.bg then frame.bg = frame:CreateTexture(nil, "BACKGROUND"); frame.bg:SetAllPoints(); frame.bg:SetColorTexture(0,0,0,0.8) end
    if not frame.icon then frame.icon = frame:CreateTexture(nil, "ARTWORK"); frame.icon:SetSize(40,40); frame.icon:SetPoint("LEFT", frame, "LEFT", 10, 0) end
    if not frame.text then frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0); frame.text:SetJustifyH("LEFT"); frame.text:SetWidth(240); frame.text:SetHeight(40) end
    frame.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    frame.text:SetText(text)
    frame:SetAlpha(1)
    C_Timer.After(5, function() if frame:IsShown() then UIFrameFadeOut(frame, 2, 1, 0) end end)
end

function RaidTrack:ShowItemAwardToast(itemID, gpAmount)
    if not itemID or not gpAmount then return end
    local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
    if not itemLink then C_Timer.After(0.5, function() RaidTrack:ShowItemAwardToast(itemID, gpAmount) end); return end
    local text = string.format("Awarded %s for %d GP", itemLink, gpAmount)
    local frame = RaidTrack.awardToastFrame or CreateFrame("Frame", nil, UIParent)
    RaidTrack.awardToastFrame = frame
    frame:SetSize(320, 64); frame:SetPoint("TOP", UIParent, "TOP", 0, -260); frame:Show()
    if not frame.bg then frame.bg = frame:CreateTexture(nil, "BACKGROUND"); frame.bg:SetAllPoints(); frame.bg:SetColorTexture(0,0,0,0.8) end
    if not frame.icon then frame.icon = frame:CreateTexture(nil, "ARTWORK"); frame.icon:SetSize(40,40); frame.icon:SetPoint("LEFT", frame, "LEFT", 10, 0) end
    if not frame.text then frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0); frame.text:SetJustifyH("LEFT"); frame.text:SetWidth(250); frame.text:SetHeight(40) end
    frame.icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.text:SetText(text)
    frame:SetAlpha(1)
    C_Timer.After(5, function() if frame:IsShown() then UIFrameFadeOut(frame, 2, 1, 0) end end)
end

function RaidTrack.FindExpansionForInstance(instanceID)
    for _, exp in ipairs(RaidTrack.OfflineRaidData or {}) do
        for _, inst in ipairs(exp.instances or {}) do
            if inst.id == instanceID then return exp.expansionID end
        end
    end
    return nil
end

function RaidTrack:LoadActiveRaid()
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}
    for _, raid in ipairs(RaidTrackDB.raidInstances) do
        if raid.status == "started" then RaidTrack.activeRaidID = raid.id break end
    end
end
function RaidTrack.SaveWindowPosition(name, frame)
    RaidTrackDB.windowPositions = RaidTrackDB.windowPositions or {}
    local point, _, relativePoint, xOfs, yOfs = frame.frame:GetPoint()
    RaidTrackDB.windowPositions[name] = { point = point, relativePoint = relativePoint, x = xOfs, y = yOfs }
end
function RaidTrack.RestoreWindowPosition(name, frame)
    if RaidTrackDB.windowPositions and RaidTrackDB.windowPositions[name] then
        local pos = RaidTrackDB.windowPositions[name]
        frame.frame:ClearAllPoints()
        frame.frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- UI gating
function RaidTrack.GetGuildRanks()
    local values, order = {}, {}
    if IsInGuild() then
        local num = GuildControlGetNumRanks() or 10
        for i = 1, num do
            local name = GuildControlGetRankName(i) or ("Rank "..i)
            values[i] = string.format("%s (%d)", name, i-1)
            table.insert(order, i)
        end
    end
    return values, order
end
function RaidTrack.GetPlayerGuildRankIndex1()
    local rankIndex0 = select(3, GetGuildInfo("player"))
    if rankIndex0 ~= nil then return (rankIndex0 + 1) end
    return 999
end
function RaidTrack.GetMinUITabRank()
    RaidTrackDB.settings = RaidTrackDB.settings or {}
    local num = GuildControlGetNumRanks() or 10
    local v = RaidTrackDB.settings.minUITabRankIndex or num
    if type(v) ~= "number" or v < 1 then v = num end
    return v
end
function RaidTrack.IsPlayerAllowedByRank()
    return RaidTrack.GetPlayerGuildRankIndex1() <= RaidTrack.GetMinUITabRank()
end

-- Raid helpers
function RaidTrack.IsRaidLeadOrAssist() return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") end
function RaidTrack.IsRaidLeader() return UnitIsGroupLeader("player") end
function RaidTrack.GetActiveRaidEntry()
    if not RaidTrackDB or not RaidTrack.activeRaidID then return nil end
    for _, r in ipairs(RaidTrackDB.raidHistory or {}) do
        if tostring(r.id) == tostring(RaidTrack.activeRaidID) then return r end
    end
    return nil
end
function RaidTrack.GetActiveRaidConfig()
    local raid = RaidTrack.GetActiveRaidEntry()
    return raid and raid.settings or nil
end
function RaidTrack.MarkRaidFlag(flagKey)
    local raid = RaidTrack.GetActiveRaidEntry()
    if not raid then return end
    raid.flags = raid.flags or {}
    raid.flags[flagKey] = true
end
function RaidTrack.WasRaidFlagged(flagKey)
    local raid = RaidTrack.GetActiveRaidEntry()
    if not raid or not raid.flags then return false end
    return raid.flags[flagKey] == true
end

-- EP helpers
function RaidTrack.AwardEPToCurrentRaidMembers(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
        if name and online then RaidTrack.LogEPGPChange(name, amount, 0, reason or "EP") end
    end
end

-- /rtdebug
SLASH_RTDEBUG1 = "/rtdebug"
SlashCmdList["RTDEBUG"] = function(msg)
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.settings = RaidTrackDB.settings or {}
    msg = tostring(msg or ""):lower():gsub("%s+", "")
    if msg == "on" or msg == "1" or msg == "true" then
        RaidTrackDB.settings.debugToChat = true
        print("|cff00ffff[RaidTrack]|r Debug echo to chat: |cff00ff00ON|r")
    elseif msg == "off" or msg == "0" or msg == "false" or msg == "" then
        RaidTrackDB.settings.debugToChat = false
        print("|cff00ffff[RaidTrack]|r Debug echo to chat: |cffff0000OFF|r")
    else
        local cur = RaidTrackDB.settings.debugToChat and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        print("|cff00ffff[RaidTrack]|r Usage: /rtdebug [on|off]  (current: " .. cur .. ")")
    end
end

-- ==== Slash Help Registry (jak było) ====
RaidTrack.Slash = RaidTrack.Slash or { descr = {}, order = {}, byTag = {} }
function RaidTrack.SetSlashDescription(tag, text) RaidTrack.Slash.descr[tag] = tostring(text or "") end
function RaidTrack.RegisterSlash(opts, handler, description)
    local tag     = assert(opts and opts.tag, "RegisterSlash: missing tag")
    local aliases = assert(opts and opts.aliases, "RegisterSlash: missing aliases")
    assert(type(handler) == "function", "RegisterSlash: handler must be function")
    SlashCmdList[tag] = handler
    for i, alias in ipairs(aliases) do _G["SLASH_" .. tag .. i] = alias end
    RaidTrack.Slash.descr[tag] = description or RaidTrack.Slash.descr[tag] or ""
    RaidTrack.Slash.byTag[tag] = RaidTrack.Slash.byTag[tag] or {}
    wipe(RaidTrack.Slash.byTag[tag]); for _, a in ipairs(aliases) do table.insert(RaidTrack.Slash.byTag[tag], a) end
    local seen; for _, t in ipairs(RaidTrack.Slash.order) do if t == tag then seen = true break end end
    if not seen then table.insert(RaidTrack.Slash.order, tag) end
end
local _KNOWN_TAG_PREFIX = { "RAIDTRACK", "RT", "RTDEBUG", "RTAUCTION", "RTSYNC", "RTEPGP" }
local function _isKnownTag(tag) for _, p in ipairs(_KNOWN_TAG_PREFIX) do if tag:find("^" .. p) then return true end end return false end
local function _aliasLooksOurs(alias) alias = alias:lower(); return alias:find("^/rt") or alias:find("^/raidtrack") end
function RaidTrack.CollectExistingSlash()
    local found = {}
    for k, v in pairs(_G) do
        local tag = k:match("^SLASH_([A-Z0-9_]+)1$")
        if tag and (SlashCmdList[tag] and type(SlashCmdList[tag]) == "function") and (_isKnownTag(tag) or true) then
            local aliases = {}; local i = 1
            while true do local alias = rawget(_G, ("SLASH_%s%d"):format(tag, i)); if not alias then break end; table.insert(aliases, alias); i = i + 1 end
            local ours = false; for _, a in ipairs(aliases) do if _aliasLooksOurs(a) then ours = true break end end
            if ours then found[tag] = aliases end
        end
    end
    for tag, aliases in pairs(found) do
        RaidTrack.Slash.byTag[tag] = { unpack(aliases) }
        local seen; for _, t in ipairs(RaidTrack.Slash.order) do if t == tag then seen = true break end end
        if not seen then table.insert(RaidTrack.Slash.order, tag) end
        RaidTrack.Slash.descr[tag] = RaidTrack.Slash.descr[tag] or ""
    end
end
function RaidTrack.PrintSlashHelp()
    RaidTrack.CollectExistingSlash()
    print("|cff00ffff[RaidTrack]|r Available slash commands:")
    local known = {}
    for _, tag in ipairs(RaidTrack.Slash.order) do
        known[tag] = true
        local aliases = RaidTrack.Slash.byTag[tag] or {}
        if #aliases > 0 then
            local primary = aliases[1]
            local extra = (#aliases > 1) and ("  (aliases: " .. table.concat(aliases, ", ", 2) .. ")") or ""
            local desc = RaidTrack.Slash.descr[tag]
            if desc and desc ~= "" then print(("  %s - %s%s"):format(primary, desc, extra))
            else print(("  %s%s"):format(primary, extra)) end
        end
    end
    local rest = {}
    for tag, aliases in pairs(RaidTrack.Slash.byTag) do if not known[tag] and #aliases > 0 then table.insert(rest, tag) end end
    table.sort(rest)
    for _, tag in ipairs(rest) do
        local aliases = RaidTrack.Slash.byTag[tag]
        local primary = aliases[1]
        local extra = (#aliases > 1) and ("  (aliases: " .. table.concat(aliases, ", ", 2) .. ")") or ""
        local desc = RaidTrack.Slash.descr[tag] or ""
        if desc ~= "" then print(("  %s - %s%s"):format(primary, desc, extra)) else print(("  %s%s"):format(primary, extra)) end
    end
    print("Tip: /raidtrack help  — to show this list")
end

-- ===== Hard global wipe: allplayers =====
function RaidTrack.DoGlobalWipeAllPlayers(reason)
    reason = tostring(reason or "season reset")

    if not (RaidTrack.IsOfficer and RaidTrack.IsOfficer()) then
        RaidTrack.AddDebugMessage("Only officer can perform /rtcleardb allplayers")
        return
    end

    -- 1) licznik +1 (nie reset!)
    RaidTrack.EnsureWipeId()
    local before = RaidTrack.GetWipeId()
    if not RaidTrack.IncrementWipeId("allplayers-wipe") then return end
    local after = RaidTrack.GetWipeId()

    -- 2) wyzeruj dane, nie tykaj _meta
    RaidTrackDB.epgp = {}
    RaidTrackDB.lootHistory = {}
    RaidTrackDB.epgpLog = { changes = {}, lastId = 0 }
    RaidTrackDB.syncStates, RaidTrackDB.lootSyncStates = {}, {}
    RaidTrackDB.raidHistory, RaidTrackDB.raidInstances = {}, {}
    RaidTrackDB.lastPayloads, RaidTrackDB.activeRaidID = {}, nil
    -- lustro legacy
    RaidTrackDB.epgpWipeID = tostring(after)

    -- legacy mirror
    RaidTrackDB.epgpWipeID = tostring(after)

    -- 3) odśwież UI
    if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
    if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end

    -- 4) ogłoś wipe (CFG), ale NIE proś o REQ_SYNC (to my jesteśmy źródłem prawdy)
    local announce = { wipe = true, epgpWipeID = after, reason = reason }
    local msg = RaidTrack.SafeSerialize(announce)
    local PREFIX = (type(SYNC_PREFIX) == "string" and SYNC_PREFIX) or "RaidTrackSync"
    C_ChatInfo.SendAddonMessage(PREFIX, "CFG|" .. msg, "GUILD")

    RaidTrack.AddDebugMessage("Global wipe done (allplayers). wipeId: " .. tostring(before) .. " -> " .. tostring(after) .. "; reason=" .. tostring(reason))
end

-- Poproś WSZYSTKICH online o FULL (REQ_SYNC|0|0) – bez dotykania Sync.lua
function RaidTrack.RequestFullSyncForDbVersion()
    if not IsInGuild() then return end
    local SYNC_PREFIX = "RaidTrackSync"
    local me = Ambiguate(UnitName("player"), "none")
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name and name ~= me then
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "REQ_SYNC|0|0", "WHISPER", name)
        end
    end
    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("Forced FULL sync request sent to online guild members.")
    end
end
