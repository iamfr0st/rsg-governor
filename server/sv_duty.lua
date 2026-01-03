--======================================================================
-- rsg-governor / server/sv_duty.lua
-- Duty tracking + payroll + governor payroll callbacks
--======================================================================

local RSGCore = exports['rsg-core']:GetCoreObject()
local TAX_RES  = 'rsg-economy'

local DUTY_TABLE = 'governor_duty_sessions'

local Gov       = Gov or {}   -- helper table from other server files
local dutyClock = {}          -- stores last clock + duty state per src

-- Small helpers
local function normRegion(name)
    if Gov.NormRegion then
        return Gov.NormRegion(name)
    end
    name = tostring(name or 'unknown'):lower()
    name = name:gsub('%s+', '_')
    return name
end

local function isOwner(src)
    if Gov.IsOwner then
        return Gov.IsOwner(src)
    end
    local ids = GetPlayerIdentifiers(src)
    if not ids or not Config or not Config.OwnerIdentifiers then return false end
    for _, id in ipairs(ids) do
        for _, cfg in ipairs(Config.OwnerIdentifiers) do
            if id == cfg then
                return true
            end
        end
    end
    return false
end

local function notify(src, msg, typ)
    typ = typ or 'inform'
    if Gov.Notify then
        return Gov.Notify(src, msg, typ)
    end
    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Governor',
        description = msg,
        type        = typ,
        duration    = 7000
    })
end

--======================================================================
-- DUTY SESSION STORAGE
--======================================================================

-- Ensure table exists (simple bootstrap; will NOT alter existing table)
CreateThread(function()
    Wait(1000)
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS ]] .. DUTY_TABLE .. [[ (
            id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
            citizenid        VARCHAR(50) NOT NULL,
            job_name         VARCHAR(64) NOT NULL,
            job_label        VARCHAR(128) NULL,
            job_type         VARCHAR(32) NULL,
            grade            INT NOT NULL DEFAULT 0,
            region_name      VARCHAR(64) NOT NULL,
            started_at       DATETIME NOT NULL,
            ended_at         DATETIME NULL,
            minutes_regular  INT NOT NULL DEFAULT 0,
            minutes_overtime INT NOT NULL DEFAULT 0,
            paid             TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (id),
            KEY idx_citizen_paid (citizenid, paid),
            KEY idx_region_paid (region_name, paid)
        )
    ]])
end)

-- active[ citizenid ] is no longer used; sessions are derived directly from DB

local function getRegionAliasForPlayer(src)
    -- Prefer exported "governor region" helper if present
    if exports['rsg-governor'] and exports['rsg-governor'].GetGovernorRegionForPlayer then
        local ok, reg = pcall(function()
            return exports['rsg-governor']:GetGovernorRegionForPlayer(src)
        end)
        if ok and reg and reg ~= '' then
            return normRegion(reg)
        end
    end

    -- Fallback: use rsg-economy region detector if available
    if TAX_RES then
        local ok, hash, alias = pcall(function()
            return exports[TAX_RES]:GetPlayerRegion(src)
        end)
        if ok and alias and alias ~= '' then
            return normRegion(alias)
        end
    end

    return 'unknown'
end

--======================================================================
-- PAYROLL COMPUTATION (REGION-LEVEL, USED BY /govpayroll & UI)
--======================================================================

-- Returns:
--   {
--      totalPay = number,
--      byCitizen = {
--         [citizenid] = {
--            citizenid, job_name, job_label, job_type, grade,
--            regular_min, ot_min, pay
--         }, ...
--      }
--   }
local function computePayrollForRegion(regionName)
    local reg = normRegion(regionName)

    local rows = MySQL.query.await(([[ 
        SELECT id, citizenid, job_name, job_label, job_type, grade,
               minutes_regular, minutes_overtime
        FROM %s
        WHERE region_name = ? AND paid = 0
    ]]):format(DUTY_TABLE), { reg }) or {}

    if #rows == 0 then
        return { totalPay = 0, byCitizen = {} }
    end

    local perCitizen = {}
    local totalPay   = 0

    for _, row in ipairs(rows) do
        local citizenid = row.citizenid
        local jobName   = row.job_name
        local jobType   = row.job_type
        local grade     = tonumber(row.grade or 0) or 0
        local regMin    = tonumber(row.minutes_regular or 0) or 0
        local otMin     = tonumber(row.minutes_overtime or 0) or 0

        -- Re-derive jobType if column is missing
        if (not jobType or jobType == '') and jobName then
            local jobDef = RSGCore.Shared.Jobs and RSGCore.Shared.Jobs[jobName]
            jobType = jobDef and jobDef.type or 'civ'
        end

        -- Hourly base from job config
        local jobDef   = RSGCore.Shared.Jobs and RSGCore.Shared.Jobs[jobName]
        local gradeStr = tostring(grade)
        local hourly   = 0
        if jobDef and jobDef.grades and jobDef.grades[gradeStr] then
            hourly = tonumber(jobDef.grades[gradeStr].payment or 0) or 0
        end

        if hourly > 0 and (regMin > 0 or otMin > 0) then
            local regularPay   = (regMin / 60.0) * hourly
            local otMultiplier = (Config.Payroll and Config.Payroll.OvertimeMultiplier) or 1.5
            local overtimePay  = (otMin / 60.0) * hourly * otMultiplier
            local pay          = regularPay + overtimePay

            local entry = perCitizen[citizenid]
            if not entry then
                entry = {
                    citizenid    = citizenid,
                    job_name     = jobName,
                    job_label    = row.job_label or jobName,
                    job_type     = jobType or 'civ',
                    grade        = grade,
                    regular_min  = 0,
                    ot_min       = 0,
                    pay          = 0.0,
                }
                perCitizen[citizenid] = entry
            end

            entry.regular_min = entry.regular_min + regMin
            entry.ot_min      = entry.ot_min + otMin
            entry.pay         = entry.pay + pay
            totalPay          = totalPay + pay
        end
    end

    return {
        totalPay = totalPay,
        byCitizen = perCitizen
    }
end

-- old region-wide marker (kept for compatibility, not used now)
local function markSessionsPaidForRegion(regionName)
    local reg = normRegion(regionName)
    MySQL.update.await(([[ 
        UPDATE %s SET paid = 1 WHERE region_name = ? AND paid = 0
    ]]):format(DUTY_TABLE), { reg })
end

-- NEW: mark sessions paid for a specific citizen in a region
local function markSessionsPaidForCitizen(regionName, citizenid)
    local reg = normRegion(regionName)
    MySQL.update.await(([[ 
        UPDATE %s
           SET paid = 1
         WHERE region_name = ? AND citizenid = ? AND paid = 0
    ]]):format(DUTY_TABLE), { reg, citizenid })
end

--======================================================================
-- PERMISSIONS
--======================================================================

local function canDoPayroll(src, regionName)
    if isOwner(src) then return true end
    if not Gov.CanActOnRegion then return false end
    return Gov.CanActOnRegion(src, regionName, 'payroll.run')
end

--======================================================================
-- GOVERNOR COMMAND: /govpayroll (CLI fallback)
--======================================================================

-- /govpayroll [region|here]
RSGCore.Commands.Add('govpayroll', 'Run payroll for your region', {
    { name = 'region', help = 'region name or "here"' },
}, false, function(source, args)
    local src    = source
    local region = args[1]

    if not region or region == '' or region == 'here' then
        local reg = nil
        if exports['rsg-governor'] and exports['rsg-governor'].GetGovernorRegionForPlayer then
            local ok, r = pcall(function()
                return exports['rsg-governor']:GetGovernorRegionForPlayer(src)
            end)
            if ok and r and r ~= '' then
                reg = r
            end
        end
        if not reg then
            notify(src, 'Unable to determine your governor region.', 'error')
            return
        end
        region = reg
    end

    local regionNorm = normRegion(region)

    if not canDoPayroll(src, regionNorm) then
        notify(src, ('You are not allowed to run payroll for "%s".'):format(regionNorm), 'error')
        return
    end

    -- Compute payroll
    local payroll = computePayrollForRegion(regionNorm)
    if payroll.totalPay <= 0 then
        notify(src, ('No unpaid duty sessions found for region "%s".'):format(regionNorm), 'inform')
        return
    end

    -- Resolve region hash for treasury
    local regionHash = nil
    local okHash, hash = pcall(function()
        return exports[TAX_RES]:ResolveRegionHash(regionNorm)
    end)
    if okHash and hash then
        regionHash = hash
    end

    if not regionHash then
        notify(src, 'Could not resolve region hash for treasury. Payroll aborted.', 'error')
        return
    end

    -- Pay only ONLINE players, credit FULL amount from treasury
    local toPay         = {}
    local totalThisRun  = 0.0
    for citizenid, entry in pairs(payroll.byCitizen) do
        local player = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
        if player then
            local amt = entry.pay
            if amt > 0 then
                toPay[#toPay+1] = {
                    src       = player.PlayerData.source,
                    citizenid = citizenid,
                    amount    = amt,
                    entry     = entry
                }
                totalThisRun = totalThisRun + amt
            end
        end
    end

    if totalThisRun <= 0 then
        notify(src, 'No online employees with unpaid duty sessions to pay.', 'inform')
        return
    end

    -- Withdraw from treasury (async)
    exports[TAX_RES]:WithdrawFromTreasury(regionHash, math.floor(totalThisRun + 0.5), src, function(ok, newBal)
        if not ok then
            notify(src, 'Treasury does not have enough funds or you are not permitted to withdraw.', 'error')
            return
        end

        -- Pay players using their preferred account (cash or bank branch)
        for _, p in ipairs(toPay) do
            local player = RSGCore.Functions.GetPlayer(p.src)
            if player then
                local amount    = math.floor(p.amount + 0.5)
                local citizenid = p.citizenid
                --local moneytype = getPayrollAccountForCitizen(citizenid)
                local moneytype = getPayrollAccountForCitizen(citizenid, regionNorm)

                local ok = player.Functions.AddMoney(moneytype, amount, ('gov-payroll-%s'):format(regionNorm))
                if ok then
                    notify(
                        p.src,
                        ('You received $%d in salary (region: %s, account: %s).'):format(amount, regionNorm, moneytype),
                        'success'
                    )
                    -- Only mark sessions paid if the deposit succeeded
                    markSessionsPaidForCitizen(regionNorm, citizenid)
                else
                    notify(
                        p.src,
                        ('Payroll deposit of $%d to your %s account failed.'):format(amount, moneytype),
                        'error'
                    )
                end
            end
        end

        notify(src, ('Payroll complete for %s. Paid $%d to %d employees. New treasury: $%d.')
            :format(regionNorm, math.floor(totalThisRun + 0.5), #toPay, math.floor(newBal or 0)), 'success')
    end)
end, 'user')

--======================================================================
-- OX_LIB CALLBACKS FOR GOVERNOR UI (REGION PAYROLL SUMMARY)
--======================================================================

-- Helper: build per-office summary from payroll + governor_offices + treasury
local function buildPayrollSummary(regionName)
    local regionNorm = normRegion(regionName)

    local payroll = computePayrollForRegion(regionNorm)
    local offices = {}

    -- Load office definitions for this region
    local rows = MySQL.query.await([[
        SELECT office_key, office_label, salary_share, supply_share
        FROM governor_offices
        WHERE region_name = ?
    ]], { regionNorm }) or {}

    local officeDefs = {}
    for _, r in ipairs(rows) do
        officeDefs[r.office_key] = {
            key          = r.office_key,
            label        = r.office_label or r.office_key,
            salary_share = tonumber(r.salary_share or 0) or 0,
            supply_share = tonumber(r.supply_share or 0) or 0,
        }
    end

    -- Aggregate unpaid minutes & pay per office
    for _, entry in pairs(payroll.byCitizen) do
        local jobType = entry.job_type or 'civ'
        local officeKey
        if jobType == 'leo' then
            officeKey = 'lawman'
        elseif jobType == 'medic' then
            officeKey = 'medic'
        else
            officeKey = 'other'
        end

        if not offices[officeKey] then
            local def = officeDefs[officeKey] or { key = officeKey, label = officeKey, salary_share = 0, supply_share = 0 }
            offices[officeKey] = {
                office_key     = def.key,
                office_label   = def.label,
                salary_share   = def.salary_share,
                supply_share   = def.supply_share,
                regular_min    = 0,
                ot_min         = 0,
                estimated_cost = 0.0,
            }
        end

        local o = offices[officeKey]
        o.regular_min    = o.regular_min + (entry.regular_min or 0)
        o.ot_min         = o.ot_min + (entry.ot_min or 0)
        o.estimated_cost = o.estimated_cost + (entry.pay or 0)
    end

    -- Fetch treasury balance (blocking wait around callback)
    local treasuryBalance = 0
    local regionHash = nil
    local okHash, hash = pcall(function()
        return exports[TAX_RES]:ResolveRegionHash(regionNorm)
    end)
    if okHash and hash then
        regionHash = hash
    end

    if regionHash then
        local balance = nil
        exports[TAX_RES]:GetTreasuryBalance(regionHash, function(bal)
            balance = bal
        end)
        local t0 = GetGameTimer()
        while balance == nil and (GetGameTimer() - t0) < 5000 do
            Wait(0)
        end
        treasuryBalance = tonumber(balance or 0) or 0
    end

    -- compute salary + supply budgets from shares
    local totalBudget = 0

    for _, o in pairs(offices) do
        local salShare = tonumber(o.salary_share or 0) or 0
        local supShare = tonumber(o.supply_share or 0) or 0

        o.salary_budget = treasuryBalance * salShare
        o.supply_budget = treasuryBalance * supShare

        totalBudget = totalBudget + (o.salary_budget or 0) + (o.supply_budget or 0)
    end

    return {
        region              = regionNorm,
        treasury            = treasuryBalance,
        total_estimated_pay = payroll.totalPay,
        total_budget        = totalBudget,
        offices             = offices
    }
end

-- Governor panel: get payroll summary for region
lib.callback.register('rsg-governor:getPayrollSummary', function(src, regionName)
    if not regionName or regionName == '' then
        return nil
    end

    local regionNorm = normRegion(regionName)

    if not canDoPayroll(src, regionNorm) then
        return nil
    end

    return buildPayrollSummary(regionNorm)
end)

-- Governor panel: get employee breakdown for region (+ optional office filter)
lib.callback.register('rsg-governor:getPayrollEmployees', function(src, data)
    data = data or {}
    local regionName  = data.region or data.regionName
    local officeKey   = data.office

    if not regionName or regionName == '' then
        return {}
    end

    local regionNorm = normRegion(regionName)
    if not canDoPayroll(src, regionNorm) then
        return {}
    end

    local rows = MySQL.query.await(([[
        SELECT id, citizenid, job_name, job_label, job_type, grade,
               minutes_regular, minutes_overtime
        FROM %s
        WHERE region_name = ? AND paid = 0
    ]]):format(DUTY_TABLE), { regionNorm }) or {}

    if #rows == 0 then
        return {}
    end

    local byCitizen = {}

    for _, row in ipairs(rows) do
        local jobName = row.job_name
        local jobType = row.job_type

        if (not jobType or jobType == '') and jobName then
            local jobDef = RSGCore.Shared.Jobs and RSGCore.Shared.Jobs[jobName]
            jobType = jobDef and jobDef.type or 'civ'
        end

        local thisOffice = 'other'
        if jobType == 'leo' then
            thisOffice = 'lawman'
        elseif jobType == 'medic' then
            thisOffice = 'medic'
        end

        if officeKey and officeKey ~= '' and thisOffice ~= officeKey then
            goto continue
        end

        local citizenid = row.citizenid
        local grade     = tonumber(row.grade or 0) or 0
        local regMin    = tonumber(row.minutes_regular or 0) or 0
        local otMin     = tonumber(row.minutes_overtime or 0) or 0

        local jobDef   = RSGCore.Shared.Jobs and RSGCore.Shared.Jobs[jobName]
        local gradeStr = tostring(grade)
        local hourly   = 0
        if jobDef and jobDef.grades and jobDef.grades[gradeStr] then
            hourly = tonumber(jobDef.grades[gradeStr].payment or 0) or 0
        end

        local pay = 0
        if hourly > 0 and (regMin > 0 or otMin > 0) then
            local regularPay   = (regMin / 60.0) * hourly
            local otMultiplier = (Config.Payroll and Config.Payroll.OvertimeMultiplier) or 1.5
            local overtimePay  = (otMin / 60.0) * hourly * otMultiplier
            pay                = regularPay + overtimePay
        end

        local entry = byCitizen[citizenid]
        if not entry then
            -- Try get name from online player
            local name = ('Citizen %s'):format(string.sub(citizenid, -4))
            local player = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
            if player and player.PlayerData and player.PlayerData.charinfo then
                local ci = player.PlayerData.charinfo
                if ci.firstname and ci.lastname then
                    name = ci.firstname .. ' ' .. ci.lastname
                end
            end

            entry = {
                citizenid   = citizenid,
                name        = name,
                job_name    = jobName,
                job_label   = row.job_label or (jobDef and jobDef.label) or jobName,
                job_type    = jobType or 'civ',
                grade       = grade,
                regular_min = 0,
                ot_min      = 0,
                pay         = 0,
                sessions    = {}
            }
            byCitizen[citizenid] = entry
        end

        entry.regular_min = entry.regular_min + regMin
        entry.ot_min      = entry.ot_min + otMin
        entry.pay         = entry.pay + pay

        entry.sessions[#entry.sessions+1] = {
            id      = row.id,
            reg_min = regMin,
            ot_min  = otMin,
        }

        ::continue::
    end

    local result = {}
    for _, entry in pairs(byCitizen) do
        result[#result+1] = entry
    end

    table.sort(result, function(a, b)
        return (a.pay or 0) > (b.pay or 0)
    end)

    return result
end)

-- Governor panel: run payroll from UI (sync)
lib.callback.register('rsg-governor:runPayroll', function(src, regionName)
    if not regionName or regionName == '' then
        return { ok = false, error = 'No region specified.' }
    end

    local regionNorm = normRegion(regionName)

    if not canDoPayroll(src, regionNorm) then
        return { ok = false, error = 'Not allowed to run payroll for this region.' }
    end

    local payroll = computePayrollForRegion(regionNorm)
    if payroll.totalPay <= 0 then
        return { ok = false, error = 'No unpaid duty sessions for this region.' }
    end

    local regionHash = nil
    local okHash, hash = pcall(function()
        return exports[TAX_RES]:ResolveRegionHash(regionNorm)
    end)
    if okHash and hash then
        regionHash = hash
    end

    if not regionHash then
        return { ok = false, error = 'Could not resolve region hash.' }
    end

    local toPay        = {}
    local totalThisRun = 0.0

    for citizenid, entry in pairs(payroll.byCitizen) do
        local player = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
        if player then
            local amt = entry.pay
            if amt > 0 then
                toPay[#toPay+1] = {
                    src       = player.PlayerData.source,
                    citizenid = citizenid,
                    amount    = amt,
                    entry     = entry
                }
                totalThisRun = totalThisRun + amt
            end
        end
    end

    if totalThisRun <= 0 then
        return { ok = false, error = 'No online employees to pay.' }
    end

    -- Wrap async WithdrawFromTreasury in a blocking wait
    local finished = false
    local success  = false
    local newBal   = 0

    exports[TAX_RES]:WithdrawFromTreasury(regionHash, math.floor(totalThisRun + 0.5), src, function(ok, bal)
        success  = ok
        newBal   = tonumber(bal or 0) or 0
        finished = true
    end)

    local t0 = GetGameTimer()
    while not finished and (GetGameTimer() - t0) < 5000 do
        Wait(0)
    end

    if not finished or not success then
        return { ok = false, error = 'Treasury check or withdraw failed (insufficient funds or permission).' }
    end

    -- Pay players using their preferred account (cash or bank branch)
    for _, p in ipairs(toPay) do
        local player = RSGCore.Functions.GetPlayer(p.src)
        if player then
            local amount    = math.floor(p.amount + 0.5)
            local citizenid = p.citizenid
            --local moneytype = getPayrollAccountForCitizen(citizenid)
            local moneytype = getPayrollAccountForCitizen(citizenid, regionNorm)

            local ok = player.Functions.AddMoney(moneytype, amount, ('gov-payroll-%s'):format(regionNorm))
            if ok then
                notify(
                    p.src,
                    ('You received $%d in salary (region: %s, account: %s).'):format(amount, regionNorm, moneytype),
                    'success'
                )
                -- Only mark sessions paid if the deposit succeeded
                markSessionsPaidForCitizen(regionNorm, citizenid)
            else
                notify(
                    p.src,
                    ('Payroll deposit of $%d to your %s account failed.'):format(amount, moneytype),
                    'error'
                )
            end
        end
    end

    notify(src, ('Payroll complete for %s. Paid $%d to %d employees. New treasury: $%d.')
        :format(regionNorm, math.floor(totalThisRun + 0.5), #toPay, math.floor(newBal or 0)), 'success')

    return {
        ok            = true,
        region        = regionNorm,
        paidEmployees = #toPay,
        totalPaid     = math.floor(totalThisRun + 0.5),
        newTreasury   = math.floor(newBal)
    }
end)

--======================================================================
--  Base rate + pay preference helpers (for /dutylog & officepanel)
--======================================================================

local function getBaseRate(jobName, grade)
    local job = RSGCore.Shared.Jobs[jobName]
    if not job or not job.grades then return 0 end

    local gKey     = tostring(grade or 0)
    local gradeCfg = job.grades[gKey]
    if not gradeCfg then return 0 end

    return tonumber(gradeCfg.payment or 0) or 0
end

-- Pay preference helpers (mode + bank branch)
local function getPayPreference(citizenid)
    local row = MySQL.single.await([[
        SELECT pay_mode, bank_branch
        FROM governor_pay_prefs
        WHERE citizenid = ?
    ]], { citizenid })

    local mode   = 'bank'
    local branch = nil

    if row then
        if row.pay_mode and row.pay_mode ~= '' then
            mode = row.pay_mode
        end
        if row.bank_branch and row.bank_branch ~= '' then
            branch = row.bank_branch
        end
    end

    return mode, branch
end

local function getPayMode(citizenid)
    local mode = getPayPreference(citizenid)
    return mode
end

-- Decide which money account to use for payroll (cash vs region bank)
function getPayrollAccountForCitizen(citizenid, regionName)
    local mode = getPayMode(citizenid)  -- uses getPayPreference under the hood
    mode = tostring(mode or 'bank'):lower()

    -- If player prefers cash, pay cash
    if mode == 'cash' then
        return 'cash'
    end

    -- Otherwise, use region-default bank (valbank, rhobank, etc.)
    local reg = normRegion(regionName or 'unknown')
    local bankId = 'bank' -- fallback to generic bank (Saint Denis)

    if Config.RegionBankDefaults and Config.RegionBankDefaults[reg] then
        bankId = Config.RegionBankDefaults[reg]
    end

    return bankId
end

local function setPayMode(citizenid, mode, branchId)
    mode = tostring(mode or 'bank'):lower()
    if mode ~= 'cash' and mode ~= 'bank' then
        mode = 'bank'
    end

    -- When branchId is nil, we do not overwrite existing branch
    MySQL.insert.await([[
        INSERT INTO governor_pay_prefs (citizenid, pay_mode, bank_branch)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            pay_mode    = VALUES(pay_mode),
            bank_branch = COALESCE(VALUES(bank_branch), bank_branch),
            updated_at  = CURRENT_TIMESTAMP
    ]], { citizenid, mode, branchId })
end

local function normalizeStamp(v)
    if type(v) == 'number' then
        -- oxmysql may give ms or sec; detect and convert
        local s = v
        if s > 1e12 then  -- definitely ms
            s = math.floor(s / 1000)
        else
            s = math.floor(s)
        end
        return os.date('%Y-%m-%d %H:%M:%S', s)
    elseif type(v) == 'string' then
        -- already a datetime string like "2025-11-26 05:52:47"
        return v
    else
        return '?'
    end
end

--======================================================================
--  HELPERS FOR DUTY CLOCK (CLOSE SESSION + OVERTIME SPLIT)
--======================================================================

-- 8 hours regular, rest overtime (per session, in IN-GAME time)
local function splitRegularOvertime(elapsedGameMin)
    elapsedGameMin = tonumber(elapsedGameMin or 0) or 0
    if elapsedGameMin <= 0 then
        return 1, 0 -- never 0-minute
    end

    -- Configurable, but default to 8h (480 min) if not set
    local overtimeCfg = (Config.Payroll and Config.Payroll.OvertimeMinutes) or (8 * 60)

    local regMin, otMin = elapsedGameMin, 0
    if overtimeCfg > 0 and elapsedGameMin > overtimeCfg then
        regMin = overtimeCfg
        otMin  = elapsedGameMin - overtimeCfg
    end

    return regMin, otMin
end

-- Close the latest open duty session for a citizen using an in-game clock snapshot
local function finalizeOpenDutySession(citizenid, igClock, realEnd)
    if not citizenid or not igClock then return end

    local igYear   = igClock.year   or 1898
    local igMonth  = igClock.month  or 1
    local igDay    = igClock.day    or 1
    local igHour   = igClock.hour   or 0
    local igMinute = igClock.minute or 0

    realEnd = realEnd or os.date('%Y-%m-%d %H:%M:%S', os.time())

    local rows = MySQL.query.await(([[
        SELECT
            id,
            started_at,
            ig_start_year,
            ig_start_month,
            ig_start_day,
            ig_start_hour,
            ig_start_minute
        FROM %s
        WHERE citizenid = ? AND ended_at IS NULL
        ORDER BY id DESC
        LIMIT 1
    ]]):format(DUTY_TABLE), { citizenid })

    if not rows or not rows[1] then
        return
    end

    local row   = rows[1]
    local rowId = row.id

    -- Build IN-GAME start and end timestamps
    local sYear   = tonumber(row.ig_start_year)   or igYear
    local sMonth  = tonumber(row.ig_start_month)  or igMonth
    local sDay    = tonumber(row.ig_start_day)    or igDay
    local sHour   = tonumber(row.ig_start_hour)   or igHour
    local sMinute = tonumber(row.ig_start_minute) or igMinute

    local startGameTs = os.time({
        year  = sYear,
        month = sMonth,
        day   = sDay,
        hour  = sHour,
        min   = sMinute,
        sec   = 0,
    })

    local endGameTs = os.time({
        year  = igYear,
        month = igMonth,
        day   = igDay,
        hour  = igHour,
        min   = igMinute,
        sec   = 0,
    })

    local elapsedGameSec = math.max(0, endGameTs - startGameTs)
    local elapsedGameMin = math.floor(elapsedGameSec / 60)
    if elapsedGameMin <= 0 then
        elapsedGameMin = 1
    end

    local regMin, otMin = splitRegularOvertime(elapsedGameMin)

    MySQL.update.await(([[
        UPDATE %s SET
            ended_at         = ?,
            minutes_regular  = ?,
            minutes_overtime = ?,
            ig_end_year      = ?,
            ig_end_month     = ?,
            ig_end_day       = ?,
            ig_end_hour      = ?,
            ig_end_minute    = ?
        WHERE id = ?
    ]]):format(DUTY_TABLE), {
        realEnd,
        regMin,
        otMin,
        igYear,
        igMonth,
        igDay,
        igHour,
        igMinute,
        rowId
    })
end

--=====================================================
--  /dutylog callback for players
--=====================================================
lib.callback.register('rsg-governor:getDutyLog', function(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return nil end

    local citizenid = Player.PlayerData.citizenid
    local job       = Player.PlayerData.job or {}
    local jobName   = job.name or 'unemployed'

    -- Normalize grade to numeric level (handles both legacy and new job.grade formats)
    local gradeLevel = 0
    if type(job.grade) == 'table' then
        gradeLevel = tonumber(job.grade.level) or 0
    else
        gradeLevel = tonumber(job.grade) or 0
    end

    local baseRate              = getBaseRate(jobName, gradeLevel)
    local payMode, bankBranchId = getPayPreference(citizenid)

    -- detect region (alias string used for display + office settings)
    local ok, regionHash, regionAlias = pcall(function()
        return lib.callback.await('rsg-economy:getRegionHash', src)
    end)

    if not ok or not regionAlias then regionAlias = "unknown" end
    regionAlias = tostring(regionAlias):lower()

    -- Office payroll settings (manual/auto)
    local officeMode, officeSchedule = 'manual', 'weekly'
    local settingsRow = MySQL.single.await([[
        SELECT pay_mode, auto_schedule
        FROM governor_office_settings
        WHERE region_alias = ? AND job_name = ?
        LIMIT 1
    ]], { regionAlias, jobName })

    if settingsRow then
        if settingsRow.pay_mode and settingsRow.pay_mode ~= '' then
            officeMode = settingsRow.pay_mode
        end
        if settingsRow.auto_schedule and settingsRow.auto_schedule ~= '' then
            officeSchedule = settingsRow.auto_schedule
        end
    end

    -- CONFIGURE WHAT TO SHOW (with safe defaults)
    local dutyCfg    = Config.DutyLog or {}
    local mode       = dutyCfg.Mode or 'unpaid_plus_recent_paid'
    local recentDays = dutyCfg.RecentDays or 14
    local limitPaid  = dutyCfg.MaxPaidHistory or 50  -- currently unused but kept

    -- UNPAID rows
    local unpaid = MySQL.query.await([[
        SELECT
            id,
            started_at,
            ended_at,
            job_name,
            grade,
            minutes_regular,
            minutes_overtime,
            paid,
            ig_start_year,
            ig_start_month,
            ig_start_day,
            ig_start_hour,
            ig_start_minute,
            ig_end_year,
            ig_end_month,
            ig_end_day,
            ig_end_hour,
            ig_end_minute
        FROM governor_duty_sessions
        WHERE citizenid = ? AND paid = 0
        ORDER BY ended_at DESC
    ]], { citizenid }) or {}

    -- PAID rows (depending on mode)
    local paid = {}

    if mode == 'unpaid_plus_recent_paid' then
        paid = MySQL.query.await([[
            SELECT
                id,
                started_at,
                ended_at,
                job_name,
                grade,
                minutes_regular,
                minutes_overtime,
                paid,
                ig_start_year,
                ig_start_month,
                ig_start_day,
                ig_start_hour,
                ig_start_minute,
                ig_end_year,
                ig_end_month,
                ig_end_day,
                ig_end_hour,
                ig_end_minute
            FROM governor_duty_sessions
            WHERE citizenid = ? AND paid = 1
            ORDER BY ended_at DESC
        ]], { citizenid }) or {}

    elseif mode == 'recent_days' then
        paid = MySQL.query.await([[
            SELECT
                id,
                started_at,
                ended_at,
                job_name,
                grade,
                minutes_regular,
                minutes_overtime,
                paid,
                ig_start_year,
                ig_start_month,
                ig_start_day,
                ig_start_hour,
                ig_start_minute,
                ig_end_year,
                ig_end_month,
                ig_end_day,
                ig_end_hour,
                ig_end_minute
            FROM governor_duty_sessions
            WHERE citizenid = ? AND ended_at >= NOW() - INTERVAL ? DAY
            ORDER BY ended_at DESC
        ]], { citizenid, recentDays }) or {}

    elseif mode == 'all' then
        paid = MySQL.query.await([[
            SELECT
                id,
                started_at,
                ended_at,
                job_name,
                grade,
                minutes_regular,
                minutes_overtime,
                paid,
                ig_start_year,
                ig_start_month,
                ig_start_day,
                ig_start_hour,
                ig_start_minute,
                ig_end_year,
                ig_end_month,
                ig_end_day,
                ig_end_hour,
                ig_end_minute
            FROM governor_duty_sessions
            WHERE citizenid = ?
            ORDER BY ended_at DESC
        ]], { citizenid }) or {}

    elseif mode == 'unpaid_only' then
        paid = {}
    end

    -- Calculate totals
    local totalReg = 0
    local totalOT  = 0
    local totalPay = 0

    local sessions = {}

    local function addRows(rows)
        for _, r in ipairs(rows or {}) do
            local regH = (r.minutes_regular  or 0) / 60
            local otH  = (r.minutes_overtime or 0) / 60

            -- 🔴 CRITICAL: normalize paid flag to numeric 0/1
            local paidFlag = 0
            if r.paid == true then
                paidFlag = 1
            else
                paidFlag = tonumber(r.paid) or 0
            end
            if paidFlag ~= 0 then paidFlag = 1 end

            local otMult = (Config.Payroll and Config.Payroll.OvertimeMultiplier) or 1.5
            local est    = (regH * baseRate) + (otH * baseRate * otMult)

            totalReg = totalReg + regH
            totalOT  = totalOT + otH

            -- Only unpaid sessions contribute to "unpaid_total"
            if paidFlag == 0 then
                totalPay = totalPay + est
            end

            local sStart = normalizeStamp(r.started_at)
            local sEnd   = normalizeStamp(r.ended_at)

            sessions[#sessions+1] = {
                id        = r.id,
                paid      = paidFlag,   -- << numeric for client
                regular   = regH,
                overtime  = otH,
                estimated = est,

                -- real world timestamps
                started_at = sStart,
                ended_at   = sEnd,
                real_start = sStart,
                real_end   = sEnd,

                -- in-game timestamps
                ig_start_year   = r.ig_start_year,
                ig_start_month  = r.ig_start_month,
                ig_start_day    = r.ig_start_day,
                ig_start_hour   = r.ig_start_hour,
                ig_start_minute = r.ig_start_minute,
                ig_end_year     = r.ig_end_year,
                ig_end_month    = r.ig_end_month,
                ig_end_day      = r.ig_end_day,
                ig_end_hour     = r.ig_end_hour,
                ig_end_minute   = r.ig_end_minute,
            }
        end
    end

    -- Unpaid first, then paid history
    addRows(unpaid)
    addRows(paid)

    -- Resolve bank branch label (from Config.BankBranches)
    local branchCfg = nil
    if bankBranchId and Config and Config.BankBranches then
        branchCfg = Config.BankBranches[bankBranchId]
    end

    return {
        region               = regionAlias,
        job_name             = jobName,
        grade                = gradeLevel,
        pay_mode             = payMode,
        bank_branch_id       = bankBranchId,
        bank_branch_label    = branchCfg and branchCfg.label or nil,
        base_rate            = baseRate,
        overtime_multiplier  = (Config.Payroll and Config.Payroll.OvertimeMultiplier) or 1.5,
        unpaid_regular       = totalReg,
        unpaid_overtime      = totalOT,
        unpaid_total         = totalPay,
        office_pay_mode      = officeMode,
        office_auto_schedule = officeSchedule,
        sessions             = sessions
    }
end)

--=====================================================
--  /dutylog payment mode setter
--=====================================================
lib.callback.register('rsg-governor:setPayMode', function(src, mode, branchId)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end

    mode = tostring(mode or 'bank'):lower()
    if mode ~= 'bank' and mode ~= 'cash' then
        return false
    end

    local citizenid = Player.PlayerData.citizenid

    if mode == 'bank' then
        -- expect a branchId such as 'valbank', 'rhobank', 'bank', 'blkbank', 'armbank'
        setPayMode(citizenid, 'bank', branchId)
    else
        -- cash: update mode but keep any previously saved bank branch
        setPayMode(citizenid, 'cash', nil)
    end

    return true
end)

--=====================================================
--  DUTY CLOCK HANDLING (called from client)
--=====================================================

-- Store last clock + duty state per player (for disconnect auto-off)
RegisterNetEvent('rsg-governor:server:duty:recordClock', function(clockData, isOnDuty)
    local src = source
    if type(clockData) ~= 'table' then return end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    dutyClock[src] = dutyClock[src] or {}
    dutyClock[src].lastClock = {
        year   = clockData.year   or 1898,
        month  = clockData.month  or 1,
        day    = clockData.day    or 1,
        hour   = clockData.hour   or 0,
        minute = clockData.minute or 0,
    }
    dutyClock[src].isOnDuty  = isOnDuty and true or false
    dutyClock[src].citizenid = citizenid
end)

RegisterNetEvent('rsg-governor:server:duty:updateClock', function(clock, isOnDuty)
    local src = source
    if type(clock) ~= 'table' then return end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizen  = Player.PlayerData.citizenid
    local job      = Player.PlayerData.job or {}
    local jobName  = job.name or 'unemployed'
    local jobType  = job.type or 'civ'
    local grade    = job.grade and job.grade.level or job.grade or 0
    local region   = getRegionAliasForPlayer(src)

    -- Keep dutyClock cache updated ALWAYS (for disconnect auto-off)
    dutyClock[src] = dutyClock[src] or {}
    dutyClock[src].lastClock = {
        year   = clock.year   or 1898,
        month  = clock.month  or 1,
        day    = clock.day    or 1,
        hour   = clock.hour   or 0,
        minute = clock.minute or 0,
    }
    dutyClock[src].isOnDuty  = isOnDuty and true or false
    dutyClock[src].citizenid = citizen

    -- Real-world timestamp now (server time)
    local now     = os.time()
    local realNow = os.date('%Y-%m-%d %H:%M:%S', now)

    -- In-game snapshot
    local igYear   = clock.year   or 1898
    local igMonth  = clock.month  or 1
    local igDay    = clock.day    or 1
    local igHour   = clock.hour   or 0
    local igMinute = clock.minute or 0

    if isOnDuty then
        ----------------------------------------------------------------
        -- SAFEGUARD:
        -- If there is already an unfinished session for this citizenid,
        -- DO NOT open a new one (ignore double /duty on).
        ----------------------------------------------------------------
        local open = MySQL.single.await(([[
            SELECT id FROM %s
            WHERE citizenid = ? AND ended_at IS NULL
            ORDER BY id DESC
            LIMIT 1
        ]]):format(DUTY_TABLE), { citizen })

        if open then
            print(('[rsg-governor] Ignoring extra ON-duty toggle for %s (open session id=%d)'):format(citizen, open.id or 0))
            notify(src, 'You already have a running duty session in the governor log. Not opening a new one.', 'error')
            return
        end

        ----------------------------------------------------------------
        -- No open session -> create a fresh one
        ----------------------------------------------------------------
        local sessionId = MySQL.insert.await(([[
            INSERT INTO %s
                (citizenid,
                 job_name, job_label, job_type, grade, region_name,
                 started_at, ended_at,
                 minutes_regular, minutes_overtime, paid,
                 ig_start_year, ig_start_month, ig_start_day,
                 ig_start_hour, ig_start_minute,
                 ig_end_year, ig_end_month, ig_end_day,
                 ig_end_hour, ig_end_minute)
            VALUES (
                ?, ?, ?, ?, ?, ?,
                ?, NULL,
                0, 0, 0,
                ?, ?, ?,
                ?, ?,
                NULL, NULL, NULL,
                NULL, NULL
            )
        ]]):format(DUTY_TABLE), {
            citizen,
            jobName,
            job.label or jobName,
            jobType,
            grade,
            region,
            realNow,              -- started_at (real)
            igYear, igMonth, igDay,
            igHour, igMinute
        })

        if not sessionId then
            print(('[rsg-governor] Failed to insert duty session for %s'):format(citizen))
        end
    else
        ----------------------------------------------------------------
        -- OFF duty → close latest open session using IN-GAME duration
        ----------------------------------------------------------------
        finalizeOpenDutySession(citizen, {
            year   = igYear,
            month  = igMonth,
            day    = igDay,
            hour   = igHour,
            minute = igMinute,
        }, realNow)

        dutyClock[src].isOnDuty = false
    end
end)

-- Auto-OFF when player disconnects (prevents "infinite" ongoing sessions)
AddEventHandler('playerDropped', function(_reason)
    local src  = source
    local info = dutyClock[src]

    if info and info.isOnDuty and info.citizenid and info.lastClock then
        -- Use the LAST in-game clock snapshot sent from the client
        finalizeOpenDutySession(info.citizenid, info.lastClock)
    end

    dutyClock[src] = nil
end)

-- /dutylog - open the player's own duty log UI
RSGCore.Commands.Add('dutylog', 'Open your duty log', {}, false, function(source, _)
    TriggerClientEvent('rsg-governor:client:openDutyLog', source)
end, 'user')
