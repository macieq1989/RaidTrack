-- LootTab.lua (final version with fixes)
local addonName, RaidTrack = ...

-- Ensure core structures exist
RaidTrack.tabs      = RaidTrack.tabs      or {}
RaidTrack.tabFrames = RaidTrack.tabFrames or {}

-- Abort if main frame is missing
if not RaidTrack.mainFrame then return end

-- Tab index for Loot
local i = 3

-- Get or create the Loot tab frame
local frame = RaidTrack.tabFrames[i]
if not frame then
    frame = CreateFrame("Frame", nil, RaidTrack.mainFrame)
    frame:SetSize(960, 700)
    frame:SetPoint("TOPLEFT", RaidTrack.mainFrame, "TOPLEFT", 20, -60)
    frame:Hide()
    RaidTrack.tabFrames[i] = frame
end
RaidTrack.lootTab = frame

-- Keep last item link and history rows
local lastItemLink
local historyRows = {}

-- Sample raids & bosses
local raidBosses = {
    ["Nerub’ar Palace"] = {"Rasha’nan","The Pale Serpent","Queen Ansurek","The Silkshaper","Skittering Horror","The Burrower Below","Anub’ikkaj","Xal’Zix"},
    ["Liberation of Undermine"] = {"Mogul Razdunk","Underboss Greasetooth","Trade Prince Gallywix","King Drekaz","Mechanical Maw","Vault Guardian V-300","Sparkfuse Syndicate","Smoglord Throg"},
}

-- DROPDOWNS
local raidDD = CreateFrame("Frame", "LootRaidDD", frame, "UIDropDownMenuTemplate")
raidDD:SetPoint("TOPLEFT", 20, -40)
UIDropDownMenu_SetWidth(raidDD, 180)
UIDropDownMenu_SetText(raidDD, "Select raid")

local playerDD = CreateFrame("Frame", "LootPlayerDD", frame, "UIDropDownMenuTemplate")
playerDD:SetPoint("TOPLEFT", raidDD, "BOTTOMLEFT", 0, -40)
UIDropDownMenu_SetWidth(playerDD, 180)
UIDropDownMenu_SetText(playerDD, "Select player")

local bossDD = CreateFrame("Frame", "LootBossDD", frame, "UIDropDownMenuTemplate")
bossDD:SetPoint("TOPLEFT", playerDD, "BOTTOMLEFT", 0, -40)
UIDropDownMenu_SetWidth(bossDD, 180)
UIDropDownMenu_SetText(bossDD, "Select boss")

-- Populate dropdowns
local function UpdateRaidDropdown()
  UIDropDownMenu_Initialize(raidDD, function(self, level)
    for raid, _ in pairs(raidBosses) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = raid
      info.func = function()
        UIDropDownMenu_SetSelectedName(raidDD, raid)
        UIDropDownMenu_SetText(raidDD, raid)
        UIDropDownMenu_SetText(bossDD, "Select boss")
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
end

local function UpdatePlayerDropdown()
  UIDropDownMenu_Initialize(playerDD, function(self, level)
    for j = 1, GetNumGroupMembers() do
      local n = GetRaidRosterInfo(j)
      if n then
        local info = UIDropDownMenu_CreateInfo()
        info.text = n
        info.func = function()
          UIDropDownMenu_SetSelectedName(playerDD, n)
          UIDropDownMenu_SetText(playerDD, n)
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end
  end)
end

local function UpdateBossDropdown()
  UIDropDownMenu_Initialize(bossDD, function(self, level)
    local raid = UIDropDownMenu_GetSelectedName(raidDD)
    if raid and raidBosses[raid] then
      for _, b in ipairs(raidBosses[raid]) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = b
        info.func = function()
          UIDropDownMenu_SetSelectedName(bossDD, b)
          UIDropDownMenu_SetText(bossDD, b)
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end
  end)
end

-- EDIT BOXES
local itemEB = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
itemEB:SetSize(300, 24)
itemEB:SetPoint("TOPLEFT", bossDD, "BOTTOMLEFT", 15, -20)
itemEB:SetAutoFocus(false)
itemEB:SetScript("OnEscapePressed", itemEB.ClearFocus)
itemEB:SetScript("OnEnterPressed", itemEB.ClearFocus)
itemEB:SetScript("OnMouseDown", function(s) s:SetFocus() end)

local gpEB = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
gpEB:SetSize(80, 24)
gpEB:SetPoint("LEFT", itemEB, "RIGHT", 20, 0)
gpEB:SetAutoFocus(false)
gpEB:SetNumeric(true)
gpEB:SetScript("OnEscapePressed", gpEB.ClearFocus)
gpEB:SetScript("OnEnterPressed", gpEB.ClearFocus)

-- BUTTONS
local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
saveBtn:SetSize(120, 30)
saveBtn:SetPoint("TOPLEFT", itemEB, "BOTTOMLEFT", 0, -30)
saveBtn:SetText("Save loot")

local pasteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
pasteBtn:SetSize(120, 30)
pasteBtn:SetPoint("LEFT", saveBtn, "RIGHT", 20, 0)
pasteBtn:SetText("Paste item")

local infoFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
infoFS:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -10)
infoFS:SetText("")

-- Backspace clearing for itemEB
itemEB:EnableKeyboard(true)
itemEB:SetScript("OnKeyDown", function(s, key)
  if key == "BACKSPACE" and s:GetText() ~= "" then
    s:SetText("")
    lastItemLink = nil
    infoFS:SetText("")
  end
end)

-- Save loot handler
saveBtn:SetScript("OnClick", function()
  local pl = UIDropDownMenu_GetSelectedName(playerDD)
  local bs = UIDropDownMenu_GetSelectedName(bossDD)
  local it = itemEB:GetText()
  local gp = tonumber(gpEB:GetText()) or 0
  if not (pl and bs and it ~= "") then
    infoFS:SetText("Fill all fields!")
    return
  end
  -- Insert loot entry
  RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}
  local lastId = (#RaidTrackDB.lootHistory > 0) and RaidTrackDB.lootHistory[#RaidTrackDB.lootHistory].id or 0
  local entry = { id = lastId + 1, time = date("%H:%M:%S"), timestamp = time(), player = pl, item = it, boss = bs, gp = gp }
  table.insert(RaidTrackDB.lootHistory, entry)
  RaidTrack.LogEPGPChange(pl, 0, gp, "Loot Save")
  infoFS:SetText("Saved!")
  C_Timer.After(0.1, RaidTrack.UpdateLootHistory)
  -- Reset UI
  UIDropDownMenu_SetText(raidDD, "Select raid")
  UIDropDownMenu_SetText(playerDD, "Select player")
  UIDropDownMenu_SetText(bossDD, "Select boss")
  itemEB:SetText("")
  gpEB:SetText("")
  -- Auto-sync
  if RaidTrackDB.settings.autoSync ~= false then
    RaidTrack.SendSyncData()
    RaidTrack.RequestSyncFromGuild()
  end
end)

-- Paste item handler
pasteBtn:SetScript("OnClick", function()
  if lastItemLink then
    itemEB:SetText(lastItemLink)
    infoFS:SetText("Pasted.")
  else
    infoFS:SetText("No link.")
  end
end)

-- Chat listener & hook
local cm = CreateFrame("Frame")
cm:RegisterEvent("CHAT_MSG_LOOT")
cm:RegisterEvent("CHAT_MSG_RAID")
cm:RegisterEvent("CHAT_MSG_PARTY")
cm:RegisterEvent("CHAT_MSG_SAY")
cm:RegisterEvent("CHAT_MSG_WHISPER")
cm:SetScript("OnEvent", function(_,_,m)
  local link = m:match("|Hitem:.-|h.-|h|r")
  if link then lastItemLink = link end
end)

local function LootTab_ChatLinkHook(cf, link, text, button)
  if button == "RightButton" and IsShiftKeyDown() and link:match("|Hitem:") and frame:IsShown() then
    lastItemLink = text
    itemEB:SetText(text)
    infoFS:SetText("Auto-pasted from chat")
  end
end
for idx = 1, NUM_CHAT_WINDOWS do
  local cf = _G["ChatFrame"..idx]
  if cf then cf:HookScript("OnHyperlinkClick", LootTab_ChatLinkHook) end
end

-- Universal auto-paste on SHIFT+Click of any item
hooksecurefunc("HandleModifiedItemClick", function(link)
  if not frame:IsShown() then return end
  if type(link) == "string" then
    local itemString = link:match("|Hitem:.-|h.-|h") or link
    lastItemLink = itemString
    itemEB:SetText(itemString)
    infoFS:SetText("Auto-pasted item")
  end
end)

-- Create history scroll
local histScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
histScroll:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -20)
histScroll:SetSize(frame:GetWidth() - 40, 300)
histScroll.ScrollBar.ThumbTexture:SetWidth(16)

local histCont = CreateFrame("Frame", nil, histScroll)
histCont:SetSize(frame:GetWidth() - 40, 300)
histScroll:SetScrollChild(histCont)

-- Update function for history with color
function RaidTrack.UpdateLootHistory()
  for _, r in ipairs(historyRows) do r:Hide() end
  historyRows = {}
  local data = RaidTrackDB.lootHistory or {}
  histCont:SetHeight(math.min(#data, 50) * 20)
  for idx = 1, math.min(#data, 50) do
    local e = data[#data - idx + 1]
    local row = CreateFrame("Frame", nil, histCont)
    row:SetSize(histCont:GetWidth(), 20)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", 5, 0)
    row:SetPoint("TOPLEFT", histCont, "TOPLEFT", 0, -(idx-1)*20)
    -- Color name & item
    local _, c = UnitClass(e.player)
    local col = RAID_CLASS_COLORS[c] or { r=1, g=1, b=1 }
    local hex = string.format("%02x%02x%02x", col.r*255, col.g*255, col.b*255)
    local pc = "|cff"..hex..e.player.."|r"
    local itLink = e.item
    local _, _, q = GetItemInfo(itLink)
    local qc = ITEM_QUALITY_COLORS[q] or { r=1, g=1, b=1 }
    local qh = string.format("%02x%02x%02x", qc.r*255, qc.g*255, qc.b*255)
    local ic = "|cff"..qh..itLink.."|r"
    local ts = e.time or date("%H:%M:%S", e.timestamp)
    local bs = e.boss or "Unknown"
    row.text:SetText(string.format("%s - %s looted %s from %s (GP:%d)", ts, pc, ic, bs, e.gp))
    row:Show()
    table.insert(historyRows, row)
  end
end

-- OnShow: init and sync
frame:SetScript("OnShow", function()
  UpdateRaidDropdown()
  UpdatePlayerDropdown()
  UpdateBossDropdown()
  UIDropDownMenu_SetText(raidDD, "Select raid")
  UIDropDownMenu_SetText(playerDD, "Select player")
  UIDropDownMenu_SetText(bossDD, "Select boss")
  itemEB:SetText("")
  gpEB:SetText("")
  infoFS:SetText("")
  RaidTrack.UpdateLootHistory()
  if RaidTrackDB.settings.autoSync then
    RaidTrack.RequestSyncFromGuild()
  end
end)

-- Expose refresh
RaidTrack.RefreshLootTab = RaidTrack.UpdateLootHistory
