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

-- Funkcja do pobierania EP, GP i PR z bazy
function GetEPGP(player)
    -- Pobieramy dane EP i GP z bazy (domyślnie 0, jeśli nie ma danych)
    local epgp = RaidTrackDB.epgp[player] or { ep = 0, gp = 0 }
    
    -- Obliczanie PR (Priority Rating) jako EP/GP
    local pr = epgp.gp > 0 and epgp.ep / epgp.gp or 0
    
    return epgp.ep, epgp.gp, pr  -- Zwracamy EP, GP i PR
end

function RaidTrack.AddLootToLog(player, itemID, gp)
    -- Dodajemy przedmiot do logu lootu
    local lootEntry = {
        player = player,
        itemID = itemID,
        gp = gp,
        timestamp = time()  -- Dodajemy znacznik czasu
    }
    table.insert(RaidTrackDB.lootHistory, lootEntry)
    RaidTrack.AddDebugMessage("Loot added for " .. player .. ": ItemID " .. itemID .. " with GP " .. gp)
end

function RaidTrack.AssignPointsToPlayer(player, gp)
    -- Przypisanie punktów GP dla gracza
    local epgp = RaidTrackDB.epgp[player] or { ep = 0, gp = 0 }
    epgp.gp = epgp.gp + gp  -- Dodajemy GP
    RaidTrackDB.epgp[player] = epgp
    RaidTrack.AddDebugMessage("Assigned " .. gp .. " GP to player " .. player)
end
function RaidTrack.GetSelectedItemID()
    -- Zakładając, że masz dostęp do UI przedmiotów
    -- Pobieramy obecnie wybrany przedmiot z UI
    local selectedItem = RaidTrack.auctionParticipantWindow.selectedItem -- Zmienna z wybranym przedmiotem w UI

    if selectedItem then
        return selectedItem.itemID  -- Zwracamy itemID wybranego przedmiotu
    else
        return nil  -- Jeśli nie ma wybranego przedmiotu
    end
end
function RaidTrack.GetEPGP(player)
    -- Zakładam, że posiadasz bazę danych EPGP i chcesz zwrócić EP, GP oraz PR
    -- Pobierz dane z bazy EPGP lub z innej lokalnej struktury danych

    -- Przykład:
    local playerEP, playerGP = 0, 0  -- Inicjalizacja domyślnych wartości EP i GP
    local playerPR = 0               -- Inicjalizacja PR (Priority Rating)
    
    -- Znajdź dane dla gracza w bazie danych
    if RaidTrackDB.epgp[player] then
        playerEP = RaidTrackDB.epgp[player].EP or 0
        playerGP = RaidTrackDB.epgp[player].GP or 0
        playerPR = RaidTrackDB.epgp[player].PR or 0
    end

    -- Zwracamy dane
    return playerEP, playerGP, playerPR
end
function RaidTrack.SendAuctionResponseChunked(auctionID, itemID, choice)
    local from = UnitName("player")

    local payload = {
        auctionID = tostring(auctionID), -- ważne!
        itemID = tonumber(itemID),
        choice = choice,
        from = from
    }

    RaidTrack.QueueAuctionChunkedSend(nil, payload.auctionID, "response", payload)

    -- Zawsze lokalnie przetwarzaj własną odpowiedź
    RaidTrack.AddDebugMessage("Locally handling own response for " .. from)
    C_Timer.After(0.05, function()
        RaidTrack.HandleAuctionResponse(payload.auctionID, payload)
    end)
end



function RaidTrack.IsLeader()
    local playerName = UnitName("player")
    local leaderName = RaidTrack.auction and RaidTrack.auction.leader

    print("[RaidTrack] UnitName:", playerName)
    print("[RaidTrack] Auction Leader:", leaderName)

    return leaderName == playerName
end

function RaidTrack.IsPlayerInMyGuild(name)
    for i = 1, GetNumGuildMembers() do
        local fullName = GetGuildRosterInfo(i)
        if fullName and strsplit("-", fullName) == name then
            return true
        end
    end
    return false
end

function RaidTrack.IsPlayerInMyRaid(name)
    for i = 1, GetNumGroupMembers() do
        local raidName = GetRaidRosterInfo(i)
        if raidName and strsplit("-", raidName) == name then
            return true
        end
    end
    return false
end


function RaidTrack.FindItemInBags(itemID)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id == itemID then
                return bag, slot
            end
        end
    end
    return nil, nil
end

function RaidTrack.ApplyHighlight(row, isSelected)
    if not row or not row.frame then return end

    if not row._highlightTexture then
        local tex = row.frame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        row._highlightTexture = tex
    end

    if isSelected then
        row._highlightTexture:SetColorTexture(0.1, 0.1, 0.3, 0.4)
        row._highlightTexture:Show()
    else
        row._highlightTexture:SetColorTexture(0, 0, 0, 0)
        row._highlightTexture:Hide()
    end
end
