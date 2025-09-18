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
  raidOnly  = true,      -- domyślnie filtruj do członków party/raidu
  filterText = "",       -- tekst filtra
}

-- ==== helpers ====
local function PlayerFullName()
  local n, r = UnitFullName("player")
  r = r and r ~= "" and r or GetRealmName()
  return (n or "Player") .. "-" .. (r:gsub("%s+", ""))
end

-- — normalizacja realmów i porównanie członkostwa w grupie/raidzie —
local function _normRealm(r)  return tostring(r or ""):lower():gsub("[%s%p]", "") end
local function _splitFull(full)
  local n, r = tostring(full or ""):match("^([^%-]+)%-?(.*)$")
  if r and r ~= "" then r = _normRealm(r) else r = nil end
  return n, r
end
local function _buildGroupSet()
  local set = {}
  local function add(unit)
    if not UnitExists(unit) then return end
    local n, r = UnitFullName(unit); if not n then return end
    set[n] = true
    set[n.."-".._normRealm(r)] = true
  end
  if IsInRaid() then
    for i=1, GetNumGroupMembers() do add("raid"..i) end
  elseif IsInGroup() then
    add("player")
    for i=1, GetNumSubgroupMembers() do add("party"..i) end
  else
    add("player")
  end
  return set
end
local function IsFullNameInMyGroup(fullName)
  local n, r = _splitFull(fullName)
  if not n then return false end
  local set = _buildGroupSet()
  if set[n] then return true end
  if r and set[n.."-"..r] then return true end
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

-- Czytelna nazwa trudności z ID (fallback na mapę, gdy API nie zwróci)
local DIFF_FALLBACK = {
  [1]  = "5 Normal",
  [2]  = "5 Heroic",
  [3]  = "10 Normal",
  [4]  = "25 Normal",
  [5]  = "10 Heroic",
  [6]  = "25 Heroic",
  [7]  = "LFR",
  [8]  = "Challenge",
  [9]  = "40 Player",
  [11] = "Heroic (Legacy)",
  [12] = "Normal (Legacy)",
  [14] = "Normal",
  [15] = "Heroic",
  [16] = "Mythic",
  [17] = "LFR",
  [23] = "5 Mythic",
  [24] = "5 Timewalking",
  [33] = "Timewalking (Raid)",
}
local function prettyDiff(diffRaw)
  local s = tostring(diffRaw or "")
  local id = tonumber(s)
  if id then
    if GetDifficultyInfo then
      local name = GetDifficultyInfo(id) -- w Retail/Classic zwraca lokalizowaną nazwę
      if name and name ~= "" then return name end
    end
    return DIFF_FALLBACK[id] or ("Diff "..id)
  end
  -- jeśli to już jest tekst (np. "25 Player"), pokaż jak jest
  return s
end

-- mapa moich lockoutów: key = name .. "||" .. <RAW diff>  → id
local function buildMyLockoutMap(results)
  local map = {}
  if not results then return map end

  local myName, myRealm = UnitFullName("player")
  local myNorm = myName.."-".._normRealm(myRealm or GetRealmName())

  -- dopasuj klucz w results niezależnie od formatu realm
  local myKey
  for who,_ in pairs(results) do
    local n, r = _splitFull(who)
    if n == myName then
      myKey = myKey or who
      if r and (n.."-"..r) == myNorm then myKey = who; break end
    end
  end
  if not myKey then return map end

  local list = results[myKey] or {}
  for _, e in ipairs(list) do
    local name  = tostring(e.name or "?")
    local diffR = tostring(e.diff or "?") -- RAW!
    local id    = tostring(e.id or "")
    if id ~= "" and id ~= "—" then
      map[name.."||"..diffR] = id
    end
  end
  return map
end

-- test filtra tekstowego (case-insensitive)
local function passesFilter(row, filterText)
  filterText = tostring(filterText or ""):lower()
  if filterText == "" then return true end
  local function L(x) return tostring(x or ""):lower() end
  return L(row.player):find(filterText, 1, true)
      or L(row.name):find(filterText, 1, true)
      or L(row.diffDisp):find(filterText, 1, true) -- filtr po ładnym tekście diff
      or L(row.id):find(filterText, 1, true)
      or L(row.reset):find(filterText, 1, true)
end

-- Zwraca posortowaną listę wierszy { player, name, diffRaw, diffDisp, id, reset, differs }
local function flattenResults(results, raidOnly, filterText)
  local myMap = buildMyLockoutMap(results)
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
          local name    = e.name or "?"
          local diffRaw = tostring(e.diff or "?")
          local diffTxt = prettyDiff(diffRaw)
          local idStr   = tostring(e.id or "?")
          local reset   = fmtReset(e.resetSec or 0)
          local key     = tostring(name).."||"..diffRaw -- porównujemy po RAW!
          local myId    = myMap[key]
          local differs = (myId and idStr ~= myId) and (idStr ~= "—")
          local row = {
            player   = who,
            name     = name,
            diffRaw  = diffRaw,
            diffDisp = diffTxt,
            id       = idStr,
            reset    = reset,
            differs  = differs,
          }
          if passesFilter(row, filterText) then
            table.insert(rows, row)
          end
        end
      else
        local row = { player = who, name = "—", diffRaw = "—", diffDisp = "—", id = "—", reset = "—", differs = false }
        if passesFilter(row, filterText) then
          table.insert(rows, row)
        end
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

local COLOR_RED = {r=1.0, g=0.35, b=0.35}

local function addCell(rowGroup, text, width, color)
  local lbl = AceGUI:Create("Label")
  lbl:SetText(text or "")
  if color and lbl.SetColor then
    lbl:SetColor(color.r or 1, color.g or 1, color.b or 1)
  end
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
  headerCell("Diff",      120) -- minimalnie szersze pod pełne nazwy
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
  local rows = flattenResults(results, ui.raidOnly, ui.filterText)

  buildHeader(ui.scroll)

  if #rows == 0 then
    local empty = AceGUI:Create("Label")
    empty:SetText("|cffaaaaaaBrak danych (sprawdź filtr / Raid only).|r")
    empty:SetFullWidth(true)
    ui.scroll:AddChild(empty)
    return
  end

  for _, r in ipairs(rows) do
    local line = AceGUI:Create("SimpleGroup")
    line:SetFullWidth(true)
    line:SetLayout("Flow")

    addCell(line, r.player,   180, nil)
    addCell(line, r.name,     260, nil)
    addCell(line, r.diffDisp, 120, nil)                         -- ładny tekst trudności
    addCell(line, r.id,       130, r.differs and COLOR_RED or nil) -- czerwone jeśli inne niż moje
    addCell(line, r.reset,     80, nil)

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
RaidTrack.UpdateRaidIdTab = RaidTrack.RefreshRaidIdTab -- alias

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

  -- Filter box
  local filterBox = AceGUI:Create("EditBox")
  filterBox:SetLabel("Filter")
  filterBox:SetText(RaidTrack._raidIdUI.filterText or "")
  filterBox:SetWidth(220)
  filterBox:DisableButton(true) -- ukryj defaultowy przycisk OK w AceGUI-EditBox
  filterBox:SetCallback("OnTextChanged", function(_, _, val)
    RaidTrack._raidIdUI.filterText = tostring(val or "")
    rebuildTable()
  end)
  top:AddChild(filterBox)

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
