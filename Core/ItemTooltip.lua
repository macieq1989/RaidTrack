-- Core/ItemTooltip.lua
local addonName, RaidTrack = ...
RaidTrack = RaidTrack or {}

---@class RaidTrackTooltip
---@field Attach fun(frame: Frame, getItemLinkFn: fun(): any, opts?: table)
RaidTrack.Tooltip = RaidTrack.Tooltip or {}
local Tooltip = RaidTrack.Tooltip

-- Utility: try to show tooltip for a given "thing" (link|id|text)
local function ShowItemTooltip(owner, thing, opts)
    if not owner or not GameTooltip then return end

    local anchor = (opts and opts.anchor) or "ANCHOR_RIGHT"
    GameTooltip:SetOwner(owner, anchor)

    local shown = false
    local t = type(thing)

    if t == "number" then
        GameTooltip:SetItemByID(thing)
        shown = true
    elseif t == "string" then
        -- full hyperlink?
        if thing:find("|Hitem:", 1, true) then
            GameTooltip:SetHyperlink(thing)
            shown = true
        else
            -- numeric string?
            local asNum = tonumber(thing)
            if asNum then
                GameTooltip:SetItemByID(asNum)
                shown = true
            end
        end
    end

    if shown then
        GameTooltip:Show()
        -- show compare tooltips if user wants it
        if (IsModifiedClick and IsModifiedClick("COMPAREITEM")) or (GetCVarBool and GetCVarBool("alwaysCompareItems")) then
            GameTooltip_ShowCompareItem(GameTooltip)
        end
    else
        -- fallback: hide if we couldn't resolve anything
        GameTooltip:Hide()
    end
end

local function HideItemTooltip()
    if GameTooltip then GameTooltip:Hide() end
    if ShoppingTooltip1 then ShoppingTooltip1:Hide() end
    if ShoppingTooltip2 then ShoppingTooltip2:Hide() end
end

--- Attach tooltip behavior to any frame.
--- @param frame Frame
--- @param getItemLinkFn fun(): any   -- should return itemLink (string with |Hitem:...), or itemID (number/string)
--- @param opts table|nil             -- { anchor = "ANCHOR_RIGHT" | ... , keepOldHandlers = true|false }
function Tooltip.Attach(frame, getItemLinkFn, opts)
    if not frame or type(getItemLinkFn) ~= "function" then return end
    opts = opts or {}
    local keepOld = (opts.keepOldHandlers ~= false) -- default: true

    -- make sure it can receive mouse
    if frame.EnableMouse then
        frame:EnableMouse(true)
    end

    -- chain existing handlers if any
    local prevEnter = keepOld and frame:GetScript("OnEnter") or nil
    local prevLeave = keepOld and frame:GetScript("OnLeave") or nil

    frame:SetScript("OnEnter", function(self, ...)
        if prevEnter then pcall(prevEnter, self, ...) end
        local thing = getItemLinkFn()
        ShowItemTooltip(self, thing, opts)
    end)

    frame:SetScript("OnLeave", function(self, ...)
        if prevLeave then pcall(prevLeave, self, ...) end
        HideItemTooltip()
    end)
end
