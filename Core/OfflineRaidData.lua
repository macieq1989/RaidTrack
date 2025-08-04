-- Core/OfflineRaidData.lua

local RaidTrack = RaidTrack or {}

-- Struktura offline'owej bazy raidów i bossów
RaidTrack.OfflineRaidData = {
    {
        expansionID = 1,
        name = "Classic",
        instances = {
            {
                id = 409,
                name = "Molten Core",
                bosses = {
                    { id = 663, name = "Lucifron" },
                    { id = 664, name = "Magmadar" },
                    { id = 665, name = "Gehennas" },
                    { id = 666, name = "Garr" },
                    { id = 667, name = "Baron Geddon" },
                    { id = 668, name = "Shazzrah" },
                    { id = 669, name = "Sulfuron Harbinger" },
                    { id = 670, name = "Golemagg the Incinerator" },
                    { id = 671, name = "Majordomo Executus" },
                    { id = 672, name = "Ragnaros" },
                }
            },
            {
                id = 249,
                name = "Onyxia's Lair",
                bosses = {
                    { id = 10184, name = "Onyxia" },
                }
            },
            {
                id = 469,
                name = "Blackwing Lair",
                bosses = {
                    { id = 610, name = "Razorgore the Untamed" },
                    { id = 611, name = "Vaelastrasz the Corrupt" },
                    { id = 612, name = "Broodlord Lashlayer" },
                    { id = 613, name = "Firemaw" },
                    { id = 614, name = "Ebonroc" },
                    { id = 615, name = "Flamegor" },
                    { id = 616, name = "Chromaggus" },
                    { id = 617, name = "Nefarian" },
                }
            },
            {
                id = 531,
                name = "Ahn'Qiraj",
                bosses = {
                    { id = 709, name = "The Prophet Skeram" },
                    { id = 710, name = "Battleguard Sartura" },
                    { id = 711, name = "Fankriss the Unyielding" },
                    { id = 712, name = "Princess Huhuran" },
                    { id = 713, name = "The Twin Emperors" },
                    { id = 714, name = "Ouro" },
                    { id = 715, name = "C'Thun" },
                }
            },
            {
                id = 533,
                name = "Naxxramas (Classic)",
                bosses = {
                    { id = 1107, name = "Anub'Rekhan" },
                    { id = 1110, name = "Grand Widow Faerlina" },
                    { id = 1116, name = "Maexxna" },
                    { id = 1117, name = "Noth the Plaguebringer" },
                    { id = 1118, name = "Heigan the Unclean" },
                    { id = 1119, name = "Loatheb" },
                    { id = 1121, name = "Instructor Razuvious" },
                    { id = 1122, name = "Gothik the Harvester" },
                    { id = 1123, name = "The Four Horsemen" },
                    { id = 1126, name = "Patchwerk" },
                    { id = 1127, name = "Grobbulus" },
                    { id = 1128, name = "Gluth" },
                    { id = 1129, name = "Thaddius" },
                    { id = 1131, name = "Sapphiron" },
                    { id = 1132, name = "Kel'Thuzad" },
                }
            },
        }
    },
    -- Tutaj dodamy kolejne dodatki: TBC, WotLK, itd...
}

-- Funkcje API bazujące na tej strukturze
function RaidTrack.GetOfflineExpansions()
    return RaidTrack.OfflineRaidData
end

function RaidTrack.GetOfflineInstances(expansionID)
    for _, exp in ipairs(RaidTrack.OfflineRaidData) do
        if exp.expansionID == expansionID then
            return exp.instances
        end
    end
    return {}
end

function RaidTrack.GetOfflineBosses(instanceID)
    for _, exp in ipairs(RaidTrack.OfflineRaidData) do
        for _, inst in ipairs(exp.instances) do
            if inst.id == instanceID then
                return inst.bosses
            end
        end
    end
    return {}
end
