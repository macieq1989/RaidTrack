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
local function _ensureCV()
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

-- === Odczyt z cache: wersja + kolor do UI ===
function RaidTrack.GetCachedClientVersion(name)
    local cv = _ensureCV()
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
            color = { r = 0.60, g = 0.60, b = 1.00 } -- nowszy niż my (rzadkie)
        end
    end
    return ver, color
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
function RaidTrack.RequestVersionSweep()
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return end
    if IsInGuild() then C_ChatInfo.SendAddonMessage(VERS_PREFIX, "REQ", "GUILD") end
    if IsInRaid()  then C_ChatInfo.SendAddonMessage(VERS_PREFIX, "REQ", "RAID")  end
end

-- === Odbiornik COMM: niezależny od Sync.lua / RegisterChunkHandler ===
local verComm = CreateFrame("Frame")
verComm:RegisterEvent("CHAT_MSG_ADDON")
verComm:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
    if prefix ~= VERS_PREFIX or not msg or sender == UnitName("player") then return end

    local who = Ambiguate and Ambiguate(sender or "", "none") or (sender or "")
    if who == "" then return end

    if msg == "REQ" then
        -- ktoś prosi o wersję → odeślij moją
        RaidTrack.SendMyVersion(who)
        return
    end

    if msg:sub(1,4) == "VER|" then
        local _, ver, ts = strsplit("|", msg)
        ver = ver and ver:match("^%s*(.-)%s*$") or nil

        local cv = _ensureCV()
        cv[who] = {
            version = ver or "unknown",
            ts = tonumber(ts) or time()
        }

        if RaidTrack.RefreshGuildTab then pcall(RaidTrack.RefreshGuildTab) end
        return
    end
end)

-- === Auto-rozgłaszanie i sweep z lekkim throttlem ===
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" then
        C_Timer.After(3, function()
            RaidTrack.SendMyVersion()                 -- ogłoś moją wersję
            C_Timer.After(2, RaidTrack.RequestVersionSweep) -- poproś o wersje
        end)
    elseif evt == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(1, RaidTrack.SendMyVersion)     -- dołączono/zmieniono grupę
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
