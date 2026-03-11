-- ============================================
--  fcrp_dealership | client/showroom.lua  v2.3
--
--  Changes from v2.0 -> v2.3:
--  • [FEAT] Spot 1 (index 1) rotates 360° continuously
--    — acts as the "podium" car. Rotation is purely
--    client-side via SetEntityHeading in a dedicated
--    thread; the vehicle stays frozen in place.
--  • [FIX] Podium car despawn bug — updateDisplay event
--    called removeDisplayVehicle then immediately called
--    spawnDisplayVehicle with only a Wait(300) between
--    them. If the delete + network sync hadn't finished,
--    the new vehicle spawned on top of the old one causing
--    flickering. Fixed with a reliable DoesEntityExist
--    confirm loop before spawning the replacement.
--  • [FIX] Rotation thread leak — stopRotation flag is
--    stored per-spot so the old thread halts cleanly when
--    a display vehicle is replaced.
-- ============================================

local displayVehicles  = {}
local stopRotation     = {}   -- stopRotation[spotIndex] = true to kill rotation thread

-- ============================================
--  Rotation thread for the podium spot (index 1)
-- ============================================

local PODIUM_SPOT       = 1
local ROTATION_SPEED    = 0.4   -- degrees per frame at 60fps (~24 deg/sec, full rotation ~15s)

local function startRotation(spotIndex, veh)
    stopRotation[spotIndex] = false
    CreateThread(function()
        while not stopRotation[spotIndex] do
            Wait(0)
            -- Re-check entity still exists each frame in case of external deletion
            if not DoesEntityExist(veh) or stopRotation[spotIndex] then break end
            local heading = GetEntityHeading(veh)
            SetEntityHeading(veh, (heading + ROTATION_SPEED) % 360.0)
        end
    end)
end

-- ============================================
--  Spawn a single display vehicle
-- ============================================

local function spawnDisplayVehicle(spotIndex, model)
    local spot = Config.DisplaySpots[spotIndex]
    if not spot then return end

    local c    = spot.coords
    local hash = GetHashKey(model)

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    if not HasModelLoaded(hash) then
        print("^3[fcrp_dealership] Display spot " .. spotIndex .. ": model '" .. model .. "' failed to load^0")
        SetModelAsNoLongerNeeded(hash)
        return
    end

    local veh = CreateVehicle(hash, c.x, c.y, c.z, c.w, false, false)
    local waitCount = 0
    while not DoesEntityExist(veh) and waitCount < 30 do
        Wait(100)
        waitCount = waitCount + 1
    end

    if not DoesEntityExist(veh) then
        SetModelAsNoLongerNeeded(hash)
        return
    end

    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    FreezeEntityPosition(veh, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleLights(veh, 0)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetModelAsNoLongerNeeded(hash)

    displayVehicles[spotIndex] = veh

    -- [FEAT] Start continuous rotation for the podium spot
    if spotIndex == PODIUM_SPOT then
        startRotation(spotIndex, veh)
    end
end

-- ============================================
--  Remove a display vehicle cleanly
-- ============================================

local function removeDisplayVehicle(spotIndex)
    -- [FIX] Stop any running rotation thread for this spot first
    stopRotation[spotIndex] = true

    local veh = displayVehicles[spotIndex]
    if veh and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, false, true)
        DeleteVehicle(veh)
    end
    displayVehicles[spotIndex] = nil
end

-- ============================================
--  Replace a display vehicle safely
--  [FIX] Waits for the old entity to be fully
--  deleted before spawning the new one, preventing
--  the double-spawn / flickering bug.
-- ============================================

local function replaceDisplayVehicle(spotIndex, model)
    local oldVeh = displayVehicles[spotIndex]

    -- Signal rotation thread to stop, then delete
    removeDisplayVehicle(spotIndex)

    -- [FIX] Confirm old vehicle is gone before spawning replacement.
    -- Without this confirmation, CreateVehicle runs while the old entity
    -- is still in the world, causing overlap and flickering.
    if oldVeh then
        local safetyCount = 0
        while DoesEntityExist(oldVeh) and safetyCount < 20 do
            Wait(100)
            safetyCount = safetyCount + 1
        end
    end

    spawnDisplayVehicle(spotIndex, model)
end

-- ============================================
--  Spawn display vehicles from a model table
--  Called directly by client/main.lua's
--  receiveDisplayModels handler so there is only
--  ONE RegisterNetEvent for that event name.
--  [FIX #13] Removed the duplicate RegisterNetEvent
--  here — having two handlers for the same event
--  caused both to fire, deleting and re-spawning
--  all display cars twice on every load/respawn.
-- ============================================

function ShowroomSpawnAll(models)
    for i in pairs(displayVehicles) do
        removeDisplayVehicle(i)
    end

    for spotIndex, model in pairs(models) do
        if Config.DisplaySpots[spotIndex] and model and model ~= '' then
            CreateThread(function()
                Wait(spotIndex * 200)
                spawnDisplayVehicle(spotIndex, model)
            end)
        end
    end
end

-- ============================================
--  Live update — one spot changed
--  [FIX] Uses replaceDisplayVehicle which waits
--  for the old vehicle to be fully deleted before
--  spawning the new one.
-- ============================================

RegisterNetEvent('fcrp_dealership:client:updateDisplay', function(spotIndex, model)
    -- Run in a thread since replaceDisplayVehicle yields
    CreateThread(function()
        replaceDisplayVehicle(spotIndex, model)
        lib.notify({
            type        = 'inform',
            title       = 'Showroom',
            description = 'Display vehicle updated.',
            duration    = 3000
        })
    end)
end)

-- ============================================
--  Initial load retry loop
-- ============================================

CreateThread(function()
    Wait(2000)
    local attempts = 0
    while next(displayVehicles) == nil and attempts < 10 do
        TriggerServerEvent('fcrp_dealership:server:getDisplayModels')
        Wait(3000)
        attempts = attempts + 1
    end
end)

print("^2[fcrp_dealership] client/showroom.lua loaded.^0")
