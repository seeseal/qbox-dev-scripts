-- ============================================
--  frcp_dealership | client/main.lua  v2.0
--  Original dealership NUI/NPC/blip logic.
--  Now also sends job status to NUI so the
--  Job Management tab can appear for employees.
-- ============================================

local isUIOpen       = false
local activeStandIndex = nil  -- which tablet stand the customer used to open the UI

-- ============================================
--  Map Blip
--  Uses the first tablet stand as the blip anchor
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
--  Pure vec4 — no props spawned.
--  The heading (w) rotates the target box so
--  it aligns with your MLO stand positions.
--  !! CHANGE ME !! coords in Config.TabletStands
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
                        TriggerServerEvent('frcp_dealership:server:getCatalog', standIndex)
                    end
                }
            }
        })
    end
end)

-- ============================================
--  Open UI
-- ============================================

RegisterNetEvent('frcp_dealership:client:openUI', function(data, standIndex)
    if isUIOpen then return end
    isUIOpen       = true
    activeStandIndex = standIndex  -- remember which stand opened this session
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
    isUIOpen         = false
    activeStandIndex = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeUI" })
end

-- ============================================
--  Spawn Vehicle at Dealership
-- ============================================

RegisterNetEvent('frcp_dealership:client:spawnVehicle', function(vehicleModel, plate)
    local spawnPoint = Config.SpawnPoint
    local model      = GetHashKey(vehicleModel)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(100) end

    local vehicle = CreateVehicle(model, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w, true, false)
    while not DoesEntityExist(vehicle) do Wait(100) end

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

RegisterNetEvent('frcp_dealership:client:updateSupply', function(model, sold)
    if not isUIOpen then return end
    SendNUIMessage({ action = "updateSupply", model = model, sold = sold })
end)

-- ============================================
--  Society balance received (for boss menu NUI)
-- ============================================

RegisterNetEvent('frcp_dealership:client:receiveSocietyBalance', function(balance)
    SendNUIMessage({ action = "receiveSocietyBalance", balance = balance })
end)

-- ============================================
--  Staff list display
-- ============================================

RegisterNetEvent('frcp_dealership:client:showStaffList', function(staffText, count)
    lib.alertDialog({
        header  = '👔 FlameDrive Staff Online (' .. count .. ')',
        content = staffText,
        cancel  = false,
    })
end)

-- ============================================
--  NUI Callbacks
-- ============================================

RegisterNUICallback('purchaseVehicle', function(data, cb)
    cb('ok')
    -- Pass model AND the stand index this customer opened the UI from
    -- activeStandIndex is set when getCatalog fires (stand interaction)
    TriggerServerEvent('frcp_dealership:server:purchase', data.model, activeStandIndex)
end)

RegisterNUICallback('closeUI', function(_, cb)
    closeUI()
    cb('ok')
end)

-- Boss: request society balance
RegisterNUICallback('getSocietyBalance', function(_, cb)
    cb('ok')
    TriggerServerEvent('frcp_dealership:server:getSocietyBalance')
end)

-- Boss: withdraw from fund
RegisterNUICallback('withdrawSociety', function(data, cb)
    cb('ok')
    TriggerServerEvent('frcp_dealership:server:withdrawSociety', data.amount)
end)

-- Salesperson: start a test drive for a nearby customer
RegisterNUICallback('startTestDrive', function(data, cb)
    cb('ok')
    -- data.model = vehicle model, data.customerId = server ID of customer
    TriggerServerEvent('frcp_dealership:server:startTestDrive', data.model, data.customerId)
end)

-- Boss: hire (target must be nearby, we use ox_target in job.lua client side)
RegisterNUICallback('hirePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('frcp_dealership:server:hire', data.targetId)
end)

RegisterNUICallback('firePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('frcp_dealership:server:fire', data.targetId)
end)

RegisterNUICallback('promotePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('frcp_dealership:server:promote', data.targetId)
end)

RegisterNUICallback('demotePlayer', function(data, cb)
    cb('ok')
    TriggerServerEvent('frcp_dealership:server:demote', data.targetId)
end)

-- ============================================
--  ESC to close
-- ============================================

CreateThread(function()
    while true do
        Wait(0)
        if isUIOpen then
            if IsControlJustPressed(0, 200) then closeUI() end
        else
            Wait(500)
        end
    end
end)

print("^2[frcp_dealership] client/main.lua loaded.^0")
