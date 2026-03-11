-- ============================================
--  fcrp_dealership | server/society.lua  v2.4
-- ============================================

-- ============================================
--  Banking helpers
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
-- ============================================

AddEventHandler('fcrp_dealership:server:depositSale', function(src, citizenid, vehicle, commissionAmt)
    if not vehicle.price or vehicle.price <= 0 then return end

    commissionAmt    = commissionAmt or 0
    local netRevenue = vehicle.price - commissionAmt

    if netRevenue <= 0 then return end

    local societyAmt = math.floor(netRevenue * (Config.SocietyPercent / 100))
    local taxAmt     = netRevenue - societyAmt

    local depOk = bankDeposit(Config.OrgBankAccount, societyAmt, 'Sale: ' .. vehicle.label)
    if not depOk then
        print("^1[fcrp_dealership] WARNING: bankDeposit failed for society cut on " ..
              vehicle.label .. " ($" .. societyAmt .. "). Check Config.BankingResource.^0")
    end

    if taxAmt > 0 then
        if Config.GovTaxEnabled then
            local taxOk = bankDeposit(Config.GovBankAccount, taxAmt, 'Tax: ' .. vehicle.label)
            if not taxOk then
                bankDeposit(Config.OrgBankAccount, taxAmt, 'Tax fallback: ' .. vehicle.label)
                print("^1[fcrp_dealership] WARNING: gov tax deposit to '" .. Config.GovBankAccount ..
                      "' failed ($" .. taxAmt .. "). Absorbed into society fund.^0")
            end
        else
            bankDeposit(Config.OrgBankAccount, taxAmt, 'Tax (gov disabled): ' .. vehicle.label)
        end
    end

    MySQL.insert(
        'INSERT INTO fcrp_dealership_transactions (type, amount, citizenid, note, created_at) VALUES (?, ?, ?, ?, ?)',
        { 'deposit', societyAmt, citizenid,
          'Sale: ' .. vehicle.label .. ' (commission $' .. commissionAmt .. ' deducted)',
          os.time() }
    )

    print("^2[fcrp_dealership] Sale deposit: +$" .. societyAmt ..
          " → " .. Config.OrgBankAccount ..
          " | Tax: $" .. taxAmt ..
          " | Commission deducted: $" .. commissionAmt .. "^0")
end)

-- ============================================
--  Get Society Balance
-- ============================================

RegisterNetEvent('fcrp_dealership:server:getSocietyBalance', function()
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

    local balance = bankGetBalance(Config.OrgBankAccount)
    TriggerClientEvent('fcrp_dealership:client:receiveSocietyBalance', src, balance)
end)

-- ============================================
--  Withdraw from Society Fund
--  [FIX #1] math.floor applied to amount so
--  a floating-point value like 499999.99 cannot
--  be used to extract a fractional dollar from
--  the org account while the integer side rounds
--  differently in AddMoney vs RemoveMoney.
-- ============================================

RegisterNetEvent('fcrp_dealership:server:withdrawSociety', function(amount)
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

    -- [FIX #1] Enforce integer — reject floats/negatives/NaN before any banking call
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
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

    local currentBalance = bankGetBalance(Config.OrgBankAccount)
    if amount > currentBalance then
        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'error',
            description = 'Insufficient funds. Current balance: $' .. tostring(currentBalance)
        })
        return
    end

    local ok = bankWithdraw(Config.OrgBankAccount, amount, 'GM withdrawal')
    if not ok then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'Banking error. Try again.' })
        return
    end

    player.Functions.AddMoney('bank', amount, 'flamedrive-society-withdrawal')

    local newBalance = bankGetBalance(Config.OrgBankAccount)
    local citizenid  = player.PlayerData.citizenid
    local name       = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname

    MySQL.insert(
        'INSERT INTO fcrp_dealership_transactions (type, amount, citizenid, note, created_at) VALUES (?, ?, ?, ?, ?)',
        { 'withdrawal', amount, citizenid, 'Boss withdrawal by ' .. name, os.time() }
    )

    TriggerClientEvent('ox_lib:notify', src, {
        type        = 'success',
        title       = 'FlameDrive Society',
        description = '$' .. tostring(amount) .. ' withdrawn. New balance: $' .. tostring(newBalance)
    })

    exports.frcp_webhook:Send(
        "dealership",
        "Society Fund Withdrawal",
        "**By:** " .. name .. " (`" .. citizenid .. "`)" ..
        "\n**Amount Withdrawn:** $" .. tostring(amount) ..
        "\n**Remaining Balance:** $" .. tostring(newBalance),
        16776960
    )

    print("^2[fcrp_dealership] " .. citizenid .. " withdrew $" .. amount .. " | Balance: $" .. newBalance .. "^0")
end)

-- ============================================
--  Startup
-- ============================================

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `fcrp_dealership_transactions` (
            `id`         INT(11)      NOT NULL AUTO_INCREMENT,
            `type`       VARCHAR(20)  NOT NULL,
            `amount`     BIGINT       NOT NULL DEFAULT 0,
            `citizenid`  VARCHAR(50)  NOT NULL,
            `note`       VARCHAR(255) NOT NULL DEFAULT '',
            `created_at` INT(11)      NOT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    print("^2[fcrp_dealership] server/society.lua loaded. Org account: " ..
          Config.OrgBankAccount .. " via " .. Config.BankingResource .. "^0")
end)
