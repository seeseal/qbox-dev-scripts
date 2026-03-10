-- ============================================================
--  FLAME CITY GP — server/main.lua  v1.2
-- ============================================================

local racers         = {}   -- [id(str)] = { name, lap, cp, score, finished, finishTime, dq, dqReason, finishPos }
local raceInProgress = false
local raceStartTime  = nil
local finishOrder    = {}   -- { id, name, time }
local dqList         = {}   -- { name, reason }
local pendingGrid    = {}   -- [slot] = serverId
local safetyCar      = nil  -- entity handle for formation lap SC

-- ============================================================
-- HELPERS
-- ============================================================
local function GetRaceTime(ts)
    if not raceStartTime then return "?" end
    local secs = ts - raceStartTime
    local m    = math.floor(secs / 60)
    local s    = secs % 60
    return string.format("%d:%05.2f", m, s)
end

local function RacerScore(data)
    -- Higher = further along the race
    return ((data.lap or 1) - 1) * 1000 + (data.cp or 1)
end

local function IsOrganiser(src)
    if not Config.OrganizerPermission then return true end
    if IsPlayerAceAllowed(src, Config.OrganizerPermission) then return true end
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok and player then
        local g = player.PlayerData.group
        if g and (g == "admin" or g == "superadmin" or g == Config.OrganizerPermission) then
            return true
        end
    end
    print(string.format("^1[F1 AUTH]^7 DENIED src=%d (%s) | qbx_group=%s",
        src, GetPlayerName(src) or "?", (ok and player) and tostring(player.PlayerData.group) or "N/A"))
    return false
end

-- Build leaderboard snapshot sorted by race position
local function BuildSnapshot()
    local list = {}
    for id, data in pairs(racers) do
        table.insert(list, {
            id       = id,
            name     = data.name,
            lap      = data.lap,
            cp       = data.cp,
            score    = RacerScore(data),
            finished = data.finished,
            dq       = data.dq,
            time     = data.finishTime and GetRaceTime(data.finishTime) or nil,
            pos      = data.finishPos,
            dqReason = data.dqReason,
        })
    end
    table.sort(list, function(a, b)
        if a.finished ~= b.finished then
            if a.finished then return true end
            if b.finished then return false end
        end
        if a.dq ~= b.dq then return not a.dq end
        return (a.score or 0) > (b.score or 0)
    end)
    return list
end

-- Broadcast leaderboard + per-player gap to leader
local function BroadcastLeaderboard()
    local snapshot = BuildSnapshot()
    local leaderScore = snapshot[1] and snapshot[1].score or 0

    for _, playerId in ipairs(GetActivePlayers()) do
        local key = tostring(playerId)
        local gap = nil

        if racers[key] then
            local myScore = RacerScore(racers[key])
            if snapshot[1] and snapshot[1].id == key then
                gap = "LEADER"
            else
                -- Score difference as approximate seconds (rough: each CP ≈ 5-8s apart)
                local diff = leaderScore - myScore
                if diff > 0 then
                    gap = string.format("+%d CP", diff)
                else
                    gap = "LEADER"
                end
            end
        end

        TriggerClientEvent('frcp_f1:client:updateLeaderboard', playerId, snapshot, gap)
    end
end

-- ============================================================
-- DISCORD WEBHOOK
-- ============================================================
local function SendWebhook()
    if not Config.DiscordWebhook or Config.DiscordWebhook:find("YOUR_WEBHOOK") then
        print("^3[F1]^7 Webhook not configured."); return
    end
    local now     = os.date("%d %b %Y · %H:%M")
    local medals  = {"🥇","🥈","🥉"}
    local podium  = ""
    local dqLines = ""

    for i, e in ipairs(finishOrder) do
        local m = medals[i] or (i .. ".")
        podium = podium .. string.format("%s  **%s** — `%s`\n", m, e.name, e.time)
    end
    if podium == "" then podium = "*No finishers*\n" end
    for _, e in ipairs(dqList) do
        dqLines = dqLines .. string.format("❌  **%s** — %s\n", e.name, e.reason)
    end
    if dqLines == "" then dqLines = "*None*\n" end

    local desc = string.format("**%s**\n\n**🏁 Results**\n%s\n**🚫 Disqualified**\n%s", now, podium, dqLines)
    -- Only include avatar_url if one is actually configured — Discord rejects empty strings
    local webhookBody = {
        username = Config.WebhookBotName or "Flame City GP",
        embeds = {{
            title       = "Flame City Grand Prix — Race Summary",
            description = desc,
            color       = 16766720,
            footer      = { text = "frcp_f1 · FiveM" }
        }}
    }
    if Config.WebhookAvatar and Config.WebhookAvatar ~= "" then
        webhookBody.avatar_url = Config.WebhookAvatar
    end

    local payload = json.encode(webhookBody)
    PerformHttpRequest(Config.DiscordWebhook, function(code, body)
        if code == 204 then
            print("^2[F1]^7 Webhook delivered OK")
        else
            print(string.format("^1[F1]^7 Webhook failed — HTTP %s | %s", tostring(code), tostring(body)))
        end
    end, "POST", payload, { ["Content-Type"] = "application/json" })
end

-- ============================================================
-- RESULTS SCREEN + DELAYED TELEPORT
-- ============================================================
local function ShowResultsAndTeleport()
    local snapshot = BuildSnapshot()
    local delay    = Config.ResultsScreenDelay or 18
    local medals   = {"🥇","🥈","🥉"}

    local lines = ""
    for _, entry in ipairs(snapshot) do
        if entry.dq then
            lines = lines .. string.format("❌ DQ  %s — %s\n", entry.name, entry.dqReason or "")
        else
            local medal = medals[entry.pos] or ("P" .. entry.pos)
            local gap   = ""
            if entry.pos == 1 then
                gap = " · WINNER"
            elseif entry.pos and finishOrder[entry.pos] and finishOrder[1] then
                local diff = finishOrder[entry.pos].rawTime - finishOrder[1].rawTime
                gap = string.format(" · +%.2fs", diff)
            end
            lines = lines .. string.format("%s  %s  %s%s\n",
                medal, entry.name, entry.time or "?", gap)
        end
    end

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = '🏁 Race Results — Flame City GP',
        description = lines,
        type        = 'inform',
        duration    = delay * 1000,
        position    = 'top',
    })

    -- After delay: teleport finishers (DQ'd already teleported instantly)
    SetTimeout(delay * 1000, function()
        for id, data in pairs(racers) do
            if data.finished and not data.dq then
                local numId = tonumber(id)
                if numId then
                    TriggerClientEvent('frcp_f1:client:teleportPostRace', numId)
                end
            end
        end
        racers = {}
        print("^2[F1]^7 Post-race teleport sent to finishers.")
    end)
end

-- ============================================================
-- 1. /f1menu COMMAND
-- ============================================================
lib.addCommand('f1menu', { help = 'Open Flame City GP Organiser Panel' }, function(source)
    if not IsOrganiser(source) then
        TriggerClientEvent('ox_lib:notify', source, {
            title='Access Denied', description='You are not an organiser.', type='error'
        })
        return
    end
    print("^3[F1]^7 /f1menu by " .. GetPlayerName(source))
    local list = {}
    for _, playerId in ipairs(GetActivePlayers()) do
        local name = GetPlayerName(playerId)
        if name then table.insert(list, { id = playerId, name = name }) end
    end
    TriggerClientEvent('frcp_f1:client:openOrganizerMenu', source, list)
end)

RegisterNetEvent('frcp_f1:server:getPlayerList', function() end) -- legacy stub

-- ============================================================
-- 2. SLOT ASSIGNMENT
-- ============================================================
RegisterNetEvent('frcp_f1:server:assignSlot', function(slot, targetId)
    local src = source
    if not IsOrganiser(src) then return end
    targetId = tonumber(targetId); slot = tonumber(slot)
    if not targetId or not slot or slot < 1 or slot > #Config.GridSpots then
        TriggerClientEvent('ox_lib:notify', src, {title='Invalid Input', type='error'}); return
    end
    local name = GetPlayerName(targetId)
    if not name then
        TriggerClientEvent('ox_lib:notify', src, {
            title='Not Found', description='ID '..targetId..' not online', type='error'}); return
    end
    pendingGrid[slot] = targetId
    -- Update the label in the organiser's menu (pass targetId so client can show correct player ID)
    TriggerClientEvent('frcp_f1:client:slotAssigned', src, slot, targetId, name)
    TriggerClientEvent('ox_lib:notify', src, {
        title='Assigned', description=string.format("P%d → %s (ID %d)", slot, name, targetId), type='success'
    })
end)

RegisterNetEvent('frcp_f1:server:clearGrid', function()
    local src = source
    if not IsOrganiser(src) then return end
    pendingGrid = {}
    TriggerClientEvent('ox_lib:notify', src, {title='Grid Cleared', type='inform'})
end)

-- ============================================================
-- 3. GRID SETUP + FORMATION LAP
-- ============================================================
local gridAssignments = {}  -- [slot] = serverId (for returnToGrid TP)

RegisterNetEvent('frcp_f1:server:setupGrid', function()
    local src = source
    if not IsOrganiser(src) then return end

    TriggerClientEvent('frcp_f1:client:cleanupCars', -1)
    racers = {}; finishOrder = {}; dqList = {}
    raceInProgress = false; raceStartTime = nil
    gridAssignments = {}

    local placed = 0
    for slot = 1, #Config.GridSpots do
        local tid  = pendingGrid[slot]
        local spot = Config.GridSpots[slot]
        if tid then
            local name = GetPlayerName(tid)
            if name then
                TriggerClientEvent('frcp_f1:client:spawnYourCar', tid, spot)
                racers[tostring(tid)] = {
                    name=name, lap=1, cp=1, score=1,
                    finished=false, dq=false, dqReason=nil,
                    finishTime=nil, finishPos=nil,
                    gridSlot=slot,
                }
                gridAssignments[slot] = tid
                placed = placed + 1
            end
        end
    end

    BroadcastLeaderboard()
    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Grid Ready',
        description = string.format('%d driver(s) on the grid', placed),
        type        = 'success'
    })
    print(string.format("^2[F1]^7 Grid set. %d human driver(s).", placed))
end)

-- ============================================================
-- 4a. STEP 2 — DEPLOY SAFETY CAR
--     Organiser manually triggers this after grid is set.
--     SC spawns and leads drivers around at capped speed.
--     Organiser decides when they've reached the start line
--     and then presses Start Race.
-- ============================================================
local scOrganiser = nil

RegisterNetEvent('frcp_f1:server:deploySafetyCar', function()
    local src = source
    if not IsOrganiser(src) then return end
    if next(racers) == nil then
        TriggerClientEvent('ox_lib:notify', src, {
            title='No Grid', description='Prepare the grid first.', type='error'}); return
    end

    scOrganiser = src

    -- SC drives: safetyCarSpot → all checkpoints → back to safetyCarSpot
    -- When it finishes, organiser's client fires frcp_f1:server:formationLapDone
    TriggerClientEvent('frcp_f1:client:spawnSafetyCar', src)

    -- Unfreeze all human racers at capped speed after SC has a moment to spawn
    SetTimeout(1500, function()
        TriggerClientEvent('frcp_f1:client:beginFormationLap', -1)
    end)

    TriggerClientEvent('ox_lib:notify', -1, {
        title = '🟡 Safety Car Deployed',
        description = 'Follow the safety car — race starts automatically when SC returns',
        type = 'inform',
        duration = 6000,
    })
    print("^3[F1]^7 Safety car deployed by " .. GetPlayerName(src))
end)

-- ── FORMATION LAP AUTO-COMPLETE ──────────────────────────────────────────
-- Fired by the organiser's client when SC arrives back at start spot.
-- 1. Despawn SC
-- 2. TP all human cars back to their grid spots
-- 3. Wait 4s → race countdown
RegisterNetEvent('frcp_f1:server:formationLapDone', function()
    local src = source  -- this is the organiser's client
    print("^2[F1]^7 Formation lap complete. Returning to grid.")

    -- Despawn SC
    TriggerClientEvent('frcp_f1:client:despawnSafetyCar', src)

    -- TP every human racer's car back to their assigned grid spot
    for id, data in pairs(racers) do
        local numId = tonumber(id)
        if numId and data.gridSlot then
            local spot = Config.GridSpots[data.gridSlot]
            if spot then
                TriggerClientEvent('frcp_f1:client:returnToGrid', numId, spot)
            end
        end
    end

    -- Give everyone 4 seconds to get settled on the grid, then start
    SetTimeout(4000, function()
        raceInProgress = true
        TriggerClientEvent('frcp_f1:client:startRace', -1)
        print("^2[F1]^7 Race started automatically after formation lap.")
    end)
end)

-- ============================================================
-- 4c. STEP 3 — MANUAL START (skip / override formation lap)
-- ============================================================
RegisterNetEvent('frcp_f1:server:startGlobalRace', function()
    local src = source
    if not IsOrganiser(src) then return end
    if raceInProgress then
        TriggerClientEvent('ox_lib:notify', src, {title='Already Racing', type='warning'}); return
    end
    if next(racers) == nil then
        TriggerClientEvent('ox_lib:notify', src, {
            title='No Drivers', description='Set up the grid first.', type='error'}); return
    end

    raceInProgress = true

    -- Stop formation lap if one was running
    TriggerClientEvent('frcp_f1:client:endFormationLap', -1)
    local scSrc = scOrganiser or src
    TriggerClientEvent('frcp_f1:client:despawnSafetyCar', scSrc)
    scOrganiser = nil

    SetTimeout(2000, function()
        TriggerClientEvent('frcp_f1:client:startRace', -1)
    end)

    print("^2[F1]^7 Race force-started by " .. GetPlayerName(src))
end)

-- ============================================================
-- 5. RACE CLOCK START
-- ============================================================
RegisterNetEvent('frcp_f1:server:raceClockStart', function()
    local key = tostring(source)
    if not racers[key] then return end  -- only registered racers can start the clock
    if not raceInProgress then return end
    if not raceStartTime then
        raceStartTime = os.time()
        print("^2[F1]^7 Clock started: " .. raceStartTime)
    end
end)

-- ============================================================
-- 6. PROGRESS UPDATES (humans)
-- ============================================================
RegisterNetEvent('frcp_f1:server:updateProgress', function(lap, cp)
    local key = tostring(source)
    if racers[key] then
        racers[key].lap   = lap
        racers[key].cp    = cp
        racers[key].score = RacerScore(racers[key])
        BroadcastLeaderboard()
    end
end)

-- ============================================================
-- 7. DQ
-- ============================================================
RegisterNetEvent('frcp_f1:server:dqPlayer', function(reason)
    local src  = source
    local name = GetPlayerName(src)
    local key  = tostring(src)
    if racers[key] then
        racers[key].dq       = true
        racers[key].dqReason = reason
        table.insert(dqList, { name=name, reason=reason })
    end
    TriggerClientEvent('ox_lib:notify', -1, {
        title='DISQUALIFIED', description=name.." — "..reason, type='error'
    })
    BroadcastLeaderboard()
    print(string.format("^1[F1]^7 DQ: %s — %s", name, reason))

    -- DQ'd player is teleported INSTANTLY — no results screen wait for them
    TriggerClientEvent('frcp_f1:client:teleportPostRace', src)

    -- Check if everyone remaining is done
    local total, done = 0, 0
    for _, d in pairs(racers) do
        total = total + 1
        if d.finished or d.dq then done = done + 1 end
    end
    if total > 0 and done >= total then
        raceInProgress = false
        SendWebhook()
        ShowResultsAndTeleport()
    end
end)

-- ============================================================
-- 8. FINISH
-- ============================================================
RegisterNetEvent('frcp_f1:server:finishRace', function()
    local src  = source
    local name = GetPlayerName(src)
    local key  = tostring(src)

    if not racers[key] or racers[key].finished then return end

    local now      = os.time()
    local position = #finishOrder + 1
    local timeStr  = GetRaceTime(now)

    racers[key].finished   = true
    racers[key].finishTime = now
    racers[key].finishPos  = position
    table.insert(finishOrder, { id=src, name=name, time=timeStr, rawTime=now - (raceStartTime or now) })

    -- Prize to winner only
    if position == 1 then
        local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        if ok and player then
            exports.ox_inventory:AddItem(src, 'money', Config.PrizeMoney)
            TriggerClientEvent('ox_lib:notify', -1, {
                title='🏁 Race Winner!',
                description=player.PlayerData.charinfo.firstname..' wins! +$'..Config.PrizeMoney,
                type='success'
            })
        end
    else
        TriggerClientEvent('ox_lib:notify', -1, {
            title=string.format('P%d Finish', position),
            description=name..' crossed the line — '..timeStr,
            type='inform'
        })
    end

    BroadcastLeaderboard()
    print(string.format("^2[F1]^7 P%d: %s — %s", position, name, timeStr))

    -- Check if all racers are done
    local total, done = 0, 0
    for _, d in pairs(racers) do
        total = total + 1
        if d.finished or d.dq then done = done + 1 end
    end

    if total > 0 and done >= total then
        raceInProgress = false
        SendWebhook()
        ShowResultsAndTeleport()
    end
end)

-- ============================================================
-- 9. RACE DIRECTOR CAM — server resolves vehicle net ID
-- ============================================================
RegisterNetEvent('frcp_f1:server:getVehicleForCam', function(targetId)
    local src = source
    if not IsOrganiser(src) then return end

    local ped = GetPlayerPed(targetId)
    if not ped or ped == 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title='Cam Error', description='Player '..targetId..' not found', type='error'})
        return
    end

    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title='Cam Error', description='Player is not in a vehicle', type='error'})
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerClientEvent('frcp_f1:client:attachDirectorCam', src, netId)
end)

-- ============================================================
-- 10. FORCE END
-- ============================================================
RegisterNetEvent('frcp_f1:server:forceEnd', function()
    local src = source
    if not IsOrganiser(src) then return end
    TriggerClientEvent('frcp_f1:client:cleanupCars', -1)
    local scSrc2 = scOrganiser
    if scSrc2 then
        TriggerClientEvent('frcp_f1:client:despawnSafetyCar', scSrc2)
        scOrganiser = nil
    end
    racers={}; finishOrder={}; dqList={}
    raceInProgress=false; raceStartTime=nil; pendingGrid={}
    safetyCar = nil
    TriggerClientEvent('ox_lib:notify', -1, {
        title='Race Reset', description='Organiser ended the race.', type='warning'
    })
    print("^3[F1]^7 Force end by " .. GetPlayerName(src))
end)
