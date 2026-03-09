-- ============================================
--  frcp_tickets | server.lua
--  All DB calls use exports.oxmysql: directly
--  for compatibility on both full and dev boots
-- ============================================

local QBX = exports.qbx_core

-- ============================================
--  Internal Functions
-- ============================================

local function addTicket(citizenid, ticketType)
    if ticketType ~= "elite" and ticketType ~= "apex" then
        print("^1[frcp_tickets] Invalid ticket type: " .. tostring(ticketType) .. "^0")
        return false
    end

    exports.oxmysql:insert('INSERT INTO player_tickets (citizenid, ticket_type) VALUES (?, ?)', {
        citizenid,
        ticketType
    }, function(id)
        if id then
            print("^2[frcp_tickets] Ticket added — CitizenID: " .. citizenid .. " | Type: " .. ticketType .. "^0")
            exports.frcp_webhook:Send(
                "tickets",
                "Ticket Delivered",
                "**CitizenID:** " .. citizenid .. "\n**Type:** " .. ticketType:upper(),
                3066993
            )
        else
            print("^1[frcp_tickets] Failed to insert ticket for: " .. citizenid .. "^0")
        end
    end)

    return true
end

local function getTicketCount(citizenid, ticketType, cb)
    exports.oxmysql:query('SELECT COUNT(*) as count FROM player_tickets WHERE citizenid = ? AND ticket_type = ?', {
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

local function consumeTicket(citizenid, ticketType, cb)
    exports.oxmysql:query('SELECT id FROM player_tickets WHERE citizenid = ? AND ticket_type = ? ORDER BY created_at ASC LIMIT 1', {
        citizenid,
        ticketType
    }, function(result)
        if not result or not result[1] then
            cb(false)
            return
        end

        local ticketId = result[1].id

        exports.oxmysql:update('DELETE FROM player_tickets WHERE id = ?', { ticketId }, function(rowsAffected)
            if rowsAffected > 0 then
                exports.oxmysql:insert('INSERT INTO player_ticket_history (citizenid, ticket_type) VALUES (?, ?)', {
                    citizenid,
                    ticketType
                })

                exports.frcp_webhook:Send(
                    "tickets",
                    "Ticket Consumed",
                    "**CitizenID:** " .. citizenid .. "\n**Type:** " .. ticketType:upper() .. "\n**Ticket ID:** " .. ticketId,
                    15844367
                )

                cb(true)
            else
                cb(false)
            end
        end)
    end)
end

-- ============================================
--  Exports
--  exports.frcp_tickets:HasTicket(citizenid, "elite", function(hasTicket) end)
--  exports.frcp_tickets:ConsumeTicket(citizenid, "apex", function(success) end)
--  exports.frcp_tickets:GetTicketCounts(citizenid, function(counts) end)
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
    exports.oxmysql:query('SELECT ticket_type, COUNT(*) as count FROM player_tickets WHERE citizenid = ? GROUP BY ticket_type', {
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
--  Run from Tebex dashboard: /addticket {citizenid} elite
-- ============================================

RegisterCommand('addticket', function(source, args)
    if source ~= 0 then
        print("^1[frcp_tickets] /addticket can only be run from server console or Tebex.^0")
        return
    end

    local citizenid  = args[1]
    local ticketType = args[2]

    if not citizenid or not ticketType then
        print("^1[frcp_tickets] Usage: /addticket [citizenid] [elite/apex]^0")
        return
    end

    addTicket(citizenid:lower(), ticketType:lower())
end, true)

-- ============================================
--  Admin Commands
-- ============================================

RegisterCommand('removeticket', function(source, args)
    local player = source ~= 0 and QBX:GetPlayer(source) or nil

    if source ~= 0 and (not player or player.PlayerData.group ~= "admin") then
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
            print("[frcp_tickets] " .. msg)
        end
    end)
end, true)

RegisterCommand('checktickets', function(source, args)
    local player = source ~= 0 and QBX:GetPlayer(source) or nil

    if source ~= 0 and (not player or player.PlayerData.group ~= "admin") then
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

    exports.frcp_tickets:GetTicketCounts(citizenid:lower(), function(counts)
        local msg = "Tickets for " .. citizenid .. " — Elite: " .. counts.elite .. " | Apex: " .. counts.apex

        if source ~= 0 then
            TriggerClientEvent('ox_lib:notify', source, { type = 'info', description = msg })
        else
            print("[frcp_tickets] " .. msg)
        end
    end)
end, true)

RegisterCommand('mytickets', function(source)
    if source == 0 then return end

    local player = QBX:GetPlayer(source)
    if not player then return end

    local citizenid = player.PlayerData.citizenid

    exports.frcp_tickets:GetTicketCounts(citizenid, function(counts)
        TriggerClientEvent('ox_lib:notify', source, {
            type        = 'info',
            title       = 'My Tickets',
            description = 'Elite: ' .. counts.elite .. ' | Apex: ' .. counts.apex,
            duration    = 6000
        })
    end)
end, false)

print("^2[frcp_tickets] Loaded successfully.^0")