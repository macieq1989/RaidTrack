local AceGUI = LibStub("AceGUI-3.0")
local addonPrefix = "RaidTrackAuction"



function RaidTrack.OpenAuctionParticipantUI(auctionData)
    if not auctionData or type(auctionData) ~= "table" or not auctionData.items or #auctionData.items == 0 then
        RaidTrack.AddDebugMessage("Invalid auctionData received by participant UI.")
        return
    end

    RaidTrack.AddDebugMessage("OpenAuctionParticipantUI() called")
    print("==== OpenAuctionParticipantUI CALLED ====")

    -- Sprawdzamy, czy okno jest już otwarte
    if RaidTrack.auctionParticipantWindow then
        RaidTrack.auctionParticipantWindow:Hide()
    end

    -- Tworzymy okno dla uczestnika aukcji
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("RaidTrack Auction")
    frame:SetStatusText("Select your response for each item")
    frame:SetLayout("List")
    frame:SetWidth(500)
    frame:SetHeight(400)
    frame:EnableResize(false)
    RaidTrack.auctionParticipantWindow = frame

    -- Ustawiamy pozycję okna na prawą stronę ekranu
    frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -200)

    -- Tworzymy ScrollFrame, by dodać suwak
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    frame:AddChild(scroll)

    -- Liczymy ilość przedmiotów
    local itemCount = #auctionData.items
    local maxVisibleItems = 5  -- Limit widocznych przedmiotów
    local itemHeight = 80      -- Wysokość pojedynczego przedmiotu (dostosuj do rzeczywistego rozmiaru)
    local scrollHeight = math.min(itemCount, maxVisibleItems) * itemHeight
    frame:SetHeight(scrollHeight + 80)  -- +80 dla paddingu lub miejsca na przyciski

    -- Iteracja przez przedmioty w aukcji
    for i, item in ipairs(auctionData.items) do
        RaidTrack.AddDebugMessage(string.format("ParticipantUI item %d: id=%s, gp=%s, link=%s", i,
            tostring(item.itemID), tostring(item.gp), tostring(item.link)))

        local itemGroup = AceGUI:Create("InlineGroup")
        itemGroup:SetFullWidth(true)
        itemGroup:SetLayout("Flow")

        local title = item.link or ("Item ID: " .. tostring(item.itemID or "???"))
        itemGroup:SetTitle(title)

        local gpLabel = AceGUI:Create("Label")
        gpLabel:SetText("GP: " .. tostring(item.gp or "?"))
        gpLabel:SetWidth(60)
        itemGroup:AddChild(gpLabel)

        -- Funkcja do tworzenia przycisków odpowiedzi
        local function CreateResponseButton(label, responseType)
            local btn = AceGUI:Create("Button")
            btn:SetText(label)
            btn:SetWidth(80)
            btn:SetCallback("OnClick", function()
                -- Sprawdzanie, czy gracz to lider aukcji
                local isLeader = UnitName("player") == auctionData.leader
                local ep, gp, pr = RaidTrack.GetEPGP(UnitName("player"))

                -- Tworzymy tabelę z odpowiedzią
                local responseData = {
                    player = UnitName("player"),
                    response = responseType,
                    ep = ep,
                    gp = gp,
                    pr = pr
                }

                -- Dodajemy odpowiedź do przedmiotu aukcji
                if not item.responses then
                    item.responses = {} -- Inicjalizujemy odpowiedzi, jeśli jeszcze nie istnieją
                end

                -- Zawsze dodajemy odpowiedź, nawet jeśli to lider
                item.responses[UnitName("player")] = responseData

                -- Jeśli lider aukcji, nie wyłączamy przycisku
                if isLeader then
                    btn:SetDisabled(false)
                else
                    btn:SetDisabled(true)
                end

                -- Wysyłamy odpowiedź do lidera aukcji
                RaidTrack.SendAuctionResponseChunked(auctionData.auctionID, item.itemID, responseType)
            end)
            return btn
        end

        -- Dodanie przycisków wyboru odpowiedzi
        itemGroup:AddChild(CreateResponseButton("Main Spec", "MS"))
        itemGroup:AddChild(CreateResponseButton("Off Spec", "OS"))
        itemGroup:AddChild(CreateResponseButton("Transmog", "TMOG"))
        itemGroup:AddChild(CreateResponseButton("Pass", "PASS"))

        -- Dodanie przedmiotu do okna aukcji
        scroll:AddChild(itemGroup)
    end
end





