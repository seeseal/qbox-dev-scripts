-- ============================================================
--  frcp_tuner  |  client/main.lua
--  Everything the player's game client actually does:
--  menus, applying vehicle mods, persisting mods on spawn.
-- ============================================================

-- ============================================================
--  State variables  (local to this client only)
-- ============================================================
local currentVehicle  = nil   -- entity handle of the vehicle the player is in
local currentPlate    = nil   -- its licence plate
local installedMods   = {}    -- mod data fetched from server
local nitrousActive   = false -- is nitrous currently firing?
local nitrousCooldown = false -- is cooldown running?
local stanceEditing   = false -- is the stance editor open?
local shopZone        = nil   -- ox_lib circle zone handle

-- ============================================================
--  Helper: safe locale lookup
-- ============================================================
local function L(key, ...)
    if GetLocale then return GetLocale(key, ...) end
    return key
end

-- ============================================================
--  Helper: show an ox_lib notification
-- ============================================================
local function Notify(msg, ntype)
    lib.notify({ type = ntype or 'inform', description = msg })
end

-- ============================================================
--  Helper: get the plate of a vehicle entity
-- ============================================================
local function GetPlate(vehicle)
    return GetVehicleNumberPlateText(vehicle):gsub('%s+', '')
end

-- ============================================================
--  MAP BLIP
-- ============================================================
CreateThread(function()
    local blip = AddBlipForCoord(Config.ShopLocation.x, Config.ShopLocation.y, Config.ShopLocation.z)
    SetBlipSprite(blip,   Config.Blip.Sprite)
    SetBlipColour(blip,   Config.Blip.Colour)
    SetBlipScale(blip,    Config.Blip.Scale)
    SetBlipDisplay(blip,  Config.Blip.Display)
    SetBlipAsShortRange(blip, Config.Blip.Short)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Blip.Label)
    EndTextCommandSetBlipName(blip)
end)

-- ============================================================
--  SHOP ZONE — ox_lib circle zone
--  When a player enters the zone, ox_target shows an interact
--  prompt. We use a simple proximity thread as fallback.
-- ============================================================
CreateThread(function()
    -- Register an ox_target sphere at the shop
    exports.ox_target:addSphereZone({
        coords  = Config.ShopLocation,
        radius  = Config.ShopRadius,
        debug   = false,
        options = {
            {
                name        = 'frcp_tuner_open',
                icon        = 'fas fa-wrench',
                label       = 'Tuner Shop',
                onSelect    = function()
                    OpenTunerMenu()
                end,
                -- Only show the option when the player has the right job
                canInteract = function()
                    local Player = exports.qbx_core:GetPlayerData()
                    return Player and Player.job and Player.job.name == Config.RequiredJob
                end,
            },
        },
    })
end)

-- ============================================================
--  OPEN TUNER MENU  (ox_lib radial/context menu)
-- ============================================================
function OpenTunerMenu()
    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not vehicle or vehicle == 0 then
        Notify(L('not_in_vehicle'), 'error')
        return
    end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        Notify(L('not_driver'), 'error')
        return
    end

    currentVehicle = vehicle
    currentPlate   = GetPlate(vehicle)

    -- Ask server for this vehicle's current mods
    TriggerServerEvent('frcp_tuner:server:GetMods', currentPlate)
    -- Menu is opened once ReceiveMods fires (see event below)
end

-- ============================================================
--  Receive mods from server, then open menu
-- ============================================================
RegisterNetEvent('frcp_tuner:client:ReceiveMods', function(data)
    installedMods = data or {}
    BuildMenu()
end)

-- ============================================================
--  BUILD THE OX_LIB CONTEXT MENU
-- ============================================================
function BuildMenu()
    local items = {}

    -- Engine Chip
    local engineLabel = L('opt_engine_chip')
    if installedMods.engine_chip == 1 then
        engineLabel = engineLabel .. L('badge_installed')
    elseif installedMods.drift_chip == 1 then
        engineLabel = engineLabel .. L('badge_blocked')
    end
    items[#items+1] = {
        title    = engineLabel,
        onSelect = function() InstallEngineChip() end,
        disabled = (installedMods.engine_chip == 1 or installedMods.drift_chip == 1),
    }

    -- Drift Chip
    local driftLabel = L('opt_drift_chip')
    if installedMods.drift_chip == 1 then
        driftLabel = driftLabel .. L('badge_installed')
    elseif installedMods.engine_chip == 1 then
        driftLabel = driftLabel .. L('badge_blocked')
    end
    items[#items+1] = {
        title    = driftLabel,
        onSelect = function() InstallDriftChip() end,
        disabled = (installedMods.drift_chip == 1 or installedMods.engine_chip == 1),
    }

    -- Stance Kit
    local stanceLabel = L('opt_stance_kit')
    if installedMods.stance_data then stanceLabel = stanceLabel .. L('badge_installed') end
    items[#items+1] = {
        title    = stanceLabel,
        onSelect = function() OpenStanceEditor() end,
    }

    -- Nitrous
    local nitLabel = L('opt_nitrous_kit')
    if installedMods.nitrous == 1 then nitLabel = nitLabel .. L('badge_installed') end
    items[#items+1] = {
        title    = nitLabel,
        onSelect = function() InstallNitrous() end,
        disabled = (installedMods.nitrous == 1),
    }

    -- Neon Kit
    local neonLabel = L('opt_neon_kit')
    if installedMods.neon_data then neonLabel = neonLabel .. L('badge_installed') end
    items[#items+1] = {
        title    = neonLabel,
        onSelect = function() OpenNeonMenu() end,
    }

    -- Remove Mods submenu
    items[#items+1] = {
        title    = L('opt_remove_mods'),
        onSelect = function() OpenRemoveMenu() end,
    }

    lib.registerContext({
        id    = 'frcp_tuner_main',
        title = L('menu_title'),
        items = items,
    })
    lib.showContext('frcp_tuner_main')
end

-- ============================================================
--  INSTALL ENGINE CHIP
-- ============================================================
function InstallEngineChip()
    -- Get vehicle depot value from native (class value * simple multiplier)
    local vClass    = GetVehicleClass(currentVehicle)
    local depotValue = (vClass + 1) * 15000   -- rough approximation
    -- Progress bar while installing
    if lib.progressBar({
        duration = Config.ProgressDurations.EngineChip,
        label    = L('prog_install'),
        useWhileDead = false,
        canCancel    = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    }) then
        TriggerServerEvent('frcp_tuner:server:InstallEngineChip', currentPlate, depotValue)
    end
end

-- ============================================================
--  Apply engine chip effect (called by server after DB confirm)
-- ============================================================
RegisterNetEvent('frcp_tuner:client:ApplyEngineChip', function(boost)
    if not currentVehicle or currentVehicle == 0 then return end
    local current = GetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')
    SetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', current + boost)
    SetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fDriveMaxFlatVel', current + boost)
    installedMods.engine_chip = 1
end)

-- ============================================================
--  INSTALL DRIFT CHIP
-- ============================================================
function InstallDriftChip()
    if lib.progressBar({
        duration = Config.ProgressDurations.DriftChip,
        label    = L('prog_install'),
        useWhileDead = false,
        canCancel    = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    }) then
        TriggerServerEvent('frcp_tuner:server:InstallDriftChip', currentPlate)
    end
end

RegisterNetEvent('frcp_tuner:client:ApplyDriftChip', function()
    if not currentVehicle or currentVehicle == 0 then return end
    SetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fTractionCurveMin', Config.DriftChip.TractionLoss)
    SetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fSuspensionCompdamp', Config.DriftChip.Suspension)
    installedMods.drift_chip = 1
end)

-- ============================================================
--  INSTALL NITROUS
-- ============================================================
function InstallNitrous()
    if lib.progressBar({
        duration = Config.ProgressDurations.NitrousKit,
        label    = L('prog_install'),
        useWhileDead = false,
        canCancel    = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    }) then
        TriggerServerEvent('frcp_tuner:server:InstallNitrous', currentPlate)
    end
end

RegisterNetEvent('frcp_tuner:client:NitrousReady', function()
    installedMods.nitrous = 1
    StartNitrousThread()
end)

function StartNitrousThread()
    CreateThread(function()
        while installedMods.nitrous == 1 do
            Wait(0)
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if IsControlJustPressed(0, 21) and not nitrousActive and not nitrousCooldown then
                    -- 21 = LSHIFT
                    nitrousActive = true
                    Notify(L('nitrous_active'), 'inform')
                    local topSpd = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', topSpd + Config.NitrousKit.SpeedBurst)

                    Wait(Config.NitrousKit.Duration * 1000)

                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', topSpd)
                    nitrousActive   = false
                    nitrousCooldown = true

                    -- Cooldown timer
                    SetTimeout(Config.NitrousKit.Cooldown * 1000, function()
                        nitrousCooldown = false
                    end)
                end
            else
                Wait(500) -- not in vehicle — check less often
            end
        end
    end)
end

-- ============================================================
--  STANCE EDITOR  (arrow-key live editor)
-- ============================================================
function OpenStanceEditor()
    if not currentVehicle or currentVehicle == 0 then return end

    -- Read current vehicle handling values as starting point
    local camber = GetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fRollCentreHeightFront')
    local height = GetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fSuspensionRaise')
    local width  = GetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fCollisionDamageMult')
    -- (width is used as a proxy — adjust for your preference)

    stanceEditing = true
    lib.notify({ type = 'inform', description = L('stance_hint'), duration = 10000 })

    CreateThread(function()
        while stanceEditing do
            Wait(0)

            -- Arrow keys — 172=UP, 173=DOWN, 174=LEFT, 175=RIGHT, 18=ENTER, 177=BACKSPACE
            if IsControlJustPressed(0, 174) then camber = camber - Config.StanceKit.CamberStep end
            if IsControlJustPressed(0, 175) then camber = camber + Config.StanceKit.CamberStep end
            if IsControlJustPressed(0, 172) then height = height + Config.StanceKit.HeightStep end
            if IsControlJustPressed(0, 173) then height = height - Config.StanceKit.HeightStep end
            if IsControlJustPressed(0, 57)  then width  = width  + Config.StanceKit.WidthStep  end -- INS
            if IsControlJustPressed(0, 182) then width  = width  - Config.StanceKit.WidthStep  end -- DEL

            -- Live apply
            SetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fRollCentreHeightFront', camber)
            SetVehicleHandlingFloat(currentVehicle, 'CHandlingData', 'fSuspensionRaise', height)

            -- ENTER — save
            if IsControlJustPressed(0, 18) then
                stanceEditing = false
                local stanceData = json.encode({ camber = camber, height = height, width = width })
                if lib.progressBar({
                    duration     = Config.ProgressDurations.StanceKit,
                    label        = L('prog_install'),
                    useWhileDead = false,
                    canCancel    = true,
                    disable      = { move = true, car = true, combat = true },
                }) then
                    TriggerServerEvent('frcp_tuner:server:SaveStance', currentPlate, stanceData)
                    installedMods.stance_data = stanceData
                end
            end

            -- BACKSPACE — cancel
            if IsControlJustPressed(0, 177) then
                stanceEditing = false
                -- Revert to whatever was saved
                if installedMods.stance_data then
                    ApplyStance(currentVehicle, json.decode(installedMods.stance_data))
                end
            end
        end
    end)
end

function ApplyStance(vehicle, data)
    if not data then return end
    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fRollCentreHeightFront', data.camber or 0)
    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fSuspensionRaise', data.height or 0)
end

-- ============================================================
--  NEON KIT MENU
-- ============================================================
function OpenNeonMenu()
    local modeItems = {}
    for i, mode in ipairs(Config.NeonKit.Modes) do
        modeItems[i] = {
            title    = mode,
            onSelect = function() ApplyAndSaveNeon(mode) end,
        }
    end
    lib.registerContext({ id = 'frcp_tuner_neon', title = '🌈 Neon Mode', items = modeItems })
    lib.showContext('frcp_tuner_neon')
end

function ApplyAndSaveNeon(mode)
    if not currentVehicle or currentVehicle == 0 then return end

    local r = Config.NeonKit.DefaultColour.r
    local g = Config.NeonKit.DefaultColour.g
    local b = Config.NeonKit.DefaultColour.b

    -- Enable all four neon positions
    SetVehicleNeonLightEnabled(currentVehicle, 0, true)
    SetVehicleNeonLightEnabled(currentVehicle, 1, true)
    SetVehicleNeonLightEnabled(currentVehicle, 2, true)
    SetVehicleNeonLightEnabled(currentVehicle, 3, true)
    SetVehicleNeonLightsColour(currentVehicle, r, g, b)

    -- Strobe / Rainbow handled in a thread
    if mode == 'Strobe' then StartStrobeThread() end
    if mode == 'Rainbow' then StartRainbowThread() end

    if lib.progressBar({
        duration     = Config.ProgressDurations.NeonKit,
        label        = L('prog_install'),
        useWhileDead = false,
        canCancel    = true,
    }) then
        local neonData = json.encode({ mode = mode, r = r, g = g, b = b })
        TriggerServerEvent('frcp_tuner:server:SaveNeon', currentPlate, neonData)
        installedMods.neon_data = neonData
    end
end

function StartStrobeThread()
    CreateThread(function()
        while installedMods.neon_data and json.decode(installedMods.neon_data).mode == 'Strobe' do
            local on = not GetVehicleNeonLightEnabled(currentVehicle, 0)
            for i = 0, 3 do SetVehicleNeonLightEnabled(currentVehicle, i, on) end
            Wait(Config.NeonKit.StrobeInterval)
        end
    end)
end

function StartRainbowThread()
    local hue = 0
    CreateThread(function()
        while installedMods.neon_data and json.decode(installedMods.neon_data).mode == 'Rainbow' do
            hue = (hue + 1) % 360
            -- Convert HSV hue to RGB
            local r, g, b = HSVtoRGB(hue, 1.0, 1.0)
            SetVehicleNeonLightsColour(currentVehicle, math.floor(r), math.floor(g), math.floor(b))
            Wait(30)
        end
    end)
end

function HSVtoRGB(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if h < 60 then r,g,b = c,x,0
    elseif h < 120 then r,g,b = x,c,0
    elseif h < 180 then r,g,b = 0,c,x
    elseif h < 240 then r,g,b = 0,x,c
    elseif h < 300 then r,g,b = x,0,c
    else r,g,b = c,0,x end
    return (r+m)*255, (g+m)*255, (b+m)*255
end

-- ============================================================
--  REMOVE MODS SUBMENU
-- ============================================================
function OpenRemoveMenu()
    local items = {}
    local function addRemove(label, key)
        items[#items+1] = {
            title    = '🗑️  Remove: ' .. label,
            onSelect = function() ConfirmRemove(key, label) end,
        }
    end
    if installedMods.engine_chip == 1 then addRemove('Engine Chip',  'engine_chip') end
    if installedMods.drift_chip  == 1 then addRemove('Drift Chip',   'drift_chip')  end
    if installedMods.stance_data      then addRemove('Stance Kit',   'stance_data') end
    if installedMods.nitrous     == 1 then addRemove('Nitrous Kit',  'nitrous')     end
    if installedMods.neon_data        then addRemove('Neon Kit',     'neon_data')   end

    if #items == 0 then
        Notify('No mods installed on this vehicle.', 'inform')
        return
    end

    lib.registerContext({ id = 'frcp_tuner_remove', title = '🗑️ Remove Mods', items = items })
    lib.showContext('frcp_tuner_remove')
end

function ConfirmRemove(key, label)
    if lib.progressBar({
        duration     = Config.ProgressDurations.Remove,
        label        = L('prog_remove'),
        useWhileDead = false,
        canCancel    = true,
        disable      = { move = true, car = true, combat = true },
    }) then
        TriggerServerEvent('frcp_tuner:server:RemoveMod', currentPlate, key)
    end
end

-- ============================================================
--  Client-side mod removal (revert handling changes)
-- ============================================================
RegisterNetEvent('frcp_tuner:client:ModRemoved', function(modKey)
    installedMods[modKey] = nil
    if modKey == 'engine_chip' or modKey == 'drift_chip' then
        -- Revert to default handling — simplest safe approach
        RequestHandlingFile(GetEntityModel(currentVehicle or 0))
    elseif modKey == 'neon_data' then
        if currentVehicle and currentVehicle ~= 0 then
            for i = 0, 3 do SetVehicleNeonLightEnabled(currentVehicle, i, false) end
        end
    end
end)

-- ============================================================
--  RESTORE MODS ON VEHICLE SPAWN
--  Triggered whenever the player enters a new vehicle
-- ============================================================
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    StartVehicleWatchThread()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        StartVehicleWatchThread()
    end
end)

local watchingVehicle = nil

function StartVehicleWatchThread()
    CreateThread(function()
        while true do
            Wait(1000)
            local ped     = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle and vehicle ~= 0 and vehicle ~= watchingVehicle then
                watchingVehicle = vehicle
                local plate = GetPlate(vehicle)
                currentVehicle = vehicle
                currentPlate   = plate
                -- Fetch mods for this vehicle and re-apply
                TriggerServerEvent('frcp_tuner:server:GetMods', plate)
            elseif (not vehicle or vehicle == 0) and watchingVehicle then
                watchingVehicle = nil
            end
        end
    end)
end

-- Apply persisted mods when ReceiveMods fires (auto-apply path)
local menuOpen = false

RegisterNetEvent('frcp_tuner:client:ReceiveMods', function(data)
    installedMods = data or {}
    -- If menu was just opened, build it; otherwise silently apply
    if menuOpen then
        menuOpen = false
        BuildMenu()
    else
        AutoApplyMods()
    end
end)

function AutoApplyMods()
    local vehicle = currentVehicle
    if not vehicle or vehicle == 0 then return end

    if installedMods.engine_chip == 1 then
        local current = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', current + Config.EngineChip.SpeedBoost)
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fDriveMaxFlatVel', current + Config.EngineChip.SpeedBoost)
    end
    if installedMods.drift_chip == 1 then
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fTractionCurveMin', Config.DriftChip.TractionLoss)
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fSuspensionCompdamp', Config.DriftChip.Suspension)
    end
    if installedMods.stance_data then
        ApplyStance(vehicle, json.decode(installedMods.stance_data))
    end
    if installedMods.neon_data then
        local nd = json.decode(installedMods.neon_data)
        SetVehicleNeonLightsColour(vehicle, nd.r, nd.g, nd.b)
        for i = 0, 3 do SetVehicleNeonLightEnabled(vehicle, i, true) end
        if nd.mode == 'Strobe' then StartStrobeThread() end
        if nd.mode == 'Rainbow' then StartRainbowThread() end
    end
    if installedMods.nitrous == 1 then
        StartNitrousThread()
    end
end

-- ============================================================
--  PD: remove chip (server asks client to find nearest vehicle)
-- ============================================================
RegisterNetEvent('frcp_tuner:client:PDRemoveChip', function()
    local ped = PlayerPedId()
    local nearbyVehicle = GetClosestVehicle(GetEntityCoords(ped), 5.0, 0, 70)
    if nearbyVehicle == 0 then
        lib.notify({ type = 'error', description = 'No vehicle nearby.' })
        return
    end
    local plate = GetPlate(nearbyVehicle)
    TriggerServerEvent('frcp_tuner:server:PDConfirmRemove', plate)
end)

-- /checkchip — display installed mods
RegisterNetEvent('frcp_tuner:client:CheckChip', function()
    local ped = PlayerPedId()
    local vehicle = GetClosestVehicle(GetEntityCoords(ped), 5.0, 0, 70)
    if vehicle == 0 then
        lib.notify({ type='error', description='No vehicle nearby.' })
        return
    end
    local plate = GetPlate(vehicle)
    TriggerServerEvent('frcp_tuner:server:GetMods', plate)
    -- result will come back via ReceiveMods and display silently
    -- (you can expand this to show a proper popup if you want)
end)

-- ============================================================
--  Notification bridge
-- ============================================================
RegisterNetEvent('frcp_tuner:client:Notify', function(key, ntype)
    Notify(L(key), ntype)
end)
