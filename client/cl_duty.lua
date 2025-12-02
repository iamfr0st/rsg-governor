function getInGameClock()
    -- RedM clock wrappers.
    -- GetClockMonth() returns 0–11, so +1 to get 1–12 for normal months.
    local year   = GetClockYear() or 1898
    local month  = (GetClockMonth() or 0) + 1
    local day    = GetClockDayOfMonth() or 1
    local hour   = GetClockHours() or 0
    local minute = GetClockMinutes() or 0

    return {
        year   = year,
        month  = month,
        day    = day,
        hour   = hour,
        minute = minute,
    }
end


-- Called by RSGCore when your duty state changes
RegisterNetEvent('RSGCore:Client:SetDuty', function(isOnDuty)
    local clock = getInGameClock()
    TriggerServerEvent('rsg-governor:server:duty:updateClock', clock, isOnDuty)
end)