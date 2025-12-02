local RSGCore = exports['rsg-core']:GetCoreObject()

-- Called from server command /dutylog
RegisterNetEvent('rsg-governor:client:openDutyLog', function()
    openDutyLogUI()
end)

local monthNames = {
    "January","February","March","April","May","June",
    "July","August","September","October","November","December"
}

-- Local mapping for bank branches (for labels in the UI)
local BankBranches = {
    valbank = 'Valentine Bank',
    rhobank = 'Rhodes Bank',
    bank    = 'Saint Denis Bank',
    blkbank = 'Blackwater Bank',
    armbank = 'Armadillo Bank',
}

-- Format in-game date/time line from ig_* fields
local function fmtInGame(s)
    if not s.ig_start_year or not s.ig_end_year then
        return "In-game date unavailable (pre-update)"
    end

    local function to12h(hour, minute)
        hour = tonumber(hour) or 0
        minute = tonumber(minute) or 0
        local suffix = "AM"
        if hour == 0 then
            hour = 12
            suffix = "AM"
        elseif hour == 12 then
            suffix = "PM"
        elseif hour > 12 then
            hour = hour - 12
            suffix = "PM"
        end
        return string.format("%d:%02d %s", hour, minute, suffix)
    end

    local startStr = string.format(
        "%s %d, %d | %s",
        monthNames[s.ig_start_month or 1] or "January",
        s.ig_start_day or 1,
        s.ig_start_year or 1898,
        to12h(s.ig_start_hour or 0, s.ig_start_minute or 0)
    )

    local endStr = string.format(
        "%s %d, %d | %s",
        monthNames[s.ig_end_month or 1] or "January",
        s.ig_end_day or 1,
        s.ig_end_year or 1898,
        to12h(s.ig_end_hour or 0, s.ig_end_minute or 0)
    )

    return string.format("%s -> %s", startStr, endStr)
end

-- Format real-world datetime strings "YYYY-MM-DD HH:MM:SS"
local function fmtRealRange(startStr, endStr)
    if not startStr and not endStr then
        return "No real-world timestamps recorded."
    end

    local function parse(dt)
        if not dt or dt == '' or dt == "?" then return nil end
        local y, m, d, hh, mm, ss = dt:match("^(%d+)%-(%d+)%-(%d+)%s+(%d+):(%d+):(%d+)")
        if not y then return nil end
        return {
            year   = tonumber(y),
            month  = tonumber(m),
            day    = tonumber(d),
            hour   = tonumber(hh),
            minute = tonumber(mm),
            second = tonumber(ss),
        }
    end

    local function to12h(hour, minute)
        hour = tonumber(hour) or 0
        minute = tonumber(minute) or 0
        local suffix = "AM"
        if hour == 0 then
            hour = 12
            suffix = "AM"
        elseif hour == 12 then
            suffix = "PM"
        elseif hour > 12 then
            hour = hour - 12
            suffix = "PM"
        end
        return string.format("%d:%02d %s", hour, minute, suffix)
    end

    local s = parse(startStr)
    local e = parse(endStr)

    if not s and not e then
        return "No real-world timestamps recorded."
    end

    local function fmt(dt)
        if not dt then return "??" end
        local monthName = monthNames[dt.month or 1] or "January"
        local time12 = to12h(dt.hour or 0, dt.minute or 0)
        return string.format("%s %d, %d | %s", monthName, dt.day or 1, dt.year or 2000, time12)
    end

    local sText = fmt(s)
    local eText = fmt(e)

    if not e then
        return string.format("%s -> (ongoing)", sText)
    end

    return string.format("%s -> %s", sText, eText)
end

-- Helper to convert float hours into "X hours Y minutes"
local function hoursToHM(hoursFloat)
    hoursFloat = tonumber(hoursFloat) or 0.0
    local totalMin = math.floor(hoursFloat * 60 + 0.5)
    local h = math.floor(totalMin / 60)
    local m = totalMin % 60
    return h, m
end

--==========================
-- Payment mode selection UI
--==========================
local function openBankBranchSelect(currentBranchId)
    local options = {}

    for id, label in pairs(BankBranches) do
        -- capture per-iteration values so the closure sees the right ones
        local branchId    = id
        local branchLabel = label

        options[#options+1] = {
            title       = branchLabel,
            description = string.format("Use %s for salary deposits.", branchLabel),
            icon        = (currentBranchId == branchId) and 'check' or 'building-columns',
            onSelect    = function()
                local ok = lib.callback.await('rsg-governor:setPayMode', false, 'bank', branchId)
                if ok then
                    lib.notify({
                        title       = 'Payment Mode',
                        type        = 'success',
                        description = ('Set to BANK (%s).'):format(branchLabel)
                    })
                    openDutyLogUI()
                else
                    lib.notify({
                        title       = 'Payment Mode',
                        type        = 'error',
                        description = 'Failed to update payment mode.'
                    })
                end
            end
        }
    end

    lib.registerContext({
        id = 'dutylog_bank_branch',
        title = 'Select Bank Branch',
        options = options
    })
    lib.showContext('dutylog_bank_branch')
end

local function selectPayMode(currentMode, currentBranchId)
    currentMode = tostring(currentMode or 'bank'):upper()

    lib.registerContext({
        id = 'dutylog_pay_mode',
        title = 'Change Payment Mode',
        options = {
            {
                title = 'BANK',
                description = 'Receive payroll to a bank account (requires branch selection).',
                icon = 'building-columns',
                onSelect = function()
                    openBankBranchSelect(currentBranchId)
                end
            },
            {
                title = 'CASH',
                description = 'Receive payroll in cash on hand.',
                icon = 'sack-dollar',
                onSelect = function()
                    local ok = lib.callback.await('rsg-governor:setPayMode', false, 'cash', nil)
                    if ok then
                        lib.notify({
                            title = 'Payment Mode',
                            type = 'success',
                            description = 'Set to CASH.'
                        })
                        openDutyLogUI()
                    else
                        lib.notify({
                            title = 'Payment Mode',
                            type = 'error',
                            description = 'Failed to update payment mode.'
                        })
                    end
                end
            },
        }
    })
    lib.showContext('dutylog_pay_mode')
end

--==========================
-- Main Duty Log UI
--==========================
function openDutyLogUI()
    local data = lib.callback.await('rsg-governor:getDutyLog', false)
    if not data then
        lib.notify({ title = 'Duty Log', description = 'Cannot fetch duty log.', type = 'error' })
        return
    end

    local options = {}

    -- SUMMARY
    local regionName = tostring(data.region or 'unknown')
    regionName = regionName:gsub("^%l", string.upper)

    local payMode = tostring(data.pay_mode or 'cash'):upper()
    local officeMode = tostring(data.office_pay_mode or 'manual'):upper()

    local branchLine = ''
    if data.pay_mode == 'bank' then
        local label = data.bank_branch_label
        if not label or label == '' then
            if data.bank_branch_id and BankBranches[data.bank_branch_id] then
                label = BankBranches[data.bank_branch_id]
            else
                label = '(not set)'
            end
        end
        branchLine = ('\nBank Branch: %s'):format(label)
    end

    local summaryDesc = string.format(
        'Unpaid: %.1f h Regular | %.1f h OT\nEstimated Pay: $%d\nPayment Mode: %s%s\nOffice Payroll Mode: %s',
        data.unpaid_regular or 0.0,
        data.unpaid_overtime or 0.0,
        math.floor((data.unpaid_total or 0) + 0.5),
        payMode,
        branchLine,
        officeMode
    )

    options[#options+1] = {
        title = ('%s — %s'):format(regionName, data.job_name or 'Unknown Job'),
        description = summaryDesc,
        icon = 'info-circle',
        disabled = true
    }

    options[#options+1] = {
        title = 'Change Payment Mode',
        description = 'Choose if you want payroll to go to Cash or Bank (with branch).',
        icon = 'credit-card',
        onSelect = function()
            selectPayMode(data.pay_mode, data.bank_branch_id)
        end
    }

    -- SESSIONS LIST
    for _, s in ipairs(data.sessions or {}) do
        local realLine   = fmtRealRange(s.real_start or s.started_at, s.real_end or s.ended_at)
        local ingameLine = fmtInGame(s)

        local regH, regM = hoursToHM(s.regular or 0.0)
        local otH,  otM  = hoursToHM(s.overtime or 0.0)

        options[#options+1] = {
            title = string.format('%s — $%d',
                s.paid == 1 and '[PAID]' or '[UNPAID]',
                math.floor((s.estimated or 0) + 0.5)
            ),
            description = string.format(
                'Real Date/Time:\n%s\n\nIn-Game Date/Time:\n%s\nRegular: %d hours %d minutes\nO.T: %d hours %d minutes',
                realLine,
                ingameLine,
                regH, regM,
                otH, otM
            ),
            arrow = true,
            onSelect = function()
                openDutyLogDetails(s, data, realLine, ingameLine)
            end
        }
    end

    lib.registerContext({
        id = 'dutylog_menu',
        title = 'Duty Log',
        options = options
    })

    lib.showContext('dutylog_menu')
end

--==========================
-- Duty Session Details UI
--==========================
function openDutyLogDetails(s, data, realLine, ingameLine)
    realLine   = realLine   or fmtRealRange(s.real_start or s.started_at, s.real_end or s.ended_at)
    ingameLine = ingameLine or fmtInGame(s)

    local regH, regM = hoursToHM(s.regular or 0.0)
    local otH,  otM  = hoursToHM(s.overtime or 0.0)

    local baseRate = tonumber(data.base_rate or 0) or 0
    local otMult   = tonumber(data.overtime_multiplier or 1.5) or 1.5
    local otRate   = math.floor(baseRate * otMult + 0.5)

    local estimated = math.floor((s.estimated or 0) + 0.5)

    local description = string.format(
        'Real Date/Time:\n%s\n\nIn-Game Date/Time:\n%s\n\nRegular: %d hours %d minutes\nOvertime: %d hours %d minutes\nRate: $%d/hr\nOT Rate: $%d/hr\n\nEstimated Pay: $%d\nStatus: %s',
        realLine,
        ingameLine,
        regH, regM,
        otH, otM,
        baseRate,
        otRate,
        estimated,
        s.paid == 1 and 'PAID' or 'UNPAID'
    )

    lib.registerContext({
        id = 'dutylog_detail',
        title = 'Duty Session Details',
        options = {
            {
                title = 'Duty Session',
                description = description,
                icon = 'clipboard',
                disabled = true
            }
        }
    })

    lib.showContext('dutylog_detail')
end
