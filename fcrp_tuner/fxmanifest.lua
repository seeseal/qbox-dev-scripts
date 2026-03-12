fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'FCRP'
description 'Qbox Illegal Tuner Shop'
version '2.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
}

shared_scripts {
    '@ox_lib/init.lua',
    'locales/en.lua',
    'config.lua',
}

client_scripts {
    'client/debug.lua',
    'client/ui.lua',
    'client/main.lua',
    'client/stance.lua',
    'client/nitrous.lua',
    'client/neon.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
}