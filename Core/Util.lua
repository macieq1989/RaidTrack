-- Core/Util.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}

local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
assert(AceSerializer, "AceSerializer-3.0 not found!")

-- Serialization
function RaidTrack.SafeSerialize(tbl)
    return AceSerializer:Serialize(tbl)
end
function RaidTrack.SafeDeserialize(str)
    -- Logowanie przed deserializacją
    

    local ok, payload = AceSerializer:Deserialize(str)

    -- Logowanie w przypadku błędu deserializacji
    if not ok then
        RaidTrack.AddDebugMessage("Deserialize failed: " .. tostring(payload))
        return false, nil
    end

    

    return true, payload
end



-- define once (idempotent)
if not RaidTrack._AddDebugMessageCore then
    function RaidTrack._AddDebugMessageCore(msg, opts)
        if msg == nil then return end
        opts = opts or {}

        RaidTrackDB.settings = RaidTrackDB.settings or {}
        local toChat = (RaidTrackDB.settings.debugToChat == true) or (opts.forceEcho == true)

        -- 1) always store to in‑addon log buffer
        RaidTrack.debugMessages = RaidTrack.debugMessages or {}
        local line = date("%H:%M:%S") .. " - " .. tostring(msg)
        table.insert(RaidTrack.debugMessages, 1, line)
        if #RaidTrack.debugMessages > 200 then
            table.remove(RaidTrack.debugMessages, #RaidTrack.debugMessages)
        end

        -- 2) optional echo to chat
        if toChat then
            print("|cff00ffff[RaidTrack]|r " .. tostring(msg))
        end
    end
end

-- public alias (can be wrapped later by UI)
RaidTrack.AddDebugMessage = RaidTrack._AddDebugMessageCore


-- Returns true if player guild rankIndex <= minSyncRank (default 1 = officer)
function RaidTrack.IsOfficer()
    if not IsInGuild() then
        return false
    end

    -- Normalize both names to base (without realm), lowercase
    local function base(name)
        if not name then return nil end
        -- strip realm if present
        local n = name:match("^[^-]+") or name
        return n:lower()
    end

    local myBase = base(UnitName("player"))
    local minRank = tonumber(RaidTrackDB and RaidTrackDB.settings and RaidTrackDB.settings.minSyncRank) or 1

    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and base(name) == myBase then
            -- rankIndex: 0 = GM, 1 = officer, 2+ niżej
            return rankIndex <= minRank
        end
    end

    -- poproś o odświeżenie rosteru na wypadek, gdyby jeszcze nie był gotowy po loginie
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    print(">> Could not find player in guild roster")
    return false
end


-- ===== Guild roster / officer cache (no name normalization) =====
RaidTrack._officerCache = RaidTrack._officerCache or { ready = false, isOfficer = false, lastCheck = 0 }

function RaidTrack._UpdateOfficerCache()
    if not IsInGuild() then
        RaidTrack._officerCache.ready = true
        RaidTrack._officerCache.isOfficer = false
        return
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end

    -- pełna nazwa gracza z realmem
    local myFull = (GetUnitName and GetUnitName("player", true)) or UnitName("player") or ""

    local found, isOfficer = false, false
    local n = GetNumGuildMembers() or 0

    for i = 1, n do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and myFull ~= "" then
            -- TYLKO ścisłe porównanie: nazwa z rosteru musi == GetUnitName("player", true)
            if name == myFull then
                found = true
                local minRank = (RaidTrackDB and RaidTrackDB.settings and RaidTrackDB.settings.minSyncRank) or 1
                isOfficer = (tonumber(rankIndex) or 99) <= minRank
                break
            end
        end
    end

    RaidTrack._officerCache.ready = (n > 0)
    RaidTrack._officerCache.isOfficer = isOfficer

    -- Bez spamu: jeśli roster gotowy i nie znaleziono, nie drukujemy nic
end

if not RaidTrack._guildEvtFrame then
    local f = CreateFrame("Frame", nil, parent)
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_LOGIN" or evt == "PLAYER_GUILD_UPDATE" then
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            end
        end
        if RaidTrack._UpdateOfficerCache then
            RaidTrack._UpdateOfficerCache()
        end
    end)
    RaidTrack._guildEvtFrame = f
end
-- ===== end guild roster / officer cache =====

-- Status helper
function RaidTrack.GetSyncStatus()
    local count = RaidTrack.lastDeltaCount or 0
    if count == 0 then
        return "Idle"
    else
        return string.format("Pending (%d events)", count)
    end
end

function RaidTrack.GetSyncTimeAgo()
    if not RaidTrack.lastSyncTime then
        return "never"
    end
    local elapsed = time() - RaidTrack.lastSyncTime
    local min = math.floor(elapsed / 60)
    local sec = elapsed % 60
    return string.format("%d min %d sec ago", min, sec)
end
function RaidTrack.DebugTableToString(tbl)
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end
    local str = ""
    for k, v in pairs(tbl) do
        str = str .. tostring(k) .. "=" .. tostring(v) .. "; "
    end
    return str
end

function RaidTrack.AddLootToLog(player, itemID, gp)
    -- Dodajemy przedmiot do logu lootu
    local lootEntry = {
        player = player,
        itemID = itemID,
        gp = gp,
        timestamp = time() -- Dodajemy znacznik czasu
    }
    table.insert(RaidTrackDB.lootHistory, lootEntry)
    RaidTrack.AddDebugMessage("Loot added for " .. player .. ": ItemID " .. itemID .. " with GP " .. gp)
end

function RaidTrack.AssignPointsToPlayer(player, gp)
    -- Przypisanie punktów GP dla gracza
    local epgp = RaidTrackDB.epgp[player] or {
        ep = 0,
        gp = 0
    }
    epgp.gp = epgp.gp + gp -- Dodajemy GP
    RaidTrackDB.epgp[player] = epgp
    RaidTrack.AddDebugMessage("Assigned " .. gp .. " GP to player " .. player)
end
function RaidTrack.GetSelectedItemID()
    -- Zakładając, że masz dostęp do UI przedmiotów
    -- Pobieramy obecnie wybrany przedmiot z UI
    local selectedItem = RaidTrack.auctionParticipantWindow.selectedItem -- Zmienna z wybranym przedmiotem w UI

    if selectedItem then
        return selectedItem.itemID -- Zwracamy itemID wybranego przedmiotu
    else
        return nil -- Jeśli nie ma wybranego przedmiotu
    end
end
function RaidTrack.GetEPGP(player)
    -- Zakładam, że posiadasz bazę danych EPGP i chcesz zwrócić EP, GP oraz PR
    -- Pobierz dane z bazy EPGP lub z innej lokalnej struktury danych

    -- Przykład:
    local playerEP, playerGP = 0, 0 -- Inicjalizacja domyślnych wartości EP i GP
    local playerPR = 0 -- Inicjalizacja PR (Priority Rating)

    -- Znajdź dane dla gracza w bazie danych
    if RaidTrackDB.epgp[player] then
        playerEP = RaidTrackDB.epgp[player].ep or 0
        playerGP = RaidTrackDB.epgp[player].gp or 0
        playerPR = playerGP > 0 and playerEP / playerGP or 0

    end

    -- Zwracamy dane
    return playerEP, playerGP, playerPR
end
function RaidTrack.SendAuctionResponseChunked(auctionID, itemID, choice)
    local from = UnitName("player")

    local payload = {
        auctionID = tostring(auctionID), -- ważne!
        itemID = tonumber(itemID),
        choice = choice,
        from = from
    }

    RaidTrack.QueueAuctionChunkedSend(nil, payload.auctionID, "response", payload)

    -- Zawsze lokalnie przetwarzaj własną odpowiedź
    RaidTrack.AddDebugMessage("Locally handling own response for " .. from)
    C_Timer.After(0.05, function()
        RaidTrack.HandleAuctionResponse(payload.auctionID, payload)
    end)
end

function RaidTrack.IsLeader()
    local playerName = UnitName("player")
    local leaderName = RaidTrack.auction and RaidTrack.auction.leader

    print("[RaidTrack] UnitName:", playerName)
    print("[RaidTrack] Auction Leader:", leaderName)

    return leaderName == playerName
end

function RaidTrack.IsPlayerInMyGuild(name)
    for i = 1, GetNumGuildMembers() do
        local fullName = GetGuildRosterInfo(i)
        if fullName and strsplit("-", fullName) == name then
            return true
        end
    end
    return false
end

function RaidTrack.IsPlayerInMyRaid(name)
    for i = 1, GetNumGroupMembers() do
        local raidName = GetRaidRosterInfo(i)
        if raidName and strsplit("-", raidName) == name then
            return true
        end
    end
    return false
end

function RaidTrack.FindItemInBags(itemID)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id == itemID then
                return bag, slot
            end
        end
    end
    return nil, nil
end

function RaidTrack.ApplyHighlight(row, isSelected)
    if not row or not row.frame then
        return
    end

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
    for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
        if localized == classLocalized then
            return token
        end
    end
    for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
        if localized == classLocalized then
            return token
        end
    end
    return classLocalized
end

-- Tworzy popup frame (raz na start)
local function CreateEPGPToastFrame()
    local frame = CreateFrame("Frame", "RaidTrackEPGPToast", UIParent)

    frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    frame:SetSize(300, 60)

    frame.bgTex = frame:CreateTexture(nil, "BACKGROUND")
    frame.bgTex:SetAllPoints()
    frame.bgTex:SetColorTexture(0, 0.4, 0, 0.6)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.text:SetPoint("CENTER")
    frame.text:SetText("")

    frame:SetScript("OnShow", function(self)
        C_Timer.After(4, function()
            self:Hide()
        end)
    end)

    return frame
end

-- Główna funkcja wywołująca popup
function RaidTrack:ShowEPGPToast(amount, playerName, type)
    if not amount or not playerName or not type then return end

    local icon
    local color
    local prefix = (amount >= 0) and "+" or ""

    if type == "EP" then
        icon = "Interface\\Icons\\INV_Misc_Coin_01"
        color = (amount >= 0) and "|cff00ff00" or "|cffff0000"
    elseif type == "GP" then
        icon = "Interface\\Icons\\INV_Misc_Coin_01"
        color = (amount >= 0) and "|cffffcc00" or "|cffff0000"
    else
        icon = "Interface\\Icons\\INV_Misc_QuestionMark"
        color = "|cffffffff"
    end

    -- Zbuduj tekst toastu
    local text = string.format("%s%s %s -> %s|r", color, type, prefix .. amount, playerName)


    -- Pokaż alert frame
    local frame = RaidTrack.epgpAlertFrame or CreateFrame("Frame", nil, UIParent)
    RaidTrack.epgpAlertFrame = frame

    frame:SetSize(300, 64)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -200)
    frame:Show()

    if not frame.bg then
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints()
        frame.bg:SetColorTexture(0, 0, 0, 0.8)
    end

    if not frame.icon then
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetSize(40, 40)
        frame.icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    end

    if not frame.text then
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
        frame.text:SetJustifyH("LEFT")
        frame.text:SetWidth(240)
        frame.text:SetHeight(40)
    end

    frame.icon:SetTexture(icon)
    frame.text:SetText(text)

    frame:SetAlpha(1)
    C_Timer.After(5, function()
        if frame:IsShown() then
            UIFrameFadeOut(frame, 2, 1, 0)
        end
    end)
end


function RaidTrack:ShowItemAwardToast(itemID, gpAmount)
    if not itemID or not gpAmount then return end

    local playerName = UnitName("player")
    local itemName, itemLink, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
    if not itemLink then
        C_Timer.After(0.5, function()
            RaidTrack:ShowItemAwardToast(itemID, gpAmount)
        end)
        return
    end

    local text = string.format("Awarded %s for %d GP", itemLink, gpAmount)

    local frame = RaidTrack.awardToastFrame or CreateFrame("Frame", nil, UIParent)
    RaidTrack.awardToastFrame = frame

    frame:SetSize(320, 64)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -260)
    frame:Show()

    if not frame.bg then
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints()
        frame.bg:SetColorTexture(0, 0, 0, 0.8)
    end

    if not frame.icon then
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetSize(40, 40)
        frame.icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    end

    if not frame.text then
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 10, 0)
        frame.text:SetJustifyH("LEFT")
        frame.text:SetWidth(250)
        frame.text:SetHeight(40)
    end

    frame.icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.text:SetText(text)

    frame:SetAlpha(1)
    C_Timer.After(5, function()
        if frame:IsShown() then
            UIFrameFadeOut(frame, 2, 1, 0)
        end
    end)
end



function RaidTrack.FindExpansionForInstance(instanceID)
    for _, exp in ipairs(RaidTrack.OfflineRaidData or {}) do
        for _, inst in ipairs(exp.instances or {}) do
            if inst.id == instanceID then
                return exp.expansionID
            end
        end
    end
    return nil
end

function RaidTrack:LoadActiveRaid()
    RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}
    for _, raid in ipairs(RaidTrackDB.raidInstances) do
        if raid.status == "started" then
            RaidTrack.activeRaidID = raid.id
            break
        end
    end
end
function RaidTrack.SaveWindowPosition(name, frame)
    if not RaidTrackDB.windowPositions then
        RaidTrackDB.windowPositions = {}
    end
    local point, _, relativePoint, xOfs, yOfs = frame.frame:GetPoint()
    RaidTrackDB.windowPositions[name] = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs
    }
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

-- ==== Guild rank helpers (UI gating) ====
function RaidTrack.GetGuildRanks()
    local values, order = {}, {}
    if IsInGuild() then
        local num = GuildControlGetNumRanks() or 10
        for i = 1, num do
            local name = GuildControlGetRankName(i) or ("Rank "..i)
            values[i] = string.format("%s (%d)", name, i-1) -- label pokazuje 0-based
            table.insert(order, i)
        end
    end
    return values, order
end

-- 1-based indeks rangi gracza (GM = 1); jak brak gildii -> duża liczba
function RaidTrack.GetPlayerGuildRankIndex1()
    local rankIndex0 = select(3, GetGuildInfo("player")) -- 0-based

    if rankIndex0 ~= nil then return (rankIndex0 + 1) end
    return 999
end

-- odczyt wymaganego progu rangi z settings (domyślnie najniższa = brak ograniczeń)
function RaidTrack.GetMinUITabRank()
    RaidTrackDB.settings = RaidTrackDB.settings or {}
    local num = GuildControlGetNumRanks() or 10
    local v = RaidTrackDB.settings.minUITabRankIndex or num
    if type(v) ~= "number" or v < 1 then v = num end
    return v
end

-- czy gracz spełnia wymagania rangi
function RaidTrack.IsPlayerAllowedByRank()
    return RaidTrack.GetPlayerGuildRankIndex1() <= RaidTrack.GetMinUITabRank()
end



-- === RaidTrack Helpers (append) ===

function RaidTrack.IsRaidLeadOrAssist()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function RaidTrack.IsRaidLeader()
    return UnitIsGroupLeader("player")
end

function RaidTrack.GetActiveRaidEntry()
    if not RaidTrackDB or not RaidTrack.activeRaidID then return nil end
    for _, r in ipairs(RaidTrackDB.raidHistory or {}) do
        if tostring(r.id) == tostring(RaidTrack.activeRaidID) then
            return r
        end
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
-- === EP helpers ===
function RaidTrack.AwardEPToCurrentRaidMembers(amount, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    for i = 1, GetNumGroupMembers() do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i)
        if name and online then
            RaidTrack.LogEPGPChange(name, amount, 0, reason or "EP")
        end
    end
end

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

-- ==== Slash Help Registry & Auto-Discovery ==================================

RaidTrack.Slash = RaidTrack.Slash or { descr = {}, order = {}, byTag = {} }

-- (Opcjonalnie) ustaw opis dla TAGu (np. "RAIDTRACK", "RTDEBUG")
function RaidTrack.SetSlashDescription(tag, text)
    RaidTrack.Slash.descr[tag] = tostring(text or "")
end

-- Pomocnicze: zarejestruj wiele aliasów dla jednego TAGu (bez zmiany tego jak działa WoW)
-- Przykład użycia zamiast ręcznego SLASH_XYZn:
--   RaidTrack.RegisterSlash({ tag="RAIDTRACK", aliases={"/raidtrack","/rt"} }, handler, "Otwiera główne okno")
function RaidTrack.RegisterSlash(opts, handler, description)
    local tag     = assert(opts and opts.tag, "RegisterSlash: missing tag")
    local aliases = assert(opts and opts.aliases, "RegisterSlash: missing aliases")
    assert(type(handler) == "function", "RegisterSlash: handler must be function")

    SlashCmdList[tag] = handler
    for i, alias in ipairs(aliases) do
        _G["SLASH_" .. tag .. i] = alias
    end

    -- opis + kolekcja do helpa
    RaidTrack.Slash.descr[tag] = description or RaidTrack.Slash.descr[tag] or ""
    RaidTrack.Slash.byTag[tag] = RaidTrack.Slash.byTag[tag] or {}
    wipe(RaidTrack.Slash.byTag[tag])
    for _, a in ipairs(aliases) do table.insert(RaidTrack.Slash.byTag[tag], a) end

    -- zachowaj kolejność wyświetlania (pierwsze rejestracje wyżej)
    local seen
    for _, t in ipairs(RaidTrack.Slash.order) do if t == tag then seen = true break end end
    if not seen then table.insert(RaidTrack.Slash.order, tag) end
end

-- Auto‑zbieranie już istniejących komend z globali (_G): SLASH_TAG1="/cmd"
-- Filtrujemy do „naszych” przez prefiks aliasu (/rt, /raidtrack) albo znane TAGi.
local _KNOWN_TAG_PREFIX = { "RAIDTRACK", "RT", "RTDEBUG", "RTAUCTION", "RTSYNC", "RTEPGP" }
local function _isKnownTag(tag)
    for _, p in ipairs(_KNOWN_TAG_PREFIX) do
        if tag:find("^" .. p) then return true end
    end
    return false
end

local function _aliasLooksOurs(alias)
    alias = alias:lower()
    return alias:find("^/rt") or alias:find("^/raidtrack")
end

-- Zbierz wszystko, co już zostało zarejestrowane klasycznym sposobem
function RaidTrack.CollectExistingSlash()
    local found = {}
    for k, v in pairs(_G) do
        local tag = k:match("^SLASH_([A-Z0-9_]+)1$")
        if tag and (SlashCmdList[tag] and type(SlashCmdList[tag]) == "function") and (_isKnownTag(tag) or true) then
            -- wczytaj wszystkie aliasy tego TAGu
            local aliases = {}
            local i = 1
            while true do
                local alias = rawget(_G, ("SLASH_%s%d"):format(tag, i))
                if not alias then break end
                table.insert(aliases, alias)
                i = i + 1
            end

            -- bierzemy tylko TAGi, które mają JAKIKOLWIEK alias wyglądający na nasz
            local ours = false
            for _, a in ipairs(aliases) do if _aliasLooksOurs(a) then ours = true break end end
            if ours then
                found[tag] = aliases
            end
        end
    end

    -- Zapisz do naszego rejestru (nie zmienia handlerów)
    for tag, aliases in pairs(found) do
        RaidTrack.Slash.byTag[tag] = { unpack(aliases) }
        local seen
        for _, t in ipairs(RaidTrack.Slash.order) do if t == tag then seen = true break end end
        if not seen then table.insert(RaidTrack.Slash.order, tag) end
        -- jeśli nie ma opisu, zostaw pusty – można uzupełnić SetSlashDescription(tag, "...") gdziekolwiek
        RaidTrack.Slash.descr[tag] = RaidTrack.Slash.descr[tag] or ""
    end
end

-- Wypisz ładny help
function RaidTrack.PrintSlashHelp()
    -- upewnij się, że mamy także te porozrzucane komendy
    RaidTrack.CollectExistingSlash()

    print("|cff00ffff[RaidTrack]|r Available slash commands:")
    -- porządek: wg order, a nowe (zebrane) na końcu alfabetycznie
    local known = {}
    for _, tag in ipairs(RaidTrack.Slash.order) do
        known[tag] = true
        local aliases = RaidTrack.Slash.byTag[tag] or {}
        if #aliases > 0 then
            local primary = aliases[1]
            local extra = ""
            if #aliases > 1 then
                extra = "  (aliases: " .. table.concat(aliases, ", ", 2) .. ")"
            end
            local desc = RaidTrack.Slash.descr[tag]
            if desc and desc ~= "" then
                print(("  %s - %s%s"):format(primary, desc, extra))
            else
                print(("  %s%s"):format(primary, extra))
            end
        end
    end

    -- Dołóż TAGi, które nie weszły do order (gdyby jakieś doszły dynamicznie)
    local rest = {}
    for tag, aliases in pairs(RaidTrack.Slash.byTag) do
        if not known[tag] and #aliases > 0 then
            table.insert(rest, tag)
        end
    end
    table.sort(rest)
    for _, tag in ipairs(rest) do
        local aliases = RaidTrack.Slash.byTag[tag]
        local primary = aliases[1]
        local extra = (#aliases > 1) and ("  (aliases: " .. table.concat(aliases, ", ", 2) .. ")") or ""
        local desc = RaidTrack.Slash.descr[tag] or ""
        if desc ~= "" then
            print(("  %s - %s%s"):format(primary, desc, extra))
        else
            print(("  %s%s"):format(primary, extra))
        end
    end

    print("Tip: /raidtrack help  — to show this list")
end

-- Hard global wipe: czyści wszystko do zera i ustawia nowy epgpWipeID.
-- Wywołanie TYLKO przez officera.
function RaidTrack.DoGlobalWipeAllPlayers(reason)
    reason = tostring(reason or "season reset")
    if not RaidTrack.IsOfficer or not RaidTrack.IsOfficer() then
        RaidTrack.AddDebugMessage("Only officer can perform /rtcleardb allplayers")
        return
    end

    -- nadaj nowy wipeID
    local wipeID = time()
    RaidTrackDB.epgpWipeID = wipeID

    -- lokalny „full zero”
    RaidTrackDB.epgp = {}
    RaidTrackDB.lootHistory = {}
    RaidTrackDB.epgpLog = { changes = {}, lastId = 0 }
    RaidTrackDB.syncStates = {}
    RaidTrackDB.lootSyncStates = {}

    -- ogarnij UI
    if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
    if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end

    -- ogłoś wipe całej gildii – lekkie info + wymuszenie FULL
    local announce = { wipe = true, epgpWipeID = wipeID, reason = reason }
    local msg = RaidTrack.SafeSerialize(announce)
    C_ChatInfo.SendAddonMessage("RaidTrackSync", "CFG|" .. msg, "GUILD")

    -- Zachęć online do natychmiastowego full pulla OD nas (pustego, ale z nowym wipeID)
    C_Timer.After(0.3, function()
        if IsInGuild() then
            for i=1, GetNumGuildMembers() do
                local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
                name = name and Ambiguate(name, "none")
                if online and name and name ~= UnitName("player") then
                    C_ChatInfo.SendAddonMessage("RaidTrackSync",
                        string.format("REQ_SYNC|%d|%d", 0, 0), "WHISPER", name)
                end
            end
        end
    end)

    RaidTrack.AddDebugMessage("Global wipe done (allplayers). WipeID="..wipeID.." reason="..reason)
end
