Config = {}

Config.F1CarModel = `br8` -- The locked model for the event
Config.MaxLaps = 5
Config.PrizeMoney = 75000 
Config.WebhookChannel = "general" 

Config.MaxOffTrackDistance = 25.0 
Config.MinEngineHealth = 900.0 -- 1000 is perfect, 900 is light smoke/damage

-- Grid Positions (X, Y, Z, Heading)
-- IMPORTANT: Use /coords in-game to fill these for your specific starting line
Config.GridSpots = {
    vector4(143.0, -3000.0, 6.0, 270.0), -- Pole Position
    vector4(140.0, -3005.0, 6.0, 270.0), -- P2
    vector4(143.0, -3010.0, 6.0, 270.0), -- P3
    vector4(140.0, -3015.0, 6.0, 270.0), -- P4
    -- Add as many spots as you expect players
}

-- The Roadmap (Checkpoints)
Config.Checkpoints = {
    vec3(150.0, -3000.0, 6.0), 
    vec3(100.0, -2900.0, 6.0), 
    vec3(50.0, -2800.0, 6.0),  
}