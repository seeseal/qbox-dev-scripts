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
--  SHOP ENTRANCE
--  !! CHANGE ME !! coords for the tuner shop entrance
--  Stand at the location in-game, type /coords, paste below
-- ─────────────────────────────────────────────
Config.ShopLocation = vector3(-331.35, -133.62, 38.06)
Config.ShopHeading  = 250.0   -- !! CHANGE ME !! heading the player faces when opening the menu
Config.ShopRadius   = 2.5     -- How close the player must be to use the shop (metres)

-- ─────────────────────────────────────────────
--  RAMP LOCATIONS  (vehicle pull-in detection zones)
-- ─────────────────────────────────────────────
Config.RampLocations = {
    vector3(-323.29, -132.12, 38.96),
}
Config.RampRadius = 8.0

-- ═══════════════════════════════════════════════════════════════
--  WORKSHOP BAYS  (vehicle pull-in zones)
-- ═══════════════════════════════════════════════════════════════
Config.WorkshopBays = {
    { coords = vec3(144.73, -3030.63, 5.57) },
    { coords = vector4(145.01, -3030.66, 5.66, 180.31) },
}

-- ═══════════════════════════════════════════════════════════════
--  CLOCK-IN / STASH
-- ═══════════════════════════════════════════════════════════════
Config.ClockInLocation = vector3(126.06, -3007.91, 6.04)
Config.StashLocation   = vector3(128.57, -3009.02, 6.04)

-- ═══════════════════════════════════════════════════════════════
--  CRAFTING BENCHES
-- ═══════════════════════════════════════════════════════════════
Config.CraftingLocations = {
    vector3(126.32, -3030.21, 6.06),
    vector3(124.48, -3031.73, 6.04),
    vector3(124.33, -3028.98, 6.04),
    vector3(126.78, -3029.01, 6.04),
}

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
    speedBoostPercent = 15,     -- % increase to top speed AND torque (fInitialDriveMaxFlatVel + fInitialDriveForce)
    driveInertiaBoost = 1.4,    -- multiplier for fDriveInertia (how quickly power builds — makes chip feel immediate)
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
    suspensionLevel    = 2,       -- suspension mod level (softest = best body roll)
    tractionCurveMax   = 0.30,    -- near-zero rear grip (normal ~2.73) — how easily the rear breaks loose
    tractionCurveMin   = 0.20,    -- (normal ~1.80)
    tractionLossMult   = 6.0,     -- how long and controllable slides are (normal 1.0)
    driveForceBoost    = 1.5,     -- multiply original drive force so throttle causes oversteer
    steeringLock       = 55.0,    -- wide lock for counter-steering (normal ~35)
    dragCoeff          = 8.0,     -- drag so slides slow naturally
    baseDragCoeff      = 4.0,     -- restored on removal
    antiRollForce      = 0.2,     -- low anti-roll = body leans through corners
    smokeScaleMin      = 1.5,     -- minimum smoke particle size
    smokeScaleSpeed    = 8.0,     -- divide speed by this to scale smoke (lower = more smoke sooner)
    smokeScaleRpm      = 1.5,     -- multiply rpm by this for smoke scale contribution
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
--  NITROUS  (Pressure System)
--  The tank is 0.0–1.0. Each activation drains pressureDrain.
--  Each nos_canister item adds canisterRefill.
--  minPressure is required to activate.
-- ─────────────────────────────────────────────
Config.Nitrous = {
    price          = 50000,
    installMs      = 9000,
    removeMs       = 7000,
    boostMPH       = 10,
    boostDuration  = 5,
    cooldown       = 300,        -- 5 min activation cooldown
    key            = 21,         -- LEFT SHIFT
    pressureDrain  = 0.35,       -- ~3 activations per full tank
    canisterRefill = 0.30,       -- ~3-4 canisters to go empty → full
    minPressure    = 0.10,       -- minimum pressure to be able to activate
}

-- ─────────────────────────────────────────────
--  EXHAUST MOD
-- ─────────────────────────────────────────────
Config.ExhaustMod = {
    price          = 35000,
    installMs      = 5000,
    removeMs       = 4000,
    rpmThreshold   = 0.82,
    throttleMax    = 0.04,
    backfireChance = 0.55,
    backfireScale  = 2.5,
}

-- ─────────────────────────────────────────────
--  FAKE PLATE
--  Player picks custom plate text via input dialog.
--  PD can use /scanplate near a vehicle to reveal the real one.
-- ─────────────────────────────────────────────
Config.FakePlate = {
    price     = 75000,
    installMs = 5000,
    removeMs  = 3000,
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
--  SUPPLY RUN
--  On-duty tuners use /supplyrun to collect damaged_parts
--  from a random location. These are the only crafting ingredient.
-- ─────────────────────────────────────────────
Config.SupplyRun = {
    cooldown     = 900,       -- seconds cooldown between completed runs (15 min)
    rewardMin    = 3,
    rewardMax    = 6,
    pickupRadius = 8.0,
    collectMs    = 8000,
    Locations    = {
        vector3(616.08,   -2020.38,  30.02),  -- Banning docks
        vector3(-1040.75, -2850.95,  14.17),  -- LSIA cargo bay
        vector3(512.88,   -2300.17,  29.34),  -- Elysian Island
        vector3(950.12,   -1600.87,  30.68),  -- La Mesa industrial
        vector3(183.75,   -2647.42,   6.00),  -- Terminal
        vector3(-270.95,  -2426.89,   6.00),  -- Port of LS
    },
}

-- ─────────────────────────────────────────────
--  CRAFT RECIPES  (damaged_parts only — from supply runs)
-- ─────────────────────────────────────────────
Config.CraftRecipes = {
    {
        item        = 's3_chip',
        label       = 'S3 Engine Chip',
        icon        = '🔧',
        craftMs     = 12000,
        ingredients = { { item = 'damaged_parts', amount = 4, label = 'Damaged Parts' } },
    },
    {
        item        = 'drift_chip',
        label       = 'Drift Chip',
        icon        = '🚗',
        craftMs     = 10000,
        ingredients = { { item = 'damaged_parts', amount = 3, label = 'Damaged Parts' } },
    },
    {
        item        = 'stance_rod',
        label       = 'Stance Rod',
        icon        = '📐',
        craftMs     = 8000,
        ingredients = { { item = 'damaged_parts', amount = 2, label = 'Damaged Parts' } },
    },
    {
        item        = 'nos_canister',
        label       = 'NOS Canister',
        icon        = '🚀',
        craftMs     = 8000,
        ingredients = { { item = 'damaged_parts', amount = 2, label = 'Damaged Parts' } },
    },
}
