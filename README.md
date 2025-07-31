# RaidTrack

**RaidTrack** is a comprehensive World of Warcraft addon for raid tracking, loot distribution, and EPGP (Effort Points / Gear Points) management. It allows raid leaders and guild officers to manage loot distribution and synchronization across guild members efficiently.

## Key Features:
- **EPGP Tracking**: Tracks EP (Effort Points) and GP (Gear Points) for each player in the raid, helping with loot distribution based on effort and previous loot costs.
- **Loot History**: Records all loot items, including player loots and corresponding GP values, with an easy-to-navigate loot history.
- **Auction System**: Auction-based loot distribution system where participants can bid on items based on their EP and GP. Supports multiple auction items.
- **Syncing**: Features a chunked data sync system to ensure accurate synchronization of loot, EPGP changes, and settings across all guild members, minimizing data loss and duplication.
- **Sync Settings**: Configurable synchronization settings including automatic syncing and rank-based permissions for officers.
- **Customizable Interface**: A fully customizable UI for both raid leaders and participants, including draggable and resizable windows, tooltips, and responsive elements.

## Auction System:
- **Multiple Bidding Options**: Participants can bid for items based on their role (Main Spec, Off Spec, Transmog, or Pass).
- **Auction Duration**: The auction leader can set the duration for each auction round.
- **Manual Sync**: Sync data manually to ensure that all players have the most up-to-date information.
- **Auction Responses**: Tracks and displays responses from auction participants, including EP, GP, and Priority Rating (PR).

## Installation:
1. Download and extract the RaidTrack addon files into your World of Warcraft `Interface/AddOns` folder.
2. Reload the UI or restart the game to initialize the addon.
3. Configure the addon using the settings tab accessible through the RaidTrack minimap icon.

## Commands:
- `/raidtrack` - Opens the RaidTrack main UI.
- `/rtcleardb` - Clears all RaidTrack data (use with caution).
