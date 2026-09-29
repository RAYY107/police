fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Evora_Police'
author 'Made By LR'
description 'Evora_Police — organisational police & government operations platform for Universal vRP'
version '1.0.0'

ui_page 'web/index.html'

-- Shared with clients. Never put secrets in these files (see config/server.lua).
shared_scripts {
    'config/config.lua',
    'config/government.lua',
    'config/permissions.lua',
    'config/fines.lua',
    'config/jail.lua',
    'config/impound.lua',
    'config/field.lua',
    'config/equipment.lua',
    'config/uniforms.lua',
    'config/security.lua',
    'config/integrations.lua',
    'config/locale.lua',
    'shared/utils.lua',
}

server_scripts {
    'config/server.lua',
    'server/core/bootstrap.lua',
    'server/core/framework.lua',
    'server/core/database.lua',
    'server/core/players.lua',
    'server/core/rpc.lua',
    'server/core/logs.lua',
    'server/integrations/base.lua',
    'server/integrations/inventory.lua',
    'server/integrations/vehicles.lua',
    'server/integrations/player.lua',
    'server/core/menu.lua',
    'server/government.lua',
    'server/confirm.lua',
    'server/spectate.lua',
    'server/targets.lua',
    'server/officers.lua',
    'server/vacation.lua',
    'server/affairs.lua',
    'server/statistics.lua',
    'server/ipad.lua',
    'server/reports.lua',
    'server/wanted.lua',
    'server/citizens.lua',
    'server/fines.lua',
    'server/jail.lua',
    'server/field.lua',
    'server/equipment.lua',
    'server/security.lua',
    'server/barricades.lua',
    'server/impound.lua',
    'server/policemenu.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/integrations.lua',
    'client/ui.lua',
    'client/confirm.lua',
    'client/ipad.lua',
    'client/spectate.lua',
    'client/jail.lua',
    'client/security.lua',
    'client/barricades.lua',
    'client/points.lua',
}

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/assets/*.*',
    'web/assets/fonts/*.*',
}
