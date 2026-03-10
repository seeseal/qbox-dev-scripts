fx_version 'cerulean'
game 'gta5'

name        'frcp_tuner'
description 'Flame City Illegal Tuner Shop — Qbox conversion'
author      'Flame City Dev'
version     '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/en.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

lua54 'yes'
