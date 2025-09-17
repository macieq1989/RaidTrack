-- Core/SVTrace.lua  (włączyć BARDZO wcześnie w .toc)
local addonName, ns = ...
_G.RaidTrack = _G.RaidTrack or ns or {}
local RaidTrack = _G.RaidTrack

-- absolutnie surowy print (nie przez Settings-tab), żeby ZAWSZE było w czacie
local function SVP(...)
  local msg = "|cffff7f00[SVTRACE]|r " .. string.format(...)
  print(msg)
end

-- uchwyty do SV (po aliasach)
_G.RaidTrackDBV2 = _G.RaidTrackDBV2 or {}
_G.RaidTrackDB   = _G.RaidTrackDBV2
local DB         = _G.RaidTrackDBV2

-- helpers
local function tcount(tbl)
  if type(tbl) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(tbl) do n=n+1 end
  return n
end
local function arrlen(tbl)
  if type(tbl) ~= "table" then return 0 end
  local n = 0
  for i=1,#tbl do if tbl[i] ~= nil then n=i end end
  return n
end
local function deepcopy(v, seen)
  if type(v) ~= "table" then return v end
  if seen and seen[v] then return seen[v] end
  local s = seen or {}
  local out = {}
  s[v] = out
  for k,val in pairs(v) do out[deepcopy(k,s)] = deepcopy(val,s) end
  return out
end

-- stan + backupy
RaidTrack._sv_guard = RaidTrack._sv_guard or {
  snap = {},
  backup = {},
  armed = true,   -- w razie czego można wyłączyć /rtsv arm off (nie dodaję teraz komendy, żeby było prosto)
}

local function snapshot(tag)
  DB._meta = DB._meta or {}
  DB.epgp  = DB.epgp or {}
  DB.lootHistory = DB.lootHistory or {}
  DB.epgpLog = DB.epgpLog or { changes = {}, lastId = 0 }

  local epgpN   = tcount(DB.epgp)
  local lootN   = arrlen(DB.lootHistory)
  local logN    = arrlen(DB.epgpLog.changes)
  local lastId  = tonumber(DB.epgpLog.lastId) or 0
  local wipeId  = (DB._meta and DB._meta.wipeId) or 0
  local schema  = (DB._meta and DB._meta.dbSchema) or 0

  RaidTrack._sv_guard.snap[tag] = {
    epgpN = epgpN, lootN = lootN, logN = logN, lastId = lastId,
    wipeId = wipeId, schema = schema,
    ptrDB = tostring(DB), ptrEPGP = tostring(DB.epgp), ptrLoot = tostring(DB.lootHistory),
  }

  SVP("%s: epgp=%d, loot=%d, log=%d(lastId=%d) | wipeId=%s schema=%s | ptr(DB=%s epgp=%s loot=%s)",
    tag, epgpN, lootN, logN, lastId, tostring(wipeId), tostring(schema),
    tostring(DB), tostring(DB.epgp), tostring(DB.lootHistory))
end

-- pierwszy snapshot (tuż po załadowaniu pliku)
snapshot("LOAD(SVTrace)")

-- backup BLISKI STARTU – żeby móc odtworzyć po cichym wipe
local function makeBackup()
  RaidTrack._sv_guard.backup = {
    epgp        = deepcopy(DB.epgp),
    lootHistory = deepcopy(DB.lootHistory),
    epgpLog     = deepcopy(DB.epgpLog),
    meta        = deepcopy(DB._meta),
  }
end
makeBackup()

-- odtworzenie ręczne (awaryjne)
function RaidTrack._SVRestoreEPGP()
  local b = RaidTrack._sv_guard.backup
  if not b or not b.epgp then
    SVP("Brak backupu do przywrócenia.")
    return
  end
  DB.epgp = deepcopy(b.epgp)
  if b.lootHistory then DB.lootHistory = deepcopy(b.lootHistory) end
  if b.epgpLog then DB.epgpLog = deepcopy(b.epgpLog) end
  SVP("Przywrócono epgp=%d, loot=%d, log=%d.",
    tcount(DB.epgp), arrlen(DB.lootHistory), arrlen(DB.epgpLog and DB.epgpLog.changes or {}))
end

-- Timery: kiedy zwykle “coś” to psuło – zobaczmy w których tikach spada
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, evt, name)
  if evt == "ADDON_LOADED" and name == addonName then
    snapshot("T+0 (ADDON_LOADED)")
    -- kilka późniejszych tików:
    C_Timer.After(0.2, function() snapshot("T+0.2") end)
    C_Timer.After(0.5, function() snapshot("T+0.5") end)
    C_Timer.After(1.0, function() snapshot("T+1.0") end)
    C_Timer.After(2.0, function() snapshot("T+2.0") end)
    C_Timer.After(5.0, function() snapshot("T+5.0") end)
  elseif evt == "PLAYER_LOGIN" then
    snapshot("LOGIN")
  end
end)

-- Hooki na podejrzane funkcje (jeśli istnieją)
local function hookFn(tbl, key, tag)
  local fn = rawget(tbl, key)
  if type(fn) ~= "function" then return end
  tbl[key] = function(...)
    SVP("%s called -> stack:\n%s", tag, debugstack(2, 8, 7))
    local r = { pcall(fn, ...) }
    if not r[1] then
      SVP("%s ERROR: %s", tag, tostring(r[2]))
      return
    end
    -- po wywołaniu znów snapshot
    snapshot(tag .. " -> AFTER")
    return select(2, unpack(r))
  end
end

-- spróbujmy owinąć najczęściej czyszczące ścieżki
C_Timer.After(0, function()
  hookFn(RaidTrack, "ClearRaidTrackDB",  "[HOOK] ClearRaidTrackDB")
  hookFn(RaidTrack, "EnsureDbSchema",    "[HOOK] EnsureDbSchema")
  hookFn(RaidTrack, "TryAdoptRemoteWipeId", "[HOOK] TryAdoptRemoteWipeId")
  hookFn(RaidTrack, "DoGlobalWipeAllPlayers", "[HOOK] DoGlobalWipeAllPlayers")
  hookFn(RaidTrack, "GlobalWipeAllPlayers",   "[HOOK] GlobalWipeAllPlayers")
  hookFn(RaidTrack, "LogEPGPChange",     "[HOOK] LogEPGPChange")
end)

-- Hook na wipe() i table.wipe – łap wykonywane na naszych tabelach
local _wipe = wipe
wipe = function(t)
  local isMine = (t == DB) or (t == DB.epgp) or (t == DB.lootHistory)
                 or (t == DB.epgpLog) or (t == (DB.epgpLog and DB.epgpLog.changes))
  if isMine then
    SVP("wipe() on %s -> stack:\n%s", tostring(t), debugstack(2, 8, 7))
  end
  return _wipe(t)
end
if table and table.wipe and table.wipe ~= wipe then
  local _tw = table.wipe
  table.wipe = function(t)
    local isMine = (t == DB) or (t == DB.epgp) or (t == DB.lootHistory)
                   or (t == DB.epgpLog) or (t == (DB.epgpLog and DB.epgpLog.changes))
    if isMine then
      SVP("table.wipe() on %s -> stack:\n%s", tostring(t), debugstack(2, 8, 7))
    end
    return _tw(t)
  end
end

-- Slash: snapshot + ręczne przywrócenie
SLASH_RTSVQ1 = "/rtsv?"
SlashCmdList["RTSVQ"] = function()
  snapshot("MANUAL")
end

SLASH_RTSVREST1 = "/rtsv!"
SlashCmdList["RTSVREST"] = function()
  RaidTrack._SVRestoreEPGP()
  snapshot("MANUAL-RESTORED")
end

-- Dodatkowa czujka: jeżeli w którymś “tiku” epgp spadnie do 0 a backup miał >0, zgłoś
local function watchdog()
  local had = tcount(RaidTrack._sv_guard.backup.epgp or {})
  local nowE = tcount(DB.epgp or {})
  if had > 0 and nowE == 0 then
    SVP("DETECTED DROP: epgp %d -> 0 bez jawnego wipe. Stack:\n%s", had, debugstack(2, 8, 7))
  end
end
C_Timer.NewTicker(1.0, watchdog, 10) -- przez pierwsze ~10s po starcie
