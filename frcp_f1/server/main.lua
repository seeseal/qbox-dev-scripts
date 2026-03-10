local racers          = {}
local spawnedVehicles = {}
local raceInProgress  = false

-- ============================================================
-- 1. Admin Command
-- ============================================================
lib.addCommand('f1menu', {
    help = 'Open F1 Race Organizer Menu',
}, function(source)
    print("^3[F1]^7 /f1menu used by " .. GetPlayerName(source))
    TriggerClientEvent('frcp_f1:client:openOrganizerMenu', source)
end)

-- ============================================================
-- 2. Grid Setup
-- ============================================================
RegisterNetEvent('frcp_f1:server:setupGrid', function()
    local src           = source
    local organizerPed  = GetPlayerPed(src)
    local organizerPos  = GetEntityCoords(organizerPed)
    local players       = GetActivePlayers()
    local spotIndex     = 1

    -- Clean up any previous race first
    TriggerClientEvent('frcp_f1:client:cleanupCars', -1)
    racers          = {}
    raceInProgress  = false

    for _, playerId in ipairs(players) do
        local ped    = GetPlayerPed(playerId)
        local pos    = GetEntityCoords(ped)

        if #(pos - organizerPos) < 50.0 and Config.GridSpots[spotIndex] then
            local spot = Config.GridSpots[spotIndex]
            TriggerClientEvent('frcp_f1:client:spawnYourCar', playerId, spot)
            racers[tostring(playerId)] = { lap = 1, cp = 1, finished = false }
            spotIndex = spotIndex + 1
        end
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Grid Ready',
        description = string.format('%d driver(s) placed on grid', spotIndex - 1),
        type        = 'success'
    })
end)

-- ============================================================
-- 3. Race Start
-- ============================================================
RegisterNetEvent('frcp_f1:server:startGlobalRace', function()
    if raceInProgress then return end
    raceInProgress = true
    TriggerClientEvent('frcp_f1:client:startRace', -1)
    print("^2[F1]^7 Race started.")
end)

-- ============================================================
-- 4. Progress Tracking
--    FIX: handler was missing entirely; server would throw
--         "no such event" warnings every checkpoint
-- ============================================================
RegisterNetEvent('frcp_f1:server:updateProgress', function(lap, cp)
    local src = tostring(source)
    if racers[src] then
        racers[src].lap = lap
        racers[src].cp  = cp
    end
end)

-- ============================================================
-- 5. DQ
-- ============================================================
RegisterNetEvent('frcp_f1:server:dqPlayer', function(reason)
    local src  = source
    local name = GetPlayerName(src)
    racers[tostring(src)] = nil

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = 'DISQUALIFIED',
        description = name .. " — " .. reason,
        type        = 'error'
    })
    print(string.format("^1[F1]^7 %s DQ'd: %s", name, reason))
end)

-- ============================================================
-- 6. Finish
-- ============================================================
RegisterNetEvent('frcp_f1:server:finishRace', function()
    local src    = source
    local name   = GetPlayerName(src)
    local player = exports.qbx_core:GetPlayer(src)

    if not player then
        print("^1[F1]^7 finishRace: could not find QBX player for src " .. src)
        return
    end

    -- Mark as finished so they don't get paid twice
    if racers[tostring(src)] and racers[tostring(src)].finished then return end
    if racers[tostring(src)] then racers[tostring(src)].finished = true end

    exports.ox_inventory:AddItem(src, 'money', Config.PrizeMoney)

    local firstName = player.PlayerData.charinfo.firstname
    TriggerClientEvent('ox_lib:notify', -1, {
        title       = '🏁 Race Finished',
        description = firstName .. ' crossed the finish line! +$' .. Config.PrizeMoney,
        type        = 'success'
    })

    raceInProgress = false
    print(string.format("^2[F1]^7 %s finished. Prize: $%d", name, Config.PrizeMoney))
end)
