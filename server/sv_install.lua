-- rsg-governor/server/sv_install.lua
-- Export used by rsg-election to install a new governor
-- Also updates the governors table.

local RSGCore = exports['rsg-core']:GetCoreObject()
RSGGovernor   = RSGGovernor or {}
Config        = Config or {}
Config.RegionGovernorJobs = Config.RegionGovernorJobs or {
    -- default is just 'governor' for all regions
}
lib.locale()

local function debugPrint(...)
    print('[rsg-governor]', ...)
end

-- Normalize region_hash to hex string like "0x41332496"
local function normalizeRegionHash(raw)
    if not raw then return nil end

    if type(raw) == 'number' then
        return string.format("0x%08X", raw)
    end

    local s = tostring(raw)

    if s:match("^%d+$") then
        local n = tonumber(s)
        if n then
            return string.format("0x%08X", n)
        end
    end

    s = s:gsub("^0X", "0x")
    return s
end

local function getGovernorJobNameForRegion(region_alias)
    if Config.RegionGovernorJobs[region_alias] then
        return Config.RegionGovernorJobs[region_alias]
    end
    return 'governor'
end

-- Best-effort way to get some unique identifier string
local function getIdentifierForPlayer(Player)
    -- Adjust these if your core uses a different key
    if Player.PlayerData.license then
        return Player.PlayerData.license
    end
    if Player.PlayerData.identifier then
        return Player.PlayerData.identifier
    end
    -- fallback: citizenid as identifier
    return Player.PlayerData.citizenid or ('src:' .. tostring(Player.PlayerData.source or '?'))
end

--- InstallGovernor(region_alias_or_hash, citizenid)
--- Called from rsg-election when an election is finalized
--- Returns true/false
function RSGGovernor.InstallGovernor(region_arg, citizenid)
    region_arg = tostring(region_arg or '')
    citizenid  = tostring(citizenid or '')

    if region_arg == '' or citizenid == '' then
        debugPrint('InstallGovernor: missing region_arg or citizenid')
        return false
    end

    local Player = RSGCore.Functions.GetPlayerByCitizenId(citizenid)
    if not Player then
        debugPrint(('InstallGovernor: player with citizenid %s not online'):format(citizenid))
        return false
    end

    -- Try to resolve region info via residency (hash + alias + name)
    local region_hash, region_alias

    local okRegion, regionInfo = pcall(function()
        return exports['rsg-residency']:GetCitizenRegion(citizenid)
    end)

    if okRegion and regionInfo then
        region_hash  = normalizeRegionHash(regionInfo.hash or regionInfo.region_hash)
        region_alias = tostring(regionInfo.alias or regionInfo.region_alias or region_arg):lower()
    else
        -- Fallback: treat region_arg as alias, hash unknown
        region_alias = region_arg:lower()
        region_hash  = nil
    end

    -- Make sure we at least have an alias
    if not region_alias or region_alias == '' then
        region_alias = region_arg:lower()
    end

    local jobName = getGovernorJobNameForRegion(region_alias)

    -- Remember previous job
    local prevJob   = nil
    local prevGrade = nil
    if Player.PlayerData.job then
        prevJob   = Player.PlayerData.job.name
        prevGrade = Player.PlayerData.job.grade and Player.PlayerData.job.grade.level or 0
    end

    -- Actually make them governor
    Player.Functions.SetJob(jobName, 0)

    -- Prepare basic info for DB rows
    local identifier   = getIdentifierForPlayer(Player)
    local characterName = (Player.PlayerData.charinfo and
        (Player.PlayerData.charinfo.firstname or '') .. ' ' ..
        (Player.PlayerData.charinfo.lastname or '')) or 'Unknown'

    ---------------------------------
    -- Update governors table
    ---------------------------------
    pcall(function()
        if not MySQL or not MySQL.update or not MySQL.insert then return end

        -- Deactivate any previous governor for this region
        MySQL.update([[
            UPDATE governors
            SET active = 0, removed_at = NOW()
            WHERE region_alias = ? AND active = 1
        ]], { region_alias })

        -- Insert new active governor row
        MySQL.insert([[
            INSERT INTO governors (identifier, citizenid, region_hash, region_alias, active, character_name)
            VALUES (?, ?, ?, ?, 1, ?)
        ]], {
            identifier,
            citizenid,
            region_hash or '',
            region_alias,
            characterName
        })
    end)

    ---------------------------------
    -- Optional: log governor term
    ---------------------------------
    pcall(function()
        if not MySQL or not MySQL.insert then return end

        -- Comment this out if you don't want term logging or table doesn't exist
        MySQL.insert([[
            INSERT INTO governor_terms (citizenid, region_alias, job_name, previous_job, previous_grade)
            VALUES (?, ?, ?, ?, ?)
        ]], {
            citizenid,
            region_alias,
            jobName,
            prevJob,
            prevGrade
        })
    end)

    debugPrint(('InstallGovernor: %s is now governor of %s (job=%s)')
        :format(characterName, region_alias, jobName)
    )

    return true
end

-- Export for other resources (like rsg-election)
exports('InstallGovernor', function(region_alias, citizenid)
    return RSGGovernor.InstallGovernor(region_alias, citizenid)
end)
