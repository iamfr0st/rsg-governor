-- rsg-governor/server/sv_funding.lua
-- Handles office funds stored in rsg-economy treasury

local RSGCore = exports['rsg-core']:GetCoreObject()

local TREASURY_TABLE = 'economy_treasury'

local function cents(n)
    n = tonumber(n or 0) or 0
    return math.floor(n)
end

local function dollars_from_cents(c)
    return (tonumber(c) or 0) / 100.0
end

-- Fetch region's treasury + office funds
local function getOfficeFunds(region)
    region = tostring(region or ''):lower()

    local row = MySQL.single.await(([[ 
        SELECT balance_cents, lawman_fund_cents, medic_fund_cents
          FROM %s WHERE region_name = ?
    ]]):format(TREASURY_TABLE), { region })

    if not row then
        return {
            treasury = 0,
            lawman   = 0,
            medic    = 0
        }
    end

    return {
        treasury = dollars_from_cents(row.balance_cents),
        lawman   = dollars_from_cents(row.lawman_fund_cents),
        medic    = dollars_from_cents(row.medic_fund_cents)
    }
end

exports('GetOfficeFunds', getOfficeFunds)

-- Governor moves money from treasury → specific office
local function transferToOffice(region, officeKey, amountDollars)
    region       = tostring(region or ''):lower()
    officeKey    = tostring(officeKey or ''):lower()
    local amount = cents(amountDollars * 100.0)

    if amount <= 0 then return false, 'Invalid amount' end

    -- Determine which field to update
    local field = nil

    if officeKey == 'lawman' or officeKey == 'sheriff' then
        field = 'lawman_fund_cents'
    elseif officeKey == 'medic' then
        field = 'medic_fund_cents'
    else
        return false, 'Unknown office'
    end

    -- Check available treasury
    local treas = MySQL.single.await(([[ 
        SELECT balance_cents FROM %s WHERE region_name = ?
    ]]):format(TREASURY_TABLE), { region })

    if not treas then return false, 'Treasury missing' end

    local available = tonumber(treas.balance_cents or 0) or 0
    if available < amount then
        return false, 'Not enough treasury funds'
    end

    -- Transfer money
    MySQL.transaction.await({
        {
            query = ([[ UPDATE %s SET balance_cents = balance_cents - ? WHERE region_name = ? ]]):format(TREASURY_TABLE),
            values = { amount, region }
        },
        {
            query = ([[ UPDATE %s SET %s = %s + ? WHERE region_name = ? ]]):format(TREASURY_TABLE, field, field),
            values = { amount, region }
        },
    })

    return true
end

exports('TransferToOffice', transferToOffice)

-- Callback used by Governor UI
lib.callback.register('rsg-governor:getOfficeFunds', function(src, region)
    return getOfficeFunds(region)
end)
