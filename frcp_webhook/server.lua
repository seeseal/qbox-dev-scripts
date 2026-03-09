-- ============================================
--  discord_webhook | server.lua
--  Shared webhook utility — used by all scripts
-- ============================================

-- Add your Discord webhook URLs here
-- One webhook per channel in your Discord server
local webhooks = {
    general    = "https://discord.com/api/webhooks/1480500600721375232/zHMvSvKAPi9T_tfhthKRzzDKfBQFSULCRNF5P2Y7wQnadPTGlsHmG0PwTWpSTxhWji-B",
    dealership = "https://discord.com/api/webhooks/1480500804556423211/n-xV5f9Y-GiaLv_KNylvCI46XUK7H_hcaNvULxYl_ZwoyE9SDD6XZEFYIXJfNgzuvxm7",
    turf       = "https://discord.com/api/webhooks/1480501260523405398/ChJQQurrJuK_97r5xI8O4FJEod3uIU1ZDpwriiOQ3JMjkYTsutdtVZ5ObyxPD1jMzs1C",
    housing    = "https://discord.com/api/webhooks/1480501379142520914/WXkhVsEV9_eCP341JJkIkvkJkHJteC8sCKm_XQ6W0hG_TEfAJncibt9vW3hpZpGZSonq",
    chop       = "https://discord.com/api/webhooks/1480501483047882875/0FenPoJdRLeigJ7yCsCpQrElajUKPIqc6jiHdF2loRaWjYChv-Lw62BC6fRHzkAZ-MF7",
    tickets    = "https://discord.com/api/webhooks/1480501559010922641/ThDXwdXfiymkAK4GExXP49mJx2h5MyB2iX9tVWWsEHua5D81CtEYWdHgWsMnPMqNyE5R ",
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
--  exports.frcp_webhook:Send("turf", "Turf Captured", "Grove Street taken by Lost MC", 3066993)
--  exports.frcp_webhook:SendSimple("chop", "A vehicle was chopped")
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