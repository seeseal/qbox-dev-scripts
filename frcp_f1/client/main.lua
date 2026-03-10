-- ============================================================
--  FLAME CITY GP — client/main.lua  v1.2
-- ============================================================

local myRaceCar   = nil
local isRacing    = false
local currentLap  = 1
local currentCP   = 1
local currentBlip = nil

-- Leaderboard + gap data pushed from server
local leaderboardData = {}
local myGapToLeader   = nil   -- string e.g. "+4.2s" or "LEADER"

-- DRS state
local drsOpen         = false
local drsZoneIndex    = 0     -- which zone we're currently in (0 = none)

-- Engine damage state
local engineStatus    = "OK"  -- "OK" | "WARNING" | "DAMAGED" | "CRITICAL"

-- Race director camera
local directorCam     = nil
local directorTarget  = nil   -- vehicle entity being watched

-- Formation lap
local formationActive = false
local formationDone   = false

-- ============================================================
-- 1. ORGANISER PANEL
-- ============================================================
-- pendingGrid display labels, updated when slots are assigned
local slotLabels = {}

RegisterNetEvent('frcp_f1:client:openOrganizerMenu', function(playerList)
    -- Build quick player lookup: id -> name
    local playerMap = {}
    for _, p in ipairs(playerList) do
        playerMap[p.id] = p.name
    end

    -- Slot rows: show current assignment or "Empty"
    local totalSlots = #Config.GridSpots
    local slotOptions = {}
    for i = 1, totalSlots do
        local assigned = slotLabels[i]
        local desc, iconColor
        if assigned then
            desc      = '✅  ' .. assigned
            iconColor = '#00cc66'
        else
            desc      = 'Tap to assign a driver'
            iconColor = '#888888'
        end
        local suffix = (i == 1) and ' — Pole' or ''
        table.insert(slotOptions, {
            title       = string.format('P%d%s', i, suffix),
            description = desc,
            icon        = 'user',
            iconColor   = iconColor,
            onSelect    = function() AssignSlot(i, playerMap) end,
        })
    end

    -- Merge all options
    local options = {}

    -- ── STEP 1 ────────────────────────────────────────────
    table.insert(options, {
        title    = 'STEP 1  ·  GRID',
        disabled = true,
        icon     = 'table-cells',
        iconColor = '#e10600',
    })
    for _, o in ipairs(slotOptions) do table.insert(options, o) end
    table.insert(options, {
        title     = 'Clear All Slots',
        icon      = 'rotate-left',
        iconColor = '#cc4444',
        onSelect  = function()
            slotLabels = {}
            TriggerServerEvent('frcp_f1:server:clearGrid')
        end,
    })
    table.insert(options, {
        title     = 'Prepare Grid',
        description = 'Spawn cars and freeze drivers on their grid spots',
        icon      = 'flag',
        iconColor = '#ffcc00',
        onSelect  = function() TriggerServerEvent('frcp_f1:server:setupGrid') end,
    })

    -- ── STEP 2 ────────────────────────────────────────────
    table.insert(options, {
        title    = 'STEP 2  ·  FORMATION LAP',
        disabled = true,
        icon     = 'shield-halved',
        iconColor = '#e10600',
    })
    table.insert(options, {
        title     = 'Deploy Safety Car',
        description = 'SC leads drivers from grid to start — you control when to go',
        icon      = 'car',
        iconColor = '#ffaa00',
        onSelect  = function() TriggerServerEvent('frcp_f1:server:deploySafetyCar') end,
    })

    -- ── STEP 3 ────────────────────────────────────────────
    table.insert(options, {
        title    = 'STEP 3  ·  RACE START',
        disabled = true,
        icon     = 'traffic-light',
        iconColor = '#e10600',
    })
    table.insert(options, {
        title     = 'START RACE',
        description = 'Despawn SC · Freeze grid · Lights out',
        icon      = 'flag-checkered',
        iconColor = '#00cc44',
        onSelect  = function() TriggerServerEvent('frcp_f1:server:startGlobalRace') end,
    })

    -- ── TOOLS ─────────────────────────────────────────────
    table.insert(options, {
        title    = 'TOOLS',
        disabled = true,
        icon     = 'wrench',
        iconColor = '#888888',
    })
    table.insert(options, {
        title     = 'Race Director Camera',
        description = 'Cinematic overhead view of any driver',
        icon      = 'video',
        iconColor = '#88aaff',
        onSelect  = function() OpenDirectorCamMenu() end,
    })
    table.insert(options, {
        title     = 'Force End / Reset',
        description = 'Emergency stop — teleports everyone and resets all state',
        icon      = 'circle-xmark',
        iconColor = '#ff4444',
        onSelect  = function() TriggerServerEvent('frcp_f1:server:forceEnd') end,
    })

    lib.registerContext({ id = 'f1_organiser', title = '  FLAME CITY GP  ·  Race Control', options = options })
    lib.showContext('f1_organiser')
end)

-- Update slot label locally after successful assign
RegisterNetEvent('frcp_f1:client:slotAssigned', function(slot, name)
    slotLabels[slot] = string.format('ID %s — %s', slot, name)
end)

function AssignSlot(slot, playerMap)
    local result = lib.inputDialog('Assign P' .. slot, {
        { type = 'number', label = 'Player Server ID', placeholder = 'e.g. 5', required = true, min = 1 }
    })
    if not result or not result[1] then return end
    local targetId = tonumber(result[1])
    if not targetId then lib.notify({ title = 'Invalid ID', type = 'error' }); return end
    TriggerServerEvent('frcp_f1:server:assignSlot', slot, targetId)
end

-- ============================================================
-- 2. RACE DIRECTOR CAMERA
--    Organiser picks a racer by server ID, a cinematic camera
--    locks on above-behind their car and tracks smoothly.
-- ============================================================
function OpenDirectorCamMenu()
    local result = lib.inputDialog('Race Director Camera', {
        { type = 'number', label = 'Target Player Server ID', placeholder = 'e.g. 3', required = true, min = 1 }
    })
    if not result or not result[1] then return end
    TriggerServerEvent('frcp_f1:server:getVehicleForCam', tonumber(result[1]))
end

RegisterNetEvent('frcp_f1:client:attachDirectorCam', function(netId)
    -- Stop any existing director cam
    StopDirectorCam()

    if not NetworkDoesNetworkIdExist(netId) then
        lib.notify({ title = 'Cam Error', description = 'Vehicle not found', type = 'error' })
        return
    end

    local veh = NetToVeh(netId)
    if not DoesEntityExist(veh) then
        lib.notify({ title = 'Cam Error', description = 'Vehicle entity missing', type = 'error' })
        return
    end

    directorTarget = veh

    directorCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamActive(directorCam, true)
    RenderScriptCams(true, true, 500, true, false)

    lib.notify({ title = '📷 Director Cam ON', description = 'Press ~INPUT_CELLPHONE_CANCEL~ to exit', type = 'inform' })

    CreateThread(function()
        while directorCam and IsCamActive(directorCam) do
            if not DoesEntityExist(directorTarget) then break end

            -- Exit on Backspace / B
            if IsControlJustPressed(0, 194) or IsControlJustPressed(0, 177) then break end

            local pos     = GetEntityCoords(directorTarget)
            local heading = GetEntityHeading(directorTarget)
            local rad     = math.rad(heading)

            -- Position: 8m behind, 4m above
            local camX = pos.x + math.sin(rad) * 8.0
            local camY = pos.y + math.cos(rad) * 8.0  -- NOTE: intentional, looks behind
            local camZ = pos.z + 4.0

            SetCamCoord(directorCam, camX, camY, camZ)
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
        directorCam    = nil
        directorTarget = nil
    end
end

-- ============================================================
-- 3. PHYSICS (base handling, applied on spawn)
-- ============================================================
local BASE_DRIVE_FORCE = 1.0
local BASE_TOP_SPEED   = 60.0

local function ApplyF1Handling(veh)
    SetVehicleModKit(veh, 0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce',        BASE_DRIVE_FORCE)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia',             1.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveBiasFront',           0.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fLowSpeedTractionLossMult', 2.8)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDragCoeff',         25.0)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax',         4.8)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMin',         2.6)
    ModifyVehicleTopSpeed(veh, BASE_TOP_SPEED)
end

-- ============================================================
-- 4. DRS SYSTEM
--    Per-frame zone detection. When inside a DRS zone:
--    - boosts fInitialDriveForce and top speed
--    - shows "DRS OPEN" in green via lib.showTextUI
-- ============================================================
local function UpdateDRS(coords)
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end
    if not Config.DRSZones or #Config.DRSZones == 0 then return end

    local wasOpen = drsOpen
    local newOpen = false
    local newZone = 0

    for i, zone in ipairs(Config.DRSZones) do
        local distEntry = #(coords - zone.entry)
        local distExit  = #(coords - zone.exit)
        -- Open if within entry radius and haven't reached the exit yet
        -- (exit radius check prevents staying open after passing the zone)
        if distEntry < zone.radius and distExit > zone.radius then
            newOpen = true
            newZone = i
            break
        end
    end

    if newOpen ~= wasOpen or newZone ~= drsZoneIndex then
        drsOpen      = newOpen
        drsZoneIndex = newZone

        local driveForce = BASE_DRIVE_FORCE
        local topSpeed   = BASE_TOP_SPEED

        if drsOpen then
            driveForce = driveForce + Config.DRS.driveForceBoost
            topSpeed   = topSpeed   + Config.DRS.topSpeedBoost
            lib.showTextUI("⚡ DRS OPEN", {
                position = "bottom-center",
                style    = { backgroundColor = '#007a00', color = 'white',
                             fontSize = '18px', fontWeight = 'bold',
                             padding = '6px 20px', letterSpacing = '3px' }
            })
        else
            lib.hideTextUI()
        end

        -- Apply to engine damage-adjusted force
        local dmgMult = GetEngineDamageMult()
        SetVehicleHandlingFloat(myRaceCar, 'CHandlingData', 'fInitialDriveForce', driveForce * dmgMult)
        ModifyVehicleTopSpeed(myRaceCar, topSpeed)
    end
end

-- ============================================================
-- 5. ENGINE DAMAGE
--    Maps engine health → drive force multiplier.
--    Updates every frame, shows tiered HUD warning.
-- ============================================================
function GetEngineDamageMult()
    if engineStatus == "CRITICAL" then return 0.35
    elseif engineStatus == "DAMAGED" then return 0.60
    elseif engineStatus == "WARNING" then return 0.85
    else return 1.0 end
end

local engineWarnShown = ""

local function UpdateEngineDamage()
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end

    local health   = GetVehicleEngineHealth(myRaceCar)
    local newStatus

    if health <= Config.EngineHealth.critical then
        newStatus = "CRITICAL"
    elseif health <= Config.EngineHealth.damaged then
        newStatus = "DAMAGED"
    elseif health <= Config.EngineHealth.warning then
        newStatus = "WARNING"
    else
        newStatus = "OK"
    end

    if newStatus ~= engineStatus then
        engineStatus = newStatus

        -- Reapply drive force with new multiplier (DRS boost preserved)
        local boost = drsOpen and Config.DRS.driveForceBoost or 0.0
        SetVehicleHandlingFloat(myRaceCar, 'CHandlingData', 'fInitialDriveForce',
            (BASE_DRIVE_FORCE + boost) * GetEngineDamageMult())

        if newStatus == "WARNING" then
            lib.notify({ title = '⚠️ ENGINE WARNING', description = 'Power reduced to 85%', type = 'warning' })
        elseif newStatus == "DAMAGED" then
            lib.notify({ title = '🔴 ENGINE DAMAGED', description = 'Power reduced to 60%', type = 'error' })
        elseif newStatus == "CRITICAL" then
            lib.notify({ title = '💀 ENGINE CRITICAL', description = 'Power at 35% — pit or retire', type = 'error' })
        end
    end
end

-- ============================================================
-- 6. FORZA RACING LINE
-- ============================================================
local function DrawRacingLine(pCoords, target)
    if #(pCoords - target) > 120.0 then return end
    local segments = 12
    local heading  = math.deg(math.atan(target.x - pCoords.x, target.y - pCoords.y)) + 180.0
    for i = 1, segments do
        local frac  = i / segments
        local x     = pCoords.x + (target.x - pCoords.x) * frac
        local y     = pCoords.y + (target.y - pCoords.y) * frac
        local found, gz = GetGroundZFor_3dCoord(x, y, pCoords.z + 10.0, false)
        local z     = found and (gz - 0.1) or (pCoords.z - 0.3)
        local alpha = math.floor(220 * (1.0 - frac * 0.6))
        DrawMarker(24, x, y, z, 0.0, 0.0, 0.0, 0.0, 0.0, heading,
            0.9, 0.9, 0.9, 0, 210, 255, alpha, false, false, 2, nil, nil, false)
    end
end

-- ============================================================
-- 7. HUD — personal lap counter + engine status + gap
-- ============================================================
local function DrawRaceHUD(lap, maxLaps, cp, totalCPs)
    -- Lap counter
    SetTextFont(4); SetTextScale(0.0, 0.50); SetTextColour(255,255,255,255)
    SetTextOutline(); SetTextEntry("STRING")
    AddTextComponentString(string.format("LAP  %d / %d", lap, maxLaps))
    DrawText(0.82, 0.86)

    -- Checkpoint
    SetTextFont(0); SetTextScale(0.0, 0.30); SetTextColour(160,210,255,200)
    SetTextOutline(); SetTextEntry("STRING")
    AddTextComponentString(string.format("CP  %d / %d", cp, totalCPs))
    DrawText(0.82, 0.898)

    -- Gap to leader
    if myGapToLeader then
        local r, g, b = 255, 255, 255
        if myGapToLeader == "LEADER" then r,g,b = 255,215,0
        elseif myGapToLeader:sub(1,1) == "+" then r,g,b = 255,100,100 end
        SetTextFont(4); SetTextScale(0.0, 0.34); SetTextColour(r,g,b,230)
        SetTextOutline(); SetTextEntry("STRING")
        AddTextComponentString(myGapToLeader)
        DrawText(0.82, 0.928)
    end

    -- Engine warning strip
    if engineStatus ~= "OK" then
        local colours = {
            WARNING  = {255, 200,  0, 220},
            DAMAGED  = {255, 100,  0, 220},
            CRITICAL = {255,  30, 30, 255},
        }
        local c = colours[engineStatus] or {255,255,255,200}
        SetTextFont(4); SetTextScale(0.0, 0.28); SetTextColour(c[1],c[2],c[3],c[4])
        SetTextOutline(); SetTextEntry("STRING")
        AddTextComponentString("ENGINE " .. engineStatus)
        DrawText(0.82, 0.958)
    end
end

-- ============================================================
-- 8. LEADERBOARD HUD
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

    SetTextFont(4); SetTextScale(0.0, 0.28); SetTextColour(255,200,0,255)
    SetTextOutline(); SetTextEntry("STRING")
    AddTextComponentString("FLAME CITY GP")
    DrawText(startX, startY)

    for i, entry in ipairs(leaderboardData) do
        local y = startY + (i * lineH) + 0.01
        local label
        if entry.finished and entry.pos then
            label = string.format("P%d  %s  ✓%s", entry.pos, entry.name, entry.time or "")
        elseif entry.dq then
            label = string.format("DQ  %s", entry.name)
        else
            label = string.format("P%d  %s  L%d·CP%d", i, entry.name, entry.lap or 1, entry.cp or 1)
        end
        local r,g,b = 220,220,220
        if entry.dq then r,g,b=255,60,60
        elseif i==1 and entry.finished then r,g,b=255,215,0
        elseif i==2 and entry.finished then r,g,b=192,192,192
        elseif i==3 and entry.finished then r,g,b=205,127,50 end
        SetTextFont(0); SetTextScale(0.0, 0.25); SetTextColour(r,g,b,220)
        SetTextOutline(); SetTextEntry("STRING")
        AddTextComponentString(label)
        DrawText(startX, y)
    end
end

-- ============================================================
-- 9. GPS
-- ============================================================
local function UpdateRaceWaypoint(coords)
    if currentBlip and DoesBlipExist(currentBlip) then RemoveBlip(currentBlip) end
    currentBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(currentBlip, 38); SetBlipColour(currentBlip, 5)
    SetBlipScale(currentBlip, 0.85); SetBlipAsShortRange(currentBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Next Checkpoint")
    EndTextCommandSetBlipName(currentBlip)
    SetNewWaypoint(coords.x, coords.y)
end

local function ClearWaypoint()
    if currentBlip and DoesBlipExist(currentBlip) then RemoveBlip(currentBlip) end
    currentBlip = nil
    SetWaypointOff()
end

-- ============================================================
-- 10. F1 STARTING LIGHTS
-- ============================================================
local countdownDone = false

local function F1Countdown()
    countdownDone = false
    CreateThread(function()
        local lights = {
            {m="● ○ ○ ○ ○", c="#7a0000"}, {m="● ● ○ ○ ○", c="#a00000"},
            {m="● ● ● ○ ○", c="#c80000"}, {m="● ● ● ● ○", c="#e00000"},
            {m="● ● ● ● ●", c="#ff0000"},
        }
        for _, light in ipairs(lights) do
            lib.showTextUI(light.m, {
                position="top-center",
                style={backgroundColor=light.c, color='white',
                       fontSize='48px', fontWeight='bold',
                       padding='10px 28px', letterSpacing='6px'}
            })
            PlaySoundFrontend(-1, "CHECKPOINT_NORMAL", "HUD_MINI_GAME_SOUNDSET", 1)
            Wait(900)
        end
        lib.hideTextUI()
        Wait(math.random(400, 900))
        lib.showTextUI("GO GO GO!", {
            position="top-center",
            style={backgroundColor="#00cc44", color='white',
                   fontSize='54px', fontWeight='bold', padding='10px 28px'}
        })
        PlaySoundFrontend(-1, "CHECKPOINT_PERFECT", "HUD_MINI_GAME_SOUNDSET", 1)
        Wait(1200)
        lib.hideTextUI()
        countdownDone = true
    end)
    while not countdownDone do Wait(100) end
end

-- ============================================================
-- 11. FORMATION LAP
--     The organiser's client spawns the safety car and drives it
--     via task AI around the circuit. All other clients see it
--     because it's a networked entity. Racers follow at capped speed.
-- ============================================================
-- 11. FORMATION LAP + NPC FILLERS
-- ============================================================

local safetyCar       = nil   -- SC entity (organiser client only)
local safetyCarBlip   = nil
local safetyCarActive = false
local npcVehicles     = {}    -- { {veh=entity, ped=entity}, ... } (organiser client)

-- ── NPC GRID FILLERS ─────────────────────────────────────────────────────
-- Server sends which slots are empty; organiser spawns NPC cars there.
-- Bot drivers: scrambled names + team livery colors
-- Primary = body, Secondary = trim  (GTA colour index 0-159)
local BOT_DRIVERS = {
    { name="Verstappin",  primary=142, secondary=82  },  -- Red Bul  (dk.blue/yellow)
    { name="Hamiltun",    primary=64,  secondary=12  },  -- Mercedez (cyan/black)
    { name="Leclairc",    primary=4,   secondary=82  },  -- Ferarri  (red/yellow)
    { name="Norriss",     primary=111, secondary=12  },  -- Mclaaren (orange/black)
    { name="Saainz",      primary=141, secondary=27  },  -- Willians (blue/white)
    { name="Russull",     primary=64,  secondary=27  },  -- Mercedez 2 (cyan/white)
    { name="Alonzo",      primary=141, secondary=156 },  -- Alpyne   (blue/pink)
    { name="Piastrii",    primary=111, secondary=17  },  -- Mclaaren 2 (orange/gold)
    { name="Cheeco",      primary=142, secondary=27  },  -- RB       (dk.blue/white)
    { name="Hulkenburg",  primary=27,  secondary=4   },  -- Haaz     (white/red)
}
local function RandomBotDriver(usedNames)
    local pool = {}
    for _, d in ipairs(BOT_DRIVERS) do
        if not usedNames[d.name] then table.insert(pool, d) end
    end
    if #pool == 0 then
        return { name="Driver"..math.random(100,999), primary=27, secondary=4 }
    end
    return pool[math.random(1, #pool)]
end

RegisterNetEvent('frcp_f1:client:spawnNPCs', function(emptySlots)
    local model = Config.F1CarModel
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    local pedModel = `a_m_m_skater_01`
    RequestModel(pedModel)
    while not HasModelLoaded(pedModel) do Wait(0) end

    npcVehicles = {}
    local usedNames = {}
    local registrations = {}  -- send to server: { {id="BOT_1", name="BOT_Norris"}, ... }

    for i, spot in ipairs(emptySlots) do
        local driver  = RandomBotDriver(usedNames)
        usedNames[driver.name] = true
        local botName = "BOT_" .. driver.name
        local botId   = "BOT_" .. i  -- stable key used server-side

        local veh = CreateVehicle(model, spot.x, spot.y, spot.z, spot.w, true, false)
        SetEntityAsMissionEntity(veh, true, true)
        ApplyF1Handling(veh)
        SetVehicleEngineOn(veh, false, true, false)
        FreezeEntityPosition(veh, true)
        SetVehicleModKit(veh, 0)
        -- Apply team livery colors
        SetVehicleColours(veh, driver.primary, driver.secondary)

        local ped = CreatePedInsideVehicle(veh, 26, pedModel, -1, true, false)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
        SetPedCanBeKnockedOffVehicle(ped, 1)

        table.insert(npcVehicles, { veh = veh, ped = ped, name = botName, id = botId })
        table.insert(registrations, { id = botId, name = botName })
    end

    -- Register all bots in the server's racers table
    TriggerServerEvent('frcp_f1:server:registerNPCs', registrations)

    lib.notify({ title = string.format('👤 %d NPC driver(s) added', #emptySlots), type = 'inform' })
end)

-- Called when formation lap ends — stop NPCs, TP back to grid, refreeze
RegisterNetEvent('frcp_f1:client:returnNPCsToGrid', function(emptySlots)
    formationActive = false  -- stops any running NPC drive threads
    for i, npc in ipairs(npcVehicles) do
        if DoesEntityExist(npc.veh) then
            local spot = emptySlots[i]
            if spot then
                -- Stop driving
                if DoesEntityExist(npc.ped) then ClearPedTasks(npc.ped) end
                SetVehicleMaxSpeed(npc.veh, 0.0)
                -- TP back to grid spot
                SetEntityCoords(npc.veh, spot.x, spot.y, spot.z, false, false, false, false)
                SetEntityHeading(npc.veh, spot.w)
                FreezeEntityPosition(npc.veh, true)
                SetVehicleEngineOn(npc.veh, false, true, false)
            end
        end
    end
end)

-- Despawn all NPC vehicles (called on forceEnd / cleanup)
RegisterNetEvent('frcp_f1:client:cleanupNPCs', function()
    for _, npc in ipairs(npcVehicles) do
        if DoesEntityExist(npc.ped) then
            ClearPedTasks(npc.ped)
            DeleteEntity(npc.ped)
        end
        if DoesEntityExist(npc.veh) then
            SetVehicleEngineOn(npc.veh, false, true, false)
            DeleteEntity(npc.veh)
        end
    end
    npcVehicles = {}
end)

-- ── SAFETY CAR ───────────────────────────────────────────────────────────
-- Route: safetyCarSpot → CP1 → CP2 → ... → CPn → back to safetyCarSpot
-- On arrival back at start: fires server:formationLapDone (once only)
RegisterNetEvent('frcp_f1:client:spawnSafetyCar', function()
    local cfg      = Config.FormationLap
    local maxSpeed = cfg.maxSpeed / 3.6
    local startSpot = cfg.safetyCarSpot

    -- Spawn SC
    local model = cfg.safetyCarModel
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    safetyCar = CreateVehicle(model,
        startSpot.x, startSpot.y, startSpot.z, startSpot.w, true, false)
    SetEntityAsMissionEntity(safetyCar, true, true)
    SetVehicleColours(safetyCar, 12, 12)
    SetVehicleNumberPlateText(safetyCar, "SAFETY")
    SetVehicleEngineOn(safetyCar, true, true, false)
    SetVehicleMaxSpeed(safetyCar, maxSpeed)

    -- Blip
    safetyCarBlip = AddBlipForEntity(safetyCar)
    SetBlipSprite(safetyCarBlip, 225)
    SetBlipColour(safetyCarBlip, 17)  -- orange
    SetBlipScale(safetyCarBlip, 1.1)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Safety Car")
    EndTextCommandSetBlipName(safetyCarBlip)

    -- Spawn driver ped
    local driverModel = `s_m_m_security_01`
    RequestModel(driverModel)
    while not HasModelLoaded(driverModel) do Wait(0) end
    local driver = CreatePedInsideVehicle(safetyCar, 26, driverModel, -1, true, false)
    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedKeepTask(driver, true)

    safetyCarActive = true

    -- Build route: all checkpoints in order, then return to start spot
    local route = {}
    for _, cp in ipairs(Config.Checkpoints) do
        table.insert(route, vector3(cp.x, cp.y, cp.z))
    end
    -- Final waypoint: back to the safety car start spot
    table.insert(route, vector3(startSpot.x, startSpot.y, startSpot.z))

    CreateThread(function()
        for idx, dest in ipairs(route) do
            if not safetyCarActive then break end

            TaskVehicleDriveToCoordLongrange(driver, safetyCar,
                dest.x, dest.y, dest.z,
                maxSpeed,
                786603,  -- normal driving + avoid obstacles
                5.0)

            -- Wait until close enough to this waypoint
            while safetyCarActive do
                if not DoesEntityExist(safetyCar) then safetyCarActive = false; break end
                local pos = GetEntityCoords(safetyCar)
                if #(pos - dest) < 18.0 then break end
                Wait(300)
            end
        end

        -- SC finished the full route — tell server to TP everyone back and start
        if safetyCarActive then
            TriggerServerEvent('frcp_f1:server:formationLapDone')
        end
    end)

    lib.notify({ title = '🟡 Safety Car deployed', description = 'Follow the SC around the circuit', type = 'inform' })
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

-- ── FORMATION LAP STATE FOR RACERS ───────────────────────────────────────
RegisterNetEvent('frcp_f1:client:beginFormationLap', function()
    formationActive = true
    local maxMs = Config.FormationLap.maxSpeed / 3.6

    -- Unfreeze and cap human racer
    if myRaceCar and DoesEntityExist(myRaceCar) then
        FreezeEntityPosition(myRaceCar, false)
        SetVehicleEngineOn(myRaceCar, true, false, false)
        SetVehicleDoorsLocked(myRaceCar, 1)
        SetVehicleMaxSpeed(myRaceCar, maxMs)
    end

    -- Drive NPCs through the circuit (same route as SC: all CPs then back to start)
    if #npcVehicles > 0 then
        local route = {}
        for _, cp in ipairs(Config.Checkpoints) do
            table.insert(route, vector3(cp.x, cp.y, cp.z))
        end
        local startSpot = Config.FormationLap.safetyCarSpot
        table.insert(route, vector3(startSpot.x, startSpot.y, startSpot.z))

        for _, npc in ipairs(npcVehicles) do
            if DoesEntityExist(npc.veh) and DoesEntityExist(npc.ped) then
                FreezeEntityPosition(npc.veh, false)
                SetVehicleEngineOn(npc.veh, true, false, false)
                SetVehicleMaxSpeed(npc.veh, maxMs * 0.92) -- slightly slower so SC leads

                local ped = npc.ped
                local veh = npc.veh
                CreateThread(function()
                    for _, dest in ipairs(route) do
                        if not formationActive then break end
                        TaskVehicleDriveToCoordLongrange(ped, veh,
                            dest.x, dest.y, dest.z,
                            maxMs * 0.92,
                            786603,
                            5.0)
                        while formationActive do
                            if not DoesEntityExist(veh) then break end
                            local pos = GetEntityCoords(veh)
                            if #(pos - dest) < 18.0 then break end
                            Wait(300)
                        end
                    end
                    -- Clear task when done
                    if DoesEntityExist(ped) then ClearPedTasks(ped) end
                end)
            end
        end
    end

    if myRaceCar then
        lib.showTextUI("🟡  FORMATION LAP — Follow the safety car", {
            position = "top-center",
            style = { backgroundColor = "#aa7700", color = 'white',
                      fontSize = '18px', fontWeight = 'bold', padding = '8px 22px' }
        })
    end
end)

-- Called by server after SC finishes route: TP this player's car back to grid spot
RegisterNetEvent('frcp_f1:client:returnToGrid', function(spot)
    formationActive = false
    lib.hideTextUI()
    if not myRaceCar or not DoesEntityExist(myRaceCar) then return end

    -- Teleport car back to assigned grid spot
    SetVehicleMaxSpeed(myRaceCar, 0.0)   -- remove speed cap
    SetEntityCoords(myRaceCar, spot.x, spot.y, spot.z, false, false, false, false)
    SetEntityHeading(myRaceCar, spot.w)
    FreezeEntityPosition(myRaceCar, true)
    SetVehicleEngineOn(myRaceCar, false, true, false)

    -- RPM lock while waiting for lights
    CreateThread(function()
        while myRaceCar and DoesEntityExist(myRaceCar) and not isRacing do
            SetVehicleCurrentRpm(myRaceCar, 0.1)
            Wait(0)
        end
    end)

    lib.notify({ title = '🏁 Back on the grid', description = 'Lights out in a moment...', type = 'inform' })
end)

-- Legacy stub — kept so old calls don't error
RegisterNetEvent('frcp_f1:client:endFormationLap', function()
    formationActive = false
    lib.hideTextUI()
    if myRaceCar and DoesEntityExist(myRaceCar) then
        SetVehicleMaxSpeed(myRaceCar, 0.0)
        FreezeEntityPosition(myRaceCar, true)
        SetVehicleEngineOn(myRaceCar, false, true, false)
    end
end)

-- ============================================================
-- 12. RESULTS  (lib.notify — NUI removed, was unreliable)
-- ============================================================
-- Results are shown via lib.notify broadcast from server.
-- Stub handlers kept so old server events don't throw errors.
RegisterNetEvent('frcp_f1:client:showResults', function() end)
RegisterNetEvent('frcp_f1:client:hideResults', function() end)

-- ============================================================
-- 13. SPAWN & CLEANUP
-- ============================================================
RegisterNetEvent('frcp_f1:client:spawnYourCar', function(spot)
    local model = Config.F1CarModel
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    myRaceCar = CreateVehicle(model, spot.x, spot.y, spot.z, spot.w, true, false)
    ApplyF1Handling(myRaceCar)

    local plate = GetVehicleNumberPlateText(myRaceCar)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    SetPedIntoVehicle(cache.ped, myRaceCar, -1)
    FreezeEntityPosition(myRaceCar, true)
    SetVehicleDoorsLocked(myRaceCar, 4)
    SetVehicleEngineOn(myRaceCar, false, true, false)

    -- Reset systems
    drsOpen      = false
    engineStatus = "OK"

    -- RPM LOCK: While the car is frozen on the grid (engine off),
    -- clamp RPM to idle (0.1) so the car doesn't rev or make noise.
    -- Once isRacing becomes true the thread exits and normal RPM applies.
    CreateThread(function()
        while myRaceCar and DoesEntityExist(myRaceCar) and not isRacing do
            SetVehicleCurrentRpm(myRaceCar, 0.1)
            Wait(0)
        end
    end)
end)

RegisterNetEvent('frcp_f1:client:cleanupCars', function()
    ClearWaypoint()
    StopDirectorCam()
    lib.hideTextUI()
    isRacing        = false
    formationActive = false
    currentLap      = 1
    currentCP       = 1
    leaderboardData = {}
    myGapToLeader   = nil
    drsOpen         = false
    engineStatus    = "OK"
    if myRaceCar and DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
    myRaceCar = nil
end)

-- ============================================================
-- 14. POST-RACE TELEPORT  (delayed — called after results screen)
-- ============================================================
RegisterNetEvent('frcp_f1:client:teleportPostRace', function()
    ClearWaypoint()
    isRacing = false
    lib.hideTextUI()
    if myRaceCar and DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
    myRaceCar = nil
    SetEntityCoords(cache.ped,
        Config.PostRaceLocation.x, Config.PostRaceLocation.y, Config.PostRaceLocation.z,
        false, false, false, false)
end)

-- ============================================================
-- 15. PERSISTENT DRAW THREAD (leaderboard always visible)
-- ============================================================
CreateThread(function()
    while true do
        DrawLeaderboard()
        Wait(0)
    end
end)

-- ============================================================
-- 16. MAIN RACE LOOP
-- ============================================================
RegisterNetEvent('frcp_f1:client:startRace', function()
    if not myRaceCar then return end
    if isRacing then return end

    currentLap   = 1
    currentCP    = 1
    formationActive = false

    if not Config.Checkpoints or #Config.Checkpoints == 0 then
        lib.notify({title='Race Error', description='No checkpoints in Config!', type='error'})
        return
    end

    F1Countdown()

    FreezeEntityPosition(myRaceCar, false)
    SetVehicleEngineOn(myRaceCar, true, false, false)
    SetVehicleDoorsLocked(myRaceCar, 1)
    isRacing = true

    TriggerServerEvent('frcp_f1:server:raceClockStart')
    UpdateRaceWaypoint(Config.Checkpoints[currentCP])

    -- ── NPC RACE LOOP ────────────────────────────────────────
    -- Each NPC gets its own thread driving the full race distance.
    -- Speed varies slightly per NPC so they spread out naturally.
    -- They park back at their grid spot after finishing.
    for npcIdx, npc in ipairs(npcVehicles) do
        if DoesEntityExist(npc.veh) and DoesEntityExist(npc.ped) then
            FreezeEntityPosition(npc.veh, false)
            SetVehicleEngineOn(npc.veh, true, false, false)
            SetVehicleMaxSpeed(npc.veh, 0.0)  -- remove cap, let handling define top speed

            local ped = npc.ped
            local veh = npc.veh
            -- Same spec as player. Tiny variance so bots spread out naturally.
            local paceVariance = 0.96 + (math.random() * 0.10)  -- 0.96–1.06
            local npcTopSpeed  = (BASE_TOP_SPEED * paceVariance) / 3.6

            local botId   = npc.id
            CreateThread(function()
                local botLap = 1
                local botCP  = 1

                -- Drive every lap
                for lap = 1, Config.MaxLaps do
                    botLap = lap
                    -- Drive every checkpoint in this lap
                    for cpIdx, cp in ipairs(Config.Checkpoints) do
                        botCP = cpIdx
                        if not DoesEntityExist(veh) then return end

                        TaskVehicleDriveToCoordLongrange(ped, veh,
                            cp.x, cp.y, cp.z,
                            npcTopSpeed,
                            6,       -- aggressive: full speed, ignores traffic rules
                            4.0)

                        -- Wait until close to checkpoint, then report progress
                        while true do
                            if not DoesEntityExist(veh) then return end
                            local pos = GetEntityCoords(veh)
                            if #(pos - vector3(cp.x, cp.y, cp.z)) < 16.0 then break end
                            Wait(400)
                        end

                        -- Report checkpoint to server so leaderboard updates
                        TriggerServerEvent('frcp_f1:server:npcProgress', botId, botLap, botCP)
                    end
                end

                -- Report finish
                TriggerServerEvent('frcp_f1:server:npcFinish', botId)

                -- Drive to post-race area and park
                if DoesEntityExist(veh) then
                    local dest = Config.PostRaceLocation
                    TaskVehicleDriveToCoordLongrange(ped, veh,
                        dest.x, dest.y, dest.z,
                        npcTopSpeed * 0.5,
                        786603, 3.0)
                    Wait(8000)
                    if DoesEntityExist(ped) then ClearPedTasks(ped) end
                    if DoesEntityExist(veh) then FreezeEntityPosition(veh, true) end
                end
            end)
        end
    end
    -- ── END NPC RACE LOOP ────────────────────────────────────

    CreateThread(function()
        while isRacing do
            local ped    = cache.ped
            local coords = GetEntityCoords(ped)

            -- ── DQ: left vehicle ────────────────────────────────────
            if not IsPedInVehicle(ped, myRaceCar, false) then
                isRacing = false
                ClearWaypoint()
                lib.hideTextUI()
                if DoesEntityExist(myRaceCar) then DeleteEntity(myRaceCar) end
                myRaceCar = nil
                TriggerServerEvent('frcp_f1:server:dqPlayer', "Left vehicle")
                lib.notify({title='DISQUALIFIED', description='You left the vehicle!', type='error'})
                break
            end

            local target = Config.Checkpoints[currentCP]
            if not target then isRacing = false; break end

            -- ── Per-frame systems ────────────────────────────────────
            UpdateDRS(coords)
            UpdateEngineDamage()
            DrawRaceHUD(currentLap, Config.MaxLaps, currentCP, #Config.Checkpoints)
            DrawRacingLine(coords, target)

            -- ── Checkpoint markers ───────────────────────────────────
            if #(coords - target) < 200.0 then
                if currentCP == 1 then
                    DrawMarker(4, target.x, target.y, target.z,
                        0,0,0, 0,0,0, 5,5,5, 255,255,255,200, false,false,2,nil,nil,false)
                    DrawMarker(1, target.x, target.y, target.z+0.05,
                        0,0,0, 0,0,0, 7,7,0.4, 255,40,40,100, false,false,2,nil,nil,false)
                else
                    DrawMarker(1, target.x, target.y, target.z+0.05,
                        0,0,0, 0,0,0, 5,5,1.2, 0,180,255,160, false,false,2,nil,nil,false)
                end
            end

            -- ── Checkpoint trigger ───────────────────────────────────
            if #(coords - target) < 15.0 then
                PlaySoundFrontend(-1, "CHECKPOINT_BEAT", "HUD_MINI_GAME_SOUNDSET", 1)

                if currentCP < #Config.Checkpoints then
                    currentCP = currentCP + 1
                else
                    currentCP  = 1
                    currentLap = currentLap + 1

                    if currentLap > Config.MaxLaps then
                        -- Finished — server sends results notify then delayed TP
                        isRacing = false
                        ClearWaypoint()
                        lib.hideTextUI()
                        TriggerServerEvent('frcp_f1:server:finishRace')
                        break
                    else
                        lib.notify({
                            title       = string.format('LAP %d COMPLETE', currentLap - 1),
                            description = string.format('%d lap(s) remaining', Config.MaxLaps - (currentLap - 1)),
                            type        = 'inform'
                        })
                    end
                end

                UpdateRaceWaypoint(Config.Checkpoints[currentCP])
                TriggerServerEvent('frcp_f1:server:updateProgress', currentLap, currentCP)
            end

            Wait(0)
        end

        -- After loop: close DRS UI if still open
        if drsOpen then
            lib.hideTextUI()
            drsOpen = false
        end
    end)
end)
