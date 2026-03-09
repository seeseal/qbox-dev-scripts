fx_version 'cerulean'
game 'gta5'

name        'frcp_dealership'
description 'FlameDrive Motors — Mega Dealership for FlameCity'
version     '1.2.1'

dependencies {
    'qbx_core',
    'oxmysql',
    'ox_lib',
    'ox_target',
    'frcp_tickets',
    'frcp_webhook',
}

shared_scripts {
    '@ox_lib/init.lua',   -- required for lib.notify, lib.addCommand, lib.alertDialog
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',   -- required for MySQL.query, MySQL.insert etc
    'server.lua',
}

client_scripts {
    'client.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

lua54 'yes'