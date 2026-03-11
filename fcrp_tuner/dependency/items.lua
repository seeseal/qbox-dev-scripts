-- ══════════════════════════════════════════════════════════════
--  fcrp_tuner  |  dependency/items.lua
--  Add these entries into your ox_inventory items.lua
--  (typically: resources/ox_inventory/data/items.lua)
--  Images go into: ox_inventory/web/images/
-- ══════════════════════════════════════════════════════════════

-- ─── CHIPS (consumed on install, crafted by Tuner II+) ────────

['s3_chip'] = {
    label       = 'S3 Engine Chip',
    weight      = 500,
    stack       = false,
    close       = true,
    description = 'An illegal performance chip. Boosts vehicle top speed by 15%.',
    image       = 's3_chip',
},

['drift_chip'] = {
    label       = 'Drift Chip',
    weight      = 500,
    stack       = false,
    close       = true,
    description = 'Reduces traction and increases tyre slip. Makes any car drift.',
    image       = 'drift_chip',
},

['stance_rod'] = {
    label       = 'Stance Rod',
    weight      = 800,
    stack       = false,
    close       = true,
    description = 'Adjustable suspension rod for tuning camber and ride height.',
    image       = 'stance_rod',
},

-- ─── CONSUMABLE (refills NOS kit in vehicle) ──────────────────

['nos_canister'] = {
    label       = 'NOS Canister',
    weight      = 1200,
    stack       = true,
    close       = true,
    description = 'Pressurised nitrous oxide. Use while seated in a vehicle to refill its NOS kit.',
    image       = 'nos_canister',
    -- ox_inventory usable item — register server-side in fcrp_tuner
    -- TriggerClientEvent('fcrp_tuner:client:useNosCanister') is fired via ox_inventory:useItem
},

-- ─── CRAFTING INGREDIENTS ─────────────────────────────────────

['electronic_parts'] = {
    label       = 'Electronic Parts',
    weight      = 300,
    stack       = true,
    close       = false,
    description = 'Various circuit boards and components used in chip fabrication.',
    image       = 'electronic_parts',
},

['metal_scrap'] = {
    label       = 'Metal Scrap',
    weight      = 600,
    stack       = true,
    close       = false,
    description = 'Salvaged metal pieces. Used in stance rods and NOS canisters.',
    image       = 'metal_scrap',
},

['rubber'] = {
    label       = 'Rubber',
    weight      = 400,
    stack       = true,
    close       = false,
    description = 'High-grade rubber compound used in drift chip assembly.',
    image       = 'rubber',
},

['compressed_gas'] = {
    label       = 'Compressed Gas',
    weight      = 900,
    stack       = true,
    close       = false,
    description = 'Pressurised gas cylinder. Needed to fill NOS canisters.',
    image       = 'compressed_gas',
},

-- ─── PAYMENT ──────────────────────────────────────────────────
--  dirty_cash is likely already in your items.lua.
--  Only add this if it is missing.

-- ['dirty_cash'] = {
--     label       = 'Dirty Cash',
--     weight      = 0,
--     stack       = true,
--     close       = false,
--     description = 'Untraceable cash. Used to pay for illegal services.',
--     image       = 'dirty_cash',
-- },
