-- ============================================
--  fd_dealership | server.lua
--  All purchase logic handled server-side
-- ============================================

local QBX = exports.qbx_core

-- ============================================
--  Supply Tracking
-- ============================================

local soldCounts = {}

local function loadSoldCounts()
    exports.oxmysql:query('SELECT model, sold FROM fd_dealership_sold', {}, function(result)
        if result then
            for _, row in ipairs(result) do
                soldCounts[row.model] = row.sold
            end
        end
        print("^2[fd_dealership] Sold counts loaded.^0")
    end)
end

local function getSoldCount(model)
    return soldCounts[model] or 0
end

local function incrementSoldCount(model)
    soldCounts[model] = (soldCounts[model] or 0) + 1
    exports.oxmysql:update(
        'INSERT INTO fd_dealership_sold (model, sold) VALUES (?, 1) ON DUPLICATE KEY UPDATE sold = sold + 1',
        { model }
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

local function playerOwnsVehicle(citizenid, model, cb)
    exports.oxmysql:query(
        'SELECT id FROM player_vehicles WHERE citizenid = ? AND vehicle = ?',
        { citizenid, model },
        function(result)
            cb(result and #result > 0)
        end
    )
end

local function generatePlate()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local plate = ""
    for i = 1, 8 do
        plate = plate .. chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return plate
end

local function notify(src, type, description, title, duration)
    TriggerClientEvent('ox_lib:notify', src, {
        type        = type,
        title       = title or "FlameDrive Motors",
        description = description,
        duration    = duration or 5000
    })
end

-- ============================================
--  Finalize Purchase
--  Only runs after all checks pass
-- ============================================

local function finalizePurchase(src, citizenid, vehicle)
    local plate = generatePlate()

    exports.oxmysql:insert(
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
                notify(src, 'error', 'Purchase failed. Please try again.')
                return
            end

            -- Increment supply counter
            incrementSoldCount(vehicle.model)

            -- Close UI
            TriggerClientEvent('fd_dealership:client:closeUI', src)

            -- Spawn vehicle at dealership for player
            TriggerClientEvent('fd_dealership:client:spawnVehicle', src, vehicle.model, plate)

            -- Discord log
            exports.frcp_webhook:Send(
                "dealership",
                "Vehicle Purchased",
                "**CitizenID:** " .. citizenid ..
                "\n**Vehicle:** " .. vehicle.label ..
                "\n**Tier:** " .. vehicle.tier:upper() ..
                "\n**Price:** $" .. vehicle.price ..
                "\n**Plate:** " .. plate ..
                "\n**Supply Remaining:** " .. (vehicle.limit == -1 and "Unlimited" or tostring(vehicle.limit - getSoldCount(vehicle.model))),
                3066993
            )

            print("^2[fd_dealership] " .. citizenid .. " purchased " .. vehicle.label .. "^0")
        end
    )
end

-- ============================================
--  Process Purchase
--  Runs ticket consume + money deduct
-- ============================================

local function processPurchase(src, player, citizenid, vehicle, tierConfig)
    -- Deduct money if required
    if tierConfig.requiresMoney and vehicle.price > 0 then
        player.Functions.RemoveMoney('bank', vehicle.price, 'fd-dealership-purchase')
    end

    -- Consume ticket if required
    if tierConfig.requiresTicket then
        exports.frcp_tickets:ConsumeTicket(citizenid, tierConfig.ticketType, function(consumed)
            if not consumed then
                -- Refund money if already deducted
                if tierConfig.requiresMoney and vehicle.price > 0 then
                    player.Functions.AddMoney('bank', vehicle.price, 'fd-dealership-refund')
                end
                notify(src, 'error', 'Ticket could not be consumed. Please try again.')
                return
            end
            finalizePurchase(src, citizenid, vehicle)
        end)
    else
        finalizePurchase(src, citizenid, vehicle)
    end
end

-- ============================================
--  Purchase Handler
--  Triggered from client when player confirms
-- ============================================

RegisterNetEvent('fd_dealership:server:purchase', function(model)
    local src       = source
    local player    = QBX:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local vehicle   = getVehicleConfig(model)

    -- Valid vehicle?
    if not vehicle then
        notify(src, 'error', 'Invalid vehicle selection.')
        return
    end

    -- Supply limit check
    if vehicle.limit ~= -1 and getSoldCount(model) >= vehicle.limit then
        notify(src, 'error', Config.Notifications.limitReached)
        return
    end

    -- Already owns this vehicle?
    playerOwnsVehicle(citizenid, model, function(owns)
        if owns then
            notify(src, 'error', Config.Notifications.alreadyOwned)
            return
        end

        local tierConfig = Config.Tiers[vehicle.tier]

        -- Ticket check
        if tierConfig.requiresTicket then
            exports.frcp_tickets:HasTicket(citizenid, tierConfig.ticketType, function(hasTicket)
                if not hasTicket then
                    notify(src, 'error', Config.Notifications.noTicket:gsub("{tier}", tierConfig.label))
                    return
                end

                -- Money check
                if tierConfig.requiresMoney and player.PlayerData.money.bank < vehicle.price then
                    notify(src, 'error', Config.Notifications.noMoney:gsub("{price}", vehicle.price))
                    return
                end

                processPurchase(src, player, citizenid, vehicle, tierConfig)
            end)
        else
            -- Standard — money check only
            if player.PlayerData.money.bank < vehicle.price then
                notify(src, 'error', Config.Notifications.noMoney:gsub("{price}", vehicle.price))
                return
            end
            processPurchase(src, player, citizenid, vehicle, tierConfig)
        end
    end)
end)

-- ============================================
--  Catalog Request
--  Client requests vehicle list on UI open
-- ============================================

RegisterNetEvent('fd_dealership:server:getCatalog', function()
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
        TriggerClientEvent('fd_dealership:client:openUI', src, {
            catalog    = catalog,
            tickets    = tickets,
            playerName = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname,
            balance    = player.PlayerData.money.bank,
        })
    end)
end)

-- ============================================
--  Load sold counts on resource start
-- ============================================

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    print('[fd_dealership] Server loaded.')
    loadSoldCounts()
end)