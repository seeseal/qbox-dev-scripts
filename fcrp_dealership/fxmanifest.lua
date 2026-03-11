fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'fcrp_dealership'
description 'FlameDrive Motors — Dealership Job System for Flame City'
author      'Flame City Dev'
version     '2.4.0'

dependencies {
    'qbx_core',
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'frcp_tickets',
    'frcp_webhook',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/job.lua',
    'server/society.lua',
    'server/testdrive.lua',
    'server/showroom.lua',
}

client_scripts {
    'client/main.lua',
    'client/job.lua',
    'client/testdrive.lua',
    'client/showroom.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/fa-subset.css',
    'html/img/*.jpg',
    'html/img/*.png',
}
