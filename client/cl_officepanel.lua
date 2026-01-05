local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()
-- ==========================================================
-- Office panel open helper (used by NUI + other events)
-- ==========================================================

local function openOfficePanel(ctx)
    ctx = ctx or {}

    -- Ensure we focus NUI
    SetNuiFocus(true, true)

    -- Tell the HTML/JS to open the office panel
    SendNUIMessage({
        action  = "govOfficePanel:open",  -- keep this in sync with your JS
        payload = ctx
    })
end

-- Optional: expose as an event for other scripts
RegisterNetEvent('rsg-governor:client:openOfficePanel', function(ctx)
    openOfficePanel(ctx)
end)

-- client/cl_officepanel.lua
local function fmtMoney(amount)
    amount = tonumber(amount) or 0
    local sign = amount < 0 and '-' or ''
    amount = math.abs(amount)

    local intPart, frac = math.modf(amount)
    frac = math.floor(frac * 100 + 0.5)

    local s = tostring(intPart)
    local formatted = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if formatted:sub(1,1) == ',' then
        formatted = formatted:sub(2)
    end

    return string.format('%s%s.%02d', sign, formatted, frac)
end

local function openPayrollSummary(info)
    if not info or not info.ok then
        lib.notify({
            title       = 'Office Payroll',
            description = (info and info.message) or 'Could not build payroll summary.',
            type        = 'error'
        })
        return
    end

    local options = {}

    local totalEmployees  = info.employee_total or info.employee_count or 0
    local onlineEmployees = info.employee_count or 0

    local treasury        = info.treasury_balance or 0
    local officeShare     = info.office_share or 0.0
    local salaryShare     = info.salary_share or 0.0
    local supplyShare     = info.supply_share or 0.0

    local payrollCost     = info.total_pay or 0
    local supplyCost      = info.supply_cost or 0  -- 0 for now

    local salaryCap       = treasury * salaryShare
    local supplyCap       = treasury * supplyShare
    local remainingShare  = treasury - payrollCost - supplyCost

    local salaryStatus    = (payrollCost <= salaryCap) and 'good' or 'over cap'
    local supplyStatus    = (supplyCost  <= supplyCap)  and 'good' or 'over cap'

    local sharePct        = math.floor(officeShare * 10000 + 0.5) / 100.0  -- e.g. 25.00

    local headerText = string.format(
        '%s — %s\n' ..
        'Employees: %d (online %d)\n' ..
        'Payroll Cost: $%s (%s)\n' ..
        'Supply Cost: $%s (%s)\n' ..
        'Treasury (office share %.2f%%): $%s\n' ..
        'Salary (cap) (%.0f%%): $%s\n' ..
        'Supply (cap) (%.0f%%): $%s\n' ..
        'Estimated office share (remaining): $%s',
        info.region_label or info.region_alias or 'Unknown Region',
        info.office_label or info.job_label or info.job_name or 'Unknown Office',

        totalEmployees,
        onlineEmployees,

        fmtMoney(payrollCost),
        salaryStatus,

        fmtMoney(supplyCost),
        supplyStatus,

        sharePct,
        fmtMoney(treasury),

        salaryShare * 100,
        fmtMoney(salaryCap),

        supplyShare * 100,
        fmtMoney(supplyCap),

        fmtMoney(remainingShare)
    )


    options[#options+1] = {
        title = 'Payroll Summary',
        description = headerText,
        icon = 'info-circle',
        disabled = true
    }

    -- List each employee preview
    for _, e in ipairs(info.employees or {}) do
        options[#options+1] = {
            title = string.format('%s — $%d', e.name or e.citizenid or 'Unknown', e.totalPay or 0),
            description = string.format('Unpaid sessions: %d', e.sessions or 0),
            icon = 'user',
            disabled = true
        }
    end

    -- Confirm button
    local canAfford = info.can_afford and (info.total_pay or 0) > 0

    options[#options+1] = {
        title = 'Confirm Payroll Payout',
        description = canAfford
            and 'Execute payroll now. This will deduct from the regional treasury and pay all listed employees.'
            or 'Cannot execute payroll. Treasury funds are insufficient or there is nothing to pay.',
        icon = 'check-circle',
        disabled = not canAfford,
        onSelect = function()
            if not canAfford then return end

            local result = lib.callback.await('rsg-governor:executeManualPayroll', false)
            if not result or not result.ok then
                lib.notify({
                    title       = 'Office Payroll',
                    description = result and result.message or 'Payroll execution failed.',
                    type        = 'error'
                })
                return
            end

            lib.notify({
                title       = 'Office Payroll',
                description = result.message or 'Payroll complete.',
                type        = 'success'
            })

            -- Return to office panel after run
            openOfficePanel()
        end
    }

    lib.registerContext({
        id = 'officepanel_payroll_summary',
        title = 'Office Payroll',
        menu = 'office_panel_payroll', -- adjust to your main menu id
        options = options
    })

    lib.showContext('officepanel_payroll_summary')
end

-- office_panel_payroll

local function openOfficePanel(data)
    if not data then
        lib.notify({ title = 'Office Panel', description = 'No office data available.', type = 'error' })
        return
    end

    local regionName   = data.region_label or data.region or 'Unknown Region'
    local officeLabel  = data.office_label or data.job_label or 'Office'
    local payMode      = data.pay_mode or 'manual'       -- 'auto' or 'manual'
    local schedule     = data.auto_schedule or 'none'    -- 'weekly', 'semi_monthly', 'monthly_end', 'none'

    local scheduleLabel
    if payMode == 'manual' then
        scheduleLabel = 'Manual (every Saturday · RP payout)'
    else
        if schedule == 'weekly' then
            scheduleLabel = 'Auto · Weekly'
        elseif schedule == 'semi_monthly' then
            scheduleLabel = 'Auto · 15th & End of Month'
        elseif schedule == 'monthly_end' then
            scheduleLabel = 'Auto · End of Month'
        else
            scheduleLabel = 'Auto · (unspecified schedule)'
        end
    end

    local options = {}

    -- HEADER (read-only summary)
    options[#options+1] = {
        title = ('%s — %s'):format(regionName, officeLabel),
        description = string.format(
            'Payment Mode: %s\nSchedule: %s',
            payMode:upper(),
            scheduleLabel
        ),
        icon = 'info-circle',
        disabled = true
    }

    -- Payroll & Attendance
    options[#options+1] = {
        title = 'Payroll & Attendance',
        description = 'Review sessions, configure payment mode, and pay employees.',
        icon = 'money-bill-wave',
        onSelect = function()
            openPayrollMenu(data)
        end
    }

    -- Supply Orders
    options[#options+1] = {
        title = 'Supply Orders',
        description = 'Order ammo, medical supplies, and restraints for this office.',
        icon = 'box-open',
        onSelect = function()
            openSuppliesMenu(data)
        end
    }

    lib.registerContext({
        id = 'office_panel_main',
        title = 'Office Panel',
        options = options
    })

    lib.showContext('office_panel_main')
end

-- Payroll & Attendance menu
function openPayrollMenu(data)
    local payMode     = data.pay_mode or 'manual'
    local schedule    = data.auto_schedule or 'none'
    local regionName  = data.region_label or data.region or 'Unknown Region'
    local officeLabel = data.office_label or data.job_label or 'Office'

    local scheduleLabel
    if payMode == 'manual' then
        scheduleLabel = 'Manual (every Saturday · RP payout)'
    else
        if schedule == 'weekly' then
            scheduleLabel = 'Weekly (Auto)'
        elseif schedule == 'semi_monthly' then
            scheduleLabel = '15th & End of Month (Auto)'
        elseif schedule == 'monthly_end' then
            scheduleLabel = 'End of Month (Auto)'
        else
            scheduleLabel = 'Auto · (unspecified)'
        end
    end

    local options = {}

    options[#options+1] = {
        title = ('Payroll — %s'):format(officeLabel),
        description = string.format(
            'Region: %s\nPayment Mode: %s\nSchedule: %s',
            regionName,
            payMode:upper(),
            scheduleLabel
        ),
        icon = 'info-circle',
        disabled = true
    }

    -- Configure Payment Mode
    options[#options+1] = {
        title = 'Configure Payment Mode',
        description = 'Choose between Auto or Manual payroll and set schedule.',
        icon = 'cog',
        onSelect = function()
            openPayModeMenu(data)
        end
    }

    -- View Employee Sessions / Pending Pay (we can reuse dutylog data later)
    options[#options+1] = {
        title = 'View Employee Sessions',
        description = 'See duty sessions and unpaid balances for this office.',
        icon = 'clipboard-list',
        onSelect = function()
            -- later: open a dedicated Payroll Sessions UI
            lib.notify({ title = 'Coming Soon', description = 'Employee sessions UI not wired yet.', type = 'inform' })
        end
    }

    -- Run Manual Payroll (for RP Saturdays)
    options[#options+1] = {
        title = 'Run Manual Payroll Now',
        description = 'Preview and execute payroll for this office (online employees only).',
        icon = 'money-check-dollar',
        onSelect = function()
            local info = lib.callback.await('rsg-governor:runManualPayroll', false)
            openPayrollSummary(info)
        end
    }

    lib.registerContext({
        id = 'office_panel_payroll',
        title = 'Payroll & Attendance',
        menu = 'office_panel_main', -- adds "<" back arrow
        options = options
    })

    lib.showContext('office_panel_payroll')
end

-- Configure Pay Mode UI
function openPayModeMenu(data)
    local options = {}

    options[#options+1] = {
        title = 'Auto — Weekly',
        description = 'Automatically pay employees once per week.',
        icon = 'calendar-week',
        onSelect = function()
            lib.callback.await('rsg-governor:setOfficePayMode', false, {
                mode = 'auto',
                schedule = 'weekly'
            })
        end
    }

    options[#options+1] = {
        title = 'Auto — 15th & End of Month',
        description = 'Automatically pay employees on the 15th and last day of the month.',
        icon = 'calendar-alt',
        onSelect = function()
            lib.callback.await('rsg-governor:setOfficePayMode', false, {
                mode = 'auto',
                schedule = 'semi_monthly'
            })
        end
    }

    options[#options+1] = {
        title = 'Auto — End of Month Only',
        description = 'Automatically pay employees on the last day of each month.',
        icon = 'calendar-day',
        onSelect = function()
            lib.callback.await('rsg-governor:setOfficePayMode', false, {
                mode = 'auto',
                schedule = 'monthly_end'
            })
        end
    }

    options[#options+1] = {
        title = 'Manual — Weekly (RP)',
        description = 'Head of Office pays employees manually every Saturday.',
        icon = 'user-clock',
        onSelect = function()
            lib.callback.await('rsg-governor:setOfficePayMode', false, {
                mode = 'manual',
                schedule = 'saturday'
            })
        end
    }

    lib.registerContext({
        id = 'office_panel_paymode',
        title = 'Payment Mode Settings',
        menu = 'office_panel_payroll', -- back arrow
        options = options
    })

    lib.showContext('office_panel_paymode')
end

-- Supply Orders UI
function openSuppliesMenu(data)
    local regionName  = data.region_label or data.region or 'Unknown Region'
    local officeLabel = data.office_label or data.job_label or 'Office'

    local options = {}

    options[#options+1] = {
        title = ('Supply Orders — %s'):format(officeLabel),
        description = ('Region: %s'):format(regionName),
        icon = 'info-circle',
        disabled = true
    }

    local function makeSupplyOption(title, desc, itemName)
        options[#options+1] = {
            title = title,
            description = desc,
            icon = 'box',
            onSelect = function()
                local input = lib.inputDialog('Order '..title, {
                    { type = 'number', label = 'Quantity', default = 1, min = 1, max = 100 }
                })
                if not input or not input[1] then return end
                local qty = tonumber(input[1]) or 0
                if qty <= 0 then return end

                TriggerServerEvent('rsg-governor:server:orderSupply', itemName, qty)
            end
        }
    end

    makeSupplyOption('Revolver Ammo Box', 'Order revolver ammunition for lawmen.', 'ammo_box_revolver')
    makeSupplyOption('Repeater Ammo Box', 'Order repeater ammunition for lawmen.', 'ammo_box_reapter')
    makeSupplyOption('Bandages', 'Order medical bandages for medics.', 'bandage')
    makeSupplyOption('Handcuffs', 'Order restraints for law enforcement use.', 'handcuff')

    lib.registerContext({
        id = 'office_panel_supplies',
        title = 'Supply Orders',
        menu = 'office_panel_main', -- back arrow
        options = options
    })

    lib.showContext('office_panel_supplies')
end

-- Command to open Office Panel
RegisterCommand('officepanel', function()
    local data = lib.callback.await('rsg-governor:getOfficePanelData', false)
    openOfficePanel(data or {})
end, false)
