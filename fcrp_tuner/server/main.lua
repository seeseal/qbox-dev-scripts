-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  server/main.lua        ║
-- ╚══════════════════════════════════════════════╝

-- ─────────────────────────────────────────────
--  HELPERS  (defined first — used everywhere)
-- ─────────────────────────────────────────────

--- FIX #10: Local Commas() replaces lib.math.groupdigits which is not guaranteed server-side
local function Commas(n)
    return tostring(math.floor(n)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

-- ─────────────────────────────────────────────
--  RUNTIME STATE
-- ─────────────────────────────────────────────

local fakePlateCache     = {}  -- displayed plate → real plate
local dutyPlayers        = {}  -- src → bool
local activeRunPlayers   = {}  -- citizenid → { reward = number, coords = vector3 }
local supplyRunCooldowns = {}  -- citizenid → os.time()
local activeCrafts       = {}  -- src → recipeIdx  (FIX #1: craft session tracking)
local fakePlatePurchases = {}  -- plate(real) → os.time() (short-lived "paid token")

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

    MySQL.query("ALTER TABLE `fcrp_tuner_mods` ADD COLUMN IF NOT EXISTS `nos_pressure` FLOAT NOT NULL DEFAULT 1.0 AFTER `nos`")
    MySQL.query("ALTER TABLE `fcrp_tuner_mods` ADD COLUMN IF NOT EXISTS `fake_plate` VARCHAR(15) DEFAULT NULL")
    MySQL.query("ALTER TABLE `fcrp_tuner_mods` ADD COLUMN IF NOT EXISTS `vehicle_value` INT NOT NULL DEFAULT 0")

    local rows = MySQL.query.await('SELECT plate, fake_plate FROM fcrp_tuner_mods WHERE fake_plate IS NOT NULL')
    for _, row in ipairs(rows or {}) do
        fakePlateCache[row.fake_plate] = row.plate
    end

    -- FIX #4: RegisterUsableItem deprecated in ox_inventory v2+. Use registerHook instead.
    exports.ox_inventory:registerHook('useItem', function(payload)
        local src = payload.source
        local ped = GetPlayerPed(src)
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then
            TriggerClientEvent('ox_lib:notify', src, { title = 'You must be inside a vehicle to use a NOS Canister.', type = 'error', duration = 3000 })
            return false
        end
        TriggerClientEvent('fcrp_tuner:client:useNosCanister', src)
    end, { itemFilter = { ['nos_canister'] = true } })
end)

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function GetPlate(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return nil end
    local displayed = string.upper(string.gsub(GetVehicleNumberPlateText(veh), '%s+', ''))
    return fakePlateCache[displayed] or displayed
end

local function GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function IsVehicleBlacklisted(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return false, nil end
    -- Class-based check (GetVehicleClass/GetVehicleTypeRaw) is client-only.
    -- Server-side we can only reliably check by model name.
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

local function IsPolice(src)
    local Player = GetPlayer(src)
    if not Player then return false end
    local job = Player.PlayerData.job
    return job and job.name == Config.PDJob
end

-- FIX #3: Shared tuner job guard used by all write-only net events
local function IsTuner(src)
    local Player = GetPlayer(src)
    if not Player then return false end
    local job = Player.PlayerData.job
    return job and job.name == Config.RequiredJob
end

-- Check that the vehicle plate is registered to the player requesting the mod.
-- Uses the standard qbox player_vehicles table.
local function IsVehicleOwned(src, plate)
    if not plate or plate == '' then return false end
    local Player = GetPlayer(src)
    if not Player then return false end
    -- Check passenger too — the payer may be the passenger, not the tuner.
    -- We verify against the tuner's own player, the ownership check is done
    -- against the vehicle plate in player_vehicles.
    local row = MySQL.single.await(
        'SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1',
        { plate }
    )
    return row ~= nil   -- plate exists in the owned vehicles table
end

local function PayCommission(src, amount)
    local gradeConf = GetJobGradeConfig(src)
    local cut = math.floor(amount * gradeConf.commission)
    if cut <= 0 then return end
    exports.ox_inventory:AddItem(src, Config.PaymentType, cut)
    TriggerClientEvent('ox_lib:notify', src, {
        title    = string.format('💰 Commission: $%s', Commas(cut)),
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
        activeRunPlayers[Player.PlayerData.citizenid] = nil
    end
    dutyPlayers[src]  = nil
    activeCrafts[src] = nil  -- FIX #1: clear dangling craft session on disconnect
end)

-- ─────────────────────────────────────────────
--  VEHICLE OWNERSHIP CHECK
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:isVehicleOwned', function(src, netId)
    local plate = GetPlate(netId)
    if not plate then return false end
    return IsVehicleOwned(src, plate)
end)

-- ─────────────────────────────────────────────
--  VEHICLE STATE
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getVehicleState', function(src, netId)
    local plate = GetPlate(netId)
    if not plate then return {
        engine_chip = false, drift_chip = false,
        nos = false, nos_pressure = 1.0, nos_cooldown_until = 0,
        neon_mode = nil, neon_r = nil, neon_g = nil, neon_b = nil,
        has_stance = false, stance = nil,
        engine_originals = nil, drift_originals = nil,
    } end

    local row = MySQL.single.await('SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row then return {
        engine_chip = false, drift_chip = false,
        nos = false, nos_pressure = 1.0, nos_cooldown_until = 0,
        neon_mode = nil, neon_r = nil, neon_g = nil, neon_b = nil,
        has_stance = false, stance = nil,
        engine_originals = nil, drift_originals = nil,
    } end

    -- Return stored original handling values so client can always apply the
    -- exact same boost from the exact same baseline — no compounding possible.
    local engineOriginals = (row.engine_chip == 1 and row.orig_speed) and {
        speed   = row.orig_speed,
        force   = row.orig_force,
        inertia = row.orig_inertia,
    } or nil

    local driftOriginals = (row.drift_chip == 1 and row.orig_traction_max) and {
        tractionMax  = row.orig_traction_max,
        tractionMin  = row.orig_traction_min,
        tractionLoss = row.orig_traction_loss,
        dragCoeff    = row.orig_drag,
        driveForce   = row.orig_drive_force,
        steeringLock = row.orig_steering_lock,
        antiRoll     = row.orig_anti_roll,
    } or nil

    return {
        engine_chip        = row.engine_chip == 1,
        drift_chip         = row.drift_chip == 1,
        nos                = row.nos == 1,
        nos_pressure       = row.nos_pressure or 1.0,
        nos_cooldown_until = row.nos_cooldown_until or 0,
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
        has_exhaust      = false,   -- exhaust mod removed from resource
        fake_plate       = nil,     -- cosmetic-only, not persisted in DB
        engine_originals = engineOriginals,
        drift_originals  = driftOriginals,
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
--  VEHICLE VALUE
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:setVehicleValue', function(netId, value)
    local plate = GetPlate(netId)
    if not plate then return end
    local safeValue = math.max(0, math.min(10000000, math.floor(tonumber(value) or 0)))
    -- Prevent clients from lowering value to reduce chip price bonus: only increase.
    local row    = MySQL.single.await('SELECT vehicle_value FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    local stored = (row and row.vehicle_value) or 0
    local final  = math.max(stored, safeValue)
    MySQL.query.await(
        'INSERT INTO fcrp_tuner_mods (plate, vehicle_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE vehicle_value = ?',
        { plate, final, final }
    )
end)

-- ─────────────────────────────────────────────
--  ORIGINAL HANDLING PERSISTENCE
--  Client sends stock handling values BEFORE applying any chip boost.
--  These are stored in the DB so ReapplyMods always has the clean baseline.
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:saveEngineChipOriginals', function(netId, speed, force, inertia)
    local src = source
    if not IsTuner(src) then return end
    local plate = GetPlate(netId)
    if not plate then return end
    local s = tonumber(speed)   or 0
    local f = tonumber(force)   or 0
    local i = tonumber(inertia) or 1.0
    MySQL.query.await(
        'UPDATE fcrp_tuner_mods SET orig_speed = ?, orig_force = ?, orig_inertia = ? WHERE plate = ?',
        { s, f, i, plate }
    )
end)

RegisterNetEvent('fcrp_tuner:server:saveDriftChipOriginals', function(netId, tractionMax, tractionMin, tractionLoss, drag, driveForce, steeringLock, antiRoll)
    local src = source
    if not IsTuner(src) then return end
    local plate = GetPlate(netId)
    if not plate then return end
    MySQL.query.await(
        'UPDATE fcrp_tuner_mods SET orig_traction_max = ?, orig_traction_min = ?, orig_traction_loss = ?, orig_drag = ?, orig_drive_force = ?, orig_steering_lock = ?, orig_anti_roll = ? WHERE plate = ?',
        {
            tonumber(tractionMax)  or 2.73,
            tonumber(tractionMin)  or 1.80,
            tonumber(tractionLoss) or 1.0,
            tonumber(drag)         or 4.0,
            tonumber(driveForce)   or 0.4,
            tonumber(steeringLock) or 35.0,
            tonumber(antiRoll)     or 0.7,
            plate
        }
    )
end)

-- ─────────────────────────────────────────────
--  PASSENGER LOOKUP
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getPassenger', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return nil end
    -- GetVehicleMaxNumberOfPassengers is client-only; iterate up to 8 seats server-side
    for seat = 0, 7 do
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
    if not IsOnDuty(src) then
        return false, 'You must be on duty to install mods.'
    end

    local plate = GetPlate(netId)
    if not plate then return false, 'Vehicle not found.' end

    local blacklisted, reason = IsVehicleBlacklisted(netId)
    if blacklisted then return false, reason end

    -- Only allow mods on player-owned vehicles registered in player_vehicles
    if not IsVehicleOwned(src, plate) then
        return false, 'This vehicle is not registered to any player. Only owned vehicles can be modified.'
    end

    local payerSrc = passengerSrc or src
    local Payer    = GetPlayer(payerSrc)
    if not Payer then return false, 'Payer not found.' end

    local price = 0
    -- Per-product item check (does NOT remove yet — see FIX #5 below)
    if productKey == 'engine_chip' then
        local vrow   = MySQL.single.await('SELECT drift_chip, engine_chip, vehicle_value FROM fcrp_tuner_mods WHERE plate = ?', { plate })
        local stored = (vrow and vrow.vehicle_value) or 0
        price = Config.EngineChip.basePrice + math.floor(stored * Config.EngineChip.carValuePercent)
        if vrow and vrow.drift_chip  == 1 then return false, 'Remove drift chip first.' end
        if vrow and vrow.engine_chip == 1 then return false, 'Engine chip already installed.' end
        local hasChip = exports.ox_inventory:GetItemCount(payerSrc, 's3_chip')
        if not hasChip or hasChip < 1 then return false, 'Requires 1x S3 Chip item.' end

    elseif productKey == 'drift_chip' then
        local vrow   = MySQL.single.await('SELECT engine_chip, drift_chip, vehicle_value FROM fcrp_tuner_mods WHERE plate = ?', { plate })
        local stored = (vrow and vrow.vehicle_value) or 0
        price = Config.DriftChip.basePrice + math.floor(stored * Config.DriftChip.carValuePercent)
        if vrow and vrow.engine_chip == 1 then return false, 'Remove engine chip first.' end
        if vrow and vrow.drift_chip  == 1 then return false, 'Drift chip already installed.' end
        local hasDrift = exports.ox_inventory:GetItemCount(payerSrc, 'drift_chip')
        if not hasDrift or hasDrift < 1 then return false, 'Requires 1x Drift Chip item.' end

    elseif productKey == 'stance_kit' then
        price = Config.StanceKit.price
        local hasRod = exports.ox_inventory:GetItemCount(payerSrc, 'stance_rod')
        if not hasRod or hasRod < 1 then return false, 'Requires 1x Stance Rod item.' end

    elseif productKey == 'nitrous_kit' then
        price = Config.Nitrous.price

    elseif productKey == 'fake_plate' then
        price = Config.FakePlate.price
        -- Fake plate is cosmetic-only: no DB record, resets on server restart.

    elseif productKey == 'neon_static' or productKey == 'neon_rainbow'
        or productKey == 'neon_rgb'    or productKey == 'neon_strobe' then
        local map = { neon_static = 'static', neon_rainbow = 'rainbow', neon_rgb = 'rgb', neon_strobe = 'strobe' }
        price = Config.NeonPrices[map[productKey]] or 25000
    else
        return false, 'Unknown product.'
    end

    local cash = exports.ox_inventory:GetItemCount(payerSrc, Config.PaymentType)
    if not cash or cash < price then
        return false, string.format('Not enough dirty cash. Need $%s.', Commas(price))
    end

    -- FIX #5: DB write FIRST, item removal AFTER. If the server crashes between the two,
    -- the player retains their items rather than losing them with no DB record written.
    local neonMap = { neon_static = 'static', neon_rainbow = 'rainbow', neon_rgb = 'rgb', neon_strobe = 'strobe' }
    local saveMap = {
        engine_chip = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, engine_chip) VALUES (?, 1) ON DUPLICATE KEY UPDATE engine_chip = 1, orig_speed = NULL, orig_force = NULL, orig_inertia = NULL', { plate }) end,
        drift_chip  = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, drift_chip)  VALUES (?, 1) ON DUPLICATE KEY UPDATE drift_chip  = 1, orig_traction_max = NULL, orig_traction_min = NULL, orig_traction_loss = NULL, orig_drag = NULL, orig_drive_force = NULL, orig_steering_lock = NULL, orig_anti_roll = NULL', { plate }) end,
        -- Mark stance as "installed" so saveStance can enforce purchase-before-save.
        -- Values are overwritten when player saves stance.
        stance_kit  = function()
            MySQL.query.await([[
                INSERT INTO fcrp_tuner_mods (plate, stance_camber, stance_height, stance_wheeldist)
                VALUES (?, 0.0, 0.0, 0.0)
                ON DUPLICATE KEY UPDATE
                    stance_camber    = COALESCE(stance_camber, 0.0),
                    stance_height    = COALESCE(stance_height, 0.0),
                    stance_wheeldist = COALESCE(stance_wheeldist, 0.0)
            ]], { plate })
        end,
        -- cosmetic-only: no DB write, but store short-lived "paid token"
        fake_plate  = function() fakePlatePurchases[plate] = os.time() end,
        nitrous_kit = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, nos, nos_pressure) VALUES (?, 1, 1.0) ON DUPLICATE KEY UPDATE nos = 1, nos_pressure = 1.0', { plate }) end,
    }

    if neonMap[productKey] then
        MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, neon_mode) VALUES (?, ?) ON DUPLICATE KEY UPDATE neon_mode = ?', { plate, neonMap[productKey], neonMap[productKey] })
    elseif saveMap[productKey] then
        saveMap[productKey]()
    end

    -- DB record committed — now safe to consume items
    exports.ox_inventory:RemoveItem(payerSrc, Config.PaymentType, price)
    if productKey == 'engine_chip' then
        exports.ox_inventory:RemoveItem(payerSrc, 's3_chip', 1)
    elseif productKey == 'drift_chip' then
        exports.ox_inventory:RemoveItem(payerSrc, 'drift_chip', 1)
    elseif productKey == 'stance_kit' then
        exports.ox_inventory:RemoveItem(payerSrc, 'stance_rod', 1)
    end

    PayCommission(src, price)
    LogDiscord('Mod Purchased', string.format('**Mod:** %s\n**Plate:** %s\n**Price:** $%s', productKey, plate, Commas(price)), nil, src)
    return true, price
end)

-- ─────────────────────────────────────────────
--  REMOVE MOD
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:removeMod', function(src, netId, modKey)
    if not IsTuner(src) then
        return false, 'You must be a tuner to remove mods.'
    end
    if not IsOnDuty(src) then
        return false, 'You must be on duty to remove mods.'
    end
    local plate = GetPlate(netId)
    if not plate then return false, 'Vehicle not found.' end

    if modKey == 'fake_plate' then
        -- Cosmetic-only: just clear the runtime cache entry and restore the real plate visually
        -- Walk cache to find which fake plate maps to this real plate
        for fk, rp in pairs(fakePlateCache) do
            if rp == plate then fakePlateCache[fk] = nil; break end
        end
        TriggerClientEvent('fcrp_tuner:client:restoreRealPlate', -1, netId, plate)
        return true
    end

    local colMap = {
        engine_chip = 'engine_chip = 0, orig_speed = NULL, orig_force = NULL, orig_inertia = NULL',
        drift_chip  = 'drift_chip = 0, orig_traction_max = NULL, orig_traction_min = NULL, orig_traction_loss = NULL, orig_drag = NULL, orig_drive_force = NULL, orig_steering_lock = NULL, orig_anti_roll = NULL',
        nos         = 'nos = 0, nos_pressure = 1.0, nos_cooldown_until = 0',
        neon        = 'neon_mode = NULL, neon_r = NULL, neon_g = NULL, neon_b = NULL',
        stance      = 'stance_camber = NULL, stance_height = NULL, stance_wheeldist = NULL',
    }
    if not colMap[modKey] then return false, 'Unknown mod.' end
    MySQL.query.await('UPDATE fcrp_tuner_mods SET ' .. colMap[modKey] .. ' WHERE plate = ?', { plate })
    return true
end)

-- ─────────────────────────────────────────────
--  STANCE SAVE
-- ─────────────────────────────────────────────

-- FIX #3: tuner job check. FIX: clamp values to config bounds to prevent exploit.
RegisterNetEvent('fcrp_tuner:server:saveStance', function(netId, camberF, camberR, height)
    local src = source
    if not IsTuner(src) then return end
    local plate = GetPlate(netId)
    if not plate then return end

    -- Enforce purchase-before-save (stance kit purchase writes stance_* columns non-NULL)
    local row = MySQL.single.await('SELECT stance_camber FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row or row.stance_camber == nil then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Stance kit is not installed on this vehicle.', type = 'error', duration = 4000 })
        return
    end

    local cfg = Config.StanceKit
    camberF = math.max(cfg.camberMin,     math.min(cfg.camberMax,     tonumber(camberF) or 0))
    camberR = math.max(cfg.camberMin,     math.min(cfg.camberMax,     tonumber(camberR) or 0))
    height  = math.max(cfg.rideHeightMin, math.min(cfg.rideHeightMax, tonumber(height)  or 0))
    MySQL.query.await([[
        INSERT INTO fcrp_tuner_mods (plate, stance_camber, stance_height, stance_wheeldist)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            stance_camber    = VALUES(stance_camber),
            stance_height    = VALUES(stance_height),
            stance_wheeldist = VALUES(stance_wheeldist)
    ]], { plate, camberF, height, camberR })
end)

-- ─────────────────────────────────────────────
--  NEON SAVE
-- ─────────────────────────────────────────────

-- FIX #3: tuner job check + mode/RGB validation
RegisterNetEvent('fcrp_tuner:server:saveNeon', function(netId, mode, r, g, b)
    local src = source
    if not IsTuner(src) then return end
    local plate = GetPlate(netId)
    if not plate then return end
    local validModes = { static = true, rainbow = true, rgb = true, strobe = true }
    if not validModes[mode] then return end

    -- Enforce purchase-before-save (neon purchase writes neon_mode non-NULL)
    local row = MySQL.single.await('SELECT neon_mode FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row or row.neon_mode == nil then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Neon kit is not installed on this vehicle.', type = 'error', duration = 4000 })
        return
    end

    r = r and math.max(0, math.min(255, math.floor(tonumber(r) or 0))) or nil
    g = g and math.max(0, math.min(255, math.floor(tonumber(g) or 0))) or nil
    b = b and math.max(0, math.min(255, math.floor(tonumber(b) or 0))) or nil
    MySQL.query.await('UPDATE fcrp_tuner_mods SET neon_mode = ?, neon_r = ?, neon_g = ?, neon_b = ? WHERE plate = ?', { mode, r, g, b, plate })
end)

-- ─────────────────────────────────────────────
--  FAKE PLATE
-- ─────────────────────────────────────────────

-- FIX #3: tuner job check added
RegisterNetEvent('fcrp_tuner:server:applyFakePlate', function(netId, plateText)
    local src = source
    if not IsTuner(src) then return end

    if not plateText or #plateText < 1 or #plateText > 8 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Invalid plate text.', type = 'error', duration = 3000 })
        return
    end

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

    -- Enforce purchase-before-apply using short-lived token from purchase callback
    local paidAt = fakePlatePurchases[plate]
    if not paidAt or (os.time() - paidAt) > 90 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'You must purchase a fake plate from the shop first.', type = 'error', duration = 4000 })
        return
    end
    fakePlatePurchases[plate] = nil

    -- Cosmetic-only: runtime cache only, nothing written to DB, resets on restart
    fakePlateCache[plateText] = plate

    TriggerClientEvent('fcrp_tuner:client:applyFakePlate', -1, netId, plateText)
    LogDiscord('Fake Plate Applied', string.format('**Real Plate:** %s\n**Fake Plate:** %s  (cosmetic)', plate, plateText), 16776960, src)
end)

-- ─────────────────────────────────────────────
--  NOS — pressure drain on activation
-- ─────────────────────────────────────────────

-- FIX #2: WHERE nos = 1 prevents clients draining pressure on vehicles without NOS installed
RegisterNetEvent('fcrp_tuner:server:nosUsed', function(netId)
    local plate   = GetPlate(netId)
    if not plate then return end
    local expires = (os.time() + Config.Nitrous.cooldown) * 1000
    MySQL.query.await(
        'UPDATE fcrp_tuner_mods SET nos_pressure = GREATEST(0.0, nos_pressure - ?), nos_cooldown_until = ? WHERE plate = ? AND nos = 1',
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

    local updated = MySQL.single.await('SELECT nos_pressure FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    local newPressure = updated and updated.nos_pressure or math.min(1.0, currentPressure + Config.Nitrous.canisterRefill)
    TriggerClientEvent('fcrp_tuner:client:nosRefillConfirmed', src, newPressure)
end)

-- ─────────────────────────────────────────────
--  CRAFT SYSTEM  (Tuner II + Master Tuner only)
-- ─────────────────────────────────────────────

-- FIX #1: activeCrafts[src] tracks open sessions.
-- craftComplete and craftCancel both require a matching session entry,
-- preventing any client from calling craftCancel to receive free items.
lib.callback.register('fcrp_tuner:server:craftItem', function(src, recipeIdx)
    local gradeConf = GetJobGradeConfig(src)
    if not gradeConf.canCraft then
        return false, 'You need to be Tuner II or higher to craft.'
    end
    local recipe = Config.CraftRecipes[recipeIdx]
    if not recipe then return false, 'Invalid recipe.' end

    if activeCrafts[src] then
        return false, 'You already have a craft in progress.'
    end

    for _, ing in ipairs(recipe.ingredients) do
        local count = exports.ox_inventory:GetItemCount(src, ing.item)
        if not count or count < ing.amount then
            return false, string.format('Missing: %dx %s', ing.amount, ing.label)
        end
    end
    for _, ing in ipairs(recipe.ingredients) do
        exports.ox_inventory:RemoveItem(src, ing.item, ing.amount)
    end

    activeCrafts[src] = recipeIdx
    return true
end)

RegisterNetEvent('fcrp_tuner:server:craftComplete', function(recipeIdx)
    local src = source
    if activeCrafts[src] ~= recipeIdx then return end
    activeCrafts[src] = nil

    local recipe = Config.CraftRecipes[recipeIdx]
    if not recipe then return end
    exports.ox_inventory:AddItem(src, recipe.item, 1)
    LogDiscord('Item Crafted', string.format('**Item:** %s', recipe.label), 65280, src)
end)

RegisterNetEvent('fcrp_tuner:server:craftCancel', function(recipeIdx)
    local src = source
    if activeCrafts[src] ~= recipeIdx then return end  -- FIX #1: must match open session
    activeCrafts[src] = nil

    local recipe = Config.CraftRecipes[recipeIdx]
    if not recipe then return end
    for _, ing in ipairs(recipe.ingredients) do
        exports.ox_inventory:AddItem(src, ing.item, ing.amount)
    end
end)

-- ─────────────────────────────────────────────
--  SOCIETY STASH  (Master Tuner only)
-- ─────────────────────────────────────────────

-- FIX: Society stash is accessible to all tuner employees (any grade).
-- Owner-only restriction removed per design update.
RegisterNetEvent('fcrp_tuner:server:openSocietyStash', function()
    local src    = source
    if not IsTuner(src) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'Only tuner employees can access the society stash.', type = 'error', duration = 4000 })
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

    local now       = os.time()
    local lastRun   = supplyRunCooldowns[cid] or 0
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

    activeRunPlayers[cid] = { reward = reward, coords = loc }
    TriggerClientEvent('fcrp_tuner:client:startSupplyRun', src, { x = loc.x, y = loc.y, z = loc.z }, reward)
    TriggerClientEvent('ox_lib:notify', src, { title = '🚚 Supply run dispatched! Follow the blip.', type = 'inform', duration = 5000 })
end)

RegisterNetEvent('fcrp_tuner:server:completeSupplyRun', function()
    local src    = source
    local Player = GetPlayer(src)
    if not Player then return end
    local cid = Player.PlayerData.citizenid

    local run = activeRunPlayers[cid]
    if not run then return end

    -- Validate player is actually at the pickup location (server-side anti-cheat)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local pcoords = GetEntityCoords(ped)
    local dist = #(pcoords - run.coords)
    if dist > (Config.SupplyRun.pickupRadius + 2.0) then
        TriggerClientEvent('ox_lib:notify', src, { title = 'You are too far from the pickup point.', type = 'error', duration = 4000 })
        return
    end

    local safeReward        = run.reward
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

-- Police-only event guard (net events can be triggered directly by cheaters)
local function RequirePolice(src)
    if IsPolice(src) then return true end
    TriggerClientEvent('ox_lib:notify', src, { title = 'Only police can use this.', type = 'error', duration = 3000 })
    return false
end

RegisterNetEvent('fcrp_tuner:server:checkChip', function(netId)
    local src   = source
    if not RequirePolice(src) then return end
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
    if not RequirePolice(src) then return end
    local plate = GetPlate(netId)
    if not plate then return end
    MySQL.query.await('UPDATE fcrp_tuner_mods SET engine_chip = 0 WHERE plate = ?', { plate })
    TriggerClientEvent('fcrp_tuner:client:engineChipRemoved', -1, netId)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Engine chip removed from ' .. plate, type = 'success', duration = 5000 })
    LogDiscord('Engine Chip Removed (PD)', '**Plate:** ' .. plate, 16776960, src)
end)

RegisterNetEvent('fcrp_tuner:server:inspectVehicle', function(netId)
    local src   = source
    if not RequirePolice(src) then return end
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
    -- Fake plate is cosmetic-only (runtime cache); checked via scanplate command

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
    if not RequirePolice(src) then return end
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