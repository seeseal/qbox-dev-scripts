Lang = {}

local _strings = {
    -- General
    cancelled              = 'Installation cancelled.',
    transaction_failed     = 'Transaction failed.',
    ramp_no_vehicle        = 'You must be the driver of a vehicle.',
    vehicle_blacklisted    = 'This vehicle cannot be modified here.',

    -- Engine Chip
    engine_chip_installed  = 'Engine chip installed! +%d%% top speed.',
    engine_chip_removed    = 'Engine chip removed.',

    -- Drift Chip
    drift_chip_installed   = 'Drift chip installed!',
    drift_chip_removed     = 'Drift chip removed.',

    -- Stance Kit
    stance_installed       = 'Stance kit installed.',
    stance_saved           = 'Stance saved.',
    stance_cancelled       = 'Stance changes cancelled.',
    stance_removed         = 'Stance kit removed.',

    -- Nitrous (pressure system)
    nos_installed          = 'Nitrous kit installed! Press LEFT SHIFT in your vehicle to activate.',
    nos_activated          = '🚀 NOS Activated!',
    nos_empty              = 'NOS tank empty! Use a NOS Canister item to refill.',
    nos_refilled           = '✅ NOS refilled!',
    nos_not_installed      = 'No NOS kit installed on this vehicle.',
    nos_removed            = 'NOS kit removed.',

    -- Exhaust
    exhaust_installed      = 'Exhaust mod installed! 🔥',
    exhaust_removed        = 'Exhaust mod removed.',

    -- Neon
    neon_installed         = 'Neon lighting installed!',
    neon_removed           = 'Neon lighting removed.',
    neon_set               = '%s neon set to %s.',
    neon_rainbow           = 'Rainbow neon activated!',
    neon_strobe            = 'Strobe neon activated!',

    -- Fake Plate
    fake_plate_applied     = '🪪 Fake plate applied: %s',
    fake_plate_removed     = 'Fake plate removed. Original plate restored.',

    -- Supply Run
    supply_run_started     = '🚚 Supply run dispatched! Follow the blip.',
    supply_run_complete    = '✅ Run complete! Collected %d damaged parts.',
    supply_run_cooldown    = 'Supply run on cooldown — %dm %ds remaining.',
    supply_run_active      = 'You already have an active supply run in progress.',

    -- Duty
    duty_on                = '🔧 Now ON duty. Ramp zone is active.',
    duty_off               = '🔧 Now OFF duty.',
    duty_off_blocked       = 'You are off duty. Use /tunerduty to go on duty.',

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
