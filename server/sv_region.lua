--======================================================================
-- rsg-governor / server/sv_regions.lua
-- Standard region resolver for governor/economy code.
--
-- Normalized concepts:
--   region_hash  : map zone hash (hex string, e.g. "0x41332496")
--   region_name  : canonical slug (e.g. "new_hanover")
--   region_alias : spaced lower (e.g. "new hanover")
--   label        : pretty UI (e.g. "New Hanover")
--
-- NOTE:
--  - This module is intentionally lightweight.
--  - It tries to use rsg-economy / rsg-residency if available.
--  - All fields are *best effort*; if something is missing, you still
--    get a sane "Unknown Region" struct instead of nils everywhere.
--======================================================================

Region = Region or {}

-- -------------------------------------------------------------------
-- Local static fallback mapping (only here, nowhere else)
-- If residency exports are not wired, we still resolve the basics.
-- Add more regions here later if needed.
-- -------------------------------------------------------------------
local LOCAL_REGION_FALLBACK = {
    -- by canonical name ("new_hanover")
    by_name = {
        new_hanover = '0x41332496',
    },
    -- by alias ("new hanover")
    by_alias = {
        ['new hanover'] = '0x41332496',
    },
    -- reverse: by hash -> alias
    by_hash = {
        ['0x41332496'] = 'new hanover',
        ['0X41332496'] = 'new hanover',
    }
}

local function toHexHash(hash)
    if not hash then return nil end

    local t = type(hash)

    if t == 'number' then
        return string.format('0x%08X', hash)
    elseif t == 'string' then
        -- Already hex-like?
        if hash:match('^0x') or hash:match('^0X') then
            return hash
        end
        local n = tonumber(hash)
        if n then
            return string.format('0x%08X', n)
        end
        return hash
    end

    return nil
end

local function normalizeName(name)
    local s = tostring(name or 'unknown'):lower()
    -- turn spaces/hyphens into underscores
    s = s:gsub('[%s%-]+', '_')
    return s
end

local function normalizeAlias(alias)
    local s = tostring(alias or 'unknown'):lower()
    -- turn underscores/hyphens into single space
    s = s:gsub('[_%-]+', ' ')
    s = s:gsub('%s+', ' ')
    return s
end

local function aliasToLabel(alias)
    alias = normalizeAlias(alias)
    -- Title-case each word
    local out = alias:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return out
end

----------------------------------------------------------------
-- Safely call rsg-residency export if it exists
-- Adjust function names here if your residency uses different API
----------------------------------------------------------------
local function tryResidencyByHash(hash)
    local ok, res = pcall(function()
        if not exports['rsg-residency'] then return nil end
        -- Example: if you have an export like GetRegionAliasByHash(hash)
        if exports['rsg-residency'].GetRegionAliasByHash then
            return exports['rsg-residency']:GetRegionAliasByHash(hash)
        end
        return nil
    end)
    if ok then
        return res
    end
    return nil
end

local function tryResidencyByName(name)
    local ok, res = pcall(function()
        if not exports['rsg-residency'] then return nil end
        -- Example: if you have an export like GetRegionHashByName(name)
        if exports['rsg-residency'].GetRegionHashByName then
            return exports['rsg-residency']:GetRegionHashByName(name)
        end
        return nil
    end)
    if ok then
        return res
    end
    return nil
end

--======================================================
-- Region:FromSource(src)
--  Use rsg-economy:getRegionHash (already in your setup)
--======================================================
function Region.FromSource(src)
    local ok, hash, alias = pcall(function()
        -- Your existing callback: returns regionHash, regionAlias
        return lib.callback.await('rsg-economy:getRegionHash', src)
    end)

    if not ok or not hash then
        return {
            hash  = nil,
            name  = 'unknown',
            alias = 'unknown',
            label = 'Unknown Region',
        }
    end

    local hex   = toHexHash(hash)
    local a     = normalizeAlias(alias)
    local name  = normalizeName(a)
    local label = aliasToLabel(a)

    return {
        hash  = hex,
        name  = name,
        alias = a,
        label = label,
    }
end

--======================================================
-- Region:FromHash(region_hash)
--  Best-effort: try residency to get alias, otherwise
--  check LOCAL_REGION_FALLBACK, otherwise generic.
--======================================================
function Region.FromHash(region_hash)
    local hex = toHexHash(region_hash)
    if not hex then
        return {
            hash  = nil,
            name  = 'unknown',
            alias = 'unknown',
            label = 'Unknown Region',
        }
    end

    -- 1) Try residency
    local alias = tryResidencyByHash(hex)

    -- 2) Fallback: local mapping by hash
    if (not alias or alias == '') and LOCAL_REGION_FALLBACK.by_hash[hex] then
        alias = LOCAL_REGION_FALLBACK.by_hash[hex]
    end

    if not alias or alias == '' then
        -- We at least know the hash
        return {
            hash  = hex,
            name  = 'unknown',
            alias = 'unknown',
            label = 'Unknown Region',
        }
    end

    local a     = normalizeAlias(alias)
    local name  = normalizeName(a)
    local label = aliasToLabel(a)

    return {
        hash  = hex,
        name  = name,
        alias = a,
        label = label,
    }
end

--======================================================
-- Region:FromName(region_name)
--  Accepts "new_hanover" or "new hanover" etc.
--  Tries residency to get a hash; if not available, uses
--  LOCAL_REGION_FALLBACK; still returns normalized fields.
--======================================================
function Region.FromName(region_name)
    local name  = normalizeName(region_name)
    local alias = normalizeAlias(region_name)
    local label = aliasToLabel(alias)

    local hash  = nil

    -- 1) Try residency
    local residHash = tryResidencyByName(name)
    if residHash then
        hash = toHexHash(residHash)
    end

    -- 2) Fallback: local mapping
    if not hash then
        hash = LOCAL_REGION_FALLBACK.by_name[name]
            or LOCAL_REGION_FALLBACK.by_alias[alias]
    end

    if hash then
        hash = toHexHash(hash)
    end

    return {
        hash  = hash,
        name  = name,
        alias = alias,
        label = label,
    }
end

--======================================================
-- Region:FromAlias(region_alias)
--  Just another entry point; same shape as FromName.
--======================================================
function Region.FromAlias(region_alias)
    return Region.FromName(region_alias)
end

--======================================================
-- Region:FromOfficeHeadRow(row)
--  Helper for governor_office_heads rows:
--    row.region_name
--    row.region_hash (if you add it later)
--======================================================
function Region.FromOfficeHeadRow(row)
    if not row then
        return {
            hash  = nil,
            name  = 'unknown',
            alias = 'unknown',
            label = 'Unknown Region',
        }
    end

    local hash = row.region_hash or nil
    local name = row.region_name or 'unknown'

    if hash then
        return Region.FromHash(hash)
    end

    return Region.FromName(name)
end
