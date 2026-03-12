-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  client/neon.lua        ║
-- ║  Four distinct neon modes:                  ║
-- ║   static  — solid single colour             ║
-- ║   rainbow — smooth full-spectrum cycle      ║
-- ║   rgb     — colour-cycle through 3 colours  ║
-- ║   strobe  — rapid on/off flash              ║
-- ╚══════════════════════════════════════════════╝

local currentMode    = nil
local currentModeTag = nil   -- used to kill loops when mode changes

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

local function StopNeon(veh)
    currentMode    = nil
    currentModeTag = nil
    if veh and DoesEntityExist(veh) then
        SetVehicleNeonLightsColour(veh, 0, 0, 0)
        for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, false) end
    end
end

local function EnableAllNeons(veh)
    for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, true) end
end

-- ─────────────────────────────────────────────
--  MODE 1: STATIC — solid chosen colour
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

    local input = lib.inputDialog('💡 Pick Neon Colour', {
        { type = 'select', label = 'Colour', options = options, required = true },
    })
    if not input then return end

    local chosen = Config.NeonColours[input[1]]
    if not chosen then return end

    ApplyStaticNeon(veh, chosen.r, chosen.g, chosen.b)
    TriggerServerEvent('fcrp_tuner:server:saveNeon',
        NetworkGetNetworkIdFromEntity(veh), mode, chosen.r, chosen.g, chosen.b)
    Notify('💡 Static neon set to ' .. chosen.label, 'success', 3000)
end)

AddEventHandler('fcrp_tuner:client:applyStaticNeon', function(veh, r, g, b)
    if not veh or not DoesEntityExist(veh) then return end
    ApplyStaticNeon(veh, r or 255, g or 255, b or 255)
end)

-- ─────────────────────────────────────────────
--  MODE 2: RAINBOW — smooth full HSV sweep
--  Cycles through the entire colour wheel slowly.
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:startRainbow', function(veh)
    StopNeon(veh)
    currentMode    = 'rainbow'
    local myTag    = {}
    currentModeTag = myTag
    EnableAllNeons(veh)

    TriggerServerEvent('fcrp_tuner:server:saveNeon',
        NetworkGetNetworkIdFromEntity(veh), 'rainbow', nil, nil, nil)

    CreateThread(function()
        local h = 0
        while currentModeTag == myTag do
            -- HSV → RGB (S=1, V=1)
            local i  = math.floor(h / 60) % 6
            local f  = (h / 60) - math.floor(h / 60)
            local q  = math.floor((1 - f) * 255)
            local t2 = math.floor(f * 255)
            local vv = 255
            local r, g, b
            if     i == 0 then r,g,b = vv,t2,0
            elseif i == 1 then r,g,b = q,vv,0
            elseif i == 2 then r,g,b = 0,vv,t2
            elseif i == 3 then r,g,b = 0,q,vv
            elseif i == 4 then r,g,b = t2,0,vv
            else               r,g,b = vv,0,q end
            SetVehicleNeonLightsColour(veh, r, g, b)
            h = (h + 1) % 360
            Wait(16)   -- ~60fps smooth cycle
        end
    end)

    Notify('🌈 Rainbow neon activated!', 'success', 3000)
end)

-- ─────────────────────────────────────────────
--  MODE 3: RGB — cycles through R → G → B in distinct steps
--  Each colour holds for a moment, then cross-fades to the next.
--  Feels different from rainbow (3 hard colours vs full spectrum).
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:startRGB', function(veh)
    StopNeon(veh)
    currentMode    = 'rgb'
    local myTag    = {}
    currentModeTag = myTag
    EnableAllNeons(veh)

    TriggerServerEvent('fcrp_tuner:server:saveNeon',
        NetworkGetNetworkIdFromEntity(veh), 'rgb', nil, nil, nil)

    -- RGB colour cycle: Red → Green → Blue → Red
    local colours = {
        { 255, 0,   0   },  -- Red
        { 0,   255, 0   },  -- Green
        { 0,   0,   255 },  -- Blue
    }

    CreateThread(function()
        local idx   = 1
        local step  = 0
        local steps = 40   -- frames to cross-fade between colours

        while currentModeTag == myTag do
            local from = colours[idx]
            local to   = colours[(idx % #colours) + 1]
            local t    = step / steps
            local r    = math.floor(from[1] + (to[1] - from[1]) * t)
            local g    = math.floor(from[2] + (to[2] - from[2]) * t)
            local b    = math.floor(from[3] + (to[3] - from[3]) * t)
            SetVehicleNeonLightsColour(veh, r, g, b)
            step = step + 1
            if step > steps then
                step = 0
                idx  = (idx % #colours) + 1
                Wait(80)   -- brief hold at full colour
            else
                Wait(16)
            end
        end
    end)

    Notify('🎨 RGB neon activated!', 'success', 3000)
end)

-- reapply hook fires openNeonPicker for rgb mode — redirect to startRGB
AddEventHandler('fcrp_tuner:client:startRGBReapply', function(veh)
    TriggerEvent('fcrp_tuner:client:startRGB', veh)
end)

-- ─────────────────────────────────────────────
--  MODE 4: STROBE — fast white flash
--  Alternates neon ON/OFF rapidly. Very distinct from other modes.
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:startStrobe', function(veh)
    StopNeon(veh)
    currentMode    = 'strobe'
    local myTag    = {}
    currentModeTag = myTag
    EnableAllNeons(veh)

    TriggerServerEvent('fcrp_tuner:server:saveNeon',
        NetworkGetNetworkIdFromEntity(veh), 'strobe', nil, nil, nil)

    CreateThread(function()
        local on = true
        while currentModeTag == myTag do
            if on then
                SetVehicleNeonLightsColour(veh, 255, 255, 255)
                for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, true) end
            else
                for i = 0, 3 do SetVehicleNeonLightEnabled(veh, i, false) end
            end
            on = not on
            Wait(80)   -- ~6 flashes/sec
        end
    end)

    Notify('⚡ Strobe neon activated!', 'success', 3000)
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
