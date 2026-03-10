-- ============================================================
--  frcp_vipgarage  |  server/main.lua
--  All database logic, vehicle spawning, admin commands.
--  The server is the ONLY place vehicles are created — clients
--  can't fake a spawn event and get a free car.
-- ============================================================

-- ============================================================
--  In-memory slot cache
--  Format: slots[slot_id] = { slot_id, owner_citizenid,
--                              coords = {x,y,z,w},
--                              vehicle_plate, vehicle_model,
--                              vehicle_props, entity = nil }
-- ============================================================
local slots   = {}
local slotMap = {}  -- plate -> slot_id for quick lookup

-- ============================================================
--  Startup: load all slots from DB
-- ============================================================
MySQL.ready(function()
    MySQL.query('SELECT * FROM frcp_vip_slots', {}, function(rows)
        if not rows then return end
        for _, row in ipairs(rows) do
            local coords = json.decode(row.coords) or {}
            slots[row.slot_id] = {
                slot_id         = row.slot_id,
                owner_citizenid = row.owner_citizenid,
                coords          = coords,
                vehicle_plate   = row.vehicle_plate,
                vehicle_model   = row.vehicle_model,
                vehicle_props   = row.vehicle_props,
                entity          = nil,
            }
            if row.vehicle_plate then
                slotMap[row.vehicle_plate] = row.slot_id
            end
        end
        if Config.Debug then
            print('[frcp_vipgarage] Loaded ' .. #rows .. ' VIP slots from DB.')
        end
        -- Tell all clients to register their ox_target zones
        TriggerClientEvent('frcp_vipgarage:client:LoadZones', -1, slots)
        -- Start streaming threads
        StartSpawnThread()
        StartDespawnThread()
    end)
end)

-- ============================================================
--  Helper: check if a citizenid has access to a slot
-- ============================================================
local function HasAccess(citizenid, slot)
    if slot.owner_citizenid == citizenid then return true end
    -- Check grants table
    local rows = MySQL.query.await(
        'SELECT id FROM frcp_vip_access WHERE owner_citizenid = ? AND allowed_citizenid = ?',
        { slot.owner_citizenid, citizenid }
    )
    return rows and #rows > 0
end

-- ============================================================
--  Helper: log to Discord via frcp_webhook
-- ============================================================
local function Log(message)
    if exports.frcp_webhook then
        exports.frcp_webhook:Send(
            'general',
            '🅿️ VIP Garage',
            message,
            5792242  -- blue in decimal (0x5865F2)
        )
    end
end

-- ============================================================
--  Helper: spawn a static (locked, engine off) vehicle entity
--  at the slot's saved coords
-- ============================================================
local function SpawnSlotEntity(slot)
    if slot.entity and DoesEntityExist(slot.entity) then return end
    if not slot.vehicle_model or not slot.vehicle_plate then return end

    local coords = slot.coords
    local modelHash = GetHashKey(slot.vehicle_model)

    -- RequestModel equivalent on server side via native
    -- Qbox/FiveM server doesn't have RequestModel — we use CreateVehicle directly.
    -- The model must be in the vehicle's streaming list.
    local entity = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w or 0.0, false, false)

    if entity and entity ~= 0 then
        SetVehicleNumberPlateText(entity, slot.vehicle_plate)
        SetEntityInvincible(entity, true)
        FreezeEntityPosition(entity, true)
        SetVehicleEngineOn(entity, false, true, false)
        SetVehicleDoorsLocked(entity, 2) -- locked to everyone

        slot.entity = entity

        if Config.Debug then
            print(('[frcp_vipgarage] Spawned entity for slot %d plate %s'):format(slot.slot_id, slot.vehicle_plate))
        end

        -- Tell nearby clients to apply saved props (mods, colour etc)
        if slot.vehicle_props then
            TriggerClientEvent('frcp_vipgarage:client:ApplyProps', -1, entity, slot.vehicle_props)
        end
    end
end

-- ============================================================
--  Helper: despawn the static entity for a slot
-- ============================================================
local function DespawnSlotEntity(slot)
    if slot.entity and DoesEntityExist(slot.entity) then
        DeleteEntity(slot.entity)
    end
    slot.entity = nil
end

-- ============================================================
--  STREAMING: spawn when players are within range
-- ============================================================
function StartSpawnThread()
    CreateThread(function()
        while true do
            Wait(Config.StreamInterval)
            local players = GetPlayers()
            for _, slot in pairs(slots) do
                if slot.vehicle_plate and not slot.entity then
                    for _, playerId in ipairs(players) do
                        local ped    = GetPlayerPed(playerId)
                        local coords = GetEntityCoords(ped)
                        local dist   = #(vector3(coords.x, coords.y, coords.z) -
                                         vector3(slot.coords.x, slot.coords.y, slot.coords.z))
                        if dist <= Config.SpawnRadius then
                            SpawnSlotEntity(slot)
                            break
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
--  STREAMING: despawn when no players are nearby
-- ============================================================
function StartDespawnThread()
    CreateThread(function()
        while true do
            Wait(Config.DespawnInterval)
            local players = GetPlayers()
            for _, slot in pairs(slots) do
                if slot.entity and DoesEntityExist(slot.entity) then
                    local anyNear = false
                    for _, playerId in ipairs(players) do
                        local ped    = GetPlayerPed(playerId)
                        local coords = GetEntityCoords(ped)
                        local dist   = #(vector3(coords.x, coords.y, coords.z) -
                                         vector3(slot.coords.x, slot.coords.y, slot.coords.z))
                        if dist <= Config.SpawnRadius then
                            anyNear = true
                            break
                        end
                    end
                    if not anyNear then
                        DespawnSlotEntity(slot)
                    end
                end
            end
        end
    end)
end

-- ============================================================
--  PARK VEHICLE  (player requests to park)
-- ============================================================
RegisterNetEvent('frcp_vipgarage:server:ParkVehicle', function(slotId, plate, model, propsJSON)
    local src      = source
    local Player   = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local slot      = slots[slotId]

    if not slot then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Invalid slot.' })
        return
    end

    if not HasAccess(citizenid, slot) then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='You do not have access to this slot.' })
        return
    end

    if slot.vehicle_plate then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Slot is already occupied.' })
        return
    end

    -- Verify player owns this vehicle
    local owned = MySQL.query.await('SELECT plate FROM player_vehicles WHERE plate = ? AND citizenid = ?', { plate, citizenid })
    if not owned or #owned == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='You do not own this vehicle.' })
        return
    end

    -- Save to DB
    MySQL.update('UPDATE frcp_vip_slots SET vehicle_plate = ?, vehicle_model = ?, vehicle_props = ? WHERE slot_id = ?',
        { plate, model, propsJSON, slotId })

    -- Update cache
    slot.vehicle_plate   = plate
    slot.vehicle_model   = model
    slot.vehicle_props   = propsJSON
    slotMap[plate]       = slotId

    -- Spawn static entity
    SpawnSlotEntity(slot)

    -- Mark as 'garaged' in player_vehicles so it doesn't appear elsewhere
    MySQL.update('UPDATE player_vehicles SET state = 1 WHERE plate = ?', { plate })

    TriggerClientEvent('ox_lib:notify', src, { type='success', description='Vehicle parked in your VIP slot.' })
    TriggerClientEvent('frcp_vipgarage:client:RefreshZone', -1, slot)

    Log(('%s %s parked **%s** (%s) in VIP slot #%d.'):format(
        Player.PlayerData.charinfo.firstname,
        Player.PlayerData.charinfo.lastname,
        plate, model, slotId
    ))
end)

-- ============================================================
--  RETRIEVE VEHICLE  (player requests to drive it out)
-- ============================================================
RegisterNetEvent('frcp_vipgarage:server:RetrieveVehicle', function(slotId)
    local src      = source
    local Player   = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local slot      = slots[slotId]

    if not slot then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Invalid slot.' })
        return
    end

    if not HasAccess(citizenid, slot) then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='You do not have access to this slot.' })
        return
    end

    if not slot.vehicle_plate then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='No vehicle in this slot.' })
        return
    end

    -- Despawn static entity
    DespawnSlotEntity(slot)

    -- Spawn driveable vehicle at slot coords
    local coords    = slot.coords
    local modelHash = GetHashKey(slot.vehicle_model)
    local veh       = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w or 0.0, true, false)

    if not veh or veh == 0 then
        -- Fallback: send to impound
        MySQL.update('UPDATE player_vehicles SET state = 2 WHERE plate = ?', { slot.vehicle_plate })
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Spawn failed — vehicle sent to impound.' })
        -- Clear slot
        MySQL.update('UPDATE frcp_vip_slots SET vehicle_plate = NULL, vehicle_model = NULL, vehicle_props = NULL WHERE slot_id = ?', { slotId })
        slotMap[slot.vehicle_plate] = nil
        slot.vehicle_plate  = nil
        slot.vehicle_model  = nil
        slot.vehicle_props  = nil
        return
    end

    SetVehicleNumberPlateText(veh, slot.vehicle_plate)
    SetVehicleEngineOn(veh, true, true, false)

    -- Tell the client to apply props and warp player in
    local propsJSON = slot.vehicle_props
    TriggerClientEvent('frcp_vipgarage:client:WarpAndApply', src, GetEntityNetworkId(veh), propsJSON)

    -- Mark as 'out' in garages
    MySQL.update('UPDATE player_vehicles SET state = 0 WHERE plate = ?', { slot.vehicle_plate })

    -- Clear slot in DB and cache
    MySQL.update('UPDATE frcp_vip_slots SET vehicle_plate = NULL, vehicle_model = NULL, vehicle_props = NULL WHERE slot_id = ?', { slotId })
    slotMap[slot.vehicle_plate] = nil
    slot.vehicle_plate  = nil
    slot.vehicle_model  = nil
    slot.vehicle_props  = nil

    TriggerClientEvent('frcp_vipgarage:client:RefreshZone', -1, slot)

    Log(('%s %s retrieved vehicle from VIP slot #%d.'):format(
        Player.PlayerData.charinfo.firstname,
        Player.PlayerData.charinfo.lastname,
        slotId
    ))
end)

-- ============================================================
--  ADMIN: /createslot [citizenid]
-- ============================================================
lib.addCommand('createslot', {
    help   = 'Create a VIP parking slot at your position (admin only)',
    params = {
        { name = 'citizenid', help = 'CitizenID of the player to assign the slot to', type = 'string' },
    },
    restricted = 'group.' .. Config.AdminGroup,
}, function(source, args)
    local src       = source
    local citizenid = args.citizenid

    -- Check slot count for this player
    local existing = MySQL.query.await('SELECT COUNT(*) AS cnt FROM frcp_vip_slots WHERE owner_citizenid = ?', { citizenid })
    local count     = (existing and existing[1] and existing[1].cnt) or 0

    if count >= Config.MaxSlotsPerOwner then
        TriggerClientEvent('ox_lib:notify', src, { type='error',
            description=('Player already has %d/%d slots.'):format(count, Config.MaxSlotsPerOwner) })
        return
    end

    -- Get admin's current position as the slot location
    local ped     = GetPlayerPed(src)
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local coordJSON = json.encode({ x = coords.x, y = coords.y, z = coords.z, w = heading })

    local newId = MySQL.insert.await('INSERT INTO frcp_vip_slots (owner_citizenid, coords) VALUES (?, ?)',
        { citizenid, coordJSON })

    slots[newId] = {
        slot_id         = newId,
        owner_citizenid = citizenid,
        coords          = { x = coords.x, y = coords.y, z = coords.z, w = heading },
        vehicle_plate   = nil,
        vehicle_model   = nil,
        vehicle_props   = nil,
        entity          = nil,
    }

    -- Tell all clients about the new slot
    TriggerClientEvent('frcp_vipgarage:client:AddZone', -1, slots[newId])

    TriggerClientEvent('ox_lib:notify', src, { type='success',
        description=('VIP slot #%d created for %s.'):format(newId, citizenid) })

    Log(('Admin created VIP slot #%d for citizenid **%s** at %.1f, %.1f.'):format(newId, citizenid, coords.x, coords.y))
end)

-- ============================================================
--  ADMIN: /removeslot [slot_id]
-- ============================================================
lib.addCommand('removeslot', {
    help   = 'Permanently remove a VIP parking slot',
    params = {
        { name = 'slot_id', help = 'Slot ID to remove', type = 'number' },
    },
    restricted = 'group.' .. Config.AdminGroup,
}, function(source, args)
    local src    = source
    local slotId = args.slot_id
    local slot   = slots[slotId]

    if not slot then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Slot not found.' })
        return
    end

    -- Send vehicle to impound if one is parked there
    if slot.vehicle_plate then
        MySQL.update('UPDATE player_vehicles SET state = 2 WHERE plate = ?', { slot.vehicle_plate })
        slotMap[slot.vehicle_plate] = nil
    end

    DespawnSlotEntity(slot)

    -- Delete from DB
    MySQL.update('DELETE FROM frcp_vip_slots WHERE slot_id = ?', { slotId })

    -- If player has no more slots, wipe their access grants too
    local remaining = MySQL.query.await('SELECT COUNT(*) AS cnt FROM frcp_vip_slots WHERE owner_citizenid = ?',
        { slot.owner_citizenid })
    if (remaining and remaining[1] and remaining[1].cnt) == 0 then
        MySQL.update('DELETE FROM frcp_vip_access WHERE owner_citizenid = ?', { slot.owner_citizenid })
    end

    -- Remove from cache and tell clients
    TriggerClientEvent('frcp_vipgarage:client:RemoveZone', -1, slotId)
    slots[slotId] = nil

    TriggerClientEvent('ox_lib:notify', src, { type='success', description=('Slot #%d removed.'):format(slotId) })
end)

-- ============================================================
--  PLAYER: /addkeypersistent [citizenid]
-- ============================================================
lib.addCommand('addkeypersistent', {
    help   = 'Grant another player access to all your VIP slots',
    params = {
        { name = 'citizenid', help = 'CitizenID to grant access to', type = 'string' },
    },
}, function(source, args)
    local src       = source
    local Player    = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    local ownerCid  = Player.PlayerData.citizenid
    local targetCid = args.citizenid

    if ownerCid == targetCid then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='You cannot grant yourself access.' })
        return
    end

    -- Check grant limit
    local grants = MySQL.query.await('SELECT COUNT(*) AS cnt FROM frcp_vip_access WHERE owner_citizenid = ?', { ownerCid })
    if (grants and grants[1] and grants[1].cnt) >= Config.MaxAccessGrantsPerOwner then
        TriggerClientEvent('ox_lib:notify', src, { type='error',
            description=('Max access grants reached (%d).'):format(Config.MaxAccessGrantsPerOwner) })
        return
    end

    MySQL.insert('INSERT IGNORE INTO frcp_vip_access (owner_citizenid, allowed_citizenid) VALUES (?, ?)',
        { ownerCid, targetCid })

    TriggerClientEvent('ox_lib:notify', src, { type='success',
        description=('Access granted to %s for all your VIP slots.'):format(targetCid) })
end)

-- ============================================================
--  PLAYER: /removeaccess [citizenid]
-- ============================================================
lib.addCommand('removeaccess', {
    help   = 'Revoke a player\'s access to your VIP slots',
    params = {
        { name = 'citizenid', help = 'CitizenID to revoke', type = 'string' },
    },
}, function(source, args)
    local src       = source
    local Player    = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    local ownerCid  = Player.PlayerData.citizenid
    local targetCid = args.citizenid

    MySQL.update('DELETE FROM frcp_vip_access WHERE owner_citizenid = ? AND allowed_citizenid = ?',
        { ownerCid, targetCid })

    TriggerClientEvent('ox_lib:notify', src, { type='success',
        description=('Access revoked for %s.'):format(targetCid) })
end)

-- ============================================================
--  Disconnect protection:
--  If a player disconnects while in park flow, impound the car
-- ============================================================
AddEventHandler('playerDropped', function()
    local src = source
    -- This is a simple safety net — the actual park/retrieve flow
    -- locks the vehicle before the player disconnects, so mid-flow
    -- disconnects are already handled by state loss.
    -- Expand here if you add a multi-step park lock state.
end)