-- Core/AutoPass.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- ======= CONFIG =======
-- Domyślne okno czasu po zabiciu bossa (sekundy) – jeżeli preset nie poda własnego
local DEFAULT_BOSS_LOOT_WINDOW = 120

-- Czy pomijać lidera raidu? (dotychczasowe zachowanie zwykle tak)
local SKIP_RAID_LEADER = true
-- ======================

-- Bezpieczny logger
local function DBG(msg)
    if RaidTrack and RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("[AutoPass] " .. tostring(msg))
    else
        print("|cff00ffff[RaidTrack]|r [AutoPass] " .. tostring(msg))
    end
end

-- Zwraca: cfg (aktywna konfiguracja), powód (gdy brak)
local function GetActiveConfigOrReason()
    local cfg = RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig() or nil
    if not cfg then return nil, "No active raid config" end
    return cfg
end

-- Czy gracz jest RL (i ewentualnie ma być wyłączony z auto-pass)?
local function IsExcludedLeader()
    if not SKIP_RAID_LEADER then return false end
    return (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) == true
end

-- Sprawdza, czy wciąż jesteśmy w oknie czasu po bossie
local function IsWithinBossWindow(cfg)
    local window = (cfg and tonumber(cfg.autoPassWindow)) or DEFAULT_BOSS_LOOT_WINDOW
    local last = tonumber(RaidTrack._lastBossKillTime or 0)
    if last <= 0 then return false end
    return (time() - last) <= window
end

-- Zwroci true/false + „dlaczego”
local function ShouldAutoPass()
    -- 1) aktywna konfiguracja i flaga
    local cfg, reason = GetActiveConfigOrReason()
    if not cfg then return false, reason end
    if cfg.autoPass == false then return false, "autoPass disabled in preset" end

    -- 2) jesteś liderem i mamy wykluczać lidera?
    if IsExcludedLeader() then return false, "excluded: raid leader" end

    -- 3) w raidzie?
    if not IsInRaid() then return false, "not in raid" end

    -- 4) okno czasu po bossie
    if not IsWithinBossWindow(cfg) then return false, "outside boss loot window" end

    return true
end

-- Bezpieczne pobranie informacji o rollu (API różni się między wersjami)
local function GetRollInfo(rollID)
    -- Retail / Classic API dla START_LOOT_ROLL:
    -- name, texture, numNeeded, quality, bindOnPickUp, canNeed, canGreed, canDE, reasonNeed, reasonGreed, reasonDE
    local ok, name, quality, bindOnPickUp = false, nil, nil, nil
    if GetLootRollItemInfo then
        local n, _, _, q, bop = GetLootRollItemInfo(rollID)
        name, quality, bindOnPickUp = n, q, bop
        ok = (name ~= nil)
    end
    return ok, name, quality, bindOnPickUp
end

-- Aby nie wysyłać Pass dwa razy
RaidTrack._autoPassSeen = RaidTrack._autoPassSeen or {}

local function AlreadyProcessed(rollID)
    return RaidTrack._autoPassSeen[rollID] == true
end

local function MarkProcessed(rollID)
    RaidTrack._autoPassSeen[rollID] = true
end

-- Główny handler
local f = CreateFrame("Frame")
f:RegisterEvent("START_LOOT_ROLL")
f:SetScript("OnEvent", function(_, event, rollID, rollTime)
    if event ~= "START_LOOT_ROLL" then return end
    rollID = tonumber(rollID)
    if not rollID then return end

    -- Diagnoza: dlaczego by się nie wykonało
    local okToPass, why = ShouldAutoPass()
    if not okToPass then
        DBG(("skip rollID=%s (%s)"):format(tostring(rollID), tostring(why)))
        return
    end

    if AlreadyProcessed(rollID) then
        DBG(("already processed rollID=%s"):format(tostring(rollID)))
        return
    end

    local ok, name, quality, bop = GetRollInfo(rollID)
    if not ok then
        DBG(("no roll info for rollID=%s"):format(tostring(rollID)))
        return
    end

    -- Opcjonalne filtry – na razie nie blokujemy po jakości, bopie itp.
    DBG(("PASS rollID=%s item='%s' q=%s bop=%s"):format(tostring(rollID), tostring(name), tostring(quality), tostring(bop)))

    -- Sam PASS
    if RollOnLoot then
        RollOnLoot(rollID, 0) -- 0 = PASS
        MarkProcessed(rollID)
    else
        DBG("RollOnLoot() API not available on this client")
    end
end)

-- Dodatkowa pomoc diagnostyczna: komenda do sprawdzenia bieżącego stanu
SLASH_RAIDTRACK_AUTOPASS1 = "/rt_autopass"
SlashCmdList["RAIDTRACK_AUTOPASS"] = function()
    local cfg, reason = GetActiveConfigOrReason()
    local flags = {
        cfg = cfg and "OK" or ("nil (" .. tostring(reason) .. ")"),
        inRaid = tostring(IsInRaid()),
        leaderExcluded = tostring(IsExcludedLeader()),
        window = tostring(IsWithinBossWindow(cfg)),
        lastBoss = tostring(RaidTrack._lastBossKillTime or "nil"),
    }
    DBG(("state: cfg=%s inRaid=%s leaderExcluded=%s window=%s lastBoss=%s")
        :format(flags.cfg, flags.inRaid, flags.leaderExcluded, flags.window, flags.lastBoss))
end
