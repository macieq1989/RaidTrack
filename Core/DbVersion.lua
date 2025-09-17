-- Core/DbVersion.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
RaidTrackDB = RaidTrackDB or {}

local DBVER_PREFIX = "RTDBVER"
local SYNC_PREFIX  = "RaidTrackSync"

if not C_ChatInfo.IsAddonMessagePrefixRegistered(DBVER_PREFIX) then
    C_ChatInfo.RegisterAddonMessagePrefix(DBVER_PREFIX)
end
if not C_ChatInfo.IsAddonMessagePrefixRegistered(SYNC_PREFIX) then
    C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)
end

RaidTrack._dbver = RaidTrack._dbver or {
    byPlayer = {},           -- [name] = { id, legacy, src, ts, prio }
    lastReq  = {},
    lastGuildSweep = 0,
}
RaidTrack._dbverChunks = RaidTrack._dbverChunks or {}

local function now() return time() end
local function me() return Ambiguate(UnitName("player"), "none") end

local function CurWipe()
    if RaidTrack.GetWipeId then
        return tonumber(RaidTrack.GetWipeId()) or 0
    end
    return tonumber(RaidTrackDB and RaidTrackDB._meta and RaidTrackDB._meta.wipeId) or 0
end

local function AcceptLegacy()
    RaidTrackDB.settings = RaidTrackDB.settings or {}
    if RaidTrackDB.settings.acceptLegacyDbVer == nil then
        RaidTrackDB.settings.acceptLegacyDbVer = true
    end
    return RaidTrackDB.settings.acceptLegacyDbVer
end

-- ---------- Priorytety źródeł (anti-downgrade) ----------
local PRIORITY = {
    ["ANN"]        = 3,
    ["CFG"]        = 2,       -- (na wypadek lokalnego użycia)
    ["SYNC-CFG"]   = 2,
    ["SYNC-FULL"]  = 2,
    ["SYNC-DELTA"] = 1,
    ["SYNC-LEGACY"]= 1,
    ["LEGACY"]     = 1,
    ["UNK"]        = 1,
}

local function src_prio(src) return PRIORITY[src or "UNK"] or 1 end

-- ================== API ==================

function RaidTrack.GetClientWipeStatus(name)
    name = name and Ambiguate(name, "none")
    if not name or name == "" then
        return "-", { r=0.7, g=0.7, b=0.7 }
    end

    if name == me() then
        return tostring(CurWipe()), { r=0.2, g=0.9, b=0.2 }
    end

    local entry = RaidTrack._dbver.byPlayer[name]
    if not entry or entry.id == nil then
        return "-", { r=0.7, g=0.7, b=0.7 }
    end

    if entry.legacy then
        if (entry.id or 0) > 1e12 then
            return "LEGACY", { r=0.9, g=0.7, b=0.2 }
        else
            return tostring(entry.id) .. " L", { r=0.9, g=0.7, b=0.2 }
        end
    end

    local mine = CurWipe()
    local peer = tonumber(entry.id) or 0
    local text = tostring(peer)

    if peer == mine then
        return text, { r=0.2, g=0.9, b=0.2 }
    elseif peer > mine then
        return text, { r=1.0, g=0.7, b=0.2 }
    else
        return text, { r=1.0, g=0.3, b=0.3 }
    end
end

function RaidTrack.ProbeClientWipe(name)
    name = name and Ambiguate(name, "none")
    if not name or name == "" or name == me() then return end
    local t = RaidTrack._dbver.lastReq[name] or 0
    if (now() - t) < 8 then return end
    RaidTrack._dbver.lastReq[name] = now()
    C_ChatInfo.SendAddonMessage(DBVER_PREFIX, "REQ", "WHISPER", name)
end

function RaidTrack.SendMyDbVersion()
    local id = CurWipe()
    C_ChatInfo.SendAddonMessage(DBVER_PREFIX, ("ANN|%d"):format(id), "GUILD")
    RaidTrack._dbver.byPlayer[me()] = { id = id, ts = now(), legacy = false, src = "ANN", prio = src_prio("ANN") }
    if RaidTrack.RefreshGuildTab then RaidTrack.RefreshGuildTab() end
end

function RaidTrack.RequestDbSweep()
    if (now() - (RaidTrack._dbver.lastGuildSweep or 0)) < 10 then return end
    RaidTrack._dbver.lastGuildSweep = now()
    C_ChatInfo.SendAddonMessage(DBVER_PREFIX, "REQ", "GUILD")
end

-- --- ANTY-DEGRADACJA: nie nadpisuj lepszego gorszym ---
function RaidTrack.SetPeerDbVersion(name, id, source)
    name = name and Ambiguate(name, "none")
    if not name or name == "" then return end

    local num         = tonumber(id) or 0
    local isHuge      = (num > 1e12)                        -- „chore” floatowe wartości
    local isLegacySrc = (type(source)=="string" and source:find("LEGACY")) and true or false
    local newLegacy   = isLegacySrc or isHuge or (source == "SYNC-DELTA")

    local newSrc  = source or (newLegacy and "SYNC-LEGACY" or "UNK")
    local newPrio = src_prio(newSrc)

    local cur = RaidTrack._dbver.byPlayer[name]
    if cur then
        local curPrio = tonumber(cur.prio) or src_prio(cur.src)
        -- 1) niższy priorytet → ignoruj
        if newPrio < curPrio then return end
        -- 2) ten sam priorytet, ale legacy próbuje nadpisać non-legacy → ignoruj
        if newPrio == curPrio and newLegacy and not cur.legacy then return end
    end

    RaidTrack._dbver.byPlayer[name] = {
        id = num,
        ts = now(),
        legacy = newLegacy and true or false,
        src = newSrc,
        prio = newPrio,
    }

    if RaidTrack.AddDebugMessage then
        local tag = (newLegacy and " L") or ""
        RaidTrack.AddDebugMessage(("DB ver from %s = %s%s (%s)"):format(
            tostring(name), tostring(num), tag, tostring(newSrc)))
    end

    if RaidTrack.RefreshGuildTab then RaidTrack.RefreshGuildTab() end
end

-- ================== RTDBVER (ping/pong) ==================
local verF = RaidTrack._dbverFrame or CreateFrame("Frame")
RaidTrack._dbverFrame = verF
verF:RegisterEvent("CHAT_MSG_ADDON")
verF:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
    sender = sender and Ambiguate(sender, "none")
    if prefix ~= DBVER_PREFIX or not sender or sender == me() then return end

    if msg == "REQ" then
        C_ChatInfo.SendAddonMessage(DBVER_PREFIX, ("ANN|%d"):format(CurWipe()), "WHISPER", sender)
        return
    end

    local idStr = msg:match("^ANN|(%-?%d+)$")
    if idStr then
        RaidTrack.SetPeerDbVersion(sender, tonumber(idStr) or 0, "ANN")
    end
end)

-- ================== Auto announce on login ==================
local lf = RaidTrack._dbverLoginFrame or CreateFrame("Frame")
RaidTrack._dbverLoginFrame = lf
lf:RegisterEvent("PLAYER_LOGIN")
lf:SetScript("OnEvent", function()
    C_Timer.After(3, function() if IsInGuild() then RaidTrack.SendMyDbVersion() end end)
end)

-- ================== Legacy SYNC listener ==================
local legacyF = RaidTrack._dbverLegacyFrame or CreateFrame("Frame")
RaidTrack._dbverLegacyFrame = legacyF
legacyF:RegisterEvent("CHAT_MSG_ADDON")
legacyF:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
    if not AcceptLegacy() then return end
    if prefix ~= SYNC_PREFIX then return end
    sender = sender and Ambiguate(sender, "none")
    if not sender or sender == me() then return end

    -- CFG
    if msg:sub(1,4) == "CFG|" then
        local payload = msg:sub(5)
        local ok, data = RaidTrack.SafeDeserialize and RaidTrack.SafeDeserialize(payload)
        if ok and data and tonumber(data.epgpWipeID or 0) then
            RaidTrack.SetPeerDbVersion(sender, tonumber(data.epgpWipeID) or 0, "SYNC-CFG")
        else
            -- fallback regex parse (stare AceSerializer ciągi)
            local num = payload:match("epgpWipeID%^N(%d+)")
            if num then
                RaidTrack.SetPeerDbVersion(sender, tonumber(num), "SYNC-LEGACY")
            end
        end
        return
    end

    -- FULL/DELTA chunks
    local i, t, d = msg:match("^(%d+)|(%d+)|(.+)$")
    i, t = tonumber(i), tonumber(t)
    if not (i and t and d) then return end

    local B = RaidTrack._dbverChunks[sender]
    if not B then
        B = { total = t, got = 0, chunks = {} }
        RaidTrack._dbverChunks[sender] = B
    end
    if not B.chunks[i] then
        B.chunks[i] = d
        B.got = B.got + 1
    end
    if B.got == B.total then
        local full = table.concat(B.chunks)
        RaidTrack._dbverChunks[sender] = nil

        local ok, data = RaidTrack.SafeDeserialize and RaidTrack.SafeDeserialize(full)
        local id, source

        if ok and data then
            if data.full and tonumber(data.full.epgpWipeID or 0) then
                id = tonumber(data.full.epgpWipeID) or 0
                source = "SYNC-FULL"
            elseif tonumber(data.epgpWipeID or 0) then
                id = tonumber(data.epgpWipeID) or 0
                source = "SYNC-DELTA"
            end
        end

        -- fallback legacy parse (AceSerializer-2.x w stringu)
        if not id then
            local num = full:match("epgpWipeID%^N(%d+)")
            if num then
                id = tonumber(num)
                source = "SYNC-LEGACY"
            else
                local big = full:match("epgpWipeID%^F(%d+)")
                if big then
                    id = tonumber(big)
                    source = "SYNC-LEGACY"
                end
            end
        end

        if id then
            RaidTrack.SetPeerDbVersion(sender, id, source or "SYNC-LEGACY")
        elseif RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("[DBVER] FULL/DELTA deserialize FAILED or empty payload")
        end
    end
end)
