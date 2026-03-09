-- ============================================
--  frcp_dealership | server/society.lua  v2.0
--
--  WHAT THIS FILE DOES (plain English):
--  ─────────────────────────────────────
--  Every time a vehicle is sold, this file
--  automatically:
--    1. Calculates the society % cut
--    2. Calculates the gov tax % cut
--    3. Saves the society money into the
--       frcp_dealership_society DB table
--    4. (Optionally) pays the gov tax into a
--       bank account if your banking script
--       supports it
--
--  Boss-only actions:
--    • Check fund balance (via boss menu in NUI)
--    • Withdraw from fund (capped by Config.MaxWithdrawal)
--
--  All fund movements are logged to Discord.
-- ============================================

-- ============================================
--  Society Fund Balance (cached in memory)
-- ============================================

local societyBalance = 0

local function loadBalance()
    MySQL.query('SELECT balance FROM frcp_dealership_society WHERE id = 1', {}, function(result)
        if result and result[1] then
            societyBalance = result[1].balance
        else
            societyBalance = 0
        end
        print("^2[frcp_dealership] Society fund loaded: $" .. societyBalance .. "^0")
    end)
end

local function saveBalance(amount, cb)
    societyBalance = amount
    MySQL.update(
        'INSERT INTO frcp_dealership_society (id, balance) VALUES (1, ?) ON DUPLICATE KEY UPDATE balance = ?',
        { amount, amount },
        function(rows)
            if cb then cb(rows and rows > 0) end
        end
    )
end

-- ============================================
--  Deposit on Sale
--  Called by server/main.lua after every sale.
--  commissionAmt has already been paid out to
--  the employee — we only deposit what remains.
--
--  Money flow on a $100,000 sale (10% commission):
--    $10,000  → salesperson bank (already paid)
--    $90,000  → split below:
--      $72,000 (80%) → society fund
--      $18,000 (20%) → gov tax
-- ============================================

AddEventHandler('frcp_dealership:server:depositSale', function(src, citizenid, vehicle, commissionAmt)
    if not vehicle.price or vehicle.price <= 0 then return end

    commissionAmt    = commissionAmt or 0
    local netRevenue = vehicle.price - commissionAmt  -- what's left after commission

    if netRevenue <= 0 then return end

    local societyAmt = math.floor(netRevenue * (Config.SocietyPercent / 100))
    local taxAmt     = netRevenue - societyAmt

    -- Add society cut to fund
    local newBalance = societyBalance + societyAmt
    saveBalance(newBalance)

    -- Log the deposit
    MySQL.insert(
        'INSERT INTO frcp_dealership_transactions (type, amount, citizenid, note, created_at) VALUES (?, ?, ?, ?, ?)',
        { 'deposit', societyAmt, citizenid,
          'Sale: ' .. vehicle.label .. ' (commission $' .. commissionAmt .. ' deducted)',
          os.time() }
    )

    print("^2[frcp_dealership] Sale deposit: +$" .. societyAmt ..
          " | Commission deducted: $" .. commissionAmt ..
          " | Fund total: $" .. newBalance .. "^0")
end)

-- ============================================
--  Get Society Balance (requested from client)
-- ============================================

RegisterNetEvent('frcp_dealership:server:getSocietyBalance', function()
    local src    = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local job = player.PlayerData.job
    if not job or job.name ~= Config.JobName then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Access denied.' })
        return
    end

    local gradeData = Config.JobGrades[job.grade.level]
    if not gradeData or not gradeData.isBoss then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Only the General Manager can view the fund.' })
        return
    end

    TriggerClientEvent('frcp_dealership:client:receiveSocietyBalance', src, societyBalance)
end)

-- ============================================
--  Withdraw from Society Fund
--  Only boss-grade. Capped by Config.MaxWithdrawal
-- ============================================

RegisterNetEvent('frcp_dealership:server:withdrawSociety', function(amount)
    local src    = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local job = player.PlayerData.job
    if not job or job.name ~= Config.JobName then return end

    local gradeData = Config.JobGrades[job.grade.level]
    if not gradeData or not gradeData.isBoss then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Only the General Manager can withdraw funds.' })
        return
    end

    -- Validate amount
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Invalid amount.' })
        return
    end

    if amount > Config.MaxWithdrawal then
        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'error',
            description = 'Maximum single withdrawal is $' .. tostring(Config.MaxWithdrawal)
        })
        return
    end

    if amount > societyBalance then
        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'error',
            description = 'Insufficient funds. Current balance: $' .. tostring(societyBalance)
        })
        return
    end

    -- Deduct and pay player
    local newBalance = societyBalance - amount
    saveBalance(newBalance, function(ok)
        if not ok then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Database error. Try again.' })
            return
        end

        player.Functions.AddMoney('bank', amount, 'flamedrive-society-withdrawal')

        local citizenid = player.PlayerData.citizenid
        local name      = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname

        -- Log transaction
        MySQL.insert(
            'INSERT INTO frcp_dealership_transactions (type, amount, citizenid, note, created_at) VALUES (?, ?, ?, ?, ?)',
            { 'withdrawal', amount, citizenid, 'Boss withdrawal by ' .. name, os.time() }
        )

        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'success',
            title       = 'FlameDrive Society',
            description = '$' .. tostring(amount) .. ' withdrawn. New balance: $' .. tostring(newBalance)
        })

        -- Discord log
        exports.frcp_webhook:Send(
            "dealership",
            "💰 Society Fund Withdrawal",
            "**By:** " .. name .. " (`" .. citizenid .. "`)" ..
            "\n**Amount Withdrawn:** $" .. tostring(amount) ..
            "\n**Remaining Balance:** $" .. tostring(newBalance),
            16776960  -- yellow
        )

        print("^2[frcp_dealership] " .. citizenid .. " withdrew $" .. amount .. " | Balance: $" .. newBalance .. "^0")
    end)
end)

-- ============================================
--  Startup
-- ============================================

MySQL.ready(function()
    -- Create tables if they don't exist
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `frcp_dealership_society` (
            `id`      INT(11)    NOT NULL DEFAULT 1,
            `balance` BIGINT     NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `frcp_dealership_transactions` (
            `id`         INT(11)      NOT NULL AUTO_INCREMENT,
            `type`       VARCHAR(20)  NOT NULL,
            `amount`     BIGINT       NOT NULL DEFAULT 0,
            `citizenid`  VARCHAR(50)  NOT NULL,
            `note`       VARCHAR(255) NOT NULL DEFAULT '',
            `created_at` INT(11)      NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    loadBalance()
    print("^2[frcp_dealership] server/society.lua loaded.^0")
end)
