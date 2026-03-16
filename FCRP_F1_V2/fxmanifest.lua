fx_version 'cerulean'
game 'gta5'

name        'frcp_f1'
description 'Flame City F1 System — v2.0 | Qbox + ox_target + oxmysql'
author      'FRCP'
version     '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

ui_page 'html/results.html'

files {
    'html/results.html',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'oxmysql',
    'ox_inventory',
}

lua54 'yes'
