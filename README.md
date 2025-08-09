# RaidTrack

**RaidTrack** is an advanced World of Warcraft addon designed to make raid management, loot tracking, and guild-wide synchronization easier than ever.  
It provides a complete toolkit for raid leaders, officers, and guilds who want full control over loot distribution, EPGP tracking, and raid data sharing.

---

## ✨ Key Features

### 📦 Loot Tracking & History
- Automatically records all loot obtained during raids.
- Tracks who received each item, with GP (Gear Points) values assigned.
- Maintains a full loot history for review and auditing.

### ⚖️ EPGP System Support
- Fully integrated Effort Points / Gear Points (EPGP) tracking.
- Automatic GP assignment based on loot.
- EP adjustments, GP resets, and wipe IDs to ensure a fair system.

### 🔄 Real-Time Guild Sync
- Sync EPGP data, loot history, and settings between guild members.
- **Minimum Guild Rank control** – choose which ranks can participate in sync.
- Automatic sync on login or manual sync request.

### ⚙️ Access Control
- Officer-only features (optional restriction).
- Adjustable minimum rank for receiving and sending sync data.
- Access control is synchronized across the guild automatically.

### 🛡️ New Raid Management Module *(v3.0)*
- Sync raid presets and status in real-time between raid members.
- Share active raid settings automatically after raid start.
- Controlled by minimum required guild rank for security.
- Built-in whisper-based data transfer for fast and private communication.

### 💰 Built-in Auction System
- Run loot auctions directly inside the raid.
- Supports **Main Spec**, **Off Spec**, **Transmog**, and **Pass** bids.
- Shows all bids to the leader with EP/GP/PR values.
- Fully synchronized between participants.

### 🖥️ UI & Quality of Life
- Modern, tab-based interface with AceGUI-3.0.
- Minimap icon with quick actions menu.
- Debug log for tracking all addon communication.
- Adjustable window sizes and persistent settings.

---

## 📥 Installation
1. Download the latest release from the **[Releases](../../releases)** page.
2. Extract the folder into your WoW `Interface/AddOns/` directory.
3. Restart the game or reload UI with `/reload`.

---

## 📜 Slash Commands
- `/rt` – Open the RaidTrack main window.
- `/rtcleardb` – Clear the database (EPGP, loot, and sync data).

---

## 🚀 Recent Major Update – **v3.0**
- Added **RaidSync** module for live raid preset/status sharing.
- Access control is now synced with settings.
- UI improvements:  
  - Moved and resized dropdowns for better alignment.  
  - Expanded debug log area.  
- Fixed multiple Lua errors related to UI tab switching.
- Improved chunk-based data transfer for reliability.

---

## 🛠️ Technical Details
- Built using **Ace3 Framework**.
- Data serialization with efficient chunk-based messaging.
- Supports both **guild-wide** and **raid-only** communication.
- Optimized to minimize in-game addon channel usage.

---

## 📄 License
This project is released under the MIT License.  
You are free to use, modify, and share it – just give credit to the original author.

