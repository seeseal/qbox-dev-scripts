fx_version 'cerulean'
game 'gta5'

author 'FCRP'
description 'Qbox Illegal Tuner Shop'
version '1.0.0'

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
