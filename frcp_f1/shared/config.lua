Config = {}

Config.F1CarModel  = `openwheel1`
Config.MaxLaps     = 1
Config.PrizeMoney  = 1000

-- Discord webhook
Config.DiscordWebhook  = "https://discord.com/api/webhooks/1480786531856945152/SqQ3Cwjp4D-uzt6vF13uUT_sauoXrfz73hdUCMa4vMq52_zHL5rcmFmUcigS-7y5iskm"
Config.WebhookBotName  = "Flame City GP"
Config.WebhookAvatar   = ""

-- Permission: "admin" | "superadmin" | nil (nil = no check, testing mode)
Config.OrganizerPermission = "admin"

-- Post-race spectator area
Config.PostRaceLocation = vec3(-1514.8, -2729.1, 13.9)

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
    maxSpeed       = 160.0,  -- km/h — fast enough to feel like a real SC lap
}

-- ── Grid spots ────────────────────────────────────────────────────────────
-- Supports up to 8 drivers. Add/remove rows as needed.
Config.GridSpots = {
    vector4(-1558.4, -2763.5, 13.9, 240.0), -- P1 Pole
    vector4(-1562.1, -2767.8, 13.9, 240.0), -- P2
    vector4(-1568.5, -2771.6, 13.9, 240.0), -- P3
    vector4(-1572.6, -2776.2, 13.9, 240.0), -- P4
    vector4(-1576.8, -2780.5, 13.9, 240.0), -- P5
    vector4(-1580.9, -2784.9, 13.9, 240.0), -- P6
    vector4(-1585.1, -2789.3, 13.9, 240.0), -- P7
    vector4(-1589.3, -2793.7, 13.9, 240.0), -- P8
}

-- ── Circuit checkpoints ───────────────────────────────────────────────────
-- CP 1 = Start/Finish (Marker 4). All others = Marker 1.
Config.Checkpoints = {
    vec3(-1558.4, -2763.5, 13.9), -- CP 1: Start / Finish
    vec3(-1844.7, -2923.6, 13.9), -- CP 2: End of Runway 1
    vec3(-1445.6, -2661.1, 13.9), -- CP 3: Final Straight
}
