-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  server/main.lua        ║
-- ╚══════════════════════════════════════════════╝

local cooldowns = {}
local COOLDOWN  = 3000  -- ms between purchases (anti-spam)

-- ─────────────────────────────────────────────
--  DB SETUP
-- ─────────────────────────────────────────────

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS fcrp_tuner_mods (
            plate              VARCHAR(12)      NOT NULL,
            engine_chip        TINYINT(1)       NOT NULL DEFAULT 0,
            drift_chip         TINYINT(1)       NOT NULL DEFAULT 0,
            nos                TINYINT(1)       NOT NULL DEFAULT 0,
            nos_cooldown       BIGINT           NOT NULL DEFAULT 0,
            nos_empty          TINYINT(1)       NOT NULL DEFAULT 0,
            nos_active         TINYINT(1)       NOT NULL DEFAULT 0,
            neon_mode          VARCHAR(16)      DEFAULT NULL,
            neon_r             TINYINT UNSIGNED DEFAULT NULL,
            neon_g             TINYINT UNSIGNED DEFAULT NULL,
            neon_b             TINYINT UNSIGNED DEFAULT NULL,
            stance_camber      FLOAT            DEFAULT NULL,
            stance_height      FLOAT            DEFAULT NULL,
            stance_wheeldist   FLOAT            DEFAULT NULL,
            PRIMARY KEY (plate)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    MySQL.query([[
        ALTER TABLE fcrp_tuner_mods
        ADD COLUMN IF NOT EXISTS nos_empty TINYINT(1) NOT NULL DEFAULT 0;
    ]])
end)

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function HasJob(src, job)
    local Player = exports.qbx_core:GetPlayer(src)
    return Player and Player.PlayerData.job and Player.PlayerData.job.name == job
end

local function GetServerPrice(productKey)
    local prices = {
        stance_kit     = Config.StanceKit.price,
        nitrous_kit    = Config.Nitrous.price,
        nitrous_refill = Config.Nitrous.refillPrice,
        neon_static    = Config.NeonPrices.static,
        neon_rainbow   = Config.NeonPrices.rainbow,
        neon_rgb       = Config.NeonPrices.rgb,
        neon_strobe    = Config.NeonPrices.strobe,
    }
    return prices[productKey]
end

local function GetOrCreateRow(plate)
    local row = MySQL.single.await(
        'SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate }
    )
    if not row then
        MySQL.insert.await(
            'INSERT INTO fcrp_tuner_mods (plate) VALUES (?)', { plate }
        )
        row = MySQL.single.await(
            'SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate }
        )
    end
    return row
end

local function SendDiscordLog(title, description, colour)
    if not Config.DiscordWebhook or Config.DiscordWebhook == '' then return end
    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST',
        json.encode({
            embeds = {{
                title       = title,
                description = description,
                color       = colour or Config.DiscordColour,
                footer      = { text = os.date('%Y-%m-%d %H:%M:%S') },
            }}
        }),
        { ['Content-Type'] = 'application/json' }
    )
end

local function Log(label, msg, src)
    print(('[fcrp_tuner] [%s] %s'):format(label, msg))
    SendDiscordLog(label, msg .. '\n**Player:** ' .. (GetPlayerName(src) or 'unknown') .. ' (src:' .. tostring(src) .. ')')
end

local function CharName(Player)
    local ci = Player.PlayerData.charinfo
    return ci.firstname .. ' ' .. ci.lastname
end

local function ClientNotify(src, msg, ntype, duration)
    TriggerClientEvent('ox_lib:notify', src, {
        title    = msg,
        type     = ntype or 'inform',
        duration = duration or 4000,
    })
end

-- ─────────────────────────────────────────────
--  GET PASSENGER
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getPassenger', function(source, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return nil end
    local driverPed = GetPedInVehicleSeat(veh, -1)
    for seat = 0, 5 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and ped ~= driverPed then
            for _, pid in ipairs(GetPlayers()) do
                if GetPlayerPed(tonumber(pid)) == ped then
                    return tonumber(pid)
                end
            end
        end
    end
    return nil
end)

-- ─────────────────────────────────────────────
--  GET VEHICLE STATE
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getVehicleState', function(source, netId)
    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return nil end
    plate = plate:gsub('%s+', '')
    local row = GetOrCreateRow(plate)
    local nowSec = os.time()
    local nosReady = (row.nos_cooldown or 0) <= nowSec
    local nosCooldownRemaining = math.max(0, (row.nos_cooldown or 0) - nowSec)
    return {
        engine_chip        = row.engine_chip  == 1 or row.engine_chip  == true,
        drift_chip         = row.drift_chip   == 1 or row.drift_chip   == true,
        nos                = row.nos          == 1 or row.nos          == true,
        nos_ready          = nosReady,
        nos_empty          = row.nos_empty    == 1 or row.nos_empty    == true,
        nos_cooldown_until = nosCooldownRemaining,
        neon_mode          = row.neon_mode,
        neon_r             = row.neon_r,
        neon_g             = row.neon_g,
        neon_b             = row.neon_b,
        has_stance         = row.stance_camber ~= nil,
        stance             = {
            camber    = row.stance_camber,
            height    = row.stance_height,
            wheeldist = row.stance_wheeldist,
        },
    }
end)

-- ─────────────────────────────────────────────
--  CHIP PRICES
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getEngineChipPrice', function(source, netId)
    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return Config.EngineChip.basePrice, 0, 0 end
    plate = plate:gsub('%s+', '')
    local result = MySQL.single.await('SELECT depotprice FROM player_vehicles WHERE plate = ?', { plate })
    local depotValue = result and result.depotprice or 0
    local bonus = math.floor(depotValue * Config.EngineChip.carValuePercent)
    local price = Config.EngineChip.basePrice + bonus
    return price, depotValue, bonus
end)

lib.callback.register('fcrp_tuner:server:getDriftChipPrice', function(source, netId)
    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return Config.DriftChip.basePrice, 0, 0 end
    plate = plate:gsub('%s+', '')
    local result = MySQL.single.await('SELECT depotprice FROM player_vehicles WHERE plate = ?', { plate })
    local depotValue = result and result.depotprice or 0
    local bonus = math.floor(depotValue * Config.DriftChip.carValuePercent)
    local price = Config.DriftChip.basePrice + bonus
    return price, depotValue, bonus
end)

-- ─────────────────────────────────────────────
--  PURCHASE CALLBACK
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:purchase', function(source, productKey, clientPrice, passengerSrc, netId)
    local src    = source
    local Driver = exports.qbx_core:GetPlayer(src)
    if not Driver then return false, Lang:t('transaction_failed') end

    if not HasJob(src, Config.RequiredJob) then
        return false, Lang:t('access_denied')
    end

    local now = GetGameTimer()
    if cooldowns[src] and (now - cooldowns[src]) < COOLDOWN then
        return false, Lang:t('slow_down')
    end

    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return false, Lang:t('transaction_failed') end
    plate = plate:gsub('%s+', '')

    local row = GetOrCreateRow(plate)

    -- ── Per-vehicle duplicate / conflict checks ──────
    if productKey == 'engine_chip' then
        if row.engine_chip == 1 or row.engine_chip == true then return false, Lang:t('engine_chip_already') end
        if row.drift_chip  == 1 or row.drift_chip  == true then return false, Lang:t('engine_chip_conflict') end
        local count = exports.ox_inventory:GetItemCount(src, 's3_chip')
        if count < 1 then
            return false, '🔧 You need an S3 Chip item in your inventory to install this.'
        end
    elseif productKey == 'drift_chip' then
        if row.drift_chip  == 1 or row.drift_chip  == true then return false, Lang:t('drift_chip_already') end
        if row.engine_chip == 1 or row.engine_chip == true then return false, Lang:t('drift_chip_conflict') end
        local count = exports.ox_inventory:GetItemCount(src, 'drift_chip')
        if count < 1 then
            return false, '🏎️ You need a Drift Chip item in your inventory to install this.'
        end
    elseif productKey == 'stance_kit' then
        local count = exports.ox_inventory:GetItemCount(src, 'stance_rod')
        if count < 1 then
            return false, '📐 You need a Stance Rod item in your inventory to install this.'
        end
    elseif productKey == 'nitrous_kit' then
        if row.nos == 1 or row.nos == true then return false, Lang:t('nos_already') end
    elseif productKey == 'nitrous_refill' then
        if not (row.nos == 1 or row.nos == true) then return false, Lang:t('nos_not_installed') end
        local nowSec = os.time()
        if (row.nos_cooldown or 0) > nowSec then
            local remaining = math.ceil((row.nos_cooldown - nowSec) / 60)
            return false, 'NOS is on cooldown. ' .. remaining .. ' min remaining.'
        end
    end

    -- ── Price ────────────────────────────────────────
    local price
    if productKey == 'engine_chip' then
        local result = MySQL.single.await('SELECT depotprice FROM player_vehicles WHERE plate = ?', { plate })
        local depotValue = result and result.depotprice or 0
        local bonus = math.floor(depotValue * Config.EngineChip.carValuePercent)
        price = Config.EngineChip.basePrice + bonus
    elseif productKey == 'drift_chip' then
        local result = MySQL.single.await('SELECT depotprice FROM player_vehicles WHERE plate = ?', { plate })
        local depotValue = result and result.depotprice or 0
        local bonus = math.floor(depotValue * Config.DriftChip.carValuePercent)
        price = Config.DriftChip.basePrice + bonus
    else
        price = GetServerPrice(productKey)
        if not price then
            print('[fcrp_tuner] Unknown product: ' .. tostring(productKey))
            return false, Lang:t('unknown_product')
        end
    end

    -- ── Payer (passenger or driver) ──────────────────
    local payerSrc = (passengerSrc and tonumber(passengerSrc)) or src
    local Payer    = exports.qbx_core:GetPlayer(payerSrc) or Driver

    local balance = exports.ox_inventory:GetItemCount(payerSrc, Config.PaymentType)

    if balance < price then
        local shortfall = price - balance
        local payerName = CharName(Payer)
        local whoLabel  = (payerSrc == src) and 'You are' or (payerName .. ' is')
        return false, '💸 Insufficient balance — ' .. whoLabel .. ' short $' .. lib.math.groupdigits(shortfall) .. ' dirty cash.'
    end

    exports.ox_inventory:RemoveItem(payerSrc, Config.PaymentType, price)
    cooldowns[src] = now

    -- ── DB write ─────────────────────────────────────
    if productKey == 'engine_chip' then
        MySQL.update.await('UPDATE fcrp_tuner_mods SET engine_chip = 1 WHERE plate = ?', { plate })
        exports.ox_inventory:RemoveItem(src, 's3_chip', 1)
    elseif productKey == 'drift_chip' then
        MySQL.update.await('UPDATE fcrp_tuner_mods SET drift_chip = 1 WHERE plate = ?', { plate })
        exports.ox_inventory:RemoveItem(src, 'drift_chip', 1)
    elseif productKey == 'stance_kit' then
        MySQL.update.await('UPDATE fcrp_tuner_mods SET stance_kit = 1 WHERE plate = ?', { plate })
        exports.ox_inventory:RemoveItem(src, 'stance_rod', 1)
    elseif productKey == 'nitrous_kit' then
        MySQL.update.await('UPDATE fcrp_tuner_mods SET nos = 1, nos_cooldown = 0 WHERE plate = ?', { plate })
    elseif productKey == 'nitrous_refill' then
        MySQL.update.await('UPDATE fcrp_tuner_mods SET nos_cooldown = 0 WHERE plate = ?', { plate })
    end

    local logMsg = string.format('**%s** installed **%s** on plate **%s** | $%d charged to **%s**',
        CharName(Driver), productKey, plate, price, CharName(Payer))
    Log('Tuner Purchase', logMsg, src)

    return true, price
end)

-- ─────────────────────────────────────────────
--  NOS REFILL STATION
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:nosStationRefill', function(source, netId)
    local src    = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false, Lang:t('transaction_failed') end

    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return false, Lang:t('transaction_failed') end
    plate = plate:gsub('%s+', '')

    local row = MySQL.single.await('SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate })

    if not row or not (row.nos == 1 or row.nos == true) then
        return false, Lang:t('nos_not_installed')
    end

    local nowSec = os.time()
    if (row.nos_cooldown or 0) > nowSec then
        local remaining = math.ceil((row.nos_cooldown - nowSec) / 60)
        return false, Lang:t('nos_cooldown', { remaining })
    end

    local price   = Config.Nitrous.refillPrice
    local balance = exports.ox_inventory:GetItemCount(src, Config.PaymentType)

    if balance < price then
        local shortfall = price - balance
        return false, '💸 Short $' .. lib.math.groupdigits(shortfall) .. ' dirty cash.'
    end

    exports.ox_inventory:RemoveItem(src, Config.PaymentType, price)
    MySQL.update.await('UPDATE fcrp_tuner_mods SET nos_cooldown = 0, nos_empty = 0 WHERE plate = ?', { plate })

    local logMsg = string.format('**%s** refilled NOS on plate **%s** at station | $%d',
        CharName(Player), plate, price)
    Log('NOS Refill (Station)', logMsg, src)

    return true, price
end)

-- ─────────────────────────────────────────────
--  NOS COOLDOWN
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:nosUsed', function(netId)
    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return end
    plate = plate:gsub('%s+', '')
    local cooldownUntil = os.time() + Config.Nitrous.cooldown
    MySQL.update.await('UPDATE fcrp_tuner_mods SET nos_cooldown = ?, nos_empty = 1 WHERE plate = ?',
        { cooldownUntil, plate })
end)

-- ─────────────────────────────────────────────
--  SAVE NEON
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:saveNeon', function(netId, mode, r, g, b)
    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return end
    plate = plate:gsub('%s+', '')
    GetOrCreateRow(plate)
    MySQL.update.await(
        'UPDATE fcrp_tuner_mods SET neon_mode = ?, neon_r = ?, neon_g = ?, neon_b = ? WHERE plate = ?',
        { mode, r, g, b, plate }
    )
end)

-- ─────────────────────────────────────────────
--  SAVE STANCE
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:saveStance', function(netId, camber, height, wheeldist)
    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return end
    plate = plate:gsub('%s+', '')
    GetOrCreateRow(plate)
    MySQL.update.await(
        'UPDATE fcrp_tuner_mods SET stance_camber = ?, stance_height = ?, stance_wheeldist = ? WHERE plate = ?',
        { camber, height, wheeldist, plate }
    )
end)

-- ─────────────────────────────────────────────
--  REMOVE MOD
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:removeMod', function(source, netId, modKey)
    local src    = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return false end
    if not HasJob(src, Config.RequiredJob) then return false, Lang:t('access_denied') end

    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return false end
    plate = plate:gsub('%s+', '')

    local row = GetOrCreateRow(plate)

    if modKey == 'engine_chip' then
        if not (row.engine_chip == 1 or row.engine_chip == true) then return false, Lang:t('engine_chip_no_chip') end
        MySQL.update.await('UPDATE fcrp_tuner_mods SET engine_chip = 0 WHERE plate = ?', { plate })
    elseif modKey == 'drift_chip' then
        if not (row.drift_chip == 1 or row.drift_chip == true) then return false, Lang:t('drift_chip_no_chip') end
        MySQL.update.await('UPDATE fcrp_tuner_mods SET drift_chip = 0 WHERE plate = ?', { plate })
    elseif modKey == 'nos' then
        if not (row.nos == 1 or row.nos == true) then return false, Lang:t('nos_not_installed') end
        MySQL.update.await('UPDATE fcrp_tuner_mods SET nos = 0, nos_cooldown = 0 WHERE plate = ?', { plate })
    elseif modKey == 'neon' then
        MySQL.update.await(
            'UPDATE fcrp_tuner_mods SET neon_mode = NULL, neon_r = NULL, neon_g = NULL, neon_b = NULL WHERE plate = ?',
            { plate })
    elseif modKey == 'stance' then
        MySQL.update.await(
            'UPDATE fcrp_tuner_mods SET stance_camber = NULL, stance_height = NULL, stance_wheeldist = NULL WHERE plate = ?',
            { plate })
    else
        return false, Lang:t('unknown_product')
    end

    local logMsg = string.format('**%s** removed **%s** from plate **%s**', CharName(Player), modKey, plate)
    Log('Tuner Removal', logMsg, src)
    return true
end)

-- ─────────────────────────────────────────────
--  PD COMMAND: /removechip
-- ─────────────────────────────────────────────

lib.addCommand('removechip', {
    help = '(PD) Remove illegal engine chip from nearby vehicle',
    restricted = false,
}, function(source)
    local src = source
    if not HasJob(src, Config.PDJob) then
        ClientNotify(src, Lang:t('remove_chip_no_perm'), 'error')
        return
    end
    TriggerClientEvent('fcrp_tuner:client:pdRemoveChipRequest', src)
end)

RegisterNetEvent('fcrp_tuner:server:pdRemoveChip', function(netId)
    local src = source
    if not HasJob(src, Config.PDJob) then return end

    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return end
    plate = plate:gsub('%s+', '')

    local row = MySQL.single.await('SELECT engine_chip FROM fcrp_tuner_mods WHERE plate = ?', { plate })

    if not row or row.engine_chip ~= 1 then
        ClientNotify(src, Lang:t('remove_chip_none'), 'error')
        return
    end

    MySQL.update.await('UPDATE fcrp_tuner_mods SET engine_chip = 0 WHERE plate = ?', { plate })
    ClientNotify(src, Lang:t('remove_chip_success'), 'success')
    TriggerClientEvent('fcrp_tuner:client:engineChipRemoved', src, netId)

    local Player = exports.qbx_core:GetPlayer(src)
    if Player then
        local logMsg = string.format('**%s** (PD) removed engine chip from plate **%s**', CharName(Player), plate)
        Log('PD Engine Chip Removal', logMsg, src)
    end
end)

-- ─────────────────────────────────────────────
--  /checkchip
-- ─────────────────────────────────────────────

lib.addCommand('checkchip', {
    help = 'Check what chips are installed on the vehicle you are in',
    restricted = false,
}, function(source)
    TriggerClientEvent('fcrp_tuner:client:checkChip', source)
end)

RegisterNetEvent('fcrp_tuner:server:checkChip', function(netId)
    local src   = source
    local veh   = NetworkGetEntityFromNetworkId(netId)
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then
        ClientNotify(src, 'Could not read vehicle plate.', 'error')
        return
    end
    plate = plate:gsub('%s+', '')

    local row = MySQL.single.await('SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate })

    local hasEngine = row and (row.engine_chip == 1 or row.engine_chip == true)
    local hasDrift  = row and (row.drift_chip  == 1 or row.drift_chip  == true)

    local msg
    if hasEngine then
        msg = '🚗 Plate [' .. plate .. '] — 🔧 Engine Chip Installed'
    elseif hasDrift then
        msg = '🚗 Plate [' .. plate .. '] — 🏎️ Drift Chip Installed'
    else
        msg = '🚗 Plate [' .. plate .. '] — No Chip Installed'
    end

    ClientNotify(src, msg, 'inform', 6000)
end)

-- ─────────────────────────────────────────────
--  CLEANUP
-- ─────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)
