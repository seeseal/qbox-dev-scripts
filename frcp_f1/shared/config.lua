--[[
╔══════════════════════════════════════════════════════════════════╗
║              FLAME CITY F1 — shared/config.lua                   ║
║                  Qbox + ox_target  |  v3.0                       ║
╚══════════════════════════════════════════════════════════════════╝

  Every gameplay rule, reward, system, NPC and location is
  controlled from this single file.
  Always restart the server after making changes.
]]

Config = {}

-- ─────────────────────────────────────────────────────────────────
-- 🌍  GENERAL
-- ─────────────────────────────────────────────────────────────────
-- +-----------------------------------------------------------------+
-- |  DEBUG FLAGS                                                    |
-- |                                                                 |
-- |  Config.Debug        -- master switch. Enables DBG() logs,     |
-- |                         /f1debug and /f1nuitest commands, and   |
-- |                         auto diagnostics on resource start.     |
-- |                                                                 |
-- |  Config.DebugVerbose -- table/payload dumps (chatty)            |
-- |  Config.DebugNUI     -- log every NUI message action name       |
-- |  Config.DebugEvents  -- log every net event trigger (noisy)     |
-- +-----------------------------------------------------------------+
Config.Debug        = false   -- master debug switch
Config.DebugVerbose = false   -- full NUI payload + table dumps
Config.DebugNUI     = false   -- log every SendNUIMessage action
Config.DebugEvents  = false   -- log every net event trigger

Config.MoneyType = 'bank'        -- 'cash' | 'bank'

-- ─────────────────────────────────────────────────────────────────
-- 🏎️  F1 CAR
-- ─────────────────────────────────────────────────────────────────
Config.F1CarModel  = `openwheel1`   -- model hash — change to any F1 car
Config.LiveryCount = 11             -- total liveries on the model (1 = reserved)

-- ─────────────────────────────────────────────────────────────────
-- 🏁  RACE RULES
-- ─────────────────────────────────────────────────────────────────
Config.MaxLaps            = 5
Config.MinPlayers         = 2    -- minimum on grid before race can start
Config.ResultsScreenDelay = 20   -- seconds before post-race teleport
Config.LapInvalidDist     = 40.0 -- metres off-course to flag lap as INVALID
Config.LapInvalidTime     = 6    -- consecutive seconds off-course to trigger

-- ─────────────────────────────────────────────────────────────────
-- 💰  PRIZE
-- ─────────────────────────────────────────────────────────────────
Config.PrizeMoney     = 100000   -- paid to P1 winner (ox_inventory item)
Config.PrizeItem      = 'money'

-- ─────────────────────────────────────────────────────────────────
-- 🔐  ORGANISER
-- ─────────────────────────────────────────────────────────────────
Config.OrganizerPermission = 'admin'  -- 'admin' | 'superadmin' | nil (dev mode)

-- ─────────────────────────────────────────────────────────────────
-- 🎒  ITEM SYSTEM
-- ─────────────────────────────────────────────────────────────────
Config.Items = {
    enabled   = false,
    entryItem = 'racechip',   -- consumed when a driver is gridded
}

-- ─────────────────────────────────────────────────────────────────
-- 🏆  XP & MMR  (true ELO-style: base 1500, loss scales by position)
-- ─────────────────────────────────────────────────────────────────
Config.DefaultMMR   = 1500    -- starting MMR for new players
Config.FastestLapXP = 15      -- bonus XP for fastest lap of the race

--            P1   P2   P3   P4   P5   P6   P7   P8
Config.XP  = { 100, 80, 60, 40, 25, 15,  8,  4 }

-- MMR gain per position (positive = gain, negative = loss)
-- Loss scales with field size: MmrLostBase * finishing_position
Config.MmrGain      = { 50, 35, 22, 12, 4, -4, -10, -18 }
Config.MmrLostBase  = -8     -- multiplied by position for DNF/DQ

-- History caps (stored as JSON in player row)
Config.MaxRaceHistory = 10
Config.MaxMmrHistory  = 20

-- ─────────────────────────────────────────────────────────────────
-- 🏅  ACHIEVEMENTS  (key = achievement id, must match server logic)
-- ─────────────────────────────────────────────────────────────────
Config.Achievements = {
    -- Wins
    { key='win_1',           label='First Blood',          desc='Win your first race.',              icon='🏆' },
    { key='win_5',           label='Hat-Trick Hero',       desc='Win 5 races.',                      icon='🥇' },
    { key='win_25',          label='Veteran',              desc='Win 25 races.',                     icon='🎖️'  },
    { key='win_50',          label='Champion',             desc='Win 50 races.',                     icon='👑'  },
    -- Podiums
    { key='podium_10',       label='On the Box',           desc='Reach the podium 10 times.',        icon='🥈'  },
    { key='podium_50',       label='Podium Regular',       desc='Reach the podium 50 times.',        icon='🥉'  },
    -- Races completed
    { key='races_10',        label='Rookie',               desc='Complete 10 races.',                icon='🏁'  },
    { key='races_50',        label='Experienced',          desc='Complete 50 races.',                icon='🚦'  },
    { key='races_100',       label='Veteran Driver',       desc='Complete 100 races.',               icon='🎗️'  },
    -- Fastest lap
    { key='fastest_lap_1',   label='Purple Sector',        desc='Set the fastest lap in a race.',    icon='💜'  },
    { key='fastest_lap_10',  label='Pace Setter',          desc='Set fastest lap 10 times.',         icon='⚡'  },
    -- Pit
    { key='pit_5',           label='Pit Crew',             desc='Complete 5 pit stops.',             icon='🔧'  },
    { key='pit_25',          label='Pit Master',           desc='Complete 25 pit stops.',            icon='🛞'  },
    -- Clean race (no engine damage)
    { key='clean_race_1',    label='Smooth Operator',      desc='Finish a race with no engine damage.',  icon='✅'  },
    { key='clean_race_10',   label='Machine Whisperer',    desc='10 clean races.',                   icon='🤍'  },
    -- DRS
    { key='drs_50',          label='Slipstream King',      desc='Use DRS 50 times.',                 icon='💨'  },
    -- MMR milestones
    { key='mmr_2000',        label='Rising Star',          desc='Reach 2000 MMR.',                   icon='⭐'  },
    { key='mmr_3000',        label='Elite Racer',          desc='Reach 3000 MMR.',                   icon='🌟'  },
    -- Special
    { key='hat_trick',       label='Hat Trick',            desc='Win 3 consecutive races.',          icon='🎩'  },
    { key='iron_man',        label='Iron Man',             desc='Finish without pitting (no-stop strategy).', icon='🦾' },
}

-- ─────────────────────────────────────────────────────────────────
-- 🗓️  OFFICIAL RACE SCHEDULE  (day-of-week + time triggers)
--    Leave empty table {} for a day to skip it.
--    'time' = 24h HH:MM server clock
-- ─────────────────────────────────────────────────────────────────
Config.RaceSchedule = {
    Monday    = {},
    Tuesday   = {},
    Wednesday = {},
    Thursday  = {},
    Friday    = {
        { time='20:00', laps=5, entryFee=0, prize=Config and Config.PrizeMoney or 100000 },
    },
    Saturday  = {
        { time='18:00', laps=5, entryFee=0, prize=Config and Config.PrizeMoney or 100000 },
        { time='22:00', laps=3, entryFee=0, prize=Config and Config.PrizeMoney or 100000 },
    },
    Sunday    = {
        { time='17:00', laps=7, entryFee=0, prize=Config and Config.PrizeMoney or 100000 },
    },
}

-- ─────────────────────────────────────────────────────────────────
-- 🎁  WEEKLY REWARD
-- ─────────────────────────────────────────────────────────────────
Config.WeeklyReward = {
    type  = 'money',                        -- 'money' | 'item'
    money = 50000,
    item  = { name='racechip', amount=3 },
}

-- ─────────────────────────────────────────────────────────────────
-- 👥  CREW SYSTEM
-- ─────────────────────────────────────────────────────────────────
Config.CrewSystem = {
    enabled        = true,
    createCost     = 5000,
    maxMembers     = 8,
    rewardCooldown = 10,   -- minutes
}



-- ─────────────────────────────────────────────────────────────────
-- 🧍  RACE MANAGER NPC
-- ─────────────────────────────────────────────────────────────────
Config.RaceManagerNPC = {
    enabled = true,
    coords  = vector4(1113.5, 264.0, 79.05, 237.0),
    model   = 's_m_m_security_01',
    label   = 'Race Manager',
}



-- ─────────────────────────────────────────────────────────────────
-- 🏎️  F1 BASE HANDLING
-- ─────────────────────────────────────────────────────────────────
Config.F1BaseHandling = {
    fInitialDriveForce        = 1.00,
    fDriveInertia             = 1.00,
    fDriveBiasFront           = 0.00,
    fLowSpeedTractionLossMult = 2.80,
    fInitialDragCoeff         = 25.0,
    fTractionCurveMax         = 4.80,
    fTractionCurveMin         = 2.60,
}
Config.F1BaseTopSpeed = 60.0

-- ─────────────────────────────────────────────────────────────────
-- 🔧  TIRE COMPOUNDS
-- ─────────────────────────────────────────────────────────────────
Config.TireCompounds = {
    soft = {
        label='🔴 Soft', color={210,50,50},
        laps=3, driveForce=0.12, topSpeedBonus=5.0,
        tractionMax=5.20, tractionMin=3.00,
        degradedForce=-0.20, degradedTraction=-0.60,
    },
    medium = {
        label='🟡 Medium', color={220,200,50},
        laps=6, driveForce=0.05, topSpeedBonus=2.0,
        tractionMax=4.80, tractionMin=2.60,
        degradedForce=-0.10, degradedTraction=-0.30,
    },
    hard = {
        label='⚪ Hard', color={200,200,200},
        laps=10, driveForce=0.00, topSpeedBonus=0.0,
        tractionMax=4.60, tractionMin=2.40,
        degradedForce=-0.05, degradedTraction=-0.15,
    },
}

-- ─────────────────────────────────────────────────────────────────
-- 🛞  PIT STOP
-- ─────────────────────────────────────────────────────────────────
Config.PitStop = {
    enabled      = true,
    mandatory    = true,       -- DQ at finish if no pit
    speedLimit   = 80.0,       -- km/h in pit lane
    stopDuration = 4,          -- seconds frozen during stop
    zone = {
        coords  = vector3(1125.0, 268.0, 79.05),
        size    = vector3(12.0, 6.0, 3.0),
        heading = 57.0,
    },
}

-- ─────────────────────────────────────────────────────────────────
-- ⚡  DRS ZONES
-- ─────────────────────────────────────────────────────────────────
Config.DRSZones = {
    { name='Main Straight',  entry=vec3(-1558.4,-2763.5,13.9), exit=vec3(-1844.7,-2923.6,13.9), radius=30.0 },
    { name='Back Straight',  entry=vec3(-1661.9,-2258.1,13.9), exit=vec3(-1319.4,-2392.4,13.9), radius=30.0 },
}
Config.DRS = { driveForceBoost=0.45, topSpeedBoost=15.0 }

-- ─────────────────────────────────────────────────────────────────
-- 🔥  ENGINE DAMAGE
-- ─────────────────────────────────────────────────────────────────
Config.EngineHealth = { warning=650.0, damaged=400.0, critical=200.0 }

-- ─────────────────────────────────────────────────────────────────
-- ⏱️  SECTOR DEFINITIONS
--    Sectors are defined by which checkpoint INDEX ends each sector.
--    With 10 CPs: sector 1 ends at CP3, sector 2 at CP6, sector 3 at CP10.
-- ─────────────────────────────────────────────────────────────────
Config.Sectors = {
    { endCP=3,  label='S1' },
    { endCP=6,  label='S2' },
    { endCP=10, label='S3' },
}

-- ─────────────────────────────────────────────────────────────────
-- 🧭  RACE LINE
-- ─────────────────────────────────────────────────────────────────
Config.RaceLine = { enabled=true, segments=12, maxDist=120.0 }

-- ─────────────────────────────────────────────────────────────────
-- 🚥  FORMATION LAP / SAFETY CAR
-- ─────────────────────────────────────────────────────────────────
Config.FormationLap = {
    enabled        = true,
    safetyCarModel = `police3`,
    safetyCarSpot  = vector4(-1540.0, -2745.0, 13.9, 60.0),
    maxSpeed       = 220.0,
}

-- ─────────────────────────────────────────────────────────────────
-- 📍  GRID SPOTS  (P1 = Pole)
-- ─────────────────────────────────────────────────────────────────
Config.GridSpots = {
    vector4(1111.96, 261.35, 79.05,  57.44),
    vector4(1110.13, 258.65, 79.05,  57.03),
    vector4(1108.64, 255.97, 79.05,  57.54),
    vector4(1106.91, 253.42, 79.05,  56.15),
    vector4(1112.11, 250.08, 79.05, 237.61),
    vector4(1113.83, 252.74, 79.05, 237.48),
    vector4(1115.38, 255.42, 79.05, 238.65),
    vector4(1117.07, 258.14, 79.05, 237.06),
}

-- ─────────────────────────────────────────────────────────────────
-- 🔵  CIRCUIT CHECKPOINTS  (CP 1 = Start/Finish line)
-- ─────────────────────────────────────────────────────────────────
Config.Checkpoints = {
    vector3(1169.35,  276.63, 80.91),  -- CP 1  Start/Finish ── Sector 3 end
    vector3(1173.79,  283.37, 80.23),  -- CP 2
    vector3(1226.80,  284.44, 80.11),  -- CP 3 ── Sector 1 end
    vector3(1274.62,  230.68, 80.09),  -- CP 4
    vector3(1237.41,  147.78, 80.10),  -- CP 5
    vector3(1174.44,   43.35, 80.05),  -- CP 6 ── Sector 2 end
    vector3(1105.96,  -67.85, 80.04),  -- CP 7
    vector3(1036.68,  -88.14, 80.11),  -- CP 8
    vector3( 999.51,   -0.70, 80.10),  -- CP 9
    vector3(1101.77,  170.51, 80.05),  -- CP 10 ── Sector 3 end / S/F approach
}

-- ─────────────────────────────────────────────────────────────────
-- 👁️  SPECTATOR MODE
-- ─────────────────────────────────────────────────────────────────
Config.Spectator = {
    vantagePoint    = vector4(1150.0, 220.0, 82.0, 240.0),
    showLeaderboard = true,
}

-- ─────────────────────────────────────────────────────────────────
-- 🍔  PLAYER NEEDS DURING RACE
--    Keeps stress=0, food=100, water=100 throughout the event.
-- ─────────────────────────────────────────────────────────────────
Config.RaceNeeds = {
    enabled      = true,
    intervalSecs = 30,
    stress       = 0,
    hunger       = 100,
    thirst       = 100,
}

-- ─────────────────────────────────────────────────────────────────
-- 🏠  POST-RACE TELEPORT
-- ─────────────────────────────────────────────────────────────────
Config.PostRaceLocation = vector4(1090.78, 194.97, 84.74, 239.1)

-- ─────────────────────────────────────────────────────────────────
-- 📢  DISCORD WEBHOOK
-- ─────────────────────────────────────────────────────────────────
Config.DiscordWebhook = 'YOUR_WEBHOOK_URL_HERE'
Config.WebhookBotName = 'Flame City GP'
Config.WebhookAvatar  = ''

-- ─────────────────────────────────────────────────────────────────
-- 🔔  NOTIFICATIONS
-- ─────────────────────────────────────────────────────────────────
Config.Notify = {
    noItem           = 'You need a {item} to enter.',
    notEnoughMoney   = 'Not enough money.',
    accessDenied     = 'Access denied.',
    raceWin          = '🏆 You won!  +{xp} XP  |  +{mmr} MMR',
    raceFinish       = 'P{pos} Finish  +{xp} XP  |  {mmr} MMR',
    disqualified     = '⛔ Disqualified — {reason}',
    lapComplete      = 'LAP {lap} — {time}',
    fastestLap       = '💜 FASTEST LAP — {time}  +{xp} XP bonus',
    lapInvalid       = '⚠️ Lap INVALID — track limits',
    pitEntry         = '🛞 Choose your compound',
    pitDone          = '🟢 Pit out — {tire}',
    pitMandatoryDQ   = 'No pit stop made. DQ applied.',
    weeklyReward     = '🎁 Weekly reward claimed!',
    weeklyNotReady   = 'Weekly reward in {hours}h.',
    crewCreated      = '🏁 Crew "{name}" created.',
    achievement      = '🏅 Achievement Unlocked: {label}',
    engineWarning    = '⚠️ ENGINE WARNING — 85% power',
    engineDamaged    = '🔴 ENGINE DAMAGED — 60% power',
    engineCritical   = '💀 ENGINE CRITICAL — 35% power',
    tireWorn         = '🔶 {tire} tires degrading!',
    drsOpen          = '⚡ DRS OPEN',
    sectorGreen      = '🟢 {sector} {time}',
    sectorPurple     = '💜 {sector} BEST {time}',
    sectorYellow     = '🟡 {sector} {time}',
    scheduleWarning  = '🏁 Official race starting in {mins} minutes!',
}

-- ─────────────────────────────────────────────────────────────────
-- 🔐  AUTHORIZATION
-- ─────────────────────────────────────────────────────────────────
Config.Auth = {
    enabled = false,
    codes   = { 'YOURCODE123' },
}

Config.WinXP = Config.XP[1]   -- P1 XP award (defaults to first entry in Config.XP)
