-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  client/main.lua        ║
-- ╚══════════════════════════════════════════════╝

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

local function GetPlayerGrade()
    local pd = exports.qbx_core:GetPlayerData()
    if not pd or not pd.job then return 0 end
    return pd.job.grade and pd.job.grade.level or 0
end

local function GetGradeConfig(grade)
    return Config.JobGrades[grade] or Config.JobGrades[0]
end

local function HasTunerJob()
    local pd = exports.qbx_core:GetPlayerData()
    return pd.job and pd.job.name == Config.RequiredJob
end

local function GetDrivenVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil end
    if GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return veh
end

-- ─────────────────────────────────────────────
--  SHARED MENU STATE  (declared early — used by multiple functions below)
-- ─────────────────────────────────────────────

local _currentMenuVeh   = nil
local _currentMenuState = nil

-- ─────────────────────────────────────────────
--  DUTY STATE
-- ─────────────────────────────────────────────

local isOnDuty  = false
local dutyBlips = {}

RegisterNetEvent('fcrp_tuner:client:dutyChanged', function(onDuty)
    isOnDuty = onDuty
    -- Clear existing blips
    for _, b in ipairs(dutyBlips) do RemoveBlip(b) end
    dutyBlips = {}
    if onDuty then
        for _, bay in ipairs(Config.WorkshopBays) do
            local b = AddBlipForCoord(bay.coords.x, bay.coords.y, bay.coords.z)
            SetBlipSprite(b, 446)
            SetBlipColour(b, 2)
            SetBlipScale(b, 0.8)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString('Tuner Shop [ON DUTY]')
            EndTextCommandSetBlipName(b)
            dutyBlips[#dutyBlips + 1] = b
        end
        Notify('🔧 You are now ON duty. Ramp zone is active.', 'success', 4000)
    else
        Notify('🔧 You are now OFF duty.', 'inform', 4000)
    end
end)

-- ─────────────────────────────────────────────
--  DRIFT CHIP APPLY / REMOVE
-- ─────────────────────────────────────────────

local function ApplyDriftChip(v)
    SetVehicleModKit(v, 0)
    SetVehicleMod(v, 15, Config.DriftChip.suspensionLevel, false)
    local baseTraction = GetVehicleHandlingFloat(v, 'CHandlingData', 'fTractionCurveMax')
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fTractionCurveMax',  baseTraction * Config.DriftChip.tractionMultiplier)
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fTractionCurveMin',  baseTraction * Config.DriftChip.tractionMultiplier)
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fTractionLossMult',  Config.DriftChip.tractionLossMult)
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fInitialDragCoeff',  Config.DriftChip.dragCoeff)
    local ptfxDict = 'core'
    RequestNamedPtfxAsset(ptfxDict)
    local t = 0
    while not HasNamedPtfxAssetLoaded(ptfxDict) and t < 2000 do Wait(10); t = t + 10 end
    for wheel = 0, 3 do
        local boneName = ({ 'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr' })[wheel + 1]
        local boneIdx  = GetEntityBoneIndexByName(v, boneName)
        if boneIdx ~= -1 then
            UseParticleFxAssetNextCall(ptfxDict)
            StartParticleFxLoopedOnEntityBone('ent_sht_gravel', v, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, boneIdx, 0.8, false, false, false)
        end
    end
end

local function RemoveDriftChip(v)
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fTractionLossMult',  1.0)
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fTractionCurveMax',  2.73)
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fTractionCurveMin',  1.80)
    SetVehicleHandlingFloat(v, 'CHandlingData', 'fInitialDragCoeff',  Config.DriftChip.baseDragCoeff)
    RemoveParticleFxFromEntity(v)
end

-- ─────────────────────────────────────────────
--  PASSENGER LOOKUP + PURCHASE
-- ─────────────────────────────────────────────

local function GetPassengerThenPurchase(veh, productKey, installMs, label, onSuccess)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    lib.callback('fcrp_tuner:server:getPassenger', false, function(passengerSrc)
        CreateThread(function()
            local completed = false
            if Config.ProgressBar then
                completed = lib.progressBar({
                    duration     = installMs,
                    label        = 'Installing ' .. label .. '...',
                    useWhileDead = false,
                    canCancel    = true,
                    disable      = { move = true, car = true, combat = true },
                    anim         = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
                })
            else
                completed = true
            end
            if not completed then
                Notify(Lang:t('cancelled'), 'error', 3000)
                return
            end
            lib.callback('fcrp_tuner:server:purchase', false,
                function(result, reasonOrPrice)
                    if not result then
                        Notify(reasonOrPrice or Lang:t('transaction_failed'), 'error', 4000)
                        return
                    end
                    onSuccess(veh)
                end,
            productKey, nil, passengerSrc, netId)
        end)
    end, netId)
end

-- ─────────────────────────────────────────────
--  ENGINE CHIP
-- ─────────────────────────────────────────────

local function BuyEngineChip(veh, cachedPrice)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local function doDialog(price)
        CreateThread(function()
            local confirmed = lib.alertDialog({
                header   = '🔧 Engine Chip',
                content  = string.format('Increases your vehicle\'s top speed by **%d%%**.\n\n💵 Cost: **$%s dirty cash**', Config.EngineChip.speedBoostPercent, lib.math.groupdigits(price)),
                centered = true,
                cancel   = true,
            })
            if confirmed ~= 'confirm' then return end
            GetPassengerThenPurchase(veh, 'engine_chip', Config.EngineChip.installMs, 'Engine Chip', function(v)
                CreateThread(function()
                    SetVehicleModKit(v, 0)
                    SetVehicleMod(v, 11, 3, false)
                    Wait(500)
                    local cur = GetVehicleHandlingFloat(v, 'CHandlingData', 'fInitialDriveMaxFlatVel')
                    SetVehicleHandlingFloat(v, 'CHandlingData', 'fInitialDriveMaxFlatVel', cur * (1.0 + Config.EngineChip.speedBoostPercent / 100.0))
                    Notify(Lang:t('engine_chip_installed', { Config.EngineChip.speedBoostPercent }), 'success', 5000)
                end)
            end)
        end)
    end
    if cachedPrice then doDialog(cachedPrice)
    else lib.callback('fcrp_tuner:server:getEngineChipPrice', false, function(price) doDialog(price) end, netId) end
end

-- ─────────────────────────────────────────────
--  DRIFT CHIP
-- ─────────────────────────────────────────────

local function BuyDriftChip(veh, cachedPrice)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local function doDialog(price)
        CreateThread(function()
            local confirmed = lib.alertDialog({
                header   = '🚗 Drift Chip',
                content  = string.format('Reduces traction by **20%%** and produces heavy tyre smoke.\n\n💵 Cost: **$%s dirty cash**', lib.math.groupdigits(price)),
                centered = true,
                cancel   = true,
            })
            if confirmed ~= 'confirm' then return end
            GetPassengerThenPurchase(veh, 'drift_chip', Config.DriftChip.installMs, 'Drift Chip', function(v)
                ApplyDriftChip(v)
                Notify(Lang:t('drift_chip_installed'), 'success', 4000)
            end)
        end)
    end
    if cachedPrice then doDialog(cachedPrice)
    else lib.callback('fcrp_tuner:server:getDriftChipPrice', false, function(price) doDialog(price) end, netId) end
end

-- ─────────────────────────────────────────────
--  CRAFT MENU  (Tuner II + Master Tuner only)
-- ─────────────────────────────────────────────

local function OpenCraftMenu()
    local options = {}
    for i, recipe in ipairs(Config.CraftRecipes) do
        local desc = 'Requires: '
        for j, ing in ipairs(recipe.ingredients) do
            desc = desc .. ing.amount .. 'x ' .. ing.label
            if j < #recipe.ingredients then desc = desc .. ', ' end
        end
        options[#options + 1] = {
            title       = recipe.icon .. '  ' .. recipe.label,
            description = desc,
            onSelect    = function()
                lib.callback('fcrp_tuner:server:craftItem', false, function(result, reason)
                    if not result then
                        Notify(reason or 'Crafting failed.', 'error', 4000)
                        return
                    end
                    local ok = lib.progressBar({
                        duration     = recipe.craftMs,
                        label        = 'Crafting ' .. recipe.label .. '...',
                        useWhileDead = false,
                        canCancel    = true,
                        disable      = { move = true, car = true, combat = true },
                        anim         = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
                    })
                    if not ok then
                        TriggerServerEvent('fcrp_tuner:server:craftCancel', i)
                        return
                    end
                    TriggerServerEvent('fcrp_tuner:server:craftComplete', i)
                    Notify('✅ ' .. recipe.label .. ' crafted!', 'success', 4000)
                end, i)
            end,
        }
    end
    lib.registerContext({ id = 'fcrp_tuner_craft', title = '🛠️ Craft Items', options = options })
    lib.showContext('fcrp_tuner_craft')
end

-- ─────────────────────────────────────────────
--  REMOVE MENU
-- ─────────────────────────────────────────────

local function OpenRemoveMenu(veh, state)
    local items = {}
    items[#items + 1] = { type = 'section', label = 'Remove Mods' }

    if state.engine_chip  then items[#items+1] = { icon='🔧', name='Remove Engine Chip',  desc='Uninstall the engine speed chip',    action='remove_engine_chip'  } end
    if state.drift_chip   then items[#items+1] = { icon='🚗', name='Remove Drift Chip',   desc='Uninstall the drift handling chip',  action='remove_drift_chip'   } end
    if state.nos          then items[#items+1] = { icon='🚀', name='Remove NOS Kit',      desc='Uninstall the nitrous kit',          action='remove_nos'          } end
    if state.neon_mode    then items[#items+1] = { icon='💡', name='Remove Neon',         desc='Turn off and remove neon lighting',  action='remove_neon'         } end
    if state.has_stance   then items[#items+1] = { icon='📐', name='Remove Stance Kit',   desc='Reset camber and ride height',       action='remove_stance'       } end
    if state.has_exhaust  then items[#items+1] = { icon='💨', name='Remove Exhaust Mod',  desc='Remove anti-lag backfire mod',       action='remove_exhaust'      } end
    if state.fake_plate   then items[#items+1] = { icon='🪪', name='Remove Fake Plate',   desc='Restore original plate · ' .. state.fake_plate, action='remove_fake_plate'  } end

    if #items <= 1 then
        Notify('No mods installed on this vehicle.', 'inform', 3000)
        return
    end

    _currentMenuVeh   = veh
    _currentMenuState = state
    UI_OpenShop(items, '')
end

-- ─────────────────────────────────────────────
--  BUILD SHOP ITEMS
-- ─────────────────────────────────────────────

local function BuildShopItems(veh, state, isTuner, grade, enginePrice, driftPrice)
    local gradeConfig = GetGradeConfig(grade)
    local items       = {}
    local lock        = not isTuner and '  🔒 Tuner required' or ''

    -- ── PERFORMANCE ──────────────────────────
    items[#items+1] = { type = 'section', label = 'Performance' }

    if state.engine_chip then
        items[#items+1] = { icon='🔧', name='Engine Chip', desc='Already installed · PD /removechip to remove', installed=true }
    elseif state.drift_chip then
        items[#items+1] = { icon='🔧', name='Engine Chip  🚫 Blocked', desc='Remove drift chip first', disabled=true }
    else
        items[#items+1] = { icon='🔧', name='Engine Chip', desc='+' .. Config.EngineChip.speedBoostPercent .. '% top speed · dirty cash' .. lock, price=enginePrice or Config.EngineChip.basePrice, action='buy_engine_chip', disabled=not isTuner }
    end

    if state.drift_chip then
        items[#items+1] = { icon='🚗', name='Drift Chip', desc='Soft suspension + high traction loss', installed=true }
    elseif state.engine_chip then
        items[#items+1] = { icon='🚗', name='Drift Chip  🚫 Blocked', desc='Remove engine chip first', disabled=true }
    else
        items[#items+1] = { icon='🚗', name='Drift Chip', desc='Soft suspension + high traction loss · dirty cash' .. lock, price=driftPrice or Config.DriftChip.basePrice, action='buy_drift_chip', disabled=not isTuner }
    end

    if state.has_stance then
        items[#items+1] = { icon='📐', name='Stance Kit', desc='Already installed', installed=true }
    else
        items[#items+1] = { icon='📐', name='Stance Kit', desc='Camber · ride height · wheel distance' .. lock, price=Config.StanceKit.price, action='buy_stance_kit', disabled=not isTuner }
    end

    -- ── EXHAUST ───────────────────────────────
    items[#items+1] = { type = 'section', label = 'Exhaust' }

    if state.has_exhaust then
        items[#items+1] = { icon='💨', name='Exhaust Mod', desc='Anti-lag backfire active 🔥', installed=true }
    else
        items[#items+1] = { icon='💨', name='Exhaust Mod', desc='Anti-lag backfire flames on throttle lift' .. lock, price=Config.ExhaustMod.price, action='buy_exhaust_mod', disabled=not isTuner }
    end

    -- ── NITROUS ───────────────────────────────
    items[#items+1] = { type = 'section', label = 'Nitrous' }

    if state.nos then
        local pct = math.floor((state.nos_pressure or 0) * 100)
        items[#items+1] = { icon='🚀', name='Nitrous Kit  (installed)', desc='Tank: ' .. pct .. '% · Use nos_canister to refill · LEFT SHIFT to activate', installed=true }
    else
        items[#items+1] = { icon='🚀', name='Install Nitrous Kit', desc='+' .. Config.Nitrous.boostMPH .. ' MPH · ' .. Config.Nitrous.boostDuration .. 's burst · refill with NOS Canister item' .. lock, price=Config.Nitrous.price, action='buy_nitrous_kit', disabled=not isTuner }
    end

    -- ── NEON ──────────────────────────────────
    items[#items+1] = { type = 'section', label = 'Neon Kits' }

    local neonDefs = {
        { key='neon_static',  icon='💡', name='Static Neon',  price=Config.NeonPrices.static  },
        { key='neon_rainbow', icon='🌈', name='Rainbow Neon', price=Config.NeonPrices.rainbow },
        { key='neon_rgb',     icon='🎨', name='RGB Neon',     price=Config.NeonPrices.rgb     },
        { key='neon_strobe',  icon='⚡', name='Strobe Neon',  price=Config.NeonPrices.strobe  },
    }
    for _, n in ipairs(neonDefs) do
        items[#items+1] = { icon=n.icon, name=n.name .. lock, desc='Neon lighting · dirty cash', price=n.price, action='buy_neon', actionData={ key=n.key }, disabled=not isTuner }
    end

    -- ── MANAGEMENT ────────────────────────────
    items[#items+1] = { type = 'section', label = 'Management' }

    -- Fake Plate
    if state.fake_plate then
        items[#items+1] = { icon='🪪', name='Fake Plate', desc='Active · ' .. state.fake_plate, installed=true }
    else
        items[#items+1] = { icon='🪪', name='Fake Plate', desc='Display a custom plate · dirty cash' .. lock, price=Config.FakePlate.price, action='buy_fake_plate', disabled=not isTuner }
    end

    items[#items+1] = { icon='🗑️', name='Remove Mods', desc='Uninstall any mod from this vehicle', action='open_remove_menu', disabled=not isTuner }

    if isTuner and gradeConfig.canCraft then
        items[#items+1] = { icon='🛠️', name='Craft Items', desc='Craft chips, rods and canisters  (' .. gradeConfig.label .. ')', action='open_craft_menu' }
    end
    if isTuner and gradeConfig.isOwner then
        items[#items+1] = { icon='💰', name='Society Stash', desc='Access the tuner society funds', action='open_society_stash' }
    end

    return items
end

-- ─────────────────────────────────────────────
--  WORKSHOP BAYS  — vehicle pull-in zones
--  Replaces the old RampLocations system.
--  Player drives into a bay, presses E to open the shop.
-- ─────────────────────────────────────────────

local inRamp   = false
local menuOpen = false

local _cachedState       = nil
local _cachedEnginePrice = nil
local _cachedDriftPrice  = nil

local function PrefetchState(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    lib.callback('fcrp_tuner:server:getVehicleState', false, function(state)
        if not state then return end
        _cachedState = state
        if not state.engine_chip and not state.drift_chip then
            lib.callback('fcrp_tuner:server:getEngineChipPrice', false, function(ep)
                _cachedEnginePrice = ep
                lib.callback('fcrp_tuner:server:getDriftChipPrice', false, function(dp)
                    _cachedDriftPrice = dp
                end, netId)
            end, netId)
        end
    end, netId)
end

for _, bay in ipairs(Config.WorkshopBays) do
    local coords = vec3(bay.coords.x, bay.coords.y, bay.coords.z)
    lib.zones.sphere({
        coords  = coords,
        radius  = Config.RampRadius,
        onEnter = function()
            local veh = GetDrivenVehicle()
            if not veh then
                Notify(Lang:t('ramp_no_vehicle'), 'error', 4000)
                return
            end
            inRamp = true
            local netId = NetworkGetNetworkIdFromEntity(veh)
            local value = GetVehicleValue(veh)
            TriggerServerEvent('fcrp_tuner:server:setVehicleValue', netId, value)
            PrefetchState(veh)

            CreateThread(function()
                while inRamp do
                    if not menuOpen and IsControlJustPressed(0, 51) then
                        local v = GetDrivenVehicle()
                        if not v then
                            Notify(Lang:t('ramp_no_vehicle'), 'error', 3000)
                        elseif HasTunerJob() and not isOnDuty then
                            Notify('You are off duty. Use /tunerduty to go on duty.', 'error', 3000)
                        else
                            menuOpen = true
                            local isTuner = HasTunerJob()
                            local grade   = isTuner and GetPlayerGrade() or 0

                            local function openWithState(state, ep, dp)
                                _currentMenuVeh   = v
                                _currentMenuState = state
                                local items = BuildShopItems(v, state, isTuner, grade, ep, dp)
                                UI_OpenShop(items, '')
                                menuOpen = false
                            end

                            if _cachedState then
                                openWithState(_cachedState, _cachedEnginePrice, _cachedDriftPrice)
                            else
                                local nId = NetworkGetNetworkIdFromEntity(v)
                                lib.callback('fcrp_tuner:server:getVehicleState', false, function(state)
                                    if not state then menuOpen = false return end
                                    if not state.engine_chip and not state.drift_chip then
                                        lib.callback('fcrp_tuner:server:getEngineChipPrice', false, function(ep)
                                            lib.callback('fcrp_tuner:server:getDriftChipPrice', false, function(dp)
                                                openWithState(state, ep, dp)
                                            end, nId)
                                        end, nId)
                                    else
                                        openWithState(state, nil, nil)
                                    end
                                end, nId)
                            end
                        end
                    end
                    Wait(0)
                end
            end)
        end,
        onExit = function()
            inRamp             = false
            menuOpen           = false
            _cachedState       = nil
            _cachedEnginePrice = nil
            _cachedDriftPrice  = nil
        end,
    })
end

-- ─────────────────────────────────────────────
--  SHOP ENTRANCE  — on-foot interaction
--  Tuner or customer stands here to access the shop
--  for a vehicle parked in a nearby bay.
-- ─────────────────────────────────────────────

local _inShopZone = false
lib.zones.sphere({
    coords  = Config.ShopLocation,
    radius  = Config.ShopRadius,
    onEnter = function()
        lib.showTextUI('[E] Open Tuner Shop', { position = 'left-center' })
        _inShopZone = true

        CreateThread(function()
            while _inShopZone do
                if IsControlJustPressed(0, 51) then
                    local ped    = PlayerPedId()
                    local pos    = GetEntityCoords(ped)
                    local target = nil
                    local bestDist = 20.0
                    for _, bay in ipairs(Config.WorkshopBays) do
                        local bcoords = vec3(bay.coords.x, bay.coords.y, bay.coords.z)
                        local veh = GetClosestVehicle(bcoords.x, bcoords.y, bcoords.z, Config.RampRadius, 0, 71)
                        if veh and veh ~= 0 then
                            local d = #(pos - GetEntityCoords(veh))
                            if d < bestDist then bestDist = d; target = veh end
                        end
                    end
                    if not target then
                        Notify('No vehicle in the workshop bays.', 'error', 3000)
                    else
                        local isTuner = HasTunerJob()
                        local grade   = isTuner and GetPlayerGrade() or 0
                        local nId     = NetworkGetNetworkIdFromEntity(target)
                        local value   = GetVehicleValue(target)
                        TriggerServerEvent('fcrp_tuner:server:setVehicleValue', nId, value)
                        lib.callback('fcrp_tuner:server:getVehicleState', false, function(state)
                            if not state then return end
                            lib.callback('fcrp_tuner:server:getEngineChipPrice', false, function(ep)
                                lib.callback('fcrp_tuner:server:getDriftChipPrice', false, function(dp)
                                    _currentMenuVeh   = target
                                    _currentMenuState = state
                                    local items = BuildShopItems(target, state, isTuner, grade, ep, dp)
                                    UI_OpenShop(items, '')
                                end, nId)
                            end, nId)
                        end, nId)
                    end
                end
                Wait(0)
            end
        end)
    end,
    onExit = function()
        _inShopZone = false
        lib.hideTextUI()
    end,
})

-- ─────────────────────────────────────────────
--  CLOCK-IN LOCATION  — duty toggle on-foot
-- ─────────────────────────────────────────────

local _inClockZone = false

-- Keep the clock-in text UI label in sync whenever duty state changes
local _origDutyChanged = nil
AddEventHandler('fcrp_tuner:client:dutyChanged', function()
    if _inClockZone then
        lib.showTextUI('[E] Clock ' .. (isOnDuty and 'Out' or 'In'), { position = 'left-center' })
    end
end)

lib.zones.sphere({
    coords  = Config.ClockInLocation,
    radius  = 1.5,
    onEnter = function()
        if not HasTunerJob() then return end
        lib.showTextUI('[E] Clock ' .. (isOnDuty and 'Out' or 'In'), { position = 'left-center' })
        _inClockZone = true

        CreateThread(function()
            while _inClockZone do
                if IsControlJustPressed(0, 51) then
                    TriggerServerEvent('fcrp_tuner:server:clockIn')
                end
                Wait(0)
            end
        end)
    end,
    onExit = function()
        if not _inClockZone then return end
        _inClockZone = false
        lib.hideTextUI()
    end,
})

-- ─────────────────────────────────────────────
--  STASH LOCATION  — society stash (Master Tuner only)
-- ─────────────────────────────────────────────

local _inStashZone = false
lib.zones.sphere({
    coords  = Config.StashLocation,
    radius  = 1.5,
    onEnter = function()
        if not HasTunerJob() then return end
        local grade = GetPlayerGrade()
        if not Config.JobGrades[grade] or not Config.JobGrades[grade].isOwner then return end
        lib.showTextUI('[E] Society Stash', { position = 'left-center' })
        _inStashZone = true

        CreateThread(function()
            while _inStashZone do
                if IsControlJustPressed(0, 51) then
                    TriggerServerEvent('fcrp_tuner:server:openSocietyStash')
                end
                Wait(0)
            end
        end)
    end,
    onExit = function()
        if not _inStashZone then return end
        _inStashZone = false
        lib.hideTextUI()
    end,
})

-- ─────────────────────────────────────────────
--  CRAFTING AREA  — single merged zone covering all bench locations
--  Bench coords are ≤2.75 m apart; a radius-4 zone centred on their
--  midpoint covers them all without triggering multiple onEnter/onExit events.
-- ─────────────────────────────────────────────

local _inCraftZone = false

local function CalcCentroid(locations)
    local sx, sy, sz = 0, 0, 0
    for _, v in ipairs(locations) do sx = sx + v.x; sy = sy + v.y; sz = sz + v.z end
    local n = #locations
    return vec3(sx / n, sy / n, sz / n)
end

lib.zones.sphere({
    coords  = CalcCentroid(Config.CraftingLocations),
    radius  = 4.0,
    onEnter = function()
        if not HasTunerJob() then return end
        local grade = GetPlayerGrade()
        if not Config.JobGrades[grade] or not Config.JobGrades[grade].canCraft then return end
        lib.showTextUI('[E] Crafting Bench', { position = 'left-center' })
        _inCraftZone = true

        CreateThread(function()
            while _inCraftZone do
                if IsControlJustPressed(0, 51) then
                    OpenCraftMenu()
                end
                Wait(0)
            end
        end)
    end,
    onExit = function()
        if not _inCraftZone then return end
        _inCraftZone = false
        lib.hideTextUI()
    end,
})

-- ─────────────────────────────────────────────
--  SHOP ACTION HANDLER
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:client:shopAction', function(action, data)
    local veh   = _currentMenuVeh
    local state = _currentMenuState
    if not veh or not DoesEntityExist(veh) then
        Notify('Vehicle not found.', 'error', 3000)
        return
    end

    UI_CloseShop()

    if action == 'buy_engine_chip' then
        BuyEngineChip(veh, _cachedEnginePrice)

    elseif action == 'buy_drift_chip' then
        BuyDriftChip(veh, _cachedDriftPrice)

    elseif action == 'buy_stance_kit' then
        GetPassengerThenPurchase(veh, 'stance_kit', Config.StanceKit.installMs, 'Stance Kit', function(v)
            TriggerEvent('fcrp_tuner:client:openStance', v)
        end)

    elseif action == 'buy_exhaust_mod' then
        GetPassengerThenPurchase(veh, 'exhaust_mod', Config.ExhaustMod.installMs, 'Exhaust Mod', function(v)
            TriggerEvent('fcrp_tuner:client:exhaustInstalled', v)
        end)

    elseif action == 'buy_nitrous_kit' then
        GetPassengerThenPurchase(veh, 'nitrous_kit', Config.Nitrous.installMs, 'Nitrous Kit', function(v)
            TriggerEvent('fcrp_tuner:client:nosInstalled', v)
        end)

    elseif action == 'buy_neon' then
        local key = data and data.key or 'neon_static'
        local neonMap = {
            neon_static  = function(v) TriggerEvent('fcrp_tuner:client:openNeonPicker', v, 'static')  end,
            neon_rainbow = function(v) TriggerEvent('fcrp_tuner:client:startRainbow', v)              end,
            neon_rgb     = function(v) TriggerEvent('fcrp_tuner:client:openNeonPicker', v, 'rgb')     end,
            neon_strobe  = function(v) TriggerEvent('fcrp_tuner:client:startStrobe', v)               end,
        }
        local fn = neonMap[key]
        if fn then GetPassengerThenPurchase(veh, key, Config.NeonInstallMs, key, fn) end

    elseif action == 'buy_fake_plate' then
        CreateThread(function()
            local input = lib.inputDialog('🪪 Fake Plate', {
                { type = 'input', label = 'Custom plate text (max 8 chars, A-Z 0-9)', required = true, max = 8, min = 1 },
            })
            if not input or not input[1] or #input[1] == 0 then return end
            local plateText = string.upper(input[1])

            local confirmed = lib.alertDialog({
                header   = '🪪 Fake Plate',
                content  = string.format('Apply fake plate **%s** to your vehicle?\n\n💵 Cost: **$%s dirty cash**', plateText, lib.math.groupdigits(Config.FakePlate.price)),
                centered = true,
                cancel   = true,
            })
            if confirmed ~= 'confirm' then return end

            GetPassengerThenPurchase(veh, 'fake_plate', Config.FakePlate.installMs, 'Fake Plate', function(v)
                TriggerServerEvent('fcrp_tuner:server:applyFakePlate', NetworkGetNetworkIdFromEntity(v), plateText)
            end)
        end)

    elseif action == 'open_remove_menu' then
        local netId = NetworkGetNetworkIdFromEntity(veh)
        lib.callback('fcrp_tuner:server:getVehicleState', false, function(freshState)
            if freshState then OpenRemoveMenu(veh, freshState) end
        end, netId)

    elseif action == 'open_craft_menu' then
        OpenCraftMenu()

    elseif action == 'open_society_stash' then
        TriggerServerEvent('fcrp_tuner:server:openSocietyStash')

    -- ── Remove actions ─────────────────────────
    elseif action == 'remove_engine_chip' then
        CreateThread(function()
            local ok = lib.progressBar({ duration=Config.EngineChip.removeMs, label='Removing Engine Chip...', useWhileDead=false, canCancel=true, disable={move=true,car=true,combat=true}, anim={dict='mini@repair',clip='fixing_a_ped',flag=49} })
            if not ok then return end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            lib.callback('fcrp_tuner:server:removeMod', false, function(result, reason)
                if not result then Notify(reason, 'error', 4000) return end
                local cur = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel')
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', math.max(10.0, cur / (1.0 + Config.EngineChip.speedBoostPercent / 100.0)))
                Notify(Lang:t('engine_chip_removed'), 'success', 4000)
            end, netId, 'engine_chip')
        end)

    elseif action == 'remove_drift_chip' then
        CreateThread(function()
            local ok = lib.progressBar({ duration=Config.DriftChip.removeMs, label='Removing Drift Chip...', useWhileDead=false, canCancel=true, disable={move=true,car=true,combat=true}, anim={dict='mini@repair',clip='fixing_a_ped',flag=49} })
            if not ok then return end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            lib.callback('fcrp_tuner:server:removeMod', false, function(result, reason)
                if not result then Notify(reason, 'error', 4000) return end
                RemoveDriftChip(veh)
                Notify(Lang:t('drift_chip_removed'), 'success', 4000)
            end, netId, 'drift_chip')
        end)

    elseif action == 'remove_nos' then
        CreateThread(function()
            local ok = lib.progressBar({ duration=Config.Nitrous.removeMs, label='Removing NOS Kit...', useWhileDead=false, canCancel=true, disable={move=true,car=true,combat=true}, anim={dict='mini@repair',clip='fixing_a_ped',flag=49} })
            if not ok then return end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            lib.callback('fcrp_tuner:server:removeMod', false, function(result, reason)
                if not result then Notify(reason, 'error', 4000) return end
                TriggerEvent('fcrp_tuner:client:nosRemoved')
                Notify(Lang:t('nos_removed'), 'success', 4000)
            end, netId, 'nos')
        end)

    elseif action == 'remove_neon' then
        CreateThread(function()
            local ok = lib.progressBar({ duration=Config.NeonRemoveMs, label='Removing Neon...', useWhileDead=false, canCancel=true, disable={move=true,car=true,combat=true}, anim={dict='mini@repair',clip='fixing_a_ped',flag=49} })
            if not ok then return end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            lib.callback('fcrp_tuner:server:removeMod', false, function(result, reason)
                if not result then Notify(reason, 'error', 4000) return end
                TriggerEvent('fcrp_tuner:client:neonRemoved', veh)
                Notify(Lang:t('neon_removed'), 'success', 4000)
            end, netId, 'neon')
        end)

    elseif action == 'remove_stance' then
        CreateThread(function()
            local ok = lib.progressBar({ duration=Config.StanceKit.removeMs, label='Removing Stance Kit...', useWhileDead=false, canCancel=true, disable={move=true,car=true,combat=true}, anim={dict='mini@repair',clip='fixing_a_ped',flag=49} })
            if not ok then return end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            lib.callback('fcrp_tuner:server:removeMod', false, function(result, reason)
                if not result then Notify(reason, 'error', 4000) return end
                TriggerEvent('fcrp_tuner:client:stanceRemoved', veh)
                Notify(Lang:t('stance_removed'), 'success', 4000)
            end, netId, 'stance')
        end)

    elseif action == 'remove_exhaust' then
        CreateThread(function()
            local ok = lib.progressBar({ duration=Config.ExhaustMod.removeMs, label='Removing Exhaust Mod...', useWhileDead=false, canCancel=true, disable={move=true,car=true,combat=true}, anim={dict='mini@repair',clip='fixing_a_ped',flag=49} })
            if not ok then return end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            lib.callback('fcrp_tuner:server:removeMod', false, function(result, reason)
                if not result then Notify(reason, 'error', 4000) return end
                TriggerEvent('fcrp_tuner:client:exhaustRemoved', veh)
                Notify('Exhaust mod removed.', 'success', 4000)
            end, netId, 'exhaust')
        end)

    elseif action == 'remove_fake_plate' then
        CreateThread(function()
            local ok = lib.progressBar({ duration=Config.FakePlate.removeMs, label='Removing fake plate...', useWhileDead=false, canCancel=true, disable={move=true,car=true,combat=true}, anim={dict='mini@repair',clip='fixing_a_ped',flag=49} })
            if not ok then return end
            local netId = NetworkGetNetworkIdFromEntity(veh)
            lib.callback('fcrp_tuner:server:removeMod', false, function(result, reason)
                if not result then Notify(reason, 'error', 4000) return end
                Notify('Fake plate removed.', 'success', 4000)
                -- Plate visual restoration is broadcast by server via restoreRealPlate event
            end, netId, 'fake_plate')
        end)
    end
end)

-- ─────────────────────────────────────────────
--  FAKE PLATE EVENTS  (broadcast from server)
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:client:applyFakePlate', function(netId, plateText)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and DoesEntityExist(veh) then
        SetVehicleNumberPlateText(veh, plateText)
    end
    local myVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if myVeh == veh then
        Notify('🪪 Fake plate applied: ' .. plateText, 'success', 4000)
    end
end)

RegisterNetEvent('fcrp_tuner:client:restoreRealPlate', function(netId, realPlate)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and DoesEntityExist(veh) then
        SetVehicleNumberPlateText(veh, realPlate)
    end
end)

-- ─────────────────────────────────────────────
--  REAPPLY MODS  — on vehicle entry / player load
-- ─────────────────────────────────────────────

local function ReapplyMods(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    lib.callback('fcrp_tuner:server:getVehicleState', false, function(state)
        if not state then return end

        if state.engine_chip then
            SetVehicleModKit(veh, 0)
            SetVehicleMod(veh, 11, 3, false)
            Wait(500)
            local cur = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel')
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', cur * (1.0 + Config.EngineChip.speedBoostPercent / 100.0))
        end

        if state.drift_chip then ApplyDriftChip(veh) end

        if state.nos then
            TriggerEvent('fcrp_tuner:client:nosInstalled', veh, true, state.nos_cooldown_until or 0, state.nos_pressure or 1.0)
        end

        if state.neon_mode then
            if state.neon_mode == 'rainbow' then
                TriggerEvent('fcrp_tuner:client:startRainbow', veh)
            elseif state.neon_mode == 'strobe' then
                TriggerEvent('fcrp_tuner:client:startStrobe', veh)
            else
                TriggerEvent('fcrp_tuner:client:applyStaticNeon', veh, state.neon_r, state.neon_g, state.neon_b)
            end
        end

        if state.has_stance and state.stance then
            -- BUG FIX: arg order matches applyStance handler (camberF, height, camberR)
            -- DB: stance_camber=camberF, stance_height=height, stance_wheeldist=camberR
            TriggerEvent('fcrp_tuner:client:applyStance', veh, state.stance.camber, state.stance.height, state.stance.wheeldist)
        end

        if state.has_exhaust then
            TriggerEvent('fcrp_tuner:client:exhaustInstalled', veh, true)
        end

        if state.fake_plate then
            SetVehicleNumberPlateText(veh, state.fake_plate)
        end
    end, netId)
end

AddEventHandler('qbx_core:playerLoaded', function()
    Wait(5000)
    local veh = GetDrivenVehicle()
    if veh then ReapplyMods(veh) end
end)

-- Vehicle entry — waits for network control before reapplying
CreateThread(function()
    local lastVeh = 0
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and veh ~= lastVeh then
            local timeout = 0
            while not NetworkHasControlOfEntity(veh) and timeout < 3000 do
                Wait(100); timeout = timeout + 100
            end
            lastVeh = veh
            ReapplyMods(veh)
        elseif veh == 0 then
            lastVeh = 0
        end
    end
end)

-- ─────────────────────────────────────────────
--  SUPPLY RUN
-- ─────────────────────────────────────────────

local supplyRunActive = false
local supplyRunZone   = nil

RegisterNetEvent('fcrp_tuner:client:startSupplyRun', function(coords, reward)
    if supplyRunActive then return end
    supplyRunActive = true

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 477)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.9)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 5)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Supply Pickup')
    EndTextCommandSetBlipName(blip)

    local inZone = false

    supplyRunZone = lib.zones.sphere({
        coords  = vec3(coords.x, coords.y, coords.z),
        radius  = Config.SupplyRun.pickupRadius,
        onEnter = function()
            inZone = true
            Notify('Press ~y~E~w~ to collect the damaged parts.', 'inform', 4000)
            CreateThread(function()
                while inZone and supplyRunActive do
                    if IsControlJustPressed(0, 51) then
                        local ok = lib.progressBar({
                            duration     = Config.SupplyRun.collectMs,
                            label        = 'Collecting damaged parts...',
                            useWhileDead = false,
                            canCancel    = true,
                            disable      = { move = true, car = false, combat = true },
                            anim         = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
                        })
                        if ok then
                            if supplyRunZone then supplyRunZone:remove(); supplyRunZone = nil end
                            RemoveBlip(blip)
                            supplyRunActive = false
                            inZone          = false
                            TriggerServerEvent('fcrp_tuner:server:completeSupplyRun')
                        else
                            Notify('Collection cancelled.', 'error', 2000)
                        end
                        break
                    end
                    Wait(0)
                end
            end)
        end,
        onExit = function()
            inZone = false
        end,
    })
end)

-- ─────────────────────────────────────────────
--  PD COMMANDS — CLIENT SIDE
-- ─────────────────────────────────────────────

RegisterNetEvent('fcrp_tuner:client:checkChip', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        Notify('You must be in a vehicle.', 'error', 3000)
        return
    end
    TriggerServerEvent('fcrp_tuner:server:checkChip', NetworkGetNetworkIdFromEntity(veh))
end)

RegisterNetEvent('fcrp_tuner:client:pdRemoveChipRequest', function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh    = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    if not veh or veh == 0 then Notify('No vehicle nearby.', 'error', 3000) return end
    TriggerServerEvent('fcrp_tuner:server:pdRemoveChip', NetworkGetNetworkIdFromEntity(veh))
end)

RegisterNetEvent('fcrp_tuner:client:requestInspect', function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh    = GetClosestVehicle(coords.x, coords.y, coords.z, 10.0, 0, 71)
    if not veh or veh == 0 then Notify('No vehicle nearby.', 'error', 3000) return end
    TriggerServerEvent('fcrp_tuner:server:inspectVehicle', NetworkGetNetworkIdFromEntity(veh))
end)

RegisterNetEvent('fcrp_tuner:client:requestScanPlate', function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local veh    = GetClosestVehicle(coords.x, coords.y, coords.z, 8.0, 0, 71)
    if not veh or veh == 0 then Notify('No vehicle nearby.', 'error', 3000) return end
    TriggerServerEvent('fcrp_tuner:server:scanPlate', NetworkGetNetworkIdFromEntity(veh))
end)

RegisterNetEvent('fcrp_tuner:client:engineChipRemoved', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or not DoesEntityExist(veh) then return end
    local cur = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel')
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel', math.max(10.0, cur / (1.0 + Config.EngineChip.speedBoostPercent / 100.0)))
end)

RegisterNetEvent('fcrp_tuner:client:openSocietyStash', function()
    exports.ox_inventory:openInventory('stash', 'fcrp_tuner_society')
end)
