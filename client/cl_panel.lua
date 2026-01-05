--======================================================================
-- rsg-governor / client/cl_panel.lua
-- Governor Panel (ox_lib context menu)
--======================================================================

lib.locale()

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
            title       = locale('view_rules'),
            description = rulesText ~= '' and rulesText or locale('no_rules_set'),
            readOnly    = true
        },
        {
            title       = locale('set_edit_rules'),
            description = locale('update_rules_text'),
            arrow       = true,
            event       = 'rsg-governor:client:setRules',
            args        = { regionName = regionName or 'here', current = rulesText }
        },
        {
            title       = locale('make_announcement'),
            description = locale('broadcast_message'),
            arrow       = true,
            event       = 'rsg-governor:client:announce',
            args        = { regionName = regionName or 'here' }
        },
    }

    lib.registerContext({
        id = 'rsg_governor_rules_menu',
        title = locale('region_rules', regionName or 'here'),
        options = options
    })
    lib.showContext('rsg_governor_rules_menu')
end

RegisterNetEvent('rsg-governor:client:setRules', function(data)
    local regionName = data.regionName or 'here'
    local current    = data.current or ''

    local txt = lib.inputDialog(locale('set_region_rules'), {
        {
            type        = 'textarea',
            label       = locale('rules_text'),
            description = locale('write_rules_desc'),
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

    local msg = askInput(locale('region_announcement'), locale('message'), locale('enter_announcement'))
    if not msg then return end

    ExecuteCommand(('govannounce here %s'):format(msg))
end)

function openOfficesMenu(regionName)
    local offices = lib.callback.await('rsg-governor:getRegionOffices', false, regionName or 'here') or {}
    if #offices == 0 then
        lib.notify({
            title       = locale('governor'),
            description = locale('no_offices_defined'),
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
            description = locale('head_salary_desc', headName, salary, salaryShare, supplyShare),
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
        title   = locale('offices_salaries'),
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
            title       = locale('edit_head_salary_shares'),
            description = locale('edit_all_values_desc'),
            arrow       = true,
            event       = 'rsg-governor:client:officeEditForm',
            args        = data
        },
        {
            title       = locale('set_head_quick'),
            description = locale('current_head', data.head_name or locale('unassigned')),
            arrow       = true,
            event       = 'rsg-governor:client:setHead',
            args        = data
        },
        {
            title       = locale('set_salary_quick'),
            description = locale('current_salary', data.salary or 0),
            arrow       = true,
            event       = 'rsg-governor:client:setSalary',
            args        = data
        },
        {
            title       = locale('set_salary_share_quick'),
            description = locale('current_salary_share', data.salary_share or 0),
            arrow       = true,
            event       = 'rsg-governor:client:setSalaryShare',
            args        = data
        },
        {
            title       = locale('set_supply_share_quick'),
            description = locale('current_supply_share', data.supply_share or 0),
            arrow       = true,
            event       = 'rsg-governor:client:setSupplyShare',
            args        = data
        },
    }


    lib.registerContext({
        id = 'rsg_governor_office_detail',
        title = locale('office_detail', office_label),
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

    local dlg = lib.inputDialog(locale('edit_office', office_label), {
        {
            type        = 'input',
            label       = locale('head_of_office_id'),
            description = locale('current_head_desc',
                currentHead ~= '' and currentHead or locale('unassigned')
            ),
            default     = '',
            required    = false,
        },
        {
            -- use input (string) instead of number to avoid ox_lib default/nil quirks
            type        = 'input',
            label       = locale('base_salary_dollars'),
            description = locale('current_salary_desc', currentSalary),
            default     = (currentSalary > 0) and tostring(math.floor(currentSalary)) or '',
            required    = false,
        },
        {
            type        = 'input',
            label       = locale('salary_share_label'),
            description = locale('salary_share_desc', currentSalaryShare),
            default     = string.format('%.2f', currentSalaryShare),
            required    = false,
        },
        {
            type        = 'input',
            label       = locale('supply_share_label'),
            description = locale('supply_share_desc', currentSupplyShare),
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
                title       = locale('governor'),
                description = locale('invalid_server_id'),
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
                title       = locale('governor'),
                description = locale('invalid_salary_value'),
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
                title       = locale('governor'),
                description = locale('invalid_salary_share'),
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
                title       = locale('governor'),
                description = locale('invalid_supply_share'),
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
        title       = locale('governor'),
        description = locale('office_update_requested', office_label),
        type        = 'success',
        duration    = 4000,
    })
end)

RegisterNetEvent('rsg-governor:client:setHead', function(data)
    local idStr = askInput(locale('set_head_of_office'), locale('player_server_id'), locale('enter_server_id'))
    if not idStr then return end
    local id = tonumber(idStr or 0) or 0
    if id <= 0 then return end

    local cmd = ('govoffice sethead here %s %d'):format(data.office_key, id)
    ExecuteCommand(cmd)
end)

RegisterNetEvent('rsg-governor:client:setSalary', function(data)
    local current = tonumber(data.salary or 0) or 0
    local input = askInput(locale('set_salary'), locale('salary_dollars'), locale('current_salary', current), tostring(math.floor(current)))
    if not input then return end
    local salary = tonumber(input or 0) or 0
    if salary < 0 then salary = 0 end

    local cmd = ('govoffice setsalary here %s %d'):format(data.office_key, salary)
    ExecuteCommand(cmd)
end)

RegisterNetEvent('rsg-governor:client:setSalaryShare', function(data)
    local current = tonumber(data.salary_share or 0) or 0
    local input = askInput(locale('set_salary_share'), locale('share_label'), locale('current_salary_share', current), tostring(current))
    if not input then return end
    local share = tonumber(input or 0) or 0
    if share < 0 then share = 0 end
    if share > 1 then share = 1 end

    local cmd = ('govoffice setfund here %s %.2f'):format(data.office_key, share)
    ExecuteCommand(cmd)
end)

RegisterNetEvent('rsg-governor:client:setSupplyShare', function(data)
    local current = tonumber(data.supply_share or 0) or 0
    local input = askInput(locale('set_supply_share'), locale('share_label'), locale('current_supply_share', current), tostring(current))
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
        lib.notify({ title = locale('governor'), description = locale('no_unpaid_duty_sessions'), type = 'inform' })
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
            description = locale('employee_duty_desc', regHours, otHours, totalHours, pay),
            disabled = true
        }
    end

    lib.registerContext({
        id      = 'rsg_governor_payroll_employees',
        title   = locale('payroll_employees', regionName or 'here'),
        menu    = 'rsg_governor_payroll_menu',
        options = opts
    })
    lib.showContext('rsg_governor_payroll_employees')
end

local function openPayrollMenu(regionName)
    local summary = lib.callback.await('rsg-governor:getPayrollSummary', false, regionName or 'here')
    if not summary then
        lib.notify({
            title       = locale('governor'),
            description = locale('unable_fetch_payroll'),
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
        title       = locale('summary'),
        description = locale('treasury_summary_desc',
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
            description = locale('office_breakdown_desc',
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
        title       = locale('view_all_employees'),
        description = locale('view_all_employees_desc'),
        arrow       = true,
        onSelect    = function()
            openPayrollEmployeesMenu(regionName, nil)
        end
    }

    options[#options+1] = {
        title       = locale('run_payroll_now'),
        description = locale('run_payroll_now_desc'),
        arrow       = true,
        onSelect    = function()
            local res = lib.callback.await('rsg-governor:runPayroll', false, regionName or 'here')
            if not res or not res.ok then
                lib.notify({
                    title       = locale('governor'),
                    description = res and res.error or locale('payroll_failed'),
                    type        = 'error'
                })
                return
            end

            lib.notify({
                title       = locale('governor'),
                description = locale('payroll_complete', res.totalPaid or 0, res.paidEmployees or 0, res.newTreasury or 0),
                type        = 'success'
            })

            -- Refresh summary
            openPayrollMenu(regionName)
        end
    }

    lib.registerContext({
        id      = 'rsg_governor_payroll_menu',
        title   = locale('payroll_attendance_region', regionName or 'here'),
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
        lib.notify({ title = locale('governor'), description = locale('not_governor'), type = 'error' })
        isOpening = false
        return
    end

    local regionNorm = region

        local options = {
        {
            title       = locale('economy_taxes'),
            description = locale('economy_taxes_desc'),
            onSelect    = function()
                openEconomyMenu()
            end
        },
        {
            title       = locale('offices_salaries'),
            description = locale('offices_salaries_desc'),
            onSelect    = function()
                openOfficesMenu(regionNorm)
            end
        },
        {
            title       = locale('payroll_attendance'),
            description = locale('payroll_attendance_desc'),
            onSelect    = function()
                openPayrollMenu(regionNorm)
            end
        },
        {
            title       = locale('rules_announcements'),
            description = locale('rules_announcements_desc'),
            onSelect    = function()
                openRulesMenu(regionNorm)
            end
        },
        {
            title       = locale('business_permits'),
            description = locale('business_permits_desc'),
            onSelect    = function()
                ExecuteCommand('govpermits here')
            end
        },
    }

    lib.registerContext({
        id = 'rsg_governor_main_panel',
        title = locale('governor_panel_region', regionNorm),
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
