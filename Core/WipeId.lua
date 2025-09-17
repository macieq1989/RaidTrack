-- Core/WipeId.lua
local addonName, ns = ...
_G.RaidTrack = _G.RaidTrack or ns or {}
local RaidTrack = _G.RaidTrack

_G.RaidTrackDB = _G.RaidTrackDB or {} -- ZAWSZE global, bez lokalnego cache'a!

-- === Konfiguracja filtrów ===
local LEGACY_MAX_WIPE = 1e9                 -- wszystko >= traktujemy jako legacy/śmieci
local ALLOW_BIG_JUMP_FROM_OFFICER = true    -- duże skoki tylko od oficera

-- === Helpers ===
local function dbg(msg)
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(msg) end
end

local function clean(n)                      -- normalizacja + odcięcie śmieci
    n = tonumber(n) or 0
    if n < 0 or n >= LEGACY_MAX_WIPE then return 0 end
    return math.floor(n + 0.5)
end

local function fmtId(n) return string.format("%.0f", tonumber(n) or 0) end

local function normName(name)
    if not name or name == "" then return "" end
    if Ambiguate then return Ambiguate(name, "none") end
    return name
end

-- Sprawdza, czy dany gracz jest oficerem wg progu minSyncRank
function RaidTrack.IsOfficerName(name)
    name = normName(name)
    if name == "" or not IsInGuild() then return false end

    local db = _G.RaidTrackDB or {}
    local minRank = tonumber(db.settings and db.settings.minSyncRank) or 1

    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full, _, rankIndex = GetGuildRosterInfo(i)
        if full and normName(full) == name then
            return (tonumber(rankIndex) or 99) <= minRank
        end
    end
    return false
end

-- Najlepszy kandydat z legacy-pól (odfiltrowany przez clean)
local function readLegacyCandidate()
    local db = _G.RaidTrackDB or {}
    local m  = db._meta or {}
    local a  = clean(m.wipeId)                 -- nowe pole
    local b  = clean(db.epgpWipeID)            -- stare lustro (string/number)
    local c  = clean(m.lastGoodWipeId)         -- bufor bezpieczeństwa
    local d  = clean(m.wipeid or db.wipeid)    -- ewentualny literówkowy wariant
    return math.max(a, b, c, d)
end

-- Ustaw licznik + spójne lustro w epgpWipeID
local function setLocal(newId, source)
    newId = clean(newId)                       -- twarde czyszczenie
    _G.RaidTrackDB = _G.RaidTrackDB or {}
    local db   = _G.RaidTrackDB
    db._meta   = db._meta or {}
    local meta = db._meta

    meta.wipeId         = newId
    meta.lastGoodWipeId = math.max(clean(meta.lastGoodWipeId), newId)
    meta.wipeSource     = source or meta.wipeSource or "unknown"

    -- utrzymuj lustro (stary kod może go jeszcze czytać)
    db.epgpWipeID = tostring(newId)
end

-- === API licznika ===
function RaidTrack.EnsureWipeId()
    _G.RaidTrackDB = _G.RaidTrackDB or {}
    -- wyczyść śmieci w istniejących polach i przyjmij najlepszy kandydat
    local best = readLegacyCandidate()
    setLocal(best, "ensure/migrate")
end

function RaidTrack.GetWipeId()
    -- bierzemy max z PRAWIDŁOWYCH (clean) pól, by nigdy nie spaść do 0 przez przypadkowy zapis
    local db = _G.RaidTrackDB or {}
    local m  = db._meta or {}
    return math.max(clean(m.wipeId), clean(db.epgpWipeID), clean(m.lastGoodWipeId))
end

function RaidTrack.SetWipeId(newId, reason)
    newId = clean(newId)
    if newId <= 0 then
        dbg("[Wipe] SetWipeId rejected: " .. fmtId(newId))
        return false
    end
    setLocal(newId, "set:" .. tostring(reason or "manual"))
    dbg("[Wipe] Set local wipeId = " .. fmtId(newId) .. " (" .. tostring(reason or "manual") .. ")")
    return true
end

function RaidTrack.IncrementWipeId(reason)
    if not (RaidTrack.IsOfficer and RaidTrack.IsOfficer()) then
        dbg("[Wipe] Blocked non-officer increment")
        return false
    end
    local id = RaidTrack.GetWipeId() + 1
    setLocal(id, "local:" .. (reason or "unknown"))
    dbg("[Wipe] Local wipeId incremented to " .. fmtId(id))
    return true
end

-- Adopcja zdalnego wipeId z filtrami anty-legacy
function RaidTrack.TryAdoptRemoteWipeId(remoteWipeId, fromWho)
    remoteWipeId = clean(remoteWipeId)
    fromWho = normName(fromWho)

    RaidTrack.EnsureWipeId()
    local localId = RaidTrack.GetWipeId()

    -- sanity
    if remoteWipeId <= 0 then
        dbg("[Wipe] Ignored remote wipeId " .. fmtId(remoteWipeId) .. " (<=0)")
        return false
    end
    if remoteWipeId <= localId then
        return false
    end

    -- mały skok (<= +1) — akceptuj od każdego
    if remoteWipeId <= (localId + 1) then
        setLocal(remoteWipeId, "remote-small:" .. (fromWho or "unknown"))
        dbg("[Wipe] Adopted remote wipeId " .. fmtId(remoteWipeId) .. " (was " .. fmtId(localId) .. ") from " .. tostring(fromWho or "?"))
        return true
    end

    -- większy skok — tylko od oficera (jeśli włączone)
    if ALLOW_BIG_JUMP_FROM_OFFICER and RaidTrack.IsOfficerName(fromWho) then
        setLocal(remoteWipeId, "remote-officer:" .. (fromWho or "unknown"))
        dbg("[Wipe] Adopted officer wipeId " .. fmtId(remoteWipeId) .. " (was " .. fmtId(localId) .. ") from " .. tostring(fromWho or "?"))
        return true
    end

    dbg("[Wipe] Ignored remote wipeId " .. fmtId(remoteWipeId) .. " from " .. tostring(fromWho or "?") .. " (big jump; sender not officer)")
    return false
end

-- === Inicjalizacja po ZAŁADOWANIU ADDONA ===
local init = CreateFrame("Frame")
init:RegisterEvent("ADDON_LOADED")
init:SetScript("OnEvent", function(_, _, name)
    if name ~= addonName then return end
    if RaidTrack.EnsureWipeId then RaidTrack.EnsureWipeId() end

    -- dodatkowa sanity: wyczyść i zsynchronizuj lustro
    local db = _G.RaidTrackDB or {}
    db._meta = db._meta or {}
    db._meta.wipeId         = clean(db._meta.wipeId)
    db._meta.lastGoodWipeId = clean(db._meta.lastGoodWipeId)
    db.epgpWipeID           = tostring(clean(db.epgpWipeID))

    db.epgpWipeID = tostring(RaidTrack.GetWipeId())
end)

-- === Sanity po zalogowaniu (tylko w górę) ===
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local best = readLegacyCandidate()
    local cur  = RaidTrack.GetWipeId()
    if best > cur then
        setLocal(best, "login/sanity")
        dbg("[Wipe] login sanity -> " .. fmtId(best))
    end
end)
