Config = {}

-- ─────────────────────────────────────────────
--  GENERAL
-- ─────────────────────────────────────────────
Config.RequiredJob  = 'tuner'
Config.PDJob        = 'police'
Config.PaymentType  = 'dirty_cash'
Config.ProgressBar  = true

-- ─────────────────────────────────────────────
--  JOB GRADES
--  grade level matches the grade set in qbx_core jobs
-- ─────────────────────────────────────────────
Config.JobGrades = {
    [0] = { label = 'Tuner I',      commission = 0.20, canCraft = false, isOwner = false },
    [1] = { label = 'Tuner II',     commission = 0.30, canCraft = true,  isOwner = false },
    [2] = { label = 'Master Tuner', commission = 0.30, canCraft = true,  isOwner = true  },
}

-- ─────────────────────────────────────────────
--  VEHICLE BLACKLIST
--  Class IDs: 13=cycles 14=boats 15=helis 16=planes 18=emergency 19=military 21=trains
-- ─────────────────────────────────────────────
Config.BlacklistedVehicleClasses = { 13, 14, 15, 16, 18, 19, 21 }
Config.BlacklistedVehicles       = { 'police', 'police2', 'police3', 'sheriff', 'ambulance', 'firetruk' }

-- ─────────────────────────────────────────────
--  RAMP LOCATIONS
-- ─────────────────────────────────────────────
Config.RampLocations = {
    vector3(-323.29, -132.12, 38.96),
}
Config.RampRadius = 8.0

-- ─────────────────────────────────────────────
--  DISCORD / LOGGING
-- ─────────────────────────────────────────────
Config.DiscordWebhook = ''
Config.DiscordColour  = 16711680

-- ─────────────────────────────────────────────
--  ENGINE CHIP
-- ─────────────────────────────────────────────
Config.EngineChip = {
    installMs         = 10000,
    removeMs          = 8000,
    speedBoostPercent = 15,
    basePrice         = 250000,
    carValuePercent   = 0.30,
}

-- ─────────────────────────────────────────────
--  DRIFT CHIP
-- ─────────────────────────────────────────────
Config.DriftChip = {
    basePrice          = 100000,
    carValuePercent    = 0.20,
    installMs          = 6000,
    removeMs           = 5000,
    suspensionLevel    = 2,
    tractionMultiplier = 0.80,
    tractionLossMult   = 1.60,
    dragCoeff          = 8.0,
    baseDragCoeff      = 4.0,
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
    camberMin      = -0.20,  camberMax     = 0.10,
    rideHeightMin  = -0.085, rideHeightMax = 0.10,
}

-- ─────────────────────────────────────────────
--  NITROUS
--  Cooldown = activation cooldown only (5 min).
--  Refill is done with a nos_canister item — no station zone.
-- ─────────────────────────────────────────────
Config.Nitrous = {
    price         = 50000,
    installMs     = 9000,
    removeMs      = 7000,
    boostMPH      = 10,
    boostDuration = 5,
    cooldown      = 300,   -- 5 min activation cooldown
    key           = 21,    -- LEFT SHIFT
}

-- ─────────────────────────────────────────────
--  EXHAUST MOD
--  Anti-lag backfire flames on throttle lift at high RPM.
-- ─────────────────────────────────────────────
Config.ExhaustMod = {
    price          = 35000,
    installMs      = 5000,
    removeMs       = 4000,
    rpmThreshold   = 0.82,  -- RPM fraction to arm backfire
    throttleMax    = 0.04,  -- throttle below this = released
    backfireChance = 0.55,  -- not every lift fires (0.0-1.0)
    backfireScale  = 2.5,
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

-- ─────────────────────────────────────────────
--  CRAFT RECIPES  (Tuner II + Master Tuner only)
-- ─────────────────────────────────────────────
Config.CraftRecipes = {
    {
        item        = 's3_chip',
        label       = 'S3 Engine Chip',
        icon        = '🔧',
        craftMs     = 12000,
        ingredients = {
            { item = 'electronic_parts', amount = 3, label = 'Electronic Parts' },
            { item = 'metal_scrap',      amount = 2, label = 'Metal Scrap'       },
        },
    },
    {
        item        = 'drift_chip',
        label       = 'Drift Chip',
        icon        = '🚗',
        craftMs     = 10000,
        ingredients = {
            { item = 'electronic_parts', amount = 2, label = 'Electronic Parts' },
            { item = 'rubber',           amount = 2, label = 'Rubber'            },
        },
    },
    {
        item        = 'stance_rod',
        label       = 'Stance Rod',
        icon        = '📐',
        craftMs     = 8000,
        ingredients = {
            { item = 'metal_scrap', amount = 3, label = 'Metal Scrap' },
        },
    },
    {
        item        = 'nos_canister',
        label       = 'NOS Canister',
        icon        = '🚀',
        craftMs     = 8000,
        ingredients = {
            { item = 'compressed_gas', amount = 2, label = 'Compressed Gas' },
            { item = 'metal_scrap',    amount = 1, label = 'Metal Scrap'    },
        },
    },
}
