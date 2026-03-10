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
--  Banking helpers
--  Thin wrappers around Renewed-Banking exports
--  (or equivalent). Change Config.BankingResource
--  if your server uses a different script.
-- ============================================

local function bankDeposit(account, amount, reason)
    if amount <= 0 then return true end
    local ok = exports[Config.BankingResource]:addAccountMoney(account, amount, reason)
    return ok
end

local function bankWithdraw(account, amount, reason)
    if amount <= 0 then return false end
    local ok = exports[Config.BankingResource]:removeAccountMoney(account, amount, reason)
    return ok
end

local function bankGetBalance(account)
    return exports[Config.BankingResource]:getAccountMoney(account) or 0
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
    local netRevenue = vehicle.price - commissionAmt

    if netRevenue <= 0 then return end

    local societyAmt = math.floor(netRevenue * (Config.SocietyPercent / 100))
    local taxAmt     = netRevenue - societyAmt

    -- ── Deposit society cut into the org bank account ───────────────────────
    local depOk = bankDeposit(
        Config.OrgBankAccount,
        societyAmt,
        'Sale: ' .. vehicle.label
    )

    if not depOk then
        print("^1[frcp_dealership] WARNING: bankDeposit failed for society cut on " ..
              vehicle.label .. " ($" .. societyAmt .. "). Check Config.BankingResource.^0")
    end
    -- ────────────────────────────────────────────────────────────────────────

    -- ── Pay gov tax ─────────────────────────────────────────────────────────
    if taxAmt > 0 then
        if Config.GovTaxEnabled then
            local taxOk = bankDeposit(
                Config.GovBankAccount,
                taxAmt,
                'Tax: ' .. vehicle.label
            )
            if not taxOk then
                -- Account likely doesn't exist yet — absorb into society fund
                -- and warn clearly so it's easy to spot in console.
                bankDeposit(Config.OrgBankAccount, taxAmt, 'Tax fallback: ' .. vehicle.label)
                print("^1[frcp_dealership] WARNING: gov tax deposit to '" .. Config.GovBankAccount ..
                      "' failed ($" .. taxAmt .. "). Does the account exist in " ..
                      Config.BankingResource .. "? Tax absorbed into society fund as fallback. " ..
                      "Set Config.GovTaxEnabled = false to silence this warning.^0")
            end
        else
            -- GovTaxEnabled = false: fold the tax slice into the org account
            bankDeposit(Config.OrgBankAccount, taxAmt, 'Tax (gov disabled): ' .. vehicle.label)
        end
    end
    -- ────────────────────────────────────────────────────────────────────────

    -- Log the deposit to the transaction table for GM reporting
    MySQL.insert(
        'INSERT INTO frcp_dealership_transactions (type, amount, citizenid, note, created_at) VALUES (?, ?, ?, ?, ?)',
        { 'deposit', societyAmt, citizenid,
          'Sale: ' .. vehicle.label .. ' (commission $' .. commissionAmt .. ' deducted)',
          os.time() }
    )

    print("^2[frcp_dealership] Sale deposit: +$" .. societyAmt ..
          " → " .. Config.OrgBankAccount ..
          " | Tax: $" .. taxAmt .. " → " .. Config.GovBankAccount ..
          " | Commission deducted: $" .. commissionAmt .. "^0")
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

    -- Read live balance directly from the banking script
    local balance = bankGetBalance(Config.OrgBankAccount)
    TriggerClientEvent('frcp_dealership:client:receiveSocietyBalance', src, balance)
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

    -- Check live balance from banking script
    local currentBalance = bankGetBalance(Config.OrgBankAccount)
    if amount > currentBalance then
        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'error',
            description = 'Insufficient funds. Current balance: $' .. tostring(currentBalance)
        })
        return
    end

    -- Withdraw from org account
    local ok = bankWithdraw(Config.OrgBankAccount, amount, 'GM withdrawal')
    if not ok then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Banking error. Try again.' })
        return
    end

    -- Pay the GM
    player.Functions.AddMoney('bank', amount, 'flamedrive-society-withdrawal')

    local newBalance    = bankGetBalance(Config.OrgBankAccount)
    local citizenid     = player.PlayerData.citizenid
    local name          = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname

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

    exports.frcp_webhook:Send(
        "dealership",
        "💰 Society Fund Withdrawal",
        "**By:** " .. name .. " (`" .. citizenid .. "`)" ..
        "\n**Amount Withdrawn:** $" .. tostring(amount) ..
        "\n**Remaining Balance:** $" .. tostring(newBalance),
        16776960
    )

    print("^2[frcp_dealership] " .. citizenid .. " withdrew $" .. amount .. " | Balance: $" .. newBalance .. "^0")
end)

-- ============================================
--  Startup
-- ============================================

MySQL.ready(function()
    -- frcp_dealership_transactions still used for GM reporting / leaderboard
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

    -- frcp_dealership_society is kept for historical compatibility but the
    -- live balance is now read directly from Config.BankingResource.
    -- No loadBalance() call needed.
    print("^2[frcp_dealership] server/society.lua loaded. Org account: " ..
          Config.OrgBankAccount .. " via " .. Config.BankingResource .. "^0")
end)
