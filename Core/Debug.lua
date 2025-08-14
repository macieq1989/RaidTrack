-- Core/Debug.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}

-- Domyślna konfiguracja debug
local DEFAULT_DEBUG_CFG = {
    enabled = true,              -- globalny włącznik/wyłącznik
    level = 3,                   -- 0=OFF,1=ERROR,2=WARN,3=INFO,4=DEBUG,5=TRACE
    whitelist_mode = true,       -- true = pokazuj TYLKO kategorie z whitelisty
    allow_uncategorized = false, -- czy pokazywać logi bez kategorii
    whitelist = {                -- dopisz tu co chcesz widzieć
        BossKill = true,
        Auction  = true,
        Sync     = true,
    },
    blacklist = {                -- opcjonalne „zawsze wycisz”
        UI = true,
    },
    dedupe_window_sec = 2,       -- anty-spam: ten sam tekst w tym oknie czasowym znika
    ring_size = 50               -- ile ostatnich wiadomości trzymać
}

-- dostęp poziomów „nazw” -> liczby
local LEVELS = { ERROR=1, WARN=2, INFO=3, DEBUG=4, TRACE=5 }

-- cache anty-spam
local _lastMsgs = {}   -- [text] = timestamp
local _ring = {}       -- ostatnie N wpisów (do wglądu np. w przyszłości)
local function _ringPush(s)
    table.insert(_ring, 1, s)
    local keep = (RaidTrackDB.settings and RaidTrackDB.settings.debug and RaidTrackDB.settings.debug.ring_size)
        or DEFAULT_DEBUG_CFG.ring_size
    while #_ring > keep do table.remove(_ring) end
end

local function _getCfg()
    RaidTrackDB.settings = RaidTrackDB.settings or {}
    RaidTrackDB.settings.debug = RaidTrackDB.settings.debug or {}
    -- Uzupełnij brakujące pola defaultami (bez nadpisu istniejących)
    for k,v in pairs(DEFAULT_DEBUG_CFG) do
        if RaidTrackDB.settings.debug[k] == nil then
            RaidTrackDB.settings.debug[k] = v
        end
    end
    return RaidTrackDB.settings.debug
end

local function _extractCategory(msg)
    -- wspieramy style: "[BossKill] ...", "[Sync] ...", "BossKill: ...", "Sync - ..."
    local s = tostring(msg or "")
    local c = s:match("^%[([%w_]+)%]") or s:match("^([%w_]+)%s*[:%-]%s")
    return c or nil
end

local function _shouldPrint(cat, levelNum, text)
    local cfg = _getCfg()
    if not cfg.enabled then return false end
    if (levelNum or 3) > (cfg.level or 0) then return false end

    -- kategorie
    if cat then
        if cfg.blacklist and cfg.blacklist[cat] then return false end
        if cfg.whitelist_mode then
            if not (cfg.whitelist and cfg.whitelist[cat]) then return false end
        end
    else
        -- brak kategorii
        if not cfg.allow_uncategorized then return false end
    end

    -- antyspam dedupe
    local win = cfg.dedupe_window_sec or 0
    if win > 0 then
        local now = time()
        local last = _lastMsgs[text]
        if last and (now - last) < win then return false end
        _lastMsgs[text] = now
    end

    return true
end

-- Główna funkcja: przyjmie msg i *opcjonalnie* level/cat
-- Użycia:
--   RaidTrack.DebugPrint("BossKill", "xxx")        -- domyślnie INFO
--   RaidTrack.DebugPrint("Sync", "yyy", "DEBUG")   -- z nazwą poziomu
--   RaidTrack.DebugPrint("Auction", "zzz", 4)      -- z numerem poziomu
function RaidTrack.DebugPrint(category, msg, level)
    local lvl = level
    if type(level) == "string" then lvl = LEVELS[level:upper()] or 3 end
    if type(level) == "number" then lvl = level end
    if lvl == nil then lvl = 3 end

    local text = tostring(msg or "")
    local cat  = category or _extractCategory(text)

    if not _shouldPrint(cat, lvl, text) then return end

    local prefix = "|cff00ffff[RaidTrack]|r"
    if cat then prefix = prefix .. " [" .. cat .. "]" end
    print(prefix .. " " .. text)
    _ringPush(date("%H:%M:%S") .. " " .. (cat and ("["..cat.."] ") or "") .. text)
end

-- Wsteczna kompatybilność: wszystkie istniejące wywołania zostają
-- i przechodzą przez filtr kategorii/pseudo-poziomu (INFO)
function RaidTrack.AddDebugMessage(msg)
    -- ustawienia
    RaidTrackDB = RaidTrackDB or {}
    RaidTrackDB.settings = RaidTrackDB.settings or {}
    -- domyślnie NIE pokazujemy na czacie; możesz włączyć /rtdebug on
    local toChat = (RaidTrackDB.settings.debugToChat == true)

    -- zawsze zapisuj do bufora UI (Settings/Log)
    RaidTrack.debugMessages = RaidTrack.debugMessages or {}
    local line = (date("%H:%M:%S") .. " - " .. tostring(msg))
    table.insert(RaidTrack.debugMessages, 1, line)
    if #RaidTrack.debugMessages > 200 then
        table.remove(RaidTrack.debugMessages, #RaidTrack.debugMessages)
    end

    -- opcjonalnie: echo na czat tylko gdy włączone w settings
    if toChat then
        print("|cff00ffff[RaidTrack]|r " .. tostring(msg))
    end
end


-- API do szybkiego sterowania w locie:
function RaidTrack.SetDebugCategory(cat, enabled)
    local cfg = _getCfg()
    cfg.whitelist = cfg.whitelist or {}
    cfg.whitelist[cat] = not not enabled
end

function RaidTrack.SetDebugLevel(level) -- 0..5 lub nazwa
    local cfg = _getCfg()
    if type(level) == "string" then
        cfg.level = LEVELS[level:upper()] or cfg.level
    elseif type(level) == "number" then
        cfg.level = math.max(0, math.min(5, level))
    end
end

function RaidTrack.EnableDebug(on)
    local cfg = _getCfg()
    cfg.enabled = not not on
end

-- Podgląd bufora ostatnich wiadomości (może się przydać na UI kiedyś)
function RaidTrack.GetRecentDebugLines()
    return _ring
end
-- Debug helper for auction responses (safe stub)
function RaidTrack.DebugPrintResponses(item)
    -- if debug is fully off or no item, just bail
    if not item then return end

    -- Minimal guard: ensure we have a list to iterate
    local bids = item.bids or {}
    local header = string.format(
        "[Auction] Responses for %s (bids=%d)",
        tostring(item.link or item.itemID or "?"),
        #bids
    )

    -- Try to use the structured debugger if present; fallback to AddDebugMessage
    if RaidTrack.DebugPrint then
        RaidTrack.DebugPrint("Auction", header, "DEBUG")
    elseif RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(header)
    end

    -- Print each bid in a compact, safe way
    for i, b in ipairs(bids) do
        local line = string.format(
            "  #%d %s -> %s | EP=%s GP=%s PR=%s",
            i,
            tostring(b.from or b.player or "?"),
            tostring(b.choice or b.response or "?"),
            tostring(b.ep or "?"),
            tostring(b.gp or "?"),
            (b.pr and string.format("%.2f", tonumber(b.pr) or 0)) or "?"
        )
        if RaidTrack.DebugPrint then
            RaidTrack.DebugPrint("Auction", line, "DEBUG")
        elseif RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage(line)
        end
    end
end
