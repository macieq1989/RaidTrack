-- Core/Sync.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local CHUNK_SIZE  = 200
local SEND_DELAY  = 0.25
local SYNC_PREFIX = "RaidTrackSync"

C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
RaidTrack.pendingSends = {}
RaidTrack.chunkBuffer = {}
RaidTrack.syncTimer = nil

function RaidTrack.ScheduleSync()
    RaidTrack.AddDebugMessage("ScheduleSync() called")
    if RaidTrack.syncTimer then RaidTrack.syncTimer:Cancel() end
    RaidTrack.syncTimer = C_Timer.NewTimer(0.5, function()
        RaidTrack.syncTimer = nil
        RaidTrack.SendSyncDeltaToEligible()
    end)
end

function RaidTrack.SendSyncDeltaToEligible()
    if not IsInGuild() then return end
    local me = UnitName("player")
    local minRank = RaidTrackDB.settings.minSyncRank or 0
    local myRank
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and Ambiguate(name, "none") == me then
            myRank = rankIndex
            break
        end
    end
    if not myRank or myRank > minRank then return end

    local sent = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if online and name ~= me and rankIndex <= minRank and not sent[name] then
            sent[name] = true
            local knownEP = RaidTrackDB.syncStates[name] or 0
            local knownLoot = RaidTrackDB.lootSyncStates[name] or 0
            local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP)
            local lootDelta = {}
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > knownLoot then table.insert(lootDelta, e) end
            end
            if #epgpDelta > 0 or #lootDelta > 0 then
                RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
            end
        end
    end
end

function RaidTrack.RequestSyncFromGuild()
    if not IsInGuild() then return end
    local me = UnitName("player")
    local epID = RaidTrackDB.epgpLog and RaidTrackDB.epgpLog.lastId or 0
    local lootID = 0
    for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
        if e.id and e.id > lootID then lootID = e.id end
    end
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")
        if name ~= me and online then
            local msg = string.format("REQ_SYNC|%d|%d", epID, lootID)
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, msg, "WHISPER", name)
        end
    end
end

function RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
    RaidTrackDB.lootSyncStates = RaidTrackDB.lootSyncStates or {}
    local sendFull = (knownEP == 0 and knownLoot == 0)
    local payload, maxEP, maxLoot

    if sendFull then
        maxEP, maxLoot = 0, 0
        for _, e in ipairs(RaidTrackDB.epgpLog.changes or {}) do
            if e.id and e.id > maxEP then maxEP = e.id end
        end
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
            if e.id and e.id > maxLoot then maxLoot = e.id end
        end
        if maxEP == 0 and maxLoot == 0 then return end

        payload = {
            full = {
                epgp = RaidTrackDB.epgp,
                loot = RaidTrackDB.lootHistory,
                epgpLog = RaidTrackDB.epgpLog.changes,
                settings = RaidTrackDB.settings or {}
            }
        }

        RaidTrack.pendingSends[name] = { meta = { lastEP = maxEP, lastLoot = maxLoot } }
        RaidTrackDB.syncStates[UnitName("player")] = maxEP
        RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
    else
        local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP)
        local lootDelta = {}
        for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
            if e.id and e.id > knownLoot then
                table.insert(lootDelta, e)
            end
        end
        payload = {
            epgpDelta = epgpDelta,
            lootDelta = lootDelta
        }

        local maxEP, maxLoot = knownEP, knownLoot
        for _, e in ipairs(epgpDelta) do
            if e.id and e.id > maxEP then maxEP = e.id end
        end
        for _, e in ipairs(lootDelta) do
            if e.id and e.id > maxLoot then maxLoot = e.id end
        end

        RaidTrackDB.syncStates[name] = maxEP
        RaidTrackDB.lootSyncStates[name] = maxLoot
        RaidTrackDB.syncStates[UnitName("player")] = maxEP
        RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
    end

    local str = RaidTrack.SafeSerialize(payload)
    local total = math.ceil(#str / CHUNK_SIZE)
    local chunks = {}
    for i = 1, total do
        chunks[i] = str:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
    end
    RaidTrack.pendingSends[name] = RaidTrack.pendingSends[name] or {}
    RaidTrack.pendingSends[name].chunks = chunks

    -- Send initial ping to begin chunk transfer
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "PING", "WHISPER", name)

    if sendFull then
        C_Timer.NewTimer(15, function()
            local p = RaidTrack.pendingSends[name]
            if p and not p.gotPong then
                RaidTrack.pendingSends[name] = nil
            end
        end)
    end

    -- ✅ Always send settings as separate message
    if RaidTrack.IsOfficer() then
        local cfgPayload = {
            settings = {
                minSyncRank = RaidTrackDB.settings.minSyncRank,
                officerOnly = RaidTrackDB.settings.officerOnly,
                autoSync    = RaidTrackDB.settings.autoSync
            }
        }
        local cfgStr = RaidTrack.SafeSerialize(cfgPayload)
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "CFG|" .. cfgStr, "WHISPER", name)
        RaidTrack.AddDebugMessage("Sent settings to " .. name .. " with sync data.")
    end
end


function RaidTrack.SendChunkBatch(name)
    local p = RaidTrack.pendingSends[name]
    if not p or not p.chunks then return end

  -- ✅ Dodane: jeśli nie ma chunków, to też zaliczamy sync
    if not p.chunks or #p.chunks == 0 then
        if p.timer then p.timer:Cancel() end
        RaidTrack.pendingSends[name] = nil
        RaidTrack.lastSyncTime = time()
        RaidTrack.AddDebugMessage("Empty sync completed with " .. name)
        return
    end


    local any = false
    for idx, c in ipairs(p.chunks) do
        if c then
            any = true
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, string.format("%d|%d|%s", idx, #p.chunks, c), "WHISPER", name)
        end
    end
    if not any then
        if p.timer then p.timer:Cancel() end
        RaidTrack.pendingSends[name] = nil
        if p.meta and p.meta.lastEP and p.meta.lastLoot then
            RaidTrackDB.syncStates[UnitName("player")] = p.meta.lastEP
            RaidTrackDB.lootSyncStates[UnitName("player")] = p.meta.lastLoot
        end
        RaidTrack.lastSyncTime = time()
    end
end

function RaidTrack.BroadcastSettings()
    if not RaidTrack.IsOfficer() then return end
    local payload = { settings = {
        minSyncRank = RaidTrackDB.settings.minSyncRank,
        officerOnly = RaidTrackDB.settings.officerOnly,
        autoSync    = RaidTrackDB.settings.autoSync
    }}
    local msg = RaidTrack.SafeSerialize(payload)
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "CFG|" .. msg, "GUILD")
end

local mf = CreateFrame("Frame")
mf:RegisterEvent("CHAT_MSG_ADDON")
mf:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then return end
    local who = Ambiguate(sender, "none")
    if msg == "PING" then
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "PONG", "WHISPER", who)
        return
    elseif msg == "PONG" and RaidTrack.pendingSends[who] then
        RaidTrack.pendingSends[who].gotPong = true
        RaidTrack.SendChunkBatch(who)
        return
    elseif msg == "PONG" then
        -- No data was pending, but PONG received -> treat as noop sync
        RaidTrack.lastSyncTime = time()
        RaidTrack.AddDebugMessage("Sync with " .. who .. " completed (no data).")
        return
    elseif msg:sub(1,9) == "REQ_SYNC|" then
        local _, epStr, lootStr = strsplit("|", msg)
        local knownEP = tonumber(epStr) or 0
        local knownLoot = tonumber(lootStr) or 0
        RaidTrack.SendSyncDataTo(who, knownEP, knownLoot)
        return
    elseif msg:sub(1,4) == "ACK|" then
        local idx = tonumber(msg:sub(5))
        local p = RaidTrack.pendingSends[who]
        if p and p.chunks[idx] then
            p.chunks[idx] = nil
        end
        return
   elseif msg:sub(1,4) == "CFG|" then
    local cfgStr = msg:sub(5)
    local ok, data = RaidTrack.SafeDeserialize(cfgStr)
    if ok and data and data.settings then
        for k, v in pairs(data.settings) do
            if v ~= nil then
                RaidTrackDB.settings[k] = v
            end
        end
        -- ⬇️ Dodaj to poniżej:
        if RaidTrack.UpdateSettingsTab then
            RaidTrack.UpdateSettingsTab()
        end
    end
    return
end


    local i, t, d = msg:match("^(%d+)|(%d+)|(.+)$")
    i, t = tonumber(i), tonumber(t)
    if not (i and t and d) then return end
    local buf = RaidTrack.chunkBuffer[who] or { chunks = {}, total = t, received = 0 }
    RaidTrack.chunkBuffer[who] = buf
    if not buf.chunks[i] then
        buf.chunks[i] = d
        buf.received = buf.received + 1
    end
    if buf.received == buf.total then
        local full = table.concat(buf.chunks)
        RaidTrack.chunkBuffer[who] = nil
        local ok, data = RaidTrack.SafeDeserialize(full)
        if not ok then return end

        if data.full then
            RaidTrackDB.epgp = data.full.epgp or {}
            RaidTrackDB.lootHistory = data.full.loot or {}
            local maxLoot = 0
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > maxLoot then maxLoot = e.id end
            end
            if data.full.settings then
                for k, v in pairs(data.full.settings) do
                    RaidTrackDB.settings[k] = v
                end
            end
            RaidTrackDB.epgpLog = {
                changes = data.full.epgpLog or {},
                lastId = (data.full.epgpLog[#data.full.epgpLog] and data.full.epgpLog[#data.full.epgpLog].id) or 0
            }
            local lastEP = RaidTrackDB.epgpLog.lastId or 0
            RaidTrackDB.syncStates[who] = lastEP
            RaidTrackDB.syncStates[UnitName("player")] = lastEP
            RaidTrackDB.lootSyncStates[who] = maxLoot
            RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
            RaidTrack.lastSyncTime = time()
            if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
            if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end
            RaidTrack.lastSyncTime = time()
            if lastEP == 0 or maxLoot == 0 then
                C_Timer.After(2, function()
                    RaidTrack.RequestSyncFromGuild()
                end)
            end
            return
        end

        RaidTrack.MergeEPGPChanges(data.epgpDelta)
        local newLastEP = 0
        for _, e in ipairs(data.epgpDelta or {}) do
            if e.id and e.id > newLastEP then newLastEP = e.id end
        end
        if newLastEP > 0 then
            RaidTrackDB.syncStates[who] = newLastEP
            RaidTrackDB.syncStates[UnitName("player")] = newLastEP
        end
        local seen = {}
        for _, e in ipairs(RaidTrackDB.lootHistory) do seen[e.id] = true end
        local mx = RaidTrackDB.lootSyncStates[who] or 0
        for _, e in ipairs(data.lootDelta or {}) do
            if e.id and not seen[e.id] then
                table.insert(RaidTrackDB.lootHistory, e)
                seen[e.id] = true
                if e.id > mx then mx = e.id end
            end
        end
        RaidTrackDB.lootSyncStates[who] = mx
        if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end
        RaidTrack.lastSyncTime = time()
    end
end)

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" and RaidTrackDB.settings.autoSync ~= false then
        C_Timer.After(5, function()
            RaidTrack.RequestSyncFromGuild()
        end)
    end
    if RaidTrack.IsOfficer() then
        C_Timer.After(10, function()
            RaidTrack.BroadcastSettings()
        end)
    end
end)
-- Jeśli masz funkcję zadeklarowaną bezpośrednio:
-- function RaidTrack.SendSyncData() ... end
-- to nic nie rób – już działa.

-- Ale jeśli nie masz jej wcale (a była wcześniej), dodaj ją z powrotem:
function RaidTrack.SendSyncData()
    if RaidTrack.HandleSendSync then
        RaidTrack.HandleSendSync()
    else
        RaidTrack.AddDebugMessage("SendSyncData: Sync system not initialized")
    end
end

function RaidTrack.HandleSendSync()
    RaidTrack.SendSyncDeltaToEligible()
end
