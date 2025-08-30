-- Core/RaidSync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local SYNC_PREFIX = "RTSYNC"
local CHUNK_SIZE  = 200
C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)

RaidTrack.lastRaidSyncID = nil

-- ==== DB guards ====
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.raidPresets         = RaidTrackDB.raidPresets         or {}
RaidTrackDB._presetTombstones   = RaidTrackDB._presetTombstones   or {}
RaidTrackDB.raidInstances       = RaidTrackDB.raidInstances       or {}
RaidTrackDB._instanceTombstones = RaidTrackDB._instanceTombstones or {}
-- ====================

local TOMBSTONE_TTL = 7*24*60*60

local function _isTombstonedPreset(name)
  local ts = RaidTrackDB._presetTombstones and RaidTrackDB._presetTombstones[name]
  return type(ts)=="number" and (time()-ts) <= TOMBSTONE_TTL
end

local function _isTombstonedInstance(id)
  id = tostring(id)
  local ts = RaidTrackDB._instanceTombstones and RaidTrackDB._instanceTombstones[id]
  return type(ts)=="number" and (time()-ts) <= TOMBSTONE_TTL
end

local function _pruneTombstones()
  local now=time()
  if RaidTrackDB._presetTombstones then
    for k,ts in pairs(RaidTrackDB._presetTombstones) do if type(ts)~="number" or (now-ts)>TOMBSTONE_TTL then RaidTrackDB._presetTombstones[k]=nil end end
  end
  if RaidTrackDB._instanceTombstones then
    for k,ts in pairs(RaidTrackDB._instanceTombstones) do if type(ts)~="number" or (now-ts)>TOMBSTONE_TTL then RaidTrackDB._instanceTombstones[k]=nil end end
  end
end

function RaidTrack.GenerateRaidSyncID()
  return tostring(time())..tostring(math.random(10000,99999))
end

local function findInstanceById(id)
  if not id then return nil end
  for _,r in ipairs(RaidTrackDB.raidInstances or {}) do if tostring(r.id)==tostring(id) then return r end end
  return nil
end

local function isInstanceEnded(inst)
  if not inst then return false end
  if tonumber(inst.endAt) then return true end
  return tostring(inst.status or ""):lower()=="ended"
end

-- Throttle UI refresh
RaidTrack._uiRefreshPending=false
function RaidTrack.RequestUIRefresh()
  if RaidTrack._uiRefreshPending then return end
  RaidTrack._uiRefreshPending=true
  C_Timer.After(0.15, function()
    RaidTrack._uiRefreshPending=false
    if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
    if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end
    if RaidTrack.RefreshRaidTab      then pcall(RaidTrack.RefreshRaidTab)      end
    if RaidTrack.RefreshPresetDropdown then pcall(RaidTrack.RefreshPresetDropdown) end
    if RaidTrack.RefreshBossesView     then pcall(RaidTrack.RefreshBossesView)     end
  end)
end

-- Batch flush RTSYNC (debounce)
RaidTrack._rs_flushScheduled=false
function RaidTrack.RequestRaidSyncFlush(delay)
  delay=tonumber(delay) or 0.4
  if RaidTrack._rs_flushScheduled then return end
  RaidTrack._rs_flushScheduled=true
  C_Timer.After(delay, function()
    RaidTrack._rs_flushScheduled=false
    if RaidTrack.SendRaidSyncData then pcall(RaidTrack.SendRaidSyncData) end
  end)
end

-- ============= SENDER =============
function RaidTrack.SendRaidSyncData()
  _pruneTombstones()

  if not IsInRaid() then return end -- WYŁĄCZNIE RAID

  -- aktywny raid
  local activeID, activePreset = nil, nil
  for _,r in ipairs(RaidTrackDB.raidInstances or {}) do
    if tostring(r.status or ""):lower()=="started" and not tonumber(r.endAt) then
      activeID=r.id; activePreset=r.preset; break
    end
  end

  -- tombstones
  local removedPresets, removedInstances = {}, {}
  for k,v in pairs(RaidTrackDB._presetTombstones or {})   do if v then table.insert(removedPresets, k)   end end
  for k,v in pairs(RaidTrackDB._instanceTombstones or {}) do if v then table.insert(removedInstances, k) end end
  if #removedPresets==0 then removedPresets=nil end
  if #removedInstances==0 then removedInstances=nil end

  local payload = {
    raidSyncID       = RaidTrack.GenerateRaidSyncID(),
    presets          = RaidTrackDB.raidPresets or {},
    instances        = RaidTrackDB.raidInstances or {},
    removedPresets   = removedPresets,
    removedInstances = removedInstances,
    activeID         = activeID,
    activePreset     = activePreset
  }
  RaidTrack.lastRaidSyncID = payload.raidSyncID

  local s = RaidTrack.SafeSerialize(payload); if not s then return end
  -- WYŁĄCZNIE RAID
  RaidTrack.QueueChunkedSend(payload.raidSyncID, SYNC_PREFIX, s, "RAID")
  if RaidTrack.AddDebugMessage then
    RaidTrack.AddDebugMessage(("[RaidSync:send] ch=RAID chunks=%d comp=no"):format(math.ceil(#s/200)))
  end
end

function RaidTrack.BroadcastRaidSync() RaidTrack.SendRaidSyncData() end

function RaidTrack.BroadcastRaidEnded(raidId, endTs)
  raidId = raidId or (RaidTrack.activeRaidID or RaidTrackDB.activeRaidID)
  if raidId then
    local inst=findInstanceById(raidId)
    if inst then inst.endAt = tonumber(endTs) or inst.endAt or time(); inst.status="ended" end
  end
  RaidTrack.SendRaidSyncData()
end

-- ============= APPLY =============
function RaidTrack.ApplyRaidSyncData(data, sender)
  if type(data)~="table" then return end

  -- init
  RaidTrackDB.raidPresets         = RaidTrackDB.raidPresets         or {}
  RaidTrackDB._presetTombstones   = RaidTrackDB._presetTombstones   or {}
  RaidTrackDB.raidInstances       = RaidTrackDB.raidInstances       or {}
  RaidTrackDB._instanceTombstones = RaidTrackDB._instanceTombstones or {}

  local srcPresets   = type(data.presets)=="table"   and data.presets   or {}
  local srcInstances = type(data.instances)=="table" and data.instances or {}
  local removedPres  = type(data.removedPresets)=="table"   and data.removedPresets   or {}
  local removedInst  = type(data.removedInstances)=="table" and data.removedInstances or {}

  -- odrzuć lokalnie tombstonowane
  for name in pairs(srcPresets) do if _isTombstonedPreset(name) then srcPresets[name]=nil end end
  for i=#srcInstances,1,-1 do local it=srcInstances[i]; if it and _isTombstonedInstance(it.id) then table.remove(srcInstances,i) end end

  -- pusty snapshot bez deletów -> ignoruj
  if next(srcPresets)==nil and #srcInstances==0 and #removedPres==0 and #removedInst==0 then
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage(("[RaidSync] Ignored empty snapshot from %s"):format(tostring(sender or "?"))) end
    return
  end

  local changed=false

  -- deletions first
  if #removedPres>0 then
    for _,name in ipairs(removedPres) do if RaidTrackDB.raidPresets[name]~=nil then RaidTrackDB.raidPresets[name]=nil; changed=true end end
  end
  if #removedInst>0 then
    local set={}; for _,id in ipairs(removedInst) do set[tostring(id)]=true end
    for i=#RaidTrackDB.raidInstances,1,-1 do local it=RaidTrackDB.raidInstances[i]; if it and set[tostring(it.id)] then table.remove(RaidTrackDB.raidInstances,i); changed=true end end
  end

  -- upsert presets
  for k,v in pairs(srcPresets) do
    if not _isTombstonedPreset(k) then
      if RaidTrackDB.raidPresets[k] ~= v then RaidTrackDB.raidPresets[k]=v; changed=true end
    end
  end

  -- upsert instances (zachowaj sticky-ended)
  local idx = {}
  for i,it in ipairs(RaidTrackDB.raidInstances) do if it and it.id~=nil then idx[tostring(it.id)]=i end end
  for _,s in ipairs(srcInstances) do
    local sid = s and s.id
    if sid and not _isTombstonedInstance(sid) then
      local key=tostring(sid); local pos=idx[key]
      if pos then
        local localInst = RaidTrackDB.raidInstances[pos]
        local lended    = tonumber(localInst.endAt) or (tostring(localInst.status or ""):lower()=="ended")
        local inended   = tonumber(s.endAt)        or (tostring(s.status or ""):lower()=="ended")
        if lended and not inended then
          -- nie cofaj ended->started
        else
          RaidTrackDB.raidInstances[pos]=s; changed=true
        end
      else
        table.insert(RaidTrackDB.raidInstances, s); idx[key]=#RaidTrackDB.raidInstances; changed=true
      end
    end
  end

  -- aktywny raid tylko dla osób w raidzie i nie-ENDED
  if data.activeID and not IsInRaid() then data.activeID, data.activePreset = nil, nil end
  local instForActive = data.activeID and findInstanceById(data.activeID)
  if instForActive and isInstanceEnded(instForActive) then data.activeID, data.activePreset = nil, nil end
  if data.activeID and _isTombstonedInstance(data.activeID) then data.activeID, data.activePreset = nil, nil end

  if data.activeID then
    RaidTrack.activeRaidID   = data.activeID
    RaidTrackDB.activeRaidID = data.activeID

    local cfg=nil
    if data.activePreset and RaidTrackDB.raidPresets then cfg = RaidTrackDB.raidPresets[data.activePreset] end
    if not cfg then local inst=findInstanceById(data.activeID); if inst and inst.preset then cfg = RaidTrackDB.raidPresets[inst.preset] end end
    RaidTrack.currentRaidConfig = cfg or nil

    if RaidTrack.AddDebugMessage then
      RaidTrack.AddDebugMessage(("[RaidSync] applied from %s: activeID=%s preset=%s cfg=%s"):format(
        tostring(sender or "?"), tostring(data.activeID), tostring(data.activePreset), RaidTrack.currentRaidConfig and "OK" or "nil"))
    end
  end

  if RaidTrack.RequestUIRefresh then RaidTrack.RequestUIRefresh("RaidSync.Apply") end

  return changed and true or false
end

-- ============= RTCHUNK receiver =============
RaidTrack.RegisterChunkHandler(SYNC_PREFIX, function(sender, msg)
  if type(msg)~="string" or msg:sub(1,8)~="RTCHUNK^" then return end

  local msgId, idx, total, chunk

  -- NEW: RTCHUNK^<msgId>^<idx>^<total>^<data>
  do
    local a = msg:find("^", 8, true)
    if a then
      local b = msg:find("^", a+1, true)
      local c = b and msg:find("^", b+1, true) or nil
      local d = c and msg:find("^", c+1, true) or nil
      if a and b and c and d then
        msgId = msg:sub(a+1, b-1)
        idx   = tonumber(msg:sub(b+1, c-1))
        total = tonumber(msg:sub(c+1, d-1))
        chunk = msg:sub(d+1)
      end
    end
  end
  -- LEGACY: RTCHUNK^<idx>^<total>^<data>
  if not (msgId and idx and total and chunk) then
    local a = msg:find("^", 8, true)
    local b = a and msg:find("^", a+1, true) or nil
    local c = b and msg:find("^", b+1, true) or nil
    if a and b and c then
      msgId=nil
      idx   = tonumber(msg:sub(a+1, b-1))
      total = tonumber(msg:sub(b+1, c-1))
      chunk = msg:sub(c+1)
    end
  end
  if not (idx and total and chunk) then return end

  RaidTrack._chunkBuffers = RaidTrack._chunkBuffers or {}
  local key = msgId and ("RT@"..tostring(msgId)) or ("RT@"..tostring(sender or "UNKNOWN"))
  local buf = RaidTrack._chunkBuffers[key] or {}
  buf[idx] = chunk
  RaidTrack._chunkBuffers[key] = buf

  for i=1,total do if not buf[i] then return end end

  local full = table.concat(buf, "")
  RaidTrack._chunkBuffers[key] = nil

  -- (brak kompresji — protokół legacy)
  local ok, data = RaidTrack.SafeDeserialize(full)
  if not ok or not data then
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("❌ Failed to deserialize RaidSync from "..tostring(sender or "?")) end
    return
  end

  if data.activeID and not IsInRaid() then data.activeID, data.activePreset=nil,nil end
  if RaidTrack.ApplyRaidSyncData then RaidTrack.ApplyRaidSyncData(data, sender)
  elseif RaidTrack.MergeRaidSyncData then RaidTrack.MergeRaidSyncData(data, sender) end

  if RaidTrack.RequestUIRefresh then RaidTrack.RequestUIRefresh("RTSYNC-Recv") end
end)

-- Legacy shim
function RaidTrack.MergeRaidSyncData(data, sender)
  if RaidTrack.ApplyRaidSyncData then RaidTrack.ApplyRaidSyncData(data, sender) end
end

-- DC guard na login
local _rt_login = CreateFrame("Frame")
_rt_login:RegisterEvent("PLAYER_LOGIN")
_rt_login:SetScript("OnEvent", function()
  C_Timer.After(0.2, function()
    local id = RaidTrack.activeRaidID or RaidTrackDB.activeRaidID
    if id then
      local inst = findInstanceById(id)
      if inst and isInstanceEnded(inst) then
        RaidTrack.activeRaidID   = nil
        RaidTrackDB.activeRaidID = nil
        if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end
        if RaidTrack.RefreshRaidDropdown then pcall(RaidTrack.RefreshRaidDropdown) end
      end
    end
  end)
end)
