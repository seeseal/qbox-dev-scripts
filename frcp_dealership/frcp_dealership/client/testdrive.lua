-- ============================================
--  frcp_dealership | client/testdrive.lua  v2.0
--
--  WHAT THIS FILE DOES (plain English):
--  ─────────────────────────────────────
--  When a salesperson starts a test drive for
--  a customer, THIS file runs on the customer's
--  machine. It:
--
--  1. Spawns a test drive car at Config.TestDriveStart
--  2. Puts the customer in the driver seat
--  3. Shows a countdown timer HUD on screen
--  4. Every second checks:
--     a. Has the timer run out? → End drive
--     b. Is player too far from spawn? → End drive
--  5. When the drive ends (any reason):
--     a. Deletes the test drive car
--     b. Teleports the player back to Config.TestDriveReturn
--     c. Shows a notification with the reason
-- ============================================

local testDriveActive  = false
local testDriveVehicle = nil
local testDriveTimer   = 0

-- ============================================
--  Begin Test Drive (called from server)
-- ============================================

RegisterNetEvent('frcp_dealership:client:beginTestDrive', function(model, duration)
    if testDriveActive then
        lib.notify({ type = 'error', description = 'You already have an active test drive.' })
        return
    end

    local spawnCoord = Config.TestDriveStart
    local vehicleModel = GetHashKey(model)

    RequestModel(vehicleModel)
    while not HasModelLoaded(vehicleModel) do Wait(100) end

    local veh = CreateVehicle(vehicleModel, spawnCoord.x, spawnCoord.y, spawnCoord.z, spawnCoord.w, true, false)
    while not DoesEntityExist(veh) do Wait(100) end

    SetVehicleNumberPlateText(veh, "TEST DRV")

    -- ── Max Performance Mods ─────────────────────────────
    -- Applies full performance upgrades so customers
    -- experience the vehicle at its absolute best.
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, 11, 3, false)   -- Engine      (level 4 = max)
    SetVehicleMod(veh, 12, 3, false)   -- Brakes       (level 4 = max)
    SetVehicleMod(veh, 13, 2, false)   -- Transmission (level 3 = max)
    SetVehicleMod(veh, 15, 2, false)   -- Suspension   (level 3 = max)
    SetVehicleMod(veh, 16, 4, false)   -- Armour       (level 5 = max)
    ToggleVehicleMod(veh, 18, true)    -- Turbo
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleFuelLevel(veh, 100.0)
    -- ─────────────────────────────────────────────────────

    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    SetModelAsNoLongerNeeded(vehicleModel)

    testDriveActive  = true
    testDriveVehicle = veh
    testDriveTimer   = duration

    lib.notify({
        type        = 'inform',
        title       = 'Test Drive Started',
        description = 'You have ' .. tostring(duration / 60) .. ' minutes. Stay within ' .. tostring(Config.TestDriveRadius) .. 'm of the dealership.',
        duration    = 7000
    })

    -- ── Minimap blip marking the return point ──────────────────────────────
    local returnBlip = AddBlipForCoord(
        Config.TestDriveReturn.x,
        Config.TestDriveReturn.y,
        Config.TestDriveReturn.z
    )
    SetBlipSprite(returnBlip, 526)          -- car dealership icon
    SetBlipColour(returnBlip, 5)            -- yellow
    SetBlipScale(returnBlip, 0.8)
    SetBlipAsShortRange(returnBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Return Vehicle Here")
    EndTextCommandSetBlipName(returnBlip)

    -- ── Countdown + boundary check loop ─────────────────────────────────────
    CreateThread(function()
        local warnedBoundary = false
        local warned30       = false

        while testDriveActive and testDriveTimer > 0 do
            Wait(1000)

            -- Boundary check
            local playerPos = GetEntityCoords(PlayerPedId())
            local origin    = Config.TestDriveReturn  -- boundary centred on return point
            local dist      = #(playerPos - vec3(origin.x, origin.y, origin.z))

            if dist > Config.TestDriveRadius then
                if not warnedBoundary then
                    warnedBoundary = true
                    lib.notify({
                        type        = 'error',
                        title       = 'Test Drive — Out of Bounds',
                        description = 'Return to the dealership area immediately!',
                        duration    = 5000
                    })
                end
                -- Give 10 seconds grace after first warning before ending
                Wait(10000)
                local newPos  = GetEntityCoords(PlayerPedId())
                local newDist = #(newPos - vec3(origin.x, origin.y, origin.z))
                if newDist > Config.TestDriveRadius then
                    RemoveBlip(returnBlip)
                    TriggerServerEvent('frcp_dealership:server:endTestDrive', 'out_of_bounds')
                    return
                else
                    warnedBoundary = false  -- they came back, reset warning
                end
            else
                warnedBoundary = false
            end

            -- 30-second warning
            if testDriveTimer == 30 and not warned30 then
                warned30 = true
                lib.notify({
                    type        = 'error',
                    title       = 'Test Drive',
                    description = '30 seconds remaining — head back to FlameDrive!',
                    duration    = 6000
                })
            end

            testDriveTimer = testDriveTimer - 1
        end

        -- Timer ran out
        if testDriveActive then
            RemoveBlip(returnBlip)
            lib.notify({
                type        = 'error',
                title       = 'Test Drive',
                description = 'Time is up! Returning to dealership.',
                duration    = 5000
            })
            TriggerServerEvent('frcp_dealership:server:endTestDrive', 'timer_expired')
        end
    end)

    -- HUD countdown display thread
    CreateThread(function()
        while testDriveActive do
            Wait(0)
            local mins = math.floor(testDriveTimer / 60)
            local secs = testDriveTimer % 60
            local label = string.format("🚗 TEST DRIVE — %d:%02d", mins, secs)
            local colour = testDriveTimer <= 30 and {255, 80, 80, 220} or {255, 255, 255, 220}

            -- Draw text on screen (top centre)
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

    -- ── Exit-vehicle detection ────────────────────────────────────────────────
    -- If the player exits the test drive vehicle at any point, give them
    -- 15 seconds to get back in. If they don't, end the drive and
    -- teleport them back to the dealership automatically.
    CreateThread(function()
        -- Wait until they're actually in the vehicle first
        while testDriveActive and not IsPedInVehicle(PlayerPedId(), testDriveVehicle, false) do
            Wait(500)
        end

        while testDriveActive do
            Wait(1000)

            if testDriveActive and DoesEntityExist(testDriveVehicle) then
                if not IsPedInVehicle(PlayerPedId(), testDriveVehicle, false) then
                    -- Player exited — start grace countdown
                    lib.notify({
                        type        = 'error',
                        title       = 'Test Drive',
                        description = 'Get back in the vehicle! Drive ends in 15 seconds.',
                        duration    = 5000
                    })

                    local graceTimer = 15
                    while testDriveActive and graceTimer > 0 do
                        Wait(1000)
                        graceTimer = graceTimer - 1

                        -- They got back in — cancel end
                        if IsPedInVehicle(PlayerPedId(), testDriveVehicle, false) then
                            lib.notify({
                                type        = 'success',
                                title       = 'Test Drive',
                                description = 'Back in the vehicle. Drive continues.',
                                duration    = 3000
                            })
                            graceTimer = -1  -- signal: they returned
                            break
                        end
                    end

                    if graceTimer == 0 then
                        -- Grace expired, they didn't get back in
                        RemoveBlip(returnBlip)
                        TriggerServerEvent('frcp_dealership:server:endTestDrive', 'exited_vehicle')
                        return
                    end
                end
            end
        end
    end)
end)

-- ============================================
--  Conclude Test Drive (called from server)
-- ============================================

RegisterNetEvent('frcp_dealership:client:concludeTestDrive', function(reason)
    if not testDriveActive then return end

    testDriveActive = false
    -- Note: returnBlip is local to beginTestDrive thread so it auto-cleans
    -- when that thread exits. RemoveBlip is also called in the timer loop above.

    -- Delete the car
    if testDriveVehicle and DoesEntityExist(testDriveVehicle) then
        -- Eject player first
        TaskLeaveVehicle(PlayerPedId(), testDriveVehicle, 0)
        Wait(500)
        DeleteVehicle(testDriveVehicle)
    end
    testDriveVehicle = nil
    testDriveTimer   = 0

    -- Teleport back to dealership
    local returnCoord = Config.TestDriveReturn
    SetEntityCoords(PlayerPedId(), returnCoord.x, returnCoord.y, returnCoord.z, false, false, false, true)

    -- Message based on why it ended
    local messages = {
        timer_expired  = 'Test drive complete! Thank you for visiting FlameDrive Motors.',
        out_of_bounds  = 'Test drive ended — you left the allowed area.',
        staff_ended    = 'Your test drive has been ended by a staff member.',
        exited_vehicle = 'Test drive ended — you left the vehicle.',
        ended          = 'Test drive ended.',
    }

    lib.notify({
        type        = 'inform',
        title       = 'Test Drive Ended',
        description = messages[reason] or messages.ended,
        duration    = 7000
    })
end)

print("^2[frcp_dealership] client/testdrive.lua loaded.^0")
