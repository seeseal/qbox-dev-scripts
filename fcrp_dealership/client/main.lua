-- ============================================
--  fcrp_dealership | client/main.lua  v2.4
--  [FIX #2] spawnVehicle model load and entity
--  creation now have timeout guards so a bad
--  model string cannot hang the client forever.
--  [FIX #14] onResourceStart event fires setDuty
--  false to re-sync server duty table if the
--  resource is restarted while players are online.
-- ============================================

local isUIOpen       = false
local activeStandIndex = nil

-- ============================================
--  [FIX #14] Resource restart re-sync
--  If only the server-side of this resource is
--  restarted (via `restart fcrp_dealership`),
--  FDDutyPlayers on the server resets to {} but
--  the client isOnDuty flag in job.lua keeps its
--  old value. This event fires on every resource
--  start and tells the server the player is off
--  duty, forcing a clean re-sync. The employee
--  just needs to clock in again normally.
-- ============================================
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerServerEvent('fcrp_dealership:server:setDuty', false)
end)

-- ============================================
--  Map Blip
-- ============================================

CreateThread(function()
    local stand1 = Config.TabletStands[1].coords
    local blip   = AddBlipForCoord(stand1.x, stand1.y, stand1.z)
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
--  Tablet Stand ox_target Zones
-- ============================================

CreateThread(function()
    for standIndex, stand in ipairs(Config.TabletStands) do
        local c = stand.coords

        exports.ox_target:addBoxZone({
            coords   = vec3(c.x, c.y, c.z),
            size     = vec3(1.2, 1.2, 2.0),
            rotation = c.w,
            options  = {
                {
                    label    = stand.label,
                    icon     = "fas fa-tablet-alt",
                    distance = 2.0,
                    onSelect = function()
                        if isUIOpen then return end
                        TriggerServerEvent('fcrp_dealership:server:getCatalog', standIndex)
                    end
                }
            }
        })
    end
end)

-- ============================================
--  Open UI
-- ============================================

RegisterNetEvent('fcrp_dealership:client:openUI', function(data, standIndex)
    if isUIOpen then return end
    isUIOpen         = true
    activeStandIndex = standIndex
    SetNuiFocus(true, true)
    TriggerServerEvent('fcrp_dealership:server:getDisplayModels')

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

RegisterNetEvent('fcrp_dealership:client:closeUI', function()
    closeUI()
end)

function closeUI()
    if not isUIOpen then return end
    isUIOpen         = false
    activeStandIndex = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeUI" })
end

-- ============================================
--  Spawn Vehicle at Dealership
--  [FIX #2] Added timeout guards on both the
--  model load and entity creation loops.
--  Previously an invalid/unstreamed model would
--  spin forever. Now it fails gracefully with a
--  notification after 5 seconds of waiting.
-- ============================================

RegisterNetEvent('fcrp_dealership:client:spawnVehicle', function(vehicleModel, plate)
    local spawnPoint = Config.SpawnPoint
    local model      = GetHashKey(vehicleModel)

    RequestModel(model)

    -- [FIX #2] Model load timeout — 50 × 100ms = 5 seconds max
    local loadTimeout = 0
    while not HasModelLoaded(model) and loadTimeout < 50 do
        Wait(100)
        loadTimeout = loadTimeout + 1
    end

    if not HasModelLoaded(model) then
        SetModelAsNoLongerNeeded(model)
        lib.notify({
            type        = 'error',
            title       = 'FlameDrive Motors',
            description = 'Vehicle could not be spawned (model failed to load). Contact an admin.',
            duration    = 8000
        })
        return
    end

    local vehicle = CreateVehicle(model, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w, true, false)

    -- [FIX #2] Entity creation timeout — 30 × 100ms = 3 seconds max
    local entityTimeout = 0
    while not DoesEntityExist(vehicle) and entityTimeout < 30 do
        Wait(100)
        entityTimeout = entityTimeout + 1
    end

    if not DoesEntityExist(vehicle) then
        SetModelAsNoLongerNeeded(model)
        lib.notify({
            type        = 'error',
            title       = 'FlameDrive Motors',
            description = 'Vehicle entity failed to create. Contact an admin.',
            duration    = 8000
        })
        return
    end

    SetVehicleNumberPlateText(vehicle, plate)
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetModelAsNoLongerNeeded(model)

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
-- ============================================

RegisterNetEvent('fcrp_dealership:client:updateSupply', function(model, sold)
    if not isUIOpen then return end
    SendNUIMessage({ action = "updateSupply", model = model, sold = sold })
end)

-- ============================================
--  Staff list display
-- ============================================

RegisterNetEvent('fcrp_dealership:client:showStaffList', function(staffText, count)
    lib.alertDialog({
        header  = 'FlameDrive Staff Online (' .. count .. ')',
        content = staffText,
        cancel  = false,
    })
end)

RegisterNetEvent('fcrp_dealership:client:receiveSalesStats', function(data)
    SendNUIMessage({
        action     = "receiveSalesStats",
        units      = data.units,
        revenue    = data.revenue,
        commission = data.commission,
        period     = data.period,
    })
end)

RegisterNetEvent('fcrp_dealership:client:receiveLeaderboard', function(data)
    SendNUIMessage({
        action  = "receiveLeaderboard",
        entries = data.entries,
    })
end)

-- ============================================
--  NUI Callbacks
-- ============================================

RegisterNUICallback('purchaseVehicle', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:purchase', data.model, activeStandIndex)
end)

RegisterNUICallback('closeUI', function(_, cb)
    closeUI()
    cb('ok')
end)

RegisterNUICallback('getSocietyBalance', function(_, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:getSocietyBalance')
end)

RegisterNUICallback('withdrawSociety', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:withdrawSociety', data.amount)
end)

RegisterNUICallback('startTestDrive', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:startTestDrive', data.model, data.customerId)
end)

RegisterNUICallback('startSelfTestDrive', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:startSelfTestDrive', data.model)
end)

RegisterNUICallback('getSalesStats', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:getSalesStats', data.period or 'today')
end)

RegisterNUICallback('getSalesLeaderboard', function(_, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:getSalesLeaderboard')
end)

RegisterNUICallback('hirePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:hire', data.targetId)
end)

RegisterNUICallback('firePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:fire', data.targetId)
end)

RegisterNUICallback('promotePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:promote', data.targetId)
end)

RegisterNUICallback('demotePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:demote', data.targetId)
end)

RegisterNUICallback('changeDisplay', function(data, cb)
    cb('ok')
    TriggerServerEvent('fcrp_dealership:server:changeDisplay', data.spot, data.model)
end)

-- ============================================
--  ESC to close
-- ============================================

CreateThread(function()
    while true do
        Wait(50)
        if isUIOpen then
            if IsControlJustPressed(0, 200) then closeUI() end
        else
            Wait(450)
        end
    end
end)

-- ============================================
--  Receive display models → forward to NUI
-- ============================================

RegisterNetEvent('fcrp_dealership:client:receiveDisplayModels', function(models)
    -- [FIX #13] Single handler owns both jobs: forwarding to NUI and spawning
    -- physical vehicles. ShowroomSpawnAll is defined in client/showroom.lua.
    -- Previously showroom.lua had its own RegisterNetEvent for the same event,
    -- meaning both handlers fired on every receiveDisplayModels broadcast — all
    -- display cars were deleted and re-created twice on every player load/respawn.
    ShowroomSpawnAll(models)

    local catalogForPicker = {}
    for _, v in ipairs(Config.Vehicles) do
        table.insert(catalogForPicker, {
            model    = v.model,
            label    = v.label,
            tier     = v.tier,
            category = v.category,
        })
    end
    SendNUIMessage({
        action           = "receiveDisplayModels",
        models           = models,
        catalogForPicker = catalogForPicker,
    })
end)

print("^2[fcrp_dealership] client/main.lua loaded.^0")
