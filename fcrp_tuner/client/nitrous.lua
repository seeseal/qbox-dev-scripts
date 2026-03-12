-- ╔══════════════════════════════════════════════╗
-- ║     fcrp_tuner  |  client/nitrous.lua       ║
-- ║  Pressure system: 0.0–1.0 tank.             ║
-- ╚══════════════════════════════════════════════╝

local nosInstalled          = false
local nosActive             = false
local nosPressure           = 1.0
local nosVehicle            = nil
local nosThread             = nil
local nosCountdown          = 0.0
local nosCooldownEndEpochMs = 0

-- FIX: Store base handling values at install time so NOS boost is always
-- applied on top of whatever the vehicle currently has (engine chip, stock, etc.)
local nosBaseForce  = nil
local nosBaseSpeed  = nil

-- NOS applies +50% torque (drive force) boost regardless of other mods
local TORQUE_BOOST = 0.50

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

local function MPHtoMS(mph) return mph * 0.44704 end
local function NowMs() return GetCloudTimeAsInt() * 1000 end

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
        UI_UpdateNos('active', math.max(0.0, nosCountdown / Config.Nitrous.boostDuration), string.format('%.1fs', nosCountdown))
    elseif remaining > 0 then
        UI_UpdateNos('cooldown', remaining / Config.Nitrous.cooldown, FormatCooldown(remaining))
    elseif IsEmpty() then
        UI_UpdateNos('empty', 0.0, '')
    else
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

    -- FIX: Snapshot CURRENT handling values right now so the +20% torque boost
    -- stacks correctly whether engine chip is installed or not.
    local curForce = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce')
    local curSpeed = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel')

    -- Apply boost relative to whatever the vehicle currently has
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce',      curForce * (1.0 + TORQUE_BOOST))
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', curSpeed + MPHtoMS(Config.Nitrous.boostMPH))

    local lockedHealth = GetVehicleEngineHealth(veh)
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

    -- Restore exactly what we had before activation (not the base install values)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce',      curForce)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', curSpeed)

    nosActive    = false
    nosCountdown = 0.0

    if IsEmpty() then
        Notify(Lang:t('nos_empty'), 'error', 5000)
    end
end

-- ─────────────────────────────────────────────
--  NOS CANISTER ITEM USE
--  FIX: The server hook fires fcrp_tuner:client:useNosCanister which then
--  triggers the server event. The old code triggered server directly from
--  the client event, causing a double-consume. Now the client event handles
--  the progress bar and fires the server event on completion.
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
    if nosPressure >= 1.0 then
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
    nosPressure           = newPressure or math.min(1.0, nosPressure + Config.Nitrous.canisterRefill)
    nosCooldownEndEpochMs = 0
    local pct = math.floor(nosPressure * 100)
    Notify(string.format('✅ NOS refilled — tank at %d%%', pct), 'success', 4000)
    UpdateNOSHud()
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
            if hudTick >= 30 then
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

AddEventHandler('fcrp_tuner:client:nosInstalled', function(veh, silent, cooldownUntil, pressure)
    if nosInstalled then
        nosInstalled = false
        Wait(0)
    end
    nosInstalled          = true
    nosVehicle            = veh
    nosActive             = false
    nosPressure           = pressure or 1.0
    nosCooldownEndEpochMs = (cooldownUntil and cooldownUntil > NowMs()) and cooldownUntil or 0
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
