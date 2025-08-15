local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}
_G[addonName] = RaidTrack

local f = CreateFrame("Frame", nil, parent)
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, addon)
    if addon ~= "RaidTrack" then return end

    -- Wrap selected functions for debug tracing
    for _, fnName in ipairs({
        "UpdateGuildRoster",
        "SendSyncData",
        "LogEPGPChange",
        "MergeEPGPChanges",
        "BroadcastSettings",
    }) do
        local fn = RaidTrack[fnName]
        if type(fn) == "function" and RaidTrack.WrapDebug then
            RaidTrack[fnName] = RaidTrack.WrapDebug(fn, fnName)
        end
    end
end)
