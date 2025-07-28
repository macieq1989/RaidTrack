local addonName, RaidTrack = ...
RaidTrack.debugMessages = RaidTrack.debugMessages or {}

-- Config
local MAX_MESSAGES = 200
local MAX_ARG_LEN = 100

-- Format helper
local function SafeVal(v)
    local t = type(v)
    if t == "table" then
        return "table: " .. tostring(v)
    elseif t == "string" then
        return "\"" .. (v:sub(1, MAX_ARG_LEN)) .. (v:len() > MAX_ARG_LEN and "..." or "") .. "\""
    else
        return tostring(v)
    end
end

-- Add message
function RaidTrack.AddDebugMessage(msg)
    if not RaidTrack.debugMessages then RaidTrack.debugMessages = {} end
    local timestamped = date("%H:%M:%S") .. " - " .. msg

    -- Skip verbose if not enabled
    if msg:match("^→ ") and not (RaidTrackDB.settings and RaidTrackDB.settings.verboseDebug) then
        return
    end

    table.insert(RaidTrack.debugMessages, timestamped)
    if #RaidTrack.debugMessages > MAX_MESSAGES then
        table.remove(RaidTrack.debugMessages, 1)
    end

    -- Auto-update debugEdit if shown
    if RaidTrack.settingsTab and RaidTrack.settingsTab:IsShown() and RaidTrack.debugEdit then
        RaidTrack.debugEdit:SetText(table.concat(RaidTrack.debugMessages, "\n"))
    end
end

function RaidTrack.WrapDebug(fn, fnName)
    return function(...)
        if not RaidTrackDB.settings.debug then
            return fn(...)
        end

        local SafeVal = function(v)
            if type(v) == "number" then return string.format("%.2f", v)
            elseif type(v) == "boolean" then return tostring(v)
            elseif type(v) == "string" then return '"' .. v .. '"'
            elseif type(v) == "table" then return "<table>"
            else return type(v) end
        end

        local args = {}
        if RaidTrackDB.settings.debugVerbose then
            for i = 1, select("#", ...) do
                table.insert(args, SafeVal(select(i, ...)))
            end
        end

        RaidTrack.AddDebugMessage(">> " .. fnName .. (RaidTrackDB.settings.debugVerbose and "(" .. table.concat(args, ", ") .. ")" or ""))

        local t1 = debugprofilestop()
        local ok, result = pcall(fn, ...)
        local t2 = debugprofilestop()

        if ok then
            if RaidTrackDB.settings.debugVerbose then
                RaidTrack.AddDebugMessage("-> " .. fnName .. " returned: " .. SafeVal(result))
            end
        else
            RaidTrack.AddDebugMessage("ERROR: " .. fnName .. " -> " .. tostring(result))
        end

        RaidTrack.AddDebugMessage("TIMER: " .. fnName .. " took " .. string.format("%.2f", t2 - t1) .. "ms")

        return result
    end
end


