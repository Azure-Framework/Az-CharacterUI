Config = {}

Config.PermDeath = true
Config.Debug = false

-- Starting cash for brand new characters
Config.StartingCash = 500000

Config.AdminRoleId = "YOUR_DISCORD_ADMIN_ROLE"

-- Park-anywhere functionality (Shift + F to park/unpark vehicles)
Config.Parking = true

-- Departments + paychecks
Config.Departments = true
Config.PaycheckIntervalMinutes = 1

-- UI Keybind
Config.UIKeybind = "F3"

-- Send player to fivem-appearance after spawn/camera
Config.UseAppearance = true

-- Discord Rich Presence
Config.DISCORD_APP_ID = "YOUR_BOT_APP_ID"
Config.UPDATE_INTERVAL = 5
Config.SERVER_NAME = "Kentucky State Roleplay"

-- Last Location
Config.EnableLastLocation = true
Config.LastLocationUpdateIntervalMs = 10000

-- FiveAppearance support
Config.EnableFiveAppearance = true

-- Character preview / mugshot
Config.Preview = {
    Enabled = true,
    Scene = vector4(402.92, -996.82, -99.00, 180.0),
    PedOffset = vector3(0.0, 0.0, 0.3),
    CamFov = 50.0,
    CamInterpMs = 250,

    Camera = {
        Enabled = true,
        Forward = 2.80,
        Right = -0.15,
        Up = 0.00,
        TargetUp = -0.35
    },

    PrefetchAppearances = true,
    PrefetchLimit = 16,
    FetchAttempts = 10,
    FetchWaitMs = 250,
    NegativeCacheMs = 4000,

    Mugshot = {
        Enabled = true,
        DeptText = "YOUR_SERVER_NAME",
        BoardProp = "prop_police_id_board",
        TextProp = "prop_police_id_text",
        HandBone = 28422
    }
}

Config.MugshotEnabled = true
Config.MugshotRefreshMs = 700

-- /characters command (OPEN CHAR MENU)
Config.Command = true
Config.OpenCommand = "characters"

-- SPAWN "DEATH SCREEN" (WASTED-style)
Config.SpawnDeathScreen = {
    Enabled = true,
    DurationMs = 4200,

    -- Scaleform shard
    ShowShard = true,
    Title = "Azure Framework",
    Subtitle = "~r~Welcome to Azure Framework | Edit Config.lua...~s~",
    ShardBgColor = 2,

    -- Screen effect
    ScreenEffect = "DeathFailOut",

    -- Timecycle
    UseTimecycle = true,
    Timecycle = "REDMIST_blend",
    TimecycleStrength = 0.70,
    ExtraTimecycle = "fp_vig_red",
    ExtraTimecycleStrength = 1.0,

    -- Camera / HUD feel
    MotionBlur = true,
    HideRadarDuring = true,

    -- Sound
    PlaySound = true,
    SoundName = "Bed",
    SoundSet = "WastedSounds"
}

Config.Housing = {
    Enabled = true,

    Custom = {
        Resource = "az_housing",
        Export = "GetPlayerHouses"
    },

    SpawnName = "My House",
    SpawnDesc = "Spawn at your house"
}

-- FIRST JOIN / WELCOME / FIRST CAR
Config.UseFirstJoin = true

Config.FirstJoin = {
    Welcome = {
        PersistOncePerPlayer = true,
        ShowEverySession = true,
        Header = "Welcome to the Server",
        Content = [[
**Quick Start Guide**

- Use **/firstcar** to claim your first vehicle.
- **You only get 1 free car every 24 hours.**
- To save your vehicle's parking spot:
  **Press SHIFT + F** while parked.

If your car isn't where you left it, make sure you parked it properly.
Enjoy your stay!
]],
        Centered = true,
        Size = "md"
    },

    FirstCar = {
        CooldownSeconds = 24 * 60 * 60,
        SedanModels = {
            "asea",
            "asterope",
            "emperor",
            "fugitive",
            "glendale",
            "ingot",
            "intruder",
            "premier",
            "primo",
            "regina"
        },
        WarpIntoVehicle = true,
        ShowCooldownChatMessage = true
    }
}

-- Emoji set
Config.EMOJIS = {
    location = "📍",
    driving = "🚗",
    walking = "🚶",
    running = "🏃",
    idle = "🧍",
    lights_on = "🚨",
    lights_off = "🔕",
    zone = "📌",
    speed = "💨"
}

-- Spawns JSON filename
Config.SpawnFile = "spawns.json"

-- Map bounds used to map world XY to the 2048x2048 map image
Config.MapBounds = {
    minX = -3000.0,
    maxX = 3000.0,
    minY = -6300.0,
    maxY = 7000.0
}

-- Only Az-Framework admins can edit/save spawns
Config.RequireAzAdminForEdit = true

-- Rich presence job display (optional ESX/QB)
Config.SHOW_JOB = false
Config.FRAMEWORK = nil -- "esx" | "qb" | nil