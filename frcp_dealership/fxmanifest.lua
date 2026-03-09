fx_version 'cerulean'
game 'gta5'

name 'frcp_dealership'
description 'FlameDrive Motors — Mega Dealership for FlameCity'
version '1.0.0'

dependencies {
    'qbx_core',
    'oxmysql',
    'ox_lib',
    'ox_target',
    'frcp_tickets',
    'frcp_webhook',
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