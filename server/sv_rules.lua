--======================================================================
-- rsg-governor / server/sv_rules.lua
-- Region rules & announcements (governor / owner only)
--======================================================================

local RSGCore = exports['rsg-core']:GetCoreObject()
Gov          = Gov or {}
lib.locale()

local function now()
    return os.time()
end

-- ensure row for rules
local function ensureRegionRules(region_name)
    region_name = Gov.NormRegion(region_name)

    local row = MySQL.single.await(
        'SELECT * FROM governor_region_rules WHERE region_name = ? LIMIT 1',
        { region_name }
    )
    if row then return row end

    MySQL.insert.await(
        'INSERT INTO governor_region_rules (region_name, rules_text) VALUES (?, ?)',
        { region_name, '' }
    )

    return MySQL.single.await(
        'SELECT * FROM governor_region_rules WHERE region_name = ? LIMIT 1',
        { region_name }
    )
end

--===============================
-- Commands: /govrules (set/show)
--===============================
-- /govrules show [region|here]
-- /govrules set  [region|here] [rules text...]
RSGCore.Commands.Add('govrules', 'Set or show region rules', {
    { name = 'mode',   help = 'set | show' },
    { name = 'region', help = 'regionName or "here"' },
    { name = 'text',   help = 'rules text (for set)' },
}, false, function(source, args)
    local src   = source
    local mode  = tostring(args[1] or 'show'):lower()
    local regionArg = args[2]

    if mode ~= 'set' and mode ~= 'show' then
        Gov.Notify(src, 'Usage: /govrules [set|show] [region|here] [rules text...]', 'error')
        return
    end

    -- resolve region
    local regionName = regionArg
    if not regionName or regionName == 'here' then
        local ok, hash, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            Gov.Notify(src, 'Unable to determine your current region.', 'error')
            return
        end
        regionName = alias
    end
    local regionNorm = Gov.NormRegion(regionName)

    if mode == 'show' then
        local row = MySQL.single.await(
            'SELECT rules_text FROM governor_region_rules WHERE region_name = ? LIMIT 1',
            { regionNorm }
        )

        local text = row and row.rules_text or 'No rules have been set for this region yet.'
        Gov.Notify(src, ('Rules for %s:\n%s'):format(regionNorm, text), 'inform')
        return
    end

    -- mode == "set": permission required
    local okAuth = false
    local ok, res = pcall(function()
        return exports['rsg-governor']:CanActOnRegion(src, regionName, 'command.govrules.set')
    end)
    if ok and res then okAuth = true end

    if not okAuth then
        Gov.Notify(src, ('You are not allowed to set rules for "%s".'):format(regionNorm), 'error')
        return
    end

    if #args < 3 then
        Gov.Notify(src, 'Usage: /govrules set [region|here] [rules text...]', 'error')
        return
    end
    local text = table.concat(args, ' ', 3)
    local maxLen = Config.Rules and Config.Rules.MaxLength or 4000
    if #text > maxLen then
        Gov.Notify(src, ('Rules too long (max %d chars).'):format(maxLen), 'error')
        return
    end

    ensureRegionRules(regionName)
    MySQL.update.await(
        'UPDATE governor_region_rules SET rules_text = ?, updated_by = ? WHERE region_name = ?',
        { text, GetPlayerName(src), regionNorm }
    )

    Gov.Notify(src, ('Updated rules for %s.'):format(regionNorm), 'success')
end, 'user')

--==================================
-- Command: /govannounce (broadcast)
--==================================
-- /govannounce [region|here] [message...]
RSGCore.Commands.Add('govannounce', 'Make a regional announcement', {
    { name = 'region',  help = 'regionName or "here"' },
    { name = 'message', help = 'announcement text' },
}, false, function(source, args)
    local src = source
    local regionArg = args[1]

    if not regionArg then
        Gov.Notify(src, 'Usage: /govannounce [region|here] [message...]', 'error')
        return
    end

    -- resolve region
    local regionName = regionArg
    if regionName == 'here' then
        local ok, hash, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            Gov.Notify(src, 'Unable to determine your current region.', 'error')
            return
        end
        regionName = alias
    end
    local regionNorm = Gov.NormRegion(regionName)

    if #args < 2 then
        Gov.Notify(src, 'Usage: /govannounce [region|here] [message...]', 'error')
        return
    end

    local msg = table.concat(args, ' ', 2)
    local maxLen = Config.Announcements and Config.Announcements.MaxLength or 1000
    if #msg > maxLen then
        Gov.Notify(src, ('Announcement too long (max %d chars).'):format(maxLen), 'error')
        return
    end

    -- permission
    local okAuth = false
    local ok, res = pcall(function()
        return exports['rsg-governor']:CanActOnRegion(src, regionName, 'command.govannounce')
    end)
    if ok and res then okAuth = true end

    if not okAuth then
        Gov.Notify(src, ('You are not allowed to announce for "%s".'):format(regionNorm), 'error')
        return
    end

    -- optional cooldown per player (simple in-memory)
    local cooldown = Config.Announcements and Config.Announcements.CooldownSecs or 60
    local key = ('gov_ann_cooldown_%d'):format(src)
    local last = GlobalState[key]
    local nowT = now()

    if last and (nowT - last) < cooldown then
        local remain = cooldown - (nowT - last)
        Gov.Notify(src, ('You must wait %d seconds before another announcement.'):format(remain), 'error')
        return
    end
    GlobalState[key] = nowT

    -- save to DB
    MySQL.insert.await(
        'INSERT INTO governor_region_announcements (region_name, message, author, created_at) VALUES (?, ?, ?, ?)',
        { regionNorm, msg, GetPlayerName(src), nowT }
    )

    -- broadcast to all players in that region (simple version using economy region callback)
    local players = RSGCore.Functions.GetPlayers()
    for _, id in ipairs(players) do
        local okR, hash, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', id)
        end)
        if okR and alias and Gov.NormRegion(alias) == regionNorm then
            Gov.Notify(id, msg, 'inform', ('Governor – %s'):format(regionNorm))
        end
    end

    Gov.Notify(src, ('Announcement sent to %s.'):format(regionNorm), 'success')
end, 'user')

--========================
-- Callbacks for UI / API
--========================

lib.callback.register('rsg-governor:getRegionRules', function(src, regionName)
    if regionName == 'here' or not regionName or regionName == '' then
        local ok, _, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if ok and alias then regionName = alias end
    end
    regionName = Gov.NormRegion(regionName or 'unknown')

    local row = MySQL.single.await(
        'SELECT rules_text FROM governor_region_rules WHERE region_name = ? LIMIT 1',
        { regionName }
    )
    return row and row.rules_text or ''
end)
