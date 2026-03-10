-- ============================================================
--  frcp_vipgarage  |  client/main.lua
--  Handles ox_target zones, applying vehicle props after spawn,
--  and warping the player into their retrieved vehicle.
-- ============================================================

-- ============================================================
--  State
-- ============================================================
local zones = {}   -- slot_id -> ox_target zone name

-- ============================================================
--  Helper: register one ox_target sphere for a slot
-- ============================================================
local function RegisterSlotZone(slot)
    if not slot or not slot.coords then return end

    local zoneName = 'frcp_vipgarage_slot_' .. slot.slot_id
    zones[slot.slot_id] = zoneName

    exports.ox_target:addSphereZone({
        name    = zoneName,
        coords  = vector3(slot.coords.x, slot.coords.y, slot.coords.z),
        radius  = Config.TargetRadius,
        debug   = Config.Debug,
        options = {
            -- PARK option — only shows when player is in a vehicle
            {
                name        = zoneName .. '_park',
                icon        = 'fas fa-parking',
                label       = '[E] Park Vehicle',
                onSelect    = function() TryPark(slot.slot_id) end,
                canInteract = function()
                    local ped = PlayerPedId()
                    local veh = GetVehiclePedIsIn(ped, false)
                    return veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped
                end,
            },
            -- RETRIEVE option — only shows when a vehicle is parked there
            {
                name        = zoneName .. '_retrieve',
                icon        = 'fas fa-car',
                label       = '[E] Retrieve Vehicle',
                onSelect    = function() TryRetrieve(slot.slot_id) end,
                canInteract = function()
                    return slot.vehicle_plate ~= nil and slot.vehicle_plate ~= ''
                end,
            },
        },
    })
end

-- ============================================================
--  Receive ALL slots on join / resource start
-- ============================================================
RegisterNetEvent('frcp_vipgarage:client:LoadZones', function(slotsData)
    for _, slot in pairs(slotsData) do
        RegisterSlotZone(slot)
    end
end)

-- ============================================================
--  Add a single new zone (admin just created a slot)
-- ============================================================
RegisterNetEvent('frcp_vipgarage:client:AddZone', function(slot)
    RegisterSlotZone(slot)
end)

-- ============================================================
--  Remove a zone (admin deleted a slot)
-- ============================================================
RegisterNetEvent('frcp_vipgarage:client:RemoveZone', function(slotId)
    local zoneName = zones[slotId]
    if zoneName then
        exports.ox_target:removeZone(zoneName)
        zones[slotId] = nil
    end
end)

-- ============================================================
--  Refresh zone data (a vehicle was parked or retrieved)
--  We remove and re-add so the canInteract checks update.
-- ============================================================
RegisterNetEvent('frcp_vipgarage:client:RefreshZone', function(slot)
    local zoneName = zones[slot.slot_id]
    if zoneName then
        exports.ox_target:removeZone(zoneName)
        zones[slot.slot_id] = nil
    end
    RegisterSlotZone(slot)
end)

-- ============================================================
--  TRY PARK  — collect props, send to server
-- ============================================================
function TryPark(slotId)
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not vehicle or vehicle == 0 then
        lib.notify({ type='error', description='You must be in a vehicle to park.' })
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle):gsub('%s+', '')
    local model = GetEntityModel(vehicle)
    local modelName = ''
    -- Convert hash to string model name
    for k, v in pairs({}) do end -- stub; use a lookup if needed
    -- We pass the model hash as a string — server uses GetHashKey to recreate
    modelName = GetDisplayNameFromVehicleModel(model):lower()

    -- Collect all vehicle props using ox_lib helper
    local propsJSON = json.encode(lib.getVehicleProperties and lib.getVehicleProperties(vehicle) or {})

    -- Eject the player before asking server to park
    TaskLeaveVehicle(ped, vehicle, 0)
    Wait(1500)

    -- Ask server to save and spawn static entity
    TriggerServerEvent('frcp_vipgarage:server:ParkVehicle', slotId, plate, modelName, propsJSON)

    -- Delete the driveable entity on client side
    -- (server will have spawned the static one)
    Wait(500)
    if DoesEntityExist(vehicle) then
        DeleteEntity(vehicle)
    end
end

-- ============================================================
--  TRY RETRIEVE
-- ============================================================
function TryRetrieve(slotId)
    TriggerServerEvent('frcp_vipgarage:server:RetrieveVehicle', slotId)
end

-- ============================================================
--  Server spawned a driveable vehicle — warp player in and apply props
-- ============================================================
RegisterNetEvent('frcp_vipgarage:client:WarpAndApply', function(netId, propsJSON)
    -- Wait for the entity to stream to this client
    local timeout = 5000
    local elapsed = 0
    local vehicle = 0

    while elapsed < timeout do
        vehicle = NetworkGetEntityFromNetworkId(netId)
        if vehicle and vehicle ~= 0 then break end
        Wait(200)
        elapsed = elapsed + 200
    end

    if not vehicle or vehicle == 0 then
        lib.notify({ type='error', description='Vehicle spawn timed out. Check impound.' })
        return
    end

    -- Wait for model to fully load before applying props
    local modelHash = GetEntityModel(vehicle)
    local loadWait  = 0
    while not HasModelLoaded(modelHash) and loadWait < 3000 do
        Wait(100)
        loadWait = loadWait + 100
    end

    -- Apply saved props (mods, colours, neons, extras etc.)
    if propsJSON and propsJSON ~= '' then
        local props = json.decode(propsJSON)
        if props and lib.setVehicleProperties then
            lib.setVehicleProperties(vehicle, props)
        end
    end

    -- Warp player into driver seat and start engine
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetVehicleEngineOn(vehicle, true, true, false)

    lib.notify({ type='success', description='Vehicle retrieved! Drive safely.' })
end)

-- ============================================================
--  Apply props to static parked entity (for nearby players)
-- ============================================================
RegisterNetEvent('frcp_vipgarage:client:ApplyProps', function(entityNetId, propsJSON)
    if not propsJSON or propsJSON == '' then return end
    local entity = NetworkGetEntityFromNetworkId(entityNetId)
    if not entity or entity == 0 then return end

    local props = json.decode(propsJSON)
    if props and lib.setVehicleProperties then
        lib.setVehicleProperties(entity, props)
    end
end)
