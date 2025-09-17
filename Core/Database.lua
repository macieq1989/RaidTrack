-- Core/Database.lua
local addonName, ns = ...
-- Ujednolicenie przestrzeni nazw
_G.RaidTrack   = _G.RaidTrack or ns or {}
local RaidTrack = _G.RaidTrack

_G.RaidTrackDB = _G.RaidTrackDB or {}
local RaidTrackDB = _G.RaidTrackDB

-- ====== Domyślne struktury (NIE dotykamy _meta / wipeId!) ======
RaidTrackDB.settings        = RaidTrackDB.settings        or {}
RaidTrackDB.epgp            = RaidTrackDB.epgp            or {}
RaidTrackDB.lootHistory     = RaidTrackDB.lootHistory     or {}
RaidTrackDB.epgpLog         = RaidTrackDB.epgpLog         or { changes = {}, lastId = 0 }
RaidTrackDB.syncStates      = RaidTrackDB.syncStates      or {}
RaidTrackDB.lootSyncStates  = RaidTrackDB.lootSyncStates  or {}
RaidTrackDB.lastPayloads    = RaidTrackDB.lastPayloads    or {}
RaidTrackDB.raidHistory     = RaidTrackDB.raidHistory     or {}
RaidTrackDB.raidInstances   = RaidTrackDB.raidInstances   or {}
RaidTrackDB.windowPositions = RaidTrackDB.windowPositions or {}

-- Domyślny próg rangi do synchronizacji (0-based z WoWa; 1 = officer domyślnie)
if RaidTrackDB.settings.minSyncRank == nil then
    RaidTrackDB.settings.minSyncRank = 1
end

-- Domyślny dostęp do zakładek UI (Access Control)
if type(RaidTrackDB.settings.minUITabRankIndex) ~= "number"
   or RaidTrackDB.settings.minUITabRankIndex < 1 then
    RaidTrackDB.settings.minUITabRankIndex = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 10
end

-- Ustawienia minimapy
RaidTrackDB.settings.minimap = RaidTrackDB.settings.minimap or {
    hide = false,
    minimapPos = 220,
}

-- ====== Init po załadowaniu dodatku ======
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end

    -- Upewnij się, że podstawowe tabele istnieją
    RaidTrackDB.settings        = RaidTrackDB.settings        or {}
    RaidTrackDB.epgp            = RaidTrackDB.epgp            or {}
    RaidTrackDB.lootHistory     = RaidTrackDB.lootHistory     or {}
    RaidTrackDB.epgpLog         = RaidTrackDB.epgpLog         or { changes = {}, lastId = 0 }
    RaidTrackDB.syncStates      = RaidTrackDB.syncStates      or {}
    RaidTrackDB.lootSyncStates  = RaidTrackDB.lootSyncStates  or {}
    RaidTrackDB.lastPayloads    = RaidTrackDB.lastPayloads    or {}
    RaidTrackDB.raidHistory     = RaidTrackDB.raidHistory     or {}
    RaidTrackDB.raidInstances   = RaidTrackDB.raidInstances   or {}
    RaidTrackDB.windowPositions = RaidTrackDB.windowPositions or {}

    -- 1) WipeId z WipeId.lua (migracja i sanity)
    if RaidTrack.EnsureWipeId then
        RaidTrack.EnsureWipeId()
    end
    -- 2) Zaktualizuj lustro legacy (epgpWipeID) PO EnsureWipeId
    if RaidTrack.GetWipeId then
        RaidTrackDB.epgpWipeID = tostring(RaidTrack.GetWipeId())
    end

    -- Przywrócenie aktywnego raidu po restarcie/reloadzie (jeśli było zapisane)
    if RaidTrackDB.activeRaidID then
        RaidTrack.activeRaidID = RaidTrackDB.activeRaidID
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("Odtworzono activeRaidID = " .. tostring(RaidTrack.activeRaidID))
        end
        C_Timer.After(1, function()
            if RaidTrack.UpdateRaidTabStatus then
                RaidTrack.UpdateRaidTabStatus()
            end
        end)
    end

    -- Domyślny minSyncRank jeśli nadal brak
    if RaidTrackDB.settings.minSyncRank == nil then
        RaidTrackDB.settings.minSyncRank = 1
        if RaidTrack.AddDebugMessage then
            RaidTrack.AddDebugMessage("Default minSyncRank set to 1")
        end
    end

    -- Auto-broadcast ustawień (oficer)
    if RaidTrack.IsOfficer and RaidTrack.IsOfficer() then
        C_Timer.After(2, function()
            if RaidTrack.BroadcastSettings then
                RaidTrack.BroadcastSettings()
            end
            if RaidTrack.AddDebugMessage then
                RaidTrack.AddDebugMessage("Auto-broadcasted settings on login (officer)")
            end
        end)
    end

    self:UnregisterEvent("ADDON_LOADED")
end)

-- ====== Local clear (nie kasuje _meta.wipeId, NIE wysyła CFG) ======
-- Domyślnie zachowuje settings (żeby „tylko cfg nowe wysyłało” przy global wipe).
-- Możesz wymusić pełen wipe ustawień podając opts.resetSettings = true.
function RaidTrack.ClearRaidTrackDB(opts)
    opts = opts or {}

    local metaBackup = RaidTrackDB and RaidTrackDB._meta
    local settingsBackup = (opts.resetSettings and {}) or (RaidTrackDB.settings or {})

    -- wyczyść wszystkie dane runtime
    RaidTrackDB.epgp            = {}
    RaidTrackDB.lootHistory     = {}
    RaidTrackDB.epgpLog         = { changes = {}, lastId = 0 }
    RaidTrackDB.syncStates      = {}
    RaidTrackDB.lootSyncStates  = {}
    RaidTrackDB.lastPayloads    = {}
    RaidTrackDB.raidHistory     = {}
    RaidTrackDB.raidInstances   = {}
    RaidTrackDB.activeRaidID    = nil

    -- zachowaj ustawienia (lub zresetuj jeśli wymuszone)
    RaidTrackDB.settings        = settingsBackup

    -- przywróć meta + wipeId
    RaidTrackDB._meta = metaBackup or {}
    if RaidTrack.EnsureWipeId then RaidTrack.EnsureWipeId() end
    if RaidTrack.GetWipeId then
        RaidTrackDB.epgpWipeID = tostring(RaidTrack.GetWipeId())
    end

    -- odśwież UI
    if RaidTrack.UpdateEPGPList then RaidTrack.UpdateEPGPList() end
    if RaidTrack.RefreshLootTab then RaidTrack.RefreshLootTab() end
    if RaidTrack.UpdateRaidTabStatus then RaidTrack.UpdateRaidTabStatus() end

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage(
            "Database cleared (local). _meta.wipeId preserved = " ..
            tostring(RaidTrackDB._meta and RaidTrackDB._meta.wipeId) ..
            (opts.resetSettings and "; settings reset" or "; settings preserved")
        )
    end
end

-- ====== Proste logowanie raidu (bez zmian) ======
function RaidTrack.RegisterRaid()
    RaidTrackDB.raidHistory = RaidTrackDB.raidHistory or {}

    local players = {}
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name then table.insert(players, name) end
    end

    table.insert(RaidTrackDB.raidHistory, {
        id        = tostring(time()),
        timestamp = time(),
        players   = players,
        status    = "finished",
    })

    if RaidTrack.RefreshRaidTab then
        RaidTrack.RefreshRaidTab()
    end

    if RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("Raid registered: " .. tostring(#players) .. " players.")
    end
end
