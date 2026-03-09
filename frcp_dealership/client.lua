-- ============================================
--  fd_dealership | client.lua
--  Handles NPC, blip, interaction and UI
-- ============================================

local isUIOpen = false

-- ============================================
--  Map Blip
-- ============================================

CreateThread(function()
    local blip = AddBlipForCoord(Config.Location.x, Config.Location.y, Config.Location.z)
    SetBlipSprite(blip, 225)          -- car dealership icon
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 27)           -- purple
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Config.DealershipName)
    EndTextCommandSetBlipName(blip)
end)

-- ============================================
--  Salesperson NPC
--  Spawns a ped at the dealership entrance.
--  ox_target is attached to the ped so the
--  player presses E directly on the NPC.
-- ============================================

CreateThread(function()
    Wait(2000)

    local model = GetHashKey("s_m_m_autoshop_01") -- car salesman ped model
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(100)
    end

    local ped = CreatePed(
        4,
        model,
        Config.Location.x,
        Config.Location.y,
        Config.Location.z - 1.0,
        Config.Location.w,
        false,
        true
    )

    -- Make ped permanent and non-threatening
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesWhenInjured(ped, false)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CLIPBOARD", 0, true)

    SetModelAsNoLongerNeeded(model)

    -- Attach ox_target to the ped
    exports.ox_target:addLocalEntity(ped, {
        {
            label    = "Browse " .. Config.DealershipName,
            icon     = "fas fa-car",
            distance = 2.5,
            onSelect = function()
                if isUIOpen then return end
                TriggerServerEvent('fd_dealership:server:getCatalog')
            end
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

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(100)
    end

    local vehicle = CreateVehicle(
        model,
        spawnPoint.x,
        spawnPoint.y,
        spawnPoint.z,
        spawnPoint.w,
        true,
        false
    )

    SetVehicleNumberPlateText(vehicle, plate)

    while not DoesEntityExist(vehicle) do
        Wait(100)
    end

    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetModelAsNoLongerNeeded(model)

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