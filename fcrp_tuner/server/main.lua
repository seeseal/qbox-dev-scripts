-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  server/main.lua        ║
-- ╚══════════════════════════════════════════════╝

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
            `nos_empty`          TINYINT(1)   NOT NULL DEFAULT 0,
            `nos_cooldown_until` BIGINT       NOT NULL DEFAULT 0,
            `neon_mode`          VARCHAR(16)  DEFAULT NULL,
            `neon_r`             SMALLINT     DEFAULT NULL,
            `neon_g`             SMALLINT     DEFAULT NULL,
            `neon_b`             SMALLINT     DEFAULT NULL,
            `stance_camber`      FLOAT        DEFAULT NULL,
            `stance_height`      FLOAT        DEFAULT NULL,
            `stance_wheeldist`   FLOAT        DEFAULT NULL,
            `has_exhaust`        TINYINT(1)   NOT NULL DEFAULT 0,
            PRIMARY KEY (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
end)

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function GetPlate(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return nil end
    return string.upper(string.gsub(GetVehicleNumberPlateText(veh), '%s+', ''))
end

local function GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function GetVehicleClass(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return -1 end
    return GetVehicleClass(veh)
end

local function GetVehicleModelName(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return '' end
    return string.lower(GetEntityModel(veh) ~= 0 and GetDisplayNameFromVehicleModel(GetEntityModel(veh)) or '')
end

local function IsVehicleBlacklisted(netId)
    local cls   = GetVehicleClass(netId)
    local model = GetVehicleModelName(netId)
    for _, c in ipairs(Config.BlacklistedVehicleClasses) do
        if c == cls then return true, 'Vehicle class not allowed.' end
    end
    for _, m in ipairs(Config.BlacklistedVehicles) do
        if m == model then return true, 'This vehicle is not allowed.' end
    end
    return false, nil
end

local function GetJobGradeConfig(src)
    local Player = GetPlayer(src)
    if not Player then return Config.JobGrades[0] end
    local grade = Player.PlayerData.job and Player.PlayerData.job.grade and Player.PlayerData.job.grade.level or 0
    return Config.JobGrades[grade] or Config.JobGrades[0]
end

local function PayCommission(src, amount)
    local gradeConf = GetJobGradeConfig(src)
    local cut = math.floor(amount * gradeConf.commission)
    if cut <= 0 then return end
    -- Pay commission directly to the tuner as dirty cash
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
--  VEHICLE STATE
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getVehicleState', function(src, netId)
    local plate = GetPlate(netId)
    if not plate then return nil end

    local row = MySQL.single.await('SELECT * FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row then return {
        engine_chip = false, drift_chip = false,
        nos = false, nos_empty = false, nos_cooldown_until = 0,
        neon_mode = nil, neon_r = nil, neon_g = nil, neon_b = nil,
        has_stance = false, stance = nil, has_exhaust = false,
    } end

    local now = os.time() * 1000
    return {
        engine_chip        = row.engine_chip == 1,
        drift_chip         = row.drift_chip == 1,
        nos                = row.nos == 1,
        nos_empty          = row.nos_empty == 1,
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
    }
end)

-- ─────────────────────────────────────────────
--  PRICE CALLBACKS
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getEngineChipPrice', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    local depotValue = 0
    if veh and veh ~= 0 then
        -- Use KVP-stored depot value if available (set by your garage script)
        local plate = GetPlate(netId)
        local stored = plate and GetResourceKvpFloat('depot_' .. plate) or 0
        depotValue = stored > 0 and stored or 0
    end
    local bonus = math.floor(depotValue * Config.EngineChip.carValuePercent)
    local price = Config.EngineChip.basePrice + bonus
    return price, depotValue, bonus
end)

lib.callback.register('fcrp_tuner:server:getDriftChipPrice', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    local depotValue = 0
    if veh and veh ~= 0 then
        local plate = GetPlate(netId)
        local stored = plate and GetResourceKvpFloat('depot_' .. plate) or 0
        depotValue = stored > 0 and stored or 0
    end
    local bonus = math.floor(depotValue * Config.DriftChip.carValuePercent)
    local price = Config.DriftChip.basePrice + bonus
    return price, depotValue, bonus
end)

-- ─────────────────────────────────────────────
--  PASSENGER LOOKUP
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:getPassenger', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return nil end
    -- Return first non-driver passenger src, or nil
    for seat = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped and ped ~= 0 then
            local passSrc = GetPlayerFromPed(ped)
            if passSrc and passSrc ~= src and passSrc ~= -1 then
                return passSrc
            end
        end
    end
    return nil
end)

-- ─────────────────────────────────────────────
--  PURCHASE
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:purchase', function(src, productKey, _, passengerSrc, netId)
    local Player = GetPlayer(src)
    if not Player then return false, 'Player not found.' end

    -- Tuner job required for all purchases
    local job = Player.PlayerData.job
    if not job or job.name ~= Config.RequiredJob then
        return false, 'You must be a tuner to install mods.'
    end

    -- Vehicle checks
    local plate = GetPlate(netId)
    if not plate then return false, 'Vehicle not found.' end

    local blacklisted, reason = IsVehicleBlacklisted(netId)
    if blacklisted then return false, reason end

    local payerSrc = passengerSrc or src
    local Payer    = GetPlayer(payerSrc)
    if not Payer then return false, 'Payer not found.' end

    -- Determine price
    local price = 0
    if productKey == 'engine_chip' then
        local depotValue = GetResourceKvpFloat('depot_' .. plate) or 0
        price = Config.EngineChip.basePrice + math.floor(depotValue * Config.EngineChip.carValuePercent)

        -- Check item + chip conflict
        local row = MySQL.single.await('SELECT drift_chip, engine_chip FROM fcrp_tuner_mods WHERE plate = ?', { plate })
        if row and row.drift_chip == 1 then return false, 'Remove drift chip first.' end
        if row and row.engine_chip == 1 then return false, 'Engine chip already installed.' end

        local hasChip = exports.ox_inventory:GetItemCount(payerSrc, 's3_chip')
        if not hasChip or hasChip < 1 then return false, 'Requires 1x S3 Chip item.' end
        exports.ox_inventory:RemoveItem(payerSrc, 's3_chip', 1)

    elseif productKey == 'drift_chip' then
        local depotValue = GetResourceKvpFloat('depot_' .. plate) or 0
        price = Config.DriftChip.basePrice + math.floor(depotValue * Config.DriftChip.carValuePercent)

        local row = MySQL.single.await('SELECT engine_chip, drift_chip FROM fcrp_tuner_mods WHERE plate = ?', { plate })
        if row and row.engine_chip == 1 then return false, 'Remove engine chip first.' end
        if row and row.drift_chip == 1 then return false, 'Drift chip already installed.' end

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

    elseif productKey == 'neon_static' or productKey == 'neon_rainbow' or productKey == 'neon_rgb' or productKey == 'neon_strobe' then
        local neonKeyMap = { neon_static = 'static', neon_rainbow = 'rainbow', neon_rgb = 'rgb', neon_strobe = 'strobe' }
        price = Config.NeonPrices[neonKeyMap[productKey]] or 25000
    else
        return false, 'Unknown product.'
    end

    -- Deduct dirty cash from payer
    local cash = exports.ox_inventory:GetItemCount(payerSrc, Config.PaymentType)
    if not cash or cash < price then
        return false, string.format('Not enough dirty cash. Need $%s.', lib.math.groupdigits(price))
    end
    exports.ox_inventory:RemoveItem(payerSrc, Config.PaymentType, price)

    -- Save to DB
    local saveMap = {
        engine_chip  = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, engine_chip) VALUES (?, 1) ON DUPLICATE KEY UPDATE engine_chip = 1', { plate }) end,
        drift_chip   = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, drift_chip) VALUES (?, 1) ON DUPLICATE KEY UPDATE drift_chip = 1', { plate }) end,
        stance_kit   = function() end, -- stance saved separately via saveStance
        nitrous_kit  = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, nos) VALUES (?, 1) ON DUPLICATE KEY UPDATE nos = 1, nos_empty = 0', { plate }) end,
        exhaust_mod  = function() MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, has_exhaust) VALUES (?, 1) ON DUPLICATE KEY UPDATE has_exhaust = 1', { plate }) end,
    }
    local neonKeys = { neon_static = 'static', neon_rainbow = 'rainbow', neon_rgb = 'rgb', neon_strobe = 'strobe' }
    if neonKeys[productKey] then
        MySQL.query.await('INSERT INTO fcrp_tuner_mods (plate, neon_mode) VALUES (?, ?) ON DUPLICATE KEY UPDATE neon_mode = ?', { plate, neonKeys[productKey], neonKeys[productKey] })
    elseif saveMap[productKey] then
        saveMap[productKey]()
    end

    -- Pay commission to tuner
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

    local colMap = {
        engine_chip = 'engine_chip = 0',
        drift_chip  = 'drift_chip = 0',
        nos         = 'nos = 0, nos_empty = 0, nos_cooldown_until = 0',
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
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:saveStance', function(netId, camber, height, wheeldist)
    local src   = source
    local plate = GetPlate(netId)
    if not plate then return end
    MySQL.query.await([[
        INSERT INTO fcrp_tuner_mods (plate, stance_camber, stance_height, stance_wheeldist)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            stance_camber = VALUES(stance_camber),
            stance_height = VALUES(stance_height),
            stance_wheeldist = VALUES(stance_wheeldist)
    ]], { plate, camber, height, wheeldist })
end)

-- ─────────────────────────────────────────────
--  NEON SAVE (RGB / static colour)
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:saveNeonColour', function(netId, r, g, b)
    local plate = GetPlate(netId)
    if not plate then return end
    MySQL.query.await('UPDATE fcrp_tuner_mods SET neon_r = ?, neon_g = ?, neon_b = ? WHERE plate = ?', { r, g, b, plate })
end)

-- ─────────────────────────────────────────────
--  NOS CANISTER ITEM USE
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:useNosCanister', function(netId)
    local src   = source
    local plate = GetPlate(netId)
    if not plate then return end

    -- Check vehicle has NOS installed
    local row = MySQL.single.await('SELECT nos FROM fcrp_tuner_mods WHERE plate = ?', { plate })
    if not row or row.nos ~= 1 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'No NOS kit installed on this vehicle.', type = 'error', duration = 4000 })
        return
    end

    -- Check item
    local count = exports.ox_inventory:GetItemCount(src, 'nos_canister')
    if not count or count < 1 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'You need a NOS Canister to refill.', type = 'error', duration = 4000 })
        return
    end
    exports.ox_inventory:RemoveItem(src, 'nos_canister', 1)
    MySQL.query.await('UPDATE fcrp_tuner_mods SET nos_empty = 0, nos_cooldown_until = 0 WHERE plate = ?', { plate })
    TriggerClientEvent('fcrp_tuner:client:nosRefillConfirmed', src)
end)

-- ─────────────────────────────────────────────
--  NOS USED  (record cooldown server-side)
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:server:nosUsed', function(netId)
    local plate   = GetPlate(netId)
    if not plate then return end
    local expires = (os.time() + Config.Nitrous.cooldown) * 1000
    MySQL.query.await('UPDATE fcrp_tuner_mods SET nos_empty = 1, nos_cooldown_until = ? WHERE plate = ?', { expires, plate })
end)

-- ─────────────────────────────────────────────
--  CRAFT SYSTEM  (Tuner II + Master Tuner)
-- ─────────────────────────────────────────────

lib.callback.register('fcrp_tuner:server:craftItem', function(src, recipeIdx)
    local gradeConf = GetJobGradeConfig(src)
    if not gradeConf.canCraft then
        return false, 'You need to be Tuner II or higher to craft.'
    end

    local recipe = Config.CraftRecipes[recipeIdx]
    if not recipe then return false, 'Invalid recipe.' end

    -- Check all ingredients
    for _, ing in ipairs(recipe.ingredients) do
        local count = exports.ox_inventory:GetItemCount(src, ing.item)
        if not count or count < ing.amount then
            return false, string.format('Missing: %dx %s', ing.amount, ing.label)
        end
    end

    -- Remove ingredients
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
    -- Refund ingredients on cancel
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
    help       = 'Remove the engine chip from a nearby vehicle.',
    restricted = 'group.' .. Config.PDJob,
}, function(src)
    TriggerClientEvent('fcrp_tuner:client:pdRemoveChipRequest', src)
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
