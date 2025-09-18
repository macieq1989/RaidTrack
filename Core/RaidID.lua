-- Core/RaidID.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local M = RaidTrack.RaidID or {}
RaidTrack.RaidID = M

local RID_PREFIX = "RaidTrackRID"
if not C_ChatInfo.IsAddonMessagePrefixRegistered(RID_PREFIX) then
  C_ChatInfo.RegisterAddonMessagePrefix(RID_PREFIX)
end

if RaidTrack.RegisterChunkHandler then
  RaidTrack.RegisterChunkHandler(RID_PREFIX, function(sender, message)
    M:OnAddonMessage(sender, message)
  end)
end

M.state = M.state or {
  collecting    = false,
  startedAt     = 0,
  timeoutSec    = 3.0,
  requester     = nil,
  results       = {},  -- [player] = { {name=..., id=..., diff=RAW, resetSec=..., resetText=...}, ... }
}

-- ==== utils ====
local function PlayerFullName()
  local n, r = UnitFullName("player")
  r = r and r ~= "" and r or GetRealmName()
  return (n or "Player") .. "-" .. (r:gsub("%s+", ""))
end

local function NormalizeFullName(s)
  if not s or s == "" then return s end
  local n, r = s:match("^([^%-]+)%-?(.*)$")
  if r == "" then
    local _, rr = UnitFullName("player")
    r = rr or GetRealmName()
  end
  r = tostring(r):gsub("%s+", "")
  return n.."-"..r
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

-- POPRAWKA: używamy poprawnej kolejności zwrotów z GetSavedInstanceInfo()
-- Retail/DF: name, id, reset, difficultyID, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEnc, prog, extendDisabled, instanceID
local function collectMyLockouts()
  local entries = {}
  local n = GetNumSavedInstances and (GetNumSavedInstances() or 0) or 0
  for i = 1, n do
    local name, id, reset, diffId, locked, extended, _, isRaid, maxPlayers, diffName =
      GetSavedInstanceInfo(i)
    if isRaid and locked and id then
      -- do payloadu wysyłamy surowy diffId (jeśli jest), inaczej nazwę
      local diffRaw = (diffId ~= nil) and tostring(diffId) or tostring(diffName or (maxPlayers and (maxPlayers.."m") or "?"))
      table.insert(entries, string.format("%s|%s|%s|%d",
        tostring(name or "?"), tostring(id), diffRaw, tonumber(reset or 0) or 0))
    end
  end
  return table.concat(entries, ";")
end

-- ====== Emisja wyników ======
local pendingBroadcast = false
local respondWhisperTo = nil

local function sendMyRIDResponse()
  local payload = collectMyLockouts()
  local msg = "RID_RSP|" .. payload
  if respondWhisperTo and respondWhisperTo ~= "" then
    C_ChatInfo.SendAddonMessage(RID_PREFIX, msg, "WHISPER", respondWhisperTo)
  end
  pendingBroadcast, respondWhisperTo = false, nil
end

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

  local msg = "RID_REQ|" .. self.state.requester
  C_ChatInfo.SendAddonMessage(RID_PREFIX, msg, ch)

  pendingBroadcast   = true
  respondWhisperTo   = self.state.requester
  if RequestRaidInfo then RequestRaidInfo() else sendMyRIDResponse() end

  C_Timer.After(self.state.timeoutSec, function()
    self.state.collecting = false
    self:PrintResults()
    if RaidTrack.UpdateRaidIdTab then RaidTrack.UpdateRaidIdTab() end
  end)
end

function M:GetResults()  return self.state.results end

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
          e.name or "?", tostring(e.diff or "?"), e.id or "?", e.resetText or "?")
        DEFAULT_CHAT_FRAME:AddMessage(line)
      end
    end
  end
end

-- ====== Odbiór ======
function M:OnAddonMessage(sender, message)
  if not sender or not message then return end

  if message:sub(1,8) == "RID_REQ|" then
    local req = message:sub(9)
    if not req or req == "" then return end
    respondWhisperTo = req
    pendingBroadcast = true
    if RequestRaidInfo then RequestRaidInfo() else sendMyRIDResponse() end
    return
  end

  if message:sub(1,8) == "RID_RSP|" then
    local who = NormalizeFullName(sender)
    if who and who ~= "" then
      local payload = message:sub(9) or ""
      self.state.results[who] = {}

      if payload ~= "" then
        for entry in string.gmatch(payload, "([^;]+)") do
          local n, id, diff, resetSec = string.match(entry, "([^|]+)|([^|]+)|([^|]+)|(%-?%d+)")
          local rec = {
            name      = n or "?",
            id        = id or "?",
            diff      = diff or "?",         -- RAW (np. "14" / "Mythic")
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

-- (opcjonalnie) debug: pokaż surowe zwroty API, gdyby coś jeszcze nie grało
SLASH_RIDRAW1 = "/rtidraw"
SlashCmdList["RIDRAW"] = function()
  local n = GetNumSavedInstances() or 0
  print("|cff00ff96[RaidTrack]|r Raw GetSavedInstanceInfo():")
  for i=1,n do
    local name, id, reset, diffId, locked, extended, instMost, isRaid, maxPlayers, diffName =
      GetSavedInstanceInfo(i)
    print(string.format("  [%d] name=%s id=%s diffId=%s diffName=%s isRaid=%s max=%s reset=%s locked=%s",
      i, tostring(name), tostring(id), tostring(diffId), tostring(diffName), tostring(isRaid), tostring(maxPlayers), tostring(reset), tostring(locked)))
  end
end
