lib.locale()

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

local dutyHeartbeatActive = false

local function startDutyHeartbeat()
    if dutyHeartbeatActive then return end
    dutyHeartbeatActive = true

    CreateThread(function()
        while dutyHeartbeatActive do
            Wait(60000) -- every 60 seconds (real time); adjust if you want finer updates

            local clock = getInGameClock()
            -- Keep the server's dutyClock[src].lastClock fresh while on duty
            TriggerServerEvent('rsg-governor:server:duty:recordClock', clock, true)
        end
    end)
end

local function stopDutyHeartbeat()
    dutyHeartbeatActive = false
end

-- Called by RSGCore when your duty state changes
RegisterNetEvent('RSGCore:Client:SetDuty', function(isOnDuty)
    local clock = getInGameClock()
    TriggerServerEvent('rsg-governor:server:duty:updateClock', clock, isOnDuty)

    if isOnDuty then
        startDutyHeartbeat()
    else
        stopDutyHeartbeat()
    end
end)
