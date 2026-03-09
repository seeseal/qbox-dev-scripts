fx_version 'cerulean'
game 'gta5'

name 'tebex_tickets'
description 'CitizenID-linked Tebex ticket system for Elite and Apex vehicle access'
version '1.0.0'

dependencies {
    'qbx_core',
    'oxmysql',
    'discord_webhook',
}

server_scripts {
    'server.lua'
}