-- ============================================
--  frcp_dealership | client.lua
--  Handles NPC, blip, interaction and UI
-- ============================================

local isUIOpen = false

-- ============================================
--  Map Blip
-- ============================================

CreateThread(function()
    local blip = AddBlipForCoord(Config.Location.x, Config.Location.y, Config.Location.z)
    SetBlipSprite(blip, 225)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 27)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Config.DealershipName)
    EndTextCommandSetBlipName(blip)
end)

-- ============================================
--  Salesperson NPC
-- ============================================

CreateThread(function()
    Wait(2000)

    local model = GetHashKey("s_m_m_autoshop_01")
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

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesWhenInjured(ped, false)
    FreezeEntityPosition(ped, true)
    SetPedCanRagdoll(ped, false)
    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CLIPBOARD", 0, true)
    SetModelAsNoLongerNeeded(model)

    exports.ox_target:addLocalEntity(ped, {
        {
            label    = "Browse " .. Config.DealershipName,
            icon     = "fas fa-car",
            distance = 2.5,
            onSelect = function()
                if isUIOpen then return end
                TriggerServerEvent('frcp_dealership:server:getCatalog')
            end
        }
    })
end)

-- ============================================
--  Open UI
-- ============================================

RegisterNetEvent('frcp_dealership:client:openUI', function(data)
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

RegisterNetEvent('frcp_dealership:client:closeUI', function()
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
--  Keys are granted automatically — no prompt
-- ============================================

RegisterNetEvent('frcp_dealership:client:spawnVehicle', function(vehicleModel, plate)
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

    while not DoesEntityExist(vehicle) do
        Wait(100)
    end

    SetVehicleNumberPlateText(vehicle, plate)
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetModelAsNoLongerNeeded(model)

    -- Grant keys automatically — suppresses the "Search for Keys" prompt
    local ped = PlayerPedId()
    TriggerEvent('vehiclekeys:client:SetOwner', plate)

    lib.notify({
        type        = 'success',
        title       = 'FlameDrive Motors',
        description = 'Your vehicle is ready. Drive it out and save it at any garage.',
        duration    = 8000
    })
end)

-- ============================================
--  Live supply update
--  Server broadcasts after every purchase.
--  If the UI is open, push the new count to NUI
--  so the remaining stock updates in real time.
-- ============================================

RegisterNetEvent('frcp_dealership:client:updateSupply', function(model, sold)
    if not isUIOpen then return end
    SendNUIMessage({
        action = "updateSupply",
        model  = model,
        sold   = sold,
    })
end)

-- ============================================
--  NUI Callbacks
-- ============================================

-- Purchase — NUI already has its own confirm modal so we fire directly
RegisterNUICallback('purchaseVehicle', function(data, cb)
    cb('ok')
    TriggerServerEvent('frcp_dealership:server:purchase', data.model)
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

print("^2[frcp_dealership] Client loaded.^0")