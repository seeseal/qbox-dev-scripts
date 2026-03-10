-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  client/neon.lua        ║
-- ╚══════════════════════════════════════════════╝

local currentMode = nil

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

local function StopNeon(veh)
    currentMode = nil
    if veh and DoesEntityExist(veh) then
        SetVehicleNeonLightsColour(veh, 0, 0, 0)
        for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, false) end
    end
end

local function EnableAllNeons(veh)
    for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, true) end
end

-- ─────────────────────────────────────────────
--  STATIC / RGB
-- ─────────────────────────────────────────────

local function ApplyStaticNeon(veh, r, g, b)
    StopNeon(veh)
    currentMode = 'static'
    EnableAllNeons(veh)
    SetVehicleNeonLightsColour(veh, r, g, b)
end

AddEventHandler('fcrp_tuner:client:openNeonPicker', function(veh, mode)
    local options = {}
    for i, c in ipairs(Config.NeonColours) do
        options[#options + 1] = { label = c.label, value = i }
    end

    local input = lib.inputDialog('🌈 Pick Neon Colour', {
        { type = 'select', label = 'Colour', options = options, required = true },
    })
    if not input then return end

    local chosen = Config.NeonColours[input[1]]
    if not chosen then return end

    ApplyStaticNeon(veh, chosen.r, chosen.g, chosen.b)
    TriggerServerEvent('fcrp_tuner:server:saveNeon',
        NetworkGetNetworkIdFromEntity(veh), mode, chosen.r, chosen.g, chosen.b)
    Notify(Lang:t('neon_set', { mode:upper(), chosen.label }), 'success', 3000)
end)

AddEventHandler('fcrp_tuner:client:applyStaticNeon', function(veh, r, g, b)
    if not veh or not DoesEntityExist(veh) then return end
    ApplyStaticNeon(veh, r or 255, g or 255, b or 255)
end)

-- ─────────────────────────────────────────────
--  RAINBOW
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:startRainbow', function(veh)
    StopNeon(veh)
    currentMode = 'rainbow'
    EnableAllNeons(veh)

    TriggerServerEvent('fcrp_tuner:server:saveNeon',
        NetworkGetNetworkIdFromEntity(veh), 'rainbow', nil, nil, nil)

    local myMode = currentMode
    CreateThread(function()
        local h = 0
        while currentMode == myMode do
            local i  = math.floor(h / 60) % 6
            local f  = (h / 60) - math.floor(h / 60)
            local p  = 0
            local q  = math.floor((1 - f) * 255)
            local t2 = math.floor(f * 255)
            local vv = 255
            local r, g, b
            if     i == 0 then r,g,b = vv,t2,p
            elseif i == 1 then r,g,b = q,vv,p
            elseif i == 2 then r,g,b = p,vv,t2
            elseif i == 3 then r,g,b = p,q,vv
            elseif i == 4 then r,g,b = t2,p,vv
            else               r,g,b = vv,p,q end
            SetVehicleNeonLightsColour(veh, r, g, b)
            h = (h + 1) % 360
            Wait(16)
        end
    end)

    Notify(Lang:t('neon_rainbow'), 'success', 3000)
end)

-- ─────────────────────────────────────────────
--  STROBE
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:startStrobe', function(veh)
    StopNeon(veh)
    currentMode = 'strobe'
    EnableAllNeons(veh)

    TriggerServerEvent('fcrp_tuner:server:saveNeon',
        NetworkGetNetworkIdFromEntity(veh), 'strobe', nil, nil, nil)

    local myMode = currentMode
    CreateThread(function()
        local on = true
        while currentMode == myMode do
            for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, on) end
            if on then SetVehicleNeonLightsColour(veh, 255, 255, 255) end
            on = not on
            Wait(120)
        end
    end)

    Notify(Lang:t('neon_strobe'), 'success', 3000)
end)

-- ─────────────────────────────────────────────
--  REMOVAL
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:neonRemoved', function(veh)
    StopNeon(veh)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then StopNeon(veh) end
end)
