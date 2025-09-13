Config = {}

Config.AdminRoleId = "YOUR_DISCORD_ADMIN_ROLE_ID"

-- Set to true to enable park-anywhere functionality (Shift + F to park/unpark vehicles)
Config.Parking = true

-- Set to true to enable departments and department paychecks
Config.Departments = true

-- How often to run distributePaychecks (in minutes)
Config.PaycheckIntervalMinutes  = 1  -- 60 1 hour.



-- Your Discord App ID (string). Put your app id here.
Config.DISCORD_APP_ID = "YOUR_DISCORD_BOT_APP_ID"

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

-- To be done later.
Config.SHOW_JOB = false
-- leave nil
Config.FRAMEWORK = nil


--┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
--┃       Discord Configuration Guide    ┃
--┃  (Bot token & webhook link & Guild ID┃
--┃        inside your server.cfg )      ┃
--┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛