Config = {}

Config.F1CarModel  = `openwheel1`
Config.MaxLaps     = 1
Config.PrizeMoney  = 75000
Config.WebhookChannel = "race_logs"

Config.MaxOffTrackDistance = 60.0
Config.MinEngineHealth     = 850.0

-- GRID: Main Runway (South Side, facing West)
Config.GridSpots = {
    vector4(-1558.4, -2763.5, 13.9, 240.0), -- Pole
    vector4(-1562.1, -2767.8, 13.9, 240.0), -- P2
    vector4(-1568.5, -2771.6, 13.9, 240.0), -- P3
    vector4(-1572.6, -2776.2, 13.9, 240.0), -- P4
}

-- Spectator / DQ teleport location
Config.DQLocation = vec3(-1514.8, -2729.1, 13.9)

-- Checkpoint marker type drawn in the race loop
-- 42 = tall cylinder (used for the outer glow)
-- 1  = flat ring     (used for the inner eye-level ring)
-- Both are drawn in code; this value is kept for reference only.
Config.FinishHologram = 42

-- CIRCUIT: Loop around LSIA runways
-- Each vec3 is the CENTRE of a drive-through gate.
-- Trigger radius is 15 m (set in client/main.lua).
Config.Checkpoints = {
    vec3(-1558.4, -2763.5, 13.9), -- CP 1: Start / Finish line
    vec3(-1844.7, -2923.6, 13.9), -- CP 2: End of Runway 1
    vec3(-1445.6, -2661.1, 13.9), -- CP 8: Final Straight back to S/F
}
