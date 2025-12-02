-- rsg-governor/shared/sh_exports.lua
-- Centralized list of server export names for rsg-governor
-- NOTE: this file does NOT define exports, only names.
-- Actual exports are defined in server/sv_exports.lua.

GovExports = {
    -- Permission / identity
    CanActOnRegion          = 'CanActOnRegion',
    GetGovernorRegion       = 'GetGovernorRegionForPlayer',
    IsAnyGovernorOnline     = 'IsAnyGovernorOnline',

    -- Offices / salaries
    GetRegionOffices        = 'GetRegionOffices',

    -- Funding config (per region/jobs)
    GetRegionFunding        = 'GetRegionFunding',
}
