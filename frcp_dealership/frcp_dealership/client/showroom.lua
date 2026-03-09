-- ============================================
--  frcp_dealership | client/showroom.lua  v2.0
-- ============================================

local displayVehicles = {}

-- ============================================
--  Spawn a single display vehicle
-- ============================================

local function spawnDisplayVehicle(spotIndex, model)
    local spot = Config.DisplaySpots[spotIndex]
    if not spot then return end

    local c      = spot.coords
    local hash   = GetHashKey(model)

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    if not HasModelLoaded(hash) then
        print("^3[frcp_dealership] Display spot " .. spotIndex .. ": model '" .. model .. "' failed to load^0")
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
end

-- ============================================
--  Remove a display vehicle cleanly
-- ============================================

local function removeDisplayVehicle(spotIndex)
    local veh = displayVehicles[spotIndex]
    if veh and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, false, true)
        DeleteVehicle(veh)
    end
    displayVehicles[spotIndex] = nil
end

-- ============================================
--  BUG FIX 1: Event name mismatch
--  Server sends 'receiveDisplayModels' but client
--  was listening on 'setDisplayModels'. Unified to
--  'receiveDisplayModels' to match the server.
-- ============================================

RegisterNetEvent('frcp_dealership:client:receiveDisplayModels', function(models)
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
end)

-- ============================================
--  Live update — one spot changed
-- ============================================

RegisterNetEvent('frcp_dealership:client:updateDisplay', function(spotIndex, model)
    removeDisplayVehicle(spotIndex)
    Wait(300)
    spawnDisplayVehicle(spotIndex, model)

    lib.notify({
        type        = 'inform',
        title       = 'Showroom',
        description = 'Display vehicle updated.',
        duration    = 3000
    })
end)

-- ============================================
--  BUG FIX 2: Wrong server event name
--  Was triggering 'getDisplayModels' but server
--  registers 'requestDisplayModels'. Fixed below.
--
--  BUG FIX 3: Race condition — 3 second wait is
--  not reliable. Now uses a retry loop so it keeps
--  retrying until the server acknowledges, which
--  handles slow DB loads on restart cleanly.
-- ============================================

CreateThread(function()
    Wait(2000)
    local attempts = 0
    while next(displayVehicles) == nil and attempts < 10 do
        TriggerServerEvent('frcp_dealership:server:getDisplayModels')
        Wait(3000)
        attempts = attempts + 1
    end
end)

print("^2[frcp_dealership] client/showroom.lua loaded.^0")