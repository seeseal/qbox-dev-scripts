-- ============================================
--  fd_dealership | config.lua
--  All vehicles, prices, and settings live here
-- ============================================

Config = {}

-- ============================================
--  Dealership Location & Spawn
--  Update these once MLO is purchased
-- ============================================

Config.Location   = vec4(-951.06, -495.1, 35.84, 224.23)
Config.SpawnPoint = vec4(-947.67, -496.79, 35.64, 296.36)

-- ============================================
--  Dealership Info
-- ============================================

Config.DealershipName = "FlameDrive Motors"
Config.ServerName     = "FlameCity"

-- ============================================
--  Tier Definitions
-- ============================================

Config.Tiers = {
    standard = {
        label          = "Standard",
        requiresTicket = false,
        ticketType     = nil,
        requiresMoney  = true,
        color          = "#4CAF50",
    },
    elite = {
        label          = "Elite",
        requiresTicket = true,
        ticketType     = "elite",
        requiresMoney  = true,
        color          = "#3A7BD5",
    },
    apex = {
        label          = "Apex",
        requiresTicket = true,
        ticketType     = "apex",
        requiresMoney  = false,
        color          = "#7B2FBE",
    },
}

-- ============================================
--  Vehicle Catalog
--  label       = display name in UI
--  model       = spawn code
--  tier        = "standard" / "elite" / "apex"
--  price       = IC price (0 for apex)
--  limit       = max units server-wide (-1 = unlimited)
--  category    = display category
--  description = short line shown in UI
-- ============================================

Config.Vehicles = {

    -- ----------------------------------------
    --  STANDARD TIER
    -- ----------------------------------------
    {
        label       = "Sentinel",
        model       = "sentinel",
        tier        = "standard",
        price       = 25000,
        limit       = -1,
        category    = "Sedans",
        description = "A reliable everyday sedan.",
    },
    {
        label       = "Sultan",
        model       = "sultan",
        tier        = "standard",
        price       = 35000,
        limit       = -1,
        category    = "Sports",
        description = "A popular sports car for city driving.",
    },
    {
        label       = "Granger",
        model       = "granger",
        tier        = "standard",
        price       = 45000,
        limit       = -1,
        category    = "SUVs",
        description = "A sturdy full-size SUV.",
    },
    {
        label       = "Rumpo",
        model       = "rumpo",
        tier        = "standard",
        price       = 20000,
        limit       = -1,
        category    = "Trucks",
        description = "A practical van for everyday use.",
    },
    {
        label       = "Bati 801",
        model       = "bati",
        tier        = "standard",
        price       = 15000,
        limit       = -1,
        category    = "Motorcycles",
        description = "A fast and agile motorcycle.",
    },

    -- ----------------------------------------
    --  ELITE TIER
    -- ----------------------------------------
    {
        label       = "Dewbauchee Exemplar",
        model       = "exemplar",
        tier        = "elite",
        price       = 180000,
        limit       = 20,
        category    = "Sports",
        description = "An imported luxury sports coupe.",
    },
    {
        label       = "Ocelot Jackal",
        model       = "jackal",
        tier        = "elite",
        price       = 155000,
        limit       = 20,
        category    = "Sports",
        description = "Sleek and refined. Built for the road.",
    },
    {
        label       = "Ubermacht Oracle XS",
        model       = "oraclexs",
        tier        = "elite",
        price       = 200000,
        limit       = 15,
        category    = "SUVs",
        description = "Premium imported SUV with full luxury spec.",
    },

    -- ----------------------------------------
    --  APEX TIER
    -- ----------------------------------------
    {
        label       = "Grotti Itali RSX",
        model       = "italirsx",
        tier        = "apex",
        price       = 0,
        limit       = 10,
        category    = "Supercars",
        description = "The pinnacle of Italian engineering.",
    },
    {
        label       = "Pegassi Torero XO",
        model       = "toreoxo",
        tier        = "apex",
        price       = 0,
        limit       = 8,
        category    = "Supercars",
        description = "A hypercar built for those who demand the best.",
    },
    {
        label       = "Pfister 811",
        model       = "pfister811",
        tier        = "apex",
        price       = 0,
        limit       = 5,
        category    = "Supercars",
        description = "German precision. Server-wide limit of 5 units.",
    },
}

-- ============================================
--  Categories — controls display order in UI
-- ============================================

Config.Categories = {
    "Sedans",
    "Sports",
    "SUVs",
    "Supercars",
    "Motorcycles",
    "Trucks",
}

-- ============================================
--  Notification Messages
-- ============================================

Config.Notifications = {
    noTicket        = "You need a {tier} Ticket to purchase this vehicle.",
    noMoney         = "You do not have enough money. Required: ${price}",
    limitReached    = "This vehicle has reached its server-wide limit.",
    purchaseSuccess = "You are now the owner of a {label}. Drive it out and save it in any garage.",
    alreadyOwned    = "You already own this vehicle.",
}