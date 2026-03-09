-- ============================================
--  discord_webhook | server.lua
--  Shared webhook utility — used by all scripts
-- ============================================

-- Add your Discord webhook URLs here
-- One webhook per channel in your Discord server
local webhooks = {
    general    = "",
    dealership = "",
    turf       = "",
    housing    = "",
    chop       = "",
    tickets    = "",
}

-- Colors (decimal) for embed sidebar
-- 3447003  = blue
-- 3066993  = green
-- 15158332 = red
-- 15844367 = yellow
-- 10181046 = purple

local function sendWebhook(channel, title, message, color)
    local webhookUrl = webhooks[channel]

    if not webhookUrl or webhookUrl == "" then
        print("^1[discord_webhook] Missing webhook URL for channel: " .. tostring(channel) .. "^0")
        return
    end

    local payload = json.encode({
        embeds = {{
            title       = tostring(title),
            description = tostring(message),
            color       = color or 3447003,
            footer      = {
                text = "Dev Server • " .. os.date("%d/%m/%Y %H:%M:%S")
            }
        }}
    })

    PerformHttpRequest(webhookUrl, function(statusCode)
        if statusCode ~= 204 then
            print("^1[discord_webhook] Webhook failed for channel: " .. tostring(channel) .. " | Status: " .. tostring(statusCode) .. "^0")
        end
    end, "POST", payload, { ["Content-Type"] = "application/json" })
end

-- ============================================
--  Exports — called by other scripts like this:
--  exports.discord_webhook:Send("turf", "Turf Captured", "Grove Street taken by Lost MC", 3066993)
--  exports.discord_webhook:SendSimple("chop", "A vehicle was chopped")
-- ============================================

exports('Send', function(channel, title, message, color)
    sendWebhook(channel, title, message, color)
end)

exports('SendSimple', function(channel, message)
    sendWebhook(channel, "Server Log", message, 3447003)
end)

-- ============================================
--  Test command — type in server console:
--  discord_test
-- ============================================

RegisterCommand('discord_test', function()
    sendWebhook("general", "Webhook Test", "Discord webhook utility is working correctly.", 3066993)
    print("^2[discord_webhook] Test webhook fired. Check your Discord general channel.^0")
end, true)