-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  client/debug.lua       ║
-- ║   F8 console debug output — safe to remove  ║
-- ║   in production by deleting from manifest   ║
-- ╚══════════════════════════════════════════════╝

local PREFIX = '^3[fcrp_tuner DEBUG]^7 '

local function D(...)
    local parts = {}
    for i = 1, select('#', ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print(PREFIX .. table.concat(parts, ' '))
end

-- ─────────────────────────────────────────────
--  ZONE ENTRY / EXIT
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:debug:zoneEnter', function(zoneName)
    D('Zone ENTER →', zoneName)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        local inSeat = GetPedInVehicleSeat(veh, -1) == ped
        D('  Vehicle netId:', NetworkGetNetworkIdFromEntity(veh), '| driver:', inSeat)
    else
        D('  Not in a vehicle')
    end
end)

AddEventHandler('fcrp_tuner:debug:zoneExit', function(zoneName)
    D('Zone EXIT ←', zoneName)
end)

-- ─────────────────────────────────────────────
--  KEY PRESS
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:debug:keyPressed', function(context)
    D('E pressed in context:', context)
end)

-- ─────────────────────────────────────────────
--  MENU
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:debug:menuOpen', function(itemCount)
    D('Menu opening — item count:', itemCount)
end)

AddEventHandler('fcrp_tuner:debug:menuFail', function(reason)
    D('^1Menu open FAILED^7 —', reason)
end)

-- ─────────────────────────────────────────────
--  CALLBACKS
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:debug:callbackResult', function(name, result)
    if result == nil then
        D('^1Callback', name, 'returned NIL^7 (server error or vehicle not synced)')
    else
        D('Callback', name, '→ OK')
    end
end)

-- ─────────────────────────────────────────────
--  PURCHASE
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:debug:purchaseStart', function(productKey)
    D('Purchase START —', productKey)
end)

AddEventHandler('fcrp_tuner:debug:purchaseResult', function(productKey, success, reason)
    if success then
        D('^2Purchase SUCCESS^7 —', productKey)
    else
        D('^1Purchase FAILED^7 —', productKey, '| reason:', tostring(reason))
    end
end)

-- ─────────────────────────────────────────────
--  DUTY
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:client:dutyChanged', function(onDuty)
    D('Duty changed → ON DUTY:', tostring(onDuty))
end)

-- ─────────────────────────────────────────────
--  PLAYER STATE SNAPSHOT  (type /tunerdebug in F8)
-- ─────────────────────────────────────────────

RegisterCommand('tunerdebug', function()
    D('========= STATE SNAPSHOT =========')
    local pd = exports.qbx_core:GetPlayerData()
    if pd and pd.job then
        D('Job:', pd.job.name, '| Grade:', pd.job.grade and pd.job.grade.level or 'nil', '| OnDuty:', tostring(pd.job.onduty))
    else
        D('^1Could not get PlayerData^7')
    end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        local isDriver = GetPedInVehicleSeat(veh, -1) == ped
        local netId    = NetworkGetNetworkIdFromEntity(veh)
        local hasCtrl  = NetworkHasControlOfEntity(veh)
        D('Vehicle — netId:', netId, '| driver:', tostring(isDriver), '| hasControl:', tostring(hasCtrl))
        D('Plate:', GetVehicleNumberPlateText(veh))
    else
        D('Not in a vehicle')
    end

    local coords = GetEntityCoords(ped)
    D(string.format('Coords: %.2f, %.2f, %.2f', coords.x, coords.y, coords.z))
    D('==================================')
end, false)

D('^2Debug script loaded^7 — type ^3tunerdebug^7 in F8 for a state snapshot')
