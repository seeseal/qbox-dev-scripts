-- ============================================
--  frcp_dealership | server/main.lua  v2.0
--  Purchase logic — unchanged from v1 except:
--  • finalizePurchase now calls SocietyDeposit
--    so every sale splits into fund + gov tax
-- ============================================

local QBX = exports.qbx_core

-- ============================================
--  Duty Tracking
--  Resource-owned table: FDDutyPlayers[serverId] = true/nil
--  Populated by server/job.lua's setDuty handler.
--  Shared across all server files in this resource
--  via FiveM's single-Lua-state-per-resource model.
--  We own this rather than relying on Qbox's
--  job.onDuty field, which isn't reliably updated
--  in all qbx_core builds.
-- ============================================
FDDutyPlayers = {}

-- ============================================
--  Purchase Cooldown (Elite only)
-- ============================================
local purchaseCooldowns = {}
local COOLDOWN_SECONDS  = 30 * 60  -- 30 minutes

-- ============================================
--  Active Sessions
--  Tracks which stand each customer is browsing at.
--  activeSessions[customerServerId] = standIndex
--  Set when getCatalog fires, cleared on purchase
--  or when UI closes.
-- ============================================
local activeSessions = {}

-- ============================================
--  Supply Tracking
-- ============================================
local soldCounts = {}

local function loadSoldCounts()
    MySQL.query('SELECT model, sold FROM frcp_dealership_sold', {}, function(result)
        if result then
            for _, row in ipairs(result) do
                soldCounts[row.model] = row.sold
            end
        end
        print("^2[frcp_dealership] Sold counts loaded.^0")
    end)
end

local function getSoldCount(model)
    return soldCounts[model] or 0
end

local function incrementSoldCount(model)
    soldCounts[model] = (soldCounts[model] or 0) + 1
    MySQL.update(
        'INSERT INTO frcp_dealership_sold (model, sold) VALUES (?, 1) ON DUPLICATE KEY UPDATE sold = sold + 1',
        { model }
    )
end

-- ============================================
--  Cooldown persistence
-- ============================================

local function loadCooldowns()
    MySQL.query('SELECT citizenid, model, purchased_at FROM frcp_dealership_cooldowns', {}, function(result)
        if not result then return end
        local now = os.time()
        for _, row in ipairs(result) do
            if (now - row.purchased_at) < COOLDOWN_SECONDS then
                if not purchaseCooldowns[row.citizenid] then
                    purchaseCooldowns[row.citizenid] = {}
                end
                purchaseCooldowns[row.citizenid][row.model] = row.purchased_at
            end
        end
        print("^2[frcp_dealership] Cooldowns loaded.^0")
    end)
end

local function saveCooldown(citizenid, model)
    local now = os.time()
    if not purchaseCooldowns[citizenid] then
        purchaseCooldowns[citizenid] = {}
    end
    purchaseCooldowns[citizenid][model] = now
    MySQL.update(
        'INSERT INTO frcp_dealership_cooldowns (citizenid, model, purchased_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE purchased_at = ?',
        { citizenid, model, now, now }
    )
end

-- ============================================
--  Helpers
-- ============================================

local function getVehicleConfig(model)
    for _, v in ipairs(Config.Vehicles) do
        if v.model == model then return v end
    end
    return nil
end

-- ============================================
--  Find Nearest On-Duty Employee to a Stand
--
--  Loops all online players, checks:
--    1. They have the flamedrive job
--    2. They are on duty (SetDuty = true)
--    3. Their position is within StandEmployeeRadius
--       of the given stand's coords
--
--  Returns the closest employee's server ID,
--  their player object, and their grade data.
--  Returns nil, nil, nil if no one qualifies.
-- ============================================

local function findEmployeeAtStand(standIndex)
    local stand = Config.TabletStands[standIndex]
    if not stand then return nil, nil, nil end

    local standPos  = vec3(stand.coords.x, stand.coords.y, stand.coords.z)
    local radius    = Config.StandEmployeeRadius
    local bestId    = nil
    local bestDist  = radius + 1
    local bestPlayer = nil
    local bestGrade  = nil

    local players = GetPlayers()
    for _, pid in ipairs(players) do
        local p = exports.qbx_core:GetPlayer(pid)
        if p then
            local job = p.PlayerData.job
            -- Must be flamedrive and on duty
            -- Must be flamedrive and on duty (checked against our own duty table,
            -- not job.onDuty, which qbx_core doesn't always update in memory)
            if job and job.name == Config.JobName and FDDutyPlayers[tonumber(pid)] then
                local gradeData = Config.JobGrades[job.grade.level]
                if gradeData then
                    -- GetEntityCoords is client-side only; we use
                    -- GetPlayerPed + GetEntityCoords via native on server
                    local ped = GetPlayerPed(pid)
                    if ped and ped ~= 0 then
                        local pos  = GetEntityCoords(ped)
                        local dist = #(pos - standPos)
                        if dist <= radius and dist < bestDist then
                            bestDist   = dist
                            bestId     = pid
                            bestPlayer = p
                            bestGrade  = gradeData
                        end
                    end
                end
            end
        end
    end

    return bestId, bestPlayer, bestGrade
end

local function generatePlate(cb)
    local chars   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local attempt = 0
    local function tryGenerate()
        attempt = attempt + 1
        local plate = ""
        for i = 1, 8 do
            local pos = math.random(1, #chars)
            plate = plate .. chars:sub(pos, pos)
        end
        MySQL.query('SELECT plate FROM player_vehicles WHERE plate = ? LIMIT 1', { plate }, function(result)
            if result and #result > 0 then
                if attempt < 5 then tryGenerate()
                else cb(nil) end
            else
                cb(plate)
            end
        end)
    end
    tryGenerate()
end

local function notify(src, ntype, description, title, duration)
    TriggerClientEvent('ox_lib:notify', src, {
        type        = ntype,
        title       = title or "FlameDrive Motors",
        description = description,
        duration    = duration or 5000
    })
end

local function fullRefund(src, citizenid, vehicle, tierConfig)
    local player = QBX:GetPlayer(src)
    if not player then return end
    if tierConfig.requiresMoney and vehicle.price > 0 then
        player.Functions.AddMoney('bank', vehicle.price, 'frcp-dealership-refund')
    end
    if tierConfig.requiresTicket then
        exports.frcp_tickets:AddTicket(citizenid, tierConfig.ticketType, 1)
    end
end

-- ============================================
--  Finalize Purchase
--  Now deposits into society fund automatically
-- ============================================

local function finalizePurchase(src, citizenid, vehicle, tierConfig, standIndex)
    generatePlate(function(plate)
        if not plate then
            notify(src, 'error', 'Purchase failed (plate error). Everything has been refunded.')
            fullRefund(src, citizenid, vehicle, tierConfig)
            return
        end

        MySQL.insert(
            'INSERT INTO player_vehicles (citizenid, vehicle, hash, mods, plate, garage, fuel, engine, body, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            {
                citizenid,
                vehicle.model,
                GetHashKey(vehicle.model),
                '{}',
                plate,
                'outside',
                100,
                1000,
                1000,
                1
            },
            function(id)
                if not id then
                    notify(src, 'error', 'Purchase failed. Everything has been refunded. Please try again.')
                    fullRefund(src, citizenid, vehicle, tierConfig)
                    return
                end

                -- Supply tracking
                incrementSoldCount(vehicle.model)

                -- Log sale for leaderboard + stats
                MySQL.insert(
                    'INSERT INTO frcp_dealership_sales_log (citizenid, model, label, tier, price, sold_at) VALUES (?, ?, ?, ?, ?, ?)',
                    { citizenid, vehicle.model, vehicle.label, vehicle.tier, vehicle.price, os.time() }
                )

                -- Cooldown for Elite
                if vehicle.tier == 'elite' then
                    saveCooldown(citizenid, vehicle.model)
                end

                -- Clear session
                activeSessions[src] = nil

                -- ── COMMISSION + SOCIETY DEPOSIT ────────────────
                local commissionAmt  = 0
                local commissionPct  = 0
                local employeeId     = nil
                local employeeCid    = nil
                local employeeLabel  = nil

                if vehicle.price and vehicle.price > 0 then
                    -- Find nearest on-duty employee to the stand
                    local empId, empPlayer, empGrade = findEmployeeAtStand(standIndex)

                    if empId and empPlayer and empGrade then
                        commissionPct = empGrade.commission or 0
                        employeeId    = empId
                        employeeCid   = empPlayer.PlayerData.citizenid
                        employeeLabel = empGrade.label

                        if commissionPct > 0 then
                            commissionAmt = math.floor(vehicle.price * (commissionPct / 100))
                            empPlayer.Functions.AddMoney('bank', commissionAmt, 'flamedrive-commission')

                            -- Log commission for stats queries
                            MySQL.insert(
                                'INSERT INTO frcp_dealership_transactions (type, amount, citizenid, note, created_at) VALUES (?, ?, ?, ?, ?)',
                                { 'commission', commissionAmt, employeeCid,
                                  'Commission on ' .. vehicle.label, os.time() }
                            )

                            TriggerClientEvent('ox_lib:notify', empId, {
                                type        = 'success',
                                title       = '💵 Commission Earned',
                                description = '$' .. tostring(commissionAmt) .. ' — ' .. vehicle.label,
                                duration    = 8000
                            })
                        end
                    end

                    -- Deposit remainder into society fund (commission already paid out of price)
                    TriggerEvent('frcp_dealership:server:depositSale', src, citizenid, vehicle, commissionAmt)
                end
                -- ────────────────────────────────────────────────

                -- Close UI and spawn vehicle
                TriggerClientEvent('frcp_dealership:client:closeUI', src)
                TriggerClientEvent('frcp_dealership:client:spawnVehicle', src, vehicle.model, plate)
                TriggerClientEvent('frcp_dealership:client:updateSupply', -1, vehicle.model, getSoldCount(vehicle.model))

                -- Discord log
                local societyAmt = math.floor((vehicle.price - commissionAmt) * (Config.SocietyPercent / 100))
                local taxAmt     = (vehicle.price - commissionAmt) - societyAmt

                local discordBody =
                    "**CitizenID:** " .. citizenid ..
                    "\n**Vehicle:** " .. vehicle.label ..
                    "\n**Tier:** " .. vehicle.tier:upper() ..
                    "\n**Sale Price:** $" .. tostring(vehicle.price)

                if employeeCid then
                    discordBody = discordBody ..
                        "\n**Salesperson:** `" .. employeeCid .. "` (" .. (employeeLabel or "?") .. ")" ..
                        "\n**Commission (" .. commissionPct .. "%):** $" .. tostring(commissionAmt)
                else
                    discordBody = discordBody .. "\n**Salesperson:** None nearby (self-service)"
                end

                discordBody = discordBody ..
                    "\n**→ Society Fund:** $" .. tostring(societyAmt) ..
                    "\n**→ Gov Tax:** $" .. tostring(taxAmt) ..
                    "\n**Plate:** " .. plate ..
                    "\n**Supply Remaining:** " .. (vehicle.limit == -1 and "Unlimited" or tostring(vehicle.limit - getSoldCount(vehicle.model)))

                exports.frcp_webhook:Send("dealership", "🚗 Vehicle Purchased", discordBody, 3066993)

                print("^2[frcp_dealership] " .. citizenid .. " purchased " .. vehicle.label ..
                      " | Commission: $" .. commissionAmt .. " to " .. (employeeCid or "none") ..
                      " | Plate: " .. plate .. "^0")
            end
        )
    end)
end

-- ============================================
--  Process Purchase
-- ============================================

local function processPurchase(src, player, citizenid, vehicle, tierConfig, standIndex)
    if tierConfig.requiresTicket then
        exports.frcp_tickets:ConsumeTicket(citizenid, tierConfig.ticketType, function(consumed)
            if not consumed then
                notify(src, 'error', 'Ticket could not be consumed. Please try again.')
                return
            end
            if tierConfig.requiresMoney and vehicle.price > 0 then
                local removed = player.Functions.RemoveMoney('bank', vehicle.price, 'frcp-dealership-purchase')
                if not removed then
                    exports.frcp_tickets:AddTicket(citizenid, tierConfig.ticketType, 1)
                    notify(src, 'error', 'Payment failed. Your ticket has been refunded. Please try again.')
                    return
                end
            end
            finalizePurchase(src, citizenid, vehicle, tierConfig, standIndex)
        end)
    else
        if tierConfig.requiresMoney and vehicle.price > 0 then
            local removed = player.Functions.RemoveMoney('bank', vehicle.price, 'frcp-dealership-purchase')
            if not removed then
                notify(src, 'error', 'Payment failed. Please try again.')
                return
            end
        end
        finalizePurchase(src, citizenid, vehicle, tierConfig, standIndex)
    end
end

-- ============================================
--  Purchase Handler
--  Now receives standIndex from client.
--  Validates an on-duty employee is nearby
--  before allowing the purchase to proceed.
-- ============================================

RegisterNetEvent('frcp_dealership:server:purchase', function(model, standIndex)
    local src       = source
    local player    = QBX:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local vehicle   = getVehicleConfig(model)

    if not vehicle then
        notify(src, 'error', 'Invalid vehicle selection.')
        return
    end

    -- Validate standIndex matches what we stored in getCatalog
    local sessionStand = activeSessions[src]
    if not sessionStand or sessionStand ~= standIndex then
        notify(src, 'error', 'Session error. Please close the UI and try again.')
        return
    end

    -- Validate stand exists
    if not Config.TabletStands[standIndex] then
        notify(src, 'error', 'Invalid stand. Please try again.')
        return
    end

    -- ── EMPLOYEE PROXIMITY CHECK ─────────────────────────
    -- A purchase requires at least one on-duty employee
    -- to be within Config.StandEmployeeRadius of this stand.
    -- Apex purchases (free IC) still require an employee —
    -- they need the ticket + employee assistance to claim.
    local empId, empPlayer, empGrade = findEmployeeAtStand(standIndex)
    if not empId then
        notify(src, 'error',
            'A FlameDrive salesperson must be present to complete your purchase. ' ..
            'Please ask a staff member to assist you.')
        return
    end
    -- ─────────────────────────────────────────────────────

    if vehicle.limit ~= -1 and getSoldCount(model) >= vehicle.limit then
        notify(src, 'error', Config.Notifications.limitReached)
        return
    end

    if vehicle.tier == 'elite' then
        local now        = os.time()
        local cdTable    = purchaseCooldowns[citizenid]
        local lastBought = cdTable and cdTable[model]
        if lastBought then
            local remaining = COOLDOWN_SECONDS - (now - lastBought)
            if remaining > 0 then
                local mins = math.ceil(remaining / 60)
                notify(src, 'error', ('Elite cooldown: %d more minute%s.'):format(mins, mins == 1 and '' or 's'))
                return
            end
        end
    end

    local tierConfig = Config.Tiers[vehicle.tier]

    if tierConfig.requiresTicket then
        exports.frcp_tickets:HasTicket(citizenid, tierConfig.ticketType, function(hasTicket)
            if not hasTicket then
                notify(src, 'error', Config.Notifications.noTicket:gsub("{tier}", tierConfig.label))
                return
            end
            if tierConfig.requiresMoney and player.PlayerData.money.bank < vehicle.price then
                notify(src, 'error', Config.Notifications.noMoney:gsub("{price}", vehicle.price))
                return
            end
            processPurchase(src, player, citizenid, vehicle, tierConfig, standIndex)
        end)
    else
        if tierConfig.requiresMoney and player.PlayerData.money.bank < vehicle.price then
            notify(src, 'error', Config.Notifications.noMoney:gsub("{price}", vehicle.price))
            return
        end
        processPurchase(src, player, citizenid, vehicle, tierConfig, standIndex)
    end
end)

-- ============================================
--  Catalog Request
--  Now receives standIndex from client and
--  stores it in activeSessions for validation
--  at purchase time.
-- ============================================

RegisterNetEvent('frcp_dealership:server:getCatalog', function(standIndex)
    local src    = source
    local player = QBX:GetPlayer(src)
    if not player then return end

    -- Validate standIndex
    if not standIndex or not Config.TabletStands[standIndex] then
        notify(src, 'error', 'Invalid tablet stand.')
        return
    end

    -- Store which stand this customer is at
    activeSessions[src] = standIndex

    local citizenid = player.PlayerData.citizenid
    local catalog   = {}
    local job       = player.PlayerData.job

    local isEmployee = (job and job.name == Config.JobName)
    local isBoss     = false
    local gradeData  = nil

    if isEmployee then
        gradeData = Config.JobGrades[job.grade.level]
        isBoss    = gradeData and gradeData.isBoss or false
    end

    -- Find if there's an employee at this stand right now
    -- so the UI can show "Assisted by: [name]" or a warning
    local empId, empPlayer, empGrade = findEmployeeAtStand(standIndex)
    local assistantInfo = nil
    if empId and empPlayer then
        assistantInfo = {
            name  = empPlayer.PlayerData.charinfo.firstname .. " " .. empPlayer.PlayerData.charinfo.lastname,
            grade = empGrade and empGrade.label or "Staff",
            commission = empGrade and empGrade.commission or 0,
        }
    end

    for _, v in ipairs(Config.Vehicles) do
        local sold      = getSoldCount(v.model)
        local remaining = v.limit == -1 and -1 or (v.limit - sold)
        table.insert(catalog, {
            label       = v.label,
            model       = v.model,
            tier        = v.tier,
            price       = v.price,
            limit       = v.limit,
            remaining   = remaining,
            available   = remaining == -1 or remaining > 0,
            category    = v.category,
            description = v.description,
        })
    end

    exports.frcp_tickets:GetTicketCounts(citizenid, function(tickets)
        TriggerClientEvent('frcp_dealership:client:openUI', src, {
            catalog       = catalog,
            tickets       = tickets,
            playerName    = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname,
            balance       = player.PlayerData.money.bank,
            isEmployee    = isEmployee,
            isBoss        = isBoss,
            jobGrade      = gradeData and gradeData.label or nil,
            assistant     = assistantInfo,   -- shown in NUI header
            standIndex    = standIndex,
        }, standIndex)
    end)
end)


-- ============================================
--  Sales Stats (for GM panel)
--  Returns units sold, revenue, commission
--  for a given period: today / week / alltime
-- ============================================

RegisterNetEvent('frcp_dealership:server:getSalesStats', function(period)
    local src  = source
    local now  = os.time()
    local from = 0

    if period == 'today' then
        -- midnight today (server local time)
        local t = os.date('*t', now)
        t.hour = 0; t.min = 0; t.sec = 0
        from = os.time(t)
    elseif period == 'week' then
        from = now - (7 * 24 * 60 * 60)
    end
    -- alltime: from = 0 (all records)

    local query = from > 0
        and 'SELECT COUNT(*) as units, SUM(price) as revenue FROM frcp_dealership_sales_log WHERE sold_at >= ?'
        or  'SELECT COUNT(*) as units, SUM(price) as revenue FROM frcp_dealership_sales_log'

    local params = from > 0 and { from } or {}

    MySQL.query(query, params, function(result)
        local units   = (result and result[1] and result[1].units)   or 0
        local revenue = (result and result[1] and result[1].revenue) or 0

        -- Also pull commission paid from transactions table
        local commQuery = from > 0
            and "SELECT SUM(amount) as total FROM frcp_dealership_transactions WHERE type = 'commission' AND created_at >= ?"
            or  "SELECT SUM(amount) as total FROM frcp_dealership_transactions WHERE type = 'commission'"

        MySQL.query(commQuery, params, function(commResult)
            local commission = (commResult and commResult[1] and commResult[1].total) or 0
            TriggerClientEvent('frcp_dealership:client:receiveSalesStats', src, {
                units      = units,
                revenue    = revenue,
                commission = commission,
                period     = period,
            })
        end)
    end)
end)

-- ============================================
--  Sales Leaderboard
--  Top 10 employees by total sales count.
--  Joins sales_log with Qbox player data to
--  get character names.
-- ============================================

RegisterNetEvent('frcp_dealership:server:getSalesLeaderboard', function()
    local src = source

    MySQL.query([[
        SELECT citizenid, COUNT(*) as sales, SUM(price) as revenue
        FROM frcp_dealership_sales_log
        GROUP BY citizenid
        ORDER BY sales DESC
        LIMIT 10
    ]], {}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('frcp_dealership:client:receiveLeaderboard', src, { entries = {} })
            return
        end

        local entries = {}
        for _, row in ipairs(result) do
            -- Try to get character name from players table
            local name = row.citizenid
            local p    = exports.qbx_core:GetPlayerByCitizenId(row.citizenid)
            if p then
                local ci   = p.PlayerData.charinfo
                name       = ci.firstname .. " " .. ci.lastname
                local job  = p.PlayerData.job
                local grade = job and job.name == Config.JobName
                    and Config.JobGrades[job.grade.level]
                    and Config.JobGrades[job.grade.level].label or ""
                table.insert(entries, {
                    citizenid = row.citizenid,
                    name      = name,
                    grade     = grade,
                    sales     = row.sales,
                    revenue   = row.revenue or 0,
                })
            else
                -- Player offline — look up name from DB
                table.insert(entries, {
                    citizenid = row.citizenid,
                    name      = row.citizenid,
                    grade     = "Offline",
                    sales     = row.sales,
                    revenue   = row.revenue or 0,
                })
            end
        end

        -- Async name lookup for offline players
        local pending = 0
        for i, entry in ipairs(entries) do
            if entry.name == entry.citizenid then
                pending = pending + 1
                local idx = i
                MySQL.query(
                    "SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1",
                    { entry.citizenid },
                    function(r)
                        if r and r[1] and r[1].charinfo then
                            local ok, ci = pcall(json.decode, r[1].charinfo)
                            if ok and ci then
                                entries[idx].name = (ci.firstname or '') .. ' ' .. (ci.lastname or '')
                            end
                        end
                        pending = pending - 1
                        if pending == 0 then
                            TriggerClientEvent('frcp_dealership:client:receiveLeaderboard', src, { entries = entries })
                        end
                    end
                )
            end
        end

        if pending == 0 then
            TriggerClientEvent('frcp_dealership:client:receiveLeaderboard', src, { entries = entries })
        end
    end)
end)

-- ============================================
--  Clean up session if player disconnects
--  while the UI is open
-- ============================================

AddEventHandler('playerDropped', function()
    local src = source
    if activeSessions[src] then
        activeSessions[src] = nil
    end
    FDDutyPlayers[src] = nil  -- clear duty state so stale entries don't linger
end)

-- ============================================
--  Admin: /clearcooldown
-- ============================================

lib.addCommand('clearcooldown', {
    help       = 'Clear Elite purchase cooldown for a player (admin only)',
    params     = {{ name = 'id', help = 'Server ID of the player', type = 'number' }},
    restricted = 'group.admin',
}, function(source, args)
    local target = QBX:GetPlayer(args.id)
    if not target then
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Player not found.' })
        return
    end
    local cid = target.PlayerData.citizenid
    purchaseCooldowns[cid] = nil
    MySQL.update('DELETE FROM frcp_dealership_cooldowns WHERE citizenid = ?', { cid })
    TriggerClientEvent('ox_lib:notify', source, { type = 'success', description = 'Cooldown cleared for ' .. cid })
end)

-- ============================================
--  Startup
-- ============================================

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `frcp_dealership_sales_log` (
            `id`         INT(11)      NOT NULL AUTO_INCREMENT,
            `citizenid`  VARCHAR(50)  NOT NULL,
            `model`      VARCHAR(50)  NOT NULL,
            `label`      VARCHAR(100) NOT NULL DEFAULT '',
            `tier`       VARCHAR(20)  NOT NULL DEFAULT 'standard',
            `price`      BIGINT       NOT NULL DEFAULT 0,
            `sold_at`    INT(11)      NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_citizenid` (`citizenid`),
            KEY `idx_sold_at`   (`sold_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `frcp_dealership_cooldowns` (
            `citizenid`    VARCHAR(50) NOT NULL,
            `model`        VARCHAR(50) NOT NULL,
            `purchased_at` INT         NOT NULL,
            PRIMARY KEY (`citizenid`, `model`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
    loadSoldCounts()
    loadCooldowns()
    print('^2[frcp_dealership] server/main.lua loaded.^0')
end)
