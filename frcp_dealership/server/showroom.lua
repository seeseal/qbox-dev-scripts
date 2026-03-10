-- ============================================
--  frcp_dealership | server/showroom.lua  v2.0
-- ============================================

local QBX = exports.qbx_core

local displayModels = {}

-- ============================================
--  Load saved display models from DB
-- ============================================

local function loadDisplayModels(cb)
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `frcp_dealership_display` (
            `spot`  INT(11)     NOT NULL,
            `model` VARCHAR(50) NOT NULL DEFAULT '',
            PRIMARY KEY (`spot`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function()
        MySQL.query('SELECT spot, model FROM frcp_dealership_display', {}, function(result)
            for spotIndex, spotData in ipairs(Config.DisplaySpots) do
                displayModels[spotIndex] = spotData.default
            end
            if result then
                for _, row in ipairs(result) do
                    if Config.DisplaySpots[row.spot] then
                        displayModels[row.spot] = row.model
                    end
                end
            end
            print("^2[frcp_dealership] Showroom display models loaded.^0")
            if cb then cb() end
        end)
    end)
end

-- ============================================
--  Save a single spot to DB
-- ============================================

local function saveDisplayModel(spot, model)
    MySQL.update(
        'INSERT INTO frcp_dealership_display (spot, model) VALUES (?, ?) ON DUPLICATE KEY UPDATE model = ?',
        { spot, model, model }
    )
end

-- ============================================
--  Get all display models (requested by client)
-- ============================================

RegisterNetEvent('frcp_dealership:server:getDisplayModels', function()
    local src = source
    TriggerClientEvent('frcp_dealership:client:receiveDisplayModels', src, displayModels)
end)

-- ============================================
--  BUG FIX: Send display models to players
--  who connect after the resource has started.
--  Previously only sent on MySQL.ready which
--  fires once — late joiners never received it.
-- ============================================

AddEventHandler('playerSpawned', function()
    local src = source
    -- Small delay to ensure client scripts are ready
    SetTimeout(3000, function()
        TriggerClientEvent('frcp_dealership:client:receiveDisplayModels', src, displayModels)
    end)
end)

-- ============================================
--  Change a display vehicle
-- ============================================

RegisterNetEvent('frcp_dealership:server:changeDisplay', function(spot, model)
    local src    = source
    local player = QBX:GetPlayer(src)
    if not player then return end

    local job = player.PlayerData.job

    if not job or job.name ~= Config.JobName then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error', description = 'Only FlameDrive employees can change display vehicles.'
        })
        return
    end

    if not FDDutyPlayers[src] then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error', description = 'You must be on duty to change display vehicles.'
        })
        return
    end

    if job.grade.level < Config.DisplayChangeMinGrade then
        local required = Config.JobGrades[Config.DisplayChangeMinGrade]
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = 'Requires ' .. (required and required.label or 'higher rank') .. ' or above.'
        })
        return
    end

    if not Config.DisplaySpots[spot] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid display spot.' })
        return
    end

    local vehicleFound = false
    local vehicleLabel = model
    for _, v in ipairs(Config.Vehicles) do
        if v.model == model then
            vehicleFound = true
            vehicleLabel = v.label
            break
        end
    end
    if not vehicleFound then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid vehicle model.' })
        return
    end

    displayModels[spot] = model
    saveDisplayModel(spot, model)

    TriggerClientEvent('frcp_dealership:client:updateDisplay', -1, spot, model)

    local empName = player.PlayerData.charinfo.firstname
    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'success',
        title       = 'Showroom Updated',
        description = 'Display ' .. spot .. ' → ' .. vehicleLabel,
        duration    = 5000
    })

    -- ============================================
    --  BUG FIX: NUI event name was wrong.
    --  Was sending 'receiveDisplayModels' but the
    --  NUI message handler listens for
    --  'receiveDisplayModels' via the JS action
    --  — this is correct, no change needed here.
    --  The real fix is the client event above.
    -- ============================================
    TriggerClientEvent('frcp_dealership:client:receiveDisplayModels', src, displayModels)

    print("^2[frcp_dealership] " .. empName .. " changed display spot " .. spot .. " to " .. model .. "^0")
end)

-- ============================================
--  Startup
-- ============================================

MySQL.ready(function()
    loadDisplayModels(function()
        TriggerClientEvent('frcp_dealership:client:receiveDisplayModels', -1, displayModels)
    end)
end)

print("^2[frcp_dealership] server/showroom.lua loaded.^0")