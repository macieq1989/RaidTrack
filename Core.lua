-- Core.lua (delta‑sync + pull‑sync, UI, slash, status, whisper, clear‑DB)

local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
assert(AceSerializer, "AceSerializer-3.0 not found!")

local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
_G[addonName] = RaidTrack

-- Serialization
function RaidTrack.SafeSerialize(tbl)
    return AceSerializer:Serialize(tbl)
end
function RaidTrack.SafeDeserialize(str)
    local ok, payload = AceSerializer:Deserialize(str)
    if not ok then
        RaidTrack.AddDebugMessage("Deserialize failed: " .. tostring(payload))
        return false, nil
    end
    return true, payload
end

-- Constants
local CHUNK_SIZE  = 200
local SEND_DELAY  = 0.25
local SYNC_PREFIX = "RaidTrackSync"

-- SavedVariables defaults (will be set properly on ADDON_LOADED)
RaidTrackDB             = RaidTrackDB             or {}
RaidTrackDB.settings    = RaidTrackDB.settings    or {}
RaidTrackDB.epgp        = RaidTrackDB.epgp        or {}
RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}
RaidTrackDB.epgpLog     = RaidTrackDB.epgpLog     or { changes = {}, lastId = 0 }
RaidTrackDB.syncStates  = RaidTrackDB.syncStates  or {}
RaidTrackDB.lootSyncStates = RaidTrackDB.lootSyncStates or {}
-- lastPayloads moved into ADDON_LOADED handler

-- Initialize SavedVariables-dependent tables after loading
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    -- ensure these exist now that SavedVariables are loaded
    RaidTrackDB.syncStates      = RaidTrackDB.syncStates      or {}
    RaidTrackDB.lootSyncStates  = RaidTrackDB.lootSyncStates  or {}
    RaidTrackDB.lastPayloads    = RaidTrackDB.lastPayloads    or {}
    initFrame:UnregisterEvent("ADDON_LOADED")
end)

initFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end

    RaidTrackDB.syncStates      = RaidTrackDB.syncStates      or {}
    RaidTrackDB.lootSyncStates  = RaidTrackDB.lootSyncStates  or {}
    RaidTrackDB.lastPayloads    = RaidTrackDB.lastPayloads    or {}
    RaidTrackDB.settings        = RaidTrackDB.settings        or {}
    
    -- ✅ Dodaj domyślny poziom rangi do synchronizacji (0 = GM, 1 = officerzy itd.)
    if RaidTrackDB.settings.minSyncRank == nil then
        RaidTrackDB.settings.minSyncRank = 1
        RaidTrack.AddDebugMessage("Default minSyncRank set to 1")
    end

    initFrame:UnregisterEvent("ADDON_LOADED")
end)



-- Debug helper
function RaidTrack.AddDebugMessage(msg)
    print("|cff00ffff[RaidTrack]|r " .. tostring(msg))
    RaidTrack.debugMessages = RaidTrack.debugMessages or {}
    table.insert(RaidTrack.debugMessages, 1, date("%H:%M:%S") .. " - " .. msg)
    if #RaidTrack.debugMessages > 50 then
        table.remove(RaidTrack.debugMessages, #RaidTrack.debugMessages)
    end
end

-- Check if player is officer (Retail)
function RaidTrack.IsOfficer()
    if not IsInGuild() then return false end
    local myName = UnitName("player")
    local myRank = nil
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and Ambiguate(name, "none") == myName then
            myRank = rankIndex
            break
        end
    end
    if myRank == nil then return false end

    local configuredMinRank = RaidTrackDB.settings.minSyncRank or 0
    return myRank <= configuredMinRank  -- im mniejszy index, tym wyższa ranga
end


-- Log EPGP changes
function RaidTrack.LogEPGPChange(player, deltaEP, deltaGP, by)
    if not player or (not deltaEP and not deltaGP) then return end
    RaidTrackDB.epgpLog.lastId = RaidTrackDB.epgpLog.lastId + 1
    local entry = {
        id        = RaidTrackDB.epgpLog.lastId,
        player    = player,
        deltaEP   = deltaEP or 0,
        deltaGP   = deltaGP or 0,
        by        = by or UnitName("player"),
        timestamp = time(),
    }
    table.insert(RaidTrackDB.epgpLog.changes, entry)
    RaidTrack.ApplyEPGPChange(entry)
    RaidTrack.AddDebugMessage("Logged change: EP=" .. entry.deltaEP .. ", GP=" .. entry.deltaGP .. " to " .. player)
    -- Auto-sync after change
if RaidTrackDB.settings.autoSync ~= false then
    RaidTrack.ScheduleSync()
end



end

-- Apply EPGP change locally
function RaidTrack.ApplyEPGPChange(entry)
    if not entry or not entry.player then return end
    local data = RaidTrackDB.epgp[entry.player] or { ep = 0, gp = 0 }
    data.ep = data.ep + entry.deltaEP
    data.gp = data.gp + entry.deltaGP
    RaidTrackDB.epgp[entry.player] = data
end

-- Get EPGP changes since given ID
function RaidTrack.GetEPGPChangesSince(lastId)
    local res = {}
    for _, e in ipairs(RaidTrackDB.epgpLog.changes) do
        if e.id > lastId then table.insert(res, e) end
    end
    return res
end

-- Merge incoming EPGP changes
function RaidTrack.HasEPGPChange(id)
    for _, e in ipairs(RaidTrackDB.epgpLog.changes) do
        if e.id == id then return true end
    end
    return false
end
function RaidTrack.MergeEPGPChanges(incoming)
    table.sort(incoming, function(a,b) return a.id < b.id end)
    for _, e in ipairs(incoming) do
        if e.id and not RaidTrack.HasEPGPChange(e.id) then
            table.insert(RaidTrackDB.epgpLog.changes, e)
            RaidTrackDB.epgpLog.lastId = math.max(RaidTrackDB.epgpLog.lastId, e.id)
            RaidTrack.ApplyEPGPChange(e)
        end
    end
    if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
end

-- UI: Main frame & tabs
RaidTrack.tabs, RaidTrack.tabFrames = {}, {}
local frame = CreateFrame("Frame","RaidTrackFrame",UIParent,"BasicFrameTemplateWithInset")
frame:SetSize(1000,800); frame:SetPoint("CENTER"); frame:Hide()
frame:EnableMouse(true); frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
RaidTrack.mainFrame = frame

frame.title = frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
frame.title:SetText("RaidTrack")

local tabNames = {"Raid","EPGP","Loot","Settings","Guild"}
for i,name in ipairs(tabNames) do
    local btn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    btn:SetSize(80,25); btn:SetText(name)
    btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10 + (i-1)*85, -30)
    RaidTrack.tabs[i] = btn
    if not RaidTrack.tabFrames[i] then
        local pane = CreateFrame("Frame", nil, frame)
        pane:SetSize(960,700); pane:SetPoint("TOPLEFT", frame, "TOPLEFT", 20,-60)
        pane:Hide()
        RaidTrack.tabFrames[i] = pane
    end
end

function RaidTrack.ShowTab(i)
    for idx,p in ipairs(RaidTrack.tabFrames) do p:SetShown(idx==i) end
    if i==2 and RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
    if i==3 and RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end
end
for i,btn in ipairs(RaidTrack.tabs) do
    btn:SetScript("OnClick", function() RaidTrack.ShowTab(i) end)
end

-- Slash command
SLASH_RAIDTRACK1 = "/raidtrack"
SlashCmdList["RAIDTRACK"] = function()
    if frame:IsShown() then frame:Hide() else frame:Show(); RaidTrack.ShowTab(1) end
end

-- Settings status
local st = RaidTrack.tabFrames[4]
st.sync = st:CreateFontString(nil,"OVERLAY","GameFontNormal")
st.sync:SetPoint("TOPLEFT",10,-10)
st.sync:SetText("Last sync: never")
function RaidTrack.UpdateSyncStatus(t)
    st.sync:SetText("Last sync: "..t)
end

-- Whisper EPGP query
local wh = CreateFrame("Frame")
wh:RegisterEvent("CHAT_MSG_WHISPER")
wh:SetScript("OnEvent", function(_,_,msg,sender)
    local who = Ambiguate(sender,"none")
    msg = msg:lower():trim()
    if msg=="!epgp" or msg=="/epgp" then
        local d = RaidTrackDB.epgp[who] or {ep=0,gp=0}
        local pr = (d.gp>0) and (d.ep/d.gp) or 0
        local rep=string.format("EP: %d GP: %d PR: %.2f",d.ep,d.gp,pr)
        SendChatMessage(rep,"WHISPER",nil,who)
        RaidTrack.AddDebugMessage("Reply to "..who..": "..rep)
    end
end)

-- Pull request deltas (only online)
function RaidTrack.RequestSyncFromGuild()
    if not IsInGuild() then return end
    local me = UnitName("player")
    local epID = RaidTrackDB.epgpLog and RaidTrackDB.epgpLog.lastId or 0
    local lootID = 0
    for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
        if e.id and e.id > lootID then lootID = e.id end
    end

    for i = 1, GetNumGuildMembers() do
        local nm, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        local who = nm and Ambiguate(nm, "none")
        if who ~= me and online then
            local msg = string.format("REQ_SYNC|%d|%d", epID, lootID)
            C_ChatInfo.SendAddonMessage(SYNC_PREFIX, msg, "WHISPER", who)
            RaidTrack.AddDebugMessage("REQ_SYNC -> " .. who .. " (epID=" .. epID .. ", lootID=" .. lootID .. ")")
        end
    end
end


-- Auto‑pull on login (no push)
-- Auto‑pull on login (no push)
local lg = CreateFrame("Frame")
lg:RegisterEvent("PLAYER_LOGIN")
lg:SetScript("OnEvent", function(_,evt)
    if evt=="PLAYER_LOGIN" and RaidTrackDB.settings.autoSync~=false then
        C_Timer.After(5, function()
            RaidTrack.AddDebugMessage("Auto pull on login")
            RaidTrack.RequestSyncFromGuild()
        end)
    end

    -- BONUS: tylko officerzy broadcastują ustawienia 10s po zalogowaniu
    if RaidTrack.IsOfficer() then
        C_Timer.After(10, function()
            RaidTrack.BroadcastSettings()
        end)
    end
end)

-- Networking setup
C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
RaidTrack.pendingSends = {}
RaidTrack.chunkBuffer = {}

RaidTrack.syncTimer = nil

function RaidTrack.ScheduleSync()
    RaidTrack.AddDebugMessage("ScheduleSync() called")
    if RaidTrack.syncTimer then
        RaidTrack.syncTimer:Cancel()
    end
    RaidTrack.syncTimer = C_Timer.NewTimer(0.5, function()
        RaidTrack.syncTimer = nil
        RaidTrack.SendSyncDeltaToEligible()
    end)
end


function RaidTrack.SendSyncDeltaToEligible()
    RaidTrack.AddDebugMessage("Running SendSyncDeltaToEligible()")

    if not IsInGuild() then return end
    local me = UnitName("player")
    local myRank = nil
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name and Ambiguate(name, "none") == me then
            myRank = rankIndex
            break
        end
    end
    if not myRank then
        RaidTrack.AddDebugMessage("Cannot determine own rank.")
        return
    end

    local minRank = RaidTrackDB.settings.minSyncRank or 0
    RaidTrack.AddDebugMessage("My rank=" .. tostring(myRank) .. ", minSyncRank=" .. tostring(minRank))
    if myRank > minRank then
        RaidTrack.AddDebugMessage("Not permitted to sync (rank too low).")
        return
    end

    local sent = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        name = name and Ambiguate(name, "none")

        if online and name ~= me and rankIndex <= minRank and not sent[name] then
            sent[name] = true

            -- Użyj obecnego syncState jako "knownEP" i "knownLoot"
            local knownEP = RaidTrackDB.syncStates[name] or 0
            local knownLoot = RaidTrackDB.lootSyncStates[name] or 0

            -- Wstępna analiza: czy będzie coś nowego do wysłania?
            local epgpDelta = RaidTrack.GetEPGPChangesSince(knownEP)
            local lootDelta = {}
            for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
                if e.id and e.id > knownLoot then
                    table.insert(lootDelta, e)
                end
            end

            if #epgpDelta == 0 and #lootDelta == 0 then
                RaidTrack.AddDebugMessage("No new delta for " .. name .. ", skipping send")
            else
                RaidTrack.AddDebugMessage("Sending delta to " .. name)
                RaidTrack.SendSyncDataTo(name, knownEP, knownLoot)
            end
        end
    end
end



-- Push only in response to REQ_SYNC
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
        if sendFull and maxEP == 0 and maxLoot == 0 then
    RaidTrack.AddDebugMessage("Skipping full sync to " .. name .. " (both EP/GP and loot are empty)")
    return
end

        payload = {
            full = {
                epgp = RaidTrackDB.epgp,
                loot = RaidTrackDB.lootHistory,
                epgpLog = RaidTrackDB.epgpLog.changes,
                settings = RaidTrackDB.settings or {}
            }
        }

        RaidTrack.pendingSends[name] = {
            meta = { lastEP = maxEP, lastLoot = maxLoot }
        }
-- ✅ Zapisz też stan jako własny (żeby nie wysyłać ponownie tego samego)
RaidTrackDB.syncStates[UnitName("player")] = maxEP
RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
RaidTrack.AddDebugMessage("Preemptively set own sync state: EP=" .. maxEP .. ", Loot=" .. maxLoot)

        RaidTrack.AddDebugMessage("Sending FULL database to " .. name)
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

        RaidTrack.AddDebugMessage("Sending DELTA to " .. name .. " (" .. #epgpDelta .. " EP/GP, " .. #lootDelta .. " loot)")
        -- Preemptively mark that we’ve sent up to this point
local maxEP = knownEP
for _, e in ipairs(epgpDelta) do
    if e.id and e.id > maxEP then maxEP = e.id end
end
RaidTrackDB.syncStates[name] = maxEP
RaidTrackDB.syncStates[UnitName("player")] = maxEP
RaidTrack.AddDebugMessage("Preemptively set own sync state: EP=" .. maxEP .. ", Loot=" .. (RaidTrackDB.lootSyncStates[UnitName("player")] or 0))

-- Preemptively mark that we've sent loot up to this point
local maxLoot = knownLoot
for _, e in ipairs(lootDelta) do
    if e.id and e.id > maxLoot then maxLoot = e.id end
end
RaidTrackDB.lootSyncStates[name] = maxLoot
RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
RaidTrack.AddDebugMessage("Preemptively set own loot sync state: Loot=" .. maxLoot .. ", EP=" .. (RaidTrackDB.syncStates[UnitName("player")] or 0))

    end

    -- Serializacja
    local str = RaidTrack.SafeSerialize(payload)
    local total = math.ceil(#str / CHUNK_SIZE)
    local chunks = {}
    for i = 1, total do
        chunks[i] = str:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
    end

    RaidTrack.pendingSends[name] = RaidTrack.pendingSends[name] or {}
    RaidTrack.pendingSends[name].chunks = chunks

    RaidTrack.AddDebugMessage("PING -> " .. name .. " (" .. total .. " chunks)")
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "PING", "WHISPER", name)

    if sendFull then
        C_Timer.NewTimer(15, function()
            local p = RaidTrack.pendingSends[name]
            if p and not p.gotPong then
                RaidTrack.AddDebugMessage("No PONG from " .. name .. " after 15s, canceling full sync.")
                RaidTrack.pendingSends[name] = nil
            end
        end)
    end
end




function RaidTrack.BroadcastSettings()
    if not RaidTrack.IsOfficer() then return end
    local s = RaidTrackDB.settings
    local payload = {
        settings = {
            minSyncRank = s.minSyncRank,
            officerOnly = s.officerOnly,
            autoSync = s.autoSync
        }
    }
    local msg = RaidTrack.SafeSerialize(payload)
    C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "CFG|" .. msg, "GUILD")
    RaidTrack.AddDebugMessage("Broadcasted settings to guild.")
end



-- Chunk sender
function RaidTrack.SendChunkBatch(name)
    local p = RaidTrack.pendingSends[name]
    if not p or not p.chunks then return end

    local any = false
    for idx, c in ipairs(p.chunks) do
        if c then
            any = true
            C_ChatInfo.SendAddonMessage(
                SYNC_PREFIX,
                string.format("%d|%d|%s", idx, #p.chunks, c),
                "WHISPER",
                name
            )
            RaidTrack.AddDebugMessage(
                string.format("Sent chunk %d/%d to %s", idx, #p.chunks, name)
            )
        end
    end

    if not any then
        if p.timer then p.timer:Cancel() end
        RaidTrack.pendingSends[name] = nil

        -- ✅ Zapisz, że odbiorca ma już te dane
        if p.meta and p.meta.lastEP and p.meta.lastLoot then
     

               -- ✅ DODANE: Zapisz również swój własny stan, żeby nie wysyłać tego ponownie
    RaidTrackDB.syncStates[UnitName("player")]     = p.meta.lastEP
    RaidTrackDB.lootSyncStates[UnitName("player")] = p.meta.lastLoot
    RaidTrack.AddDebugMessage("Updated own sync state after full send to " .. name)


            RaidTrack.AddDebugMessage("Updated own sync state after full send to " .. name)
        end

        RaidTrack.lastSyncTime = time()
        RaidTrack.AddDebugMessage("Sync completed for " .. name)
    end
end


-- Incoming handler
local mf = CreateFrame("Frame")
mf:RegisterEvent("CHAT_MSG_ADDON")
mf:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
    if prefix ~= SYNC_PREFIX or sender == UnitName("player") then return end
    local who = Ambiguate(sender, "none")

    if msg == "PING" then
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, "PONG", "WHISPER", who)
        return
    elseif msg == "PONG" and RaidTrack.pendingSends[who] then
    RaidTrack.AddDebugMessage("Received PONG from " .. who)
    RaidTrack.pendingSends[who].gotPong = true
    RaidTrack.SendChunkBatch(who)

        return
 elseif msg:sub(1,9) == "REQ_SYNC|" then
    local _, epStr, lootStr = strsplit("|", msg)
    local knownEP = tonumber(epStr) or 0
    local knownLoot = tonumber(lootStr) or 0
    RaidTrack.AddDebugMessage("Got REQ_SYNC from " .. who .. " (knownEP=" .. knownEP .. ", knownLoot=" .. knownLoot .. ")")
    RaidTrack.SendSyncDataTo(who, knownEP, knownLoot)

        return
    elseif msg:sub(1,4) == "ACK|" then
        local idx = tonumber(msg:sub(5))
        RaidTrack.AddDebugMessage("Received ACK " .. idx .. " from " .. who)
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
            RaidTrackDB.settings[k] = v
        end
        RaidTrack.AddDebugMessage("Received sync settings from " .. who)
    end
    return

    end

    -- Data chunk
    local i,t,d = msg:match("^(%d+)|(%d+)|(.+)$")
    i,t = tonumber(i), tonumber(t)
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
    if ok and data then
        -- 🔁 FULL SYNC (new player)
        if data.full then
    RaidTrackDB.epgp = data.full.epgp or {}
    RaidTrackDB.lootHistory = data.full.loot or {}

    -- Compute maxLoot based on received lootHistory
    local maxLoot = 0
    for _, e in ipairs(RaidTrackDB.lootHistory or {}) do
        if e.id and e.id > maxLoot then maxLoot = e.id end
    end

    if data.full.settings then
        for k, v in pairs(data.full.settings) do
            RaidTrackDB.settings[k] = v
        end
        RaidTrack.AddDebugMessage("Received sync settings from full sync")
    end

    RaidTrackDB.epgpLog = {
        changes = data.full.epgpLog or {},
        lastId = (data.full.epgpLog[#data.full.epgpLog] and data.full.epgpLog[#data.full.epgpLog].id) or 0
    }

    -- Ustaw stan synchronizacji EPGP
local lastEP = RaidTrackDB.epgpLog.lastId or 0
RaidTrackDB.syncStates[who] = lastEP
RaidTrackDB.syncStates[UnitName("player")] = lastEP
RaidTrack.AddDebugMessage("Set syncStates[" .. UnitName("player") .. "] = " .. lastEP)
RaidTrack.AddDebugMessage("Set syncStates[" .. who .. "] = " .. lastEP)

    RaidTrackDB.lootSyncStates[who] = maxLoot
RaidTrackDB.lootSyncStates[UnitName("player")] = maxLoot
RaidTrack.AddDebugMessage("Set lootSyncStates[" .. UnitName("player") .. "] = " .. maxLoot)
RaidTrack.AddDebugMessage("Set lootSyncStates[" .. who .. "] = " .. maxLoot)


    RaidTrack.AddDebugMessage("Full database received from " .. who)
    RaidTrack.lastSyncTime = time() -- ✅ ustawienie czasu tutaj

    if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
    if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end

    -- 🔁 Retry delta sync after full load ONLY if new data was added
    if RaidTrackDB.syncStates[UnitName("player")] == 0 or RaidTrackDB.lootSyncStates[UnitName("player")] == 0 then
        C_Timer.After(2, function()
            RaidTrack.RequestSyncFromGuild()
        end)
    else
        RaidTrack.AddDebugMessage("No need to re-request after full sync (already up to date).")
    end

    return
end



        -- 🔁 Normal delta merge
        RaidTrack.MergeEPGPChanges(data.epgpDelta)

-- 🔁 After delta received, update sync state
local newLastEP = 0
for _, e in ipairs(data.epgpDelta or {}) do
    if e.id and e.id > newLastEP then
        newLastEP = e.id
    end
end
if newLastEP > 0 then
    RaidTrackDB.syncStates[who] = newLastEP
    RaidTrackDB.syncStates[UnitName("player")] = newLastEP
    RaidTrack.AddDebugMessage("Updated syncStates after delta: " .. newLastEP)
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
if RaidTrack.RefreshLootTab then
    RaidTrack.RefreshLootTab()
end

    end
end

end)  -- tutaj jest to jedyne zamknięcie funkcji i SetScript


-- Clear DB
local function ClearRaidTrackDB()
    if RaidTrackDB then wipe(RaidTrackDB) end
    RaidTrackDB = {
      settings = {},
      epgp = {},
      lootHistory = {},
      epgpLog = { changes = {}, lastId = 0 },
      syncStates = {},
      lootSyncStates = {},
      lastPayloads = {}
    }
    RaidTrack.AddDebugMessage("Database cleared; reload UI.")
end

SLASH_RT_CLEARDATA1 = "/rtcleardb"
SlashCmdList["RT_CLEARDATA"] = ClearRaidTrackDB

-- Alias dla kompatybilności: stare SendSyncData → pull‑sync
function RaidTrack.SendSyncData()
    RaidTrack.RequestSyncFromGuild()
end


local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

local ldbObject = LDB:NewDataObject("RaidTrack", {
    type = "launcher",
    text = "RaidTrack",
    icon = "Interface\\Icons\\inv_misc_groupneedmore", -- Możesz zmienić
    OnClick = function(_, button)
        if RaidTrack.mainFrame:IsShown() then
            RaidTrack.mainFrame:Hide()
        else
            RaidTrack.mainFrame:Show()
            RaidTrack.ShowTab(1)
        end
    end,
    OnTooltipShow = function(tt)
    tt:AddLine("RaidTrack")
    tt:AddLine("Left-click to open/close the addon", 1, 1, 1)

    if RaidTrack.lastSyncTime then
        local elapsed = math.floor(time() - RaidTrack.lastSyncTime)
        local mins = math.floor(elapsed / 60)
        local secs = elapsed % 60
        local timeStr = string.format("%d min %d sec ago", mins, secs)
        tt:AddLine("Last sync: " .. timeStr, 0.8, 0.8, 0.8)
    else
        tt:AddLine("Last sync: Never", 0.8, 0.8, 0.8)
    end
end

})

-- Domyślne ustawienia dla ikony
RaidTrackDB.settings = RaidTrackDB.settings or {}
RaidTrackDB.settings.minimap = RaidTrackDB.settings.minimap or {}

-- Rejestruj ikonę, jeżeli jeszcze nie została zarejestrowana
C_Timer.After(1, function()
    if LDBIcon and not LDBIcon:IsRegistered("RaidTrack") then
        LDBIcon:Register("RaidTrack", ldbObject, RaidTrackDB.settings.minimap)
    end
end)

-- Dodaj funkcję statusu jeśli jeszcze jej nie masz
function RaidTrack.GetSyncStatus()
    local count = RaidTrack.lastDeltaCount or 0
    if count == 0 then
        return "Idle"
    else
        return string.format("Pending (%d events)", count)
    end
end

