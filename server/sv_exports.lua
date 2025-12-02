-- rsg-governor/server/sv_exports.lua
-- All server exports & shared callbacks for rsg-governor v2

Gov = Gov or {}

-----------------------------------------------------------------
-- SAFE WRAPPER HELPERS
-----------------------------------------------------------------

local function safeCall(fn, ...)
    if type(fn) == 'function' then
        return fn(...)
    end
    return nil
end

-----------------------------------------------------------------
-- PERMISSION / GOVERNOR IDENTITY EXPORTS
-- (implemented in server/sv_auth.lua)
-----------------------------------------------------------------

exports('CanActOnRegion', function(src, regionName, actionTag)
    return safeCall(Gov.CanActOnRegion, src, regionName, actionTag)
end)

exports('GetGovernorRegionForPlayer', function(src)
    return safeCall(Gov.GetGovernorRegionForPlayer, src)
end)

exports('IsAnyGovernorOnline', function(regionName)
    return safeCall(Gov.IsAnyGovernorOnline, regionName) or false
end)

-----------------------------------------------------------------
-- OFFICES / HEADS / SALARIES EXPORTS
-- (implemented in server/sv_offices.lua)
-----------------------------------------------------------------

exports('GetRegionOffices', function(region_name)
    return safeCall(Gov.GetRegionOffices, region_name) or {}
end)

-----------------------------------------------------------------
-- FUNDING CONFIG EXPORTS
-- (implemented in server/sv_funding.lua)
-----------------------------------------------------------------

exports('GetRegionFunding', function(region_name)
    return safeCall(Gov.GetRegionFunding, region_name) or {}
end)

-----------------------------------------------------------------
-- OX_LIB CALLBACKS FOR CLIENTS
-----------------------------------------------------------------

-- Used by /governor panel to know "Which region am I governor of?"
lib.callback.register('rsg-governor:getMyGovernorRegion', function(src)
    return safeCall(Gov.GetGovernorRegionForPlayer, src)
end)
