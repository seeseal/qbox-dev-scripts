-- ============================================
--  frcp_dealership | server.lua
--  All purchase logic handled server-side
-- ============================================

local QBX = exports.qbx_core

-- ============================================
--  Purchase Cooldown (Elite only)
--  purchaseCooldowns[citizenid][model] = os.time()
--  Persisted in DB so it survives server restarts
-- ============================================
local purchaseCooldowns = {}
local COOLDOWN_SECONDS  = 30 * 60  -- !! CHANGE ME !! 30 mins — change number to adjust

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
            -- Only load cooldowns that are still active
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

-- Generates a unique 8-char plate with collision check
-- Retries up to 5 times then calls cb(nil) on failure
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
                -- Collision found — retry
                if attempt < 5 then
                    tryGenerate()
                else
                    cb(nil)  -- give up after 5 attempts
                end
            else
                cb(plate)  -- unique plate confirmed
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

-- Full refund helper — gives back money AND ticket
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
--  Only called after ticket AND money deducted
-- ============================================

local function finalizePurchase(src, citizenid, vehicle, tierConfig)
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
                    -- DB insert failed — full refund
                    notify(src, 'error', 'Purchase failed. Everything has been refunded. Please try again.')
                    fullRefund(src, citizenid, vehicle, tierConfig)
                    return
                end

                -- Success — increment supply
                incrementSoldCount(vehicle.model)

                -- Save cooldown for Elite purchases
                if vehicle.tier == 'elite' then
                    saveCooldown(citizenid, vehicle.model)
                end

                -- Close UI
                TriggerClientEvent('frcp_dealership:client:closeUI', src)

                -- Spawn vehicle and grant keys
                TriggerClientEvent('frcp_dealership:client:spawnVehicle', src, vehicle.model, plate)

                -- Push updated supply to all open UIs
                TriggerClientEvent('frcp_dealership:client:updateSupply', -1, vehicle.model, getSoldCount(vehicle.model))

                -- Discord log
                exports.frcp_webhook:Send(
                    "dealership",
                    "🚗 Vehicle Purchased",
                    "**CitizenID:** " .. citizenid ..
                    "\n**Vehicle:** " .. vehicle.label ..
                    "\n**Tier:** " .. vehicle.tier:upper() ..
                    "\n**Price:** $" .. vehicle.price ..
                    "\n**Plate:** " .. plate ..
                    "\n**Supply Remaining:** " .. (vehicle.limit == -1 and "Unlimited" or tostring(vehicle.limit - getSoldCount(vehicle.model))),
                    3066993
                )

                print("^2[frcp_dealership] " .. citizenid .. " purchased " .. vehicle.label .. " | Plate: " .. plate .. "^0")
            end
        )
    end)
end

-- ============================================
--  Process Purchase
--  Order: TICKET FIRST, MONEY SECOND
--  If ticket fails, no money was touched.
--  If money fails, ticket is refunded.
--  If DB fails, both are refunded.
-- ============================================

local function processPurchase(src, player, citizenid, vehicle, tierConfig)
    if tierConfig.requiresTicket then
        -- Consume ticket first
        exports.frcp_tickets:ConsumeTicket(citizenid, tierConfig.ticketType, function(consumed)
            if not consumed then
                notify(src, 'error', 'Ticket could not be consumed. Please try again.')
                return
            end

            -- Then deduct money
            if tierConfig.requiresMoney and vehicle.price > 0 then
                local removed = player.Functions.RemoveMoney('bank', vehicle.price, 'frcp-dealership-purchase')
                if not removed then
                    -- Money failed — refund the ticket
                    exports.frcp_tickets:AddTicket(citizenid, tierConfig.ticketType, 1)
                    notify(src, 'error', 'Payment failed. Your ticket has been refunded. Please try again.')
                    return
                end
            end

            finalizePurchase(src, citizenid, vehicle, tierConfig)
        end)
    else
        -- Standard — money only
        if tierConfig.requiresMoney and vehicle.price > 0 then
            local removed = player.Functions.RemoveMoney('bank', vehicle.price, 'frcp-dealership-purchase')
            if not removed then
                notify(src, 'error', 'Payment failed. Please try again.')
                return
            end
        end
        finalizePurchase(src, citizenid, vehicle, tierConfig)
    end
end

-- ============================================
--  Purchase Handler
-- ============================================

RegisterNetEvent('frcp_dealership:server:purchase', function(model)
    local src       = source
    local player    = QBX:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local vehicle   = getVehicleConfig(model)

    if not vehicle then
        notify(src, 'error', 'Invalid vehicle selection.')
        return
    end

    -- Supply limit
    if vehicle.limit ~= -1 and getSoldCount(model) >= vehicle.limit then
        notify(src, 'error', Config.Notifications.limitReached)
        return
    end

    -- Elite cooldown
    if vehicle.tier == 'elite' then
        local now        = os.time()
        local cdTable    = purchaseCooldowns[citizenid]
        local lastBought = cdTable and cdTable[model]
        if lastBought then
            local remaining = COOLDOWN_SECONDS - (now - lastBought)
            if remaining > 0 then
                local mins = math.ceil(remaining / 60)
                notify(src, 'error', ('Elite vehicles have a 30-minute repurchase cooldown. Please wait %d more minute%s.'):format(mins, mins == 1 and '' or 's'))
                return
            end
        end
    end

    local tierConfig = Config.Tiers[vehicle.tier]

    -- Read-only checks before touching anything
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
            processPurchase(src, player, citizenid, vehicle, tierConfig)
        end)
    else
        if tierConfig.requiresMoney and player.PlayerData.money.bank < vehicle.price then
            notify(src, 'error', Config.Notifications.noMoney:gsub("{price}", vehicle.price))
            return
        end
        processPurchase(src, player, citizenid, vehicle, tierConfig)
    end
end)

-- ============================================
--  Catalog Request
-- ============================================

RegisterNetEvent('frcp_dealership:server:getCatalog', function()
    local src    = source
    local player = QBX:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local catalog   = {}

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
            catalog    = catalog,
            tickets    = tickets,
            playerName = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname,
            balance    = player.PlayerData.money.bank,
        })
    end)
end)

-- ============================================
--  Admin: /clearcooldown [serverid]
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
    print('^2[frcp_dealership] Admin ' .. source .. ' cleared cooldown for ' .. cid .. '^0')
end)

-- ============================================
--  Startup
-- ============================================

MySQL.ready(function()
    -- Auto-create cooldowns table
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
    print('^2[frcp_dealership] Server loaded.^0')
end)