-- Core/Util.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

local AceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
assert(AceSerializer, "AceSerializer-3.0 not found!")

-- Serialization
function RaidTrack.SafeSerialize(tbl)
    return AceSerializer:Serialize(tbl)
end
function RaidTrack.SafeDeserialize(str)
    -- Logowanie przed deserializacją
    RaidTrack.AddDebugMessage("Attempting to deserialize data: " .. tostring(str))

    local ok, payload = AceSerializer:Deserialize(str)

    -- Logowanie w przypadku błędu deserializacji
    if not ok then
        RaidTrack.AddDebugMessage("Deserialize failed: " .. tostring(payload))
        return false, nil
    end

    -- Logowanie po pomyślnej deserializacji
    RaidTrack.AddDebugMessage("Deserialized data successfully: " .. tostring(payload))

    return true, payload
end


-- Debug helper
function RaidTrack.AddDebugMessage(msg)
    print("|cff00ffff[RaidTrack]|r " .. tostring(msg))
    RaidTrack.debugMessages = RaidTrack.debugMessages or {}
    table.insert(RaidTrack.debugMessages, 1, date("%H:%M:%S") .. " - " .. msg)
    if #RaidTrack.debugMessages > 50 then
        table.remove(RaidTrack.debugMessages, #RaidTrack.debugMessages)
    end
end

-- Check if player is officer
function RaidTrack.IsOfficer()
    if not IsInGuild() then return false end
    local myName = UnitName("player")
    for i = 1, GetNumGuildMembers() do
    local name, _, rankIndex = GetGuildRosterInfo(i)
    -- RaidTrack.AddDebugMessage("Roster: " .. tostring(name) .. " rank " .. tostring(rankIndex))
    if name and Ambiguate(name, "none") == myName then
        RaidTrack.AddDebugMessage("Matched player: " .. tostring(name) .. " rank " .. tostring(rankIndex))
        return rankIndex <= (RaidTrackDB.settings.minSyncRank or 1)
    end
end

    print(">> Could not find player in guild roster")
    return false
end


-- Status helper
function RaidTrack.GetSyncStatus()
    local count = RaidTrack.lastDeltaCount or 0
    if count == 0 then
        return "Idle"
    else
        return string.format("Pending (%d events)", count)
    end
end

function RaidTrack.GetSyncTimeAgo()
    if not RaidTrack.lastSyncTime then return "never" end
    local elapsed = time() - RaidTrack.lastSyncTime
    local min = math.floor(elapsed / 60)
    local sec = elapsed % 60
    return string.format("%d min %d sec ago", min, sec)
end
function RaidTrack.DebugTableToString(tbl)
    if type(tbl) ~= "table" then return tostring(tbl) end
    local str = ""
    for k, v in pairs(tbl) do
        str = str .. tostring(k) .. "=" .. tostring(v) .. "; "
    end
    return str
end
