-- ============================================================
--  frcp_tuner  |  server/main.lua
--  Handles all database reads/writes, payment, and logging.
--  Players NEVER directly touch the DB — all trust is here.
-- ============================================================

-- Auto-create the table if it doesn't exist yet.
-- This runs once on every server start; it's safe to leave.
MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `frcp_tuner_mods` (
            `plate`         VARCHAR(10)  NOT NULL,
            `engine_chip`   TINYINT(1)   NOT NULL DEFAULT 0,
            `drift_chip`    TINYINT(1)   NOT NULL DEFAULT 0,
            `stance_data`   LONGTEXT     NULL,
            `nitrous`       TINYINT(1)   NOT NULL DEFAULT 0,
            `neon_data`     LONGTEXT     NULL,
            `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end)

-- ============================================================
--  Helper: Get or create a row for a plate
-- ============================================================
local function EnsurePlate(plate, cb)
    MySQL.query('SELECT plate FROM frcp_tuner_mods WHERE plate = ?', { plate }, function(rows)
        if not rows or #rows == 0 then
            MySQL.insert('INSERT INTO frcp_tuner_mods (plate) VALUES (?)', { plate }, function()
                cb()
            end)
        else
            cb()
        end
    end)
end

-- ============================================================
--  Helper: Deduct black_money from player's ox_inventory
-- ============================================================
local function ChargeBM(playerId, amount)
    local removed = exports.ox_inventory:RemoveItem(playerId, Config.PaymentItem, amount)
    return removed
end

-- ============================================================
--  Helper: Send a Discord log via frcp_webhook
-- ============================================================
local function Log(message, title)
    if exports.frcp_webhook then
        exports.frcp_webhook:Send(
            'tuner',
            title or '🔧 Tuner Shop',
            message,
            8204478  -- purple in decimal (0x7D3DBE)
        )
    end
end

-- ============================================================
--  Fetch all mods for a plate — called when player enters vehicle
-- ============================================================
RegisterNetEvent('frcp_tuner:server:GetMods', function(plate)
    local src = source
    MySQL.query('SELECT * FROM frcp_tuner_mods WHERE plate = ?', { plate }, function(rows)
        local data = (rows and rows[1]) or {}
        TriggerClientEvent('frcp_tuner:client:ReceiveMods', src, data)
    end)
end)

-- ============================================================
--  INSTALL ENGINE CHIP
-- ============================================================
RegisterNetEvent('frcp_tuner:server:InstallEngineChip', function(plate, depotValue)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end

    -- Verify job server-side — client can be spoofed
    if Player.PlayerData.job.name ~= Config.RequiredJob then return end

    -- Check no existing chip
    MySQL.query('SELECT engine_chip, drift_chip FROM frcp_tuner_mods WHERE plate = ?', { plate }, function(rows)
        local row = (rows and rows[1]) or {}
        if row.engine_chip == 1 then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'already_has_chip', 'error')
            return
        end
        if row.drift_chip == 1 then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'engine_drift_conflict', 'error')
            return
        end

        -- Calculate price
        local price = Config.EngineChip.BasePrice + math.floor((depotValue or 0) * Config.EngineChip.DepotMultiplier)

        -- Charge payment
        if not ChargeBM(src, price) then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'no_funds', 'error')
            return
        end

        EnsurePlate(plate, function()
            MySQL.update('UPDATE frcp_tuner_mods SET engine_chip = 1 WHERE plate = ?', { plate })
            TriggerClientEvent('frcp_tuner:client:ApplyEngineChip', src, Config.EngineChip.SpeedBoost)
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'chip_installed', 'success')
            Log(('%s %s purchased **Engine Chip** on plate **%s** for **$%s** BM.'):format(
                Player.PlayerData.charinfo.firstname,
                Player.PlayerData.charinfo.lastname,
                plate,
                price
            ))
        end)
    end)
end)

-- ============================================================
--  INSTALL DRIFT CHIP
-- ============================================================
RegisterNetEvent('frcp_tuner:server:InstallDriftChip', function(plate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.name ~= Config.RequiredJob then return end

    MySQL.query('SELECT engine_chip, drift_chip FROM frcp_tuner_mods WHERE plate = ?', { plate }, function(rows)
        local row = (rows and rows[1]) or {}
        if row.drift_chip == 1 then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'already_has_chip', 'error')
            return
        end
        if row.engine_chip == 1 then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'drift_engine_conflict', 'error')
            return
        end

        if not ChargeBM(src, Config.DriftChip.Price) then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'no_funds', 'error')
            return
        end

        EnsurePlate(plate, function()
            MySQL.update('UPDATE frcp_tuner_mods SET drift_chip = 1 WHERE plate = ?', { plate })
            TriggerClientEvent('frcp_tuner:client:ApplyDriftChip', src)
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'drift_installed', 'success')
            Log(('%s %s purchased **Drift Chip** on plate **%s** for **$%s** BM.'):format(
                Player.PlayerData.charinfo.firstname,
                Player.PlayerData.charinfo.lastname,
                plate,
                Config.DriftChip.Price
            ))
        end)
    end)
end)

-- ============================================================
--  INSTALL NITROUS
-- ============================================================
RegisterNetEvent('frcp_tuner:server:InstallNitrous', function(plate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.name ~= Config.RequiredJob then return end

    MySQL.query('SELECT nitrous FROM frcp_tuner_mods WHERE plate = ?', { plate }, function(rows)
        local row = (rows and rows[1]) or {}
        if row.nitrous == 1 then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'already_has_chip', 'error')
            return
        end

        if not ChargeBM(src, Config.NitrousKit.Price) then
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'no_funds', 'error')
            return
        end

        EnsurePlate(plate, function()
            MySQL.update('UPDATE frcp_tuner_mods SET nitrous = 1 WHERE plate = ?', { plate })
            TriggerClientEvent('frcp_tuner:client:NitrousReady', src)
            TriggerClientEvent('frcp_tuner:client:Notify', src, 'nitrous_installed', 'success')
            Log(('%s %s purchased **Nitrous Kit** on plate **%s** for **$%s** BM.'):format(
                Player.PlayerData.charinfo.firstname,
                Player.PlayerData.charinfo.lastname,
                plate,
                Config.NitrousKit.Price
            ))
        end)
    end)
end)

-- ============================================================
--  INSTALL STANCE KIT — saves camber/height/width JSON
-- ============================================================
RegisterNetEvent('frcp_tuner:server:SaveStance', function(plate, stanceJSON)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.name ~= Config.RequiredJob then return end

    if not ChargeBM(src, Config.StanceKit.Price) then
        TriggerClientEvent('frcp_tuner:client:Notify', src, 'no_funds', 'error')
        return
    end

    EnsurePlate(plate, function()
        MySQL.update('UPDATE frcp_tuner_mods SET stance_data = ? WHERE plate = ?', { stanceJSON, plate })
        TriggerClientEvent('frcp_tuner:client:Notify', src, 'stance_installed', 'success')
        Log(('%s %s purchased **Stance Kit** on plate **%s** for **$%s** BM.'):format(
            Player.PlayerData.charinfo.firstname,
            Player.PlayerData.charinfo.lastname,
            plate,
            Config.StanceKit.Price
        ))
    end)
end)

-- ============================================================
--  INSTALL NEON KIT — saves mode + colour JSON
-- ============================================================
RegisterNetEvent('frcp_tuner:server:SaveNeon', function(plate, neonJSON)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.name ~= Config.RequiredJob then return end

    if not ChargeBM(src, Config.NeonKit.Price) then
        TriggerClientEvent('frcp_tuner:client:Notify', src, 'no_funds', 'error')
        return
    end

    EnsurePlate(plate, function()
        MySQL.update('UPDATE frcp_tuner_mods SET neon_data = ? WHERE plate = ?', { neonJSON, plate })
        TriggerClientEvent('frcp_tuner:client:Notify', src, 'neon_installed', 'success')
        Log(('%s %s purchased **Neon Kit** on plate **%s** for **$%s** BM.'):format(
            Player.PlayerData.charinfo.firstname,
            Player.PlayerData.charinfo.lastname,
            plate,
            Config.NeonKit.Price
        ))
    end)
end)

-- ============================================================
--  REMOVE A MOD  (player-requested, at shop)
-- ============================================================
RegisterNetEvent('frcp_tuner:server:RemoveMod', function(plate, modKey)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.name ~= Config.RequiredJob then return end

    -- Validate modKey is one of the known columns — prevents SQL injection
    local allowed = { engine_chip=true, drift_chip=true, stance_data=true, nitrous=true, neon_data=true }
    if not allowed[modKey] then return end

    local nullVal = (modKey == 'stance_data' or modKey == 'neon_data') and 'NULL' or '0'
    -- Safe because modKey is whitelisted above
    MySQL.update('UPDATE frcp_tuner_mods SET `'..modKey..'` = '..nullVal..' WHERE plate = ?', { plate })
    TriggerClientEvent('frcp_tuner:client:ModRemoved', src, modKey)
    TriggerClientEvent('frcp_tuner:client:Notify', src, 'mod_removed', 'success')
    Log(('%s %s removed **%s** from plate **%s**.'):format(
        Player.PlayerData.charinfo.firstname,
        Player.PlayerData.charinfo.lastname,
        modKey,
        plate
    ))
end)

-- ============================================================
--  PD: /removechip command
-- ============================================================
lib.addCommand('removechip', {
    help     = 'Remove an illegal engine chip from the nearest vehicle (PD only)',
    restricted = false, -- we check job manually below
}, function(source)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.name ~= Config.PDJob then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='You do not have permission.' })
        return
    end
    -- Tell the client to find the nearest vehicle and report its plate
    TriggerClientEvent('frcp_tuner:client:PDRemoveChip', src)
end)

-- Client reports back the plate of the nearest vehicle
RegisterNetEvent('frcp_tuner:server:PDConfirmRemove', function(plate)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.name ~= Config.PDJob then return end

    MySQL.query('SELECT engine_chip FROM frcp_tuner_mods WHERE plate = ?', { plate }, function(rows)
        local row = (rows and rows[1]) or {}
        if not row.engine_chip or row.engine_chip == 0 then
            TriggerClientEvent('ox_lib:notify', src, { type='error', description='No engine chip found on that vehicle.' })
            return
        end
        MySQL.update('UPDATE frcp_tuner_mods SET engine_chip = 0 WHERE plate = ?', { plate })
        TriggerClientEvent('frcp_tuner:client:ModRemoved', src, 'engine_chip')
        TriggerClientEvent('ox_lib:notify', src, { type='success', description='Engine chip removed.' })
        Log(('Officer **%s %s** removed engine chip from plate **%s**.'):format(
            Player.PlayerData.charinfo.firstname,
            Player.PlayerData.charinfo.lastname,
            plate
        ))
    end)
end)

-- ============================================================
--  /checkchip — anyone can see what chip a vehicle has
-- ============================================================
lib.addCommand('checkchip', {
    help = 'Check what mods are on the nearest vehicle',
}, function(source)
    TriggerClientEvent('frcp_tuner:client:CheckChip', source)
end)