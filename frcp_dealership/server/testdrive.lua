-- ============================================
--  frcp_dealership | server/testdrive.lua  v2.0
--
--  WHAT THIS FILE DOES (plain English):
--  ─────────────────────────────────────
--  Tracks active test drives server-side so
--  that:
--  • We know which player has which test drive car
--  • If a player disconnects mid-drive the car
--    is cleaned up and the drive ends properly
--  • A salesperson can end a test drive early
--    using /endtestdrive [playerID]
--  • Only employees with canTestDrive = true
--    can start a test drive for a customer
-- ============================================

local QBX = exports.qbx_core

-- activeTestDrives[playerServerId] = { model, startTime, networkId }
local activeTestDrives = {}

-- ============================================
--  Start Test Drive
--  Called by client when salesperson approves
-- ============================================

RegisterNetEvent('frcp_dealership:server:startTestDrive', function(model, customerServerId)
    local src    = source  -- this is the SALESPERSON calling it
    local player = QBX:GetPlayer(src)
    if not player then return end

    -- Check caller is an employee allowed to run test drives
    local job       = player.PlayerData.job
    local gradeData = job and Config.JobGrades[job.grade.level]

    if not job or job.name ~= Config.JobName or not gradeData or not gradeData.canTestDrive then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error', description = 'You are not authorised to start test drives.'
        })
        return
    end

    -- Validate customer
    local customer = QBX:GetPlayer(customerServerId)
    if not customer then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Customer not found.' })
        return
    end

    -- Don't allow double test drives
    if activeTestDrives[customerServerId] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'That player already has an active test drive.' })
        return
    end

    -- Validate model exists in catalog
    local vehicleFound = false
    for _, v in ipairs(Config.Vehicles) do
        if v.model == model then vehicleFound = true; break end
    end
    if not vehicleFound then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid vehicle model.' })
        return
    end

    -- Register drive server-side
    activeTestDrives[customerServerId] = {
        model       = model,
        startTime   = os.time(),
        salesPerson = src
    }

    -- Tell the CUSTOMER's client to spawn and start the test drive
    TriggerClientEvent('frcp_dealership:client:beginTestDrive', customerServerId, model, Config.TestDriveDuration)

    -- Tell the salesperson it worked
    local custName = customer.PlayerData.charinfo.firstname .. " " .. customer.PlayerData.charinfo.lastname
    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'success',
        title       = 'Test Drive',
        description = custName .. ' is now test driving the ' .. model .. '.'
    })

    print("^2[frcp_dealership] Test drive started: " .. model .. " for player " .. customerServerId .. "^0")
end)

-- ============================================
--  End Test Drive
--  Called by client when timer expires or
--  player goes out of bounds, OR by /endtestdrive
-- ============================================

RegisterNetEvent('frcp_dealership:server:endTestDrive', function(reason)
    local src = source
    local drive = activeTestDrives[src]
    if not drive then return end

    activeTestDrives[src] = nil

    -- Tell client to delete car and teleport player back
    TriggerClientEvent('frcp_dealership:client:concludeTestDrive', src, reason or 'ended')

    print("^2[frcp_dealership] Test drive ended for player " .. src .. " (" .. (reason or 'ended') .. ")^0")
end)

-- ============================================
--  /endtestdrive [playerID]
--  Salesperson can force-end a customer's drive
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
    TriggerClientEvent('frcp_dealership:client:concludeTestDrive', targetId, 'staff_ended')

    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'Test drive ended.' })
end)

-- ============================================
--  Clean up if player disconnects during drive
-- ============================================

AddEventHandler('playerDropped', function()
    local src = source
    if activeTestDrives[src] then
        activeTestDrives[src] = nil
        print("^3[frcp_dealership] Test drive cleaned up — player " .. src .. " disconnected^0")
    end
end)

-- ============================================
--  Export: check if player has active test drive
-- ============================================

exports('HasTestDrive', function(serverId)
    return activeTestDrives[serverId] ~= nil
end)

print("^2[frcp_dealership] server/testdrive.lua loaded.^0")
