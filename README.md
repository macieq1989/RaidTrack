# RaidTrack

RaidTrack is a World of Warcraft addon + companion Discord bot that helps guilds manage **raids, loot, and EPGP** in a fully synchronized way.

## ✨ Features
- **Raid Tracking** – automatically records raid instances, bosses killed, and player attendance.
- **EPGP System** – fully integrated tracking of Effort Points (EP) and Gear Points (GP).
- **Auction-based Loot Distribution**  
  - Raid leader can start auctions for multiple items.  
  - Players respond with **BIS / Upgrade / Offspec / Disenchant / Transmog / Pass**.  
  - Integrated **tooltips** when hovering over items in the auction window.  
  - Auction timer is synchronized across all raid members.
- **Discord Sync** (via [RaidTrack-Discord-Bot](https://github.com/macieq1989/RaidTrack-Discord-Bot))  
  - Raid data exported directly to Discord channels.  
  - Loot posts and signup embeds.  
  - Class/spec icons and raid rosters with images.
- **Guild Integration**  
  - Officer-only synchronization options.  
  - Automatic checks for guild rank permissions.

## 🆕 Recent Updates
- Added **tooltips in Auction Participant UI**.  
- Auction timer is now consistent for all players (synchronized `endsAt`).  
- Improved caching and linking of auction items.  
- Fixed rare bug where one player saw only a 2-second timer.  

## 📦 Installation
1. Download the latest release from [Releases](https://github.com/macieq1989/RaidTrack/releases).  
2. Extract into your `World of Warcraft/_retail_/Interface/AddOns/` folder.  
3. Launch WoW and enable **RaidTrack** in the AddOn list.

## 🔗 Related
- [RaidTrack-Discord-Bot](https://github.com/macieq1989/RaidTrack-Discord-Bot) — companion bot for syncing raid data to Discord.
