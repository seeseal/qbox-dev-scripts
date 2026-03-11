-- ╔══════════════════════════════════════════════╗
-- ║     fcrp_tuner  |  client/nitrous.lua       ║
-- ║  Pressure system: 0.0–1.0 tank.             ║
-- ║  Each activation drains Config.Nitrous.pressureDrain.  ║
-- ║  Each nos_canister item refills canisterRefill.        ║
-- ╚══════════════════════════════════════════════╝

local nosInstalled      = false
local nosActive         = false
local nosPressure       = 1.0   -- 0.0 (empty) → 1.0 (full)
local nosVehicle        = nil
local nosThread         = nil
local nosCountdown      = 0.0
-- FIX #7: Store cooldown as real epoch-ms (os.time()*1000) so it survives
-- game-session restarts and stays in sync with the server's os.time() clock.
local nosCooldownEndEpochMs = 0

local TORQUE_BOOST = 0.50

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

local function MPHtoMS(mph) return mph * 0.44704 end
-- FIX #7: Use real wall-clock (ms) rather than game timer
local function NowMs() return os.time() * 1000 end

local function CooldownRemainingSec()
    if nosCooldownEndEpochMs <= 0 then return 0 end
    return math.max(0.0, (nosCooldownEndEpochMs - NowMs()) / 1000.0)
end

local function FormatCooldown(secs)
    local s = math.ceil(secs)
    local m = math.floor(s / 60)
    local r = s % 60
    return m > 0 and string.format('%dm %ds', m, r) or string.format('%ds', r)
end

local function IsEmpty() return nosPressure < Config.Nitrous.minPressure end

-- ─────────────────────────────────────────────
--  HUD
-- ─────────────────────────────────────────────

local function UpdateNOSHud()
    if not nosInstalled then return end
    local remaining = CooldownRemainingSec()
    if nosActive then
        -- Bar shows burn countdown
        UI_UpdateNos('active', math.max(0.0, nosCountdown / Config.Nitrous.boostDuration), string.format('%.1fs', nosCountdown))
    elseif remaining > 0 then
        -- Bar shows cooldown progress (drains down)
        UI_UpdateNos('cooldown', remaining / Config.Nitrous.cooldown, FormatCooldown(remaining))
    elseif IsEmpty() then
        UI_UpdateNos('empty', 0.0, '')
    else
        -- Bar shows tank pressure
        UI_UpdateNos('ready', nosPressure, string.format('%d%%', math.floor(nosPressure * 100)))
    end
end

-- ─────────────────────────────────────────────
--  ACTIVATE
-- ─────────────────────────────────────────────

local function ActivateNOS(veh)
    if nosActive then return end
    if IsEmpty() then
        Notify('NOS tank empty — use a NOS Canister item to refill.', 'error', 3000)
        return
    end
    local remaining = CooldownRemainingSec()
    if remaining > 0 then
        Notify('⏳ NOS cooldown — ' .. FormatCooldown(remaining) .. ' remaining.', 'error', 3000)
        return
    end

    nosActive    = true
    nosCountdown = Config.Nitrous.boostDuration

    -- Drain pressure immediately on activation (client-authoritative display)
    nosPressure = math.max(0.0, nosPressure - Config.Nitrous.pressureDrain)

    local lockedHealth   = GetVehicleEngineHealth(veh)
    local baseDriveForce = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce')
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce', baseDriveForce * (1.0 + TORQUE_BOOST))

    local boostMS = MPHtoMS(Config.Nitrous.boostMPH)
    local baseSpd = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel')
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', baseSpd + boostMS)

    SetVehicleEngineOn(veh, true, true, false)
    Notify(Lang:t('nos_activated'), 'success', 2000)
    TriggerServerEvent('fcrp_tuner:server:nosUsed', NetworkGetNetworkIdFromEntity(veh))

    nosCooldownEndEpochMs = NowMs() + (Config.Nitrous.cooldown * 1000)

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
    nosCountdown = 0.0

    if IsEmpty() then
        Notify(Lang:t('nos_empty'), 'error', 5000)
    end
end

-- ─────────────────────────────────────────────
--  NOS CANISTER ITEM USE
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:client:useNosCanister', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if not veh or veh == 0 then
        Notify('You must be in a vehicle to use a NOS Canister.', 'error', 3000)
        return
    end
    if not nosInstalled then
        Notify(Lang:t('nos_not_installed'), 'error', 3000)
        return
    end
    if not IsEmpty() and nosPressure >= 1.0 then
        Notify('NOS tank is already full.', 'inform', 3000)
        return
    end

    local ok = lib.progressBar({
        duration     = 4000,
        label        = 'Refilling NOS...',
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
        anim         = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
    })
    if not ok then return end

    TriggerServerEvent('fcrp_tuner:server:useNosCanister', NetworkGetNetworkIdFromEntity(veh))
end)

-- Server confirms refill and sends new pressure level
RegisterNetEvent('fcrp_tuner:client:nosRefillConfirmed', function(newPressure)
    nosPressure             = newPressure or math.min(1.0, nosPressure + Config.Nitrous.canisterRefill)
    nosCooldownEndEpochMs   = 0
    local pct = math.floor(nosPressure * 100)
    Notify(string.format('✅ NOS refilled — tank at %d%%', pct), 'success', 4000)
end)

-- ─────────────────────────────────────────────
--  INPUT LOOP
-- ─────────────────────────────────────────────

local function StartNOSThread(veh)
    nosThread = nil
    UI_ShowNos(true)
    local hudTick = 0
    nosThread = CreateThread(function()
        while nosInstalled do
            Wait(0)
            hudTick = hudTick + 1
            if hudTick >= 30 then   -- update HUD ~2× per second
                hudTick = 0
                UpdateNOSHud()
            end

            local ped    = PlayerPedId()
            local curVeh = GetVehiclePedIsIn(ped, false)

            if curVeh ~= 0 and curVeh == nosVehicle and GetPedInVehicleSeat(nosVehicle, -1) == ped then
                if IsControlJustPressed(0, Config.Nitrous.key) then
                    local remaining = CooldownRemainingSec()
                    if nosActive then
                        -- already burning
                    elseif remaining > 0 then
                        Notify('⏳ NOS cooldown — ' .. FormatCooldown(remaining) .. ' remaining.', 'error', 3000)
                    elseif IsEmpty() then
                        Notify('NOS empty — use a NOS Canister item to refill.', 'error', 3000)
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
--  EVENTS
-- ─────────────────────────────────────────────

-- FIX #7: cooldownUntil is now raw epoch-ms from server (nos_cooldown_until column).
-- Compare directly against NowMs() (os.time()*1000) — no game-timer conversion needed.
AddEventHandler('fcrp_tuner:client:nosInstalled', function(veh, silent, cooldownUntil, pressure)
    if nosInstalled then
        nosInstalled = false
        Wait(0)
    end
    nosInstalled            = true
    nosVehicle              = veh
    nosActive               = false
    nosPressure             = pressure or 1.0
    nosCooldownEndEpochMs   = (cooldownUntil and cooldownUntil > NowMs()) and cooldownUntil or 0
    if not silent then Notify(Lang:t('nos_installed'), 'success', 5000) end
    StartNOSThread(veh)
end)

AddEventHandler('fcrp_tuner:client:nosRemoved', function()
    nosInstalled          = false
    nosActive             = false
    nosPressure           = 1.0
    nosCooldownEndEpochMs = 0
    nosVehicle            = nil
    nosThread             = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    nosInstalled          = false
    nosActive             = false
    nosPressure           = 1.0
    nosCooldownEndEpochMs = 0
end)
