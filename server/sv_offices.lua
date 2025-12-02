-- rsg-governor/server/sv_offices.lua

local RSGCore = exports['rsg-core']:GetCoreObject()
Gov          = Gov or {}

local function cents(d)
    d = tonumber(d or 0) or 0
    return math.floor(d * 100 + 0.5)
end

local function clampShare(x)
    x = tonumber(x or 0) or 0
    if x < 0 then x = 0 end
    if x > 1 then x = 1 end
    return x
end

-- Normalize region
function Gov.NormRegion(s)
    s = tostring(s or ''):lower()
    s = s:gsub('[%s%-]+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    return s
end

-- Simple notify wrapper if you don't already have one
function Gov.Notify(src, msg, typ)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Governor',
        description = msg,
        type        = typ or 'inform',
        duration    = 5000
    })
end

local function findBossGradeForJob(jobName)
    if not RSGShared or not RSGShared.Jobs then return nil end

    local job = RSGShared.Jobs[jobName]
    if not job or not job.grades then return nil end

    for grade, data in pairs(job.grades) do
        if data.isboss then
            return tonumber(grade) or grade
        end
    end
    return nil
end

local function buildOfficeJobName(region_alias, office_key)
    if not Config.Offices or not Config.Offices.JobMap then return nil end
    local map = Config.Offices.JobMap[office_key]
    if type(map) == 'function' then
        return map(region_alias)
    elseif type(map) == 'string' then
        -- static job name (same for all regions)
        return map
    end
    return nil
end

-- Ensure office row exists (with 0 shares)
local function ensureOfficeRow(region_name, office_key, office_label)
    region_name  = Gov.NormRegion(region_name)
    office_key   = tostring(office_key or ''):lower()
    office_label = office_label or office_key

    MySQL.insert.await([[
        INSERT INTO governor_offices (region_name, office_key, office_label, base_salary_cents, salary_share, supply_share)
        VALUES (?, ?, ?, 0, 0.0, 0.0)
        ON DUPLICATE KEY UPDATE
            office_label = VALUES(office_label)
    ]], { region_name, office_key, office_label })
end

local function setOfficeHead(region_name, office_key, citizenid, char_name)
    region_name = Gov.NormRegion(region_name)
    office_key  = tostring(office_key or 'unknown'):lower()

    MySQL.insert.await([[
        INSERT INTO governor_office_heads (region_name, office_key, citizenid, char_name)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            citizenid   = VALUES(citizenid),
            char_name   = VALUES(char_name),
            assigned_at = CURRENT_TIMESTAMP
    ]], { region_name, office_key, citizenid, char_name })
end

local function clearOfficeHead(region_name, office_key)
    region_name = Gov.NormRegion(region_name)
    office_key  = tostring(office_key or 'unknown'):lower()

    MySQL.update.await(
        'DELETE FROM governor_office_heads WHERE region_name = ? AND office_key = ?',
        { region_name, office_key }
    )
end

-- Set base salary (office-level, dollars -> cents)
local function setOfficeSalary(region_name, office_key, salaryDollars)
    ensureOfficeRow(region_name, office_key, office_key)
    local reg = Gov.NormRegion(region_name)
    local key = tostring(office_key or ''):lower()
    local c   = cents(salaryDollars)

    MySQL.update.await([[
        UPDATE governor_offices
           SET base_salary_cents = ?
         WHERE region_name = ? AND office_key = ?
    ]], { c, reg, key })
end

-- Set SALARY share (0.0 - 1.0)
local function setOfficeSalaryShare(region_name, office_key, share)
    ensureOfficeRow(region_name, office_key, office_key)
    local reg = Gov.NormRegion(region_name)
    local key = tostring(office_key or ''):lower()
    local v   = clampShare(share)

    MySQL.update.await([[
        UPDATE governor_offices
           SET salary_share = ?
         WHERE region_name = ? AND office_key = ?
    ]], { v, reg, key })
end

-- Set SUPPLY share (0.0 - 1.0)
local function setOfficeSupplyShare(region_name, office_key, share)
    ensureOfficeRow(region_name, office_key, office_key)
    local reg = Gov.NormRegion(region_name)
    local key = tostring(office_key or ''):lower()
    local v   = clampShare(share)

    MySQL.update.await([[
        UPDATE governor_offices
           SET supply_share = ?
         WHERE region_name = ? AND office_key = ?
    ]], { v, reg, key })
end

-- Backwards compatibility: old name still exists, maps to salary share
local function setOfficeFundingShare(region_name, office_key, share)
    setOfficeSalaryShare(region_name, office_key, share)
end

-- Create default offices for a region if none exist yet
local function ensureDefaultOfficesForRegion(region_name)
    region_name = Gov.NormRegion(region_name or 'unknown')

    local rows = MySQL.query.await(
        'SELECT id FROM governor_offices WHERE region_name = ? LIMIT 1',
        { region_name }
    )
    if rows and rows[1] then
        return -- already has at least one office
    end

    if not Config.Offices or not Config.Offices.Default then
        return
    end

    for _, def in ipairs(Config.Offices.Default) do
        local key   = tostring(def.key or 'unknown'):lower()
        local label = def.label or def.key or key

        MySQL.insert.await([[
            INSERT INTO governor_offices (region_name, office_key, office_label, base_salary_cents, funding_share)
            VALUES (?, ?, ?, 0, 0.0)
            ON DUPLICATE KEY UPDATE
                office_label = VALUES(office_label)
        ]], { region_name, key, label })
    end

    if Config.Debug then
        print(('[rsg-governor] Created default offices for region %s'):format(region_name))
    end
end

--======================
-- COMMAND: /govoffice
--======================

-- /govoffice sethead    [region|here] [officeKey] [serverId]
-- /govoffice clearhead  [region|here] [officeKey]
-- /govoffice setsalary  [region|here] [officeKey] [salaryDollars]
-- /govoffice setfund    [region|here] [officeKey] [share 0.0-1.0]   (SALARY share)
-- /govoffice setsupply  [region|here] [officeKey] [share 0.0-1.0]   (SUPPLY share)
RSGCore.Commands.Add('govoffice', 'Manage regional offices (governor only)', {
    { name = 'mode',      help = 'sethead | clearhead | setsalary | setfund | setsupply' },
    { name = 'region',    help = 'region name or "here"' },
    { name = 'officeKey', help = 'office key (sheriff, lawman, medic, etc)' },
    { name = 'arg4',      help = 'serverId / salary / share' },
}, true, function(source, args)
    local src    = source
    local mode   = tostring(args[1] or ''):lower()
    local region = args[2]
    local office = args[3]

    if mode ~= 'sethead' and mode ~= 'clearhead'
       and mode ~= 'setsalary' and mode ~= 'setfund'
       and mode ~= 'setsupply' then
        Gov.Notify(src, 'Usage: /govoffice [sethead|clearhead|setsalary|setfund|setsupply] [region|here] [officeKey] [id/salary/share]', 'error')
        return
    end

    if not region or not office then
        Gov.Notify(src, 'Region and officeKey are required.', 'error')
        return
    end

    -- Resolve region "here"
    if region == 'here' then
        local ok, hash, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            Gov.Notify(src, 'Unable to determine your current region. Move a bit and try again.', 'error')
            return
        end
        region = alias
    end

    region = Gov.NormRegion(region)
    office = tostring(office or ''):lower()

    -- Permissions: governor or owner only
    local okAuth = false
    local okPerm, res = pcall(function()
        return exports['rsg-governor']:CanActOnRegion(src, region, 'command.govoffice.' .. mode)
    end)
    if okPerm and res then okAuth = true end

    if not okAuth then
        Gov.Notify(src, ('You are not allowed to manage offices for "%s".'):format(region), 'error')
        return
    end

    -- Ensure office definition row exists
    ensureOfficeRow(region, office, office)

    if mode == 'sethead' then
        -- (your existing residency-aware head logic here)
        -- keep what we already wrote earlier for sethead
        -- ...
        return

    elseif mode == 'clearhead' then
        clearOfficeHead(region, office)
        Gov.Notify(src, ('Cleared head of "%s" in %s.'):format(office, region), 'success')

    elseif mode == 'setsalary' then
        local salary = tonumber(args[4] or 0) or 0
        if salary < 0 then salary = 0 end
        setOfficeSalary(region, office, salary)
        Gov.Notify(src, ('Set salary of "%s" in %s to $%d.'):format(office, region, salary), 'success')

    elseif mode == 'setfund' then
        -- SALARY share
        local share = clampShare(args[4])
        setOfficeSalaryShare(region, office, share)
        Gov.Notify(src, ('Set SALARY share of "%s" in %s to %.2f.'):format(office, region, share), 'success')

    elseif mode == 'setsupply' then
        -- SUPPLY share
        local share = clampShare(args[4])
        setOfficeSupplyShare(region, office, share)
        Gov.Notify(src, ('Set SUPPLY share of "%s" in %s to %.2f.'):format(office, region, share), 'success')
    end
end, 'user')

-- =========================
-- Exports for other scripts
-- =========================

-- Return offices + heads for a region for UI / economy
exports('GetRegionOffices', function(region_name)
    region_name = Gov.NormRegion(region_name)
    local offices = MySQL.query.await(
        'SELECT * FROM governor_offices WHERE region_name = ?',
        { region_name }
    ) or {}

    local heads = MySQL.query.await(
        'SELECT * FROM governor_office_heads WHERE region_name = ?',
        { region_name }
    ) or {}

    -- attach head info into office rows
    local headMap = {}
    for _, h in ipairs(heads) do
        local key = tostring(h.office_key or ''):lower()
        headMap[key] = h
    end

    for _, o in ipairs(offices) do
        local key = tostring(o.office_key or ''):lower()
        local h   = headMap[key]
        if h then
            o.head_citizenid = h.citizenid
            o.head_char_name = h.char_name
        end
    end

    return offices
end)

-- ox_lib callback for client UI
lib.callback.register('rsg-governor:getRegionOffices', function(src, region)
    region = region or 'here'

    -- Resolve "here" via economy region hash/alias
    if region == 'here' then
        local ok, hash, alias = pcall(function()
            return lib.callback.await('rsg-economy:getRegionHash', src)
        end)
        if not ok or not alias then
            return {}
        end
        region = alias
    end

    local reg = Gov.NormRegion(region)

    -- Join with heads table if you have one
    local rows = MySQL.query.await([[
        SELECT  o.region_name,
                o.office_key,
                o.office_label,
                o.base_salary_cents,
                o.salary_share,
                o.supply_share,
                h.char_name AS head_char_name
          FROM governor_offices o
     LEFT JOIN governor_office_heads h
            ON h.region_name = o.region_name
           AND h.office_key  = o.office_key
         WHERE o.region_name = ?
      ORDER BY o.office_key
    ]], { reg }) or {}

    -- Fallback: if salary_share is NULL but funding_share exists, map it
    for _, r in ipairs(rows) do
        if (r.salary_share == nil or r.salary_share == 0) and r.funding_share ~= nil then
            r.salary_share = r.funding_share
        end
        if r.supply_share == nil then
            r.supply_share = 0.0
        end
    end

    return rows
end)

-- =========================
-- Public: GetRegionOffices
-- (used by exports in sv_exports.lua and by UI callback)
-- =========================

function Gov.GetRegionOffices(region_name)
    region_name = Gov.NormRegion(region_name or 'unknown')

    -- ensure default offices (lawman, medic, etc.) exist for this region
    ensureDefaultOfficesForRegion(region_name)

    local offices = MySQL.query.await(
        'SELECT * FROM governor_offices WHERE region_name = ?',
        { region_name }
    ) or {}

    local heads = MySQL.query.await(
        'SELECT * FROM governor_office_heads WHERE region_name = ?',
        { region_name }
    ) or {}

    local headMap = {}
    for _, h in ipairs(heads) do
        local key = tostring(h.office_key or ''):lower()
        headMap[key] = h
    end

    for _, o in ipairs(offices) do
        local key = tostring(o.office_key or ''):lower()
        local h   = headMap[key]
        if h then
            o.head_citizenid = h.citizenid
            o.head_char_name = h.char_name
        end
    end

    return offices
end