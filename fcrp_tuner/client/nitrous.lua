-- ╔══════════════════════════════════════════════╗
-- ║     fcrp_tuner  |  client/nitrous.lua       ║
-- ╚══════════════════════════════════════════════╝

local nosInstalled   = false
local nosActive      = false
local nosEmpty       = false
local nosVehicle     = nil
local nosThread      = nil
local nosCountdown   = 0.0
local nosCooldownEndMs = 0

local TORQUE_BOOST = 0.50

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

local function MPHtoMS(mph) return mph * 0.44704 end
local function NowMs() return GetGameTimer() end

local function CooldownRemainingSec()
    if nosCooldownEndMs <= 0 then return 0 end
    return math.max(0.0, (nosCooldownEndMs - NowMs()) / 1000.0)
end

-- ─────────────────────────────────────────────
--  HUD
-- ─────────────────────────────────────────────

local function FormatCooldown(secs)
    local s = math.ceil(secs)
    local m = math.floor(s / 60)
    local r = s % 60
    if m > 0 then
        return string.format('%dm %ds', m, r)
    else
        return string.format('%ds', r)
    end
end

local function UpdateNOSHud()
    if not nosInstalled then return end
    local remaining = CooldownRemainingSec()

    if nosActive then
        local fraction = math.max(0.0, nosCountdown / Config.Nitrous.boostDuration)
        UI_UpdateNos('active', fraction, string.format('%.1fs', nosCountdown))
    elseif remaining > 0 then
        local fraction = remaining / Config.Nitrous.cooldown
        UI_UpdateNos('cooldown', fraction, FormatCooldown(remaining))
    elseif nosEmpty then
        UI_UpdateNos('empty', 0, '')
    else
        UI_UpdateNos('ready', 1, '')
    end
end

-- ─────────────────────────────────────────────
--  ACTIVATE
-- ─────────────────────────────────────────────

local function ActivateNOS(veh)
    if nosActive or nosEmpty then return end

    local remaining = CooldownRemainingSec()
    if remaining > 0 then
        Notify('⏳ NOS cooldown — ' .. FormatCooldown(remaining) .. ' remaining.', 'error', 3000)
        return
    end

    nosActive    = true
    nosCountdown = Config.Nitrous.boostDuration

    local lockedHealth = GetVehicleEngineHealth(veh)

    local baseDriveForce = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce')
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce', baseDriveForce * (1.0 + TORQUE_BOOST))

    local boostMS = MPHtoMS(Config.Nitrous.boostMPH)
    local baseSpd = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel')
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', baseSpd + boostMS)

    SetVehicleEngineOn(veh, true, true, false)

    Notify(Lang:t('nos_activated'), 'success', 2000)
    TriggerServerEvent('fcrp_tuner:server:nosUsed', NetworkGetNetworkIdFromEntity(veh))

    nosCooldownEndMs = NowMs() + (Config.Nitrous.cooldown * 1000)

    local elapsed  = 0
    local interval = 100
    while elapsed < Config.Nitrous.boostDuration * 1000 do
        Wait(interval)
        elapsed      = elapsed + interval
        nosCountdown = math.max(0.0, Config.Nitrous.boostDuration - elapsed / 1000.0)
        SetVehicleEngineHealth(veh, lockedHealth)
        UpdateNOSHud()
    end

    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce',      baseDriveForce)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', baseSpd)

    nosActive    = false
    nosEmpty     = true
    nosCountdown = 0.0

    Notify(Lang:t('nos_empty'), 'error', 5000)
end

-- ─────────────────────────────────────────────
--  INPUT LOOP
-- ─────────────────────────────────────────────

local function StartNOSThread(veh)
    nosThread = nil
    UI_ShowNos(true)
    nosThread = CreateThread(function()
        while nosInstalled do
            Wait(500)
            local ped    = PlayerPedId()
            local curVeh = GetVehiclePedIsIn(ped, false)

            UpdateNOSHud()

            if curVeh ~= 0 and curVeh == nosVehicle and GetPedInVehicleSeat(nosVehicle, -1) == ped then
                if IsControlJustPressed(0, Config.Nitrous.key) then
                    local remaining = CooldownRemainingSec()
                    if nosActive then
                        -- burning
                    elseif remaining > 0 then
                        Notify('⏳ NOS cooldown — ' .. FormatCooldown(remaining) .. ' remaining.', 'error', 3000)
                    elseif nosEmpty then
                        Notify(Lang:t('nos_no_refill_here'), 'error', 3000)
                    else
                        CreateThread(function() ActivateNOS(nosVehicle) end)
                    end
                end
            end
        end
        UI_ShowNos(false)
        nosThread = nil
    end)
end

-- ─────────────────────────────────────────────
--  NOS REFILL STATION ZONE
-- ─────────────────────────────────────────────

local inRefillZone = false

lib.zones.sphere({
    coords  = Config.NosRefillStation.coords,
    radius  = Config.NosRefillStation.radius,
    onEnter = function()
        inRefillZone = true
        CreateThread(function()
            while inRefillZone do
                local ped = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)

                if veh ~= 0 and nosInstalled and GetPedInVehicleSeat(veh, -1) == ped and not nosActive then
                    local remaining = CooldownRemainingSec()

                    if remaining > 0 then
                        SetTextFont(4)
                        SetTextScale(0.38, 0.38)
                        SetTextColour(255, 200, 0, 220)
                        SetTextOutline()
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName('~y~⏳ Refill cooldown: ~w~' .. FormatCooldown(remaining))
                        EndTextCommandDisplayText(0.5, 0.88)

                    elseif nosEmpty then
                        local priceLabel = lib.math.groupdigits(Config.Nitrous.refillPrice)
                        SetTextFont(4)
                        SetTextScale(0.38, 0.38)
                        SetTextColour(255, 255, 255, 220)
                        SetTextOutline()
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to refill NOS · $' .. priceLabel)
                        EndTextCommandDisplayText(0.5, 0.88)

                        if IsControlJustPressed(0, 51) then
                            local netId = NetworkGetNetworkIdFromEntity(veh)
                            lib.callback('fcrp_tuner:server:nosStationRefill', false,
                                function(result, reason)
                                    if not result then
                                        Notify(reason or Lang:t('transaction_failed'), 'error', 4000)
                                        return
                                    end
                                    nosEmpty         = false
                                    nosCooldownEndMs = 0
                                    Notify(Lang:t('nos_refilled'), 'success', 4000)
                                end,
                            netId)
                        end
                    else
                        SetTextFont(4)
                        SetTextScale(0.38, 0.38)
                        SetTextColour(255, 255, 255, 180)
                        SetTextOutline()
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName('~g~✅ NOS is fully charged.')
                        EndTextCommandDisplayText(0.5, 0.88)
                    end
                end
                Wait(0)
            end
        end)
    end,
    onExit = function()
        inRefillZone = false
    end,
})

-- ─────────────────────────────────────────────
--  EVENTS
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:nosInstalled', function(veh, silent, cooldownUntil, isEmpty)
    nosInstalled = true
    nosVehicle   = veh
    nosActive    = false
    nosEmpty     = isEmpty or false

    if cooldownUntil and cooldownUntil > 0 then
        nosCooldownEndMs = NowMs() + (cooldownUntil * 1000)
    else
        nosCooldownEndMs = 0
    end

    if not silent then
        Notify(Lang:t('nos_installed'), 'success', 5000)
    end
    StartNOSThread(veh)
end)

AddEventHandler('fcrp_tuner:client:nosRefilled', function(veh)
    if not nosInstalled then
        Notify(Lang:t('nos_not_installed'), 'error', 4000)
        return
    end
    nosActive        = false
    nosEmpty         = false
    nosCooldownEndMs = 0
    nosVehicle       = veh
    Notify(Lang:t('nos_refilled'), 'success', 4000)
    StartNOSThread(veh)
end)

AddEventHandler('fcrp_tuner:client:nosRemoved', function()
    nosInstalled     = false
    nosActive        = false
    nosEmpty         = false
    nosCooldownEndMs = 0
    nosVehicle       = nil
    nosThread        = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    nosInstalled     = false
    nosActive        = false
    nosEmpty         = false
    nosCooldownEndMs = 0
end)
