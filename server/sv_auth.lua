-- rsg-governor/server/sv_auth.lua
-- Central permissions for governors & owners, using `governors` table
-- Columns expected: id, identifier, citizenid (optional), char_name, region_alias, region_hash (any), active

local RSGCore = exports['rsg-core']:GetCoreObject()
Gov          = Gov or {}
lib.locale()

local GOVERNOR_TABLE = 'governors'

-------------------------------------------------
-- Owner check (full power everywhere)
-------------------------------------------------
local function isServerOwner(src)
    local ids = GetPlayerIdentifiers(src)
    if not ids then return false end

    for _, id in ipairs(ids) do
        if Gov.IsOwnerIdentifier(id) then
            return true
        end
    end
    return false
end

-------------------------------------------------
-- Governor lookup by player identifiers
-------------------------------------------------
-- Try all identifiers the player has (prefer license:), return the row or nil
local function getGovernorRowForPlayer(src)
    local ids = GetPlayerIdentifiers(src)
    if not ids or #ids == 0 then return nil end

    local ordered = {}
    for _, id in ipairs(ids) do
        if id:sub(1, 8) == 'license:' then
            table.insert(ordered, 1, id)
        else
            table.insert(ordered, id)
        end
    end

    for _, ident in ipairs(ordered) do
        local row = MySQL.single.await(
            ('SELECT * FROM %s WHERE identifier = ? AND active = 1 LIMIT 1'):format(GOVERNOR_TABLE),
            { ident }
        )
        if row then
            return row
        end
    end

    return nil
end

-------------------------------------------------
-- Public permission helpers
-------------------------------------------------

function Gov.CanActOnRegion(src, regionName, actionTag)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end

    -- 1) Server owner: always allowed
    if isServerOwner(src) then
        if Config.Debug then
            print(('[rsg-governor] OWNER %s allowed on %s (%s)')
                :format(GetPlayerName(src), tostring(regionName), tostring(actionTag or '')))
        end
        return true
    end

    -- 2) Governor: find row by identifier
    local row = getGovernorRowForPlayer(src)
    if not row then
        if Config.Debug then
            print(('[rsg-governor] %s is not governor for any region (%s)')
                :format(GetPlayerName(src), tostring(actionTag or '')))
        end
        return false
    end

    local govAlias = row.region_alias or ''
    if govAlias == '' then
        if Config.Debug then
            print(('[rsg-governor] %s has governor row without region_alias (%s)')
                :format(GetPlayerName(src), tostring(actionTag or '')))
        end
        return false
    end

    local wantedNorm = Gov.NormRegion(regionName or '')
    local govNorm    = Gov.NormRegion(govAlias)

    if wantedNorm ~= govNorm then
        if Config.Debug then
            print(('[rsg-governor] %s governor of %s, denied on %s (%s)')
                :format(GetPlayerName(src), govNorm, wantedNorm, tostring(actionTag or '')))
        end
        return false
    end

    if Config.Debug then
        print(('[rsg-governor] %s allowed on region %s (%s)')
            :format(GetPlayerName(src), govNorm, tostring(actionTag or '')))
    end
    return true
end

function Gov.GetGovernorRegionForPlayer(src)
    local row = getGovernorRowForPlayer(src)
    if not row or not row.region_alias or row.region_alias == '' then
        return nil
    end
    return Gov.NormRegion(row.region_alias)
end

-- Used for permits auto/manual logic, etc.
function Gov.IsAnyGovernorOnline(regionName)
    local wantedNorm = Gov.NormRegion(regionName or '')

    local players = RSGCore.Functions.GetPlayers()
    for _, src in ipairs(players) do
        local row = getGovernorRowForPlayer(src)
        if row and row.region_alias and row.region_alias ~= '' then
            if Gov.NormRegion(row.region_alias) == wantedNorm then
                return true
            end
        end
    end
    return false
end

-------------------------------------------------
-- Exports / Callbacks
-------------------------------------------------

exports('CanActOnRegion', function(src, regionName, actionTag)
    return Gov.CanActOnRegion(src, regionName, actionTag)
end)

exports('GetGovernorRegionForPlayer', function(src)
    return Gov.GetGovernorRegionForPlayer(src)
end)

exports('IsAnyGovernorOnline', function(regionName)
    return Gov.IsAnyGovernorOnline(regionName)
end)

-- For the /governor panel client
lib.callback.register('rsg-governor:getMyGovernorRegion', function(src)
    return Gov.GetGovernorRegionForPlayer(src)
end)
