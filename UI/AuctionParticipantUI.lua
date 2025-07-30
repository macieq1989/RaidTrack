local AceGUI = LibStub("AceGUI-3.0")
local addonPrefix = "RaidTrackAuction"

function RaidTrack:OpenAuctionParticipantUI(auctionData)
    RaidTrack.AddDebugMessage("OpenAuctionParticipantUI() called")
    print("==== OpenAuctionParticipantUI CALLED ====")

    -- Najważniejsze: dokładny debug wejścia
    RaidTrack.AddDebugMessage("RAW auctionData: " .. (RaidTrack.SafeSerialize(auctionData) or "nil"))
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

    -- Jeżeli brak danych aukcji lub przedmiotów
    if not auctionData or not auctionData.items or type(auctionData.items) ~= "table" or #auctionData.items == 0 then
        print("RaidTrack: Invalid auction data received by participant UI.")
        return
    end

    -- Sprawdzanie, czy okno jest już otwarte
    if self.auctionParticipantWindow then
        self.auctionParticipantWindow:Hide()  -- Ukrywamy poprzednie okno, jeśli jest otwarte
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("RaidTrack Auction")
    frame:SetStatusText("Select your response for each item")
    frame:SetLayout("List")
    frame:SetWidth(500)
    frame:SetHeight(400)
    frame:EnableResize(false)
    self.auctionParticipantWindow = frame

    -- Pełny debug każdej rzeczy
    for i, item in ipairs(auctionData.items) do
        RaidTrack.AddDebugMessage(string.format("ParticipantUI item %d: id=%s, gp=%s, link=%s", i, tostring(item.itemID), tostring(item.gp), tostring(item.link)))

        local itemGroup = AceGUI:Create("InlineGroup")
        itemGroup:SetFullWidth(true)
        itemGroup:SetLayout("Flow")

        -- Fallback title
        local title = item.link or ("Item ID: " .. tostring(item.itemID or "???"))
        itemGroup:SetTitle(title)

        local gpLabel = AceGUI:Create("Label")
        gpLabel:SetText("GP: " .. tostring(item.gp or "?"))
        gpLabel:SetWidth(60)
        itemGroup:AddChild(gpLabel)

        -- Funkcja tworząca przycisk do odpowiedzi
        local function CreateResponseButton(label, responseType)
            local btn = AceGUI:Create("Button")
            btn:SetText(label)
            btn:SetWidth(80)
            btn:SetCallback("OnClick", function()
                RaidTrack.SendAuctionResponseChunked(auctionData.auctionID, item.itemID, responseType)

                -- Zablokowanie przycisku po kliknięciu
                btn:SetDisabled(true)
            end)
            return btn
        end

        -- Dodawanie przycisków do odpowiedzi
        itemGroup:AddChild(CreateResponseButton("Main Spec", "MS"))
        itemGroup:AddChild(CreateResponseButton("Off Spec", "OS"))
        itemGroup:AddChild(CreateResponseButton("Transmog", "TMOG"))
        itemGroup:AddChild(CreateResponseButton("Pass", "PASS"))

        frame:AddChild(itemGroup)
    end
end
