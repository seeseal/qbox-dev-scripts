fx_version 'cerulean'
game 'gta5'

name 'fd_dealership'
description 'FlameDrive Motors — Mega Dealership for FlamCity'
version '1.0.0'

dependencies {
    'qbx_core',
    'oxmysql',
    'ox_lib',
    'ox_target',
    'tebex_tickets',
    'discord_webhook',
}

shared_scripts {
    'config.lua'
}

server_scripts {
    'server.lua'
}

client_scripts {
    'client.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}