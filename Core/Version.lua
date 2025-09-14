-- Core/Version.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- === Wersja z TOC (fallback "dev") ===
local _getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
RaidTrack.VERSION = (_getMeta and _getMeta(addonName, "Version")) or "dev"

-- === Prefix komunikacji wersji ===
local VERS_PREFIX = "RTVER"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, VERS_PREFIX)
end

-- === DB: bezpieczna inicjalizacja ===
RaidTrackDB = RaidTrackDB or {}
local function _cv()
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.clientVersions = RaidTrackDB.clientVersions or {}
    return RaidTrackDB.clientVersions
end

-- === Porównywanie x.y.z => -1 / 0 / 1 ===
function RaidTrack.CompareVersions(a, b)
    local function split(s)
        local x, y, z = tostring(s or ""):match("(%d+)%.?(%d*)%.?(%d*)")
        return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    end
    local a1, a2, a3 = split(a)
    local b1, b2, b3 = split(b)
    if a1 ~= b1 then return (a1 < b1) and -1 or 1 end
    if a2 ~= b2 then return (a2 < b2) and -1 or 1 end
    if a3 ~= b3 then return (a3 < b3) and -1 or 1 end
    return 0
end

-- 🔧 Migracja: wyczyść stare "unknown" i przeterminowane ślady
local function _normalizeClientVersions()
    local cv = _cv()
    local now = time()
    for name, rec in pairs(cv) do
        if type(rec) ~= "table" then
            cv[name] = nil
        else
            if rec.version == "unknown" or rec.version == "" then
                rec.version = nil
            end
            -- Opcjonalnie czyść bardzo stare, puste wpisy bez wersji/hasAddon
            if (not rec.version) and (not rec.hasAddon) and (not rec.legacy) and (rec.ts and now - rec.ts > 7*24*3600) then
                cv[name] = nil
            end
        end
    end
end

-- wywołaj migrację przy starcie
local _ver_login = CreateFrame("Frame")
_ver_login:RegisterEvent("PLAYER_LOGIN")
_ver_login:SetScript("OnEvent", function() _normalizeClientVersions() end)


-- === Stary helper (zachowany dla zgodności) ===
function RaidTrack.GetCachedClientVersion(name)
    local cv = _cv()
    local n = Ambiguate and Ambiguate(name or "", "none") or (name or "")
    local rec = cv[n]
    local ver = rec and rec.version or nil
    local color = { r = 0.70, g = 0.70, b = 0.70 } -- szary: brak danych

    if ver then
        local cmp = RaidTrack.CompareVersions(ver, RaidTrack.VERSION)
        if cmp == 0 then
            color = { r = 0.20, g = 1.00, b = 0.20 } -- zielony: zgodny
        elseif cmp < 0 then
            color = { r = 1.00, g = 0.80, b = 0.20 } -- żółty: starszy
        else
            color = { r = 0.60, g = 0.60, b = 1.00 } -- nowszy niż my
        end
    end
    return ver, color
end

-- === NOWY: status do UI (tekst + kolor) ===
-- Zwraca:
--  ver, zielony/żółty/niebieski  -> gdy znamy numer
--  "old", pomarańczowy           -> gdy ma addon (hasAddon) ale brak RTVER
--  "-", czerwony                 -> gdy brak śladów addona
function RaidTrack.GetClientVersionStatus(name)
    local cv = _cv()
    local n  = Ambiguate and Ambiguate(name or "", "none") or (name or "")
    local rec = cv[n]

    -- mamy numer
    if rec and rec.version then
        local ver, col = RaidTrack.GetCachedClientVersion(name)
        return ver or "?", col or {r=.7,g=.7,b=.7}
    end

    -- brak numeru, ale wiemy że ma jakiś RaidTrack (np. odpowiedział PONG na Sync)
    if rec and rec.hasAddon then
        return "old", { r = 1.00, g = 0.55, b = 0.15 } -- pomarańczowy
    end

    -- kompletny brak śladów
    return "-", { r = 1.00, g = 0.25, b = 0.25 } -- czerwony
end

-- === Wysyłanie mojej wersji ===
function RaidTrack.SendMyVersion(targetOrChannel)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
    local payload = ("VER|%s|%d"):format(tostring(RaidTrack.VERSION), time())

    if type(targetOrChannel) == "string"
       and targetOrChannel:upper() ~= "GUILD"
       and targetOrChannel:upper() ~= "RAID" then
        C_ChatInfo.SendAddonMessage(VERS_PREFIX, payload, "WHISPER", targetOrChannel)
        return
    end

    if IsInGuild() then C_ChatInfo.SendAddonMessage(VERS_PREFIX, payload, "GUILD") end
    if IsInRaid()  then C_ChatInfo.SendAddonMessage(VERS_PREFIX, payload, "RAID")  end
end

-- === Poproś o wersje od innych ===
function RaidTrack.RequestVersionSweep(target)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
    if type(target) == "string" and target ~= "" then
        C_ChatInfo.SendAddonMessage(VERS_PREFIX, "REQ", "WHISPER", target)
        return
    end
    if IsInGuild() then C_ChatInfo.SendAddonMessage(VERS_PREFIX, "REQ", "GUILD") end
    if IsInRaid()  then C_ChatInfo.SendAddonMessage(VERS_PREFIX, "REQ", "RAID")  end
end

-- === Delikatna sonda: wersja + obecność (throttle) ===
RaidTrack._lastVerProbe = RaidTrack._lastVerProbe or {}
function RaidTrack.ProbeClientVersion(name, force)
    if not name or name == "" then return end
    local now = time()
    local last = RaidTrack._lastVerProbe[name] or 0
    if not force and (now - last) < 90 then return end -- 90s throttle
    RaidTrack._lastVerProbe[name] = now

    -- 1) poproś o wersję (WHISPER, żeby nie spamować)
    RaidTrack.RequestVersionSweep(name)

    -- 2) ping obecności po starym/nowszym kanale Sync (jeśli ktoś ma bardzo stary addon, zwykle odpowie PONG)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage("RaidTrackSync", "PING", "WHISPER", name)
    end
end

-- === Odbiornik RTVER ===
local verComm = CreateFrame("Frame")
verComm:RegisterEvent("CHAT_MSG_ADDON")
verComm:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
    if prefix ~= VERS_PREFIX or not msg or sender == UnitName("player") then return end

    local who = Ambiguate and Ambiguate(sender or "", "none") or (sender or "")
    if who == "" then return end

    if msg == "REQ" then
        RaidTrack.SendMyVersion(who)
        return
    end

    if msg:sub(1,4) == "VER|" then
        local _, ver, ts = strsplit("|", msg)
        ver = ver and ver:match("^%s*(.-)%s*$") or nil
        local cv = _cv()
        cv[who] = cv[who] or {}
        -- 🔧 NIE zapisuj już literalnego "unknown"
        if ver and ver ~= "" then
            cv[who].version = ver
        else
            cv[who].version = nil
        end
        cv[who].ts       = tonumber(ts) or time()
        cv[who].hasAddon = true               -- skoro wysłał VER, addon jest
        if RaidTrack.RefreshGuildTab then pcall(RaidTrack.RefreshGuildTab) end
        return
    end
end)


-- === Pasywne wykrywanie „ma addona” po starszych/nowszych prefixach ===
do
    local KNOWN_PREFIX = {
        ["RaidTrackSync"] = true,
        ["RTSYNC"]        = true,
        ["auction"]       = true,
    }
    -- rejestracja ostrożna (mogą być już zarejestrowane)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        for p in pairs(KNOWN_PREFIX) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, p) end
    end

    local presComm = CreateFrame("Frame")
    presComm:RegisterEvent("CHAT_MSG_ADDON")
    presComm:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        if not KNOWN_PREFIX[prefix] or not sender or sender == UnitName("player") then return end
        local who = Ambiguate and Ambiguate(sender, "none") or sender
        if who == "" then return end

        local cv = _cv()
        cv[who] = cv[who] or {}
        cv[who].hasAddon = true
        cv[who].lastSeen = time()

        -- jeżeli przyszedł klasyczny PONG po naszym PING, a nie mamy numeru wersji,
        -- to najpewniej jest to bardzo stary addon (legacy)
        if prefix == "RaidTrackSync" and msg == "PONG" and not cv[who].version then
            cv[who].legacy = true
        end
    end)
end

-- === Auto-rozgłaszanie i sweep z lekkim throttlem ===
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" then
        C_Timer.After(3, function()
            RaidTrack.SendMyVersion()
            C_Timer.After(2, RaidTrack.RequestVersionSweep)
        end)
    elseif evt == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(1, RaidTrack.SendMyVersion)
    elseif evt == "GUILD_ROSTER_UPDATE" then
        if not RaidTrack._lastVerPing or (time() - RaidTrack._lastVerPing) > 60 then
            RaidTrack._lastVerPing = time()
            C_Timer.After(0.5, RaidTrack.RequestVersionSweep)
        end
    end
end)

-- === Slash do ręcznego sprawdzenia ===
SLASH_RTVER1 = "/rtver"
SlashCmdList["RTVER"] = function()
    print(("RaidTrack version: %s"):format(tostring(RaidTrack.VERSION)))
    RaidTrack.RequestVersionSweep()
end
