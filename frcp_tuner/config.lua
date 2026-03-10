-- ============================================================
--  frcp_tuner  |  config.lua
--  🔧 CUSTOM INPUTS — everything marked !! CHANGE ME !!
-- ============================================================

Config = {}

-- !! CHANGE ME !! coords for the tuner shop entrance
-- Stand at the location in-game, type /coords, paste below
Config.ShopLocation = vector3(-331.35, -133.62, 38.06)

-- !! CHANGE ME !! heading the player faces when opening the menu
Config.ShopHeading  = 250.0

-- How close the player must be to use the shop (metres)
Config.ShopRadius   = 2.5

-- !! CHANGE ME !! job name that can operate this shop
-- This is the job your in-game 'tuner' mechanic character will have
Config.RequiredJob  = 'tuner'

-- !! CHANGE ME !! police job that can use /removechip
Config.PDJob        = 'police'

-- Payment item — must match the ox_inventory item name for black money
-- Default Qbox item is 'black_money' — change only if yours differs
Config.PaymentItem  = 'black_money'

-- ============================================================
--  ENGINE CHIP
-- ============================================================
Config.EngineChip = {
    BasePrice      = 250000,    -- flat base cost in black_money
    DepotMultiplier = 0.30,     -- 30% of the vehicle's depot value added on top
    SpeedBoost     = 15.0,      -- MPH added to top speed
}

-- ============================================================
--  DRIFT CHIP  (mutually exclusive with engine chip)
-- ============================================================
Config.DriftChip = {
    Price          = 120000,
    Suspension     = 0.35,   -- GTA suspension value (lower = softer)
    TractionLoss   = 0.85,   -- higher = more slide
}

-- ============================================================
--  STANCE KIT
-- ============================================================
Config.StanceKit = {
    Price       = 80000,
    -- Adjustment step per arrow-key press
    CamberStep  = 0.005,
    HeightStep  = 0.01,
    WidthStep   = 0.005,
}

-- ============================================================
--  NITROUS KIT
-- ============================================================
Config.NitrousKit = {
    Price        = 95000,
    SpeedBurst   = 10.0,     -- MPH boost while active
    Duration     = 10,       -- seconds the boost lasts
    Cooldown     = 1800,     -- seconds before next use (30 min)
    Key          = 'LSHIFT', -- keyboard key that fires the nitrous
}

-- ============================================================
--  NEON KITS
-- ============================================================
Config.NeonKit = {
    Price  = 45000,
    Modes  = { 'Static', 'RGB', 'Rainbow', 'Strobe' },
    -- Default static colour (R, G, B)
    DefaultColour = { r = 128, g = 0, b = 255 },
    StrobeInterval = 500, -- ms between strobe flashes
}

-- ============================================================
--  PROGRESS BAR durations (milliseconds)
-- ============================================================
Config.ProgressDurations = {
    EngineChip  = 15000,
    DriftChip   = 12000,
    StanceKit   = 10000,
    NitrousKit  = 8000,
    NeonKit     = 6000,
    Remove      = 8000,
}

-- ============================================================
--  BLIP on map for the tuner shop
-- ============================================================
Config.Blip = {
    Sprite  = 566,           -- wrench icon
    Colour  = 5,             -- yellow
    Scale   = 0.8,
    Label   = 'Tuner Shop',
    Display = 4,
    Short   = true,
}
