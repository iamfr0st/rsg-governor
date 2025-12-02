Config = {}

-- Who counts as "server owner" (full power everywhere)
Config.OwnerIdentifiers = {
    steam = {
        -- 'steam:110000112345678',
    },
    license = {
        -- 'license:xxxx',
    }
}

-- Governor panel + auth behaviour
Config.Governor = {
    AllowDeputies = true,        -- future: deputies can share some powers
    PanelCommand  = 'governor',  -- /governor opens governor UI (when we add it)
}

-- Link to economy resource (for taxes, treasury, reporting)
Config.Economy = {
    ResourceName          = 'rsg-economy',
    TaxCategories         = { sales = true, trade = true, property = true },
    GovernorsCanOnlySetHere = true, -- governors cannot pick arbitrary region in UI
    -- IMPORTANT:
    -- Withdrawal from treasury is NEVER exposed via governor commands.
    -- Only the economy resource (and owner/admin) does transfers.
}

-- Offices & salaries
Config.Offices = {
    -- Default office definitions; one set per region.
    -- Governors can assign heads and salaries, but not directly move money.
    Default = {
        { key = 'sheriff',       label = 'Sheriff',       maxSalary = 100 },
        { key = 'medic',       label = 'Medic',       maxSalary = 120 },
        { key = 'judge',         label = 'Judge',         maxSalary = 150 },
        { key = 'tax_collector', label = 'Tax Collector', maxSalary = 80  },
        { key = 'doctor',        label = 'Medical Chief', maxSalary = 90  },
    },

    -- Funding shares per office (how much of regional "gov payroll" budget they *may* receive)
    -- This is just configuration; actual treasury payout stays in rsg-economy.
    FundingMinShare = 0.0,
    FundingMaxShare = 1.0,
}

Config.Offices = Config.Offices or {}

Config.Offices.JobMap = Config.Offices.JobMap or {
    -- office_key = function(region_alias) return job_name end
    lawman = function(region_alias)
        -- e.g. "new_hanover" -> "new_hanover_lawman"
        return string.format('%s_lawman', region_alias)
    end,
    medic = function(region_alias)
        return string.format('%s_medic', region_alias)
    end,
}

-- Region-wide rules text
Config.Rules = {
    MaxLength = 4000,
}

-- Region announcements (broadcasts)
Config.Announcements = {
    MaxLength    = 1000,
    CooldownSecs = 60,
}

--==============================================================
--  Payroll (hourly + overtime, in-game time)
--==============================================================
Config.Payroll = {
    Enabled           = true,

    -- In-game regular hours window (24h)
    RegularStartHour  = 8,    -- 08:00
    RegularEndHour    = 17,   -- 17:00 (5 PM)

    -- Overtime multiplier (applied to hourly pay outside regular hours)
    OvertimeMultiplier = 1.50,

    -- Which jobs are treated as "lawman" vs "medic" for payroll
    -- (we reuse the same lists you already have)
    LawmanJobs = Config.GovFundJobs and Config.GovFundJobs.lawman or {},
    MedicJobs  = Config.GovFundJobs and Config.GovFundJobs.medic  or {},
}

Config.DutyLog = {
    -- What the /dutylog UI should show:
    -- 'unpaid_plus_recent_paid', 'recent_days', 'all', 'unpaid_only'
    Mode = 'unpaid_plus_recent_paid',

    -- Used when Mode = 'recent_days'
    RecentDays = 14,

    -- Used when Mode = 'unpaid_plus_recent_paid'
    MaxPaidHistory = 50,

    -- Optional DB retention (ignored unless you wire cleanup code)
    Retention = {
        Enabled  = false, -- set true if you later add a cleanup job
        KeepDays = 90,
        RunOnStart = false,
    }
}

--============================================================
-- GOVERNOR BANK BRANCHES (Linked to rsg-banking Config)
--============================================================
Config.BankBranches = {
    valbank = {
        id        = 'valbank',
        label     = 'Valentine Bank',
        moneyType = 'valbank',
    },
    rhobank = {
        id        = 'rhobank',
        label     = 'Rhodes Bank',
        moneyType = 'rhobank',
    },
    bank = {
        id        = 'bank',
        label     = 'Saint Denis Bank',
        moneyType = 'bank',
    },
    blkbank = {
        id        = 'blkbank',
        label     = 'Blackwater Bank',
        moneyType = 'blkbank',
    },
    armbank = {
        id        = 'armbank',
        label     = 'Armadillo Bank',
        moneyType = 'armbank',
    },
}


Config.Debug = false
