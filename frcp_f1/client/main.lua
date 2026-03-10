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

local currentPlayerMap = {}  -- persists between slot assignments so re-opens work

local function OpenOrganizerMenu()
    local totalSlots = #Config.GridSpots
    local slotOptions = {}
    for i = 1, totalSlots do
        local slotIndex = i  -- capture by value to fix the loop-closure bug
        local assigned  = slotLabels[slotIndex]
        local desc, iconColor
        if assigned then
            desc      = '✅  ' .. assigned
            iconColor = '#00cc66'
        else
            desc      = 'Tap to assign a driver'
            iconColor = '#888888'
        end
        local suffix = (slotIndex == 1) and ' — Pole' or ''
        table.insert(slotOptions, {
            title       = string.format('P%d%s', slotIndex, suffix),
            description = desc,
            icon        = 'user',
            iconColor   = iconColor,
            onSelect    = function() AssignSlot(slotIndex, currentPlayerMap) end,
        })
    end

    local options = {}

    -- ── STEP 1 ────────────────────────────────────────────
    table.insert(options, {
        title     = 'STEP 1  ·  GRID',
        disabled  = true,
        icon      = 'table-cells',
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
            OpenOrganizerMenu()
        end,
    })
    table.insert(options, {
        title       = 'Prepare Grid',
        description = 'Spawn cars and freeze drivers on their grid spots',
        icon        = 'flag',
        iconColor   = '#ffcc00',
        onSelect    = function()
            TriggerServerEvent('frcp_f1:server:setupGrid')
            OpenOrganizerMenu()
        end,
    })

    -- ── STEP 2 ────────────────────────────────────────────
    table.insert(options, {
        title     = 'STEP 2  ·  FORMATION LAP',
        disabled  = true,
        icon      = 'shield-halved',
        iconColor = '#e10600',
    })
    table.insert(options, {
        title       = 'Deploy Safety Car',
        description = 'SC leads drivers from grid to start — you control when to go',
        icon        = 'car',
        iconColor   = '#ffaa00',
        onSelect    = function()
            TriggerServerEvent('frcp_f1:server:deploySafetyCar')
            OpenOrganizerMenu()
        end,
    })

    -- ── STEP 3 ────────────────────────────────────────────
    table.insert(options, {
        title     = 'STEP 3  ·  RACE START',
        disabled  = true,
        icon      = 'traffic-light',
        iconColor = '#e10600',
    })
    table.insert(options, {
        title       = 'START RACE',
        description = 'Despawn SC · Freeze grid · Lights out',
        icon        = 'flag-checkered',
        iconColor   = '#00cc44',
        onSelect    = function()
            TriggerServerEvent('frcp_f1:server:startGlobalRace')
            OpenOrganizerMenu()
        end,
    })

    -- ── TOOLS ─────────────────────────────────────────────
    table.insert(options, {
        title     = 'TOOLS',
        disabled  = true,
        icon      = 'wrench',
        iconColor = '#888888',
    })
    table.insert(options, {
        title       = 'Race Director Camera',
        description = 'Cinematic overhead view of any driver',
        icon        = 'video',
        iconColor   = '#88aaff',
        onSelect    = function() OpenDirectorCamMenu() end,
    })
    table.insert(options, {
        title       = 'Force End / Reset',
        description = 'Emergency stop — teleports everyone and resets all state',
        icon        = 'circle-xmark',
        iconColor   = '#ff4444',
        onSelect    = function()
            TriggerServerEvent('frcp_f1:server:forceEnd')
            OpenOrganizerMenu()
        end,
    })

    lib.registerContext({ id = 'f1_organiser', title = '  FLAME CITY GP  ·  Race Control', options = options })
    lib.showContext('f1_organiser')
end

RegisterNetEvent('frcp_f1:client:openOrganizerMenu', function(playerList)
    currentPlayerMap = {}
    for _, p in ipairs(playerList) do
        currentPlayerMap[p.id] = p.name
    end
    OpenOrganizerMenu()
end)

-- Update slot label locally after successful assign, then refresh the menu
RegisterNetEvent('frcp_f1:client:slotAssigned', function(slot, playerId, name)
    slotLabels[slot] = string.format('ID %d — %s', playerId, name)
    OpenOrganizerMenu()
end)

function AssignSlot(slot, playerMap)
    local result = lib.inputDialog('Assign P' .. slot, {
        { type = 'number', label = 'Player Server ID', placeholder = 'e.g. 5', required = true, min = 1 }
    })
    if not result or not result[1] then OpenOrganizerMenu(); return end
    local targetId = tonumber(result[1])
    if not targetId then
        lib.notify({ title = 'Invalid ID', type = 'error' })
        OpenOrganizerMenu()
        return
    end
    TriggerServerEvent('frcp_f1:server:assignSlot', slot, targetId)
    -- Menu will re-open via slotAssigned event once server confirms
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
    lib.showContext('f1_organiser')
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
        -- Project the player's position onto the entry→exit segment.
        -- t=0 means at entry, t=1 means at exit.
        -- DRS is open when the player is between entry and exit (0 <= t <= 1)
        -- and within the lateral corridor (radius) of that segment.
        local ex = zone.exit.x  - zone.entry.x
        local ey = zone.exit.y  - zone.entry.y
        local ez = zone.exit.z  - zone.entry.z
        local lenSq = ex*ex + ey*ey + ez*ez

        local t = 0.0
        if lenSq > 0.0 then
            local dx = coords.x - zone.entry.x
            local dy = coords.y - zone.entry.y
            local dz = coords.z - zone.entry.z
            t = (dx*ex + dy*ey + dz*ez) / lenSq
        end

        if t >= 0.0 and t <= 1.0 then
            -- Closest point on the segment
            local cx = zone.entry.x + t * ex
            local cy = zone.entry.y + t * ey
            local cz = zone.entry.z + t * ez
            local lateral = math.sqrt(
                (coords.x - cx)^2 + (coords.y - cy)^2 + (coords.z - cz)^2
            )
            if lateral < zone.radius then
                newOpen = true
                newZone = i
                break
            end
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
-- ============================================================

local safetyCar       = nil   -- SC entity (organiser client only)
local safetyCarBlip   = nil
local safetyCarActive = false

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
-- 12. RESULTS
-- ============================================================
-- Results are broadcast via ox_lib:notify from the server.
-- No client-side handling needed.

-- ============================================================
-- 13. SPAWN & CLEANUP
-- ============================================================
-- Livery assignment: 11 liveries (1–11). Livery 1 is reserved — never randomised.
-- Each driver gets a unique livery from 2–11 per race session.
local usedLiveries = {}

local function AssignLivery(veh)
    local pool = {}
    for i = 2, 11 do
        if not usedLiveries[i] then table.insert(pool, i) end
    end
    local chosen
    if #pool > 0 then
        chosen = pool[math.random(1, #pool)]
        usedLiveries[chosen] = true
    else
        -- Fallback if somehow all 10 slots are taken (>10 drivers)
        chosen = math.random(2, 11)
    end
    SetVehicleLivery(veh, chosen)
end

-- Max performance mods for openwheel1
local function ApplyMaxMods(veh)
    SetVehicleModKit(veh, 0)
    -- Iterate all mod slots 0-49 and apply max value
    local modSlots = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23}
    for _, slot in ipairs(modSlots) do
        local count = GetNumVehicleMods(veh, slot)
        if count > 0 then
            SetVehicleMod(veh, slot, count - 1, false)
        end
    end
    -- Turbo
    ToggleVehicleMod(veh, 18, true)
    -- Xenon lights
    ToggleVehicleMod(veh, 22, true)
end

RegisterNetEvent('frcp_f1:client:spawnYourCar', function(spot)
    local ped = cache and cache.ped or PlayerPedId()
    if not ped or ped == 0 then
        lib.notify({ title = 'Spawn Error', description = 'Ped not ready — try again in a moment', type = 'error' })
        return
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

    -- Reset systems
    drsOpen      = false
    engineStatus = "OK"

    -- RPM lock while frozen on grid
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
    usedLiveries    = {}
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
    local ped = cache and cache.ped or PlayerPedId()
    if ped and ped ~= 0 then
        SetEntityCoords(ped,
            Config.PostRaceLocation.x, Config.PostRaceLocation.y, Config.PostRaceLocation.z,
            false, false, false, false)
    end
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


    CreateThread(function()
        while isRacing do
            local ped    = cache and cache.ped or PlayerPedId()
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
