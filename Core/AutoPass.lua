-- Core/AutoPass.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- ======= CONFIG =======
local DEFAULT_BOSS_LOOT_WINDOW = 120   -- można nadpisać w presecie: cfg.autoPassWindow
local SKIP_RAID_LEADER = true          -- RL nie autopassuje
-- ======================

local function DBG(msg)
    if RaidTrack and RaidTrack.AddDebugMessage then
        RaidTrack.AddDebugMessage("[AutoPass] " .. tostring(msg))
    else
        print("|cff00ffff[RaidTrack]|r [AutoPass] " .. tostring(msg))
    end
end

local function GetCfg()
    return (RaidTrack.GetActiveRaidConfig and RaidTrack.GetActiveRaidConfig()) or RaidTrack.currentRaidConfig
end

local function WithinBossWindow(cfg)
    local window = (cfg and tonumber(cfg.autoPassWindow)) or DEFAULT_BOSS_LOOT_WINDOW
    local last = tonumber(RaidTrack._lastBossKillTime or 0)
    if last <= 0 then return false end
    return (time() - last) <= window
end

local function IsLeaderExcluded()
    if not SKIP_RAID_LEADER then return false end
    return (RaidTrack.IsRaidLeader and RaidTrack.IsRaidLeader()) == true
end

local function ShouldAutoPass()
    if not IsInRaid() then return false, "not in raid" end

    local cfg = GetCfg()
    if not cfg then return false, "no active raid config" end
    if cfg.autoPass == false then return false, "autoPass disabled in preset" end

    if IsLeaderExcluded() then return false, "excluded: raid leader" end
    if not WithinBossWindow(cfg) then return false, "outside boss loot window" end
    return true
end

RaidTrack._autoPassSeen = RaidTrack._autoPassSeen or {}

local function AlreadyProcessed(rollID)
    return rollID and RaidTrack._autoPassSeen[rollID]
end

local function MarkProcessed(rollID)
    if rollID then RaidTrack._autoPassSeen[rollID] = true end
end

local function GetRollInfo(rollID)
    if not rollID or not GetLootRollItemInfo then return false end
    local texture, name, count, quality, bop, canNeed, canGreed, canDE, reasonNeed, reasonGreed, reasonDE =
        GetLootRollItemInfo(rollID)
    return name ~= nil, {
        texture = texture, name = name, count = count, quality = quality, bop = bop,
        canNeed = canNeed, canGreed = canGreed, canDE = canDE,
        reasonNeed = reasonNeed, reasonGreed = reasonGreed, reasonDE = reasonDE
    }
end

local function DoPass(rollID)
    if AlreadyProcessed(rollID) then
        DBG(("already processed rollID=%s"):format(tostring(rollID)))
        return
    end

    local okToPass, why = ShouldAutoPass()
    if not okToPass then
        DBG(("skip rollID=%s (%s)"):format(tostring(rollID), tostring(why)))
        return
    end

    local ok, info = GetRollInfo(rollID)
    if not ok then
        DBG(("no roll info for rollID=%s"):format(tostring(rollID)))
        return
    end

    DBG(("PASS rollID=%s item='%s' q=%s bop=%s need=%s greed=%s de=%s"):
        format(tostring(rollID), tostring(info.name), tostring(info.quality), tostring(info.bop),
               tostring(info.canNeed), tostring(info.canGreed), tostring(info.canDE)))

    if RollOnLoot then
        RollOnLoot(rollID, 0) -- 0 = PASS
        MarkProcessed(rollID)
    else
        DBG("RollOnLoot() API not available on this client")
    end
end

-- ======= EVENTY =======
local f = CreateFrame("Frame")
f:RegisterEvent("START_LOOT_ROLL")

-- Spróbuj zarejestrować Retail/TWW: LOOT_ROLLS_START, ale bez crasha na Classicach
local hasLootRollsStart = false
do
    local ok = pcall(f.RegisterEvent, f, "LOOT_ROLLS_START")
    if ok then
        hasLootRollsStart = true
        DBG("LOOT_ROLLS_START supported; will use Retail flow as well")
    else
        DBG("LOOT_ROLLS_START not available on this client; using START_LOOT_ROLL only")
    end
end

-- Handler
f:SetScript("OnEvent", function(_, event, ...)
    if event == "START_LOOT_ROLL" then
        local rollID = ...
        DoPass(tonumber(rollID))

    elseif event == "LOOT_ROLLS_START" and hasLootRollsStart then
        -- Retail/TWW: przejdź po aktywnych rollach, jeśli API istnieje
        if type(GetActiveLootRollIDs) == "function" then
            local okToPass, why = ShouldAutoPass()
            if not okToPass then
                DBG(("skip LOOT_ROLLS_START (%s)"):format(tostring(why)))
                return
            end
            for _, rollID in ipairs(GetActiveLootRollIDs() or {}) do
                DoPass(rollID)
            end
        else
            DBG("GetActiveLootRollIDs() not available; fallback to START_LOOT_ROLL only")
        end
    end
end)

-- Diagnoza
SLASH_RAIDTRACK_AUTOPASS1 = "/rt_autopass"
SlashCmdList["RAIDTRACK_AUTOPASS"] = function()
    local cfg = GetCfg()
    local flags = {
        cfg   = cfg and "OK" or "nil",
        auto  = cfg and tostring(cfg.autoPass) or "nil",
        raid  = tostring(IsInRaid()),
        leadX = tostring(IsLeaderExcluded()),
        win   = tostring(WithinBossWindow(cfg)),
        lastB = tostring(RaidTrack._lastBossKillTime or "nil"),
        retailEvt = tostring(hasLootRollsStart),
    }
    DBG(("state: cfg=%s auto=%s inRaid=%s leaderExcluded=%s window=%s lastBoss=%s retailEvt=%s")
        :format(flags.cfg, flags.auto, flags.raid, flags.leadX, flags.win, flags.lastB, flags.retailEvt))

    if type(GetActiveLootRollIDs) == "function" then
        local ids = GetActiveLootRollIDs() or {}
        DBG("active rollIDs: " .. (#ids > 0 and table.concat(ids, ", ") or "none"))
    end
end
