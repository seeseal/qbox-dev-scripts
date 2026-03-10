Config = {}

-- ─────────────────────────────────────────────
--  GENERAL
-- ─────────────────────────────────────────────
Config.RequiredJob      = 'tuner'
Config.PDJob            = 'police'   -- job allowed to use /removechip
Config.PaymentType      = 'dirty_cash'
Config.ZoneRadius       = 8.0
Config.ProgressBar      = true

-- ─────────────────────────────────────────────
--  RAMP LOCATIONS  (4 workspaces inside tuner shop)
--  anyone can view prices, tuner job required to install
-- ─────────────────────────────────────────────
Config.RampLocations = {
    vector3(-323.29, -132.12, 38.96), -- ramp 1
   
}
Config.RampRadius = 8.0

-- ─────────────────────────────────────────────
--  DISCORD / LOGGING
-- ─────────────────────────────────────────────
Config.DiscordWebhook = ''   -- paste your webhook URL here; leave '' to disable
Config.DiscordColour  = 16711680  -- red

-- ─────────────────────────────────────────────
--  ENGINE CHIP
-- ─────────────────────────────────────────────
Config.EngineChip = {
    installMs          = 10000,
    removeMs           = 8000,
    speedBoostPercent  = 15,     -- % increase to fInitialDriveMaxFlatVel
    basePrice          = 250000,
    carValuePercent    = 0.30,   -- price = basePrice + (depotvalue * 30%)
}

-- ─────────────────────────────────────────────
--  DRIFT CHIP
-- ─────────────────────────────────────────────
Config.DriftChip = {
    basePrice          = 100000,
    carValuePercent    = 0.20,   -- price = basePrice + (depotvalue * 20%)
    installMs          = 6000,
    removeMs           = 5000,
    suspensionLevel    = 2,
    tractionMultiplier = 0.80,   -- traction curves scaled to 80% (20% less grip)
    tractionLossMult   = 1.60,   -- high loss multiplier = more oversteer/slide
    dragCoeff          = 8.0,    -- higher drag coeff = more tyre resistance / smoke
    baseDragCoeff      = 4.0,    -- stock value to restore on removal
}

-- ─────────────────────────────────────────────
--  STANCE KIT
-- ─────────────────────────────────────────────
Config.StanceKit = {
    price          = 50000,
    installMs      = 7000,
    removeMs       = 5000,
    camberStep     = 0.01,
    rideHeightStep = 0.005,
    camberMin      = -0.20,  camberMax     = 0.10,   -- negative = inward lean (stance look)
    rideHeightMin  = -0.085, rideHeightMax = 0.10,   -- negative = lowered
}

-- ─────────────────────────────────────────────
--  NITROUS
-- ─────────────────────────────────────────────
Config.Nitrous = {
    price         = 50000,
    refillPrice   = 25000,
    installMs     = 9000,
    removeMs      = 7000,
    boostMPH      = 10,
    boostDuration = 5,       -- seconds active
    cooldown      = 1800,    -- seconds before refill is allowed again (30 min)
    key           = 21,      -- LEFT SHIFT
}

-- ─────────────────────────────────────────────
--  NOS REFILL STATION  (dedicated location)
--  Players drive here to refill their NOS kit.
--  Set this to a spot near a garage / back alley.
-- ─────────────────────────────────────────────
Config.NosRefillStation = {
    coords   = vector3(-359.06, -122.33, 38.06),
    radius   = 6.0,
    refillMs = 5000,
}

-- ─────────────────────────────────────────────
--  NEON KITS
-- ─────────────────────────────────────────────
Config.NeonPrices = {
    static  = 25000,
    rainbow = 25000,
    rgb     = 25000,
    strobe  = 25000,
}
Config.NeonInstallMs = 4000
Config.NeonRemoveMs  = 3000

Config.NeonColours = {
    { label = 'Red',    r = 255, g = 0,   b = 0   },
    { label = 'Blue',   r = 0,   g = 0,   b = 255 },
    { label = 'Green',  r = 0,   g = 255, b = 0   },
    { label = 'Purple', r = 128, g = 0,   b = 128 },
    { label = 'Pink',   r = 255, g = 0,   b = 127 },
    { label = 'White',  r = 255, g = 255, b = 255 },
    { label = 'Yellow', r = 255, g = 255, b = 0   },
    { label = 'Orange', r = 255, g = 128, b = 0   },
    { label = 'Cyan',   r = 0,   g = 255, b = 255 },
}