--======================================================================
-- rsg-governor / server/sv_permits.lua
-- Business permits: application + approval (manual / auto)
--======================================================================

local RSGCore = exports['rsg-core']:GetCoreObject()
Gov          = Gov or {}
lib.locale()

local function now()
    return os.time()
end

local function permitsEnabled()
    return not Config.Permits or Config.Permits.Enabled ~= false
end

-- internal: create permit row
local function createPermit(region_name, Player, license_type, business_name)
    region_name   = Gov.NormRegion(region_name)
    license_type  = tostring(license_type or 'general'):lower()
    business_name = business_name or 'Business'

    local citizenid = Player.PlayerData.citizenid
    local charName  = (Player.PlayerData.charinfo and
                      (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname))
                      or ('Citizen ' .. citizenid)

    local minS = (Config.Permits and Config.Permits.AutoApproveMinSecs) or (5 * 60)
    local maxS = (Config.Permits and Config.Permits.AutoApproveMaxSecs) or (20 * 60)
    local autoSec = math.random(minS, maxS)

    MySQL.insert.await([[
        INSERT INTO governor_business_permits
            (region_name, citizenid, char_name, business_name, license_type, status, auto_after_secs, submitted_at)
        VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)
    ]], {
        region_name,
        citizenid,
        charName,
        business_name,
        license_type,
        autoSec,
        now()
    })
end

-- internal: approve (and hook into rsg-economy business reg if you want)
local function approvePermitRow(row, auto, decidedBy)
    auto = auto == true

    -- Business registration is up to you. This is a hook into rsg-economy:
    -- (only if you already have an export like RegisterBusiness)
    pcall(function()
        exports['rsg-economy']:RegisterBusiness(
            row.citizenid,
            row.region_name,
            row.business_name,
            row.license_type,
            true -- VAT registered by default
        )
    end)

    local status = auto and 'autoapproved' or 'approved'

    MySQL.update.await(
        'UPDATE governor_business_permits SET status = ?, decided_at = ?, decided_by = ? WHERE id = ?',
        { status, now(), decidedBy or 'system', row.id }
    )
end

local function rejectPermitRow(row, decidedBy)
    MySQL.update.await(
        'UPDATE governor_business_permits SET status = "rejected", decided_at = ?, decided_by = ? WHERE id = ?',
        { now(), decidedBy or 'system', row.id }
    )
end

--======================
-- Commands: /applybiz
--======================

-- /applybiz [licenseType] [business name...]
RSGCore.Commands.Add('applybiz', 'Apply for a business permit', {
    { name = 'licenseType', help = 'shop | market | ranch | etc' },
    { name = 'name',        help = 'business name (rest of args)' },
}, false, function(source, args)
    if not permitsEnabled() then return end

    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local license_type = tostring(args[1] or 'general')
    if #args < 2 then
        Gov.Notify(src, 'Usage: /applybiz [licenseType] [business name...]', 'error')
        return
    end
    local bizName = table.concat(args, ' ', 2)

    -- resolve region from economy region hash
    local ok, hash, alias = pcall(function()
        return lib.callback.await('rsg-economy:getRegionHash', src)
    end)
    if not ok or not alias then
        Gov.Notify(src, 'Unable to determine your current region. Move a bit and try again.', 'error')
        return
    end

    createPermit(alias, Player, license_type, bizName)
    Gov.Notify(src, ('You applied for a business permit in %s.'):format(Gov.NormRegion(alias)), 'success')
end, 'user')

--=========================
-- Commands: /govpermits
--=========================

-- /govpermits [region|here]
RSGCore.Commands.Add('govpermits', 'List pending business permits (governor only)', {
    { name = 'region', help = 'regionName or "here"' },
}, false, function(source, args)
    if not permitsEnabled() then return end

    local src    = source
    local region = args[1]

    if not region or region == 'here' then
        local ok, hash, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            Gov.Notify(src, 'Unable to determine your current region.', 'error')
            return
        end
        region = alias
    end

    local okAuth = false
    local ok, res = pcall(function()
        return exports['rsg-governor']:CanActOnRegion(src, region, 'command.govpermits')
    end)
    if ok and res then okAuth = true end

    if not okAuth then
        Gov.Notify(src, 'You are not allowed to manage permits in this region.', 'error')
        return
    end

    local rows = MySQL.query.await(
        'SELECT * FROM governor_business_permits WHERE region_name = ? AND status = "pending" ORDER BY submitted_at ASC',
        { Gov.NormRegion(region) }
    )

    if not rows or #rows == 0 then
        Gov.Notify(src, 'No pending business permits for this region.', 'inform')
        return
    end

    local lines = {}
    for _, r in ipairs(rows) do
        lines[#lines+1] = ('#%d %s (%s) - "%s" [%s]')
            :format(r.id, r.char_name, r.citizenid, r.business_name, r.license_type)
    end

    Gov.Notify(src, table.concat(lines, '\n'), 'inform')
end, 'user')

-- /approvebiz [permitId]
RSGCore.Commands.Add('approvebiz', 'Approve a business permit (governor only)', {
    { name = 'id', help = 'permit id' },
}, false, function(source, args)
    if not permitsEnabled() then return end

    local src = source
    local id  = tonumber(args[1] or 0) or 0
    if id <= 0 then
        Gov.Notify(src, 'Usage: /approvebiz [permitId]', 'error')
        return
    end

    local row = MySQL.single.await(
        'SELECT * FROM governor_business_permits WHERE id = ? LIMIT 1',
        { id }
    )
    if not row then
        Gov.Notify(src, 'Permit not found.', 'error')
        return
    end
    if row.status ~= 'pending' then
        Gov.Notify(src, 'Permit is not pending.', 'error')
        return
    end

    local okAuth = false
    local ok, res = pcall(function()
        return exports['rsg-governor']:CanActOnRegion(src, row.region_name, 'command.approvebiz')
    end)
    if ok and res then okAuth = true end

    if not okAuth then
        Gov.Notify(src, 'You are not allowed to approve permits in this region.', 'error')
        return
    end

    approvePermitRow(row, false, GetPlayerName(src))
    Gov.Notify(src, ('Approved permit #%d for "%s".'):format(id, row.business_name), 'success')
end, 'user')

-- /rejectbiz [permitId]
RSGCore.Commands.Add('rejectbiz', 'Reject a business permit (governor only)', {
    { name = 'id', help = 'permit id' },
}, false, function(source, args)
    if not permitsEnabled() then return end

    local src = source
    local id  = tonumber(args[1] or 0) or 0
    if id <= 0 then
        Gov.Notify(src, 'Usage: /rejectbiz [permitId]', 'error')
        return
    end

    local row = MySQL.single.await(
        'SELECT * FROM governor_business_permits WHERE id = ? LIMIT 1',
        { id }
    )
    if not row then
        Gov.Notify(src, 'Permit not found.', 'error')
        return
    end
    if row.status ~= 'pending' then
        Gov.Notify(src, 'Permit is not pending.', 'error')
        return
    end

    local okAuth = false
    local ok, res = pcall(function()
        return exports['rsg-governor']:CanActOnRegion(src, row.region_name, 'command.rejectbiz')
    end)
    if ok and res then okAuth = true end

    if not okAuth then
        Gov.Notify(src, 'You are not allowed to reject permits in this region.', 'error')
        return
    end

    rejectPermitRow(row, GetPlayerName(src))
    Gov.Notify(src, ('Rejected permit #%d for "%s".'):format(id, row.business_name), 'success')
end, 'user')

--=========================
-- Auto-approval loop
--=========================
CreateThread(function()
    Wait(5000)
    if not permitsEnabled() then return end

    while true do
        Wait(60 * 1000)

        local rows = MySQL.query.await(
            'SELECT * FROM governor_business_permits WHERE status = "pending"',
            {}
        )
        if not rows or #rows == 0 then
            goto continue
        end

        local nowT = now()
        for _, r in ipairs(rows) do
            local elapsed = nowT - (tonumber(r.submitted_at or 0) or 0)
            local limit   = tonumber(r.auto_after_secs or 0) or 0

            if limit > 0 and elapsed >= limit then
                -- Only auto-approve if NO governor online for that region
                local hasGov = exports['rsg-governor']:IsAnyGovernorOnline(r.region_name)
                if not hasGov then
                    approvePermitRow(r, true, 'auto')
                    print(('[rsg-governor] Auto-approved business permit #%d for %s in %s')
                        :format(r.id, r.business_name, r.region_name))
                end
            end
        end

        ::continue::
    end
end)
