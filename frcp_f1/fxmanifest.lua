fx_version 'cerulean'
game 'gta5'

description 'Flame City F1 System'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua'
}

client_scripts { 'client/main.lua' }
server_scripts { 'server/main.lua' }

dependencies {
    'qbx_core',
    'ox_lib',
    'frcp_webhook'
}
