-- ============================================
--  tebex_tickets | server.lua
-- ============================================

local QBX = exports.qbx_core

-- ============================================
--  Internal Functions
-- ============================================

-- Add a ticket to the database for a player
local function addTicket(citizenid, ticketType)
    if ticketType ~= "elite" and ticketType ~= "apex" then
        print("^1[tebex_tickets] Invalid ticket type: " .. tostring(ticketType) .. "^0")
        return false
    end

    MySQL.insert('INSERT INTO player_tickets (citizenid, ticket_type) VALUES (?, ?)', {
        citizenid,
        ticketType
    }, function(id)
        if id then
            print("^2[tebex_tickets] Ticket added — CitizenID: " .. citizenid .. " | Type: " .. ticketType .. "^0")

            -- Log to Discord
            exports.discord_webhook:Send(
                "tickets",
                "Ticket Delivered",
                "**CitizenID:** " .. citizenid .. "\n**Type:** " .. ticketType:upper(),
                3066993 -- green
            )
        else
            print("^1[tebex_tickets] Failed to insert ticket for: " .. citizenid .. "^0")
        end
    end)

    return true
end

-- Check how many unused tickets a player has
local function getTicketCount(citizenid, ticketType, cb)
    MySQL.query('SELECT COUNT(*) as count FROM player_tickets WHERE citizenid = ? AND ticket_type = ?', {
        citizenid,
        ticketType
    }, function(result)
        if result and result[1] then
            cb(result[1].count)
        else
            cb(0)
        end
    end)
end

-- Check if player has at least one ticket of a type
-- If yes, consume it and return true. If no, return false.
local function consumeTicket(citizenid, ticketType, cb)
    -- Find the oldest unused ticket of that type
    MySQL.query('SELECT id FROM player_tickets WHERE citizenid = ? AND ticket_type = ? ORDER BY created_at ASC LIMIT 1', {
        citizenid,
        ticketType
    }, function(result)
        if not result or not result[1] then
            cb(false)
            return
        end

        local ticketId = result[1].id

        -- Delete that specific ticket row
        MySQL.update('DELETE FROM player_tickets WHERE id = ?', { ticketId }, function(rowsAffected)
            if rowsAffected > 0 then
                -- Log to history table
                MySQL.insert('INSERT INTO player_ticket_history (citizenid, ticket_type) VALUES (?, ?)', {
                    citizenid,
                    ticketType
                })

                -- Log to Discord
                exports.discord_webhook:Send(
                    "tickets",
                    "Ticket Consumed",
                    "**CitizenID:** " .. citizenid .. "\n**Type:** " .. ticketType:upper() .. "\n**Ticket ID:** " .. ticketId,
                    15844367 -- yellow
                )

                cb(true)
            else
                cb(false)
            end
        end)
    end)
end

-- ============================================
--  Exports — used by dealership and used car market
--  
--  Check ticket (does NOT consume):
--  exports.tebex_tickets:HasTicket(citizenid, "elite", function(hasTicket) end)
--
--  Consume ticket (use on purchase):
--  exports.tebex_tickets:ConsumeTicket(citizenid, "apex", function(success) end)
-- ============================================

exports('HasTicket', function(citizenid, ticketType, cb)
    getTicketCount(citizenid, ticketType, function(count)
        cb(count > 0)
    end)
end)

exports('ConsumeTicket', function(citizenid, ticketType, cb)
    consumeTicket(citizenid, ticketType, cb)
end)

exports('GetTicketCounts', function(citizenid, cb)
    MySQL.query('SELECT ticket_type, COUNT(*) as count FROM player_tickets WHERE citizenid = ? GROUP BY ticket_type', {
        citizenid
    }, function(result)
        local counts = { elite = 0, apex = 0 }
        if result then
            for _, row in ipairs(result) do
                counts[row.ticket_type] = row.count
            end
        end
        cb(counts)
    end)
end)

-- ============================================
--  Tebex Delivery Command
--  This is what Tebex fires automatically on purchase
--  Command on Tebex: /addticket {citizenid} elite
-- ============================================

RegisterCommand('addticket', function(source, args)
    -- source = 0 means server console or Tebex (not a player)
    if source ~= 0 then
        print("^1[tebex_tickets] /addticket can only be run from server console or Tebex.^0")
        return
    end

    local citizenid  = args[1]
    local ticketType = args[2]

    if not citizenid or not ticketType then
        print("^1[tebex_tickets] Usage: /addticket [citizenid] [elite/apex]^0")
        return
    end

    addTicket(citizenid:lower(), ticketType:lower())
end, true)

-- ============================================
--  Admin Commands
-- ============================================

-- Manually remove a ticket from a player
RegisterCommand('removeticket', function(source, args)
    local player = source ~= 0 and QBX:GetPlayer(source) or nil

    -- Allow server console or admins only
    if source ~= 0 and (not player or not player.PlayerData.group == "admin") then
        return
    end

    local citizenid  = args[1]
    local ticketType = args[2]

    if not citizenid or not ticketType then
        local msg = "Usage: /removeticket [citizenid] [elite/apex]"
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = msg })
        else
            print(msg)
        end
        return
    end

    consumeTicket(citizenid:lower(), ticketType:lower(), function(success)
        local msg = success
            and ("Ticket removed — " .. citizenid .. " | " .. ticketType)
            or  ("No ticket found for " .. citizenid .. " | " .. ticketType)

        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, {
                type = success and 'success' or 'error',
                description = msg
            })
        else
            print("[tebex_tickets] " .. msg)
        end
    end)
end, true)

-- Check how many tickets a citizenid has
RegisterCommand('checktickets', function(source, args)
    local player = source ~= 0 and QBX:GetPlayer(source) or nil

    if source ~= 0 and (not player or not player.PlayerData.group == "admin") then
        return
    end

    local citizenid = args[1]

    if not citizenid then
        local msg = "Usage: /checktickets [citizenid]"
        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = msg })
        else
            print(msg)
        end
        return
    end

    exports.tebex_tickets:GetTicketCounts(citizenid:lower(), function(counts)
        local msg = "Tickets for " .. citizenid .. " — Elite: " .. counts.elite .. " | Apex: " .. counts.apex

        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { type = 'info', description = msg })
        else
            print("[tebex_tickets] " .. msg)
        end
    end)
end, true)

-- Player checks their own tickets
RegisterCommand('mytickets', function(source)
    if source == 0 then return end

    local player = QBX:GetPlayer(source)
    if not player then return end

    local citizenid = player.PlayerData.citizenid

    exports.tebex_tickets:GetTicketCounts(citizenid, function(counts)
        TriggerClientEvent('o