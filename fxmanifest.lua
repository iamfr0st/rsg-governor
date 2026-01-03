fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

name 'rsg-governor'
author 'fr0st'
description 'Regional governors, offices, rules & permits for RedM'
version '1.5.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/sh_helpers.lua',
    'shared/sh_exports.lua',
    --'shared/sh_regions.lua',
}

client_scripts {
    'client/cl_panel.lua',
    'client/cl_dutylog.lua',
    'client/cl_duty.lua',
    'client/cl_officepanel.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_auth.lua',
    --'server/sv_governors.lua',
    'server/sv_install.lua',
    'server/sv_offices.lua',
    'server/sv_rules.lua',
    'server/sv_funding.lua',
    'server/sv_permits.lua',
    'server/sv_duty.lua',
    'server/sv_exports.lua',
    'server/sv_region.lua',
    'server/sv_officepanel.lua',
    
    
}
