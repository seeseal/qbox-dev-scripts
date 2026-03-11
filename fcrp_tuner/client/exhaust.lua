-- ╔══════════════════════════════════════════════╗
-- ║     fcrp_tuner  |  client/exhaust.lua       ║
-- ║  Anti-lag backfire on throttle lift at      ║
-- ║  high RPM. Particle + audio.                ║
-- ╚══════════════════════════════════════════════╝

local exhaustInstalled = false
local exhaustVehicle   = nil
local exhaustThread    = nil

local PTFX_DICT   = 'core'
local PTFX_EFFECT = 'veh_backfire'

-- ─────────────────────────────────────────────
--  LOAD ASSET
-- ─────────────────────────────────────────────

local ptfxLoaded = false
local function EnsurePtfx()
    if ptfxLoaded then return end
    RequestNamedPtfxAsset(PTFX_DICT)
    local t = 0
    while not HasNamedPtfxAssetLoaded(PTFX_DICT) and t < 2000 do
        Wait(10); t = t + 10
    end
    ptfxLoaded = HasNamedPtfxAssetLoaded(PTFX_DICT)
end

-- ─────────────────────────────────────────────
--  BACKFIRE EFFECT
-- ─────────────────────────────────────────────

local function PlayBackfire(veh)
    if not ptfxLoaded then EnsurePtfx() end
    -- Try primary exhaust bone, then fall back to exhausts
    local bones = { 'exhaust', 'exhaust_2', 'exhaust_3', 'exhaust_4' }
    local fired  = false
    for _, boneName in ipairs(bones) do
        local boneIdx = GetEntityBoneIndexByName(veh, boneName)
        if boneIdx ~= -1 then
            UseParticleFxAssetNextCall(PTFX_DICT)
            StartParticleFxNonLoopedOnEntityBone(
                PTFX_EFFECT, veh,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                boneIdx,
                Config.ExhaustMod.backfireScale,
                false, false, false
            )
            fired = true
        end
    end
    -- Fallback: play at entity position if no exhaust bone found
    if not fired then
        UseParticleFxAssetNextCall(PTFX_DICT)
        StartParticleFxNonLoopedAtCoord(
            PTFX_EFFECT,
            GetEntityCoords(veh),
            0.0, 0.0, 0.0,
            Config.ExhaustMod.backfireScale,
            false, false, false
        )
    end
end

-- ─────────────────────────────────────────────
--  MONITOR THREAD
-- ─────────────────────────────────────────────

local function StartExhaustThread(veh)
    exhaustThread = nil
    EnsurePtfx()

    exhaustThread = CreateThread(function()
        local prevThrottle = 0.0
        local prevRpm      = 0.0

        while exhaustInstalled do
            Wait(50)

            local ped    = PlayerPedId()
            local curVeh = GetVehiclePedIsIn(ped, false)

            if curVeh ~= 0 and curVeh == exhaustVehicle and GetPedInVehicleSeat(exhaustVehicle, -1) == ped then
                local throttle = GetVehicleAccelerator(curVeh)
                local rpm      = GetVehicleCurrentRpm(curVeh)

                -- Detect: was at high RPM + throttle, just released throttle
                local wasArmed   = prevRpm > Config.ExhaustMod.rpmThreshold and prevThrottle > 0.3
                local throttleOff = throttle < Config.ExhaustMod.throttleMax

                if wasArmed and throttleOff then
                    if math.random() < Config.ExhaustMod.backfireChance then
                        PlayBackfire(curVeh)
                    end
                end

                prevThrottle = throttle
                prevRpm      = rpm
            else
                prevThrottle = 0.0
                prevRpm      = 0.0
            end
        end
        exhaustThread = nil
    end)
end

-- ─────────────────────────────────────────────
--  EVENTS
-- ─────────────────────────────────────────────

-- silent = true when called from reapplyMods
AddEventHandler('fcrp_tuner:client:exhaustInstalled', function(veh, silent)
    if not veh or not DoesEntityExist(veh) then return end
    exhaustInstalled = true
    exhaustVehicle   = veh
    if not silent then
        lib.notify({ title = 'Exhaust mod installed! 🔥', type = 'success', duration = 4000 })
    end
    StartExhaustThread(veh)
end)

AddEventHandler('fcrp_tuner:client:exhaustRemoved', function(veh)
    exhaustInstalled = false
    exhaustVehicle   = nil
    exhaustThread    = nil
end)

-- Fix: ensure particles are cleaned up on resource stop
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    exhaustInstalled = false
    exhaustVehicle   = nil
    exhaustThread    = nil
    -- Also clean up drift chip particles if somehow still running
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        RemoveParticleFxFromEntity(veh)
    end
end)
