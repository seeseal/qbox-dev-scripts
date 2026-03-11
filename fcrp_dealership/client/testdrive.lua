-- ============================================
--  fcrp_dealership | client/testdrive.lua  v2.3
--
--  Changes from v2.0 -> v2.3:
--  • [FIX] Timer-end active flag bug — testDriveActive
--    is now set false BEFORE TriggerServerEvent so
--    players can start a new drive immediately.
--  • [FIX] HUD car emoji removed — caused rendering
--    issues on some clients. Plain text only.
--  • [FEAT] Catalogue UI auto-closes on test drive start.
--  • [FEAT] Death detection — drive ends if player dies.
--  • [FEAT] Engine health detection — drive ends if
--    vehicle engine health reaches 0.
-- ============================================

local testDriveActive     = false
local testDriveVehicle    = nil
local testDriveTimer      = 0
local testDriveReturnBlip = nil

-- ============================================
--  Begin Test Drive (called from server)
-- ============================================

RegisterNetEvent('fcrp_dealership:client:beginTestDrive', function(model, duration)
    if testDriveActive then
        lib.notify({ type = 'error', description = 'You already have an active test drive.' })
        return
    end

    -- [FEAT] Auto-close catalogue UI if open
    SendNUIMessage({ action = 'closeUI' })
    SetNuiFocus(false, false)

    local spawnCoord   = Config.TestDriveStart
    local vehicleModel = GetHashKey(model)

    RequestModel(vehicleModel)

    -- [FIX #2] Model load timeout — 50 × 100ms = 5 seconds max
    local loadTimeout = 0
    while not HasModelLoaded(vehicleModel) and loadTimeout < 50 do
        Wait(100)
        loadTimeout = loadTimeout + 1
    end

    if not HasModelLoaded(vehicleModel) then
        SetModelAsNoLongerNeeded(vehicleModel)
        lib.notify({
            type        = 'error',
            title       = 'Test Drive',
            description = 'Vehicle could not be spawned (model failed to load). Contact an admin.',
            duration    = 7000
        })
        return
    end

    local veh = CreateVehicle(vehicleModel, spawnCoord.x, spawnCoord.y, spawnCoord.z, spawnCoord.w, true, false)

    -- [FIX #2] Entity creation timeout — 30 × 100ms = 3 seconds max
    local entityTimeout = 0
    while not DoesEntityExist(veh) and entityTimeout < 30 do
        Wait(100)
        entityTimeout = entityTimeout + 1
    end

    if not DoesEntityExist(veh) then
        SetModelAsNoLongerNeeded(vehicleModel)
        lib.notify({
            type        = 'error',
            title       = 'Test Drive',
            description = 'Vehicle entity failed to create. Contact an admin.',
            duration    = 7000
        })
        return
    end

    SetVehicleNumberPlateText(veh, "TEST DRV")

    -- Max Performance Mods
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, 11, 3, false)   -- Engine
    SetVehicleMod(veh, 12, 3, false)   -- Brakes
    SetVehicleMod(veh, 13, 2, false)   -- Transmission
    SetVehicleMod(veh, 15, 2, false)   -- Suspension
    SetVehicleMod(veh, 16, 4, false)   -- Armour
    ToggleVehicleMod(veh, 18, true)    -- Turbo
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleFuelLevel(veh, 100.0)

    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    SetModelAsNoLongerNeeded(vehicleModel)

    testDriveActive  = true
    testDriveVehicle = veh
    testDriveTimer   = duration

    lib.notify({
        type        = 'inform',
        title       = 'Test Drive Started',
        description = 'You have ' .. tostring(math.floor(duration / 60)) .. ' minutes. Stay within ' .. tostring(Config.TestDriveRadius) .. 'm of the dealership.',
        duration    = 7000
    })

    -- Return-point minimap blip
    testDriveReturnBlip = AddBlipForCoord(Config.TestDriveReturn.x, Config.TestDriveReturn.y, Config.TestDriveReturn.z)
    SetBlipSprite(testDriveReturnBlip, 526)
    SetBlipColour(testDriveReturnBlip, 5)
    SetBlipScale(testDriveReturnBlip, 0.8)
    SetBlipAsShortRange(testDriveReturnBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Return Vehicle Here")
    EndTextCommandSetBlipName(testDriveReturnBlip)

    -- ============================================================
    --  Main loop: countdown + boundary + death + engine checks
    -- ============================================================
    CreateThread(function()
        local warnedBoundary = false
        local warned30       = false

        while testDriveActive and testDriveTimer > 0 do
            Wait(1000)

            local ped = PlayerPedId()

            -- [FEAT] Death detection
            if IsEntityDead(ped) then
                testDriveActive = false  -- set false BEFORE server event
                RemoveBlip(testDriveReturnBlip)
                TriggerServerEvent('fcrp_dealership:server:endTestDrive', 'player_died')
                return
            end

            -- [FEAT] Engine health — ends drive if engine is destroyed
            if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
                if GetVehicleEngineHealth(testDriveVehicle) <= 0 then
                    testDriveActive = false
                    RemoveBlip(testDriveReturnBlip)
                    TriggerServerEvent('fcrp_dealership:server:endTestDrive', 'vehicle_destroyed')
                    return
                end
            end

            -- Boundary check
            local origin = Config.TestDriveReturn
            local dist   = #(GetEntityCoords(ped) - vec3(origin.x, origin.y, origin.z))

            if dist > Config.TestDriveRadius then
                if not warnedBoundary then
                    warnedBoundary = true
                    lib.notify({
                        type = 'error', title = 'Test Drive - Out of Bounds',
                        description = 'Return to the dealership area immediately!',
                        duration = 5000
                    })
                end
                Wait(10000)
                local newDist = #(GetEntityCoords(PlayerPedId()) - vec3(origin.x, origin.y, origin.z))
                if newDist > Config.TestDriveRadius then
                    testDriveActive = false
                    RemoveBlip(testDriveReturnBlip)
                    TriggerServerEvent('fcrp_dealership:server:endTestDrive', 'out_of_bounds')
                    return
                else
                    warnedBoundary = false
                end
            else
                warnedBoundary = false
            end

            -- 30-second warning (use <= not == to survive loop timing drift)
            if testDriveTimer <= 30 and not warned30 then
                warned30 = true
                lib.notify({
                    type = 'error', title = 'Test Drive',
                    description = '30 seconds remaining — head back to FlameDrive!',
                    duration = 6000
                })
            end

            testDriveTimer = testDriveTimer - 1
        end

        -- [FIX] Timer-end active flag bug:
        -- Set testDriveActive = false HERE, before firing server event.
        -- Old code left it true until concludeTestDrive returned from the server,
        -- blocking any new drive attempt in that round-trip window.
        if testDriveActive then
            testDriveActive = false
            RemoveBlip(testDriveReturnBlip)
            lib.notify({
                type = 'error', title = 'Test Drive',
                description = 'Time is up! Returning to dealership.',
                duration = 5000
            })
            TriggerServerEvent('fcrp_dealership:server:endTestDrive', 'timer_expired')
        end
    end)

    -- ============================================================
    --  HUD countdown thread
    --  [FIX] Removed car emoji (was causing font issues on some
    --  clients). Plain text renders correctly on all machines.
    -- ============================================================
    CreateThread(function()
        while testDriveActive do
            Wait(0)
            local mins   = math.floor(testDriveTimer / 60)
            local secs   = testDriveTimer % 60
            local label  = string.format("TEST DRIVE  %d:%02d", mins, secs)
            local colour = testDriveTimer <= 30 and {255, 80, 80, 220} or {255, 255, 255, 220}

            SetTextFont(4)
            SetTextScale(0.5, 0.5)
            SetTextColour(colour[1], colour[2], colour[3], colour[4])
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName(label)
            EndTextCommandDisplayText(0.5, 0.03)
        end
    end)

    -- ============================================================
    --  Exit-vehicle grace period thread
    -- ============================================================
    CreateThread(function()
        -- Wait until actually seated first
        while testDriveActive and not IsPedInVehicle(PlayerPedId(), testDriveVehicle, false) do
            Wait(500)
        end

        while testDriveActive do
            Wait(1000)

            if not testDriveActive then break end

            if DoesEntityExist(testDriveVehicle) and not IsPedInVehicle(PlayerPedId(), testDriveVehicle, false) then
                lib.notify({
                    type = 'error', title = 'Test Drive',
                    description = 'Get back in the vehicle! Drive ends in 15 seconds.',
                    duration = 5000
                })

                local graceTimer = 15
                while testDriveActive and graceTimer > 0 do
                    Wait(1000)
                    graceTimer = graceTimer - 1
                    if IsPedInVehicle(PlayerPedId(), testDriveVehicle, false) then
                        lib.notify({
                            type = 'success', title = 'Test Drive',
                            description = 'Back in the vehicle. Drive continues.',
                            duration = 3000
                        })
                        graceTimer = -1
                        break
                    end
                end

                if graceTimer == 0 then
                    testDriveActive = false
                    RemoveBlip(testDriveReturnBlip)
                    TriggerServerEvent('fcrp_dealership:server:endTestDrive', 'exited_vehicle')
                    return
                end
            end
        end
    end)
end)

-- ============================================
--  Conclude Test Drive (called from server)
-- ============================================

RegisterNetEvent('fcrp_dealership:client:concludeTestDrive', function(reason)
    -- testDriveActive may already be false (set client-side before the server
    -- round-trip for timer_expired, death, engine, etc). Still run full cleanup.
    testDriveActive = false

    if testDriveReturnBlip then
        RemoveBlip(testDriveReturnBlip)
        testDriveReturnBlip = nil
    end

    if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
        local ped = PlayerPedId()

        -- [FIX #12] Only issue TaskLeaveVehicle if the ped is actually seated.
        -- If they are dead/ragdolling, TaskLeaveVehicle silently fails and the
        -- vehicle deletion orphans the ped mid-air on teleport.
        if IsPedInVehicle(ped, testDriveVehicle, false) then
            TaskLeaveVehicle(ped, testDriveVehicle, 0)
            -- Wait up to 2s for the ped to physically exit, then force-delete regardless
            local exitWait = 0
            while IsPedInVehicle(ped, testDriveVehicle, false) and exitWait < 20 do
                Wait(100)
                exitWait = exitWait + 1
            end
        end

        DeleteVehicle(testDriveVehicle)
    end
    testDriveVehicle = nil
    testDriveTimer   = 0

    -- [FIX #12] Only teleport the player if they are alive.
    -- A dead ped will respawn at the hospital via normal game flow;
    -- force-teleporting a dead ped causes a visual glitch.
    local returnCoord = Config.TestDriveReturn
    if not IsEntityDead(PlayerPedId()) then
        SetEntityCoords(PlayerPedId(), returnCoord.x, returnCoord.y, returnCoord.z, false, false, false, true)
    end

    local messages = {
        timer_expired     = 'Test drive complete! Thank you for visiting FlameDrive Motors.',
        out_of_bounds     = 'Test drive ended — you left the allowed area.',
        staff_ended       = 'Your test drive has been ended by a staff member.',
        exited_vehicle    = 'Test drive ended — you left the vehicle.',
        player_died       = 'Test drive ended — you were killed.',
        vehicle_destroyed = 'Test drive ended — the vehicle was destroyed.',
        ended             = 'Test drive ended.',
    }

    lib.notify({
        type        = 'inform',
        title       = 'Test Drive Ended',
        description = messages[reason] or messages.ended,
        duration    = 7000
    })
end)

print("^2[fcrp_dealership] client/testdrive.lua loaded.^0")
