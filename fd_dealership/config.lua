-- ============================================
--  fd_dealership | config.lua
--  All vehicles, prices, and settings live here
--  Devs never need to touch server.lua or client.lua
--  just to add or change vehicles
-- ============================================

Config = {}

-- ============================================
--  Dealership Location
--  Change these coords once MLO is purchased
-- ============================================

Config.Location = vector3(0.0, 0.0, 0.0)
Config.Heading  = 0.0

-- ============================================
--  Dealership Info
-- ============================================

Config.DealershipName = "FlameDrive Motors"
Config.ServerName     = "FlamCity"

-- ============================================
--  Tier Definitions
--  These control what each tier requires
-- ============================================

Config.Tiers = {
    standard = {
        label       = "Standard",
        requiresTicket = false,
        ticketType  = nil,
        requiresMoney  = true,
        color       = "#E87B35", -- orange
    },
    elite = {
        label       = "Elite",
        requiresTicket = true,
        ticketType  = "elite",
        requiresMoney  = true,
        color       = "#4A90D9", -- blue
    },
    apex = {
        label       = "Apex",
        requiresTicket = true,
        ticketType  = "apex",
        requiresMoney  = false, -- apex is free IC
        color       = "#C0392B", -- red
    },
}

-- ============================================
--  Vehicle Catalog
--  Each vehicle needs:
--    label       = display name in UI
--    model       = spawn code (must match vehicle in server)
--    tier        = "standard" / "elite" / "apex"
--    price       = IC price (0 for apex)
--    limit       = max units server-wide (-1 = unlimited)
--    description = short line shown in UI
--    category    = "Sedans" / "Sports" / "SUVs" / "Supercars" / "Motorcycles" / "Trucks"
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
        label       = "Übermacht Oracle XS",
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
        description = "The pinnacle of Italian engineering. Rare and exclusive.",
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
--  Categories shown in UI — controls display order
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
--  Notifications
-- ============================================

Config.Notifications = {
    noTicket        = "You need a {tier} Ticket to purchase this vehicle.",
    noMoney         = "You do not have enough money. Required: ${price}",
    limitReached    = "This vehicle has reached its server-wide limit and is no longer available.",
    purchaseSuccess = "You are now the owner of a {label}. Check your garage.",
    alreadyOwned    = "You already own this vehicle.",
}
```

---

**Save both files and push to GitHub.**

Commit message:
```
add fd_dealership fxmanifest and config