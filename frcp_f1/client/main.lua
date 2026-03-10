local inRace = false
local currentCheckpoint = 1
local currentLap = 1
local isDQ = false
local leaderboard = {}

-- Function to force identical performance and randomize visuals
function PrepareF1Grid(veh)
    -- 1. Performance Parity (Identical for everyone)
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, 11, 3, false) -- Engine Level 4
    SetVehicleMod(veh, 12, 2, false) -- Brakes Level 3
    SetVehicleMod(veh, 13, 2, false) -- Transmission Level 3
    ToggleVehicleMod(veh, 18, true)  -- Turbo
    SetVehicleFixed(veh)
    
    -- 2. Visual Randomization (Team Colors/Decals)
    -- This ensures players look different but drive the same
    local randomLivery = math.random(0, GetNumVehicleMods(veh, 48) - 1)
    local r, g, b = math.random(0, 255), math.random(0, 255), math.random(0, 255)
    
    SetVehicleMod(veh, 48, randomLivery, false) -- Apply random Decal/Livery
    SetVehicleCustomPrimaryColour(veh, r, g, b) -- Apply random Team Color
    SetVehicleDirtyLevel(veh, 0.0) -- Keep them shiny
    
    -- 3. Physics Injection
    SetVehicleCheatPowerIncrease(veh, 1.4) 
    -- Increase steering lock so tight F1 corners are possible in 1st person
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fSteeringLock', 50.0)
end

-- Main Loop: Logic enforcement
CreateThread(function()
    while true do
        local sleep = 1000
        if inRace then
            sleep = 0
            local ped = cache.ped
            local veh = GetVehiclePedIsIn(ped, false)
            local coords = GetEntityCoords(ped)

            -- 1. NPC & Traffic Clearing
            ClearAreaOfPeds(coords.x, coords.y, coords.z, 200.0, 1)
            ClearAreaOfVehicles(coords.x, coords.y, coords.z, 200.0, false, false, false, false, false)
            
            -- 2. Force First Person
            SetFollowVehicleCamViewMode(4) 
            
            -- 3. Disable Exit Vehicle (Key: F)
            DisableControlAction(0, 75, true) 

            -- 4. Damage & Pathing Check
            if not isDQ then
                if GetVehicleEngineHealth(veh) < Config.MinEngineHealth then
                    Disqualify("ENGINE FAILURE")
                end
                
                local target = Config.Checkpoints[currentCheckpoint]
                if #(coords - target) > 100.0 then
                    Disqualify("OFF TRACK")
                end
            end
        end
        Wait(sleep)
    end
end)

function Disqualify(reason)
    inRace = false
    isDQ = true
    local veh = GetVehiclePedIsIn(cache.ped, false)
    SetVehicleEngineHealth(veh, -1.0)
    lib.notify({title = 'DISQUALIFIED', description = reason, type = 'error'})
    TriggerServerEvent('frcp_f1:server:dqPlayer', reason)
end

-- Race Start Event
RegisterNetEvent('frcp_f1:client:startRace', function()
    local ped = cache.ped
    local veh = GetVehiclePedIsIn(ped, false)

    -- Strict Model Check: Only the BR8 is allowed for the Pro experience
    if not veh or GetEntityModel(veh) ~= `br8` then
        lib.notify({
            title = 'Race Control',
            description = 'You must be in a Benefactor BR8 to participate!',
            type = 'error'
        })
        return
    end

    -- Apply the "Fair Play" visuals and performance
    PrepareF1Grid(veh)

    inRace = true
    isDQ = false
    currentCheckpoint = 1
    currentLap = 1

    FreezeEntityPosition(veh, true)
    SetVehicleDoorsLocked(veh, 4)

    -- Countdown
    for i = 5, 1, -1 do
        lib.showTextUI('**RACE STARTING IN: ' .. i .. '**', {position = 'top-center'})
        PlaySoundFrontend(-1, "CHECKPOINT_AHEAD", "HUD_MINI_GAME_SOUNDSET", true)
        Wait(1000)
    end
    lib.hideTextUI()
    
    FreezeEntityPosition(veh, false)
    TriggerServerEvent('frcp_f1:server:updateProgress', currentLap, currentCheckpoint)
    SpawnCheckpoint()
end)

function SpawnCheckpoint()
    if currentCheckpoint > #Config.Checkpoints then
        currentLap = currentLap + 1
        currentCheckpoint = 1
    end

    if currentLap > Config.MaxLaps then
        inRace = false
        lib.hideTextUI()
        TriggerServerEvent('frcp_f1:server:finishRace')
        return
    end

    local coords = Config.Checkpoints[currentCheckpoint]
    -- Tracker Loop
    CreateThread(function()
        while inRace and not isDQ do
            Wait(0)
            DrawMarker(27, coords.x, coords.y, coords.z - 0.9, 0, 0, 0, 0, 0, 0, 10.0, 10.0, 1.0, 0, 150, 255, 100, false, false, 2, false, nil, nil, false)
            if #(GetEntityCoords(cache.ped) - coords) < 12.0 then
                currentCheckpoint = currentCheckpoint + 1
                TriggerServerEvent('frcp_f1:server:updateProgress', currentLap, currentCheckpoint)
                SpawnCheckpoint()
                break
            end
        end
    end)
end

RegisterNetEvent('frcp_f1:client:updateLeaderboard', function(list)
    if not inRace then return end
    local text = "**LEADERBOARD**\n"
    for i, data in ipairs(list) do
        text = text .. i .. ". " .. data.name .. " (Lap " .. data.lap .. ")\n"
    end
    lib.showTextUI(text, {position = 'right-center'})
end)

-- Organizer Menu
RegisterNetEvent('frcp_f1:client:openOrganizerMenu', function()
    lib.registerContext({
        id = 'f1_organizer_menu',
        title = 'F1 Race Management',
        options = {
            {
                title = '1. Prepare Grid',
                description = 'Spawn BR8s for everyone nearby and align them',
                icon = 'car-side',
                onSelect = function()
                    TriggerServerEvent('frcp_f1:server:setupGrid')
                end
            },
            {
                title = '2. Start Countdown',
                description = 'Begin the 5-second countdown for all drivers',
                icon = 'flag-checkered',
                onSelect = function()
                    TriggerServerEvent('frcp_f1:server:startGlobalRace') -- You'll add this to server.lua
                end
            }
        }
    })
    lib.showContext('f1_organizer_menu')
end)

-- Preps the car once the server spawns it
RegisterNetEvent('frcp_f1:client:prepSpawnedCar', function(netId)
    local timeout = 0
    while not NetworkDoesEntityExistWithNetworkId(netId) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    local veh = NetToVeh(netId)
    if DoesEntityExist(veh) then
        PrepareF1Grid(veh) -- Uses our previous Tuning/Color function
        FreezeEntityPosition(veh, true) -- Lock them until race start
        SetVehicleDoorsLocked(veh, 4)
    end
end)