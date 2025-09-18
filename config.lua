Config = {}

Config.AdminRoleId = "YOUR_DISCORD_ADMIN_ROLEID"

-- Set to true to enable park-anywhere functionality (Shift + F to park/unpark vehicles)
Config.Parking = true

-- Set to true to enable departments and department paychecks
Config.Departments = true

-- How often to run distributePaychecks (in minutes)
Config.PaycheckIntervalMinutes  = 1  -- 60 1 hour.

-- Default key: 121 = F10
-- You can find FiveM control IDs here: https://docs.fivem.net/docs/game-references/controls/
Config.OpenUIKey = 121

-- Your Discord App ID (string). Put your app id here.
Config.DISCORD_APP_ID = "YOUR_DISCORDAPP_ID"

-- Update interval in seconds
Config.UPDATE_INTERVAL = 5

-- Server name shown in presence text
Config.SERVER_NAME = "Azure Framework Showcase"

-- Emoji set (customize if you like)
Config.EMOJIS = {
  location = "📍",
  driving  = "🚗",
  walking  = "🚶",
  running  = "🏃",
  idle     = "🧍",
  lights_on = "🚨",
  lights_off = "🔕",
  zone     = "📌",
  speed    = "💨"
}

-- filename inside the resource folder to store spawns
Config.SpawnFile = Config.SpawnFile or "spawns.json"

-- map bounds used to map world XY to the 2048x2048 map image
-- These values should match how you want the projection to work for your vertical 2048x2048 map.png
-- Adjust to your server's world extents used for mapping.
Config.MapBounds = Config.MapBounds or {
  minX = -3000.0,
  maxX = 3000.0,
  minY = -6300.0,
  maxY = 7000.0
}

-- optional: allow only Az-Framework admins to edit/save
Config.RequireAzAdminForEdit = true

-- Show job (ESX/QBCore) in presence? false => don't attempt to fetch job
Config.SHOW_JOB = false
-- If you use ESX/QBCore, set framework: "esx" or "qb" or leave nil
Config.FRAMEWORK = nil


--┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
--┃       Discord Configuration Guide    ┃
--┃  (Bot token & webhook link & Guild ID┃
--┃        inside your server.cfg )      ┃
--┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛


