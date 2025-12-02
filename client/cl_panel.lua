--======================================================================
-- rsg-governor / client/cl_panel.lua
-- Governor Panel (ox_lib context menu)
--======================================================================

local isOpening = false

local function openEconomyMenu()
    -- just use the existing economy command
    ExecuteCommand('economy')
end

local function askInput(title, label, placeholder, default)
    local input = lib.inputDialog(title, {
        {
            type        = 'input',
            label       = label,
            placeholder = placeholder or '',
            default     = default or '',
        }
    })
    if not input or not input[1] or input[1] == '' then
        return nil
    end
    return input[1]
end

local function openRulesMenu(regionName)
    local rulesText = lib.callback.await('rsg-governor:getRegionRules', false, regionName or 'here')

    local options = {
        {
            title       = 'View Rules',
            description = rulesText ~= '' and rulesText or 'No rules set for this region.',
            readOnly    = true
        },
        {
            title       = 'Set / Edit Rules',
            description = 'Update region rules text',
            arrow       = true,
            event       = 'rsg-governor:client:setRules',
            args        = { regionName = regionName or 'here', current = rulesText }
        },
        {
            title       = 'Make Announcement',
            description = 'Broadcast a message to this region',
            arrow       = true,
            event       = 'rsg-governor:client:announce',
            args        = { regionName = regionName or 'here' }
        },
    }

    lib.registerContext({
        id = 'rsg_governor_rules_menu',
        title = ('Region Rules – %s'):format(regionName or 'here'),
        options = options
    })
    lib.showContext('rsg_governor_rules_menu')
end

RegisterNetEvent('rsg-governor:client:setRules', function(data)
    local regionName = data.regionName or 'here'
    local current    = data.current or ''

    local txt = lib.inputDialog('Set Region Rules', {
        {
            type        = 'textarea',
            label       = 'Rules Text',
            description = 'Write the rules for this region.',
            default     = current,
            min         = 0,
            max         = Config.Rules and Config.Rules.MaxLength or 4000,
        }
    })
    if not txt or not txt[1] then return end

    local rulesText = txt[1]
    if rulesText == current then return end

    -- we’ll reuse the /govrules command
    ExecuteCommand(('govrules set here %s'):format(rulesText))
end)

RegisterNetEvent('rsg-governor:client:announce', function(data)
    local regionName = data.regionName or 'here'

    local msg = askInput('Region Announcement', 'Message', 'Enter announcement...')
    if not msg then return end

    ExecuteCommand(('govannounce here %s'):format(msg))
end)

function openOfficesMenu(regionName)
    local offices = lib.callback.await('rsg-governor:getRegionOffices', false, regionName or 'here') or {}
    if #offices == 0 then
        lib.notify({
            title       = 'Governor',
            description = 'No offices defined for this region yet.',
            type        = 'inform'
        })
        return
    end

    local options = {}

    for _, o in ipairs(offices) do
        local label        = o.office_label or o.office_key
        local salary       = (o.base_salary_cents or 0) / 100.0
        local salaryShare  = tonumber(o.salary_share or o.funding_share or 0) or 0
        local supplyShare  = tonumber(o.supply_share or 0) or 0
        local headName     = o.head_char_name or 'Unassigned'

        options[#options+1] = {
            title = label,
            description = ('Head: %s\nSalary: $%.2f\nSalary share: %.2f\nSupply share: %.2f')
                :format(headName, salary, salaryShare, supplyShare),
            arrow = true,
            event = 'rsg-governor:client:officeDetail',
            args  = {
                regionName    = regionName or 'here',
                office_key    = o.office_key,
                office_label  = label,
                salary        = salary,
                salary_share  = salaryShare,
                supply_share  = supplyShare,
                head_name     = headName,
            }
        }
    end

    lib.registerContext({
        id      = 'rsg_governor_offices',
        title   = 'Offices & Salaries',
        options = options
    })

    lib.showContext('rsg_governor_offices')
end

RegisterNetEvent('rsg-governor:client:officeDetail', function(data)
    local regionName   = data.regionName or 'here'
    local office_key   = data.office_key
    local office_label = data.office_label or data.office_key

    local options = {
        {
            title       = 'Edit Head / Salary / Shares',
            description = 'Open a form to edit all values at once.',
            arrow       = true,
            event       = 'rsg-governor:client:officeEditForm',
            args        = data
        },
        {
            title       = 'Set Head (quick)',
            description = ('Current: %s'):format(data.head_name or 'Unassigned'),
            arrow       = true,
            event       = 'rsg-governor:client:setHead',
            args        = data
        },
        {
            title       = 'Set Salary (quick)',
            description = ('Current: $%.2f'):format(data.salary or 0),
            arrow       = true,
            event       = 'rsg-governor:client:setSalary',
            args        = data
        },
        {
            title       = 'Set Salary Share (quick)',
            description = ('Current: %.2f (0.0 - 1.0)'):format(data.salary_share or 0),
            arrow       = true,
            event       = 'rsg-governor:client:setSalaryShare',
            args        = data
        },
        {
            title       = 'Set Supply Share (quick)',
            description = ('Current: %.2f (0.0 - 1.0)'):format(data.supply_share or 0),
            arrow       = true,
            event       = 'rsg-governor:client:setSupplyShare',
            args        = data
        },
    }


    lib.registerContext({
        id = 'rsg_governor_office_detail',
        title = ('Office – %s'):format(office_label),
        options = options
    })
    lib.showContext('rsg_governor_office_detail')
end)

RegisterNetEvent('rsg-governor:client:officeEditForm', function(data)
    local regionName         = data.regionName or 'here'
    local office_key         = data.office_key
    local office_label       = data.office_label or data.office_key
    local currentHead        = data.head_name or ''

    local currentSalary      = tonumber(data.salary or 0) or 0
    -- Try new fields first, fall back to old `funding` if needed
    local currentSalaryShare = tonumber(data.salary_share or data.funding or 0) or 0
    local currentSupplyShare = tonumber(data.supply_share or 0) or 0

    local dlg = lib.inputDialog(('Edit Office – %s'):format(office_label), {
        {
            type        = 'input',
            label       = 'Head of Office (Server ID)',
            description = ('Current head: %s (leave blank to keep)'):format(
                currentHead ~= '' and currentHead or 'Unassigned'
            ),
            default     = '',
            required    = false,
        },
        {
            -- use input (string) instead of number to avoid ox_lib default/nil quirks
            type        = 'input',
            label       = 'Base salary (dollars)',
            description = ('Current: $%.2f (leave blank to keep)'):format(currentSalary),
            default     = (currentSalary > 0) and tostring(math.floor(currentSalary)) or '',
            required    = false,
        },
        {
            type        = 'input',
            label       = 'Salary share (0.0 – 1.0)',
            description = ('Current: %.2f (leave blank to keep)'):format(currentSalaryShare),
            default     = string.format('%.2f', currentSalaryShare),
            required    = false,
        },
        {
            type        = 'input',
            label       = 'Supply share (0.0 – 1.0)',
            description = ('Current: %.2f (leave blank to keep)'):format(currentSupplyShare),
            default     = string.format('%.2f', currentSupplyShare),
            required    = false,
        },
    })

    if not dlg then return end

    local headIdStr      = dlg[1]
    local salaryStr      = dlg[2]
    local salaryShareStr = dlg[3]
    local supplyShareStr = dlg[4]

    ----------------------------------------------------------------------
    -- HEAD: only change if field is non-empty
    ----------------------------------------------------------------------
    if headIdStr and headIdStr ~= '' then
        local headId = tonumber(headIdStr)
        if headId and headId > 0 then
            local cmd = ('govoffice sethead here %s %d'):format(office_key, headId)
            ExecuteCommand(cmd)
        else
            lib.notify({
                title       = 'Governor',
                description = 'Invalid server ID for head of office.',
                type        = 'error',
                duration    = 4000,
            })
        end
    end

    ----------------------------------------------------------------------
    -- SALARY: only change if field is non-empty
    ----------------------------------------------------------------------
    if salaryStr and salaryStr ~= '' then
        local num = tonumber(salaryStr)
        if not num then
            lib.notify({
                title       = 'Governor',
                description = 'Invalid salary value. Must be a number.',
                type        = 'error',
                duration    = 4000,
            })
        else
            local s = math.floor(math.max(0, num))
            if s ~= math.floor(currentSalary) then
                local cmd = ('govoffice setsalary here %s %d'):format(office_key, s)
                ExecuteCommand(cmd)
            end
        end
    end

    ----------------------------------------------------------------------
    -- SALARY SHARE: only change if field is non-empty
    ----------------------------------------------------------------------
    if salaryShareStr and salaryShareStr ~= '' then
        local num = tonumber(salaryShareStr)
        if not num then
            lib.notify({
                title       = 'Governor',
                description = 'Invalid salary share. Must be a number between 0.0 and 1.0.',
                type        = 'error',
                duration    = 4000,
            })
        else
            local share = num
            if share < 0 then share = 0 end
            if share > 1 then share = 1 end
            if math.abs(share - currentSalaryShare) > 0.0001 then
                -- /govoffice setfund = SALARY share
                local cmd = ('govoffice setfund here %s %.2f'):format(office_key, share)
                ExecuteCommand(cmd)
            end
        end
    end

    ----------------------------------------------------------------------
    -- SUPPLY SHARE: only change if field is non-empty
    ----------------------------------------------------------------------
    if supplyShareStr and supplyShareStr ~= '' then
        local num = tonumber(supplyShareStr)
        if not num then
            lib.notify({
                title       = 'Governor',
                description = 'Invalid supply share. Must be a number between 0.0 and 1.0.',
                type        = 'error',
                duration    = 4000,
            })
        else
            local share = num
            if share < 0 then share = 0 end
            if share > 1 then share = 1 end
            if math.abs(share - currentSupplyShare) > 0.0001 then
                -- /govoffice setsupply = SUPPLY share
                local cmd = ('govoffice setsupply here %s %.2f'):format(office_key, share)
                ExecuteCommand(cmd)
            end
        end
    end

    lib.notify({
        title       = 'Governor',
        description = ('Office "%s" update requested.'):format(office_label),
        type        = 'success',
        duration    = 4000,
    })
end)

RegisterNetEvent('rsg-governor:client:setHead', function(data)
    local idStr = askInput('Set Head of Office', 'Player Server ID', 'Enter server ID of the player...')
    if not idStr then return end
    local id = tonumber(idStr or 0) or 0
    if id <= 0 then return end

    local cmd = ('govoffice sethead here %s %d'):format(data.office_key, id)
    ExecuteCommand(cmd)
end)

RegisterNetEvent('rsg-governor:client:setSalary', function(data)
    local current = tonumber(data.salary or 0) or 0
    local input = askInput('Set Salary', 'Salary (dollars)', ('Current: %.2f'):format(current), tostring(math.floor(current)))
    if not input then return end
    local salary = tonumber(input or 0) or 0
    if salary < 0 then salary = 0 end

    local cmd = ('govoffice setsalary here %s %d'):format(data.office_key, salary)
    ExecuteCommand(cmd)
end)

RegisterNetEvent('rsg-governor:client:setSalaryShare', function(data)
    local current = tonumber(data.salary_share or 0) or 0
    local input = askInput('Set Salary Share', 'Share (0.0 - 1.0)', ('Current: %.2f'):format(current), tostring(current))
    if not input then return end
    local share = tonumber(input or 0) or 0
    if share < 0 then share = 0 end
    if share > 1 then share = 1 end

    local cmd = ('govoffice setfund here %s %.2f'):format(data.office_key, share)
    ExecuteCommand(cmd)
end)

RegisterNetEvent('rsg-governor:client:setSupplyShare', function(data)
    local current = tonumber(data.supply_share or 0) or 0
    local input = askInput('Set Supply Share', 'Share (0.0 - 1.0)', ('Current: %.2f'):format(current), tostring(current))
    if not input then return end
    local share = tonumber(input or 0) or 0
    if share < 0 then share = 0 end
    if share > 1 then share = 1 end

    local cmd = ('govoffice setsupply here %s %.2f'):format(data.office_key, share)
    ExecuteCommand(cmd)
end)

--======================
-- Payroll & Attendance
--======================

local function openPayrollEmployeesMenu(regionName, officeKey)
    local employees = lib.callback.await('rsg-governor:getPayrollEmployees', false, {
        region = regionName or 'here',
        office = officeKey
    }) or {}

    if #employees == 0 then
        lib.notify({ title = 'Governor', description = 'No unpaid duty sessions found for this filter.', type = 'inform' })
        return
    end

    local opts = {}

    for _, e in ipairs(employees) do
        local totalHours = ((e.regular_min or 0) + (e.ot_min or 0)) / 60.0
        local regHours   = (e.regular_min or 0) / 60.0
        local otHours    = (e.ot_min or 0) / 60.0
        local pay        = e.pay or 0
        local jobLabel   = e.job_label or e.job_name or 'Job'
        local grade      = e.grade or 0

        opts[#opts+1] = {
            title = string.format('%s (%s %d)', e.name or e.citizenid, jobLabel, grade),
            description = string.format(
                'Regular: %.1f h, OT: %.1f h\nTotal hours: %.1f\nEstimated pay: $%.2f',
                regHours, otHours, totalHours, pay
            ),
            disabled = true
        }
    end

    lib.registerContext({
        id      = 'rsg_governor_payroll_employees',
        title   = ('Payroll – Employees (%s)'):format(regionName or 'here'),
        menu    = 'rsg_governor_payroll_menu',
        options = opts
    })
    lib.showContext('rsg_governor_payroll_employees')
end

local function openPayrollMenu(regionName)
    local summary = lib.callback.await('rsg-governor:getPayrollSummary', false, regionName or 'here')
    if not summary then
        lib.notify({
            title       = 'Governor',
            description = 'Unable to fetch payroll summary or you are not allowed.',
            type        = 'error'
        })
        return
    end

        local treasury    = tonumber(summary.treasury or 0) or 0
    local totalPay    = tonumber(summary.total_estimated_pay or 0) or 0
    local totalBudget = tonumber(summary.total_budget or 0) or 0
    local offices     = summary.offices or {}

    local remaining = treasury - totalBudget
    if remaining < 0 then remaining = 0 end

    local options = {}

    -- Summary: treasury, total budgets, remaining, and estimated payroll
    options[#options+1] = {
        title       = 'Summary',
        description = string.format(
            'Treasury: $%d\nTotal office budgets: $%d\nRemaining Treasury (after budgets): $%d\nEstimated total payroll: $%d',
            math.floor(treasury),
            math.floor(totalBudget),
            math.floor(remaining),
            math.floor(totalPay)
        ),
        disabled    = true
    }

    -- Per-office breakdown
    for officeKey, o in pairs(offices) do
        local label       = o.office_label or officeKey
        local regMin      = o.regular_min or 0
        local otMin       = o.ot_min or 0
        local estCost     = o.estimated_cost or 0
        local salaryBudg  = o.salary_budget or 0
        local supplyBudg  = o.supply_budget or 0
        local salaryShare = o.salary_share or 0
        local supplyShare = o.supply_share or 0

        local regHours = regMin / 60.0
        local otHours  = otMin / 60.0

        options[#options+1] = {
            title = string.format('%s – $%.2f', label, estCost),
            description = string.format(
                'Regular: %.1f h, OT: %.1f h\n' ..
                'Salary Share: %.2f (Budget: $%.2f)\n' ..
                'Supply Share: %.2f (Budget: $%.2f)',
                regHours, otHours,
                salaryShare, salaryBudg,
                supplyShare, supplyBudg
            ),
            arrow = true,
            onSelect = function()
                openPayrollEmployeesMenu(regionName, officeKey)
            end
        }
    end

    options[#options+1] = {
        title       = 'View All Employees',
        description = 'Show all unpaid sessions for this region.',
        arrow       = true,
        onSelect    = function()
            openPayrollEmployeesMenu(regionName, nil)
        end
    }

    options[#options+1] = {
        title       = 'Run Payroll Now',
        description = 'Pay all online employees with unpaid duty sessions (bank).',
        arrow       = true,
        onSelect    = function()
            local res = lib.callback.await('rsg-governor:runPayroll', false, regionName or 'here')
            if not res or not res.ok then
                lib.notify({
                    title       = 'Governor',
                    description = res and res.error or 'Payroll failed.',
                    type        = 'error'
                })
                return
            end

            lib.notify({
                title       = 'Governor',
                description = string.format(
                    'Payroll complete: paid $%d to %d employees.\nNew treasury: $%d.',
                    res.totalPaid or 0, res.paidEmployees or 0, res.newTreasury or 0
                ),
                type        = 'success'
            })

            -- Refresh summary
            openPayrollMenu(regionName)
        end
    }

    lib.registerContext({
        id      = 'rsg_governor_payroll_menu',
        title   = ('Payroll & Attendance – %s'):format(regionName or 'here'),
        menu    = 'rsg_governor_main_panel',
        options = options
    })
    lib.showContext('rsg_governor_payroll_menu')
end

--======================
-- Main Governor Panel
--======================

local function openGovernorPanel()
    if isOpening then return end
    isOpening = true

    -- Ask server which region (if any) this player is governor of
    local region = lib.callback.await('rsg-governor:getMyGovernorRegion', false)
    if not region or region == '' then
        lib.notify({ title = 'Governor', description = 'You are not a governor of any region.', type = 'error' })
        isOpening = false
        return
    end

    local regionNorm = region

        local options = {
        {
            title       = 'Economy / Taxes',
            description = 'Open economy panel (taxes, VAT, revenue) for your region.',
            onSelect    = function()
                openEconomyMenu()
            end
        },
        {
            title       = 'Offices & Salaries',
            description = 'Manage heads of office, salaries, and funding shares.',
            onSelect    = function()
                openOfficesMenu(regionNorm)
            end
        },
        {
            title       = 'Payroll & Attendance',
            description = 'Review duty, estimate costs, and run payroll.',
            onSelect    = function()
                openPayrollMenu(regionNorm)
            end
        },
        {
            title       = 'Rules & Announcements',
            description = 'Set regional rules and send announcements.',
            onSelect    = function()
                openRulesMenu(regionNorm)
            end
        },
        {
            title       = 'Business Permits',
            description = 'Review and approve business permits.',
            onSelect    = function()
                ExecuteCommand('govpermits here')
            end
        },
    }

    lib.registerContext({
        id = 'rsg_governor_main_panel',
        title = ('Governor Panel – %s'):format(regionNorm),
        options = options
    })
    lib.showContext('rsg_governor_main_panel')

    isOpening = false
end

-- Callback for region detection (server side wrapper over Gov.GetGovernorRegionForPlayer)
-- Add this on server side (sv_auth.lua or new small file):
-- lib.callback.register('rsg-governor:getMyGovernorRegion', function(src) return exports['rsg-governor']:GetGovernorRegionForPlayer(src) end)

RegisterCommand(Config.Governor and Config.Governor.PanelCommand or 'governor', function()
    openGovernorPanel()
end, false)
