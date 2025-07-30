local AceGUI = LibStub("AceGUI-3.0")
local addonPrefix = "RaidTrackAuction"

function RaidTrack.OpenAuctionParticipantUI(auctionData)
    if not auctionData or type(auctionData) ~= "table" or not auctionData.items or #auctionData.items == 0 then
        RaidTrack.AddDebugMessage("Invalid auctionData received by participant UI.")
        return
    end

    RaidTrack.AddDebugMessage("OpenAuctionParticipantUI() called")
    print("==== OpenAuctionParticipantUI CALLED ====")

    -- Najważniejsze: dokładny debug wejścia
    RaidTrack.AddDebugMessage("Opening UI for auctionID: " .. tostring(auctionData.auctionID))
    RaidTrack.AddDebugMessage("Item count: " .. tostring(#auctionData.items))

    if auctionData and auctionData.items then
        RaidTrack.AddDebugMessage("RAW items: " .. (RaidTrack.SafeSerialize(auctionData.items) or "nil"))
    else
        RaidTrack.AddDebugMessage("Brak auctionData lub auctionData.items!")
    end

    -- Standardowe checki
    if not auctionData then
        RaidTrack.AddDebugMessage("auctionData is nil!")
    elseif not auctionData.items then
        RaidTrack.AddDebugMessage("auctionData.items is nil!")
    elseif type(auctionData.items) ~= "table" then
        RaidTrack.AddDebugMessage("auctionData.items is not a table! Got: " .. type(auctionData.items))
    elseif #auctionData.items == 0 then
        RaidTrack.AddDebugMessage("auctionData.items is an empty table!")
    end

    -- Sprawdzanie, czy okno jest już otwarte
    if RaidTrack.auctionParticipantWindow then
        RaidTrack.auctionParticipantWindow:Hide()
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("RaidTrack Auction")
    frame:SetStatusText("Select your response for each item")
    frame:SetLayout("List")
    frame:SetWidth(500)
    frame:SetHeight(400)
    frame:EnableResize(false)
    RaidTrack.auctionParticipantWindow = frame

    -- Pełny debug każdej rzeczy
    for i, item in ipairs(auctionData.items) do
        RaidTrack.AddDebugMessage(string.format("ParticipantUI item %d: id=%s, gp=%s, link=%s", i, tostring(item.itemID), tostring(item.gp), tostring(item.link)))

        local itemGroup = AceGUI:Create("InlineGroup")
        itemGroup:SetFullWidth(true)
        itemGroup:SetLayout("Flow")

        local title = item.link or ("Item ID: " .. tostring(item.itemID or "???"))
        itemGroup:SetTitle(title)

        local gpLabel = AceGUI:Create("Label")
        gpLabel:SetText("GP: " .. tostring(item.gp or "?"))
        gpLabel:SetWidth(60)
        itemGroup:AddChild(gpLabel)

        local function CreateResponseButton(label, responseType)
            local btn = AceGUI:Create("Button")
            btn:SetText(label)
            btn:SetWidth(80)
            btn:SetCallback("OnClick", function()
                RaidTrack.SendAuctionResponseChunked(auctionData.auctionID, item.itemID, responseType)
                btn:SetDisabled(true)
            end)
            return btn
        end

        itemGroup:AddChild(CreateResponseButton("Main Spec", "MS"))
        itemGroup:AddChild(CreateResponseButton("Off Spec", "OS"))
        itemGroup:AddChild(CreateResponseButton("Transmog", "TMOG"))
        itemGroup:AddChild(CreateResponseButton("Pass", "PASS"))

        frame:AddChild(itemGroup)
    end
end
