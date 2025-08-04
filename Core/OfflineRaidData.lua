

-- Core/OfflineRaidData.lua

local RaidTrack = RaidTrack or {}

RaidTrack.OfflineRaidData = {
    {
        expansionID = 1,
        name = "Classic",
        instances = {
            {
                id = 409,
                name = "Molten Core",
                bosses = {
                    { id = 1000, name = "Lucifron" },
                    { id = 1001, name = "Magmadar" },
                    { id = 1002, name = "Gehennas" },
                    { id = 1003, name = "Garr" },
                    { id = 1004, name = "Baron Geddon" },
                    { id = 1005, name = "Shazzrah" },
                    { id = 1006, name = "Sulfuron Harbinger" },
                    { id = 1007, name = "Golemagg the Incinerator" },
                    { id = 1008, name = "Majordomo Executus" },
                    { id = 1009, name = "Ragnaros" },
                }
            },
            {
                id = 249,
                name = "Onyxia's Lair",
                bosses = {
                    { id = 1000, name = "Onyxia" },
                }
            },
            {
                id = 469,
                name = "Blackwing Lair",
                bosses = {
                    { id = 1000, name = "Razorgore the Untamed" },
                    { id = 1001, name = "Vaelastrasz the Corrupt" },
                    { id = 1002, name = "Broodlord Lashlayer" },
                    { id = 1003, name = "Firemaw" },
                    { id = 1004, name = "Ebonroc" },
                    { id = 1005, name = "Flamegor" },
                    { id = 1006, name = "Chromaggus" },
                    { id = 1007, name = "Nefarian" },
                }
            },
            {
                id = 531,
                name = "Ahn'Qiraj",
                bosses = {
                    { id = 1000, name = "The Prophet Skeram" },
                    { id = 1001, name = "Battleguard Sartura" },
                    { id = 1002, name = "Fankriss the Unyielding" },
                    { id = 1003, name = "Princess Huhuran" },
                    { id = 1004, name = "The Twin Emperors" },
                    { id = 1005, name = "Ouro" },
                    { id = 1006, name = "C'Thun" },
                }
            },
            {
                id = 533,
                name = "Naxxramas (Classic)",
                bosses = {
                    { id = 1000, name = "Anub'Rekhan" },
                    { id = 1001, name = "Grand Widow Faerlina" },
                    { id = 1002, name = "Maexxna" },
                    { id = 1003, name = "Noth the Plaguebringer" },
                    { id = 1004, name = "Heigan the Unclean" },
                    { id = 1005, name = "Loatheb" },
                    { id = 1006, name = "Instructor Razuvious" },
                    { id = 1007, name = "Gothik the Harvester" },
                    { id = 1008, name = "The Four Horsemen" },
                    { id = 1009, name = "Patchwerk" },
                    { id = 1010, name = "Grobbulus" },
                    { id = 1011, name = "Gluth" },
                    { id = 1012, name = "Thaddius" },
                    { id = 1013, name = "Sapphiron" },
                    { id = 1014, name = "Kel'Thuzad" },
                }
            },
        }
    },
    {
        expansionID = 2,
        name = "The Burning Crusade",
        instances = {
            {
                id = 544,
                name = "Magtheridon's Lair",
                bosses = {
                    { id = 1000, name = "Magtheridon" },
                }
            },
            {
                id = 546,
                name = "Gruul's Lair",
                bosses = {
                    { id = 1000, name = "High King Maulgar" },
                    { id = 1001, name = "Gruul the Dragonkiller" },
                }
            },
            {
                id = 548,
                name = "Serpentshrine Cavern",
                bosses = {
                    { id = 1000, name = "Hydross the Unstable" },
                    { id = 1001, name = "The Lurker Below" },
                    { id = 1002, name = "Leotheras the Blind" },
                    { id = 1003, name = "Fathom-Lord Karathress" },
                    { id = 1004, name = "Morogrim Tidewalker" },
                    { id = 1005, name = "Lady Vashj" },
                }
            },
            {
                id = 550,
                name = "Tempest Keep",
                bosses = {
                    { id = 1000, name = "Al'ar" },
                    { id = 1001, name = "Void Reaver" },
                    { id = 1002, name = "High Astromancer Solarian" },
                    { id = 1003, name = "Kael'thas Sunstrider" },
                }
            },
            {
                id = 534,
                name = "The Battle for Mount Hyjal",
                bosses = {
                    { id = 1000, name = "Rage Winterchill" },
                    { id = 1001, name = "Anetheron" },
                    { id = 1002, name = "Kaz'rogal" },
                    { id = 1003, name = "Azgalor" },
                    { id = 1004, name = "Archimonde" },
                }
            },
            {
                id = 564,
                name = "Black Temple",
                bosses = {
                    { id = 1000, name = "High Warlord Naj'entus" },
                    { id = 1001, name = "Supremus" },
                    { id = 1002, name = "Shade of Akama" },
                    { id = 1003, name = "Teron'khan" },
                    { id = 1004, name = "Gurtogg Bloodboil" },
                    { id = 1005, name = "Reliquary of Souls" },
                    { id = 1006, name = "Mother Shahraz" },
                    { id = 1007, name = "The Illidari Council" },
                    { id = 1008, name = "Illidan Stormrage" },
                }
            },
            {
                id = 580,
                name = "Sunwell Plateau",
                bosses = {
                    { id = 1000, name = "Kalecgos" },
                    { id = 1001, name = "Brutallus" },
                    { id = 1002, name = "Felmyst" },
                    { id = 1003, name = "Eredar Twins" },
                    { id = 1004, name = "M'uru" },
                    { id = 1005, name = "Kil'jaeden" },
                }
            },
        }
    },
    {
        expansionID = 3,
        name = "Wrath of the Lich King",
        instances = {
            {
                id = 615,
                name = "The Obsidian Sanctum",
                bosses = {
                    { id = 1000, name = "Sartharion" },
                }
            },
            {
                id = 616,
                name = "The Eye of Eternity",
                bosses = {
                    { id = 1000, name = "Malygos" },
                }
            },
            {
                id = 624,
                name = "Vault of Archavon",
                bosses = {
                    { id = 1000, name = "Archavon the Stone Watcher" },
                    { id = 1001, name = "Emalon the Storm Watcher" },
                    { id = 1002, name = "Koralon the Flame Watcher" },
                    { id = 1003, name = "Toravon the Ice Watcher" },
                }
            },
            {
                id = 603,
                name = "Ulduar",
                bosses = {
                    { id = 1000, name = "Flame Leviathan" },
                    { id = 1001, name = "Ignis the Furnace Master" },
                    { id = 1002, name = "Razorscale" },
                    { id = 1003, name = "XT-002 Deconstructor" },
                    { id = 1004, name = "Assembly of Iron" },
                    { id = 1005, name = "Kologarn" },
                    { id = 1006, name = "Auriaya" },
                    { id = 1007, name = "Hodir" },
                    { id = 1008, name = "Thorim" },
                    { id = 1009, name = "Freya" },
                    { id = 1010, name = "Mimiron" },
                    { id = 1011, name = "General Vezax" },
                    { id = 1012, name = "Yogg-Saron" },
                    { id = 1013, name = "Algalon the Observer" },
                }
            },
            {
                id = 616,
                name = "Trial of the Crusader",
                bosses = {
                    { id = 1000, name = "Northrend Beasts" },
                    { id = 1001, name = "Lord Jaraxxus" },
                    { id = 1002, name = "Faction Champions" },
                    { id = 1003, name = "Twin Val'kyr" },
                    { id = 1004, name = "Anub'arak" },
                }
            },
            {
                id = 631,
                name = "Icecrown Citadel",
                bosses = {
                    { id = 1000, name = "Lord Marrowgar" },
                    { id = 1001, name = "Lady Deathwhisper" },
                    { id = 1002, name = "Gunship Battle" },
                    { id = 1003, name = "Deathbringer Saurfang" },
                    { id = 1004, name = "Festergut" },
                    { id = 1005, name = "Rotface" },
                    { id = 1006, name = "Professor Putricide" },
                    { id = 1007, name = "Blood Princes" },
                    { id = 1008, name = "Blood-Queen Lana'thel" },
                    { id = 1009, name = "Valithria Dreamwalker" },
                    { id = 1010, name = "Sindragosa" },
                    { id = 1011, name = "The Lich King" },
                }
            },
            {
                id = 724,
                name = "The Ruby Sanctum",
                bosses = {
                    { id = 1000, name = "Halion" },
                }
            },
        }
    },
    {
        expansionID = 4,
        name = "Cataclysm",
        instances = {
            {
                id = 754,
                name = "Blackwing Descent",
                bosses = {
                    { id = 1000, name = "Magmaw" },
                    { id = 1001, name = "Omnotron Defense System" },
                    { id = 1002, name = "Maloriak" },
                    { id = 1003, name = "Atramedes" },
                    { id = 1004, name = "Chimaeron" },
                    { id = 1005, name = "Nefarian" },
                }
            },
            {
                id = 758,
                name = "The Bastion of Twilight",
                bosses = {
                    { id = 1000, name = "Halfus Wyrmbreaker" },
                    { id = 1001, name = "Theralion and Valiona" },
                    { id = 1002, name = "Ascendant Council" },
                    { id = 1003, name = "Cho'gall" },
                    { id = 1004, name = "Sinestra" },
                }
            },
            {
                id = 773,
                name = "Throne of the Four Winds",
                bosses = {
                    { id = 1000, name = "Conclave of Wind" },
                    { id = 1001, name = "Al'Akir" },
                }
            },
            {
                id = 800,
                name = "Firelands",
                bosses = {
                    { id = 1000, name = "Beth'tilac" },
                    { id = 1001, name = "Lord Rhyolith" },
                    { id = 1002, name = "Alysrazor" },
                    { id = 1003, name = "Shannox" },
                    { id = 1004, name = "Baleroc" },
                    { id = 1005, name = "Majordomo Staghelm" },
                    { id = 1006, name = "Ragnaros" },
                }
            },
            {
                id = 824,
                name = "Dragon Soul",
                bosses = {
                    { id = 1000, name = "Morchok" },
                    { id = 1001, name = "Warlord Zon'ozz" },
                    { id = 1002, name = "Yor'sahj the Unsleeping" },
                    { id = 1003, name = "Hagara the Stormbinder" },
                    { id = 1004, name = "Ultraxion" },
                    { id = 1005, name = "Warmaster Blackhorn" },
                    { id = 1006, name = "Spine of Deathwing" },
                    { id = 1007, name = "Madness of Deathwing" },
                }
            },
        }
    },
    {
        expansionID = 5,
        name = "Mists of Pandaria",
        instances = {
            {
                id = 896,
                name = "Mogu'shan Vaults",
                bosses = {
                    { id = 1000, name = "The Stone Guard" },
                    { id = 1001, name = "Feng the Accursed" },
                    { id = 1002, name = "Gara'jal the Spiritbinder" },
                    { id = 1003, name = "The Spirit Kings" },
                    { id = 1004, name = "Elegon" },
                    { id = 1005, name = "Will of the Emperor" },
                }
            },
            {
                id = 897,
                name = "Heart of Fear",
                bosses = {
                    { id = 1000, name = "Imperial Vizier Zor'lok" },
                    { id = 1001, name = "Blade Lord Ta'yak" },
                    { id = 1002, name = "Garalon" },
                    { id = 1003, name = "Wind Lord Mel'jarak" },
                    { id = 1004, name = "Amber-Shaper Un'sok" },
                    { id = 1005, name = "Grand Empress Shek'zeer" },
                }
            },
            {
                id = 886,
                name = "Terrace of Endless Spring",
                bosses = {
                    { id = 1000, name = "Protectors of the Endless" },
                    { id = 1001, name = "Tsulong" },
                    { id = 1002, name = "Lei Shi" },
                    { id = 1003, name = "Sha of Fear" },
                }
            },
            {
                id = 930,
                name = "Throne of Thunder",
                bosses = {
                    { id = 1000, name = "Jin'rokh the Breaker" },
                    { id = 1001, name = "Horridon" },
                    { id = 1002, name = "Council of Elders" },
                    { id = 1003, name = "Tortos" },
                    { id = 1004, name = "Megaera" },
                    { id = 1005, name = "Ji-Kun" },
                    { id = 1006, name = "Durumu the Forgotten" },
                    { id = 1007, name = "Primordius" },
                    { id = 1008, name = "Dark Animus" },
                    { id = 1009, name = "Iron Qon" },
                    { id = 1010, name = "Twin Consorts" },
                    { id = 1011, name = "Lei Shen" },
                    { id = 1012, name = "Ra-den" },
                }
            },
            {
                id = 953,
                name = "Siege of Orgrimmar",
                bosses = {
                    { id = 1000, name = "Immerseus" },
                    { id = 1001, name = "The Fallen Protectors" },
                    { id = 1002, name = "Norushen" },
                    { id = 1003, name = "Sha of Pride" },
                    { id = 1004, name = "Galakras" },
                    { id = 1005, name = "Iron Juggernaut" },
                    { id = 1006, name = "Dark Shaman" },
                    { id = 1007, name = "General Nazgrim" },
                    { id = 1008, name = "Malkorok" },
                    { id = 1009, name = "Spoils of Pandaria" },
                    { id = 1010, name = "Thok the Bloodthirsty" },
                    { id = 1011, name = "Siegecrafter Blackfuse" },
                    { id = 1012, name = "Paragons of the Klaxxi" },
                    { id = 1013, name = "Garrosh Hellscream" },
                }
            },
        }
    },
    {
        expansionID = 6,
        name = "Warlords of Draenor",
        instances = {
            {
                id = 988,
                name = "Highmaul",
                bosses = {
                    { id = 1000, name = "Kargath Bladefist" },
                    { id = 1001, name = "The Butcher" },
                    { id = 1002, name = "Tectus" },
                    { id = 1003, name = "Brackenspore" },
                    { id = 1004, name = "Twin Ogron" },
                    { id = 1005, name = "Ko'ragh" },
                    { id = 1006, name = "Imperator Mar'gok" },
                }
            },
            {
                id = 989,
                name = "Blackrock Foundry",
                bosses = {
                    { id = 1000, name = "Gruul" },
                    { id = 1001, name = "Oregorger" },
                    { id = 1002, name = "Beastlord Darmac" },
                    { id = 1003, name = "Flamebender Ka'graz" },
                    { id = 1004, name = "Hans'gar and Franzok" },
                    { id = 1005, name = "Operator Thogar" },
                    { id = 1006, name = "The Blast Furnace" },
                    { id = 1007, name = "Kromog" },
                    { id = 1008, name = "Iron Maidens" },
                    { id = 1009, name = "Blackhand" },
                }
            },
            {
                id = 1026,
                name = "Hellfire Citadel",
                bosses = {
                    { id = 1000, name = "Hellfire Assault" },
                    { id = 1001, name = "Iron Reaver" },
                    { id = 1002, name = "Kormrok" },
                    { id = 1003, name = "Hellfire High Council" },
                    { id = 1004, name = "Kilrogg Deadeye" },
                    { id = 1005, name = "Gorefiend" },
                    { id = 1006, name = "Shadow-Lord Iskar" },
                    { id = 1007, name = "Socrethar the Eternal" },
                    { id = 1008, name = "Fel Lord Zakuun" },
                    { id = 1009, name = "Xhul'horac" },
                    { id = 1010, name = "Tyrant Velhari" },
                    { id = 1011, name = "Mannoroth" },
                    { id = 1012, name = "Archimonde" },
                }
            },
        }
    },
    {
        expansionID = 7,
        name = "Legion",
        instances = {
            {
                id = 1115,
                name = "The Emerald Nightmare",
                bosses = {
                    { id = 1000, name = "Nythendra" },
                    { id = 1001, name = "Elerethe Renferal" },
                    { id = 1002, name = "Il'gynoth" },
                    { id = 1003, name = "Ursoc" },
                    { id = 1004, name = "Dragons of Nightmare" },
                    { id = 1005, name = "Cenarius" },
                    { id = 1006, name = "Xavius" },
                }
            },
            {
                id = 1114,
                name = "Trial of Valor",
                bosses = {
                    { id = 1000, name = "Odyn" },
                    { id = 1001, name = "Guarm" },
                    { id = 1002, name = "Helya" },
                }
            },
            {
                id = 1088,
                name = "The Nighthold",
                bosses = {
                    { id = 1000, name = "Skorpyron" },
                    { id = 1001, name = "Chronomatic Anomaly" },
                    { id = 1002, name = "Trilliax" },
                    { id = 1003, name = "Spellblade Aluriel" },
                    { id = 1004, name = "Tichondrius" },
                    { id = 1005, name = "Krosus" },
                    { id = 1006, name = "High Botanist Tel'arn" },
                    { id = 1007, name = "Star Augur Etraeus" },
                    { id = 1008, name = "Grand Magistrix Elisande" },
                    { id = 1009, name = "Gul'dan" },
                }
            },
            {
                id = 1147,
                name = "Tomb of Sargeras",
                bosses = {
                    { id = 1000, name = "Goroth" },
                    { id = 1001, name = "Demonic Inquisition" },
                    { id = 1002, name = "Harjatan" },
                    { id = 1003, name = "Sisters of the Moon" },
                    { id = 1004, name = "The Desolate Host" },
                    { id = 1005, name = "Maiden of Vigilance" },
                    { id = 1006, name = "Fallen Avatar" },
                    { id = 1007, name = "Kil'jaeden" },
                }
            },
            {
                id = 1188,
                name = "Antorus, the Burning Throne",
                bosses = {
                    { id = 1000, name = "Garothi Worldbreaker" },
                    { id = 1001, name = "Felhounds of Sargeras" },
                    { id = 1002, name = "Antoran High Command" },
                    { id = 1003, name = "Portal Keeper Hasabel" },
                    { id = 1004, name = "Eonar the Life-Binder" },
                    { id = 1005, name = "Imonar the Soulhunter" },
                    { id = 1006, name = "Kin'garoth" },
                    { id = 1007, name = "Varimathras" },
                    { id = 1008, name = "The Coven of Shivarra" },
                    { id = 1009, name = "Aggramar" },
                    { id = 1010, name = "Argus the Unmaker" },
                }
            },
        }
    },
    {
        expansionID = 8,
        name = "Battle for Azeroth",
        instances = {
            {
                id = 1861,
                name = "Uldir",
                bosses = {
                    { id = 1000, name = "Taloc" },
                    { id = 1001, name = "MOTHER" },
                    { id = 1002, name = "Fetid Devourer" },
                    { id = 1003, name = "Zek'voz" },
                    { id = 1004, name = "Vectis" },
                    { id = 1005, name = "Zul" },
                    { id = 1006, name = "Mythrax" },
                    { id = 1007, name = "G'huun" },
                }
            },
            {
                id = 2070,
                name = "Battle of Dazar'alor",
                bosses = {
                    { id = 1000, name = "Champion of the Light" },
                    { id = 1001, name = "Grong" },
                    { id = 1002, name = "Jadefire Masters" },
                    { id = 1003, name = "Opulence" },
                    { id = 1004, name = "Conclave of the Chosen" },
                    { id = 1005, name = "King Rastakhan" },
                    { id = 1006, name = "High Tinker Mekkatorque" },
                    { id = 1007, name = "Stormwall Blockade" },
                    { id = 1008, name = "Lady Jaina Proudmoore" },
                }
            },
            {
                id = 2096,
                name = "Crucible of Storms",
                bosses = {
                    { id = 1000, name = "The Restless Cabal" },
                    { id = 1001, name = "Uu'nat" },
                }
            },
            {
                id = 2217,
                name = "The Eternal Palace",
                bosses = {
                    { id = 1000, name = "Abyssal Commander Sivara" },
                    { id = 1001, name = "Blackwater Behemoth" },
                    { id = 1002, name = "Radiance of Azshara" },
                    { id = 1003, name = "Lady Ashvane" },
                    { id = 1004, name = "Orgozoa" },
                    { id = 1005, name = "The Queen's Court" },
                    { id = 1006, name = "Za'qul" },
                    { id = 1007, name = "Queen Azshara" },
                }
            },
            {
                id = 2212,
                name = "Ny'alotha",
                bosses = {
                    { id = 1000, name = "Wrathion" },
                    { id = 1001, name = "Maut" },
                    { id = 1002, name = "The Prophet Skitra" },
                    { id = 1003, name = "Dark Inquisitor Xanesh" },
                    { id = 1004, name = "Vexiona" },
                    { id = 1005, name = "The Hivemind" },
                    { id = 1006, name = "Shad'har" },
                    { id = 1007, name = "Drest'agath" },
                    { id = 1008, name = "Il'gynoth" },
                    { id = 1009, name = "Carapace of N'Zoth" },
                    { id = 1010, name = "N'Zoth the Corruptor" },
                }
            },
        }
    },
    {
        expansionID = 9,
        name = "Shadowlands",
        instances = {
            {
                id = 2390,
                name = "Castle Nathria",
                bosses = {
                    { id = 1000, name = "Shriekwing" },
                    { id = 1001, name = "Huntsman Altimor" },
                    { id = 1002, name = "Hungering Destroyer" },
                    { id = 1003, name = "Artificer Xy'mox" },
                    { id = 1004, name = "Sun King's Salvation" },
                    { id = 1005, name = "Lady Inerva Darkvein" },
                    { id = 1006, name = "The Council of Blood" },
                    { id = 1007, name = "Sludgefist" },
                    { id = 1008, name = "Stone Legion Generals" },
                    { id = 1009, name = "Sire Denathrius" },
                }
            },
            {
                id = 2407,
                name = "Sanctum of Domination",
                bosses = {
                    { id = 1000, name = "The Tarragrue" },
                    { id = 1001, name = "The Eye of the Jailer" },
                    { id = 1002, name = "The Nine" },
                    { id = 1003, name = "Remnant of Ner'zhul" },
                    { id = 1004, name = "Soulrender Dormazain" },
                    { id = 1005, name = "Painsmith Raznal" },
                    { id = 1006, name = "Guardian of the First Ones" },
                    { id = 1007, name = "Fatescribe Roh-Kalo" },
                    { id = 1008, name = "Kel'Thuzad" },
                    { id = 1009, name = "Sylvanas Windrunner" },
                }
            },
            {
                id = 2481,
                name = "Sepulcher of the First Ones",
                bosses = {
                    { id = 1000, name = "Vigilant Guardian" },
                    { id = 1001, name = "Skolex" },
                    { id = 1002, name = "Artificer Xy'mox" },
                    { id = 1003, name = "Dausegne" },
                    { id = 1004, name = "Prototype Pantheon" },
                    { id = 1005, name = "Lihuvim" },
                    { id = 1006, name = "Halondrus" },
                    { id = 1007, name = "Anduin Wrynn" },
                    { id = 1008, name = "Lords of Dread" },
                    { id = 1009, name = "Rygelon" },
                    { id = 1010, name = "The Jailer" },
                }
            },
        }
    },
    {
        expansionID = 10,
        name = "Dragonflight",
        instances = {
            {
                id = 2522,
                name = "Vault of the Incarnates",
                bosses = {
                    { id = 1000, name = "Eranog" },
                    { id = 1001, name = "Terros" },
                    { id = 1002, name = "The Primal Council" },
                    { id = 1003, name = "Sennarth" },
                    { id = 1004, name = "Dathea" },
                    { id = 1005, name = "Kurog Grimtotem" },
                    { id = 1006, name = "Broodkeeper Diurna" },
                    { id = 1007, name = "Raszageth" },
                }
            },
            {
                id = 2569,
                name = "Aberrus",
                bosses = {
                    { id = 1000, name = "Kazzara" },
                    { id = 1001, name = "Molgoth" },
                    { id = 1002, name = "Experimentation of Dracthyr" },
                    { id = 1003, name = "Zaqali Invasion" },
                    { id = 1004, name = "Rashok" },
                    { id = 1005, name = "Zskarn" },
                    { id = 1006, name = "Magmorax" },
                    { id = 1007, name = "Neltharion" },
                    { id = 1008, name = "Scalecommander Sarkareth" },
                }
            },
            {
                id = 2549,
                name = "Amirdrassil",
                bosses = {
                    { id = 1000, name = "Gnarlroot" },
                    { id = 1001, name = "Igira" },
                    { id = 1002, name = "Volcoross" },
                    { id = 1003, name = "Council of Dreams" },
                    { id = 1004, name = "Larodar" },
                    { id = 1005, name = "Nymue" },
                    { id = 1006, name = "Smolderon" },
                    { id = 1007, name = "Tindral" },
                    { id = 1008, name = "Fyrakk" },
                }
            },
        }
    },
    {
        expansionID = 11,
        name = "The War Within",
        instances = {
            {
                id = 2700,
                name = "Ara-Kara",
                bosses = {
                    { id = 1000, name = "The Bloodbound Horror" },
                    { id = 1001, name = "Halls of Awakening" },
                    { id = 1002, name = "Tidefury Depths" },
                    { id = 1003, name = "The Empress Below" },
                }
            },
            {
    id = 2701,
    name = "Liberation of Undermine",
    bosses = {
        { id = 1, name = "Cauldron of Carnage" },
        { id = 2, name = "Rik Reverb" },
        { id = 3, name = "Sprocketmonger Lockenstock" },
        { id = 4, name = "Stix Bunkjunker" },
        { id = 5, name = "Vexie and the Geargrinders" },
        { id = 6, name = "One‑Armed Bandit" },
        { id = 7, name = "Mug’Zee" },
        { id = 8, name = "Chrome King Gallywix" },
    }
}

        }
        
    },
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
