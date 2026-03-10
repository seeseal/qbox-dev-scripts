local myRaceCar  = nil
local isRacing   = false
local currentLap = 1
local currentCP  = 1
local currentBlip = nil

-- ============================================================
-- 1. ORGANIZER MENU
-- ============================================================
RegisterNetEvent('frcp_f1:client:openOrganizerMenu', function()
    lib.registerContext({
        id    = 'f1_menu',
        title = 'Flame City GP Control',
        options = {
            {
                title       = '1. Prepare Grid',
                description = 'Teleport players into F1 cars',
                icon        = 'car-side',
                onSelect    = function() TriggerServerEvent('frcp_f1:server:setupGrid') end
            },
            {
                title       = '2. START RACE',
                description = 'Lights out and away we go!',
                icon        = 'flag-checkered',
                onSelect    = function() TriggerServerEvent('frcp_f1:server:startGlobalRace') end
            }
        }
    })
    lib.showContext('f1_menu')
end)

-- ============================================================
-- 2. PHYSICS
-- ============================================================
local function ApplyF1Handling(veh)
    SetVehicleModKit(veh, 0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce',        1.85)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia',             1.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveBiasFront',           0.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fLowSpeedTractionLossMult', 2.8)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDragCoeff',         25.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax',         4.8)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin',         2.6)
    ModifyVehicleTopSpeed(veh, 60.0)
end

-- ============================================================
-- 3. FORZA-STYLE RACING LINE
-- ============================================================
local function DrawRacingLine(pCoords, target)
    if #(pCoords - target) > 120.0 then return end

    local segments = 12
    -- +180 because DrawMarker type-24 faces away from player by default
    local heading = math.deg(math.atan(target.x - pCoords.x, target.y - pCoords.y)) + 180.0

    for i = 1, segments do
        local frac = i / segments
        local x = pCoords.x + (target.x - pCoords.x) * frac
        local y = pCoords.y + (target.y - pCoords.y) * frac

        local found, gz = GetGroundZFor_3dCoord(x, y, pCoords.z + 10.0, false)
        local z = found and (gz - 0.1) or (pCoords.z - 0.3)

        local alpha = math.floor(220 * (1.0 - frac * 0.6))

        DrawMarker(24, x, y, z,
            0.0, 0.0, 0.0,
            0.0, 0.0, heading,
            0.9, 0.9, 0.9,
            0, 210, 255, alpha,
            false, false, 2, nil, nil, false)
    end
end

-- ============================================================
-- 4. LAP HUD
-- ============================================================
local function DrawRaceHUD(lap, maxLaps, cp, totalCPs)
    SetTextFont(4)
    SetTextScale(0.0, 0.50)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(string.format("LAP  %d / %d", lap, maxLaps))
    DrawText(0.82, 0.88)

    SetTextFont(0)
    SetTextScale(0.0, 0.32)
    SetTextColour(160, 210, 255, 200)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(string.format("Checkpoint  %d / %d", cp, totalCPs))
    DrawText(0.82, 0.915)
end

-- ============================================================
-- 5. GPS — checkpoint-to-checkpoint
--
--    SetNewWaypoint(x, y) tells GTA's GPS to pathfind along the
--    road network to that point, drawing the coloured route line
--    on the minimap exactly like a mission waypoint.
--    We combine it with a blip so the dot appears on the map too.
-- ============================================================
local function UpdateRaceWaypoint(coords)
    if currentBlip and DoesBlipExist(currentBlip) then
        RemoveBlip(currentBlip)
    end

    currentBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(currentBlip, 38)           -- Checkpoint ring icon
    SetBlipColour(currentBlip, 5)            -- Yellow
    SetBlipScale(currentBlip, 0.85)
    SetBlipAsShortRange(currentBlip, false)  -- Always visible on minimap
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Next Checkpoint")
    EndTextCommandSetBlipName(currentBlip)

    -- This is the key call: makes the GPS draw a road-following route line
    SetNewWaypoint(coords.x, coords.y)
end

local function ClearWaypoint()
    if currentBlip and DoesBlipExist(currentBlip) then
        RemoveBlip(currentBlip)
    end
    currentBlip = nil
    SetWaypointOff()
end

-- ============================================================
-- 6. F1 STARTING LIGHTS  (own thread — doesn't block net events)
-- ============================================================
local countdownDone = false

local function F1Countdown()
    countdownDone = false
    CreateThread(function()
        local lights = {
            {m = "● ○ ○ ○ ○", c = "#7a0000"},
            {m = "● ● ○ ○ ○", c = "#a00000"},
            {m = "● ● ● ○ ○", c = "#c80000"},
            {m = "● ● ● ● ○", c = "#e00000"},
            {m = "● ● ● ● ●", c = "#ff0000"},
        }
        for _, light in ipairs(lights) do
            lib.showTextUI(light.m, {
                position = "top-center",
                style    = {backgroundColor = light.c, color = 'white',
                            fontSize = '48px', fontWeight = 'bold',
                            padding = '10px 28px', letterSpacing = '6px'}
            })
            PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", 1)
            Wait(900)
        end
        lib.hideTextUI()
        Wait(math.random(400, 900)) -- Random lights-out like real F1
        lib.showTextUI("GO GO GO!", {
            position = "top-center",
            style    = {backgroundColor = "#00cc44", color = 'white',
                        fontSize = '54px', fontWeight = 'bold', padding = '10px 28px'}
        })
        PlaySoundFrontend(-1, "CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", 1)
        Wait(1200)
        lib.hideTextUI()
        countdownDone = true
    end)
    while not countdownDone do Wait(100) end
end

-- ============================================================
-- 7. SPAWN & CLEANUP
-- ============================================================
RegisterNetEvent('frcp_f1:client:spawnYourCar', function(spot)
    local model = Config.F1CarModel
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    myRaceCar = CreateVehicle(model, spot.x, spot.y, spot.z, spot.w, true, false)
    ApplyF1Handling(myRaceCar)

    local plate = GetVehicleNumberPlateText(myRaceCar)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    SetPedIntoVehicle(cache.ped, myRaceCar, -1)

    FreezeEntityPosition(myRaceCar, true)
    SetVehicleDoorsLocked(myRaceCar, 4)
    SetVehicleEngineOn(myRaceCar, false, true, false)
end)

RegisterNetEvent('frcp_f1:client:cleanupCars', function()
    ClearWaypoint()
    isRacing   = false
    currentLap = 1
    currentCP  = 1
    if myRaceCar and DoesEntityExist(myRaceCar) then
        DeleteEntity(myRaceCar)
    end
    myRaceCar = nil
end)

-- ============================================================
-- 8. MAIN RACE LOOP
-- ============================================================
RegisterNetEvent('frcp_f1:client:startRace', function()
    if not myRaceCar then return end
    if isRacing then return end

    currentLap = 1
    currentCP  = 1

    if not Config.Checkpoints or #Config.Checkpoints == 0 then
        lib.notify({title = 'Race Error', description = 'No checkpoints in Config!', type = 'error'})
        return
    end

    F1Countdown()

    FreezeEntityPosition(myRaceCar, false)
    SetVehicleEngineOn(myRaceCar, true, false, false)
    SetVehicleDoorsLocked(myRaceCar, 1)
    isRacing = true

    -- Point GPS at first checkpoint immediately after lights out
    UpdateRaceWaypoint(Config.Checkpoints[currentCP])

    CreateThread(function()
        while isRacing do
            local ped    = cache.ped
            local coords = GetEntityCoords(ped)

            -- ── DQ ───────────────────────────────────────────────────
            if not IsPedInVehicle(ped, myRaceCar, false) then
                isRacing = false
                ClearWaypoint()
                if DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
                myRaceCar = nil
                SetEntityCoords(ped,
                    Config.DQLocation.x, Config.DQLocation.y, Config.DQLocation.z,
                    false, false, false, false)
                TriggerServerEvent('frcp_f1:server:dqPlayer', "Player left vehicle")
                lib.notify({title = 'DISQUALIFIED', description = 'You left the vehicle!', type = 'error'})
                break
            end

            -- ── Nil guard ────────────────────────────────────────────
            local target = Config.Checkpoints[currentCP]
            if not target then isRacing = false; break end

            -- ── HUD & racing line ────────────────────────────────────
            DrawRaceHUD(currentLap, Config.MaxLaps, currentCP, #Config.Checkpoints)
            DrawRacingLine(coords, target)

            -- ── Checkpoint marker (within 200 m) ─────────────────────
            if #(coords - target) < 200.0 then
                local isStartFinish = (currentCP == 1)

                if isStartFinish then
                    -- Marker 4: checkered-flag cylinder for the Start / Finish line
                    DrawMarker(
                        4,
                        target.x, target.y, target.z,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        5.0, 5.0, 5.0,
                        255, 255, 255, 200,
                        false, false, 2, nil, nil, false)
                    -- Red glow ring at ground level to emphasise S/F
                    DrawMarker(
                        1,
                        target.x, target.y, target.z + 0.05,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        7.0, 7.0, 0.4,
                        255, 40, 40, 100,
                        false, false, 2, nil, nil, false)
                else
                    -- Marker 1: flat circle for all regular checkpoints
                    DrawMarker(
                        1,
                        target.x, target.y, target.z + 0.05,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        5.0, 5.0, 1.2,
                        0, 180, 255, 160,
                        false, false, 2, nil, nil, false)
                end
            end

            -- ── Checkpoint trigger ───────────────────────────────────
            if #(coords - target) < 15.0 then
                PlaySoundFrontend(-1, "CHECKPOINT_BEAT", "HUD_MINI_GAME_SOUNDSET", 1)

                if currentCP < #Config.Checkpoints then
                    currentCP = currentCP + 1
                else
                    currentCP  = 1
                    currentLap = currentLap + 1

                    if currentLap > Config.MaxLaps then
                        isRacing = false
                        ClearWaypoint()
                        TriggerServerEvent('frcp_f1:server:finishRace')
                        lib.notify({title = '🏁 RACE FINISHED', description = 'You crossed the finish line!', type = 'success'})
                        break
                    else
                        lib.notify({
                            title       = string.format('LAP %d COMPLETE', currentLap - 1),
                            description = string.format('%d lap(s) remaining', Config.MaxLaps - (currentLap - 1)),
                            type        = 'inform'
                        })
                    end
                end

                -- GPS hops to the next checkpoint along the road network
                UpdateRaceWaypoint(Config.Checkpoints[currentCP])
                TriggerServerEvent('frcp_f1:server:updateProgress', currentLap, currentCP)
            end

            Wait(0)
        end
    end)
end)
