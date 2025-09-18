-- Core/RaidID.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local M = RaidTrack.RaidID or {}
RaidTrack.RaidID = M

-- Osobny, krótki prefix (<=16 znaków) na AddOn Messages
local RID_PREFIX = "RaidTrackRID"
if not C_ChatInfo.IsAddonMessagePrefixRegistered(RID_PREFIX) then
  C_ChatInfo.RegisterAddonMessagePrefix(RID_PREFIX)
end

-- Zarejestruj handler przez istniejący dispatcher w Core/Sync.lua
if RaidTrack.RegisterChunkHandler then
  RaidTrack.RegisterChunkHandler(RID_PREFIX, function(sender, message)
    M:OnAddonMessage(sender, message)
  end)
end

-- ====== Stan modułu ======
M.state = M.state or {
  collecting    = false,
  startedAt     = 0,
  timeoutSec    = 3.0,
  requester     = nil,       -- pełna nazwa proszącego
  results       = {},        -- [player] = { {name=..., id=..., diff=..., resetSec=..., resetText=...}, ... }
}

-- ====== Utilsy ======
local function PlayerFullName()
  if UnitFullName then
    local n, r = UnitFullName("player")
    r = r and r ~= "" and r or GetRealmName()
    return (n or "Player") .. "-" .. (r:gsub("%s+", ""))
  end
  local n = UnitName("player") or "Player"
  return n .. "-" .. (GetRealmName():gsub("%s+", ""))
end

local function InGroupChannel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

local function fmtReset(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return "0h" end
  local d = math.floor(seconds / 86400); seconds = seconds % 86400
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  if d > 0 then return string.format("%dd%dh", d, h) end
  if h > 0 then return string.format("%dh%dm", h, m) end
  return string.format("%dm", m)
end

local function collectMyLockouts()
  local entries = {}
  local n = GetNumSavedInstances and (GetNumSavedInstances() or 0) or 0
  for i = 1, n do
    local name, id, reset, diffId, locked, extended, isRaid, maxPlayers, diffName =
      GetSavedInstanceInfo(i)
    if isRaid and locked and id then
      diffName = diffName or (maxPlayers and (maxPlayers .. "m")) or "?"
      table.insert(entries, string.format("%s|%s|%s|%d",
        tostring(name or "?"), tostring(id), tostring(diffName), tonumber(reset or 0) or 0))
    end
  end
  return table.concat(entries, ";")
end

-- ====== Emisja wyników (serializacja „prosta”) ======
local pendingBroadcast = false
local respondWhisperTo = nil

local function sendMyRIDResponse()
  local payload = collectMyLockouts()
  local me = PlayerFullName()
  local msg = "RID_RSP|" .. payload
  -- zawsze WHISPER do proszącego (requester znany z RID_REQ)
  if respondWhisperTo and respondWhisperTo ~= "" then
    C_ChatInfo.SendAddonMessage(RID_PREFIX, msg, "WHISPER", respondWhisperTo)
  else
    -- awaryjnie: nic nie rób
  end
  pendingBroadcast, respondWhisperTo = false, nil
end

-- Własny frame do UPDATE_INSTANCE_INFO (dispatcher CHAT_MSG_ADDON już masz w Core/Sync.lua)
local f = CreateFrame("Frame")
f:RegisterEvent("UPDATE_INSTANCE_INFO")
f:SetScript("OnEvent", function(_, evt)
  if evt == "UPDATE_INSTANCE_INFO" and pendingBroadcast then
    sendMyRIDResponse()
  end
end)

-- ====== API ======
function M:Request(timeoutSec)
  local ch = InGroupChannel()
  if not ch then
    print("|cff00ff96[RaidTrack]|r Musisz być w party/raidzie, aby zebrać ID.")
    return
  end
  self.state.collecting = true
  self.state.startedAt  = time()
  self.state.timeoutSec = tonumber(timeoutSec) or 3.0
  self.state.requester  = PlayerFullName()
  wipe(self.state.results)

  -- Wyślij prośbę do grupy/raida; odpowiadajcie WHISPEREM do mnie
  local msg = "RID_REQ|" .. self.state.requester
  C_ChatInfo.SendAddonMessage(RID_PREFIX, msg, ch)

  -- Odśwież i wyślij swoje lockouty do siebie (też WHISPER), żeby mieć pełny obraz
  pendingBroadcast   = true
  respondWhisperTo   = self.state.requester
  if RequestRaidInfo then RequestRaidInfo() else sendMyRIDResponse() end

  -- Zakończ kolekcję po timeout
  C_Timer.After(self.state.timeoutSec, function()
    self.state.collecting = false
    -- jeśli chcesz od razu zobaczyć wynik w czacie:
    self:PrintResults()
    -- a do UI w nowej zakładce po prostu odpalisz RaidTrack.UpdateRaidIdTab() (jak ją zrobimy)
    if RaidTrack.UpdateRaidIdTab then RaidTrack.UpdateRaidIdTab() end
  end)
end

function M:GetResults()
  return self.state.results
end

function M:PrintResults()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff96[RaidTrack]|r Wyniki ID (raid lockouts):")
  local keys = {}
  for p,_ in pairs(self.state.results) do table.insert(keys, p) end
  table.sort(keys)
  if #keys == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("  (brak odpowiedzi — inni muszą mieć ten sam moduł)")
    return
  end
  for _, who in ipairs(keys) do
    local list = self.state.results[who]
    if not list or #list == 0 then
      DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00"..who.."|r: brak zablokowanych raidów")
    else
      DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00"..who.."|r:")
      for _, e in ipairs(list) do
        local line = string.format("    %s (%s) — ID=%s, reset=%s",
          e.name or "?", e.diff or "?", e.id or "?", e.resetText or "?")
        DEFAULT_CHAT_FRAME:AddMessage(line)
      end
    end
  end
end

-- ====== Odbiór wiadomości ======
function M:OnAddonMessage(sender, message)
  if not sender or not message then return end

  -- RID_REQ|<requester-fullname>
  if message:sub(1,8) == "RID_REQ|" then
    local req = message:sub(9)
    if not req or req == "" then return end
    -- zawsze odpowiadamy WHISPEREM do proszącego
    respondWhisperTo = req
    pendingBroadcast = true
    if RequestRaidInfo then RequestRaidInfo() else sendMyRIDResponse() end
    return
  end

  -- RID_RSP|<payload>
  if message:sub(1,8) == "RID_RSP|" then
    -- nazwa nadawcy jako klucz
    local who = sender
    if who and who ~= "" then
      local payload = message:sub(9) or ""
      self.state.results[who] = {}

      if payload ~= "" then
        for entry in string.gmatch(payload, "([^;]+)") do
          local n, id, diff, resetSec = string.match(entry, "([^|]+)|([^|]+)|([^|]+)|(%-?%d+)")
          local rec = {
            name      = n or "?",
            id        = id or "?",
            diff      = diff or "?",
            resetSec  = tonumber(resetSec) or 0,
          }
          rec.resetText = fmtReset(rec.resetSec)
          table.insert(self.state.results[who], rec)
        end
      end
    end
    return
  end
end

-- ====== Komendy ======
SLASH_RAIDTRACKRID1 = "/rtid"
SLASH_RAIDTRACKRID2 = "/raidid"
SlashCmdList["RAIDTRACKRID"] = function(msg)
  local secs = tonumber(msg)
  M:Request(secs)
end
