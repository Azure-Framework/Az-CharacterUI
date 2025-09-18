fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'Azure(TheStoicBear)'
description 'Azure CharacterUI'
version '1.3.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
} 

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

client_scripts {
    'client.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/config.js',
    'html/map.png'
}
