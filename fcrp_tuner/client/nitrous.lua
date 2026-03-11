-- ╔══════════════════════════════════════════════╗
-- ║     fcrp_tuner  |  client/nitrous.lua       ║
-- ╚══════════════════════════════════════════════╝
-- Refill is now via nos_canister item — no station zone.
-- Cooldown reduced to 5 minutes (Config.Nitrous.cooldown).

local nosInstalled     = false
local nosActive        = false
local nosEmpty         = false
local nosVehicle       = nil
local nosThread        = nil
local nosCountdown     = 0.0
local nosCooldownEndMs = 0

local TORQUE_BOOST = 0.50

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

local function MPHtoMS(mph) return mph * 0.44704 end
local function NowMs()      return GetGameTimer() end

local function CooldownRemainingSec()
    if nosCooldownEndMs <= 0 then return 0 end
    return math.max(0.0, (nosCooldownEndMs - NowMs()) / 1000.0)
end

local function FormatCooldown(secs)
    local s = math.ceil(secs)
    local m = math.floor(s / 60)
    local r = s % 60
    return m > 0 and string.format('%dm %ds', m, r) or string.format('%ds', r)
end

-- ─────────────────────────────────────────────
--  HUD
-- ─────────────────────────────────────────────

local function UpdateNOSHud()
    if not nosInstalled then return end
    local remaining = CooldownRemainingSec()
    if nosActive then
        UI_UpdateNos('active', math.max(0.0, nosCountdown / Config.Nitrous.boostDuration), string.format('%.1fs', nosCountdown))
    elseif remaining > 0 then
        UI_UpdateNos('cooldown', remaining / Config.Nitrous.cooldown, FormatCooldown(remaining))
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

    local lockedHealth   = GetVehicleEngineHealth(veh)
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
--  NOS CANISTER ITEM USE  (replaces station zone)
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
    if not nosEmpty then
        Notify('NOS is already full — no refill needed.', 'inform', 3000)
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

RegisterNetEvent('fcrp_tuner:client:nosRefillConfirmed', function()
    nosEmpty         = false
    nosCooldownEndMs = 0
    Notify(Lang:t('nos_refilled'), 'success', 4000)
end)

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

AddEventHandler('fcrp_tuner:client:nosInstalled', function(veh, silent, cooldownUntil, isEmpty)
    nosInstalled = true
    nosVehicle   = veh
    nosActive    = false
    nosEmpty     = isEmpty or false
    nosCooldownEndMs = (cooldownUntil and cooldownUntil > 0) and (NowMs() + cooldownUntil * 1000) or 0
    if not silent then Notify(Lang:t('nos_installed'), 'success', 5000) end
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
