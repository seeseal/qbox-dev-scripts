-- ============================================
--  fcrp_dealership | server/showroom.lua  v2.4
--  [FIX #13] playerSpawned replaced with
--  QBCore:Client:OnPlayerLoaded so respawns
--  after death don't trigger a redundant full
--  display model re-broadcast.
-- ============================================

local QBX = exports.qbx_core

local displayModels = {}

-- ============================================
--  Load saved display models from DB
-- ============================================

local function loadDisplayModels(cb)
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `fcrp_dealership_display` (
            `spot`  INT(11)     NOT NULL,
            `model` VARCHAR(50) NOT NULL DEFAULT '',
            PRIMARY KEY (`spot`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function()
        MySQL.query('SELECT spot, model FROM fcrp_dealership_display', {}, function(result)
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
            print("^2[fcrp_dealership] Showroom display models loaded.^0")
            if cb then cb() end
        end)
    end)
end

-- ============================================
--  Save a single spot
-- ============================================

local function saveDisplayModel(spot, model)
    MySQL.update(
        'INSERT INTO fcrp_dealership_display (spot, model) VALUES (?, ?) ON DUPLICATE KEY UPDATE model = ?',
        { spot, model, model }
    )
end

-- ============================================
--  Get all display models
-- ============================================

RegisterNetEvent('fcrp_dealership:server:getDisplayModels', function()
    local src = source
    TriggerClientEvent('fcrp_dealership:client:receiveDisplayModels', src, displayModels)
end)

-- ============================================
--  [FIX #13] Send display models on first load only.
--  Old code used playerSpawned which fires on every
--  respawn (including after death), causing the client
--  to delete and re-spawn all display vehicles every
--  time a player dies. QBCore:Client:OnPlayerLoaded
--  fires only once per character login session.
-- ============================================

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player.PlayerData.source
    SetTimeout(3000, function()
        TriggerClientEvent('fcrp_dealership:client:receiveDisplayModels', src, displayModels)
    end)
end)

-- ============================================
--  Change a display vehicle
-- ============================================

RegisterNetEvent('fcrp_dealership:server:changeDisplay', function(spot, model)
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

    -- [FIX #11] O(1) model validation via shared vehicleMap
    if not vehicleMap or not vehicleMap[model] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid vehicle model.' })
        return
    end

    local vehicleLabel = vehicleMap[model].label
    displayModels[spot] = model
    saveDisplayModel(spot, model)

    -- Broadcast single-spot update to all clients
    TriggerClientEvent('fcrp_dealership:client:updateDisplay', -1, spot, model)

    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'success',
        title       = 'Showroom Updated',
        description = 'Display ' .. spot .. ' → ' .. vehicleLabel,
        duration    = 5000
    })

    print("^2[fcrp_dealership] " .. player.PlayerData.charinfo.firstname ..
          " changed display spot " .. spot .. " to " .. model .. "^0")
end)

-- ============================================
--  Startup
-- ============================================

MySQL.ready(function()
    loadDisplayModels(function()
        TriggerClientEvent('fcrp_dealership:client:receiveDisplayModels', -1, displayModels)
    end)
end)

print("^2[fcrp_dealership] server/showroom.lua loaded.^0")
