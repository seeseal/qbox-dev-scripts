Config = {}

Config.F1CarModel  = `openwheel1`
Config.MaxLaps     = 5
Config.PrizeMoney  = 100000

-- Discord webhook
Config.DiscordWebhook  = "https://discord.com/api/webhooks/1480786531856945152/SqQ3Cwjp4D-uzt6vF13uUT_sauoXrfz73hdUCMa4vMq52_zHL5rcmFmUcigS-7y5iskm"
Config.WebhookBotName  = "Flame City GP"
Config.WebhookAvatar   = ""

-- Permission: "admin" | "superadmin" | nil (nil = no check, testing mode)
Config.OrganizerPermission = "admin"

-- Post-race spectator area
Config.PostRaceLocation = vec4(1090.78, 194.97, 84.74, 239.1)

-- How long (seconds) the results screen stays up before teleporting
Config.ResultsScreenDelay = 18

-- ── Engine damage thresholds ───────────────────────────────────────────────
Config.EngineHealth = {
    warning  = 650.0,
    damaged  = 400.0,
    critical = 200.0,
}

-- ── DRS Zones ─────────────────────────────────────────────────────────────
Config.DRSZones = {
    {
        name   = "Main Straight",
        entry  = vec3(-1558.4, -2763.5, 13.9),
        exit   = vec3(-1844.7, -2923.6, 13.9),
        radius = 30.0,
    },
    {
        name   = "Back Straight",
        entry  = vec3(-1661.9, -2258.1, 13.9),
        exit   = vec3(-1319.4, -2392.4, 13.9),
        radius = 30.0,
    },
}

-- DRS performance boost values
Config.DRS = {
    driveForceBoost = 0.45,
    topSpeedBoost   = 15.0,
}

-- ── Formation lap ─────────────────────────────────────────────────────────
Config.FormationLap = {
    enabled        = true,
    safetyCarModel = `police3`,
    safetyCarSpot  = vector4(-1540.0, -2745.0, 13.9, 60.0),
    maxSpeed       = 220.0,  -- km/h — fast enough to feel like a real SC lap
}

-- ── Grid spots ────────────────────────────────────────────────────────────
-- Supports up to 8 drivers. Add/remove rows as needed.
Config.GridSpots = {
    vec4(1111.96, 261.35, 79.05, 57.44), -- P1 Pole
    vec4(1110.13, 258.65, 79.05, 57.03), -- P2
    vec4(1108.64, 255.97, 79.05, 57.54), -- P3
    vec4(1106.91, 253.42, 79.05, 56.15), -- P4
    vec4(1112.11, 250.08, 79.05, 237.61), -- P5
    vec4(1113.83, 252.74, 79.05, 237.48), -- P6
    vec4(1115.38, 255.42, 79.05, 238.65), -- P7
    vec4(1117.07, 258.14, 79.05, 237.06), -- P8
}

-- ── Circuit checkpoints ───────────────────────────────────────────────────
-- CP 1 = Start/Finish (Marker 4). All others = Marker 1.
Config.Checkpoints = {
    vec3(1169.35, 276.63, 80.91), -- CP 1: Start / Finish
    vec3(1173.79, 283.37, 80.23), -- CP 2: End of Runway 1
    vec3(1226.8, 284.44, 80.11),
    vec3(1274.62, 230.68, 80.09),
    vec3(1237.41, 147.78, 80.1),
    vec3(1174.44, 43.35, 80.05),
    vec3(1105.96, -67.85, 80.04),
    vec3(1036.68, -88.14, 80.11),
    vec3(999.51, -0.7, 80.1),
    vec3(1101.77, 170.51, 80.05), -- CP 3: Final Straight
}
