-- ============================================================
--  frcp_tuner  |  locales/en.lua
--  All player-facing text lives here.
--  !! CHANGE ME !! — edit strings to match your server's tone
-- ============================================================

local Locale = {
    -- Menu titles
    menu_title          = '🔧 Tuner Shop',
    menu_subtitle       = 'Illegal Performance & Style',

    -- Option labels shown in the ox_lib menu
    opt_engine_chip     = '⚡ Engine Chip',
    opt_drift_chip      = '🌀 Drift Chip',
    opt_stance_kit      = '📐 Stance Kit',
    opt_nitrous_kit     = '💨 Nitrous Kit',
    opt_neon_kit        = '🌈 Neon Kit',
    opt_remove_mods     = '🗑️  Remove Mods',
    opt_close           = '✖ Close',

    -- State badges shown next to options
    badge_installed     = ' ✅ Installed',
    badge_blocked       = ' 🚫 Conflict',

    -- Notifications (shown in the corner of the screen)
    not_in_vehicle          = 'You must be in a vehicle.',
    not_driver              = 'You must be the driver.',
    no_job                  = 'You do not have the required job.',
    not_near_shop           = 'You are not near the tuner shop.',
    no_funds                = 'Not enough black money.',
    already_has_chip        = 'This vehicle already has a chip installed.',
    engine_drift_conflict   = 'Remove the drift chip first.',
    drift_engine_conflict   = 'Remove the engine chip first.',
    chip_installed          = 'Engine chip installed.',
    drift_installed         = 'Drift kit installed.',
    stance_installed        = 'Stance kit installed.',
    nitrous_installed       = 'Nitrous installed.',
    neon_installed          = 'Neon kit installed.',
    mod_removed             = 'Mod removed.',
    nitrous_active          = '💨 Nitrous active!',
    nitrous_cooldown        = 'Nitrous on cooldown.',
    nitrous_not_installed   = 'No nitrous kit installed.',
    chip_not_found          = 'No engine chip found on this vehicle.',
    chip_removed_pd         = 'Engine chip removed by officer.',

    -- Progress bar labels
    prog_install        = 'Installing mod…',
    prog_remove         = 'Removing mod…',

    -- Stance editor hints
    stance_hint         = '[←→] Camber   [↑↓] Height   [INS/DEL] Width   [ENTER] Save   [BACKSPACE] Cancel',

    -- Discord log messages (these go to your turf log channel)
    log_purchased       = 'purchased **%s** on plate **%s** for **$%s** black money.',
    log_removed         = 'removed **%s** from plate **%s**.',
    log_chip_pd         = 'Officer **%s** removed engine chip from plate **%s**.',
}

-- Make strings accessible via lib.locale() in Qbox
if lib and lib.setLocale then
    lib.setLocale(Locale)
else
    -- Fallback direct getter used internally
    function GetLocale(key, ...)
        local str = Locale[key] or ('MISSING_LOCALE:'..key)
        if select('#', ...) > 0 then
            return str:format(...)
        end
        return str
    end
end
