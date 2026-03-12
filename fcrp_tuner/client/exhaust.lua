-- ╔══════════════════════════════════════════════╗
-- ║     fcrp_tuner  |  client/exhaust.lua       ║
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
--  FIX: StartParticleFxNonLoopedOnEntityBone is not a valid FiveM native.
--  We resolve the bone world position manually and fire a coord-based effect.
-- ─────────────────────────────────────────────

local function PlayBackfire(veh)
    if not ptfxLoaded then EnsurePtfx() end
    if not ptfxLoaded then return end

    local bones = { 'exhaust', 'exhaust_2', 'exhaust_3', 'exhaust_4' }
    local fired  = false
    local heading = GetEntityHeading(veh)

    for _, boneName in ipairs(bones) do
        local boneIdx = GetEntityBoneIndexByName(veh, boneName)
        if boneIdx ~= -1 then
            local bonePos = GetWorldPositionOfEntityBone(veh, boneIdx)
            UseParticleFxAssetNextCall(PTFX_DICT)
            StartParticleFxNonLoopedAtCoord(
                PTFX_EFFECT,
                bonePos.x, bonePos.y, bonePos.z,
                0.0, 0.0, heading,
                Config.ExhaustMod.backfireScale,
                false, false, false
            )
            fired = true
        end
    end

    -- Fallback: fire at rear of vehicle if no exhaust bone exists
    if not fired then
        local pos = GetOffsetFromEntityInWorldCoords(veh, 0.0, -2.5, 0.3)
        UseParticleFxAssetNextCall(PTFX_DICT)
        StartParticleFxNonLoopedAtCoord(
            PTFX_EFFECT,
            pos.x, pos.y, pos.z,
            0.0, 0.0, heading,
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
                local throttle = GetVehicleThrottleOffset(curVeh)
                local rpm      = GetVehicleCurrentRpm(curVeh)

                local wasArmed    = prevRpm > Config.ExhaustMod.rpmThreshold and prevThrottle > 0.3
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

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    exhaustInstalled = false
    exhaustVehicle   = nil
    exhaustThread    = nil
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then RemoveParticleFxFromEntity(veh) end
end)
