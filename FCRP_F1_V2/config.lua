--[[
╔══════════════════════════════════════════════════════════════╗
║            FLAME CITY F1 — shared/config.lua                 ║
║                  Qbox + ox_target  |  v2.0                   ║
╚══════════════════════════════════════════════════════════════╝

  All gameplay, physics, rewards, systems and locations are
  controlled from this single file. Restart the server after
  every change.
]]

Config = {}

-- ─────────────────────────────────────────────────────────────
-- 🌍  GENERAL
-- ─────────────────────────────────────────────────────────────
Config.Debug              = false
Config.Language           = 'en'       -- 'en' | 'tr' | 'de'
Config.MoneyType          = 'bank'     -- 'cash' | 'bank'
Config.EventPrefix        = 'frcp_f1'  -- do NOT change unless you rename all events too

-- ─────────────────────────────────────────────────────────────
-- 🏎️  F1 CAR  (the one model used for every race)
-- ─────────────────────────────────────────────────────────────
Config.F1CarModel         = `openwheel1`   -- change to any model hash

-- How many liveries your model has (1-based). Livery 1 is reserved for
-- special use; random assignment starts from 2.
Config.LiveryCount        = 11

-- ─────────────────────────────────────────────────────────────
-- 🏁  RACE RULES
-- ─────────────────────────────────────────────────────────────
Config.MaxLaps            = 5
Config.MinPlayers         = 2          -- minimum drivers needed to start
Config.StartFreezeSeconds = 3          -- seconds the grid is frozen while SC peels off
Config.ResultsScreenDelay = 18         -- seconds results overlay stays before TP

-- ─────────────────────────────────────────────────────────────
-- 💰  PRIZE
-- ─────────────────────────────────────────────────────────────
Config.PrizeMoney         = 100000     -- winner prize (ox_inventory cash item)
Config.PrizeItem          = 'money'    -- item name used by ox_inventory

-- ─────────────────────────────────────────────────────────────
-- 🔐  ORGANISER
-- ─────────────────────────────────────────────────────────────
-- 'admin' | 'superadmin' | nil (nil = no permission check, dev mode)
Config.OrganizerPermission = 'admin'

-- ─────────────────────────────────────────────────────────────
-- 🎒  ITEM SYSTEM
-- ─────────────────────────────────────────────────────────────
Config.Items = {
    enabled    = false,         -- true = drivers need the item below to be assigned a grid slot
    entryItem  = 'racechip',    -- item consumed when a driver is placed on the grid
}

-- ─────────────────────────────────────────────────────────────
-- 👥  CREW SYSTEM
-- ─────────────────────────────────────────────────────────────
Config.CrewSystem = {
    enabled        = true,
    createCost     = 5000,      -- money to create a crew
    maxMembers     = 8,
    rewardCooldown = 10,        -- minutes between crew reward claims
}

-- ─────────────────────────────────────────────────────────────
-- 🏆  XP & RATING  (index = finishing position, 1 = winner)
-- ─────────────────────────────────────────────────────────────
Config.WinXP     = 150
Config.RatingWin =  50

--          P1   P2   P3   P4   P5   P6   P7   P8
Config.XP     = { 100,  80,  60,  40,  25,  15,   8,   4 }
Config.Rating = {  50,  35,  22,  12,   4,  -4, -10, -18 }

-- ─────────────────────────────────────────────────────────────
-- 🎁  WEEKLY REWARD  (claim with /f1reward)
-- ─────────────────────────────────────────────────────────────
Config.WeeklyReward = {
    type   = 'money',                           -- 'money' | 'item'
    money  = 50000,
    item   = { name = 'racechip', amount = 3 },
}

-- ─────────────────────────────────────────────────────────────
-- ⏱️  AUTO-RACE  (server-clock triggers — 24h format HH:MM)
-- ─────────────────────────────────────────────────────────────
Config.AutoRace = {
    -- { time = '20:00' },
    -- { time = '23:00' },
}

-- ─────────────────────────────────────────────────────────────
-- 🧍  RACE MANAGER NPC  (ox_target interaction)
-- ─────────────────────────────────────────────────────────────
Config.RaceManagerNPC = {
    enabled = true,
    coords  = vector4(1113.5, 264.0, 79.05, 237.0),  -- beside pit lane entry
    model   = 's_m_m_security_01',
    label   = 'Race Manager',
    -- Players with OrganizerPermission get the full organiser panel.
    -- All others get a read-only standings / stats viewer.
}

-- ─────────────────────────────────────────────────────────────
-- 🏎️  F1 BASE HANDLING  (applied on car spawn)
-- ─────────────────────────────────────────────────────────────
Config.F1BaseHandling = {
    fInitialDriveForce        = 1.00,
    fDriveInertia             = 1.00,
    fDriveBiasFront           = 0.00,
    fLowSpeedTractionLossMult = 2.80,
    fInitialDragCoeff         = 25.0,
    fTractionCurveMax         = 4.80,
    fTractionCurveMin         = 2.60,
}
Config.F1BaseTopSpeed = 60.0  -- passed to ModifyVehicleTopSpeed

-- ─────────────────────────────────────────────────────────────
-- 🔧  TIRE COMPOUNDS  (pit stop selection)
-- ─────────────────────────────────────────────────────────────
-- Each compound overrides specific handling floats on top of the base preset.
-- 'laps' = how many laps before the compound starts degrading.
-- Set Config.PitStop.mandatory = false to make pit stops optional.
Config.TireCompounds = {
    soft = {
        label           = '🔴 Soft',
        color           = { 210, 50,  50  },
        laps            = 3,    -- starts degrading after this many laps
        driveForce      = 0.12, -- BONUS added to base
        topSpeedBonus   = 5.0,
        tractionMax     = 5.20,
        tractionMin     = 3.00,
        degradedForce   = -0.20, -- penalty when worn
        degradedTraction= -0.60,
    },
    medium = {
        label           = '🟡 Medium',
        color           = { 220, 200, 50  },
        laps            = 6,
        driveForce      = 0.05,
        topSpeedBonus   = 2.0,
        tractionMax     = 4.80,
        tractionMin     = 2.60,
        degradedForce   = -0.10,
        degradedTraction= -0.30,
    },
    hard = {
        label           = '⚪ Hard',
        color           = { 200, 200, 200 },
        laps            = 10,
        driveForce      = 0.00,
        topSpeedBonus   = 0.0,
        tractionMax     = 4.60,
        tractionMin     = 2.40,
        degradedForce   = -0.05,
        degradedTraction= -0.15,
    },
}

-- ─────────────────────────────────────────────────────────────
-- 🛞  PIT STOP
-- ─────────────────────────────────────────────────────────────
Config.PitStop = {
    enabled   = true,
    mandatory = true,           -- drivers MUST pit at least once or face DQ at finish

    -- Zone: driver pulls into this box area to trigger pit
    zone = {
        coords  = vector3(1125.0, 268.0, 79.05),
        size    = vector3(12.0, 6.0, 3.0),
        heading = 57.0,
    },

    -- Pit lane speed limiter (km/h). 0 = no limit enforced
    speedLimit   = 80.0,        -- km/h

    -- How long the stop takes (seconds) — player is frozen
    stopDuration = 4,
}

-- ─────────────────────────────────────────────────────────────
-- ⚡  DRS ZONES
-- ─────────────────────────────────────────────────────────────
Config.DRSZones = {
    {
        name   = 'Main Straight',
        entry  = vec3(-1558.4, -2763.5, 13.9),
        exit   = vec3(-1844.7, -2923.6, 13.9),
        radius = 30.0,
    },
    {
        name   = 'Back Straight',
        entry  = vec3(-1661.9, -2258.1, 13.9),
        exit   = vec3(-1319.4, -2392.4, 13.9),
        radius = 30.0,
    },
}

Config.DRS = {
    driveForceBoost = 0.45,
    topSpeedBoost   = 15.0,
}

-- ─────────────────────────────────────────────────────────────
-- 🔥  ENGINE DAMAGE THRESHOLDS
-- ─────────────────────────────────────────────────────────────
Config.EngineHealth = {
    warning  = 650.0,   -- 85% power
    damaged  = 400.0,   -- 60% power
    critical = 200.0,   -- 35% power
}

-- ─────────────────────────────────────────────────────────────
-- 🧭  RACE LINE  (Forza-style arrows toward next CP)
-- ─────────────────────────────────────────────────────────────
Config.RaceLine = {
    enabled   = true,
    segments  = 12,      -- arrow count (lower = lighter)
    maxDist   = 120.0,   -- don't draw if CP is further than this
}

-- ─────────────────────────────────────────────────────────────
-- 🚥  FORMATION LAP  /  SAFETY CAR
-- ─────────────────────────────────────────────────────────────
Config.FormationLap = {
    enabled        = true,
    safetyCarModel = `police3`,
    safetyCarSpot  = vector4(-1540.0, -2745.0, 13.9, 60.0),
    maxSpeed       = 220.0,   -- km/h cap during SC lap
}

-- ─────────────────────────────────────────────────────────────
-- 📍  GRID SPOTS  (up to 8 drivers)
-- ─────────────────────────────────────────────────────────────
Config.GridSpots = {
    vector4(1111.96, 261.35, 79.05,  57.44),  -- P1 Pole
    vector4(1110.13, 258.65, 79.05,  57.03),  -- P2
    vector4(1108.64, 255.97, 79.05,  57.54),  -- P3
    vector4(1106.91, 253.42, 79.05,  56.15),  -- P4
    vector4(1112.11, 250.08, 79.05, 237.61),  -- P5
    vector4(1113.83, 252.74, 79.05, 237.48),  -- P6
    vector4(1115.38, 255.42, 79.05, 238.65),  -- P7
    vector4(1117.07, 258.14, 79.05, 237.06),  -- P8
}

-- ─────────────────────────────────────────────────────────────
-- 🔵  CIRCUIT CHECKPOINTS
-- ─────────────────────────────────────────────────────────────
-- CP 1 = Start/Finish. All others use a cylinder marker.
Config.Checkpoints = {
    vector3(1169.35, 276.63, 80.91),  -- CP 1: Start / Finish
    vector3(1173.79, 283.37, 80.23),
    vector3(1226.80, 284.44, 80.11),
    vector3(1274.62, 230.68, 80.09),
    vector3(1237.41, 147.78, 80.10),
    vector3(1174.44,  43.35, 80.05),
    vector3(1105.96, -67.85, 80.04),
    vector3(1036.68, -88.14, 80.11),
    vector3( 999.51,  -0.70, 80.10),
    vector3(1101.77, 170.51, 80.05),  -- CP 10: Final straight
}

-- ─────────────────────────────────────────────────────────────
-- 🏠  POST-RACE TELEPORT LOCATION
-- ─────────────────────────────────────────────────────────────
Config.PostRaceLocation = vector4(1090.78, 194.97, 84.74, 239.1)

-- ─────────────────────────────────────────────────────────────
-- 📢  DISCORD WEBHOOK
-- ─────────────────────────────────────────────────────────────
Config.DiscordWebhook  = 'YOUR_WEBHOOK_URL_HERE'
Config.WebhookBotName  = 'Flame City GP'
Config.WebhookAvatar   = ''

-- ─────────────────────────────────────────────────────────────
-- 🔔  NOTIFICATIONS  (used in Notify() helper)
-- ─────────────────────────────────────────────────────────────
Config.Notify = {
    noItem           = 'You need a {item} to enter the race.',
    notEnoughMoney   = 'Not enough money!',
    accessDenied     = 'You are not an organiser.',
    raceWin          = '🏆 You won the race!  +{xp} XP  |  +{r} Rating',
    raceFinish       = 'You finished P{pos}  +{xp} XP  |  {r} Rating',
    disqualified     = '⛔ You have been disqualified — {reason}',
    pitEntry         = '🛞 Pit stop — choose your tire compound',
    pitDone          = '🟢 Pit out — {tire} fitted',
    pitMandatoryDQ   = 'You must pit at least once. DQ applied.',
    weeklyReward     = '🎁 Weekly reward claimed!',
    weeklyNotReady   = 'Weekly reward available in {hours} hours.',
    crewCreated      = '🏁 Crew "{name}" created successfully.',
    engineWarning    = '⚠️ ENGINE WARNING — 85% power',
    engineDamaged    = '🔴 ENGINE DAMAGED — 60% power',
    engineCritical   = '💀 ENGINE CRITICAL — 35% power',
    tireWorn         = '🔶 Tire wear warning — {tire} compound degrading!',
    drsOpen          = '⚡ DRS OPEN',
}

-- ─────────────────────────────────────────────────────────────
-- 🔐  AUTHORIZATION  (restrict to server-specific auth codes)
-- ─────────────────────────────────────────────────────────────
Config.Auth = {
    enabled = false,
    codes   = { 'YOURCODE123' },
}
