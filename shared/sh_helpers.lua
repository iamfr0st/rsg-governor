-- rsg-governor/shared/sh_helpers.lua

Gov = Gov or {}

function Gov.NormRegion(s)
    s = tostring(s or ''):lower()
    s = s:gsub('[%s%-]+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    return s
end

function Gov.Notify(src, msg, type_, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = title or 'Governor',
        description = msg,
        type        = type_ or 'inform',
        duration    = 8000,
    })
end

function Gov.IsOwnerIdentifier(identifier)
    if not Config or not Config.OwnerIdentifiers then return false end
    for idType, list in pairs(Config.OwnerIdentifiers) do
        for _, v in ipairs(list) do
            if v == identifier then
                return true
            end
        end
    end
    return false
end

-- Requires Config.BankBranches to be defined in config.lua

function getPayPreference(citizenid)
    if not citizenid then
        return { mode = 'cash', bank_branch = nil }
    end

    local rows = MySQL.query.await(
        'SELECT pay_mode, bank_branch FROM governor_pay_prefs WHERE citizenid = ? LIMIT 1',
        { citizenid }
    )

    if rows and rows[1] then
        local mode = rows[1].pay_mode or 'cash'
        local branch = rows[1].bank_branch

        if mode ~= 'cash' and mode ~= 'bank' then
            mode = 'cash'
        end

        if branch and (not Config.BankBranches or not Config.BankBranches[branch]) then
            branch = nil
        end

        return { mode = mode, bank_branch = branch }
    end

    return { mode = 'cash', bank_branch = nil }
end

function setPayPreference(citizenid, mode, branch)
    if not citizenid then return { mode = 'cash', bank_branch = nil } end

    mode = (mode == 'bank') and 'bank' or 'cash'

    local branchToSave = nil
    if mode == 'bank' and branch and Config.BankBranches and Config.BankBranches[branch] then
        branchToSave = branch
    end

    MySQL.insert.await([[
        INSERT INTO governor_pay_prefs (citizenid, pay_mode, bank_branch)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            pay_mode    = VALUES(pay_mode),
            bank_branch = VALUES(bank_branch)
    ]], { citizenid, mode, branchToSave })

    return { mode = mode, bank_branch = branchToSave }
end

-- If something else calls this helper, keep it:
function getPayMode(citizenid)
    local pref = getPayPreference(citizenid)
    return pref.mode
end
