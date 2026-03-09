-- ============================================
--  fd_dealership | server.lua
--  Handles all purchase logic server-side
--  Never trust the client — all checks done here
-- ============================================

local QBX = exports.qbx_core

-- ============================================
--  Supply Tracking
--  Loaded from DB on resource start
--  Tracks how many of each vehicle have been sold
-- ============================================

local soldCounts = {}

-- Load sold counts from database on start
local function loadSoldCounts()
    MySQL.query('SELECT model, sold FROM fd_dealership_sold', {}, function(result)
        if result then
            for _, row in ipairs(result) do
                soldCounts[row.model] = row.sold
            end
        end
        print("^2[fd_dealership] Sold counts loaded — " .. #(result or {}) .. " models tracked.^0")
    end)
end

-- Get sold count for a model
local function getSoldCount(model)
    return soldCounts[model] or 0
end

-- Increment sold count in memory and database
local function incrementSoldCount(model)
    soldCounts[model] = (soldCounts[model] or 0) + 1

    MySQL.update(
        'INSERT INTO fd_dealership_sold (model, sold) VALUES (?, 1) ON DUPLICATE KEY UPDATE sold = sold + 1',
        { model },
        function() end
    )
end

-- ============================================
--  Helper — find vehicle config by model
-- ============================================

local function getVehicleConfig(model)
    for _, v in ipairs(Config.Vehicles) do
        if v.model == model then
            return v
        end
    end
    return nil
end

-- ============================================
--  Helper — check if player already owns vehicle
-- ============================================

local function playerOwnsVehicle(citizenid, model, cb)
    MySQL.query(
        'SELECT id FROM player_vehicles WHERE citizenid = ? AND vehicle = ?',
        { citizenid, model },
        function(result)
            cb(result and #result > 0)
        end
    )
end

-- ============================================
--  Helper — generate a random plate
-- ============================================

local function generatePlate()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local plate  = ""
    for i = 1, 8 do
        local rand = math.random(1, #chars)
        plate = plate .. chars:sub(rand, rand)
    end
    return plate
end

-- ============================================
--  Main Purchase Handler
--  Called from client when player confirms purchase
-- ============================================

RegisterNetEvent('fd_dealership:server:purchase', function(model)
    local src      = source
    local player   = QBX:GetPlayer(src)

    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local vehicle   = getVehicleConfig(model)

    -- Vehicle exists in config?
    if not vehicle then
        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'error',
            description = 'Invalid vehicle selection.'
        })
        return
    end

    -- Check server-wide supply limit
    if vehicle.limit ~= -1 and getSoldCount(model) >= vehicle.limit then
        TriggerClientEvent('ox_lib:notify', src, {
            type        = 'error',
            description = Config.Notifications.limitReached
        })
        return
    end

    -- Check if player already owns this vehicle
    playerOwnsVehicle(citizenid, model, function(owns)
        if owns then
            TriggerClientEvent('ox_lib:notify', src, {
                type        = 'error',
                description = Config.Notifications.alreadyOwned
            })
            return
        end

        local tierConfig = Config.Tiers[vehicle.tier]

        -- Check ticket requirement
        if tierConfig.requiresTicket then
            exports.tebex_tickets:HasTicket(citizenid, tierConfig.ticketType, function(hasTicket)
                if not hasTicket then
                    TriggerClientEvent('ox_lib:notify', src, {
                        type        = 'error',
                        description = Config.Notifications.noTicket
                            :gsub("{tier}", tierConfig.label)
                    })
                    return
                end

                -- Has ticket — check money if required
                if tierConfig.requiresMoney then
                    if player.PlayerData.money.bank < vehicle.price then
                        TriggerClientEvent('ox_lib:notify', src, {
                            type        = 'error',
                            description = Config.Notifications.noMoney
                                :gsub("{price}", vehicle.price)
                        })
                        return
                    end
                end

                -- All checks passed — process purchase
                processPurchase(src, player, citizenid, vehicle, tierConfig)
            end)
        else
            -- Standard tier — no ticket needed, just check money
            if player.PlayerData.money.bank < vehicle.price then
                TriggerClientEvent('ox_lib:notify', src, {
                    type        = 'error',
                    description = Config.Notifications.noMoney
                        :gsub("{price}", vehicle.price)
                })
                return
            end

            processPurchase(src, player, citizenid, vehicle, tierConfig)
        end
    end)
end)

-- ============================================
--  Process Purchase
--  Only called after all checks pass
-- ============================================

function processPurchase(src, player, citizenid, vehicle, tierConfig)

    -- Deduct money if required
    if tierConfig.requiresMoney and vehicle.price > 0 then
        player.Functions.RemoveMoney('bank', vehicle.price, 'fd-dealership-purchase')
    end

    -- Consume ticket if required
    if tierConfig.requiresTicket then
        exports.tebex_tickets:ConsumeTicket(citizenid, tierConfig.ticketType, function(consumed)
            if not consumed then
                -- Ticket was consumed between check and purchase (race condition safety)
                TriggerClientEvent('ox_lib:notify', src, {
                    type        = 'error',
                    description = 'Ticket could not be consumed. Please try again.'
                })
                -- Refund money if it was deducted
                if tierConfig.requiresMoney and vehicle.price > 0 then
                    player.Functions.AddMoney('bank', vehicle.price, 'fd-dealership-refund')
                end
                return
            end

            -- Ticket consumed — finalize purchase
            finalizePurchase(src, citizenid, vehicle)
        end)
    else
        finalizePurchase(src, citizenid, vehicle)
    end
end

-- ============================================
--  Finalize Purchase
--  Adds vehicle to player garage and DB
-- ============================================

function finalizePurchase(src, citizenid, vehicle)
    local plate = generatePlate()

    MySQL.insert(
        'INSERT INTO player_vehicles (citizenid, vehicle, hash, mods, plate, garage, fuel, engine, body, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            citizenid,
            vehicle.model,
            GetHashKey(vehicle.model),
            '{}',
            plate,
            'pillboxgarage',  -- default garage, change to match your server
            100,
            1000,
            1000,
            0
        },
        function(id)
            if id then
                -- Track supply
                incrementSoldCount(vehicle.model)

                -- Notify player
                TriggerClientEvent('ox_lib:notify', src, {
                    type        = 'success',
                    title       = 'Purchase Complete',
                    description = Config.Notifications.purchaseSuccess
                        :gsub("{label}", vehicle.label),
                    duration    = 8000
                })

                -- Close UI
                TriggerClientEvent('fd_dealership:client:closeUI', src)

                -- Discord log
                exports.discord_webhook:Send(
                    "dealership",
                    "Vehicle Purchased",
                    "**Player:** " .. citizenid ..
                    "\n**Vehicle:** " .. vehicle.label ..
                    "\n**Tier:** " .. vehicle.tier:upper() ..
                    "\n**Price:** $" .. vehicle.price ..
                    "\n**Plate:** " .. plate ..
                    "\n**Supply Remaining:** " .. (vehicle.limit == -1 and "Unlimited" or (vehicle.limit - getSoldCount(vehicle.model))),
                    3066993
                )

                print("^2[fd_dealership] Purchase complete — " .. citizenid .. " bought " .. vehicle.label .. "^0")
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    type        = 'error',
                    description = 'Purchase failed. Please try again.'
                })
            end
        end
    )
end

-- ============================================
--  Catalog Request
--  Client requests full vehicle list + sold counts
-- ============================================

RegisterNetEvent('fd_dealership:server:getCatalog', function()
    local src    = source
    local player = QBX:GetPlayer(src)
    if not player then return end

    local citizenid = player.PlayerData.citizenid
    local catalog   = {}

    -- Build catalog with availability info
    for _, v in ipairs(Config.Vehicles) do
        local sold      = getSoldCount(v.model)
        local remaining = v.limit == -1 and -1 or (v.limit - sold)
        local available = remaining == -1 or remaining > 0

        table.insert(catalog, {
            label       = v.label,
            model       = v.model,
            tier        = v.tier,
            price       = v.price,
            limit       = v.limit,
            remaining   = remaining,
            available   = available,
            category    = v.category,
            description = v.description,
        })
    end

    -- Check player's tickets
    exports.tebex_tickets:GetTicketCounts(citizenid, function(tickets)
        TriggerClientEvent('fd_dealership:client:openUI', src, {
            catalog    = catalog,
            tickets    = tickets,
            playerName = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname,
            balance    = player.PlayerData.money.bank,
        })
    end)
end)

-- ============================================
--  SQL for this resource
--  Run in phpMyAdmin before first start:
--
--  CREATE TABLE IF NOT EXISTS `fd_dealership_sold` (
--      `model` VARCHAR(50) NOT NULL,
--      `sold`  INT(11)     NOT NULL DEFAULT 0,
--      PRIMARY KEY (`model`)
--  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
--
-- ============================================

-- Load sold counts when resource starts
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        loadSoldCounts()
    end
end)

print("^2[fd_dealership] Server loaded.^0")
```

---

**Save and push to GitHub.**

Commit message:
```
add fd_dealership server.lua