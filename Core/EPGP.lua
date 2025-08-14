-- Core/EPGP.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}



-- Log EPGP change
function RaidTrack.LogEPGPChange(player, deltaEP, deltaGP, by)
    if not player or (not deltaEP and not deltaGP) then
        return
    end
    RaidTrackDB.epgpLog.lastId = RaidTrackDB.epgpLog.lastId + 1
    local entry = {
        id = RaidTrackDB.epgpLog.lastId,
        player = player,
        deltaEP = deltaEP or 0,
        deltaGP = deltaGP or 0,
        by = by or UnitName("player"),
        timestamp = time()
    }
    table.insert(RaidTrackDB.epgpLog.changes, entry)
    RaidTrack.ApplyEPGPChange(entry)
    RaidTrack.AddDebugMessage("Logged change: EP=" .. entry.deltaEP .. ", GP=" .. entry.deltaGP .. " to " .. player)
    -- Jeśli zmiana dotyczy mnie – pokaż toast lokalnie
    if entry.player == UnitName("player") then
        if entry.deltaEP and entry.deltaEP ~= 0 then
            RaidTrack:ShowEPGPToast(entry.deltaEP, entry.player, "EP")
        end
        if entry.deltaGP and entry.deltaGP ~= 0 then
            RaidTrack:ShowEPGPToast(entry.deltaGP, entry.player, "GP")
        end
    end

    if RaidTrackDB.settings.autoSync ~= false then
        RaidTrack.ScheduleSync()
    end
end

-- Apply EPGP change locally
-- Core/EPGP.lua
function RaidTrack.ApplyEPGPChange(entry)
    if not entry or not entry.player then
        return
    end

    -- Minimal GP = 1 (również przy pierwszym wpisie)
    local st = RaidTrackDB.epgp[entry.player] or { ep = 0, gp = 1 }

    st.ep = (tonumber(st.ep) or 0) + (tonumber(entry.deltaEP) or 0)
    st.gp = (tonumber(st.gp) or 1) + (tonumber(entry.deltaGP) or 0)

    -- Nigdy poniżej 1
    if st.gp < 1 then
        st.gp = 1
    end

    RaidTrackDB.epgp[entry.player] = st
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
        if e.id == id then
            return true
        end
    end
    return false
end

function RaidTrack.MergeEPGPChanges(incoming)
    -- Zabezpieczenie przed pustą lub błędnie przekazaną wartością
    if type(incoming) ~= "table" then
        RaidTrack.AddDebugMessage("MergeEPGPChanges: incoming is not a table! (" .. tostring(incoming) .. ")")
        return -- Jeśli incoming nie jest tabelą, kończymy funkcję
    end

    -- Debugowanie zawartości danych przed dalszym przetwarzaniem
    RaidTrack.AddDebugMessage("MergeEPGPChanges: incoming is a table, containing: ")
    for k, v in pairs(incoming) do
        -- Dodajemy szczegóły o każdym elemencie, aby sprawdzić, czy to zmiana EPGP
        RaidTrack.AddDebugMessage("  Key: " .. tostring(k) .. ", Value: " .. tostring(v) .. " (type: " .. type(v) .. ")")

        -- Jeśli to zmiana EPGP, powinna zawierać id, gp i epgpChanges (nie może zawierać 'gp' jako ceny przedmiotu)
        if v.gp then
            RaidTrack.AddDebugMessage("Ignoring 'gp' field in EPGP change since it's just an auction price: " ..
                                          tostring(v.gp))
        end
    end

    -- Przetwarzanie zmian EPGP
    table.sort(incoming, function(a, b)
        return a.id < b.id
    end)
    for _, e in ipairs(incoming) do
        -- Tylko zmiany, które mają id, są traktowane jako zmiany EPGP
        if e.id and not RaidTrack.HasEPGPChange(e.id) then
            -- Dodajemy zmiany EPGP do bazy danych
            table.insert(RaidTrackDB.epgpLog.changes, e)
            RaidTrackDB.epgpLog.lastId = math.max(RaidTrackDB.epgpLog.lastId, e.id)
            -- Zastosowanie zmiany EPGP
            RaidTrack.ApplyEPGPChange(e)
            -- Jeśli ta zmiana dotyczy mnie – pokaż lokalny toast
            if e.player == UnitName("player") then
                if e.deltaEP and e.deltaEP ~= 0 then
                    RaidTrack:ShowEPGPToast(e.deltaEP, e.player, "EP")
                end
                if e.deltaGP and e.deltaGP ~= 0 then
                    RaidTrack:ShowEPGPToast(e.deltaGP, e.player, "GP")
                end
            end

        end
    end

    -- Aktualizacja listy EPGP
    if RaidTrack.UpdateEPGPList then
        RaidTrack.UpdateEPGPList()
    end
end

