-- locales/en.lua
local Translations = {
    -- General
    ['no_job']            = "You don't have the right connections here.",
    ['drive_in']          = 'Drive your vehicle into the shop.',
    ['get_in_vehicle']    = 'Get back in your vehicle!',
    ['cancelled']         = 'Installation cancelled.',
    ['transaction_failed']= 'Transaction failed!',
    ['unknown_product']   = 'Unknown product.',
    ['invalid_price']     = 'Invalid price.',
    ['slow_down']         = 'Slow down!',
    ['access_denied']     = 'Access denied.',
    ['press_open']        = 'Press ~INPUT_CONTEXT~ to open Tuner Shop',
    ['no_funds']          = "%s doesn't have enough dirty cash! ($%d needed)",

    -- Engine Chip
    ['engine_chip_installed']     = '+%d%% top speed chip installed! 🏎️',
    ['engine_chip_already']       = 'This vehicle already has an engine chip installed.',
    ['engine_chip_conflict']      = 'Remove the drift chip before installing an engine chip.',
    ['engine_chip_removed']       = 'Engine chip removed.',
    ['engine_chip_no_chip']       = 'This vehicle has no engine chip to remove.',

    -- Drift Chip
    ['drift_chip_installed']      = 'Drift chip installed!',
    ['drift_chip_already']        = 'This vehicle already has a drift chip installed.',
    ['drift_chip_conflict']       = 'Remove the engine chip before installing a drift chip.',
    ['drift_chip_removed']        = 'Drift chip removed.',
    ['drift_chip_no_chip']        = 'This vehicle has no drift chip to remove.',

    -- Stance
    ['stance_installed']          = 'Stance kit installed! Adjust with arrow keys.',
    ['stance_already']            = 'This vehicle already has a stance kit installed.',
    ['stance_saved']              = 'Stance saved! ✅',
    ['stance_cancelled']          = 'Stance cancelled.',
    ['stance_removed']            = 'Stance kit removed.',
    ['stance_mode']               = 'Stance mode — arrow keys to adjust. ENTER to save.',

    -- Nitrous
    ['nos_installed']             = 'Nitrous installed! LEFT SHIFT to activate 🚀',
    ['nos_already']               = 'This vehicle already has a NOS kit installed.',
    ['nos_activated']             = '🚀 NOS ACTIVATED!',
    ['nos_refilled']              = 'NOS refilled and ready! 🚀',
    ['nos_not_installed']         = 'No NOS kit installed on this vehicle.',
    ['nos_no_refill_here']        = 'NOS is empty — drive to the refill station.',
    ['nos_cooldown']              = 'NOS refill on cooldown. %d min remaining.',
    ['nos_removed']               = 'NOS kit removed.',
    ['nos_empty']                 = '⚠️ NOS is empty — head to the refill station!',
    ['nos_station_press']         = 'Press ~INPUT_CONTEXT~ to refill NOS · $%s',
    ['nos_station_no_nos']        = 'Your vehicle has no NOS kit installed.',
    ['nos_station_not_empty']     = 'Your NOS is still charged — no refill needed.',
    ['nos_station_refilling']     = 'Refilling NOS...',

    -- Neon
    ['neon_set']                  = '%s neon set to %s! 💡',
    ['neon_rainbow']              = 'Rainbow neon activated! 🌈',
    ['neon_strobe']               = 'Strobe neon activated! ⚡',
    ['neon_removed']              = 'Neon kit removed.',
    ['neon_already']              = 'This vehicle already has a neon kit. Visit removal menu first.',

    -- Ramp
    ['ramp_press_open']       = 'Press ~INPUT_CONTEXT~ to view Tuner Menu',
    ['ramp_tuner_only']       = 'Only a tuner can install mods. Prices shown for reference.',
    ['ramp_no_vehicle']       = 'Drive your vehicle onto the ramp.',
    ['ramp_not_tuner']        = 'You need a tuner to install this mod.',

    -- Removal (PD)
    ['remove_chip_no_perm']       = 'Only PD can remove engine chips.',
    ['remove_chip_success']       = 'Engine chip successfully removed from vehicle.',
    ['remove_chip_none']          = 'No engine chip found on this vehicle.',

    -- Progress bars
    ['installing']                = 'Installing %s...',
    ['removing']                  = 'Removing %s...',
}

-- Simple locale wrapper — no qb-core dependency
Lang = {
    t = function(self, key, args)
        local str = Translations[key]
        if not str then return key end
        if args then
            if type(args) == 'table' then
                return string.format(str, table.unpack(args))
            else
                return string.format(str, args)
            end
        end
        return str
    end
}
