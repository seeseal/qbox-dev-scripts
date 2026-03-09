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

    -- Start the countdown + boundary loop
    CreateThread(function()
        while testDriveActive and testDriveTimer > 0 do
            Wait(1000)

            -- Boundary check
            local playerPos = GetEntityCoords(PlayerPedId())
            local origin    = Config.TestDriveStart
            local dist      = #(playerPos - vec3(origin.x, origin.y, origin.z))

            if dist > Config.TestDriveRadius then
                lib.notify({
                    type        = 'error',
                    title       = 'Test Drive',
                    description = 'You have gone too far! Returning to dealership.',
                    duration    = 5000
                })
                TriggerServerEvent('frcp_dealership:server:endTestDrive', 'out_of_bounds')
                return
            end

            testDriveTimer = testDriveTimer - 1
        end

        -- Timer ran out
        if testDriveActive then
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
end)

-- ============================================
--  Conclude Test Drive (called from server)
-- ============================================

RegisterNetEvent('frcp_dealership:client:concludeTestDrive', function(reason)
    if not testDriveActive then return end

    testDriveActive = false

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
        timer_expired = 'Test drive complete! Thank you for visiting FlameDrive Motors.',
        out_of_bounds = 'Test drive ended — you left the allowed area.',
        staff_ended   = 'Your test drive has been ended by a staff member.',
        ended         = 'Test drive ended.',
    }

    lib.notify({
        type        = 'inform',
        title       = 'Test Drive Ended',
        description = messages[reason] or messages.ended,
        duration    = 7000
    })
end)

print("^2[frcp_dealership] client/testdrive.lua loaded.^0")
