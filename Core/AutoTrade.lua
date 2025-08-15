local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

-- AutoTrade.lua
local f = CreateFrame("Frame", nil, parent)
f:RegisterEvent("TRADE_SHOW")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")
f:RegisterEvent("TRADE_CLOSED")

RaidTrack.pendingAutoTrades = RaidTrack.pendingAutoTrades or {}

local tradeWasSuccessful = false

local function OnTradeShow()
    local target = UnitName("target")
    if not target then return end

    RaidTrack.AddDebugMessage("TRADE_SHOW with: " .. target)

    -- Szukamy przypisanego itemu do tej osoby
    for auctionID, auction in pairs(RaidTrack.activeAuctions or {}) do
        for _, item in ipairs(auction.items or {}) do
            if item.assignedTo == target and not item._autoTraded then
                local itemLink = item.link or ("item:" .. tostring(item.itemID))
                for bag = 0, NUM_BAG_SLOTS do
                    for slot = 1, C_Container.GetContainerNumSlots(bag) do
                        local id = C_Container.GetContainerItemID(bag, slot)
                        if id == item.itemID then
                            C_Container.UseContainerItem(bag, slot)
                            item._autoTraded = true
                            RaidTrack.pendingAutoTrades[target] = {
                                auctionID = auctionID,
                                itemID = item.itemID,
                                link = itemLink
                            }
                            RaidTrack.AddDebugMessage("Auto-traded item to " .. target .. ": " .. itemLink)
                            return
                        end
                    end
                end
            end
        end
    end
end

local function OnTradeAccepted()
    tradeWasSuccessful = true
    RaidTrack.AddDebugMessage("TRADE_ACCEPT_UPDATE: Trade marked as successful")
end

local function OnTradeClosed()
    local target = UnitName("target")
    RaidTrack.AddDebugMessage("TRADE_CLOSED with: " .. tostring(target))

    if not target then return end

    if tradeWasSuccessful then
        if RaidTrack.pendingAutoTrades[target] then
            RaidTrack.AddDebugMessage("Trade completed, clearing autoTrade entry for " .. target)
            RaidTrack.pendingAutoTrades[target] = nil
        end
    else
        -- Trade nie powiódł się – zresetuj flagę
        for _, auction in pairs(RaidTrack.activeAuctions or {}) do
            for _, item in ipairs(auction.items or {}) do
                if item.assignedTo == target and item._autoTraded then
                    item._autoTraded = false
                    RaidTrack.AddDebugMessage("Trade failed, reset autoTrade flag for: " .. target)
                end
            end
        end
    end

    tradeWasSuccessful = false
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "TRADE_SHOW" then
        OnTradeShow()
    elseif event == "TRADE_ACCEPT_UPDATE" then
        OnTradeAccepted()
    elseif event == "TRADE_CLOSED" then
        OnTradeClosed()
    end
end)
