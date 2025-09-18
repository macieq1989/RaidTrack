-- Modules/RaidID_Tab.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local AceGUI = LibStub("AceGUI-3.0")

-- Przechowujemy refy do UI, żeby łatwo odświeżać
RaidTrack._raidIdUI = RaidTrack._raidIdUI or {
  container = nil,
  scroll    = nil,
  statusLbl = nil,
  timeout   = 3,
  raidOnly  = true, -- domyślnie filtruj do członków party/raidu
}

-- ==== helpers ====
local function PlayerFullName()
  local n, r = UnitFullName("player")
  r = r and r ~= "" and r or GetRealmName()
  return (n or "Player") .. "-" .. (r:gsub("%s+", ""))
end

local function IsFullNameInMyGroup(fullName)
  if not fullName or fullName == "" then return false end
  local targetName, targetRealm = fullName:match("^([^%-]+)%-?(.*)$")
  targetRealm = targetRealm ~= "" and targetRealm or nil

  local function matchUnit(unit)
    if not UnitExists(unit) then return false end
    local n, r = UnitFullName(unit)
    if not n then return false end
    if targetRealm then
      return (n == targetName) and (r == targetRealm)
    else
      return (n == targetName)
    end
  end

  if IsInRaid() then
    for i=1, GetNumGroupMembers() do
      if matchUnit("raid"..i) then return true end
    end
  elseif IsInGroup() then
    if matchUnit("player") then return true end
    for i=1, GetNumSubgroupMembers() do
      if matchUnit("party"..i) then return true end
    end
  else
    return matchUnit("player")
  end
  return false
end

local function fmtReset(sec)
  sec = tonumber(sec or 0) or 0
  if sec <= 0 then return "0h" end
  local d = math.floor(sec / 86400); sec = sec % 86400
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  if d > 0 then return string.format("%dd%dh", d, h) end
  if h > 0 then return string.format("%dh%dm", h, m) end
  return string.format("%dm", m)
end

local function flattenResults(results, raidOnly)
  -- Zwraca posortowaną listę wierszy { player, name, diff, id, resetText }
  local rows = {}
  for who, list in pairs(results or {}) do
    if (not raidOnly) or IsFullNameInMyGroup(who) then
      if list and #list > 0 then
        table.sort(list, function(a,b)
          if a.name == b.name then
            return tostring(a.id) < tostring(b.id)
          end
          return tostring(a.name) < tostring(b.name)
        end)
        for _, e in ipairs(list) do
          table.insert(rows, {
            player = who,
            name   = e.name or "?",
            diff   = e.diff or "?",
            id     = e.id or "?",
            reset  = fmtReset(e.resetSec or 0),
          })
        end
      else
        -- pokaż „puste” lockouty jako 1 wiersz
        table.insert(rows, {
          player = who, name = "—", diff = "—", id = "—", reset = "—"
        })
      end
    end
  end
  table.sort(rows, function(a,b)
    if a.player == b.player then
      if a.name == b.name then
        return tostring(a.id) < tostring(b.id)
      end
      return a.name < b.name
    end
    return a.player < b.player
  end)
  return rows
end

local function addCell(rowGroup, text, width)
  local lbl = AceGUI:Create("Label")
  lbl:SetText(text or "")
  lbl:SetWidth(width)
  rowGroup:AddChild(lbl)
end

local function buildHeader(parent)
  local header = AceGUI:Create("SimpleGroup")
  header:SetFullWidth(true)
  header:SetLayout("Flow")

  local function headerCell(txt, width)
    local l = AceGUI:Create("Label")
    l:SetText("|cffffd200"..txt.."|r")
    l:SetWidth(width)
    header:AddChild(l)
  end

  headerCell("Player",   180)
  headerCell("Instance", 260)
  headerCell("Diff",      90)
  headerCell("ID",       130)
  headerCell("Reset",     80)

  parent:AddChild(header)
end

local function rebuildTable()
  local ui = RaidTrack._raidIdUI
  if not ui or not ui.scroll then return end

  ui.scroll:ReleaseChildren()

  -- brak modułu zbierającego?
  if not (RaidTrack.RaidID and RaidTrack.RaidID.GetResults) then
    local info = AceGUI:Create("Label")
    info:SetText("|cffff8080RaidID core missing.|r Dodaj plik |cffffff00Modules/RaidID.lua|r, aby zbierać dane (/raidid).")
    info:SetFullWidth(true)
    ui.scroll:AddChild(info)
    return
  end

  local results = RaidTrack.RaidID:GetResults()
  local rows = flattenResults(results, ui.raidOnly)

  buildHeader(ui.scroll)

  if #rows == 0 then
    local empty = AceGUI:Create("Label")
    empty:SetText("|cffaaaaaaBrak danych. Użyj przycisku Scan (wszyscy w grupie muszą mieć moduł).|r")
    empty:SetFullWidth(true)
    ui.scroll:AddChild(empty)
    return
  end

  for _, r in ipairs(rows) do
    local line = AceGUI:Create("SimpleGroup")
    line:SetFullWidth(true)
    line:SetLayout("Flow")

    addCell(line, r.player, 180)
    addCell(line, r.name,   260)
    addCell(line, r.diff,    90)
    addCell(line, r.id,     130)
    addCell(line, r.reset,   80)

    ui.scroll:AddChild(line)
  end
end

-- === API wołane z zewnątrz / przez Refresh ===
function RaidTrack.RefreshRaidIdTab()
  local ui = RaidTrack._raidIdUI
  if ui and ui.statusLbl then
    ui.statusLbl:SetText("|cffaaaaaaReady.|r")
  end
  rebuildTable()
end

-- Alias, bo moduł zbierający wywołuje UpdateRaidIdTab jeśli istnieje:
RaidTrack.UpdateRaidIdTab = RaidTrack.RefreshRaidIdTab

-- === Renderer zakładki ===
function RaidTrack:Render_raidIdTab(container)
  RaidTrack._raidIdUI.container = container
  container:ReleaseChildren()

  local root = AceGUI:Create("SimpleGroup")
  root:SetFullWidth(true)
  root:SetFullHeight(true)
  root:SetLayout("List")
  container:AddChild(root)

  -- Top bar
  local top = AceGUI:Create("SimpleGroup")
  top:SetFullWidth(true)
  top:SetLayout("Flow")
  root:AddChild(top)

  -- Scan button
  local btn = AceGUI:Create("Button")
  btn:SetText("Scan (3s)")
  btn:SetWidth(100)
  btn:SetCallback("OnClick", function()
    if RaidTrack.RaidID and RaidTrack.RaidID.Request then
      local secs = tonumber(RaidTrack._raidIdUI.timeout) or 3
      btn:SetText("Scanning…")
      btn:SetDisabled(true)
      if RaidTrack._raidIdUI.statusLbl then
        RaidTrack._raidIdUI.statusLbl:SetText("|cff00ff96Scanning…|r Odpowiedzi przyjdą WHISPER-em.")
      end
      RaidTrack.RaidID:Request(secs)
      C_Timer.After(secs + 0.1, function()
        btn:SetText("Scan ("..secs.."s)")
        btn:SetDisabled(false)
      end)
    else
      print("|cffff8080[RaidTrack]|r Brak modułu zbierającego (Modules/RaidID.lua).")
    end
  end)
  top:AddChild(btn)

  -- Timeout
  local box = AceGUI:Create("EditBox")
  box:SetLabel("Timeout (s)")
  box:SetText(tostring(RaidTrack._raidIdUI.timeout or 3))
  box:SetWidth(120)
  box:SetCallback("OnEnterPressed", function(_, _, val)
    local n = tonumber(val)
    if n and n >= 1 and n <= 10 then
      RaidTrack._raidIdUI.timeout = n
    else
      RaidTrack._raidIdUI.timeout = 3
      box:SetText("3")
    end
  end)
  top:AddChild(box)

  -- Raid only
  local chk = AceGUI:Create("CheckBox")
  chk:SetLabel("Raid only")
  chk:SetValue(RaidTrack._raidIdUI.raidOnly and true or false)
  chk:SetWidth(120)
  chk:SetCallback("OnValueChanged", function(_, _, v)
    RaidTrack._raidIdUI.raidOnly = not not v
    rebuildTable()
  end)
  top:AddChild(chk)

  -- Status label (fills rest of width)
  local status = AceGUI:Create("Label")
  status:SetText("|cffaaaaaaReady.|r")
  status:SetFullWidth(true)
  top:AddChild(status)
  RaidTrack._raidIdUI.statusLbl = status

  -- Scroll table
  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("List")
  scroll:SetFullWidth(true)
  scroll:SetFullHeight(true)
  root:AddChild(scroll)
  RaidTrack._raidIdUI.scroll = scroll

  -- Initial build
  rebuildTable()
end
