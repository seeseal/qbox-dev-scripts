fx_version 'cerulean'
game 'gta5'

name        'fcrp_f1'
description 'Flame City F1 — v3.0 | Qbox + ox_target + oxmysql'
author      'FCRP'
version     '3.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/debug.lua',    -- debug utilities (DBG / DBGW / DBGE / /f1debug / /f1nuitest)
    'shared/hooks.lua',
}

client_scripts {
    'client/main.lua',
    'client/nui_callbacks.lua',  -- NUI callback handlers for the HTML dashboard
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/style.css',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'oxmysql',
    'ox_inventory',
}

lua54 'yes'
