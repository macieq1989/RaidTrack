-- UI/RaidConfigUI.lua
local addonName, RaidTrack = ...
local AceGUI = LibStub("AceGUI-3.0")

function RaidTrack:OpenRaidConfigWindow()
    if self.raidConfigWindow then
        self.raidConfigWindow:Show()
        return
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Raid Configuration")
    frame:SetStatusText("Configure raid settings")
    frame:SetLayout("List")
    frame:SetWidth(400)
    frame:SetHeight(500)
    frame:EnableResize(false)
    self.raidConfigWindow = frame

    local config = {
        autoPass = true,
        lootMode = "auction",
        awardEP = {
            onTime = 5,
            bossKill = 10,
            fullAttendance = 15
        },
        requirements = {
            flask = true,
            enchants = true
        }
    }

    -- Auto-pass
    local autoPass = AceGUI:Create("CheckBox")
    autoPass:SetLabel("Auto-Pass for all players (except leader)")
    autoPass:SetValue(config.autoPass)
    autoPass:SetCallback("OnValueChanged", function(_, _, val)
        config.autoPass = val
    end)
    frame:AddChild(autoPass)

    -- Loot Mode
    local lootMode = AceGUI:Create("Dropdown")
    lootMode:SetLabel("Loot Mode")
    lootMode:SetList({
        manual = "Manual",
        auction = "Auction",
        softres = "Soft-reserve"
    })
    lootMode:SetValue(config.lootMode)
    lootMode:SetCallback("OnValueChanged", function(_, _, val)
        config.lootMode = val
    end)
    frame:AddChild(lootMode)

    -- EP values
    local epOnTime = AceGUI:Create("EditBox")
    epOnTime:SetLabel("EP: On Time Bonus")
    epOnTime:SetText(tostring(config.awardEP.onTime))
    epOnTime:SetCallback("OnTextChanged", function(_, _, val)
        config.awardEP.onTime = tonumber(val) or 0
    end)
    frame:AddChild(epOnTime)

    local epBossKill = AceGUI:Create("EditBox")
    epBossKill:SetLabel("EP: Per Boss Kill")
    epBossKill:SetText(tostring(config.awardEP.bossKill))
    epBossKill:SetCallback("OnTextChanged", function(_, _, val)
        config.awardEP.bossKill = tonumber(val) or 0
    end)
    frame:AddChild(epBossKill)

    local epFull = AceGUI:Create("EditBox")
    epFull:SetLabel("EP: Full Attendance")
    epFull:SetText(tostring(config.awardEP.fullAttendance))
    epFull:SetCallback("OnTextChanged", function(_, _, val)
        config.awardEP.fullAttendance = tonumber(val) or 0
    end)
    frame:AddChild(epFull)

    -- Requirements
    local reqFlask = AceGUI:Create("CheckBox")
    reqFlask:SetLabel("Require Flask")
    reqFlask:SetValue(config.requirements.flask)
    reqFlask:SetCallback("OnValueChanged", function(_, _, val)
        config.requirements.flask = val
    end)
    frame:AddChild(reqFlask)

    local reqEnchants = AceGUI:Create("CheckBox")
    reqEnchants:SetLabel("Require Enchants")
    reqEnchants:SetValue(config.requirements.enchants)
    reqEnchants:SetCallback("OnValueChanged", function(_, _, val)
        config.requirements.enchants = val
    end)
    frame:AddChild(reqEnchants)

    -- Save as preset
    local presetInput = AceGUI:Create("EditBox")
    presetInput:SetLabel("Save as Preset (name)")
    presetInput:SetText("")
    frame:AddChild(presetInput)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save Preset")
   saveBtn:SetCallback("OnClick", function()
    local name = presetInput:GetText()
    if name and name ~= "" then
        RaidTrack.SaveRaidPreset(name, config)

        -- 🔄 odśwież dropdown w RaidTab, jeśli istnieje
        if RaidTrack.raidPresetDropdown and RaidTrack.raidPresetDropdown.SetList then
            local presets = RaidTrack.GetRaidPresets()
            local values = {}
            for n in pairs(presets) do
                values[n] = n
            end
            RaidTrack.raidPresetDropdown:SetList(values)
        end
    end
end)

    frame:AddChild(saveBtn)

    -- Confirm
    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Confirm")
    confirmBtn:SetFullWidth(true)
    confirmBtn:SetCallback("OnClick", function()
        RaidTrack.currentRaidConfig = config
        RaidTrack.AddDebugMessage("Current raid config confirmed.")
        frame:Hide()
    end)
    frame:AddChild(confirmBtn)
end
