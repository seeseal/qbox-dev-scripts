local spawnedVehicles = {}
local racers = {}

-- 1. Command to open the Admin Organizer Menu
lib.addCommand('f1menu', {
    help = 'Open F1 Race Organizer Menu',
    restricted = 'group.admin'
}, function(source)
    TriggerClientEvent('frcp_f1:client:openOrganizerMenu', source)
end)

-- 2. Setup Grid: Spawns cars and puts nearby players inside them
RegisterNetEvent('frcp_f1:server:setupGrid', function()
    local src = source
    local players = GetActivePlayers()
    local spotIndex = 1

    -- Cleanup old race vehicles
    for _, v in pairs(spawnedVehicles) do
        if DoesEntityExist(v) then DeleteEntity(v) end
    end
    spawnedVehicles = {}
    racers = {}

    local organizerCoords = GetEntityCoords(GetPlayerPed(src))

    for _, playerId in ipairs(players) do
        local ped = GetPlayerPed(playerId)
        local coords = GetEntityCoords(ped)

        -- Only grab players within 50m of the organizer
        if #(coords - organizerCoords) < 50.0 and Config.GridSpots[spotIndex] then
            local spot = Config.GridSpots[spotIndex]
            
            -- Create the Vehicle
            local veh = CreateVehicle(Config.F1CarModel, spot.x, spot.y, spot.z, spot.w, true, true)
            while not DoesEntityExist(veh) do Wait(10) end
            
            table.insert(spawnedVehicles, veh)
            SetPedIntoVehicle(ped, veh, -1)
            
            -- Sync tuning/colors to the specific player
            TriggerClientEvent('frcp_f1:client:prepSpawnedCar', playerId, NetworkGetNetworkIdFromEntity(veh))
            
            spotIndex = spotIndex + 1
        end
    end
    
    TriggerClientEvent('ox_lib:notify', src, {description = 'Grid Prepared Successfully', type = 'success'})
end)

-- 3. Start Race: Triggers the countdown for everyone
RegisterNetEvent('frcp_f1:server:startGlobalRace', function()
    TriggerClientEvent('frcp_f1:client:startRace', -1)
end)

-- 4. Progress Tracker & Leaderboard Logic
RegisterNetEvent('frcp_f1:server:updateProgress', function(lap, checkpoint)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    racers[src] = {
        name = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname,
        lap = lap,
        checkpoint = checkpoint
    }

    -- Sort by Lap, then by Checkpoint
    local list = {}
    for k, v in pairs(racers) do table.insert(list, v) end
    table.sort(list, function(a, b)
        if a.lap ~= b.lap then return a.lap > b.lap end
        return a.checkpoint > b.checkpoint
    end)

    TriggerClientEvent('frcp_f1:client:updateLeaderboard', -1, list)
end)

-- 5. Race Finish & Rewards
RegisterNetEvent('frcp_f1:server:finishRace', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    
    exports.ox_inventory:AddItem(src, 'money', Config.PrizeMoney)
    
    local name = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname
    exports.frcp_webhook:Send(Config.WebhookChannel, 'F1 Grand Prix Winner', name .. " has finished the race and won $" .. Config.PrizeMoney, 5763719)
end)

-- 6. Disqualification Cleanup
RegisterNetEvent('frcp_f1:server:dqPlayer', function(reason)
    local src = source
    racers[src] = nil
    TriggerClientEvent('ox_lib:notify', -1, {description = GetPlayerName(src) .. " was DQ'd: " .. reason, type = 'error'})
end)