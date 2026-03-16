-- ============================================================
--  FLAME CITY F1 — client/main.lua  v2.0
--  Qbox + ox_target | ox_lib
-- ============================================================

local lib = exports['ox_lib']

-- ── Race state ───────────────────────────────────────────────
local myRaceCar      = nil
local isRacing       = false
local currentLap     = 1
local currentCP      = 1
local currentBlip    = nil

-- ── Leaderboard / gap ────────────────────────────────────────
local leaderboardData = {}
local myGapToLeader   = nil

-- ── DRS ──────────────────────────────────────────────────────
local drsOpen      = false
local drsZoneIndex = 0

-- ── Engine damage ─────────────────────────────────────────────
local engineStatus    = 'OK'
local engineWarnShown = ''

-- ── Director cam ──────────────────────────────────────────────
local directorCam    = nil
local directorTarget = nil

-- ── Formation lap ─────────────────────────────────────────────
local formationActive = false
local safetyCar       = nil
local safetyCarBlip   = nil
local safetyCarActive = false

-- ── Pit stop ──────────────────────────────────────────────────
local currentTire    = 'medium'   -- starting compound
local tireLapsOnSet  = 0          -- laps driven on current set
local hasPitted      = false
local inPitZone      = false
local pitZoneAdded   = false

-- ── Liveries ──────────────────────────────────────────────────
local usedLiveries = {}

-- ============================================================
-- HELPERS
-- ============================================================
local function Notify(key, vars, ntype)
    local str = Config.Notify[key] or key
    if vars then
        for k, v in pairs(vars) do
            str = str:gsub('{' .. k .. '}', tostring(v))
        end
    end
    lib.notify({ title = 'Flame City GP', description = str, type = ntype or 'inform' })
end

local function DBG(...)
    if Config.Debug then print('[FRCP_F1][CLIENT]', ...) end
end

-- ============================================================
-- 1. RACE MANAGER NPC  (ox_target)
-- ============================================================
local npcHandle = nil

local function SpawnRaceManagerNPC()
    local cfg = Config.RaceManagerNPC
    if not cfg.enabled then return end

    local model = cfg.model
    if type(model) == 'string' then model = joaat(model) end
    lib.requestModel(model)

    npcHandle = CreatePed(4,
        model,
        cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w,
        false, true)
    SetEntityInvincible(npcHandle, true)
    SetBlockingOfNonTemporaryEvents(npcHandle, true)
    FreezeEntityPosition(npcHandle, true)
    SetModelAsNoLongerNeeded(model)

    -- Give pedestrian a racing-suit-ish look via a clipboard prop
    local propModel = joaat('prop_cs_clipboard')
    lib.requestModel(propModel)
    local prop = CreateObject(propModel, 0, 0, 0, true, true, true)
    AttachEntityToEntity(prop, npcHandle, GetPedBoneIndex(npcHandle, 28422),
        0.11, 0.02, 0.0, 10.0, 0.0, 0.0, true, true, false, true, 1, true)

    exports['ox_target']:addLocalEntity(npcHandle, {
        {
            label  = cfg.label,
            icon   = 'fas fa-flag-checkered',
            action = function()
                TriggerServerEvent('frcp_f1:server:requestMenuOpen')
            end,
        },
        {
            label  = 'My F1 Stats',
            icon   = 'fas fa-chart-line',
            action = function()
                TriggerServerEvent('frcp_f1:server:requestMyStats')
            end,
        },
    })
    DBG('Race Manager NPC spawned.')
end

CreateThread(SpawnRaceManagerNPC)

-- ============================================================
-- 2. ORGANISER PANEL  (ox_lib context menu)
-- ============================================================
local slotLabels      = {}
local currentPlayerMap = {}

local function OpenOrganizerMenu()
    local totalSlots = #Config.GridSpots
    local slotOptions = {}
    for i = 1, totalSlots do
        local idx      = i
        local assigned = slotLabels[idx]
        local desc, iconColor
        if assigned then
            desc      = '✅  ' .. assigned
            iconColor = '#00cc66'
        else
            desc      = 'Tap to assign a driver'
            iconColor = '#888888'
        end
        table.insert(slotOptions, {
            title       = string.format('P%d%s', idx, idx == 1 and ' — Pole' or ''),
            description = desc,
            icon        = 'user',
            iconColor   = iconColor,
            onSelect    = function() AssignSlot(idx, currentPlayerMap) end,
        })
    end

    local options = {}

    -- STEP 1 — GRID
    table.insert(options, { title='STEP 1  ·  GRID', disabled=true, icon='table-cells', iconColor='#e10600' })
    for _, o in ipairs(slotOptions) do table.insert(options, o) end
    table.insert(options, {
        title='Clear All Slots', icon='rotate-left', iconColor='#cc4444',
        onSelect=function()
            slotLabels = {}
            TriggerServerEvent('frcp_f1:server:clearGrid')
            OpenOrganizerMenu()
        end,
    })
    table.insert(options, {
        title='Prepare Grid',
        description='Spawn cars and freeze drivers on their grid spots',
        icon='flag', iconColor='#ffcc00',
        onSelect=function()
            TriggerServerEvent('frcp_f1:server:setupGrid')
            OpenOrganizerMenu()
        end,
    })

    -- STEP 2 — FORMATION LAP
    table.insert(options, { title='STEP 2  ·  FORMATION LAP', disabled=true, icon='shield-halved', iconColor='#e10600' })
    table.insert(options, {
        title='Deploy Safety Car',
        description='SC leads drivers from grid to start',
        icon='car', iconColor='#ffaa00',
        onSelect=function()
            TriggerServerEvent('frcp_f1:server:deploySafetyCar')
            OpenOrganizerMenu()
        end,
    })

    -- STEP 3 — RACE START
    table.insert(options, { title='STEP 3  ·  RACE START', disabled=true, icon='traffic-light', iconColor='#e10600' })
    table.insert(options, {
        title='START RACE',
        description='Despawn SC · Freeze grid · Lights out',
        icon='flag-checkered', iconColor='#00cc44',
        onSelect=function()
            TriggerServerEvent('frcp_f1:server:startGlobalRace')
            OpenOrganizerMenu()
        end,
    })

    -- TOOLS
    table.insert(options, { title='TOOLS', disabled=true, icon='wrench', iconColor='#888888' })
    table.insert(options, {
        title='Race Director Camera',
        description='Cinematic overhead view of any driver',
        icon='video', iconColor='#88aaff',
        onSelect=function() OpenDirectorCamMenu() end,
    })
    table.insert(options, {
        title='Force End / Reset',
        description='Emergency stop — teleports everyone',
        icon='circle-xmark', iconColor='#ff4444',
        onSelect=function()
            TriggerServerEvent('frcp_f1:server:forceEnd')
            OpenOrganizerMenu()
        end,
    })

    lib.registerContext({ id='f1_organiser', title='  FLAME CITY GP  ·  Race Control', options=options })
    lib.showContext('f1_organiser')
end

-- Server tells the client whether to open organiser or spectator view
RegisterNetEvent('frcp_f1:client:openOrganizerMenu', function(playerList)
    currentPlayerMap = {}
    for _, p in ipairs(playerList) do currentPlayerMap[p.id] = p.name end
    OpenOrganizerMenu()
end)

RegisterNetEvent('frcp_f1:client:openStatsMenu', function(stats)
    lib.registerContext({
        id    = 'f1_stats_view',
        title = '🏎️ My F1 Stats',
        options = {
            { title='XP',     description=tostring(stats.xp),     icon='star',           disabled=true },
            { title='Rating', description=tostring(stats.rating),  icon='ranking-star',   disabled=true },
            { title='Wins',   description=tostring(stats.wins),    icon='trophy',         disabled=true },
            { title='Races',  description=tostring(stats.races),   icon='flag-checkered', disabled=true },
        }
    })
    lib.showContext('f1_stats_view')
end)

RegisterNetEvent('frcp_f1:client:slotAssigned', function(slot, playerId, name)
    slotLabels[slot] = string.format('ID %d — %s', playerId, name)
    OpenOrganizerMenu()
end)

function AssignSlot(slot, playerMap)
    local result = lib.inputDialog('Assign P' .. slot, {
        { type='number', label='Player Server ID', placeholder='e.g. 5', required=true, min=1 }
    })
    if not result or not result[1] then OpenOrganizerMenu(); return end
    local targetId = tonumber(result[1])
    if not targetId then
        lib.notify({ title='Invalid ID', type='error' }); OpenOrganizerMenu(); return
    end
    TriggerServerEvent('frcp_f1:server:assignSlot', slot, targetId)
end

-- ============================================================
-- 3. RACE DIRECTOR CAMERA
-- ============================================================
function OpenDirectorCamMenu()
    local result = lib.inputDialog('Race Director Camera', {
        { type='number', label='Target Player Server ID', placeholder='e.g. 3', required=true, min=1 }
    })
    lib.showContext('f1_organiser')
    if not result or not result[1] then return end
    TriggerServerEvent('frcp_f1:server:getVehicleForCam', tonumber(result[1]))
end

RegisterNetEvent('frcp_f1:client:attachDirectorCam', function(netId)
    StopDirectorCam()
    if not NetworkDoesNetworkIdExist(netId) then
        lib.notify({ title='Cam Error', description='Vehicle not found', type='error' }); return
    end
    local veh = NetToVeh(netId)
    if not DoesEntityExist(veh) then
        lib.notify({ title='Cam Error', description='Vehicle entity missing', type='error' }); return
    end
    directorTarget = veh
    directorCam    = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(directorCam, true)
    RenderScriptCams(true, true, 500, true, false)
    lib.notify({ title='📷 Director Cam ON', description='Press ~INPUT_CELLPHONE_CANCEL~ to exit', type='inform' })
    CreateThread(function()
        while directorCam and IsCamActive(directorCam) do
            if not DoesEntityExist(directorTarget) then break end
            if IsControlJustPressed(0, 194) or IsControlJustPressed(0, 177) then break end
            local pos     = GetEntityCoords(directorTarget)
            local heading = GetEntityHeading(directorTarget)
            local rad     = math.rad(heading)
            SetCamCoord(directorCam, pos.x + math.sin(rad)*8.0, pos.y + math.cos(rad)*8.0, pos.z + 4.0)
            PointCamAtEntity(directorCam, directorTarget, 0.0, 0.0, 0.5, true)
            SetCamFov(directorCam, 55.0)
            Wait(0)
        end
        StopDirectorCam()
    end)
end)

function StopDirectorCam()
    if directorCam then
        RenderScriptCams(false, true, 500, true, false)
        DestroyCam(directorCam, false)
        directorCam = nil; directorTarget = nil
    end
end

-- ============================================================
-- 4. BASE PHYSICS
-- ============================================================
local BASE_DRIVE_FORCE = Config.F1BaseHandling.fInitialDriveForce
local BASE_TOP_SPEED   = Config.F1BaseTopSpeed

local function ApplyF1Handling(veh)
    SetVehicleModKit(veh, 0)
    for key, val in pairs(Config.F1BaseHandling) do
        SetVehicleHandlingFloat(veh, 'CHandlingData', key, val)
    end
    ModifyVehicleTopSpeed(veh, BASE_TOP_SPEED)
end

-- ============================================================
-- 5. TIRE COMPOUNDS
-- ============================================================
local function ApplyTireCompound(veh, compound)
    if not DoesEntityExist(veh) then return end
    local c = Config.TireCompounds[compound]
    if not c then return end

    local isDegraded = (currentLap - tireLapsOnSet) > c.laps
    local df = BASE_DRIVE_FORCE + c.driveForce + (isDegraded and c.degradedForce or 0.0)
    local tMax = c.tractionMax  + (isDegraded and c.degradedTraction or 0.0)
    local tMin = c.tractionMin  + (isDegraded and c.degradedTraction * 0.5 or 0.0)

    -- Combine with DRS and engine damage multipliers
    local dmgMult = GetEngineDamageMult()
    local drsMult = drsOpen and Config.DRS.driveForceBoost or 0.0

    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce', (df + drsMult) * dmgMult)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax',  tMax)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin',  tMin)
    ModifyVehicleTopSpeed(veh, BASE_TOP_SPEED + c.topSpeedBonus + (drsOpen and Config.DRS.topSpeedBoost or 0.0))
end

-- Check and warn when compound starts degrading
local lastTireWarn = ''
local function CheckTireWear()
    if not myRaceCar then return end
    local c = Config.TireCompounds[currentTire]
    if not c then return end
    local lapsOn = currentLap - tireLapsOnSet
    if lapsOn > c.laps and lastTireWarn ~= currentTire .. tostring(currentLap) then
        lastTireWarn = currentTire .. tostring(currentLap)
        Notify('tireWorn', { tire = c.label }, 'warning')
        ApplyTireCompound(myRaceCar, currentTire)
    end
end

-- ============================================================
-- 6. PIT STOP
-- ============================================================
local function OpenTireMenu()
    local options = {}
    for id, comp in pairs(Config.TireCompounds) do
        local cid = id
        table.insert(options, {
            title       = comp.label,
            description = ('Lasts ~%d laps  ·  Force +%.2f  ·  Speed +%.0f'):format(
                comp.laps, comp.driveForce, comp.topSpeedBonus),
            icon        = 'circle',
            iconColor   = ('rgb(%d,%d,%d)'):format(comp.color[1], comp.color[2], comp.color[3]),
            onSelect    = function()
                TriggerServerEvent('frcp_f1:server:pitStop', cid)
            end,
        })
    end
    lib.registerContext({ id='f1_tire_menu', title='🛞 Choose Tire Compound', options=options })
    lib.showContext('f1_tire_menu')
end

RegisterNetEvent('frcp_f1:client:doPitStop', function(compound)
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end

    -- Freeze car in pit lane
    FreezeEntityPosition(myRaceCar, true)
    SetVehicleEngineOn(myRaceCar, false, true, false)

    -- Progress bar as stop duration
    lib.progressBar({
        duration = Config.PitStop.stopDuration * 1000,
        label    = 'Changing tires...',
        useWhileDead = false,
        canCancel    = false,
        disable = { move=true, car=true, mouse=false, combat=true },
    })

    -- Apply new compound
    currentTire   = compound
    tireLapsOnSet = currentLap
    hasPitted     = true
    ApplyTireCompound(myRaceCar, compound)

    -- Unfreeze
    FreezeEntityPosition(myRaceCar, false)
    SetVehicleEngineOn(myRaceCar, true, false, false)

    local c = Config.TireCompounds[compound]
    Notify('pitDone', { tire = c and c.label or compound }, 'success')
end)

-- Register pit lane zone (called after car spawns)
local function RegisterPitZone()
    if pitZoneAdded or not Config.PitStop.enabled then return end
    pitZoneAdded = true
    local z = Config.PitStop.zone

    exports['ox_target']:addBoxZone({
        coords   = z.coords,
        size     = z.size,
        rotation = z.heading,
        debug    = Config.Debug,
        options  = {
            {
                label  = 'Pit Stop',
                icon   = 'fas fa-wrench',
                onSelect = function()
                    if not isRacing then
                        lib.notify({ title='Not in a race', type='error' }); return
                    end
                    OpenTireMenu()
                end,
            },
        },
    })
end

-- ============================================================
-- 7. DRS SYSTEM
-- ============================================================
local function UpdateDRS(coords)
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end
    if not Config.DRSZones or #Config.DRSZones == 0 then return end

    local wasOpen = drsOpen
    local newOpen = false
    local newZone = 0

    for i, zone in ipairs(Config.DRSZones) do
        local ex = zone.exit.x - zone.entry.x
        local ey = zone.exit.y - zone.entry.y
        local ez = zone.exit.z - zone.entry.z
        local lenSq = ex*ex + ey*ey + ez*ez
        local t = 0.0
        if lenSq > 0.0 then
            local dx = coords.x - zone.entry.x
            local dy = coords.y - zone.entry.y
            local dz = coords.z - zone.entry.z
            t = (dx*ex + dy*ey + dz*ez) / lenSq
        end
        if t >= 0.0 and t <= 1.0 then
            local cx = zone.entry.x + t*ex
            local cy = zone.entry.y + t*ey
            local cz = zone.entry.z + t*ez
            local lat = math.sqrt((coords.x-cx)^2+(coords.y-cy)^2+(coords.z-cz)^2)
            if lat < zone.radius then newOpen=true; newZone=i; break end
        end
    end

    if newOpen ~= wasOpen or newZone ~= drsZoneIndex then
        drsOpen      = newOpen
        drsZoneIndex = newZone
        if drsOpen then
            lib.showTextUI(Config.Notify.drsOpen, {
                position='bottom-center',
                style={ backgroundColor='#007a00', color='white',
                        fontSize='18px', fontWeight='bold', padding='6px 20px', letterSpacing='3px' }
            })
        else
            lib.hideTextUI()
        end
        ApplyTireCompound(myRaceCar, currentTire)
    end
end

-- ============================================================
-- 8. ENGINE DAMAGE
-- ============================================================
function GetEngineDamageMult()
    if engineStatus == 'CRITICAL' then return 0.35
    elseif engineStatus == 'DAMAGED' then return 0.60
    elseif engineStatus == 'WARNING' then return 0.85
    else return 1.0 end
end

local function UpdateEngineDamage()
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end
    local health    = GetVehicleEngineHealth(myRaceCar)
    local newStatus
    if health <= Config.EngineHealth.critical then newStatus = 'CRITICAL'
    elseif health <= Config.EngineHealth.damaged then newStatus = 'DAMAGED'
    elseif health <= Config.EngineHealth.warning then newStatus = 'WARNING'
    else newStatus = 'OK' end

    if newStatus ~= engineStatus then
        engineStatus = newStatus
        if newStatus == 'WARNING'  then Notify('engineWarning',  nil, 'warning')
        elseif newStatus == 'DAMAGED'  then Notify('engineDamaged',  nil, 'error')
        elseif newStatus == 'CRITICAL' then Notify('engineCritical', nil, 'error') end
        ApplyTireCompound(myRaceCar, currentTire)
    end
end

-- ============================================================
-- 9. RACING LINE
-- ============================================================
local function DrawRacingLine(pCoords, target)
    if not Config.RaceLine.enabled then return end
    if #(pCoords - target) > Config.RaceLine.maxDist then return end
    local segs    = Config.RaceLine.segments
    local heading = math.deg(math.atan(target.x-pCoords.x, target.y-pCoords.y)) + 180.0
    for i = 1, segs do
        local frac  = i / segs
        local x     = pCoords.x + (target.x-pCoords.x)*frac
        local y     = pCoords.y + (target.y-pCoords.y)*frac
        local found, gz = GetGroundZFor_3dCoord(x, y, pCoords.z+10.0, false)
        local z     = found and (gz-0.1) or (pCoords.z-0.3)
        local alpha = math.floor(220*(1.0-frac*0.6))
        DrawMarker(24, x, y, z, 0,0,0, 0,0, heading,
            0.9, 0.9, 0.9, 0, 210, 255, alpha, false, false, 2, nil, nil, false)
    end
end

-- ============================================================
-- 10. HUD  (lap / CP / gap / engine / tire)
-- ============================================================
local function DrawRaceHUD(lap, maxLaps, cp, totalCPs)
    -- Lap
    SetTextFont(4); SetTextScale(0.0,0.50); SetTextColour(255,255,255,255)
    SetTextOutline(); SetTextEntry('STRING')
    AddTextComponentString(string.format('LAP  %d / %d', lap, maxLaps))
    DrawText(0.82, 0.83)

    -- Checkpoint
    SetTextFont(0); SetTextScale(0.0,0.30); SetTextColour(160,210,255,200)
    SetTextOutline(); SetTextEntry('STRING')
    AddTextComponentString(string.format('CP  %d / %d', cp, totalCPs))
    DrawText(0.82, 0.865)

    -- Tire compound
    local tc = Config.TireCompounds[currentTire]
    if tc then
        local r, g, b = table.unpack(tc.color)
        local lapsOn  = currentLap - tireLapsOnSet
        local worn    = lapsOn > tc.laps
        SetTextFont(0); SetTextScale(0.0,0.28); SetTextColour(r, g, b, worn and 150 or 220)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString(tc.label .. (worn and '  [WORN]' or ''))
        DrawText(0.82, 0.897)
    end

    -- Gap to leader
    if myGapToLeader then
        local r, g, b = 255, 255, 255
        if myGapToLeader == 'LEADER' then r,g,b=255,215,0
        elseif myGapToLeader:sub(1,1) == '+' then r,g,b=255,100,100 end
        SetTextFont(4); SetTextScale(0.0,0.34); SetTextColour(r,g,b,230)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString(myGapToLeader)
        DrawText(0.82, 0.927)
    end

    -- Engine warning
    if engineStatus ~= 'OK' then
        local colours = { WARNING={255,200,0,220}, DAMAGED={255,100,0,220}, CRITICAL={255,30,30,255} }
        local c = colours[engineStatus] or {255,255,255,200}
        SetTextFont(4); SetTextScale(0.0,0.28); SetTextColour(c[1],c[2],c[3],c[4])
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString('ENGINE ' .. engineStatus)
        DrawText(0.82, 0.955)
    end
end

-- ============================================================
-- 11. LEADERBOARD HUD
-- ============================================================
RegisterNetEvent('frcp_f1:client:updateLeaderboard', function(data, gap)
    leaderboardData = data
    myGapToLeader   = gap
end)

local function DrawLeaderboard()
    if not leaderboardData or #leaderboardData == 0 then return end
    local startX = 0.78
    local startY = 0.04
    local lineH  = 0.028

    SetTextFont(4); SetTextScale(0.0,0.28); SetTextColour(255,200,0,255)
    SetTextOutline(); SetTextEntry('STRING')
    AddTextComponentString('FLAME CITY GP')
    DrawText(startX, startY)

    for i, entry in ipairs(leaderboardData) do
        local y     = startY + (i * lineH) + 0.01
        local label
        if entry.finished and entry.pos then
            label = string.format('P%d  %s  ✓%s', entry.pos, entry.name, entry.time or '')
        elseif entry.dq then
            label = string.format('DQ  %s', entry.name)
        else
            label = string.format('P%d  %s  L%d·CP%d', i, entry.name, entry.lap or 1, entry.cp or 1)
        end
        local r, g, b = 220, 220, 220
        if entry.dq then r,g,b=255,60,60
        elseif i==1 and entry.finished then r,g,b=255,215,0
        elseif i==2 and entry.finished then r,g,b=192,192,192
        elseif i==3 and entry.finished then r,g,b=205,127,50 end
        SetTextFont(0); SetTextScale(0.0,0.25); SetTextColour(r,g,b,220)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString(label)
        DrawText(startX, y)
    end
end

CreateThread(function()
    while true do DrawLeaderboard(); Wait(0) end
end)

-- ============================================================
-- 12. GPS WAYPOINT
-- ============================================================
local function UpdateRaceWaypoint(coords)
    if currentBlip and DoesBlipExist(currentBlip) then RemoveBlip(currentBlip) end
    currentBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(currentBlip, 38); SetBlipColour(currentBlip, 5)
    SetBlipScale(currentBlip, 0.85); SetBlipAsShortRange(currentBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Next Checkpoint')
    EndTextCommandSetBlipName(currentBlip)
    SetNewWaypoint(coords.x, coords.y)
end

local function ClearWaypoint()
    if currentBlip and DoesBlipExist(currentBlip) then RemoveBlip(currentBlip) end
    currentBlip = nil; SetWaypointOff()
end

-- ============================================================
-- 13. F1 STARTING LIGHTS
-- ============================================================
local countdownDone = false
local function F1Countdown()
    countdownDone = false
    CreateThread(function()
        local lights = {
            {m='● ○ ○ ○ ○', c='#7a0000'},{m='● ● ○ ○ ○', c='#a00000'},
            {m='● ● ● ○ ○', c='#c80000'},{m='● ● ● ● ○', c='#e00000'},
            {m='● ● ● ● ●', c='#ff0000'},
        }
        for _, light in ipairs(lights) do
            lib.showTextUI(light.m, {
                position='top-center',
                style={backgroundColor=light.c, color='white',
                       fontSize='48px', fontWeight='bold', padding='10px 28px', letterSpacing='6px'}
            })
            PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', 1)
            Wait(900)
        end
        lib.hideTextUI()
        Wait(math.random(400, 900))
        lib.showTextUI('GO GO GO!', {
            position='top-center',
            style={backgroundColor='#00cc44', color='white', fontSize='54px',
                   fontWeight='bold', padding='10px 28px'}
        })
        PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', 1)
        Wait(1200)
        lib.hideTextUI()
        countdownDone = true
    end)
    while not countdownDone do Wait(100) end
end

-- ============================================================
-- 14. FORMATION LAP
-- ============================================================
RegisterNetEvent('frcp_f1:client:spawnSafetyCar', function()
    local cfg      = Config.FormationLap
    local maxSpeed = cfg.maxSpeed / 3.6
    local startSpot = cfg.safetyCarSpot
    local model    = cfg.safetyCarModel

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    safetyCar = CreateVehicle(model, startSpot.x, startSpot.y, startSpot.z, startSpot.w, true, false)
    SetEntityAsMissionEntity(safetyCar, true, true)
    SetVehicleColours(safetyCar, 12, 12)
    SetVehicleNumberPlateText(safetyCar, 'SAFETY')
    SetVehicleEngineOn(safetyCar, true, true, false)
    SetVehicleMaxSpeed(safetyCar, maxSpeed)

    safetyCarBlip = AddBlipForEntity(safetyCar)
    SetBlipSprite(safetyCarBlip, 225); SetBlipColour(safetyCarBlip, 17)
    SetBlipScale(safetyCarBlip, 1.1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Safety Car')
    EndTextCommandSetBlipName(safetyCarBlip)

    local driverModel = `s_m_m_security_01`
    RequestModel(driverModel)
    while not HasModelLoaded(driverModel) do Wait(0) end
    local driver = CreatePedInsideVehicle(safetyCar, 26, driverModel, -1, true, false)
    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedKeepTask(driver, true)

    safetyCarActive = true

    local route = {}
    for _, cp in ipairs(Config.Checkpoints) do
        table.insert(route, vector3(cp.x, cp.y, cp.z))
    end
    table.insert(route, vector3(startSpot.x, startSpot.y, startSpot.z))

    CreateThread(function()
        for _, dest in ipairs(route) do
            if not safetyCarActive then break end
            TaskVehicleDriveToCoordLongrange(driver, safetyCar, dest.x, dest.y, dest.z, maxSpeed, 786603, 5.0)
            while safetyCarActive do
                if not DoesEntityExist(safetyCar) then safetyCarActive=false; break end
                if #(GetEntityCoords(safetyCar) - dest) < 18.0 then break end
                Wait(300)
            end
        end
        if safetyCarActive then TriggerServerEvent('frcp_f1:server:formationLapDone') end
    end)
    lib.notify({ title='🟡 Safety Car deployed', description='Follow the SC around the circuit', type='inform' })
end)

RegisterNetEvent('frcp_f1:client:despawnSafetyCar', function()
    safetyCarActive = false
    if safetyCarBlip and DoesBlipExist(safetyCarBlip) then RemoveBlip(safetyCarBlip) end
    safetyCarBlip = nil
    if safetyCar and DoesEntityExist(safetyCar) then
        local driver = GetPedInVehicleSeat(safetyCar, -1)
        if driver and driver ~= 0 then DeleteEntity(driver) end
        DeleteEntity(safetyCar)
    end
    safetyCar = nil
end)

RegisterNetEvent('frcp_f1:client:beginFormationLap', function()
    formationActive = true
    if myRaceCar and DoesEntityExist(myRaceCar) then
        FreezeEntityPosition(myRaceCar, false)
        SetVehicleEngineOn(myRaceCar, true, false, false)
        SetVehicleDoorsLocked(myRaceCar, 1)
        SetVehicleMaxSpeed(myRaceCar, Config.FormationLap.maxSpeed / 3.6)
    end
    if myRaceCar then
        lib.showTextUI('🟡  FORMATION LAP — Follow the safety car', {
            position='top-center',
            style={ backgroundColor='#aa7700', color='white', fontSize='18px', fontWeight='bold', padding='8px 22px' }
        })
    end
end)

RegisterNetEvent('frcp_f1:client:returnToGrid', function(spot)
    formationActive = false
    lib.hideTextUI()
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end
    SetVehicleMaxSpeed(myRaceCar, 0.0)
    SetEntityCoords(myRaceCar, spot.x, spot.y, spot.z, false, false, false, false)
    SetEntityHeading(myRaceCar, spot.w)
    FreezeEntityPosition(myRaceCar, true)
    SetVehicleEngineOn(myRaceCar, false, true, false)
    CreateThread(function()
        while myRaceCar and DoesEntityExist(myRaceCar) and not isRacing do
            SetVehicleCurrentRpm(myRaceCar, 0.1); Wait(0)
        end
    end)
    lib.notify({ title='🏁 Back on the grid', description='Lights out in a moment...', type='inform' })
end)

RegisterNetEvent('frcp_f1:client:endFormationLap', function()
    formationActive = false; lib.hideTextUI()
    if myRaceCar and DoesEntityExist(myRaceCar) then
        SetVehicleMaxSpeed(myRaceCar, 0.0)
        FreezeEntityPosition(myRaceCar, true)
        SetVehicleEngineOn(myRaceCar, false, true, false)
    end
end)

-- ============================================================
-- 15. SPAWN & CLEANUP
-- ============================================================
local function AssignLivery(veh)
    local pool = {}
    for i = 2, Config.LiveryCount do
        if not usedLiveries[i] then table.insert(pool, i) end
    end
    local chosen = #pool > 0 and pool[math.random(1, #pool)] or math.random(2, Config.LiveryCount)
    usedLiveries[chosen] = true
    SetVehicleLivery(veh, chosen)
end

local function ApplyMaxMods(veh)
    SetVehicleModKit(veh, 0)
    for _, slot in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23}) do
        local count = GetNumVehicleMods(veh, slot)
        if count > 0 then SetVehicleMod(veh, slot, count-1, false) end
    end
    ToggleVehicleMod(veh, 18, true)
    ToggleVehicleMod(veh, 22, true)
end

RegisterNetEvent('frcp_f1:client:spawnYourCar', function(spot)
    local ped = cache and cache.ped or PlayerPedId()
    if not ped or ped == 0 then
        lib.notify({ title='Spawn Error', description='Ped not ready', type='error' }); return
    end

    local model = Config.F1CarModel
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    myRaceCar = CreateVehicle(model, spot.x, spot.y, spot.z, spot.w, true, false)
    ApplyF1Handling(myRaceCar)
    ApplyMaxMods(myRaceCar)
    AssignLivery(myRaceCar)

    local plate = GetVehicleNumberPlateText(myRaceCar)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    SetPedIntoVehicle(ped, myRaceCar, -1)
    FreezeEntityPosition(myRaceCar, true)
    SetVehicleDoorsLocked(myRaceCar, 4)
    SetVehicleEngineOn(myRaceCar, false, true, false)

    -- Reset per-session state
    drsOpen      = false
    engineStatus = 'OK'
    currentTire  = 'medium'
    tireLapsOnSet = 0
    hasPitted    = false
    lastTireWarn = ''

    CreateThread(function()
        while myRaceCar and DoesEntityExist(myRaceCar) and not isRacing do
            SetVehicleCurrentRpm(myRaceCar, 0.1); Wait(0)
        end
    end)

    -- Register pit zone after car spawns
    RegisterPitZone()
end)

RegisterNetEvent('frcp_f1:client:cleanupCars', function()
    ClearWaypoint(); StopDirectorCam(); lib.hideTextUI()
    isRacing=false; formationActive=false; currentLap=1; currentCP=1
    leaderboardData={}; myGapToLeader=nil; drsOpen=false
    engineStatus='OK'; usedLiveries={}
    currentTire='medium'; tireLapsOnSet=0; hasPitted=false; lastTireWarn=''
    if myRaceCar and DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
    myRaceCar = nil

    -- Hide results overlay
    SendNUIMessage({ action='hideResults' })
    SetNuiFocus(false, false)
end)

-- ============================================================
-- 16. POST-RACE TELEPORT
-- ============================================================
RegisterNetEvent('frcp_f1:client:teleportPostRace', function()
    ClearWaypoint(); isRacing=false; lib.hideTextUI()
    if myRaceCar and DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
    myRaceCar = nil
    local ped = cache and cache.ped or PlayerPedId()
    if ped and ped ~= 0 then
        SetEntityCoords(ped,
            Config.PostRaceLocation.x, Config.PostRaceLocation.y, Config.PostRaceLocation.z,
            false,false,false,false)
    end
    SendNUIMessage({ action='hideResults' })
    SetNuiFocus(false, false)
end)

-- ============================================================
-- 17. RESULTS NUI OVERLAY
-- ============================================================
RegisterNetEvent('frcp_f1:client:showResults', function(data)
    SendNUIMessage({ action='showResults', results=data.results, subtitle=data.subtitle, delay=data.delay })
    SetNuiFocus(false, false)
end)

-- ============================================================
-- 18. MAIN RACE LOOP
-- ============================================================
RegisterNetEvent('frcp_f1:client:startRace', function()
    if not myRaceCar then return end
    if isRacing then return end

    currentLap = 1; currentCP = 1; formationActive = false

    if not Config.Checkpoints or #Config.Checkpoints == 0 then
        lib.notify({title='Race Error', description='No checkpoints in Config!', type='error'}); return
    end

    F1Countdown()

    FreezeEntityPosition(myRaceCar, false)
    SetVehicleEngineOn(myRaceCar, true, false, false)
    SetVehicleDoorsLocked(myRaceCar, 1)
    isRacing = true

    -- Apply starting compound
    ApplyTireCompound(myRaceCar, currentTire)

    TriggerServerEvent('frcp_f1:server:raceClockStart')
    UpdateRaceWaypoint(Config.Checkpoints[currentCP])

    CreateThread(function()
        while isRacing do
            local ped    = cache and cache.ped or PlayerPedId()
            local coords = GetEntityCoords(ped)

            -- DQ: left vehicle
            if not IsPedInVehicle(ped, myRaceCar, false) then
                isRacing = false; ClearWaypoint(); lib.hideTextUI()
                if DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
                myRaceCar = nil
                TriggerServerEvent('frcp_f1:server:dqPlayer', 'Left vehicle')
                lib.notify({title='DISQUALIFIED', description='You left the vehicle!', type='error'})
                break
            end

            local target = Config.Checkpoints[currentCP]
            if not target then isRacing=false; break end

            -- Per-frame systems
            UpdateDRS(coords)
            UpdateEngineDamage()
            CheckTireWear()
            DrawRaceHUD(currentLap, Config.MaxLaps, currentCP, #Config.Checkpoints)
            DrawRacingLine(coords, target)

            -- Pit lane speed limiter
            if Config.PitStop.enabled and Config.PitStop.speedLimit > 0 then
                local pitZ = Config.PitStop.zone
                if #(coords - pitZ.coords) < 20.0 then
                    local speed = GetEntitySpeed(myRaceCar) * 3.6
                    if speed > Config.PitStop.speedLimit then
                        SetEntityMaxSpeed(myRaceCar, Config.PitStop.speedLimit / 3.6)
                    else
                        SetEntityMaxSpeed(myRaceCar, 9999.0)
                    end
                else
                    SetEntityMaxSpeed(myRaceCar, 9999.0)
                end
            end

            -- Checkpoint markers
            if #(coords - target) < 200.0 then
                if currentCP == 1 then
                    DrawMarker(4, target.x,target.y,target.z, 0,0,0, 0,0,0, 5,5,5, 255,255,255,200, false,false,2,nil,nil,false)
                    DrawMarker(1, target.x,target.y,target.z+0.05, 0,0,0, 0,0,0, 7,7,0.4, 255,40,40,100, false,false,2,nil,nil,false)
                else
                    DrawMarker(1, target.x,target.y,target.z+0.05, 0,0,0, 0,0,0, 5,5,1.2, 0,180,255,160, false,false,2,nil,nil,false)
                end
            end

            -- Checkpoint hit
            if #(coords - target) < 15.0 then
                PlaySoundFrontend(-1, 'CHECKPOINT_BEAT', 'HUD_MINI_GAME_SOUNDSET', 1)
                if currentCP < #Config.Checkpoints then
                    currentCP = currentCP + 1
                else
                    currentCP  = 1
                    currentLap = currentLap + 1
                    if currentLap > Config.MaxLaps then
                        -- Mandatory pit check
                        if Config.PitStop.enabled and Config.PitStop.mandatory and not hasPitted then
                            TriggerServerEvent('frcp_f1:server:dqPlayer', 'No mandatory pit stop')
                            Notify('pitMandatoryDQ', nil, 'error')
                            isRacing = false; ClearWaypoint(); lib.hideTextUI(); break
                        end
                        isRacing = false; ClearWaypoint(); lib.hideTextUI()
                        TriggerServerEvent('frcp_f1:server:finishRace')
                        break
                    else
                        lib.notify({
                            title=string.format('LAP %d COMPLETE', currentLap-1),
                            description=string.format('%d lap(s) remaining', Config.MaxLaps-(currentLap-1)),
                            type='inform'
                        })
                    end
                end
                UpdateRaceWaypoint(Config.Checkpoints[currentCP])
                TriggerServerEvent('frcp_f1:server:updateProgress', currentLap, currentCP)
            end

            Wait(0)
        end

        if drsOpen then lib.hideTextUI(); drsOpen=false end
    end)
end)

-- ============================================================
-- 19. AUTO-RACE CLOCK WATCHER
-- ============================================================
CreateThread(function()
    while true do
        Wait(30000)
        if Config.AutoRace and #Config.AutoRace > 0 then
            local h, m = GetClockHours(), GetClockMinutes()
            local now  = string.format('%02d:%02d', h, m)
            for _, entry in ipairs(Config.AutoRace) do
                if entry.time == now then
                    TriggerServerEvent('frcp_f1:server:autoRaceTrigger')
                end
            end
        end
    end
end)

DBG('Client v2.0 loaded.')
