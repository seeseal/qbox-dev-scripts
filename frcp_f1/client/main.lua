-- ============================================================
--  FLAME CITY F1 — client/main.lua  v3.0
--  Qbox + ox_target | ox_lib
-- ============================================================

local lib = exports['ox_lib']

-- ── Race state ───────────────────────────────────────────────
local myRaceCar      = nil
local isRacing       = false
local currentLap     = 1
local currentCP      = 1
local currentBlip    = nil

-- ── Timing ───────────────────────────────────────────────────
local lapStartMs        = nil   -- GetGameTimer() at lap start
local sectorStartMs     = nil
local sectorTimes       = {}    -- { {label, ms, delta} }
local bestLapMs         = nil   -- personal best this session
local bestSectorMs      = { [1]=nil, [2]=nil, [3]=nil }
local currentSectorIdx  = 1
local raceStartMs       = nil
local fastestLapMs      = nil   -- personal fastest this race
local lapTimesThisRace  = {}
local lapIsValid        = true
local offCourseTimer    = 0

-- ── Stats to report to server ────────────────────────────────
local pitCount   = 0
local drsCount   = 0
local engineOk   = true
local currentTyre= 'medium'

-- ── Leaderboard ──────────────────────────────────────────────
local leaderboardData = {}
local myGapToLeader   = nil

-- ── DRS ──────────────────────────────────────────────────────
local drsOpen      = false
local drsZoneIndex = 0

-- ── Engine ───────────────────────────────────────────────────
local engineStatus = 'OK'

-- ── Pit ──────────────────────────────────────────────────────
local hasPitted      = false
local pitZoneAdded   = false
local inPitSpeedo    = false

-- ── Race line / formation ────────────────────────────────────
local formationActive = false
local safetyCar       = nil
local safetyCarBlip   = nil
local safetyCarActive = false

-- ── Liveries ─────────────────────────────────────────────────
local usedLiveries = {}


-- ── Organiser panel state ────────────────────────────────────
local slotLabels      = {}
local currentPlayerMap= {}
local directorCam     = nil
local directorTarget  = nil
local directorMode    = 1   -- 1=Follow 2=Helicopter 3=TV 4=Onboard
local directorModes   = { 'Follow', 'Helicopter', 'TV Cam', 'Onboard' }

-- ── Spectator state ──────────────────────────────────────────
local isSpectating      = false
local specTargets       = {}   -- { { name, netId, lap, pos } }
local specIndex         = 1
local specCam           = nil

-- ============================================================
-- HELPERS
-- ============================================================
local function Notify(key, vars, ntype)
    local str = Config.Notify[key] or key
    if vars then for k,v in pairs(vars) do str = str:gsub('{'..k..'}', tostring(v)) end end
    lib.notify({ title='Flame City GP', description=str, type=ntype or 'inform' })
end

local function DBG(...)
    if Config.Debug then print('[FCRP_F1][CL]', ...) end
end

local function FmtMs(ms)
    if not ms then return '—' end
    local s = ms / 1000
    return string.format('%d:%06.3f', math.floor(s/60), s % 60)
end

local function GetCurrentMs() return GetGameTimer() end

-- ============================================================
-- RACE MANAGER NPC
-- ============================================================
local npcHandle = nil
local npcProp   = nil

local function SpawnRaceManagerNPC()
    local cfg = Config.RaceManagerNPC
    if not cfg.enabled then return end
    local model = type(cfg.model) == 'string' and joaat(cfg.model) or cfg.model
    lib.requestModel(model)
    npcHandle = CreatePed(4, model, cfg.coords.x, cfg.coords.y, cfg.coords.z-1.0, cfg.coords.w, false, true)
    SetEntityInvincible(npcHandle, true)
    SetBlockingOfNonTemporaryEvents(npcHandle, true)
    FreezeEntityPosition(npcHandle, true)
    SetModelAsNoLongerNeeded(model)
    -- Clipboard prop
    local clipModel = joaat('prop_cs_clipboard')
    lib.requestModel(clipModel)
    npcProp = CreateObject(clipModel, 0,0,0, true, true, true)
    AttachEntityToEntity(npcProp, npcHandle, GetPedBoneIndex(npcHandle, 28422), 0.11, 0.02, 0.0, 10.0, 0.0, 0.0, true, true, false, true, 1, true)
    exports['ox_target']:addLocalEntity(npcHandle, {
        { label=cfg.label,           icon='fas fa-flag-checkered',
          action=function() TriggerServerEvent('fcrp_f1:sv:requestMenuOpen') end },
        { label='My Stats',          icon='fas fa-chart-line',
          action=function() TriggerServerEvent('fcrp_f1:sv:requestMyStats') end },
        { label='Leaderboard',       icon='fas fa-ranking-star',
          action=function() TriggerServerEvent('fcrp_f1:sv:requestLeaderboard') end },
        { label='Claim Weekly Reward',icon='fas fa-gift',
          action=function() TriggerServerEvent('fcrp_f1:sv:claimWeeklyReward') end }, -- FIX #1
    })
    DBG('NPC spawned.')
end
CreateThread(SpawnRaceManagerNPC)

-- ============================================================
-- ORGANISER PANEL
-- ============================================================
local function OpenOrganizerMenu()
    local totalSlots = #Config.GridSpots
    local slotOpts   = {}
    for i = 1, totalSlots do
        local idx = i
        local assigned = slotLabels[idx]
        slotOpts[#slotOpts+1] = {
            title=string.format('P%d%s', idx, idx==1 and ' — Pole' or ''),
            description=assigned and ('✅ '..assigned) or 'Tap to assign',
            icon='user', iconColor=assigned and '#00cc66' or '#888888',
            onSelect=function() AssignSlot(idx) end,
        }
    end
    local options = {}
    table.insert(options, {title='STEP 1  ·  GRID', disabled=true, icon='table-cells', iconColor='#e10600'})
    for _,o in ipairs(slotOpts) do table.insert(options, o) end
    table.insert(options, {title='Clear All Slots', icon='rotate-left', iconColor='#cc4444',
        onSelect=function() slotLabels={}; TriggerServerEvent('fcrp_f1:sv:clearGrid'); OpenOrganizerMenu() end})
    table.insert(options, {title='Prepare Grid', description='Spawn cars on grid spots',
        icon='flag', iconColor='#ffcc00',
        onSelect=function() TriggerServerEvent('fcrp_f1:sv:setupGrid'); OpenOrganizerMenu() end})
    table.insert(options, {title='STEP 2  ·  FORMATION LAP', disabled=true, icon='shield-halved', iconColor='#e10600'})
    table.insert(options, {title='Deploy Safety Car', icon='car', iconColor='#ffaa00',
        onSelect=function() TriggerServerEvent('fcrp_f1:sv:deploySafetyCar'); OpenOrganizerMenu() end})
    table.insert(options, {title='STEP 3  ·  RACE START', disabled=true, icon='traffic-light', iconColor='#e10600'})
    table.insert(options, {title='START RACE', description='Despawn SC · Freeze grid · Lights out',
        icon='flag-checkered', iconColor='#00cc44',
        onSelect=function() TriggerServerEvent('fcrp_f1:sv:startGlobalRace'); OpenOrganizerMenu() end})
    table.insert(options, {title='TOOLS', disabled=true, icon='wrench', iconColor='#888888'})
    table.insert(options, {title='Race Director Camera', icon='video', iconColor='#88aaff',
        onSelect=function() OpenDirectorCamMenu() end})
    table.insert(options, {title='Force End / Reset', icon='circle-xmark', iconColor='#ff4444',
        onSelect=function() TriggerServerEvent('fcrp_f1:sv:forceEnd'); OpenOrganizerMenu() end})
    lib.registerContext({id='f1_organiser', title='  FLAME CITY GP  ·  Race Control', options=options})
    lib.showContext('f1_organiser')
end

RegisterNetEvent('fcrp_f1:cl:openOrganizerMenu', function(playerList)
    currentPlayerMap = {}
    for _,p in ipairs(playerList) do currentPlayerMap[p.id]=p.name end
    OpenOrganizerMenu()
end)
RegisterNetEvent('fcrp_f1:cl:slotAssigned', function(slot, pid, name)
    slotLabels[slot] = string.format('ID %d — %s', pid, name)
    OpenOrganizerMenu()
end)

function AssignSlot(slot)
    local result = lib.inputDialog('Assign P'..slot, {
        {type='number', label='Player Server ID', placeholder='e.g. 5', required=true, min=1}
    })
    if not result or not result[1] then OpenOrganizerMenu(); return end
    local tid = tonumber(result[1])
    if not tid then lib.notify({title='Invalid ID', type='error'}); OpenOrganizerMenu(); return end
    TriggerServerEvent('fcrp_f1:sv:assignSlot', slot, tid)
end

-- ============================================================
-- STATS / LEADERBOARD MENUS
-- ============================================================
RegisterNetEvent('fcrp_f1:cl:openStatsMenu', function(stats, history)
    local bLap = stats.best_lap_ms and FmtMs(stats.best_lap_ms) or '—'
    local opts  = {
        {title='MMR',         description=tostring(stats.mmr or 1500), icon='ranking-star', disabled=true},
        {title='XP',          description=tostring(stats.xp or 0),     icon='star',         disabled=true},
        {title='Wins',        description=tostring(stats.wins or 0),    icon='trophy',       disabled=true},
        {title='Races',       description=tostring(stats.races or 0),   icon='flag-checkered',disabled=true},
        {title='Podiums',     description=tostring(stats.podiums or 0), icon='medal',        disabled=true},
        {title='Fastest Laps',description=tostring(stats.fastest_laps or 0), icon='bolt',   disabled=true},
        {title='Best Lap',    description=bLap,                         icon='stopwatch',    disabled=true},
    }
    if history and #history > 0 then
        table.insert(opts, {title='── Last Races ──', disabled=true, icon='clock'})
        for _, r in ipairs(history) do
            local desc = string.format('P%d  %s  |  Best: %s  |  %s',
                r.position, r.race_time or '?', r.best_lap or '?', r.tyre_used or '?')
            if r.dq == 1 then desc = 'DQ — ' .. (r.dq_reason or '?') end
            table.insert(opts, {title=os.date('%d %b', r.race_date and os.time() or os.time()), description=desc, icon='calendar', disabled=true})
        end
    end
    lib.registerContext({id='f1_stats', title='🏎️ My F1 Career', options=opts})
    lib.showContext('f1_stats')
end)

RegisterNetEvent('fcrp_f1:cl:showLeaderboard', function(rows)
    if not rows or #rows == 0 then
        lib.notify({title='Leaderboard', description='No data yet.', type='inform'}); return
    end
    local opts = {}
    for i, r in ipairs(rows) do
        opts[#opts+1] = {
            title=string.format('#%d  %s', i, r.citizenid),
            description=string.format('MMR: %d  |  Wins: %d  |  Races: %d', r.mmr, r.wins, r.races),
            icon= i==1 and 'crown' or (i<=3 and 'medal' or 'user'),
            iconColor= i==1 and '#FFD700' or (i==2 and '#C0C0C0' or (i==3 and '#CD7F32' or '#888888')),
            disabled=true,
        }
    end
    lib.registerContext({id='f1_lb', title='🏁 F1 Leaderboard — Top 20', options=opts})
    lib.showContext('f1_lb')
end)

-- ============================================================
-- RACE DIRECTOR CAMERA  (4 modes, cycle with F6)
-- ============================================================
local CAM_MODES = {
    {
        label = 'Follow',
        -- Behind and slightly above the car, smooth chase
        update = function(cam, veh)
            local pos     = GetEntityCoords(veh)
            local heading = GetEntityHeading(veh)
            local rad     = math.rad(heading)
            local cx = pos.x + math.sin(rad) * 9.0
            local cy = pos.y + math.cos(rad) * 9.0
            local cz = pos.z + 3.5
            SetCamCoord(cam, cx, cy, cz)
            PointCamAtEntity(cam, veh, 0.0, 0.0, 0.5, true)
            SetCamFov(cam, 52.0)
        end,
    },
    {
        label = 'Helicopter',
        -- Directly overhead, top-down bird's eye
        update = function(cam, veh)
            local pos = GetEntityCoords(veh)
            SetCamCoord(cam, pos.x, pos.y, pos.z + 28.0)
            PointCamAtEntity(cam, veh, 0.0, 0.0, 0.0, true)
            SetCamFov(cam, 45.0)
        end,
    },
    {
        label = 'TV Cam',
        -- Wide side-on angle, slightly elevated
        update = function(cam, veh)
            local pos     = GetEntityCoords(veh)
            local heading = GetEntityHeading(veh)
            local rad     = math.rad(heading + 90.0)
            local cx = pos.x + math.sin(rad) * 14.0
            local cy = pos.y + math.cos(rad) * 14.0
            local cz = pos.z + 5.0
            SetCamCoord(cam, cx, cy, cz)
            PointCamAtEntity(cam, veh, 0.0, 0.0, 0.5, true)
            SetCamFov(cam, 60.0)
        end,
    },
    {
        label = 'Onboard',
        -- Hood-mount first-person style
        update = function(cam, veh)
            local pos     = GetEntityCoords(veh)
            local heading = GetEntityHeading(veh)
            local fwd     = GetEntityForwardVector(veh)
            local cx = pos.x + fwd.x * 2.2
            local cy = pos.y + fwd.y * 2.2
            local cz = pos.z + 0.55
            SetCamCoord(cam, cx, cy, cz)
            PointCamAtEntity(cam, veh, fwd.x * 30, fwd.y * 30, 0.0, false)
            SetCamFov(cam, 68.0)
        end,
    },
}

function OpenDirectorCamMenu()
    local result = lib.inputDialog('Race Director Camera', {
        {type='number', label='Target Player Server ID', placeholder='e.g. 3', required=true, min=1}
    })
    lib.showContext('f1_organiser')
    if not result or not result[1] then return end
    TriggerServerEvent('fcrp_f1:sv:getVehicleForCam', tonumber(result[1]))
end

RegisterNetEvent('fcrp_f1:cl:attachDirectorCam', function(netId)
    StopDirectorCam()
    if not NetworkDoesNetworkIdExist(netId) then
        lib.notify({title='Cam Error', description='Vehicle not found', type='error'}); return
    end
    local veh = NetToVeh(netId)
    if not DoesEntityExist(veh) then
        lib.notify({title='Cam Error', description='Entity missing', type='error'}); return
    end
    directorTarget = veh
    directorMode   = 1
    directorCam    = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(directorCam, true)
    RenderScriptCams(true, true, 500, true, false)
    SendNUIMessage({action='camMode', label=CAM_MODES[directorMode].label})
    lib.notify({title='Director Cam ON', description='F6 = cycle mode  |  Backspace = exit', type='inform'})

    CreateThread(function()
        while directorCam and IsCamActive(directorCam) do
            if not DoesEntityExist(directorTarget) then break end

            -- Exit
            if IsControlJustPressed(0, 194) or IsControlJustPressed(0, 177) then break end

            -- Cycle mode with F6 (key 311)
            if IsControlJustPressed(0, 311) then
                directorMode = (directorMode % #CAM_MODES) + 1
                SendNUIMessage({action='camMode', label=CAM_MODES[directorMode].label})
                lib.notify({title='Camera: '..CAM_MODES[directorMode].label, type='inform', duration=2000})
            end

            CAM_MODES[directorMode].update(directorCam, directorTarget)
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
        SendNUIMessage({action='camHide'})
    end
end

-- ============================================================
-- BASE HANDLING
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
-- TIRE COMPOUNDS
-- ============================================================
local function GetEngineDamageMult()
    if engineStatus=='CRITICAL' then return 0.35
    elseif engineStatus=='DAMAGED' then return 0.60
    elseif engineStatus=='WARNING' then return 0.85
    else return 1.0 end
end

local function ApplyTireCompound(veh, compound)
    if not DoesEntityExist(veh) then return end
    local c = Config.TireCompounds[compound]
    if not c then return end
    local isDegraded = (currentLap - 1) >= c.laps  -- 0-based so lap 1 = first lap
    local df    = BASE_DRIVE_FORCE + c.driveForce + (isDegraded and c.degradedForce or 0.0)
    local tMax  = c.tractionMax  + (isDegraded and c.degradedTraction or 0.0)
    local tMin  = c.tractionMin  + (isDegraded and c.degradedTraction*0.5 or 0.0)
    local drsBoost = drsOpen and Config.DRS.driveForceBoost or 0.0
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce', (df + drsBoost) * GetEngineDamageMult())
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax',  tMax)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin',  tMin)
    ModifyVehicleTopSpeed(veh, BASE_TOP_SPEED + c.topSpeedBonus + (drsOpen and Config.DRS.topSpeedBoost or 0.0))
end

-- tire wear check
local lastTireWarn = ''
local function CheckTireWear()
    if not myRaceCar then return end
    local c = Config.TireCompounds[currentTyre]
    if not c then return end
    local lapsOn = currentLap - 1
    if lapsOn >= c.laps and lastTireWarn ~= currentTyre..currentLap then
        lastTireWarn = currentTyre..currentLap
        Notify('tireWorn', {tire=c.label}, 'warning')
        ApplyTireCompound(myRaceCar, currentTyre)
    end
end

-- ============================================================
-- PIT STOP
-- ============================================================
local function OpenTireMenu()
    local opts = {}
    for id, comp in pairs(Config.TireCompounds) do
        local cid = id
        opts[#opts+1] = {
            title=comp.label,
            description=string.format('~%d laps  ·  Force +%.2f  ·  Speed +%.0f',
                comp.laps, comp.driveForce, comp.topSpeedBonus),
            icon='circle',
            iconColor=string.format('rgb(%d,%d,%d)', comp.color[1], comp.color[2], comp.color[3]),
            onSelect=function() TriggerServerEvent('fcrp_f1:sv:pitStop', cid) end,
        }
    end
    lib.registerContext({id='f1_tire_menu', title='🛞 Compound Choice', options=opts})
    lib.showContext('f1_tire_menu')
end

RegisterNetEvent('fcrp_f1:cl:doPitStop', function(compound)
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end
    lapIsValid = false  -- pit lap is always invalid for fastest-lap purposes
    FreezeEntityPosition(myRaceCar, true)
    SetVehicleEngineOn(myRaceCar, false, true, false)
    lib.progressBar({
        duration=Config.PitStop.stopDuration*1000,
        label='Changing tires…',
        useWhileDead=false, canCancel=false,
        disable={move=true, car=true, mouse=false, combat=true},
    })
    currentTyre   = compound
    hasPitted     = true
    pitCount      = pitCount + 1
    lastTireWarn  = ''
    ApplyTireCompound(myRaceCar, compound)
    FreezeEntityPosition(myRaceCar, false)
    SetVehicleEngineOn(myRaceCar, true, false, false)
    local c = Config.TireCompounds[compound]
    Notify('pitDone', {tire=c and c.label or compound}, 'success')
    if OpenClientFunctions and OpenClientFunctions.OnPitExit then
        OpenClientFunctions.OnPitExit(compound)
    end
end)

-- Register pit zone — called AFTER race starts (not on spawn)
local function RegisterPitZone()
    if pitZoneAdded or not Config.PitStop.enabled then return end
    pitZoneAdded = true
    local z = Config.PitStop.zone
    exports['ox_target']:addBoxZone({
        coords=z.coords, size=z.size, rotation=z.heading,
        debug=Config.Debug,
        options={{
            label='Pit Stop', icon='fas fa-wrench',
            onSelect=function()
                if not isRacing then lib.notify({title='Not racing', type='error'}); return end
                if OpenClientFunctions and OpenClientFunctions.OnPitEntry then
                    OpenClientFunctions.OnPitEntry()
                end
                OpenTireMenu()
            end,
        }},
    })
end

-- ============================================================
-- DRS
-- ============================================================
local function UpdateDRS(coords)
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end
    if not Config.DRSZones or #Config.DRSZones == 0 then return end
    local wasOpen = drsOpen; local newOpen = false; local newZone = 0
    for i, zone in ipairs(Config.DRSZones) do
        local ex=zone.exit.x-zone.entry.x; local ey=zone.exit.y-zone.entry.y; local ez=zone.exit.z-zone.entry.z
        local lenSq=ex*ex+ey*ey+ez*ez; local t=0.0
        if lenSq>0 then
            local dx=coords.x-zone.entry.x; local dy=coords.y-zone.entry.y; local dz=coords.z-zone.entry.z
            t=(dx*ex+dy*ey+dz*ez)/lenSq
        end
        if t>=0.0 and t<=1.0 then
            local cx=zone.entry.x+t*ex; local cy=zone.entry.y+t*ey; local cz=zone.entry.z+t*ez
            if math.sqrt((coords.x-cx)^2+(coords.y-cy)^2+(coords.z-cz)^2) < zone.radius then
                newOpen=true; newZone=i; break
            end
        end
    end
    if newOpen ~= wasOpen or newZone ~= drsZoneIndex then
        drsOpen=newOpen; drsZoneIndex=newZone
        if drsOpen then
            drsCount = drsCount + 1
            TriggerServerEvent('fcrp_f1:sv:drsUsed')
            lib.showTextUI(Config.Notify.drsOpen, {
                position='bottom-center',
                style={backgroundColor='#007a00', color='white',
                       fontSize='18px', fontWeight='bold', padding='6px 20px', letterSpacing='3px'}
            })
        else lib.hideTextUI() end
        ApplyTireCompound(myRaceCar, currentTyre)
    end
end

-- ============================================================
-- ENGINE DAMAGE
-- ============================================================
local function UpdateEngineDamage()
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end
    local health = GetVehicleEngineHealth(myRaceCar)
    local new
    if health <= Config.EngineHealth.critical then new='CRITICAL'
    elseif health <= Config.EngineHealth.damaged then new='DAMAGED'
    elseif health <= Config.EngineHealth.warning then new='WARNING'
    else new='OK' end
    if new ~= engineStatus then
        engineStatus = new
        if new == 'WARNING'  then Notify('engineWarning',  nil, 'warning')
        elseif new == 'DAMAGED'  then Notify('engineDamaged',  nil, 'error')
        elseif new == 'CRITICAL' then Notify('engineCritical', nil, 'error') end
        if new ~= 'OK' then
            engineOk = false
            TriggerServerEvent('fcrp_f1:sv:engineDamaged')
        end
        ApplyTireCompound(myRaceCar, currentTyre)
    end
end

-- ============================================================
-- SECTOR TIMING
-- ============================================================
local function GetCurrentSector()
    for i, s in ipairs(Config.Sectors) do
        if currentCP <= s.endCP then return i end
    end
    return #Config.Sectors
end

local function OnSectorComplete(sectorIdx, ms)
    local best = bestSectorMs[sectorIdx]
    local label = (Config.Sectors[sectorIdx] and Config.Sectors[sectorIdx].label) or ('S'..sectorIdx)
    local timeStr = FmtMs(ms)
    local notifyKey
    if not best or ms < best then
        bestSectorMs[sectorIdx] = ms
        notifyKey = 'sectorPurple'
    elseif ms <= (best * 1.02) then
        notifyKey = 'sectorGreen'
    else
        notifyKey = 'sectorYellow'
    end
    Notify(notifyKey, {sector=label, time=timeStr}, 'inform')
    sectorTimes[sectorIdx] = { label=label, ms=ms, str=timeStr }
    DBG(string.format('Sector %d: %s', sectorIdx, timeStr))
end

-- ============================================================
-- RACE LINE
-- ============================================================
local function DrawRacingLine(pCoords, target)
    if not Config.RaceLine.enabled then return end
    if #(pCoords-target) > Config.RaceLine.maxDist then return end
    local segs = Config.RaceLine.segments
    local heading = math.deg(math.atan(target.x-pCoords.x, target.y-pCoords.y)) + 180.0
    for i = 1, segs do
        local frac = i/segs
        local x = pCoords.x + (target.x-pCoords.x)*frac
        local y = pCoords.y + (target.y-pCoords.y)*frac
        local found, gz = GetGroundZFor_3dCoord(x, y, pCoords.z+10.0, false)
        local z = found and (gz-0.1) or (pCoords.z-0.3)
        DrawMarker(24, x,y,z, 0,0,0, 0,0,heading, 0.9,0.9,0.9,
            0, 210, 255, math.floor(220*(1.0-frac*0.6)), false, false, 2, nil, nil, false)
    end
end

-- ============================================================
-- HUD
-- ============================================================
local hudFastestLapFlash = 0   -- timestamp when fastest lap was set

local function DrawRaceHUD(lap, maxLaps, cp, totalCPs)
    -- LAP counter
    SetTextFont(4); SetTextScale(0.0,0.50); SetTextColour(255,255,255,255)
    SetTextOutline(); SetTextEntry('STRING')
    AddTextComponentString(string.format('LAP  %d / %d', lap, maxLaps))
    DrawText(0.82, 0.80)

    -- CP
    SetTextFont(0); SetTextScale(0.0,0.28); SetTextColour(160,210,255,200)
    SetTextOutline(); SetTextEntry('STRING')
    AddTextComponentString(string.format('CP  %d / %d', cp, totalCPs))
    DrawText(0.82, 0.840)

    -- Best lap
    if bestLapMs then
        SetTextFont(4); SetTextScale(0.0,0.26); SetTextColour(170,255,170,220)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString('BEST  '..FmtMs(bestLapMs))
        DrawText(0.82, 0.868)
    end

    -- Fastest lap flash
    if GetGameTimer() - hudFastestLapFlash < 4000 then
        SetTextFont(4); SetTextScale(0.0,0.28); SetTextColour(190,0,255,240)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString('💜 FASTEST LAP')
        DrawText(0.38, 0.04)
    end

    -- Tire
    local tc = Config.TireCompounds[currentTyre]
    if tc then
        local r,g,b = table.unpack(tc.color)
        local lapsOn = currentLap - 1
        local worn   = lapsOn >= tc.laps
        SetTextFont(0); SetTextScale(0.0,0.26); SetTextColour(r, g, b, worn and 140 or 220)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString(tc.label..(worn and '  [WORN]' or ''))
        DrawText(0.82, 0.894)
    end

    -- Invalid lap banner
    if not lapIsValid then
        SetTextFont(4); SetTextScale(0.0,0.28); SetTextColour(255,180,0,255)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString('⚠️  LAP INVALID')
        DrawText(0.38, 0.08)
    end

    -- Gap to leader
    if myGapToLeader then
        local r,g,b = 255,255,255
        if myGapToLeader=='LEADER' then r,g,b=255,215,0
        elseif myGapToLeader:sub(1,1)=='+' then r,g,b=255,100,100 end
        SetTextFont(4); SetTextScale(0.0,0.32); SetTextColour(r,g,b,230)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString(myGapToLeader)
        DrawText(0.82, 0.920)
    end

    -- Engine warning
    if engineStatus ~= 'OK' then
        local colours={WARNING={255,200,0,220},DAMAGED={255,100,0,220},CRITICAL={255,30,30,255}}
        local c = colours[engineStatus] or {255,255,255,200}
        SetTextFont(4); SetTextScale(0.0,0.26); SetTextColour(c[1],c[2],c[3],c[4])
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString('ENGINE '..engineStatus)
        DrawText(0.82, 0.950)
    end
end

-- ============================================================
-- LEADERBOARD HUD
-- ============================================================
RegisterNetEvent('fcrp_f1:cl:updateLeaderboard', function(data, gap)
    leaderboardData=data; myGapToLeader=gap
end)

local function DrawLeaderboard()
    if not leaderboardData or #leaderboardData == 0 then return end
    local sx, sy, lh = 0.78, 0.04, 0.028
    SetTextFont(4); SetTextScale(0.0,0.27); SetTextColour(255,200,0,255)
    SetTextOutline(); SetTextEntry('STRING')
    AddTextComponentString('FLAME CITY GP')
    DrawText(sx, sy)
    for i, e in ipairs(leaderboardData) do
        local y     = sy + (i*lh) + 0.01
        local label
        if e.finished and e.pos then
            label = string.format('P%d  %s  ✓%s', e.pos, e.name, e.time or '')
        elseif e.dq then
            label = string.format('DQ  %s', e.name)
        else
            label = string.format('P%d  %s  L%d·%d', i, e.name, e.lap or 1, e.cp or 1)
        end
        local r,g,b = 220,220,220
        if e.dq then r,g,b=255,60,60
        elseif i==1 and e.finished then r,g,b=255,215,0
        elseif i==2 and e.finished then r,g,b=192,192,192
        elseif i==3 and e.finished then r,g,b=205,127,50 end
        SetTextFont(0); SetTextScale(0.0,0.24); SetTextColour(r,g,b,220)
        SetTextOutline(); SetTextEntry('STRING')
        AddTextComponentString(label)
        DrawText(sx, y)
    end
end

CreateThread(function() while true do DrawLeaderboard(); Wait(0) end end)

-- ============================================================
-- GPS
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
    currentBlip=nil; SetWaypointOff()
end

-- ============================================================
-- F1 STARTING LIGHTS
-- ============================================================
local countdownDone = false
local function F1Countdown()
    countdownDone = false
    CreateThread(function()
        local lights = {
            {m='● ○ ○ ○ ○',c='#7a0000'},{m='● ● ○ ○ ○',c='#a00000'},
            {m='● ● ● ○ ○',c='#c80000'},{m='● ● ● ● ○',c='#e00000'},
            {m='● ● ● ● ●',c='#ff0000'},
        }
        for _, light in ipairs(lights) do
            lib.showTextUI(light.m, {position='top-center',
                style={backgroundColor=light.c, color='white', fontSize='48px',
                       fontWeight='bold', padding='10px 28px', letterSpacing='6px'}})
            PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', 1)
            Wait(900)
        end
        lib.hideTextUI(); Wait(math.random(400, 900))
        lib.showTextUI('GO GO GO!', {position='top-center',
            style={backgroundColor='#00cc44', color='white', fontSize='54px',
                   fontWeight='bold', padding='10px 28px'}})
        PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', 1)
        Wait(1200); lib.hideTextUI()
        countdownDone = true
    end)
    while not countdownDone do Wait(100) end
end

-- ============================================================
-- FORMATION LAP
-- ============================================================
RegisterNetEvent('fcrp_f1:cl:spawnSafetyCar', function()
    local cfg = Config.FormationLap
    local maxSpeed = cfg.maxSpeed / 3.6
    local startSpot = cfg.safetyCarSpot
    RequestModel(cfg.safetyCarModel)
    while not HasModelLoaded(cfg.safetyCarModel) do Wait(0) end
    safetyCar = CreateVehicle(cfg.safetyCarModel, startSpot.x, startSpot.y, startSpot.z, startSpot.w, true, false)
    SetEntityAsMissionEntity(safetyCar, true, true)
    SetVehicleColours(safetyCar, 12, 12)
    SetVehicleNumberPlateText(safetyCar, 'SAFETY')
    SetVehicleEngineOn(safetyCar, true, true, false)
    SetVehicleMaxSpeed(safetyCar, maxSpeed)
    safetyCarBlip = AddBlipForEntity(safetyCar)
    SetBlipSprite(safetyCarBlip, 225); SetBlipColour(safetyCarBlip, 17); SetBlipScale(safetyCarBlip, 1.1)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Safety Car'); EndTextCommandSetBlipName(safetyCarBlip)
    local dm = `s_m_m_security_01`; RequestModel(dm); while not HasModelLoaded(dm) do Wait(0) end
    local driver = CreatePedInsideVehicle(safetyCar, 26, dm, -1, true, false)
    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true); SetPedKeepTask(driver, true)
    safetyCarActive = true
    local route = {}
    for _, cp in ipairs(Config.Checkpoints) do route[#route+1] = vector3(cp.x,cp.y,cp.z) end
    route[#route+1] = vector3(startSpot.x, startSpot.y, startSpot.z)
    CreateThread(function()
        for _, dest in ipairs(route) do
            if not safetyCarActive then break end
            TaskVehicleDriveToCoordLongrange(driver, safetyCar, dest.x, dest.y, dest.z, maxSpeed, 786603, 5.0)
            while safetyCarActive do
                if not DoesEntityExist(safetyCar) then safetyCarActive=false; break end
                if #(GetEntityCoords(safetyCar)-dest) < 18.0 then break end
                Wait(300)
            end
        end
        if safetyCarActive then TriggerServerEvent('fcrp_f1:sv:formationLapDone') end
    end)
    lib.notify({title='🟡 Safety Car', description='Follow the SC around the circuit.', type='inform'})
end)

RegisterNetEvent('fcrp_f1:cl:despawnSafetyCar', function()
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

RegisterNetEvent('fcrp_f1:cl:beginFormationLap', function()
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
            style={backgroundColor='#aa7700', color='white', fontSize='18px', fontWeight='bold', padding='8px 22px'}
        })
    end
end)

RegisterNetEvent('fcrp_f1:cl:returnToGrid', function(spot)
    formationActive = false; lib.hideTextUI()
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
    lib.notify({title='🏁 Back on the Grid', description='Lights out in a moment…', type='inform'})
end)

RegisterNetEvent('fcrp_f1:cl:endFormationLap', function()
    formationActive=false; lib.hideTextUI()
    if myRaceCar and DoesEntityExist(myRaceCar) then
        SetVehicleMaxSpeed(myRaceCar, 0.0); FreezeEntityPosition(myRaceCar, true)
        SetVehicleEngineOn(myRaceCar, false, true, false)
    end
end)

-- ============================================================
-- SPAWN / CLEANUP
-- ============================================================
local function AssignLivery(veh)
    local pool = {}
    for i = 2, Config.LiveryCount do if not usedLiveries[i] then pool[#pool+1] = i end end
    local chosen = #pool > 0 and pool[math.random(1,#pool)] or math.random(2, Config.LiveryCount)
    usedLiveries[chosen] = true
    SetVehicleLivery(veh, chosen)
end

local function ApplyMaxMods(veh)
    SetVehicleModKit(veh, 0)
    for _, slot in ipairs({0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23}) do
        local count = GetNumVehicleMods(veh, slot)
        if count > 0 then SetVehicleMod(veh, slot, count-1, false) end
    end
    ToggleVehicleMod(veh, 18, true); ToggleVehicleMod(veh, 22, true)
end

RegisterNetEvent('fcrp_f1:cl:spawnYourCar', function(spot)
    local ped = cache and cache.ped or PlayerPedId()
    if not ped or ped == 0 then lib.notify({title='Spawn Error', type='error'}); return end
    local model = Config.F1CarModel
    RequestModel(model); while not HasModelLoaded(model) do Wait(0) end
    myRaceCar = CreateVehicle(model, spot.x, spot.y, spot.z, spot.w, true, false)
    ApplyF1Handling(myRaceCar); ApplyMaxMods(myRaceCar); AssignLivery(myRaceCar)
    TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(myRaceCar))
    SetPedIntoVehicle(ped, myRaceCar, -1)
    FreezeEntityPosition(myRaceCar, true)
    SetVehicleDoorsLocked(myRaceCar, 4)
    SetVehicleEngineOn(myRaceCar, false, true, false)
    -- Reset all per-session state
    drsOpen=false; engineStatus='OK'; currentTyre='medium'
    hasPitted=false; pitCount=0; drsCount=0; engineOk=true
    lapIsValid=true; offCourseTimer=0
    bestLapMs=nil; fastestLapMs=nil; lapTimesThisRace={}
    sectorTimes={}; bestSectorMs={[1]=nil,[2]=nil,[3]=nil}
    currentSectorIdx=1; lapStartMs=nil; sectorStartMs=nil
    lastTireWarn=''
    CreateThread(function()
        while myRaceCar and DoesEntityExist(myRaceCar) and not isRacing do
            SetVehicleCurrentRpm(myRaceCar, 0.1); Wait(0)
        end
    end)
end)

RegisterNetEvent('fcrp_f1:cl:cleanupCars', function()
    ClearWaypoint(); StopDirectorCam(); lib.hideTextUI()
    isRacing=false; formationActive=false; currentLap=1; currentCP=1
    leaderboardData={}; myGapToLeader=nil; drsOpen=false
    engineStatus='OK'; usedLiveries={}; lapIsValid=true
    currentTyre='medium'; pitCount=0; drsCount=0; engineOk=true
    if myRaceCar and DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
    myRaceCar=nil
    SendNUIMessage({action='hideResults'}); SetNuiFocus(false, false)
end)

RegisterNetEvent('fcrp_f1:cl:teleportPostRace', function()
    ClearWaypoint(); isRacing=false; lib.hideTextUI()
    if myRaceCar and DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
    myRaceCar=nil
    local ped = cache and cache.ped or PlayerPedId()
    if ped and ped ~= 0 then
        SetEntityCoords(ped, Config.PostRaceLocation.x, Config.PostRaceLocation.y,
            Config.PostRaceLocation.z, false, false, false, false)
    end
    SendNUIMessage({action='hideResults'}); SetNuiFocus(false, false)
end)

-- ============================================================
-- RESULTS NUI
-- ============================================================
-- BUG FIX #5: showResults handler moved to client/nui_callbacks.lua
-- as 'fcrp_f1:cl:showResults_NUI' with corrected SetNuiFocus(true, false).
-- This original handler is kept as a no-op fallback for external resources.
RegisterNetEvent('fcrp_f1:cl:showResults', function(data)
    -- Handled by cl:showResults_NUI in nui_callbacks.lua
    DBG('[COMPAT] cl:showResults received — NUI handled by _NUI variant')
end)

-- ============================================================
-- FASTEST LAP CLIENT FLASH
-- ============================================================
RegisterNetEvent('fcrp_f1:cl:fastestLapSet', function(ms)
    hudFastestLapFlash = GetGameTimer()
    Notify('fastestLap', {time=FmtMs(ms), xp=tostring(Config.FastestLapXP or 15)}, 'inform')
end)

-- ============================================================
-- MAIN RACE LOOP
-- ============================================================
RegisterNetEvent('fcrp_f1:cl:startRace', function()
    if not myRaceCar then return end
    if isRacing then return end
    if OpenClientFunctions and OpenClientFunctions.CanStartRace then
        if not OpenClientFunctions.CanStartRace() then return end
    end
    if not Config.Checkpoints or #Config.Checkpoints == 0 then
        lib.notify({title='Race Error', description='No checkpoints!', type='error'}); return
    end

    currentLap=1; currentCP=1; formationActive=false; lapIsValid=true
    sectorTimes={}; currentSectorIdx=1

    F1Countdown()

    FreezeEntityPosition(myRaceCar, false)
    SetVehicleEngineOn(myRaceCar, true, false, false)
    SetVehicleDoorsLocked(myRaceCar, 1)
    isRacing = true

    ApplyTireCompound(myRaceCar, currentTyre)
    lapStartMs     = GetCurrentMs()
    sectorStartMs  = GetCurrentMs()
    raceStartMs    = GetCurrentMs()

    -- Lock to first-person view
    SetFollowVehicleCamViewMode(0)

    TriggerServerEvent('fcrp_f1:sv:raceClockStart')
    UpdateRaceWaypoint(Config.Checkpoints[currentCP])

    -- Now safe to register pit zone
    RegisterPitZone()

    CreateThread(function()
        while isRacing do
            local ped    = cache and cache.ped or PlayerPedId()
            local coords = GetEntityCoords(ped)

            -- DQ: left vehicle
            if not IsPedInVehicle(ped, myRaceCar, false) then
                isRacing=false; ClearWaypoint(); lib.hideTextUI()
                if DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
                myRaceCar=nil
                TriggerServerEvent('fcrp_f1:sv:dqPlayer', 'Left vehicle')
                lib.notify({title='DISQUALIFIED', description='You left the vehicle!', type='error'})
                break
            end

            local target = Config.Checkpoints[currentCP]
            if not target then isRacing=false; break end

            -- Track limit invalidation
            if #(coords - target) > Config.LapInvalidDist then
                offCourseTimer = offCourseTimer + 1
                if offCourseTimer >= (Config.LapInvalidTime * 10) and lapIsValid then
                    lapIsValid = false
                    Notify('lapInvalid', nil, 'warning')
                end
            else
                offCourseTimer = 0
            end

            -- Per-frame systems
            UpdateDRS(coords)
            UpdateEngineDamage()
            CheckTireWear()
            DrawRaceHUD(currentLap, Config.MaxLaps, currentCP, #Config.Checkpoints)
            DrawRacingLine(coords, target)

            -- Enforce first-person view
            if GetFollowVehicleCamViewMode() ~= 0 then
                SetFollowVehicleCamViewMode(0)
            end

            -- Pit lane speed limiter
            if Config.PitStop.enabled and Config.PitStop.speedLimit > 0 then
                local pitZ = Config.PitStop.zone
                if #(coords - pitZ.coords) < 22.0 then
                    local spd = GetEntitySpeed(myRaceCar) * 3.6
                    if spd > Config.PitStop.speedLimit then
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
                    DrawMarker(4, target.x,target.y,target.z, 0,0,0,0,0,0,5,5,5,255,255,255,200,false,false,2,nil,nil,false)
                    DrawMarker(1, target.x,target.y,target.z+0.05,0,0,0,0,0,0,7,7,0.4,255,40,40,100,false,false,2,nil,nil,false)
                else
                    DrawMarker(1, target.x,target.y,target.z+0.05,0,0,0,0,0,0,5,5,1.2,0,180,255,160,false,false,2,nil,nil,false)
                end
            end

            -- Checkpoint hit
            if #(coords - target) < 15.0 then
                PlaySoundFrontend(-1, 'CHECKPOINT_BEAT', 'HUD_MINI_GAME_SOUNDSET', 1)

                -- Sector timing
                local newSector = GetCurrentSector()
                if newSector ~= currentSectorIdx and sectorStartMs then
                    OnSectorComplete(currentSectorIdx, GetCurrentMs() - sectorStartMs)
                    currentSectorIdx = newSector
                    sectorStartMs    = GetCurrentMs()
                end

                if OpenClientFunctions and OpenClientFunctions.OnCheckpointPassed then
                    OpenClientFunctions.OnCheckpointPassed(currentCP, #Config.Checkpoints)
                end

                if currentCP < #Config.Checkpoints then
                    currentCP = currentCP + 1
                else
                    -- Complete the final sector
                    if sectorStartMs then
                        OnSectorComplete(currentSectorIdx, GetCurrentMs() - sectorStartMs)
                    end

                    currentCP  = 1
                    local lapMs = GetCurrentMs() - (lapStartMs or GetCurrentMs())

                    -- Lap time
                    if lapIsValid then
                        if not bestLapMs or lapMs < bestLapMs then
                            bestLapMs = lapMs
                            if not fastestLapMs or lapMs < fastestLapMs then fastestLapMs = lapMs end
                        end
                        lapTimesThisRace[#lapTimesThisRace+1] = lapMs
                        -- Sector snapshot for server
                        local stForServer = {}
                        for _, s in ipairs(sectorTimes) do stForServer[#stForServer+1] = {label=s.label, ms=s.ms, str=s.str} end
                        TriggerServerEvent('fcrp_f1:sv:lapComplete', lapMs, stForServer)
                    end

                    lapStartMs     = GetCurrentMs()
                    sectorStartMs  = GetCurrentMs()
                    currentSectorIdx = 1
                    sectorTimes    = {}
                    lapIsValid     = true
                    offCourseTimer = 0
                    currentLap     = currentLap + 1

                    if OpenClientFunctions and OpenClientFunctions.OnLapComplete then
                        OpenClientFunctions.OnLapComplete(currentLap - 1, lapMs)
                    end

                    if currentLap > Config.MaxLaps then
                        -- Mandatory pit check
                        if Config.PitStop.enabled and Config.PitStop.mandatory and not hasPitted then
                            TriggerServerEvent('fcrp_f1:sv:dqPlayer', 'No pit stop')
                            Notify('pitMandatoryDQ', nil, 'error')
                            isRacing=false; ClearWaypoint(); lib.hideTextUI(); break
                        end
                        -- Finish — send full client data
                        isRacing=false; ClearWaypoint(); lib.hideTextUI()
                        TriggerServerEvent('fcrp_f1:sv:finishRace', {
                            fastestLapMs = fastestLapMs,
                            bestLapStr   = FmtMs(fastestLapMs),
                            sectorTimes  = sectorTimes,
                            tyre         = currentTyre,
                            pitCount     = pitCount,
                            drsCount     = drsCount,
                            engineOk     = engineOk,
                        })
                        if OpenClientFunctions and OpenClientFunctions.OnRaceFinish then
                            OpenClientFunctions.OnRaceFinish(0, GetCurrentMs() - (raceStartMs or GetCurrentMs()))
                        end
                        break
                    else
                        local lapNotif = (Config.Notify.lapComplete)
                            :gsub('{lap}', tostring(currentLap-1))
                            :gsub('{time}', FmtMs(lapMs))
                        lib.notify({title='Lap Complete', description=lapNotif, type='inform', duration=3000})
                    end
                end

                UpdateRaceWaypoint(Config.Checkpoints[currentCP])
                TriggerServerEvent('fcrp_f1:sv:updateProgress', currentLap, currentCP)
            end

            Wait(0)
        end

        if drsOpen then lib.hideTextUI(); drsOpen=false end
    end)
end)

-- ============================================================
-- SPECTATOR MODE
-- ============================================================
local function StopSpectate()
    if not isSpectating then return end
    isSpectating = false
    specTargets  = {}
    specIndex    = 1
    if specCam then
        RenderScriptCams(false, true, 500, true, false)
        DestroyCam(specCam, false)
        specCam = nil
    end
    SendNUIMessage({action='specHide'})
    lib.notify({title='Spectator Mode', description='You stopped spectating.', type='inform'})
end

local function UpdateSpecCam()
    if not isSpectating or #specTargets == 0 then return end
    local t = specTargets[specIndex]
    if not t then return end
    if not NetworkDoesNetworkIdExist(t.netId) then return end
    local veh = NetToVeh(t.netId)
    if not DoesEntityExist(veh) then return end

    local pos     = GetEntityCoords(veh)
    local heading = GetEntityHeading(veh)
    local rad     = math.rad(heading)
    SetCamCoord(specCam, pos.x + math.sin(rad)*10.0, pos.y + math.cos(rad)*10.0, pos.z + 4.0)
    PointCamAtEntity(specCam, veh, 0.0, 0.0, 0.5, true)
    SetCamFov(specCam, 52.0)

    SendNUIMessage({
        action = 'specUpdate',
        name   = t.name,
        info   = string.format('LAP %d  ·  P%d', t.lap or 1, t.pos or 1),
    })
end

RegisterNetEvent('fcrp_f1:cl:startSpectating', function(targets)
    if isSpectating then StopSpectate() end
    if not targets or #targets == 0 then
        lib.notify({title='No Drivers', description='Race not active or no drivers on track.', type='error'}); return
    end

    isSpectating = true
    specTargets  = targets
    specIndex    = 1

    local ped = cache and cache.ped or PlayerPedId()
    local vp  = Config.Spectator.vantagePoint
    SetEntityCoords(ped, vp.x, vp.y, vp.z, false, false, false, false)
    SetEntityHeading(ped, vp.w)

    specCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamActive(specCam, true)
    RenderScriptCams(true, true, 500, true, false)

    lib.notify({
        title       = 'Spectator Mode',
        description = 'LEFT / RIGHT = cycle drivers  |  Backspace = exit',
        type        = 'inform',
        duration    = 5000,
    })

    CreateThread(function()
        while isSpectating do
            if IsControlJustPressed(0, 174) then  -- LEFT arrow
                specIndex = ((specIndex - 2) % #specTargets) + 1
                lib.notify({title='Watching: '..specTargets[specIndex].name, type='inform', duration=2000})
            elseif IsControlJustPressed(0, 175) then  -- RIGHT arrow
                specIndex = (specIndex % #specTargets) + 1
                lib.notify({title='Watching: '..specTargets[specIndex].name, type='inform', duration=2000})
            end

            if IsControlJustPressed(0, 177) then  -- Backspace
                StopSpectate(); break
            end

            UpdateSpecCam()
            Wait(0)
        end
    end)
end)

-- Server pushes updated lap/pos data periodically
RegisterNetEvent('fcrp_f1:cl:specTargetsUpdate', function(targets)
    if not isSpectating or not targets then return end
    for i, nt in ipairs(targets) do
        if specTargets[i] then
            specTargets[i].lap = nt.lap
            specTargets[i].pos = nt.pos
        end
    end
end)

-- Auto-exit spectator when race ends
RegisterNetEvent('fcrp_f1:cl:raceEnded', function()
    if isSpectating then
        SetTimeout(3000, StopSpectate)
    end
end)

-- ============================================================
-- PLAYER NEEDS MAINTENANCE DURING RACE
-- ============================================================
CreateThread(function()
    while true do
        local interval = (Config.RaceNeeds and Config.RaceNeeds.intervalSecs or 30) * 1000
        Wait(interval)
        if isRacing and Config.RaceNeeds and Config.RaceNeeds.enabled then
            TriggerServerEvent('fcrp_f1:sv:maintainNeeds')
        end
    end
end)

-- ============================================================
-- KEYBINDS
-- ============================================================
-- BUG FIX #4: F5 keybind moved to client/nui_callbacks.lua as
-- 'fcrp_f1_nui' to avoid double-open with the new NUI dashboard.
-- The old command below is kept as a non-bound fallback only.
-- RegisterKeyMapping('fcrp_f1_menu', 'Open F1 Race Manager', 'keyboard', 'F5')
RegisterCommand('fcrp_f1_menu', function()
    TriggerServerEvent('fcrp_f1:sv:requestMenuOpen')
end, false)

DBG('Client v3.0 loaded.')
