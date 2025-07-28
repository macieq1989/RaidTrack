-- Core/EPGP.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- Log EPGP change
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

-- Get EPGP changes since a given ID
function RaidTrack.GetEPGPChangesSince(lastId)
    local res = {}
    for _, e in ipairs(RaidTrackDB.epgpLog.changes) do
        if e.id > lastId then
            table.insert(res, e)
        end
    end
    return res
end

-- Check if an EPGP change with a given ID exists
function RaidTrack.HasEPGPChange(id)
    for _, e in ipairs(RaidTrackDB.epgpLog.changes) do
        if e.id == id then return true end
    end
    return false
end

-- Merge incoming EPGP changes
function RaidTrack.MergeEPGPChanges(incoming)
    table.sort(incoming, function(a, b) return a.id < b.id end)
    for _, e in ipairs(incoming) do
        if e.id and not RaidTrack.HasEPGPChange(e.id) then
            table.insert(RaidTrackDB.epgpLog.changes, e)
            RaidTrackDB.epgpLog.lastId = math.max(RaidTrackDB.epgpLog.lastId, e.id)
            RaidTrack.ApplyEPGPChange(e)
        end
    end
    if RaidTrack.UpdateEPGPList then
        RaidTrack.UpdateEPGPList()
    end
end