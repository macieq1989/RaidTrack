-- Core/Database.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- Default database setup
RaidTrackDB = RaidTrackDB or {}
RaidTrackDB.settings = RaidTrackDB.settings or {}
RaidTrackDB.epgp = RaidTrackDB.epgp or {}
RaidTrackDB.lootHistory = RaidTrackDB.lootHistory or {}
RaidTrackDB.epgpLog = RaidTrackDB.epgpLog or { changes = {}, lastId = 0 }
RaidTrackDB.syncStates = RaidTrackDB.syncStates or {}
RaidTrackDB.lootSyncStates = RaidTrackDB.lootSyncStates or {}
RaidTrackDB.settings.minSyncRank = RaidTrackDB.settings.minSyncRank or 1
-- Presety i instancje raidu (jeśli nie istnieją, zainicjuj)
RaidTrackDB.raidPresets   = RaidTrackDB.raidPresets   or {}
RaidTrackDB.raidInstances = RaidTrackDB.raidInstances or {}

-- Tombstony dla jawnych usunięć (lokalne buforowanie tego, co trzeba rozesłać)
RaidTrackDB._presetTombstones   = RaidTrackDB._presetTombstones   or {}
RaidTrackDB._instanceTombstones = RaidTrackDB._instanceTombstones or {}


-- Default minimum UI tab access rank (Access Control)
if type(RaidTrackDB.settings.minUITabRankIndex) ~= "number"
   or RaidTrackDB.settings.minUITabRankIndex < 1 then
    RaidTrackDB.settings.minUITabRankIndex = GuildControlGetNumRanks() or 10
end

RaidTrackDB.settings.minimap = RaidTrackDB.settings.minimap or {
    hide = false,
    minimapPos = 220, -- default minimap position angle
}
RaidTrackDB.epgpWipeID = RaidTrackDB.epgpWipeID or tostring(time()..math.random(10000,99999))







-- Initialize DB on ADDON_LOADED
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end

    -- TWARDY INIT STRUKTUR
    RaidTrackDB.settings         = RaidTrackDB.settings         or {}
    RaidTrackDB.epgp             = RaidTrackDB.epgp             or {}
    RaidTrackDB.lootHistory      = RaidTrackDB.lootHistory      or {}
    RaidTrackDB.epgpLog          = RaidTrackDB.epgpLog          or { changes = {}, lastId = 0 }
    RaidTrackDB.syncStates       = RaidTrackDB.syncStates       or {}
    RaidTrackDB.lootSyncStates   = RaidTrackDB.lootSyncStates   or {}
    RaidTrackDB.lastPayloads     = RaidTrackDB.lastPayloads     or {}
    RaidTrackDB.raidPresets      = RaidTrackDB.raidPresets      or {}
    RaidTrackDB.raidInstances    = RaidTrackDB.raidInstances    or {}
    RaidTrackDB._presetTombstones   = RaidTrackDB._presetTombstones   or {}
    RaidTrackDB._instanceTombstones = RaidTrackDB._instanceTombstones or {}

    -- minSyncRank default
    if RaidTrackDB.settings.minSyncRank == nil then
        RaidTrackDB.settings.minSyncRank = 1
        if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Default minSyncRank set to 1") end
    end

    -- Odtworzenie activeRaidID po reloadzie
    if RaidTrackDB.activeRaidID then
        RaidTrack.activeRaidID = RaidTrackDB.activeRaidID
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("Odtworzono activeRaidID = " .. tostring(RaidTrack.activeRaidID))
        end
        C_Timer.After(1, function()
            if RaidTrack.UpdateRaidTabStatus then pcall(RaidTrack.UpdateRaidTabStatus) end
        end)
    end

    -- Auto-broadcast settings (tylko jeśli funkcje istnieją i gracz ma uprawnienia)
    C_Timer.After(2, function()
        if RaidTrack.IsOfficer and RaidTrack.IsOfficer() and RaidTrack.BroadcastSettings then
            pcall(RaidTrack.BroadcastSettings)
            if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Auto-broadcasted settings on login (officer)") end
        end
    end)

    self:UnregisterEvent("ADDON_LOADED")
end)


-- Clear DB helper
function RaidTrack.ClearRaidTrackDB()
    if RaidTrackDB then wipe(RaidTrackDB) end
    RaidTrackDB = {
        settings         = {},
        epgp             = {},
        lootHistory      = {},
        epgpLog          = { changes = {}, lastId = 0 },
        syncStates       = {},
        lootSyncStates   = {},
        lastPayloads     = {},
        -- KONIECZNIE zachowaj struktury sync raidu/presetów:
        raidPresets      = {},
        raidInstances    = {},
        _presetTombstones   = {},
        _instanceTombstones = {},
    }
    if RaidTrack.AddDebugMessage then RaidTrack.AddDebugMessage("Database cleared; reload UI.") end
end





function RaidTrack.RegisterRaid()
    RaidTrackDB.raidHistory = RaidTrackDB.raidHistory or {}

    local players = {}
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then table.insert(players, name) end
    end

    table.insert(RaidTrackDB.raidHistory, {
        timestamp = time(),
        players = players,
    })

    if RaidTrack.RefreshRaidTab then
        RaidTrack.RefreshRaidTab()
    end

    RaidTrack.AddDebugMessage("Raid registered: " .. tostring(#players) .. " players.")
end
