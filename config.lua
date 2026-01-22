
Config = Config or {}
Config.PermDeath = true
Config.Debug = true

-- Starting cash for brand new characters
Config.StartingCash = 500000   -- 1MIL starting cash

Config.AdminRoleId = "1437877833048395986"

-- Park-anywhere functionality (Shift + F to park/unpark vehicles)
Config.Parking = true-- default true

-- Departments + paychecks
Config.Departments = true -- default true
Config.PaycheckIntervalMinutes =  1 -- minutes

-- UI Keybind
Config.UIKeybind = "F3"

-- Send player to fivem-appearance after spawn/camera
Config.UseAppearance = true

-- Discord Rich Presence
Config.DISCORD_APP_ID = "1259656710306660402"
Config.UPDATE_INTERVAL = 5
Config.SERVER_NAME = "Azure Framework Showcase"

-- Last Location
Config.EnableLastLocation = true
Config.LastLocationUpdateIntervalMs = 10000

-- FiveAppearance support
Config.EnableFiveAppearance = true

-- =========================================================
-- /characters command (OPEN CHAR MENU)
-- =========================================================
-- true = registers command
-- false = no command registered
Config.Command = (Config.Command ~= false) -- default true
Config.OpenCommand = Config.OpenCommand or "characters" -- /characters


-- ==========================================================
-- SPAWN "DEATH SCREEN" (WASTED-style) — CONFIG (COMMENTED)
-- ==========================================================
-- This config drives:
--  • The WASTED shard scaleform ("mp_big_message_freemode") :contentReference[oaicite:0]{index=0}
--  • Optional screen FX via StartScreenEffect :contentReference[oaicite:1]{index=1}
--  • Optional timecycle grading via SetTimecycleModifier :contentReference[oaicite:2]{index=2}
--  • Optional frontend sounds via PlaySoundFrontend :contentReference[oaicite:3]{index=3}

Config = Config or {}

Config.SpawnDeathScreen = Config.SpawnDeathScreen or {
  -- Master switch (turn the entire feature on/off)
  Enabled = true,

  -- How long the effect runs while you are fading/spawning (ms)
  -- Tip: Usually 1500–4500 feels good. You set 4200 which is nice for “server intro”.
  DurationMs = 4200,

  -- ==========================================================
  -- SCALEFORM "WASTED" SHARD (BIG CENTER TEXT)
  -- ==========================================================
  -- Uses scaleform: "mp_big_message_freemode"
  -- Method: "SHOW_SHARD_WASTED_MP_MESSAGE" :contentReference[oaicite:4]{index=4}
  ShowShard = true,

  -- Big text (top line)
  Title = "State of LS",

  -- Smaller text (2nd line)
  -- Supports GTA color codes, e.g.
  --   ~r~ red, ~b~ blue, ~g~ green, ~y~ yellow, ~p~ purple, ~o~ orange, ~s~ reset
  Subtitle = "~r~Welcome to SLS | Always RP...~s~",

  -- Background style/color index for the shard.
  -- Rockstar uses small integers here; 5 is the common “Wasted” look.
  -- You can try: 0,1,2,3,4,5,6 (varies by shard type / game scripts).
  ShardBgColor = 2,

  -- ==========================================================
  -- SCREEN EFFECT (POST-FX) — StartScreenEffect
  -- ==========================================================
  -- This is the “screen filter / vignette / transitions” bucket.
  -- Set "" (empty string) to disable.
  --
  -- A *huge* list exists; below are common/useful ones.
  -- Full community lists: :contentReference[oaicite:5]{index=5}
  ScreenEffect = "DeathFailOut",

  -- Common “death / fail / drama”:
  --   "DeathFailOut"
  --   "DeathFailMPDark"
  --   "DeathFailMPIn"
  --   "DeathFailNeutralIn"
  --   "DeathFailMichaelIn"
  --   "DeathFailFranklinIn"
  --   "DeathFailTrevorIn"
  --
  -- “focus / blur / transition”:
  --   "FocusIn"
  --   "FocusOut"
  --   "MinigameTransitionIn"
  --   "MinigameTransitionOut"
  --   "SwitchHUDIn"
  --   "SwitchHUDOut"
  --   "SwitchShortNeutralIn"
  --   "SwitchShortMichaelIn"
  --   "SwitchShortFranklinIn"
  --   "SwitchShortTrevorIn"
  --
  -- “celebration / heist / UI-ish”:
  --   "HeistCelebPass"
  --   "HeistCelebPassBW"
  --   "HeistCelebToast"
  --   "MP_Celeb_Win"
  --   "MP_Celeb_Win_Out"
  --
  -- “fun / drug-trip style”:
  --   "DrugsMichaelAliensFightIn"
  --   "DrugsMichaelAliensFight"
  --   "DrugsMichaelAliensFightOut"
  --   "DrugsTrevorClownsFightIn"
  --   "DrugsTrevorClownsFight"
  --   "DrugsTrevorClownsFightOut"
  --   "DMT_flight"
  --   "DMT_flight_intro"
  --   "ChopVision"
  --
  -- Note:
  -- - StartScreenEffect names overlap with “Screen FX” / “AnimpostFX” concepts in GTA.
  -- - If you ever swap to AnimpostfxPlay, the name list is similar but the native differs. :contentReference[oaicite:6]{index=6}

  -- ==========================================================
  -- TIMECYCLE COLOR GRADING — SetTimecycleModifier / SetExtraTimecycleModifier
  -- ==========================================================
  -- Timecycle modifiers are the “color grading / lighting mood” layer.
  -- Turn off by setting UseTimecycle=false.
  UseTimecycle = true,

  -- Main timecycle modifier name (tons exist; these are just examples)
  -- Reference list (big): :contentReference[oaicite:7]{index=7}
  Timecycle = "REDMIST_blend",

  -- 0.0 to 1.0-ish (game accepts floats; extremes can look blown out)
  TimecycleStrength = 0.70,

  -- Extra timecycle modifier (a second layer).
  -- Useful for vignettes like fp_vig_* etc.
  -- Important: scripting generally gets one “main” modifier + one “extra” modifier. :contentReference[oaicite:8]{index=8}
  ExtraTimecycle = "fp_vig_red",
  ExtraTimecycleStrength = 1.0,

  -- Some popular timecycle examples to try:
  --   "REDMIST_blend"         (dramatic red haze) :contentReference[oaicite:9]{index=9}
  --   "hud_def_blur"          (HUD blur style)
  --   "MP_corona_tint"        (subtle tint)
  --   "NG_filmic01"           (filmic look)
  --   "NG_blackout"           (dark / blackout vibe)
  --   "BarryFadeOut"          (trippy fade)
  --   "damage"                (injury-ish)
  --
  -- Extra/vignette style examples:
  --   "fp_vig_red"            (red vignette) :contentReference[oaicite:10]{index=10}
  --   "fp_vig_blue"
  --   "fp_vig_black"
  --
  -- How to find more:
  -- - Browse big timecycle lists (RAGE wiki / data browsers). :contentReference[oaicite:11]{index=11}
  -- - In FiveM, these names ultimately come from GTA’s timecycle data referenced by the native. :contentReference[oaicite:12]{index=12}

  -- ==========================================================
  -- CAMERA / HUD FEEL
  -- ==========================================================
  -- Adds motion blur on the player ped during the effect (cinematic feel)
  MotionBlur = true,

  -- Hide radar while the effect is running (you usually re-enable after spawn)
  HideRadarDuring = true,

  -- ==========================================================
  -- SOUND (FRONTEND SOUND)
  -- ==========================================================
  -- Plays a UI/frontend sound while the shard/FX runs.
  -- Disable by setting PlaySound=false.
  PlaySound = true,

  -- “Wasted” style clank commonly used:
  --   SoundName="Bed", SoundSet="WastedSounds" :contentReference[oaicite:13]{index=13}
  SoundName = "Bed",
  SoundSet  = "WastedSounds",

  -- Other common frontend sound combos people use:
  --   "ScreenFlash", "MissionFailedSounds" :contentReference[oaicite:14]{index=14}
  --   "SELECT",      "HUD_FRONTEND_DEFAULT_SOUNDSET" :contentReference[oaicite:15]{index=15}
  --   "BACK",        "HUD_FRONTEND_DEFAULT_SOUNDSET" :contentReference[oaicite:16]{index=16}
  --
  -- Finding more sounds:
  -- - The native is PlaySoundFrontend(audioName, audioRef). :contentReference[oaicite:17]{index=17}
  -- - There are community “frontend sounds” lists (not official, but handy). :contentReference[oaicite:18]{index=18}
}

-- Tip:
-- If you ever want ZERO post effects but keep the text:
--   ScreenEffect = ""
--   UseTimecycle = false
--   MotionBlur = false
-- (Shard text + sound still works.)



Config.Housing = Config.Housing or {
  Enabled = true,

  -- Put your housing export here
  Custom = {
    Resource = "az_housing",      -- CHANGE THIS
    Export = "GetPlayerHouses",   -- CHANGE THIS (but now called with charid)
  },

  SpawnName = "My House",
  SpawnDesc = "Spawn at your house",
}



-- Emoji set
Config.EMOJIS = Config.EMOJIS or {
  location  = "📍",
  driving   = "🚗",
  walking   = "🚶",
  running   = "🏃",
  idle      = "🧍",
  lights_on = "🚨",
  lights_off= "🔕",
  zone      = "📌",
  speed     = "💨"
}

-- Spawns JSON filename
Config.SpawnFile = Config.SpawnFile or "spawns.json"

-- Map bounds used to map world XY to the 2048x2048 map image
Config.MapBounds = Config.MapBounds or {
  minX = -3000.0,
  maxX =  3000.0,
  minY = -6300.0,
  maxY =  7000.0
}

-- Only Az-Framework admins can edit/save spawns
Config.RequireAzAdminForEdit = (Config.RequireAzAdminForEdit ~= false)

-- Rich presence job display (optional ESX/QB)
Config.SHOW_JOB = (Config.SHOW_JOB == true) -- default false
Config.FRAMEWORK = Config.FRAMEWORK or nil  -- "esx" | "qb" | nil

--┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
--┃       Discord Configuration Guide    ┃
--┃  (Bot token & webhook link & Guild ID┃
--┃        inside your server.cfg )      ┃
--┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
