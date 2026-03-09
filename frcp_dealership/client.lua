-- ============================================
--  fd_dealership | client.lua
--  Handles interaction and UI communication
-- ============================================

local isUIOpen = false

-- ============================================
--  Target Zone
--  Interaction point at dealership entrance
-- ============================================

CreateThread(function()
    Wait(2000)

    exports.ox_target:addSphereZone({
        coords  = Config.Location,
        radius  = 5.0,
        options = {
            {
                label    = "Browse " .. Config.DealershipName,
                icon     = "fas fa-car",
                onSelect = function()
                    if isUIOpen then return end
                    TriggerServerEvent('fd_dealership:server:getCatalog')
                end
            }
        }
    })
end)

-- ============================================
--  Open UI
-- ============================================

RegisterNetEvent('fd_dealership:client:openUI', function(data)
    if isUIOpen then return end
    isUIOpen = true

    SetNuiFocus(true, true)
    SendNUIMessage({
        action         = "openDealership",
        data           = data,
        tiers          = Config.Tiers,
        categories     = Config.Categories,
        dealershipName = Config.DealershipName,
    })
end)

-- ============================================
--  Close UI
-- ============================================

RegisterNetEvent('fd_dealership:client:closeUI', function()
    closeUI()
end)

function closeUI()
    if not isUIOpen then return end
    isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeUI" })
end

-- ============================================
--  Spawn Vehicle at Dealership
--  Triggered by server after purchase confirms
-- ============================================

RegisterNetEvent('fd_dealership:client:spawnVehicle', function(vehicleModel, plate)
    local spawnPoint = Config.SpawnPoint
    local model      = GetHashKey(vehicleModel)

    -- Load model
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(100)
    end

    -- Spawn at dealership spawn point
    local vehicle = CreateVehicle(
        model,
        spawnPoint.x,
        spawnPoint.y,
        spawnPoint.z,
        spawnPoint.w,
        true,
        false
    )

    -- Set plate
    SetVehicleNumberPlateText(vehicle, plate)

    -- Wait for entity
    while not DoesEntityExist(vehicle) do
        Wait(100)
    end

    -- Put player in driver seat
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)

    -- Free model memory
    SetModelAsNoLongerNeeded(model)

    -- Notify player
    lib.notify({
        type        = 'success',
        title       = 'FlameDrive Motors',
        description = 'Your vehicle is ready. Drive it out and save it at any garage.',
        duration    = 8000
    })
end)

-- ============================================
--  NUI Callbacks
-- ============================================

RegisterNUICallback('purchaseVehicle', function(data, cb)
    TriggerServerEvent('fd_dealership:server:purchase', data.model)
    cb('ok')
end)

RegisterNUICallback('closeUI', function(_, cb)
    closeUI()
    cb('ok')
end)

-- ============================================
--  ESC to close UI
-- ============================================

CreateThread(function()
    while true do
        Wait(0)
        if isUIOpen then
            if IsControlJustPressed(0, 200) then
                closeUI()
            end
        else
            Wait(500)
        end
    end
end)

print("^2[fd_dealership] Client loaded.^0")
```

---

Replace all three files completely, save, and push.

Commit message:
```
clean rewrite config client server fd_dealership