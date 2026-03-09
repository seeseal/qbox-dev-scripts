-- ============================================
--  frcp_dealership | config.lua  v2.0
--  ALL custom values live here.
--  !! Lines marked CHANGE ME !! are the ones
--  you will need to update for your server.
-- ============================================

Config = {}

-- ============================================
--  Vehicle Spawn Point
--  !! CHANGE ME !! — where purchased cars appear
-- ============================================

Config.SpawnPoint = vec4(-947.67, -496.79, 35.64, 296.36)

-- ============================================
--  Tablet Stands
--  4 stands around the showroom floor.
--  Each stand spawns a prop and an ox_target
--  interaction zone. Any customer can walk up
--  and open the catalog. A purchase will only
--  go through if an on-duty employee is within
--  Config.StandEmployeeRadius metres of the
--  SAME stand at the moment of purchase.
--
--  coords  = vec4(x, y, z, heading) of the prop
--  label   = shown in ox_target prompt
--
--  !! CHANGE ME !! — set to real MLO positions
-- ============================================

Config.TabletStands = {
    [1] = { coords = vec4(-951.06, -495.1,  35.84, 224.23), label = "Browse Vehicles — Stand 1" },
    [2] = { coords = vec4(-953.00, -493.5,  35.84, 200.00), label = "Browse Vehicles — Stand 2" },
    [3] = { coords = vec4(-955.00, -495.0,  35.84, 180.00), label = "Browse Vehicles — Stand 3" },
    [4] = { coords = vec4(-953.50, -497.0,  35.84, 160.00), label = "Browse Vehicles — Stand 4" },
}

-- How close (metres) an on-duty employee must be
-- to a tablet stand for a purchase to go through.
-- 3.0 is tight (right next to it). 5.0 is relaxed.
Config.StandEmployeeRadius = 4.0   -- !! CHANGE ME if needed !!

-- ============================================
--  Dealership Info
-- ============================================

Config.DealershipName = "FlameDrive Motors"
Config.ServerName     = "FlameCity"

-- ============================================
--  JOB SYSTEM
--  JobName must match exactly what is set in
--  your Qbox job list (qbx_core/shared/jobs.lua
--  or your jobs database table)
--
--  !! CHANGE ME !! — set JobName to your exact
--  job name in Qbox, e.g. "flakedrive" or
--  "dealership". Grades must match too.
-- ============================================

Config.JobName = "flamedrive"   -- !! CHANGE ME !!

Config.JobGrades = {
    -- grade  label              boss    testdrive  sell    commission
    -- Commission = % of sale price paid to the employee on every closed deal.
    -- Trainees earn 0% — they shadow and learn.
    -- GM earns 0% commission — they withdraw directly from the society fund.
    -- No hourly pay — everyone earns purely from sales.
    [0] = { label = "Trainee",         isBoss = false, canTestDrive = true,  canSell = false, commission = 0  },
    [1] = { label = "Salesperson",     isBoss = false, canTestDrive = true,  canSell = true,  commission = 10 },
    [2] = { label = "Sales Manager",   isBoss = false, canTestDrive = true,  canSell = true,  commission = 20 },
    [3] = { label = "General Manager", isBoss = true,  canTestDrive = true,  canSell = true,  commission = 0  },
}

-- Commission math reference (for your economy):
--   Salesperson  10% on $15,000  (Bati)       = $1,500
--   Salesperson  10% on $200,000 (Oracle XS)  = $20,000
--   Sales Mgr    20% on $15,000  (Bati)       = $3,000
--   Sales Mgr    20% on $200,000 (Oracle XS)  = $40,000
--   Apex vehicles = $0 (free IC, no revenue to split)

-- ============================================
--  SOCIETY FUND
--  Every sale is automatically split.
--  SocietyPercent + TaxPercent must equal 100.
--
--  Example: price $100,000
--    → $80,000 goes to society fund
--    → $20,000 goes to GovBankAccount
--
--  GovBankAccount: the bank account name that
--  receives the tax cut. Set this to whatever
--  your government/city-hall account is called
--  in your banking script.
--  !! CHANGE ME !! if you use a banking script
-- ============================================

Config.SocietyPercent  = 80     -- % that goes into the dealership fund
Config.TaxPercent      = 20     -- % that goes to government as tax
Config.GovBankAccount  = "gov_taxes"  -- !! CHANGE ME !!

-- ============================================
--  TEST DRIVE
--  Duration: how many seconds the test drive
--  lasts before the car is automatically
--  deleted and the player is teleported back.
--
--  Radius: how far (in metres) from the
--  TestDriveStart point the player can go.
--  If they exceed this the drive ends early.
--
--  TestDriveStart: where test drive cars spawn.
--  !! CHANGE ME !! to a spot outside your MLO
-- ============================================

Config.TestDriveDuration = 300          -- seconds (300 = 5 minutes)
Config.TestDriveRadius   = 300.0        -- metres from return point before warning (!! CHANGE ME !!)
Config.TestDriveStart    = vec4(-976.52, -469.84, 35.28, 56.0)   -- !! CHANGE ME !! road near dealership
Config.TestDriveReturn   = vec3(-951.06, -495.1,  35.84)          -- !! CHANGE ME !! where player returns

-- ============================================
--  EMPLOYEE LOCATIONS
--  These are the coords for the on-duty zone,
--  stash, and changing room.
--  !! CHANGE ME !! — move these into your MLO
-- ============================================

Config.OnDutyCoords     = vec3(-948.0, -492.0, 35.84)   -- !! CHANGE ME !! clock-in/out marker
Config.StashCoords      = vec3(-950.0, -490.0, 35.84)   -- !! CHANGE ME !! shared employee stash
Config.ChangingRoomCoords = vec3(-952.0, -488.0, 35.84) -- !! CHANGE ME !! changing room marker

-- Employee outfit when on duty
-- These component IDs match GTA V ped components
-- !! CHANGE ME !! — set to your uniform/outfit
-- component: which clothing slot (3=torso, 4=legs, 6=feet, 8=shirt/undershirt, 11=jacket)
Config.EmployeeOutfit = {
    -- { component = 11, drawable = 15, texture = 0 }, -- example jacket
    -- { component = 8,  drawable = 58, texture = 0 }, -- example shirt
    -- { component = 4,  drawable = 18, texture = 0 }, -- example trousers
}
-- NOTE: If you leave Config.EmployeeOutfit empty the changing room
-- will open the ox_lib clothing menu instead (recommended until
-- you have confirmed ped component IDs for your uniform).

-- ============================================
--  STASH
--  Shared stash used by all on-duty employees.
--  slots/weight can be adjusted freely.
-- ============================================

Config.StashId      = "flamedrive_employee_stash"
Config.StashSlots   = 20
Config.StashWeight  = 100000   -- in grams (ox_inventory uses grams)

-- ============================================
--  BOSS MENU
--  Fund withdrawal: max amount boss can take
--  out in a single transaction.
-- ============================================

Config.MaxWithdrawal = 500000   -- !! CHANGE ME !! to whatever suits your economy


-- ============================================
--  SHOWROOM DISPLAY VEHICLES
--  Static vehicles placed on the showroom floor.
--  Add as many spots as you like.
--
--  coords   = vec4(x, y, z, heading) — where
--             the vehicle spawns
--  default  = model name shown on first load
--             (overridden by DB once an employee
--             changes it in the UI)
--
--  !! CHANGE ME !! — set coords to your MLO
--  showroom floor positions
-- ============================================

Config.DisplaySpots = {
    [1] = { coords = vec4(-944.59, -485.76, 35.43, 30.07),  default = "italirsx"   },
    [2] = { coords = vec4(-952.0, -493.0, 35.84, 90.0),  default = "pfister811" },
    [3] = { coords = vec4(-952.0, -495.0, 35.84, 90.0),  default = "toreoxo"    },
    [4] = { coords = vec4(-955.0, -491.0, 35.84, 270.0), default = "exemplar"   },
    [5] = { coords = vec4(-955.0, -493.0, 35.84, 270.0), default = "oraclexs"   },
    [6] = { coords = vec4(-955.0, -495.0, 35.84, 270.0), default = "elegy"      },
}

-- Minimum grade required to change a display vehicle
-- 0 = any employee, 1 = Salesperson+, 2 = Sales Manager+, 3 = GM only
Config.DisplayChangeMinGrade = 0   -- any on-duty employee

-- ============================================
--  Tier Definitions  (unchanged from v1)
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
--  Vehicle Catalog  (unchanged from v1)
-- ============================================

Config.Vehicles = {

    -- ══════════════════════════════════════════
    --  STANDARD TIER
    --  Cash only. No ticket required.
    -- ══════════════════════════════════════════

    -- Sedans
    { label="Sentinel",              model="sentinel",      tier="standard", price=25000,  limit=-1, category="Sedans",      description="A reliable everyday sedan." },
    { label="Tailgater S",           model="tailgater2",    tier="standard", price=38000,  limit=-1, category="Sedans",      description="Executive luxury meets daily practicality." },
    { label="Schafter V12",          model="schafter3",     tier="standard", price=55000,  limit=-1, category="Sedans",      description="A powerful four-door with sport credentials." },

    -- Sports
    { label="Sultan",                model="sultan",        tier="standard", price=35000,  limit=-1, category="Sports",      description="A popular sports car for city driving." },
    { label="Elegy RH8",             model="elegy",         tier="standard", price=48000,  limit=-1, category="Sports",      description="Inspired by Japanese performance culture." },
    { label="Banshee",               model="banshee",       tier="standard", price=62000,  limit=-1, category="Sports",      description="Two-seat muscle machine with raw power." },

    -- SUVs
    { label="Granger",               model="granger",       tier="standard", price=45000,  limit=-1, category="SUVs",        description="A sturdy full-size SUV." },
    { label="Cavalcade",             model="cavalcade",     tier="standard", price=40000,  limit=-1, category="SUVs",        description="Premium American full-size SUV." },
    { label="Radius",                model="radius",        tier="standard", price=52000,  limit=-1, category="SUVs",        description="Compact crossover with modern styling." },

    -- Trucks
    { label="Rumpo",                 model="rumpo",         tier="standard", price=20000,  limit=-1, category="Trucks",      description="A practical van for everyday use." },
    { label="Bobcat XL",             model="bobcatxl",      tier="standard", price=28000,  limit=-1, category="Trucks",      description="Heavy-duty pickup for work and play." },
    { label="Sandking SWB",          model="sandking2",     tier="standard", price=42000,  limit=-1, category="Trucks",      description="Short wheelbase monster truck." },

    -- Motorcycles
    { label="Bati 801",              model="bati",          tier="standard", price=15000,  limit=-1, category="Motorcycles", description="A fast and agile motorcycle." },
    { label="Akuma",                 model="akuma",         tier="standard", price=18000,  limit=-1, category="Motorcycles", description="Lightweight Japanese superbike." },
    { label="Hexer",                 model="hexer",         tier="standard", price=22000,  limit=-1, category="Motorcycles", description="Touring cruiser built for long runs." },

    -- ══════════════════════════════════════════
    --  ELITE TIER
    --  Requires Elite Ticket + cash payment.
    -- ══════════════════════════════════════════

    -- Sports
    { label="Dewbauchee Exemplar",   model="exemplar",      tier="elite",    price=180000, limit=20, category="Sports",      description="An imported luxury sports coupe." },
    { label="Ocelot Jackal",         model="jackal",        tier="elite",    price=155000, limit=20, category="Sports",      description="Sleek and refined. Built for the road." },
    { label="Übermacht Sentinel XS", model="sentinelxs",    tier="elite",    price=165000, limit=20, category="Sports",      description="Sport-tuned version of a modern icon." },
    { label="Vapid Flash GT",        model="flashgt",       tier="elite",    price=175000, limit=15, category="Sports",      description="American muscle wrapped in European style." },

    -- SUVs
    { label="Übermacht Oracle XS",   model="oraclexs",      tier="elite",    price=200000, limit=15, category="SUVs",        description="Premium imported SUV with full luxury spec." },
    { label="Gallivanter Baller ST", model="baller6",       tier="elite",    price=188000, limit=15, category="SUVs",        description="The preferred SUV of the city elite." },

    -- Motorcycles
    { label="Pegassi Reaper",        model="reaper",        tier="elite",    price=145000, limit=20, category="Motorcycles", description="Italian engineering meets raw performance." },
    { label="Shitzu Hakuchou",       model="hakuchou",      tier="elite",    price=120000, limit=20, category="Motorcycles", description="A precision instrument for the open road." },

    -- Sedans
    { label="Enus Cognoscenti 55",   model="cognoscenti2",  tier="elite",    price=210000, limit=15, category="Sedans",      description="Hand-built British luxury saloon." },

    -- ══════════════════════════════════════════
    --  APEX TIER
    --  Requires Apex Ticket. No cash cost IC.
    --  Server-wide supply limits enforced.
    -- ══════════════════════════════════════════

    -- Supercars
    { label="Grotti Itali RSX",      model="italirsx",      tier="apex",     price=0,      limit=10, category="Supercars",   description="The pinnacle of Italian engineering." },
    { label="Pegassi Torero XO",     model="toreoxo",       tier="apex",     price=0,      limit=8,  category="Supercars",   description="A hypercar built for those who demand the best." },
    { label="Pfister 811",           model="pfister811",    tier="apex",     price=0,      limit=5,  category="Supercars",   description="German precision. Server-wide limit of 5 units." },
    { label="Overflod Tyrant",       model="tyrant",        tier="apex",     price=0,      limit=6,  category="Supercars",   description="Scandinavian hypercar. Rarer than rare." },
    { label="Truffade Thrax",        model="thrax",         tier="apex",     price=0,      limit=6,  category="Supercars",   description="French hypercar engineering at its finest." },
    { label="Pegassi Zorrusso",      model="zorrusso",      tier="apex",     price=0,      limit=8,  category="Supercars",   description="A supercar forged from obsession." },

    -- Motorcycles (Apex)
    { label="Pegassi Oppressor",     model="oppressor",     tier="apex",     price=0,      limit=10, category="Motorcycles", description="The most wanted bike in Los Santos." },
}

Config.Categories = { "Sedans", "Sports", "SUVs", "Supercars", "Motorcycles", "Trucks" }

Config.Notifications = {
    noTicket        = "You need a {tier} Ticket to purchase this vehicle.",
    noMoney         = "You do not have enough money. Required: ${price}",
    limitReached    = "This vehicle has reached its server-wide limit.",
    purchaseSuccess = "You are now the owner of a {label}. Drive it out and save it in any garage.",
    alreadyOwned    = "You already own this vehicle.",
}
