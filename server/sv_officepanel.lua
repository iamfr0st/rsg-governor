--======================================================================
-- rsg-governor / server/sv_officepanel.lua
-- Office Panel: payroll settings, manual payroll, and supply orders
--======================================================================

local RSGCore = exports['rsg-core']:GetCoreObject()

-- DB tables
local OFFICE_ALLOC_TABLE    = 'governor_offices'
local OFFICE_SETTINGS_TABLE = 'governor_office_settings'

-- Use shared BankBranches from config
local BankBranches = Config.BankBranches or {}

--=====================================================
--  Base rate helper (same logic as duty/payroll)
--=====================================================

local function getBaseRate(jobName, gradeLevel)
    jobName    = tostring(jobName or 'unemployed')
    gradeLevel = tonumber(gradeLevel or 0) or 0

    local baseRate = 0

    -- 1) Config.Payroll.BaseRates override (optional)
    if Config.Payroll and Config.Payroll.BaseRates then
        local cfg = Config.Payroll.BaseRates[jobName]
        if type(cfg) == 'table' then
            baseRate = tonumber(cfg[gradeLevel])
                or tonumber(cfg[tostring(gradeLevel)])
                or tonumber(cfg.base)
                or 0
        elseif cfg ~= nil then
            baseRate = tonumber(cfg) or 0
        end
    end

    -- 2) Fallback to RSGShared.Jobs or RSGCore.Shared.Jobs
    if not baseRate or baseRate <= 0 then
        local jobsCfg = nil

        if RSGShared and RSGShared.Jobs then
            jobsCfg = RSGShared.Jobs
        elseif RSGCore and RSGCore.Shared and RSGCore.Shared.Jobs then
            jobsCfg = RSGCore.Shared.Jobs
        end

        if jobsCfg then
            local jobCfg  = jobsCfg[jobName]
            local grades  = jobCfg and jobCfg.grades or nil
            local gRow    = grades and grades[tostring(gradeLevel)] or nil

            if gRow and gRow.payment then
                baseRate = tonumber(gRow.payment) or 0
            end
        end
    end

    return baseRate or 0
end

--=====================================================
--  Pay preference helpers (mode + bank branch)
--=====================================================

local function getPayPreference(citizenid)
    local row = MySQL.single.await([[
        SELECT pay_mode, bank_branch
        FROM governor_pay_prefs
        WHERE citizenid = ?
    ]], { citizenid })

    local mode   = 'cash'
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

--=====================================================
--  Office pay settings (governor_office_settings)
--=====================================================

local ValidSchedules = {
    weekly        = true,
    semi_monthly  = true,
    monthly_end   = true,
    saturday      = true,
}

local function normalizeOfficeSettings(row)
    local mode = (row and row.pay_mode) or 'manual'
    mode = (mode == 'auto') and 'auto' or 'manual'

    local sched = (row and row.auto_schedule) or 'weekly'
    if not ValidSchedules[sched] then
        sched = 'weekly'
    end

    return mode, sched
end

-- governor_office_settings(region_alias, job_name, pay_mode, auto_schedule)
local function fetchOfficeSettings(regionAlias, jobName)
    regionAlias = tostring(regionAlias or 'unknown'):lower()
    jobName     = tostring(jobName or 'unemployed'):lower()

    local rows = MySQL.query.await(string.format([[
        SELECT pay_mode, auto_schedule
        FROM %s
        WHERE region_alias = ? AND job_name = ?
        LIMIT 1
    ]], OFFICE_SETTINGS_TABLE), { regionAlias, jobName })

    if rows and rows[1] then
        local mode, sched = normalizeOfficeSettings(rows[1])
        return mode, sched
    end

    local defaultMode  = 'manual'
    local defaultSched = 'saturday'

    MySQL.insert.await(string.format([[
        INSERT INTO %s (region_alias, job_name, pay_mode, auto_schedule)
        VALUES (?, ?, ?, ?)
    ]], OFFICE_SETTINGS_TABLE), { regionAlias, jobName, defaultMode, defaultSched })

    return defaultMode, defaultSched
end

local function saveOfficeSettings(regionAlias, jobName, mode, schedule)
    regionAlias = tostring(regionAlias or 'unknown'):lower()
    jobName     = tostring(jobName or 'unemployed'):lower()

    mode = (mode == 'auto') and 'auto' or 'manual'
    if not ValidSchedules[schedule or ''] then
        schedule = 'weekly'
    end

    MySQL.insert.await(string.format([[
        INSERT INTO %s (region_alias, job_name, pay_mode, auto_schedule)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            pay_mode      = VALUES(pay_mode),
            auto_schedule = VALUES(auto_schedule)
    ]], OFFICE_SETTINGS_TABLE), { regionAlias, jobName, mode, schedule })

    return mode, schedule
end

--=====================================================
--  Office / region resolution from governor_office_heads
--=====================================================

-- governor_office_heads(region_name, office_key, citizenid, char_name, assigned_at, [optional region_hash])
-- governor_office_heads(region_name, office_key, citizenid, char_name, assigned_at)
local function getHeadOfficeRow(citizenid)
    local rows = MySQL.query.await([[
        SELECT region_name, office_key, char_name
        FROM governor_office_heads
        WHERE citizenid = ?
        LIMIT 1
    ]], { citizenid })

    if rows and rows[1] then
        return rows[1]
    end
    return nil
end

local function getHeadRegionAndOffice(citizenid)
    local row = getHeadOfficeRow(citizenid)
    if not row then
        return {
            region    = 'unknown',
            office    = nil,
            regionInfo = {
                hash  = nil,
                name  = 'unknown',
                alias = 'unknown',
                label = 'Unknown Region',
            }
        }
    end

    local regionName = row.region_name or 'unknown'

    -- 1) Start from the canonical name (new_hanover / new hanover)
    local reg = Region.FromName(regionName)
    -- reg.name  -> "new_hanover"
    -- reg.alias -> "new hanover"
    -- reg.label -> "New Hanover"
    -- reg.hash  -> nil for now

    -- 2) Try to enrich with residency data (region_hash + better alias)
    local residency = nil
    local ok, res = pcall(function()
        if exports['rsg-residency'] and exports['rsg-residency'].GetResidency then
            return exports['rsg-residency']:GetResidency(citizenid)
        end
        return nil
    end)
    if ok then
        residency = res
    end

    if residency then
        -- If residency has a region_hash, use that directly.
        if residency.region_hash and residency.region_hash ~= '' then
            reg.hash = residency.region_hash  -- already stored as hex in DB
        end

        -- If residency has a region_alias, we can prefer that for display.
        if residency.region_alias and residency.region_alias ~= '' then
            local alias = residency.region_alias
            local aliasNorm = alias:lower():gsub('[_%-]+', ' '):gsub('%s+', ' ')
            reg.alias = aliasNorm

            -- Rebuild label from alias ("new hanover" -> "New Hanover")
            reg.label = aliasNorm:gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper() .. rest:lower()
            end)
        end
    end

    return {
        region    = reg.name,     -- canonical slug: "new_hanover"
        office    = row.office_key,
        regionInfo = reg,         -- includes hash, alias, label
    }
end

--=====================================================
--  Office allocation (salary_share / supply_share / funding_share)
--=====================================================

local function deriveOfficeKey(jobName)
    jobName = tostring(jobName or 'unemployed'):lower()
    local regionPart, officePart = jobName:match('^(.+)_([^_]+)$')
    if officePart and officePart ~= '' then
        return officePart
    end
    return jobName
end

-- governor_offices(region_name, office_key, office_label,
--                  base_salary_cents, salary_share, supply_share,
--                  funding_share, is_active)
local function getOfficeAllocation(regionName, jobName)
    regionName = tostring(regionName or 'unknown')
    jobName    = tostring(jobName or 'unemployed'):lower()

    local officeKey = deriveOfficeKey(jobName)

    local rows = MySQL.query.await(string.format([[
        SELECT
            region_name,
            office_label,
            base_salary_cents,
            salary_share,
            supply_share,
            funding_share,
            is_active
        FROM %s
        WHERE region_name = ?
          AND office_key = ?
          AND is_active = 1
        LIMIT 1
    ]], OFFICE_ALLOC_TABLE), { regionName, officeKey })

    if rows and rows[1] then
        local r = rows[1]
        return {
            region_name        = r.region_name,
            office_label       = r.office_label,
            base_salary_cents  = r.base_salary_cents,
            salary_share       = tonumber(r.salary_share)  or 0.0,
            supply_share       = tonumber(r.supply_share)  or 0.0,
            funding_share      = tonumber(r.funding_share) or 1.0,
        }
    end

    return nil
end

local function getOfficeFundingShare(regionName, jobName)
    local alloc = getOfficeAllocation(regionName, jobName)
    if not alloc then return 1.0 end

    local share = alloc.funding_share or 1.0
    if share < 0.0 then share = 0.0 end
    if share > 1.0 then share = 1.0 end
    return share
end

--=====================================================
--  Treasury helpers (economy_treasury by region_hash)
--=====================================================

local function ensureTreasuryRow(regionHash)
    if not regionHash then return 0 end

    local rows = MySQL.query.await(
        'SELECT balance FROM economy_treasury WHERE region_hash = ? LIMIT 1',
        { regionHash }
    )

    if rows and rows[1] then
        return rows[1].balance or 0
    end

    MySQL.insert.await(
        'INSERT INTO economy_treasury (region_hash, balance) VALUES (?, ?)',
        { regionHash, 0 }
    )

    return 0
end

local function getTreasuryBalanceByHash(regionHash)
    if not regionHash then return 0 end

    local rows = MySQL.query.await(
        'SELECT balance FROM economy_treasury WHERE region_hash = ? LIMIT 1',
        { regionHash }
    )

    if rows and rows[1] then
        return rows[1].balance or 0
    end

    return ensureTreasuryRow(regionHash)
end

local function adjustTreasuryByHash(regionHash, delta)
    if not regionHash then return false, 0 end

    delta = math.floor(tonumber(delta or 0) or 0)
    local current = getTreasuryBalanceByHash(regionHash)
    local newBal  = current + delta

    if newBal < 0 then
        return false, current
    end

    MySQL.update.await(
        'UPDATE economy_treasury SET balance = ? WHERE region_hash = ?',
        { newBal, regionHash }
    )

    return true, newBal
end

local function deductTreasuryByHash(regionHash, amount)
    amount = math.floor(tonumber(amount or 0) or 0)
    if amount <= 0 then
        return true, getTreasuryBalanceByHash(regionHash)
    end
    return adjustTreasuryByHash(regionHash, -amount)
end

--=====================================================
--  Office Panel Data (/officepanel main UI)
--=====================================================

lib.callback.register('rsg-governor:getOfficePanelData', function(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return nil end

    local job      = Player.PlayerData.job or {}
    local jobName  = job.name or 'unemployed'
    local jobLabel = job.label or jobName

    local citizenid = Player.PlayerData.citizenid

    -- Determine region and office from governor_office_heads
    local headInfo = getHeadRegionAndOffice(citizenid)
    local regionName  = headInfo.region       -- canonical slug (e.g. "new_hanover")
    local regionInfo  = headInfo.regionInfo   -- includes hash, alias, label
    local regionLabel = regionInfo.label

    local alloc        = getOfficeAllocation(regionName, jobName)
    local officeLabel  = (alloc and alloc.office_label) or jobLabel
    local salaryShare  = (alloc and alloc.salary_share)  or 0.0
    local supplyShare  = (alloc and alloc.supply_share)  or 0.0
    local fundingShare = (alloc and alloc.funding_share) or 1.0
    if fundingShare < 0.0 then fundingShare = 0.0 end
    if fundingShare > 1.0 then fundingShare = 1.0 end

    -- Full treasury (by region_hash) and office's share
    local regionHash   = regionInfo.hash
    local rawTreasury  = getTreasuryBalanceByHash(regionHash)
    local officeBudget = math.floor(rawTreasury * fundingShare + 0.5)

    -- office settings (manual/auto, schedule) keyed by region_alias + job_name
    local regionAliasForSettings = tostring(regionInfo.alias or 'unknown'):lower()
    local payMode, autoSched     = fetchOfficeSettings(regionAliasForSettings, jobName)

    return {
        region           = regionName,
        region_label     = regionLabel,
        office_label     = officeLabel,
        job_label        = jobLabel,
        job_name         = jobName,

        pay_mode         = payMode,
        auto_schedule    = autoSched,

        treasury_balance = officeBudget,   -- office share
        treasury_raw     = rawTreasury,    -- full region treasury
        office_share     = fundingShare,
        salary_share     = salaryShare,
        supply_share     = supplyShare,
    }
end)

lib.callback.register('rsg-governor:setOfficePayMode', function(src, payload)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end

    payload = payload or {}

    local mode     = (payload.mode or 'manual'):lower()
    local schedule = (payload.schedule or 'weekly'):lower()

    local job      = Player.PlayerData.job or {}
    local jobName  = job.name or 'unemployed'

    local citizenid = Player.PlayerData.citizenid
    local headInfo  = getHeadRegionAndOffice(citizenid)
    local regionInfo = headInfo.regionInfo

    local regionAliasForSettings = tostring(regionInfo.alias or 'unknown'):lower()
    local finalMode, finalSched  = saveOfficeSettings(regionAliasForSettings, jobName, mode, schedule)

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Office Panel',
        description = ('Payment mode set to %s (%s).'):format(finalMode, finalSched),
        type        = 'success'
    })

    return true
end)

--=====================================================
--  Payroll builder (for preview & execute)
--=====================================================

local function buildOfficePayroll(regionName, jobName, headCitizenId)
    jobName = tostring(jobName or 'unemployed'):lower()

    -- We primarily group by job_name; regionName is informational here.
    local rows = MySQL.query.await([[
        SELECT
            id,
            citizenid,
            job_name,
            grade,
            minutes_regular,
            minutes_overtime,
            paid
        FROM governor_duty_sessions
        WHERE LOWER(job_name) = ?
          AND paid = 0
        ORDER BY citizenid
    ]], { jobName })

    if (not rows or not rows[1]) and headCitizenId then
        -- Last fallback: head's own unpaid sessions
        rows = MySQL.query.await([[
            SELECT
                id,
                citizenid,
                job_name,
                grade,
                minutes_regular,
                minutes_overtime,
                paid
            FROM governor_duty_sessions
            WHERE citizenid = ?
              AND paid = 0
            ORDER BY ended_at DESC
        ]], { headCitizenId })
    end

    if not rows or not rows[1] then
        return {
            totalPay      = 0,
            employees     = {},
            employeeCount = 0,
        }
    end

    local otMult    = (Config.Payroll and Config.Payroll.OvertimeMultiplier) or 1.5
    local byCitizen = {}

    for _, r in ipairs(rows) do
        local cid = r.citizenid
        if cid and cid ~= '' then
            local gradeLevel = tonumber(r.grade or 0) or 0
            local baseRate   = getBaseRate(jobName, gradeLevel) or 0

            if baseRate > 0 then
                local regH = (r.minutes_regular  or 0) / 60
                local otH  = (r.minutes_overtime or 0) / 60
                local est  = (regH * baseRate) + (otH * baseRate * otMult)
                est = math.max(0, est)

                if est > 0 then
                    local entry = byCitizen[cid]
                    if not entry then
                        local fullName = cid
                        if RSGCore.Functions.GetPlayerByCitizenId then
                            local P = RSGCore.Functions.GetPlayerByCitizenId(cid)
                            if P and P.PlayerData and P.PlayerData.charinfo then
                                local ci = P.PlayerData.charinfo
                                fullName = (ci.firstname or 'Unknown') .. ' ' .. (ci.lastname or '')
                            end
                        end

                        entry = {
                            citizenid  = cid,
                            name       = fullName,
                            totalPay   = 0,
                            sessions   = 0,
                            sessionIds = {},
                        }
                        byCitizen[cid] = entry
                    end

                    entry.totalPay              = entry.totalPay + est
                    entry.sessions              = entry.sessions + 1
                    entry.sessionIds[#entry.sessionIds+1] = r.id
                end
            end
        end
    end

    local employeesList = {}
    local totalPay      = 0
    local empCount      = 0

    for _, e in pairs(byCitizen) do
        e.totalPay = math.floor(e.totalPay + 0.5)
        if e.totalPay > 0 then
            totalPay = totalPay + e.totalPay
            empCount = empCount + 1
            employeesList[#employeesList+1] = e
        end
    end

    totalPay = math.floor(totalPay + 0.5)

    return {
        totalPay      = totalPay,
        employees     = employeesList,
        employeeCount = empCount,
    }
end

--=====================================================
--  Manual Payroll PREVIEW
--=====================================================

lib.callback.register('rsg-governor:runManualPayroll', function(src)
    local Head = RSGCore.Functions.GetPlayer(src)
    if not Head then
        return { ok = false, message = 'Head of office not found.' }
    end

    local headJob  = Head.PlayerData.job or {}
    local jobName  = headJob.name or 'unemployed'
    local jobLabel = headJob.label or jobName

    -- isboss check
    local isBoss = false
    if headJob.isboss then
        isBoss = true
    elseif type(headJob.grade) == 'table' and headJob.grade.isboss then
        isBoss = true
    end

    if not isBoss then
        return { ok = false, message = 'You must be the head of this office to run payroll.' }
    end

    local headCID   = Head.PlayerData.citizenid
    local headInfo  = getHeadRegionAndOffice(headCID)
    local regionName  = headInfo.region
    local regionInfo  = headInfo.regionInfo

    local summary      = buildOfficePayroll(regionName, jobName, headCID)
    local regionHash   = regionInfo.hash
    local rawTreasury  = getTreasuryBalanceByHash(regionHash)

    local alloc        = getOfficeAllocation(regionName, jobName)
    local officeLabel  = (alloc and alloc.office_label) or jobLabel
    local fundingShare = (alloc and alloc.funding_share) or 1.0
    local salaryShare  = (alloc and alloc.salary_share)  or 0.0
    local supplyShare  = (alloc and alloc.supply_share)  or 0.0

    if fundingShare < 0.0 then fundingShare = 0.0 end
    if fundingShare > 1.0 then fundingShare = 1.0 end

    local officeBudget = math.floor(rawTreasury * fundingShare + 0.5)
    local supplyCost   = 0

    local onlineCount = 0
    if RSGCore.Functions.GetPlayerByCitizenId then
        for _, e in ipairs(summary.employees or {}) do
            local P = RSGCore.Functions.GetPlayerByCitizenId(e.citizenid)
            if P then
                onlineCount = onlineCount + 1
            end
        end
    end

    local canAfford = (summary.totalPay <= officeBudget)

    return {
        ok                 = true,
        region             = regionName,
        region_label       = regionInfo.label,
        job_name           = jobName,
        job_label          = jobLabel,
        office_label       = officeLabel,

        total_pay          = summary.totalPay,
        employees          = summary.employees,
        employee_count     = onlineCount,
        employee_total     = summary.employeeCount,

        treasury_balance   = officeBudget,
        treasury_raw       = rawTreasury,
        office_share       = fundingShare,

        salary_share       = salaryShare,
        supply_share       = supplyShare,
        supply_cost        = supplyCost,

        message            = (summary.totalPay > 0)
            and string.format('Payroll cost: $%d for %d employees.', summary.totalPay, summary.employeeCount)
            or 'No unpaid sessions for this office.',
        can_afford         = canAfford,
    }
end)

--=====================================================
--  Manual Payroll EXECUTE
--=====================================================

lib.callback.register('rsg-governor:executeManualPayroll', function(src)
    local Head = RSGCore.Functions.GetPlayer(src)
    if not Head then
        return { ok = false, message = 'Head of office not found.' }
    end

    local headJob  = Head.PlayerData.job or {}
    local jobName  = headJob.name or 'unemployed'
    local jobLabel = headJob.label or jobName

    local isBoss = false
    if headJob.isboss then
        isBoss = true
    elseif type(headJob.grade) == 'table' and headJob.grade.isboss then
        isBoss = true
    end

    if not isBoss then
        return { ok = false, message = 'You must be the head of this office to run payroll.' }
    end

    local headCID   = Head.PlayerData.citizenid
    local headInfo  = getHeadRegionAndOffice(headCID)
    local regionName  = headInfo.region
    local regionInfo  = headInfo.regionInfo

    local summary      = buildOfficePayroll(regionName, jobName, headCID)
    local totalPay     = summary.totalPay
    local regionHash   = regionInfo.hash
    local rawTreasury  = getTreasuryBalanceByHash(regionHash)
    local fundingShare = getOfficeFundingShare(regionName, jobName)
    local officeBudget = math.floor(rawTreasury * fundingShare + 0.5)

    if totalPay <= 0 or summary.employeeCount <= 0 then
        return { ok = false, message = 'No unpaid sessions for this office.' }
    end

    if officeBudget < totalPay then
        return {
            ok           = false,
            message      = string.format(
                'Insufficient office funds. Need $%d, office budget is $%d (share %.0f%% of treasury $%d).',
                totalPay, officeBudget, fundingShare * 100, rawTreasury
            ),
            needed       = totalPay,
            officeBudget = officeBudget,
            treasury     = rawTreasury,
        }
    end

    local okDeduct, newTreasury = deductTreasuryByHash(regionHash, totalPay)
    if not okDeduct then
        return {
            ok       = false,
            message  = 'Treasury update failed. Payroll aborted.',
            treasury = rawTreasury,
        }
    end

    local countPaid = 0

    for _, e in ipairs(summary.employees) do
        local cid = e.citizenid
        if cid then
            local P = nil
            if RSGCore.Functions.GetPlayerByCitizenId then
                P = RSGCore.Functions.GetPlayerByCitizenId(cid)
            end

            local amount = math.floor(e.totalPay + 0.5)
            if P and amount > 0 then
                local payMode, branchId = getPayPreference(cid)
                payMode = tostring(payMode or 'cash'):lower()

                local moneyType = 'cash'

                if payMode == 'bank' then
                    local branchCfg = branchId and BankBranches[branchId] or nil
                    if not branchCfg then
                        -- fallback to a generic "bank" branch if misconfigured
                        branchCfg = BankBranches['bank'] or next(BankBranches)
                    end
                    if type(branchCfg) == 'table' then
                        moneyType = branchCfg.moneyType or 'bank'
                    else
                        moneyType = 'bank'
                    end
                end

                print(('[rsg-governor] Payroll: paying %s %d via %s (mode=%s, branch=%s)')
                    :format(cid, amount, moneyType, payMode, tostring(branchId)))

                P.Functions.AddMoney(moneyType, amount, 'governor-office-payroll')

                for _, sid in ipairs(e.sessionIds or {}) do
                    MySQL.update.await('UPDATE governor_duty_sessions SET paid = 1 WHERE id = ?', { sid })
                end

                countPaid = countPaid + 1
            end
        end
    end

    return {
        ok          = true,
        message     = string.format(
            'Payroll complete for %s (%s).\nPaid %d employees.\nTotal payout: $%d.\nRegion treasury remaining: $%d.',
            jobLabel,
            regionInfo.label,
            countPaid,
            totalPay,
            newTreasury
        ),
        total_pay   = totalPay,
        employees   = summary.employees,
        paid_count  = countPaid,
        treasury    = newTreasury,
    }
end)

--=====================================================
--  Supply Orders (ammo, bandage, handcuff)
--=====================================================

RegisterNetEvent('rsg-governor:server:orderSupply', function(itemName, quantity)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    itemName = tostring(itemName or ''):lower()
    quantity = tonumber(quantity or 0) or 0

    if quantity <= 0 then return end

    local allowed = {
        ammo_box_revolver = true,
        ammo_box_reapter  = true,
        bandage           = true,
        handcuff          = true,
    }

    if not allowed[itemName] then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Supply Orders',
            description = 'You cannot order this item.',
            type        = 'error'
        })
        return
    end

    local inv = exports['rsg-inventory']
    if inv and inv.AddItem then
        inv:AddItem(src, itemName, quantity)
    else
        print(('[rsg-governor] Would give %dx %s to %s'):format(
            quantity, itemName, Player.PlayerData.citizenid
        ))
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Supply Orders',
        description = ('Ordered %dx %s'):format(quantity, itemName),
        type        = 'success'
    })
end)
