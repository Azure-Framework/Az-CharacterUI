# 🚀 Az-CharacterUI

A simple, robust character selection + spawn menu built for the **Azure Framework**.  


<img width="1291" height="800" alt="image" src="https://github.com/user-attachments/assets/8bcb1165-7cc7-4ed9-b285-d9f5e48153d6" />
<img width="824" height="334" alt="image" src="https://github.com/user-attachments/assets/731845ca-0fe6-474c-9a6f-51eb8754421f" />






---

## 🔧 What it does
- ✅ Let players **create**, **select**, and **delete** characters  
- 📍 Includes a **spawn selector** so players pick spawn locations  
- 🔒 Prevents the menu from reopening once a player has an active character  
- ⌨️ Opens via a configurable key or the `/charmenu` chat command  
- 🔄 Integrates nicely with existing server flows (no extra DB instructions here)

---

## ⚙️ Quick install (Owner steps)
1. Place the folder named `Az-CharacterUI` into your server resources folder, for example:  
   - `resources/[Framework]/Az-CharacterUI`  
2. Add to `server.cfg`:
```
ensure Az-CharacterUI
```
3. Restart the FiveM server.

---

## ✅ Requirements
- FiveM server (lua54)
- `@ox_lib` present (resource is referenced)
- Optional: `Az-Framework` (used for admin spawn-edit checks; resource still runs without it)

---

## 🛠️ Quick configuration (what to change)
Edit `config.lua` inside the resource folder. Common owner-editable options:
- `Config.UIKeybind` — key that opens the menu (e.g. `"F3"` or `"K"`)
- `Config.SERVER_NAME` — server name displayed in presence text
- `Config.SpawnFile` — filename used to store spawn points (default: `spawns.json`)
- `Config.RequireAzAdminForEdit` — `true` if only Az-Framework admins should edit spawns
- `Config.MapBounds` — world bounds for map projection (leave default unless you know the map extents)

After editing `config.lua`, save and restart the server.

---

## 🧭 Commands & Usage (for players & staff)
- `/charmenu` — open the character menu (player command)
- `spawnsel` — request the spawn selector (server/admin use)
- `azfw_debug_focus` — prints NUI focus state (admin debugging)

Player flow:
- Press the configured key or type `/charmenu`
- Create/select/delete characters
- Selecting a character closes the UI and moves camera to player spawn

---

## 🩺 Troubleshooting (Owner-focused)
- **Characters not showing**  
- Confirm resource is `ensure`d in `server.cfg`.  
- Check server console for azfw debug logs (enable DEBUG in `server.lua` if needed).
- **Menu keeps re-opening or won’t close**  
- Try a server restart. If issue persists, check server console and provide logs.
- **Keybind change not taking effect**  
- Edit `Config.UIKeybind` in `config.lua`, save, restart the server.

If you need help, gather server console output related to `Az-CharacterUI` and share it — logs make diagnosis much faster.

---

## 📁 Files included
- `server.lua` — server-side logic
- `client.lua` — client-side logic
- `config.lua` — editable settings
- `html/` — NUI files (index + config + map)
- `fxmanifest.lua` — resource manifest
- `spawns.json` — created automatically if missing

---

## 💬 Need help?
If you run into problems, provide:
1. Server console logs mentioning `azfw` or `Az-CharacterUI`  
2. Your `config.lua` values (redact sensitive tokens)  
3. Steps to reproduce the issue

Join the Azure-Framework Discord or contact the resource author with that info for faster support.

---

Thank you — drop this `README.md` in your `Az-CharacterUI` folder and you're good to go. 🎮✨





