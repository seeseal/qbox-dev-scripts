Lang = {}

local _strings = {
    -- General
    cancelled              = 'Installation cancelled.',
    transaction_failed     = 'Transaction failed.',
    ramp_no_vehicle        = 'You must be the driver of a vehicle.',
    vehicle_blacklisted    = 'This vehicle cannot be modified here.',

    -- Engine Chip
    engine_chip_installed  = 'Engine chip installed! +%s%% top speed.',
    engine_chip_removed    = 'Engine chip removed.',

    -- Drift Chip
    drift_chip_installed   = 'Drift chip installed!',
    drift_chip_removed     = 'Drift chip removed.',

    -- Stance Kit
    stance_installed       = 'Stance kit installed.',
    stance_saved           = 'Stance saved.',
    stance_cancelled       = 'Stance changes cancelled.',
    stance_removed         = 'Stance kit removed.',

    -- Nitrous
    nos_installed          = 'Nitrous kit installed! Press LEFT SHIFT in a vehicle to activate.',
    nos_activated          = '🚀 NOS Activated!',
    nos_empty              = 'NOS empty! Use a NOS Canister item to refill.',
    nos_refilled           = '✅ NOS refilled!',
    nos_not_installed      = 'No NOS kit installed on this vehicle.',
    nos_removed            = 'NOS kit removed.',

    -- Exhaust
    exhaust_installed      = 'Exhaust mod installed! 🔥',
    exhaust_removed        = 'Exhaust mod removed.',

    -- Neon
    neon_installed         = 'Neon lighting installed!',
    neon_removed           = 'Neon lighting removed.',

    -- Craft
    craft_no_permission    = 'You need to be Tuner II or higher to craft.',
    craft_missing_items    = 'Missing ingredients.',
}

function Lang:t(key, args)
    local str = _strings[key]
    if not str then return '[missing: ' .. tostring(key) .. ']' end
    if args then return string.format(str, table.unpack(args)) end
    return str
end
