-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  server/main.lua        ║
-- ╚══════════════════════════════════════════════╝

-- ─────────────────────────────────────────────
--  RUNTIME STATE
-- ─────────────────────────────────────────────

-- Maps displayed fake plate text → real plate (populated from DB on start)
local fakePlateCache    = {}

-- src → true when that tuner is on duty
local dutyPlayers       = {}

-- citizenid → true when that tuner has an active supply run in progress
local activeRunPlayers  = {}

-- citizenid → os.time() of last completed supply run
local supplyRunCooldowns = {}

-- ─────────────────────────────────────────────
--  DB INIT
-- ─────────────────────────────────────────────

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `fcrp_tuner_mods` (
            `plate`              VARCHAR(15)  NOT NULL,
            `engine_chip`        TINYINT(1)   NOT NULL DEFAULT 0,
            `drift_chip`         TINYINT(1)   NOT NULL DEFAULT 0,
            `nos`                TINYINT(1)   NOT NULL DEFAULT 0,
            `nos_pressure`       FLOAT        NOT NULL DEFAULT 1.0,
            `nos_cooldown_until` BIGINT       NOT NULL DEFAULT 0,
            `neon_mode`          VARCHAR(16)  DEFAULT NULL,
            `neon_r`             SMALLINT     DEFAULT NULL,
            `neon_g`             SMALLINT     DEFAULT NULL,
            `neon_b`             SMALLINT     DEFAULT NULL,
            `stance_camber`      FLOAT        DEFAULT NULL,
            `stance_height`      FLOAT        DEFAULT NULL,
            `stance_wheeldist`   FLOAT        DEFAULT NULL,
            `has_exhaust`        TINYINT(1)   NOT NULL DEFAULT 0,
            `fake_plate`         VARCHAR(15)  DEFAULT NULL,
            `vehicle_value`      INT          NOT NULL DEFAULT 0,
            PRIMARY KEY (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Add new columns to existing installs (safe on fresh installs too)
    MySQL.query("ALTER TABLE `fcrp_tuner_mods` ADD COLUMN IF NOT EXISTS `nos_pressure` FLOAT NOT NULL DEFAULT 1.0 AFTER `nos`")
    MySQL.query("ALTER TABLE `fcrp_tuner_mods` ADD COLUMN IF NOT EXISTS `fake_plate` VARCHAR(15) DEFAULT NULL")
    MySQL.query("ALTER TABLE `fcrp_tuner_mods` ADD COLUMN IF NOT EXISTS `vehicle_value` INT NOT NULL DEFAULT 0")

    -- Load fake plate cache from DB
    local rows = MySQL.query.await('SELECT plate, fake_plate FROM fcrp_tuner_mods WHERE fake_plate IS NOT NULL')
    for _, row in ipairs(rows or {}) do
        fakePlateCache[row.fake_plate] = row.plate
    end

    -- Register nos_canister as a usable item
    exports.ox_inventory:RegisterUsableItem('nos_canister', function(src)
        local ped = GetPlayerPed(src)
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then
            TriggerClientEvent('ox_lib:notify', src, { title = 'You must be inside a vehicle to use a NOS Canister.', type = 'error', duration = 3000 })
            return
        end
        TriggerClientEvent('fcrp_tuner:client:useNosCanister', src)
    end)
end)

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

-- Resolves the real plate for a vehicle, even if a fake plate is currently displayed
local function GetPlate(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return nil end
    local displayed = string.upper(string.gsub(GetVehicleNumberPlateText(veh), '%s+', ''))
    return fakePlateCache[displayed] or displayed
end

local function GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

-- BUG FIX: replaced the original local GetVehicleClass (which shadowed the native and recursed)
-- and GetVehicleModelName (which used a client-only native). Now operates on the entity handle directly.
local function IsVehicleBlacklisted(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return false, nil end
    local cls = GetVehicleClass(veh)
    for _, c in ipairs(Config.BlacklistedVehicleClasses) do
        if c == cls then return true, 'Vehicle class not allowed.' end
    end
    local model = GetEntityModel(veh)
    for _, m in ipairs(Config.BlacklistedVehicles) do
        if GetHashKey(m) == model then return true, 'This vehicle is not allowed.' end
    end
    return false, nil
end

local function GetJobGradeConfig(src)
    local Player = GetPlayer(src)
    if not Player then return Config.JobGrades[0] end
    local grade = Player.PlayerData.job and Player.PlayerData.job.grade and Player.PlayerData.job.grade.level or 0
    return Config.JobGrades[grade] or Config.JobGrades[0]
end

local function IsOnDuty(src)
    local Player = GetPlayer(src)
    if not Player then return false end
    local job = Player.PlayerData.job
    if not job or job.name ~= Config.RequiredJob then return false end
    return dutyPlayers[src] == true
end

local function PayCommission(src, amount)
    local gradeConf = GetJobGradeConfig(src)
    local cut = math.floor(amount * gradeConf.commission)
    if cut <= 0 then return end
    exports.ox_inventory:AddItem(src, Config.PaymentType, cut)
    TriggerClientEvent('ox_lib:notify', src, {
        title    = string.format('💰 Commission: $%s', lib.math.groupdigits(cut)),
        type     = 'success',
        duration = 5000,
    })
end

local function LogDiscord(title, description, colour, src)
    if Config.DiscordWebhook == '' then return end
    local Player = GetPlayer(src)
    local name   = Player and Player.PlayerData.charinfo and
                   (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname) or 'Unknown'
    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST',
        json.encode({
            username = 'fcrp_tuner',
            embeds = {{
                title       = title,
                description = description .. '\n**Player:** ' .. name .. ' (' .. src .. ')',
                color       = colour or Config.DiscordColour,
            }}
        }),
        { ['Content-Type'] = 'application/json' }
    )
end

-- ─────────────────────────────────────────────
--  CLEANUP ON DISCONNECT
-- ─────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src    = source
    local Player = GetPlayer(src)
    if Player then
        local cid = Player.PlayerData.citizenid
        activeRunPlayers[cid] = nil
    end
    dutyPlayers[src] = nil
end)

-- ─────────────────────────────────────────────
--  VEHICLE STATE
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getVehicleState', function(src, netId)
    local plate = GetPlate(netId)
    if not plate then return nil end

    local row = MySQL.single.await('SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row then return {
        engine_chip = false, drift_chip = false,
        nos = false, nos_pressure = 1.0, nos_cooldown_until = 0,
        neon_mode = nil, neon_r = nil, neon_g = nil, neon_b = nil,
        has_stance = false, stance = nil, has_exhaust = false, fake_plate = nil,
    } end

    local now = os.time() * 1000
    return {
        engine_chip        = row.engine_chip == 1,
        drift_chip         = row.drift_chip == 1,
        nos                = row.nos == 1,
        nos_pressure       = row.nos_pressure or 1.0,
        nos_cooldown_until = math.max(0, (row.nos_cooldown_until or 0) - now) / 1000,
        neon_mode          = row.neon_mode,
        neon_r             = row.neon_r,
        neon_g             = row.neon_g,
        neon_b             = row.neon_b,
        has_stance         = row.stance_camber ~= nil,
        stance             = row.stance_camber and {
            camber    = row.stance_camber,
            height    = row.stance_height,
            wheeldist = row.stance_wheeldist,
        } or nil,
        has_exhaust = row.has_exhaust == 1,
        fake_plate  = row.fake_plate,
    }
end)

-- ─────────────────────────────────────────────
--  PRICE CALLBACKS
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getEngineChipPrice', function(src, netId)
    local plate  = GetPlate(netId)
    local row    = plate and MySQL.single.await('SELECT vehicle_value FROM fcrp_tuner_mods WHERE plate = ?', { plate }) or nil
    local stored = (row and row.vehicle_value) or 0
    local bonus  = math.floor(stored * Config.EngineChip.carValuePercent)
    return Config.EngineChip.basePrice + bonus, stored, bonus
end)

lib.callback.register('fcrp_tuner:server:getDriftChipPrice', function(src, netId)
    local plate  = GetPlate(netId)
    local row    = plate and MySQL.single.await('SELECT vehicle_value FROM fcrp_tuner_mods WHERE plate = ?', { plate }) or nil
    local stored = (row and row.vehicle_value) or 0
    local bonus  = math.floor(stored * Config.DriftChip.carValuePercent)
    return Config.DriftChip.basePrice + bonus, stored, bonus
end)

-- ─────────────────────────────────────────────
--  VEHICLE VALUE  (sent by client on ramp entry)
--  Client reads GetVehicleValue() and reports it so server can
--  compute chip price bonuses without needing KVP natives.
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:setVehicleValue', function(netId, value)
    local plate = GetPlate(netId)
    if not plate then return end
    local safeValue = math.max(0, math.min(10000000, math.floor(tonumber(value) or 0)))
    MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, vehicle_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE vehicle_value = ?', { plate, safeValue, safeValue })
end)

-- ─────────────────────────────────────────────
--  PASSENGER LOOKUP
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getPassenger', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return nil end
    for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local ped     = GetPedInVehicleSeat(veh, seat)
        local passSrc = ped and ped ~= 0 and GetPlayerFromPed(ped) or -1
        if passSrc ~= -1 and passSrc ~= src then return passSrc end
    end
    return nil
end)

-- ─────────────────────────────────────────────
--  PURCHASE
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:purchase', function(src, productKey, _, passengerSrc, netId)
    local Player = GetPlayer(src)
    if not Player then return false, 'Player not found.' end

    local job = Player.PlayerData.job
    if not job or job.name ~= Config.RequiredJob then
        return false, 'You must be a tuner to install mods.'
    end

    local plate = GetPlate(netId)
    if not plate then return false, 'Vehicle not found.' end

    local blacklisted, reason = IsVehicleBlacklisted(netId)
    if blacklisted then return false, reason end

    local payerSrc = passengerSrc or src
    local Payer    = GetPlayer(payerSrc)
    if not Payer then return false, 'Payer not found.' end

    local price = 0

    if productKey == 'engine_chip' then
        local vrow   = MySQL.single.await('SELECT drift_chip, engine_chip, vehicle_value FROM fcrp_tuner_mods WHERE plate = ?', { plate })
        local stored = (vrow and vrow.vehicle_value) or 0
        price = Config.EngineChip.basePrice + math.floor(stored * Config.EngineChip.carValuePercent)
        if vrow and vrow.drift_chip  == 1 then return false, 'Remove drift chip first.' end
        if vrow and vrow.engine_chip == 1 then return false, 'Engine chip already installed.' end
        local hasChip = exports.ox_inventory:GetItemCount(payerSrc, 's3_chip')
        if not hasChip or hasChip < 1 then return false, 'Requires 1x S3 Chip item.' end
        exports.ox_inventory:RemoveItem(payerSrc, 's3_chip', 1)

    elseif productKey == 'drift_chip' then
        local vrow   = MySQL.single.await('SELECT engine_chip, drift_chip, vehicle_value FROM fcrp_tuner_mods WHERE plate = ?', { plate })
        local stored = (vrow and vrow.vehicle_value) or 0
        price = Config.DriftChip.basePrice + math.floor(stored * Config.DriftChip.carValuePercent)
        if vrow and vrow.engine_chip == 1 then return false, 'Remove engine chip first.' end
        if vrow and vrow.drift_chip  == 1 then return false, 'Drift chip already installed.' end
        local hasDrift = exports.ox_inventory:GetItemCount(payerSrc, 'drift_chip')
        if not hasDrift or hasDrift < 1 then return false, 'Requires 1x Drift Chip item.' end
        exports.ox_inventory:RemoveItem(payerSrc, 'drift_chip', 1)

    elseif productKey == 'stance_kit' then
        price = Config.StanceKit.price
        local hasRod = exports.ox_inventory:GetItemCount(payerSrc, 'stance_rod')
        if not hasRod or hasRod < 1 then return false, 'Requires 1x Stance Rod item.' end
        exports.ox_inventory:RemoveItem(payerSrc, 'stance_rod', 1)

    elseif productKey == 'nitrous_kit' then
        price = Config.Nitrous.price

    elseif productKey == 'exhaust_mod' then
        price = Config.ExhaustMod.price

    elseif productKey == 'fake_plate' then
        price = Config.FakePlate.price

    elseif productKey == 'neon_static' or productKey == 'neon_rainbow'
        or productKey == 'neon_rgb'    or productKey == 'neon_strobe' then
        local map = { neon_static = 'static', neon_rainbow = 'rainbow', neon_rgb = 'rgb', neon_strobe = 'strobe' }
        price = Config.NeonPrices[map[productKey]] or 25000
    else
        return false, 'Unknown product.'
    end

    local cash = exports.ox_inventory:GetItemCount(payerSrc, Config.PaymentType)
    if not cash or cash < price then
        return false, string.format('Not enough dirty cash. Need $%s.', lib.math.groupdigits(price))
    end
    exports.ox_inventory:RemoveItem(payerSrc, Config.PaymentType, price)

    -- Persist to DB
    local saveMap = {
        engine_chip = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, engine_chip) VALUES (?, 1) ON DUPLICATE KEY UPDATE engine_chip = 1', { plate }) end,
        drift_chip  = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, drift_chip)  VALUES (?, 1) ON DUPLICATE KEY UPDATE drift_chip  = 1', { plate }) end,
        stance_kit  = function() end,  -- saved separately via saveStance
        fake_plate  = function() end,  -- saved separately via applyFakePlate
        nitrous_kit = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, nos, nos_pressure) VALUES (?, 1, 1.0) ON DUPLICATE KEY UPDATE nos = 1, nos_pressure = 1.0', { plate }) end,
        exhaust_mod = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, has_exhaust) VALUES (?, 1) ON DUPLICATE KEY UPDATE has_exhaust = 1', { plate }) end,
    }
    local neonMap = { neon_static = 'static', neon_rainbow = 'rainbow', neon_rgb = 'rgb', neon_strobe = 'strobe' }
    if neonMap[productKey] then
        MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, neon_mode) VALUES (?, ?) ON DUPLICATE KEY UPDATE neon_mode = ?', { plate, neonMap[productKey], neonMap[productKey] })
    elseif saveMap[productKey] then
        saveMap[productKey]()
    end

    PayCommission(src, price)
    LogDiscord('Mod Purchased', string.format('**Mod:** %s\n**Plate:** %s\n**Price:** $%s', productKey, plate, lib.math.groupdigits(price)), nil, src)
    return true, price
end)

-- ─────────────────────────────────────────────
--  REMOVE MOD
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:removeMod', function(src, netId, modKey)
    local plate = GetPlate(netId)
    if not plate then return false, 'Vehicle not found.' end

    if modKey == 'fake_plate' then
        local row = MySQL.single.await('SELECT fake_plate FROM fcrp_tuner_mods WHERE plate = ?', { plate })
        if row and row.fake_plate then
            fakePlateCache[row.fake_plate] = nil
        end
        MySQL.query.await('UPDATE fcrp_tuner_mods SET fake_plate = NULL WHERE plate = ?', { plate })
        -- Broadcast plate restoration to all clients
        TriggerClientEvent('fcrp_tuner:client:restoreRealPlate', -1, netId, plate)
        return true
    end

    local colMap = {
        engine_chip = 'engine_chip = 0',
        drift_chip  = 'drift_chip = 0',
        nos         = 'nos = 0, nos_pressure = 1.0, nos_cooldown_until = 0',
        neon        = 'neon_mode = NULL, neon_r = NULL, neon_g = NULL, neon_b = NULL',
        stance      = 'stance_camber = NULL, stance_height = NULL, stance_wheeldist = NULL',
        exhaust     = 'has_exhaust = 0',
    }
    if not colMap[modKey] then return false, 'Unknown mod.' end
    MySQL.query.await('UPDATE fcrp_tuner_mods SET ' .. colMap[modKey] .. ' WHERE plate = ?', { plate })
    return true
end)

-- ─────────────────────────────────────────────
--  STANCE SAVE
--  BUG FIX: parameter order corrected — client sends (camberF, camberR, height)
--  Old signature (camber, height, wheeldist) swapped rear camber and ride height in the DB.
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:saveStance', function(netId, camberF, camberR, height)
    local plate = GetPlate(netId)
    if not plate then return end
    MySQL.query.await([[
        INSERT INTO fcrp_tuner_mods (plate, stance_camber, stance_height, stance_wheeldist)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            stance_camber    = VALUES(stance_camber),
            stance_height    = VALUES(stance_height),
            stance_wheeldist = VALUES(stance_wheeldist)
    ]], { plate, camberF, height, camberR })  -- wheeldist column stores camberR
end)

-- ─────────────────────────────────────────────
--  NEON SAVE
--  BUG FIX: renamed from saveNeonColour → saveNeon to match client/neon.lua
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:saveNeon', function(netId, mode, r, g, b)
    local plate = GetPlate(netId)
    if not plate then return end
    MySQL.query.await('UPDATE fcrp_tuner_mods SET neon_mode = ?, neon_r = ?, neon_g = ?, neon_b = ? WHERE plate = ?', { mode, r, g, b, plate })
end)

-- ─────────────────────────────────────────────
--  FAKE PLATE
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:applyFakePlate', function(netId, plateText)
    local src = source
    if not plateText or #plateText < 1 or #plateText > 8 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Invalid plate text.', type = 'error', duration = 3000 })
        return
    end

    -- Sanitise: uppercase alphanumeric + spaces only
    plateText = string.upper(plateText):gsub('[^A-Z0-9 ]', '')
    if #plateText < 1 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Invalid plate text — use letters and numbers only.', type = 'error', duration = 3000 })
        return
    end

    if fakePlateCache[plateText] then
        TriggerClientEvent('ox_lib:notify', src, { title = 'That plate is already in use by another vehicle.', type = 'error', duration = 3000 })
        return
    end

    local plate = GetPlate(netId)
    if not plate then return end

    MySQL.query.await('UPDATE fcrp_tuner_mods SET fake_plate = ? WHERE plate = ?', { plateText, plate })
    fakePlateCache[plateText] = plate

    -- Broadcast to all clients so every player sees the new plate
    TriggerClientEvent('fcrp_tuner:client:applyFakePlate', -1, netId, plateText)
    LogDiscord('Fake Plate Applied', string.format('**Real Plate:** %s\n**Fake Plate:** %s', plate, plateText), 16776960, src)
end)

-- ─────────────────────────────────────────────
--  NOS — pressure drain on activation
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:nosUsed', function(netId)
    local plate   = GetPlate(netId)
    if not plate then return end
    local expires = (os.time() + Config.Nitrous.cooldown) * 1000
    MySQL.query.await(
        'UPDATE fcrp_tuner_mods SET nos_pressure = GREATEST(0.0, nos_pressure - ?), nos_cooldown_until = ? WHERE plate = ?',
        { Config.Nitrous.pressureDrain, expires, plate }
    )
end)

-- ─────────────────────────────────────────────
--  NOS CANISTER USE — refill pressure
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:useNosCanister', function(netId)
    local src   = source
    local plate = GetPlate(netId)
    if not plate then return end

    local row = MySQL.single.await('SELECT nos, nos_pressure FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row or row.nos ~= 1 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'No NOS kit installed on this vehicle.', type = 'error', duration = 4000 })
        return
    end

    local currentPressure = row.nos_pressure or 1.0
    if currentPressure >= 1.0 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'NOS tank is already full.', type = 'inform', duration = 3000 })
        return
    end

    local count = exports.ox_inventory:GetItemCount(src, 'nos_canister')
    if not count or count < 1 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'You need a NOS Canister to refill.', type = 'error', duration = 4000 })
        return
    end
    exports.ox_inventory:RemoveItem(src, 'nos_canister', 1)

    MySQL.query.await(
        'UPDATE fcrp_tuner_mods SET nos_pressure = LEAST(1.0, nos_pressure + ?), nos_cooldown_until = 0 WHERE plate = ?',
        { Config.Nitrous.canisterRefill, plate }
    )

    -- Return new pressure to client
    local updated = MySQL.single.await('SELECT nos_pressure FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    local newPressure = updated and updated.nos_pressure or math.min(1.0, currentPressure + Config.Nitrous.canisterRefill)
    TriggerClientEvent('fcrp_tuner:client:nosRefillConfirmed', src, newPressure)
end)

-- ─────────────────────────────────────────────
--  CRAFT SYSTEM  (Tuner II + Master Tuner only)
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:craftItem', function(src, recipeIdx)
    local gradeConf = GetJobGradeConfig(src)
    if not gradeConf.canCraft then
        return false, 'You need to be Tuner II or higher to craft.'
    end
    local recipe = Config.CraftRecipes[recipeIdx]
    if not recipe then return false, 'Invalid recipe.' end

    for _, ing in ipairs(recipe.ingredients) do
        local count = exports.ox_inventory:GetItemCount(src, ing.item)
        if not count or count < ing.amount then
            return false, string.format('Missing: %dx %s', ing.amount, ing.label)
        end
    end
    for _, ing in ipairs(recipe.ingredients) do
        exports.ox_inventory:RemoveItem(src, ing.item, ing.amount)
    end
    return true
end)

RegisterNetEvent('fcrp_tuner:server:craftComplete', function(recipeIdx)
    local src    = source
    local recipe = Config.CraftRecipes[recipeIdx]
    if not recipe then return end
    exports.ox_inventory:AddItem(src, recipe.item, 1)
    LogDiscord('Item Crafted', string.format('**Item:** %s', recipe.label), 65280, src)
end)

RegisterNetEvent('fcrp_tuner:server:craftCancel', function(recipeIdx)
    local src    = source
    local recipe = Config.CraftRecipes[recipeIdx]
    if not recipe then return end
    for _, ing in ipairs(recipe.ingredients) do
        exports.ox_inventory:AddItem(src, ing.item, ing.amount)
    end
end)

-- ─────────────────────────────────────────────
--  SOCIETY STASH  (Master Tuner only)
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:openSocietyStash', function()
    local src       = source
    local gradeConf = GetJobGradeConfig(src)
    if not gradeConf.isOwner then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Only the Master Tuner can access the society stash.', type = 'error', duration = 4000 })
        return
    end
    TriggerClientEvent('fcrp_tuner:client:openSocietyStash', src)
end)

-- ─────────────────────────────────────────────
--  DUTY TOGGLE
-- ─────────────────────────────────────────────

local function ToggleDuty(src)
    local Player = GetPlayer(src)
    if not Player then return end
    local job = Player.PlayerData.job
    if not job or job.name ~= Config.RequiredJob then
        TriggerClientEvent('ox_lib:notify', src, { title = 'You are not employed as a tuner.', type = 'error', duration = 3000 })
        return
    end
    dutyPlayers[src] = not dutyPlayers[src]
    local onDuty = dutyPlayers[src]
    TriggerClientEvent('fcrp_tuner:client:dutyChanged', src, onDuty)
    LogDiscord('Duty Toggle', string.format('**Status:** %s', onDuty and 'ON DUTY' or 'OFF DUTY'), onDuty and 65280 or 16711680, src)
end

lib.addCommand('tunerduty', {
    help = 'Toggle on/off duty as a tuner.',
}, function(src)
    ToggleDuty(src)
end)

RegisterNetEvent('fcrp_tuner:server:clockIn', function()
    ToggleDuty(source)
end)

-- ─────────────────────────────────────────────
--  SUPPLY RUN
-- ─────────────────────────────────────────────

lib.addCommand('supplyrun', {
    help = 'Start a supply run to collect damaged parts for crafting.',
}, function(src)
    local Player = GetPlayer(src)
    if not Player then return end
    local job = Player.PlayerData.job
    if not job or job.name ~= Config.RequiredJob then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Only tuners can run supplies.', type = 'error', duration = 3000 })
        return
    end
    if not IsOnDuty(src) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'You must be on duty. Use /tunerduty first.', type = 'error', duration = 3000 })
        return
    end

    local cid = Player.PlayerData.citizenid
    if activeRunPlayers[cid] then
        TriggerClientEvent('ox_lib:notify', src, { title = 'You already have an active supply run.', type = 'error', duration = 3000 })
        return
    end

    local now = os.time()
    local lastRun = supplyRunCooldowns[cid] or 0
    local remaining = Config.SupplyRun.cooldown - (now - lastRun)
    if remaining > 0 then
        local m = math.floor(remaining / 60)
        local s = remaining % 60
        TriggerClientEvent('ox_lib:notify', src, {
            title    = string.format('Supply run on cooldown — %dm %ds remaining.', m, s),
            type     = 'error',
            duration = 4000,
        })
        return
    end

    local loc    = Config.SupplyRun.Locations[math.random(#Config.SupplyRun.Locations)]
    local reward = math.random(Config.SupplyRun.rewardMin, Config.SupplyRun.rewardMax)

    activeRunPlayers[cid] = reward   -- store value, not just boolean
    TriggerClientEvent('fcrp_tuner:client:startSupplyRun', src, { x = loc.x, y = loc.y, z = loc.z }, reward)
    TriggerClientEvent('ox_lib:notify', src, { title = '🚚 Supply run dispatched! Follow the blip.', type = 'inform', duration = 5000 })
end)

RegisterNetEvent('fcrp_tuner:server:completeSupplyRun', function()
    local src    = source
    local Player = GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid

    if not activeRunPlayers[cid] then return end
    local safeReward        = activeRunPlayers[cid]  -- use server-stored value
    activeRunPlayers[cid]   = nil
    supplyRunCooldowns[cid] = os.time()
    exports.ox_inventory:AddItem(src, 'damaged_parts', safeReward)
    TriggerClientEvent('ox_lib:notify', src, {
        title    = string.format('✅ Run complete! Collected %d damaged parts.', safeReward),
        type     = 'success',
        duration = 6000,
    })
    LogDiscord('Supply Run Complete', string.format('**Parts Collected:** %d', safeReward), 65280, src)
end)

RegisterNetEvent('fcrp_tuner:server:cancelSupplyRun', function()
    local src    = source
    local Player = GetPlayer(src)
    if not Player then return end
    activeRunPlayers[Player.PlayerData.citizenid] = nil
end)

-- ─────────────────────────────────────────────
--  PD COMMANDS
-- ─────────────────────────────────────────────

lib.addCommand('checkchip', {
    help = 'Check if a nearby vehicle has an engine chip.',
}, function(src)
    local job = GetPlayer(src) and GetPlayer(src).PlayerData.job
    if not job or job.name ~= Config.PDJob then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Only police can use this command.', type = 'error', duration = 3000 })
        return
    end
    TriggerClientEvent('fcrp_tuner:client:checkChip', src)
end)

-- BUG FIX: removed `restricted = 'group.police'` — Qbox doesn't auto-assign ACE groups per job.
-- Now uses a manual job check matching /checkchip.
lib.addCommand('removechip', {
    help = 'Remove the engine chip from a nearby vehicle.',
}, function(src)
    local job = GetPlayer(src) and GetPlayer(src).PlayerData.job
    if not job or job.name ~= Config.PDJob then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Only police can use this command.', type = 'error', duration = 3000 })
        return
    end
    TriggerClientEvent('fcrp_tuner:client:pdRemoveChipRequest', src)
end)

-- NEW: full mod inspection for all tuner mods on a vehicle
lib.addCommand('inspectcar', {
    help = 'Inspect a nearby vehicle for all illegal tuner modifications.',
}, function(src)
    local job = GetPlayer(src) and GetPlayer(src).PlayerData.job
    if not job or job.name ~= Config.PDJob then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Only police can use this command.', type = 'error', duration = 3000 })
        return
    end
    TriggerClientEvent('fcrp_tuner:client:requestInspect', src)
end)

-- NEW: fake plate scanner
lib.addCommand('scanplate', {
    help = 'Scan a nearby vehicle to check for a fake plate.',
}, function(src)
    local job = GetPlayer(src) and GetPlayer(src).PlayerData.job
    if not job or job.name ~= Config.PDJob then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Only police can use this command.', type = 'error', duration = 3000 })
        return
    end
    TriggerClientEvent('fcrp_tuner:client:requestScanPlate', src)
end)

RegisterNetEvent('fcrp_tuner:server:checkChip', function(netId)
    local src   = source
    local plate = GetPlate(netId)
    if not plate then return end
    local row = MySQL.single.await('SELECT engine_chip FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    local has  = row and row.engine_chip == 1
    TriggerClientEvent('ox_lib:notify', src, {
        title    = has and ('🚨 Chip detected on ' .. plate) or ('✅ No chip on ' .. plate),
        type     = has and 'error' or 'success',
        duration = 5000,
    })
    LogDiscord('Chip Check', string.format('**Plate:** %s\n**Result:** %s', plate, has and 'CHIP FOUND' or 'Clean'), nil, src)
end)

RegisterNetEvent('fcrp_tuner:server:pdRemoveChip', function(netId)
    local src   = source
    local plate = GetPlate(netId)
    if not plate then return end
    MySQL.query.await('UPDATE fcrp_tuner_mods SET engine_chip = 0 WHERE plate = ?', { plate })
    TriggerClientEvent('fcrp_tuner:client:engineChipRemoved', -1, netId)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Engine chip removed from ' .. plate, type = 'success', duration = 5000 })
    LogDiscord('Engine Chip Removed (PD)', '**Plate:** ' .. plate, 16776960, src)
end)

RegisterNetEvent('fcrp_tuner:server:inspectVehicle', function(netId)
    local src   = source
    local plate = GetPlate(netId)
    if not plate then
        TriggerClientEvent('ox_lib:notify', src, { title = 'No vehicle found nearby.', type = 'error', duration = 3000 })
        return
    end
    local row = MySQL.single.await('SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row then
        TriggerClientEvent('ox_lib:notify', src, { title = '✅ ' .. plate .. ' — No illegal mods on record.', type = 'success', duration = 6000 })
        LogDiscord('Vehicle Inspected', string.format('**Plate:** %s\n**Result:** Clean', plate), 65280, src)
        return
    end
    local mods = {}
    if row.engine_chip  == 1 then mods[#mods+1] = '🔧 Engine Chip (+' .. Config.EngineChip.speedBoostPercent .. '% speed)' end
    if row.drift_chip   == 1 then mods[#mods+1] = '🚗 Drift Chip' end
    if row.nos          == 1 then
        local pct = math.floor((row.nos_pressure or 0) * 100)
        mods[#mods+1] = '🚀 Nitrous Kit (' .. pct .. '% pressure)'
    end
    if row.neon_mode        then mods[#mods+1] = '💡 Neon (' .. row.neon_mode .. ')' end
    if row.stance_camber    then mods[#mods+1] = '📐 Stance Kit' end
    if row.has_exhaust == 1 then mods[#mods+1] = '💨 Exhaust Mod' end
    if row.fake_plate       then mods[#mods+1] = '🪪 Fake Plate (real: ' .. plate .. ')' end

    if #mods == 0 then
        TriggerClientEvent('ox_lib:notify', src, { title = '✅ ' .. plate .. ' — No active mods.', type = 'success', duration = 6000 })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title       = '🚨 Illegal mods on ' .. plate,
            description = table.concat(mods, '  |  '),
            type        = 'error',
            duration    = 10000,
        })
    end
    LogDiscord('Vehicle Inspected', string.format('**Plate:** %s\n**Mods:** %s', plate, #mods > 0 and table.concat(mods, ', ') or 'Clean'), nil, src)
end)

RegisterNetEvent('fcrp_tuner:server:scanPlate', function(netId)
    local src = source
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'No vehicle found nearby.', type = 'error', duration = 3000 })
        return
    end
    local displayed = string.upper(string.gsub(GetVehicleNumberPlateText(veh), '%s+', ''))
    local realPlate = fakePlateCache[displayed]
    if realPlate then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = '🚨 Fake plate detected!',
            description = string.format('Displayed: **%s**  →  Real plate: **%s**', displayed, realPlate),
            type        = 'error',
            duration    = 8000,
        })
        LogDiscord('Fake Plate Detected', string.format('**Displayed:** %s\n**Real Plate:** %s', displayed, realPlate), 16711680, src)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title    = string.format('✅ Plate %s — appears legitimate.', displayed),
            type     = 'success',
            duration = 5000,
        })
    end
end)
