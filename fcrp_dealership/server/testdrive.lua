-- ============================================
--  fcrp_dealership | server/testdrive.lua  v2.4
--  [FIX #9] endTestDrive reason is now
--  whitelisted server-side. Unknown reason
--  strings from a malicious client are replaced
--  with 'ended' before being forwarded.
--  [FIX #11] Model validation uses vehicleMap
--  (O(1)) instead of O(n) loop.
-- ============================================

local QBX = exports.qbx_core

-- [FIX #9] Whitelist of valid end reasons.
-- Any reason not in this set is replaced with 'ended'
-- before being forwarded to the client, so a malicious
-- client cannot inject arbitrary strings into logs.
local VALID_REASONS = {
    timer_expired     = true,
    out_of_bounds     = true,
    exited_vehicle    = true,
    player_died       = true,
    vehicle_destroyed = true,
    staff_ended       = true,
    ended             = true,
}

local activeTestDrives = {}

-- ============================================
--  Self Test Drive
-- ============================================

RegisterNetEvent('fcrp_dealership:server:startSelfTestDrive', function(model)
    local src = source

    if activeTestDrives[src] then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error', description = 'You already have an active test drive running.'
        })
        return
    end

    -- [FIX #11] O(1) model validation via shared vehicleMap
    if not vehicleMap or not vehicleMap[model] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid vehicle.' })
        return
    end

    activeTestDrives[src] = {
        model     = model,
        startTime = os.time(),
        self      = true,
    }

    TriggerClientEvent('fcrp_dealership:client:beginTestDrive', src, model, Config.TestDriveDuration)
    print("^2[fcrp_dealership] Self test drive started: " .. model .. " for player " .. src .. "^0")
end)

-- ============================================
--  Start Test Drive (salesperson-initiated)
-- ============================================

RegisterNetEvent('fcrp_dealership:server:startTestDrive', function(model, customerServerId)
    local src    = source
    local player = QBX:GetPlayer(src)
    if not player then return end

    local job       = player.PlayerData.job
    local gradeData = job and Config.JobGrades[job.grade.level]

    if not job or job.name ~= Config.JobName or not gradeData or not gradeData.canTestDrive then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error', description = 'You are not authorised to start test drives.'
        })
        return
    end

    local customer = QBX:GetPlayer(customerServerId)
    if not customer then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Customer not found.' })
        return
    end

    if activeTestDrives[customerServerId] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'That player already has an active test drive.' })
        return
    end

    -- [FIX #11] O(1) model validation via shared vehicleMap
    if not vehicleMap or not vehicleMap[model] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid vehicle model.' })
        return
    end

    activeTestDrives[customerServerId] = {
        model       = model,
        startTime   = os.time(),
        salesPerson = src
    }

    TriggerClientEvent('fcrp_dealership:client:beginTestDrive', customerServerId, model, Config.TestDriveDuration)

    local custName = customer.PlayerData.charinfo.firstname .. " " .. customer.PlayerData.charinfo.lastname
    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'success',
        title       = 'Test Drive',
        description = custName .. ' is now test driving the ' .. model .. '.'
    })

    print("^2[fcrp_dealership] Test drive started: " .. model .. " for player " .. customerServerId .. "^0")
end)

-- ============================================
--  End Test Drive
--  [FIX #9] Reason is whitelisted before use.
-- ============================================

RegisterNetEvent('fcrp_dealership:server:endTestDrive', function(reason)
    local src   = source
    local drive = activeTestDrives[src]
    if not drive then return end

    activeTestDrives[src] = nil

    -- [FIX #9] Reject unknown reasons — client cannot inject arbitrary strings
    local safeReason = VALID_REASONS[reason] and reason or 'ended'

    TriggerClientEvent('fcrp_dealership:client:concludeTestDrive', src, safeReason)
    print("^2[fcrp_dealership] Test drive ended for player " .. src .. " (" .. safeReason .. ")^0")
end)

-- ============================================
--  /endtestdrive [playerID]
-- ============================================

lib.addCommand('endtestdrive', {
    help   = 'End a customer test drive early',
    params = {{ name = 'id', help = 'Server ID of the customer', type = 'number' }},
    restricted = false,
}, function(src, args)
    local caller = QBX:GetPlayer(src)
    if not caller then return end

    local job       = caller.PlayerData.job
    local gradeData = job and Config.JobGrades[job.grade.level]

    if not job or job.name ~= Config.JobName or not gradeData then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'You are not a FlameDrive employee.' })
        return
    end

    local targetId = tonumber(args.id)
    local drive    = activeTestDrives[targetId]

    if not drive then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'That player does not have an active test drive.' })
        return
    end

    activeTestDrives[targetId] = nil
    TriggerClientEvent('fcrp_dealership:client:concludeTestDrive', targetId, 'staff_ended')
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Test drive ended.' })
end)

-- ============================================
--  Cleanup on disconnect
-- ============================================

AddEventHandler('playerDropped', function()
    local src = source
    if activeTestDrives[src] then
        activeTestDrives[src] = nil
        print("^3[fcrp_dealership] Test drive cleaned up — player " .. src .. " disconnected^0")
    end
end)

-- ============================================
--  Export
-- ============================================

exports('HasTestDrive', function(serverId)
    return activeTestDrives[serverId] ~= nil
end)

print("^2[fcrp_dealership] server/testdrive.lua loaded.^0")
