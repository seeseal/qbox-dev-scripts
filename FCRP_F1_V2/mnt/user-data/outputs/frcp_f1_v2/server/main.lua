-- ============================================================
--  FLAME CITY F1 — server/main.lua  v2.0
--  Qbox + oxmysql | ox_lib
-- ============================================================

-- ── Race state ───────────────────────────────────────────────
local racers         = {}   -- [id(str)] = { name, lap, cp, score, finished, finishTime, dq, dqReason, finishPos, pitDone, gridSlot }
local raceInProgress = false
local raceStartTime  = nil
local finishOrder    = {}
local dqList         = {}
local pendingGrid    = {}
local gridAssignments= {}
local scOrganiser    = nil

-- ============================================================
-- DB INIT
-- ============================================================
CreateThread(function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS f1_players (
            citizenid      VARCHAR(50)  PRIMARY KEY,
            xp             INT          NOT NULL DEFAULT 0,
            rating         INT          NOT NULL DEFAULT 1000,
            wins           INT          NOT NULL DEFAULT 0,
            races          INT          NOT NULL DEFAULT 0,
            weekly_claimed BIGINT       NOT NULL DEFAULT 0
        )
    ]], {})

    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS f1_crews (
            id      INT          AUTO_INCREMENT PRIMARY KEY,
            name    VARCHAR(100) NOT NULL,
            leader  VARCHAR(50)  NOT NULL,
            members TEXT         NOT NULL DEFAULT '[]'
        )
    ]], {})

    print('^2[FRCP_F1]^7 DB tables ensured.')
end)

-- ============================================================
-- HELPERS
-- ============================================================
local function DBG(...)
    if Config.Debug then print('[FRCP_F1][SERVER]', ...) end
end

local function GetRaceTime(ts)
    if not raceStartTime then return '?' end
    local secs = ts - raceStartTime
    return string.format('%d:%05.2f', math.floor(secs/60), secs % 60)
end

local function RacerScore(data)
    return ((data.lap or 1) - 1) * 1000 + (data.cp or 1)
end

local function IsOrganiser(src)
    if not Config.OrganizerPermission then return true end
    if IsPlayerAceAllowed(src, Config.OrganizerPermission) then return true end
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok and player then
        local g = player.PlayerData.group
        if g and (g == 'admin' or g == 'superadmin' or g == Config.OrganizerPermission) then return true end
    end
    DBG(string.format('AUTH DENIED src=%d (%s)', src, GetPlayerName(src) or '?'))
    return false
end

local function GetPlayer(src)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return (ok and player) and player or nil
end

local function GetCid(src)
    local p = GetPlayer(src)
    return p and p.PlayerData.citizenid or tostring(src)
end

local function AddMoney(src, amount)
    local p = GetPlayer(src)
    if p then p.Functions.AddMoney(Config.MoneyType, amount, 'f1-prize') end
end

local function RemoveMoney(src, amount)
    local p = GetPlayer(src)
    if not p then return false end
    if p.Functions.GetMoney(Config.MoneyType) < amount then return false end
    p.Functions.RemoveMoney(Config.MoneyType, amount, 'f1-fee')
    return true
end

local function HasItem(src, itemName)
    local p = GetPlayer(src)
    return p and p.Functions.GetItemByName(itemName) ~= nil
end

local function RemoveItem(src, itemName, amount)
    local p = GetPlayer(src)
    if p then p.Functions.RemoveItem(itemName, amount or 1) end
end

-- ── Leaderboard ──────────────────────────────────────────────
local function BuildSnapshot()
    local list = {}
    for id, data in pairs(racers) do
        table.insert(list, {
            id=id, name=data.name,
            lap=data.lap, cp=data.cp,
            score=RacerScore(data),
            finished=data.finished, dq=data.dq,
            time=data.finishTime and GetRaceTime(data.finishTime) or nil,
            pos=data.finishPos, dqReason=data.dqReason,
        })
    end
    table.sort(list, function(a,b)
        if a.finished ~= b.finished then
            if a.finished then return true end
            if b.finished then return false end
        end
        if a.dq ~= b.dq then return not a.dq end
        return (a.score or 0) > (b.score or 0)
    end)
    return list
end

local function BroadcastLeaderboard()
    local snapshot = BuildSnapshot()
    local leaderScore = snapshot[1] and snapshot[1].score or 0
    for _, playerId in ipairs(GetActivePlayers()) do
        local key = tostring(playerId)
        local gap = nil
        if racers[key] then
            if snapshot[1] and snapshot[1].id == key then
                gap = 'LEADER'
            else
                local diff = leaderScore - RacerScore(racers[key])
                gap = diff > 0 and string.format('+%d CP', diff) or 'LEADER'
            end
        end
        TriggerClientEvent('frcp_f1:client:updateLeaderboard', playerId, snapshot, gap)
    end
end

-- ── DB: Get or create player stats ───────────────────────────
local function GetOrCreateStats(cid, cb)
    MySQL.Async.fetchAll('SELECT * FROM f1_players WHERE citizenid = @cid', { ['@cid']=cid }, function(rows)
        if rows and rows[1] then
            cb(rows[1])
        else
            MySQL.Async.execute(
                'INSERT INTO f1_players (citizenid) VALUES (@cid)',
                { ['@cid']=cid },
                function()
                    cb({ citizenid=cid, xp=0, rating=1000, wins=0, races=0, weekly_claimed=0 })
                end
            )
        end
    end)
end

local function UpdateStats(cid, xpDelta, rDelta, won)
    MySQL.Async.execute([[
        UPDATE f1_players
        SET xp=xp+@xp, rating=rating+@r, wins=wins+@w, races=races+1
        WHERE citizenid=@cid
    ]], { ['@xp']=xpDelta, ['@r']=rDelta, ['@w']=won and 1 or 0, ['@cid']=cid })
end

-- ── XP helpers ───────────────────────────────────────────────
local function GetXpForPos(pos)
    return Config.XP[pos] or (Config.XP[#Config.XP] or 1)
end
local function GetRatingForPos(pos)
    return Config.Rating[pos] or (Config.Rating[#Config.Rating] or -20)
end

-- ============================================================
-- DISCORD WEBHOOK
-- ============================================================
local function SendWebhook()
    if not Config.DiscordWebhook or Config.DiscordWebhook == 'YOUR_WEBHOOK_URL_HERE' then return end
    local medals  = {'🥇','🥈','🥉'}
    local podium  = ''
    local dqLines = ''
    for i, e in ipairs(finishOrder) do
        podium = podium .. string.format('%s  **%s** — `%s`\n', medals[i] or (i..'.'), e.name, e.time)
    end
    if podium == '' then podium = '*No finishers*\n' end
    for _, e in ipairs(dqList) do
        dqLines = dqLines .. string.format('❌  **%s** — %s\n', e.name, e.reason)
    end
    if dqLines == '' then dqLines = '*None*\n' end
    local desc = string.format('**%s**\n\n**🏁 Results**\n%s\n**🚫 Disqualified**\n%s',
        os.date('%d %b %Y · %H:%M'), podium, dqLines)
    local body = { username=Config.WebhookBotName or 'Flame City GP',
        embeds={{ title='Flame City Grand Prix — Race Summary', description=desc,
            color=16766720, footer={text='frcp_f1 v2.0 · FiveM'} }} }
    if Config.WebhookAvatar and Config.WebhookAvatar ~= '' then body.avatar_url = Config.WebhookAvatar end
    PerformHttpRequest(Config.DiscordWebhook, function(code)
        print(code == 204 and '^2[F1]^7 Webhook OK' or string.format('^1[F1]^7 Webhook failed HTTP %s', tostring(code)))
    end, 'POST', json.encode(body), { ['Content-Type']='application/json' })
end

-- ============================================================
-- RESULTS SCREEN
-- ============================================================
local function ShowResultsAndTeleport()
    local snapshot = BuildSnapshot()
    local delay    = Config.ResultsScreenDelay or 18
    local medals   = {'🥇','🥈','🥉'}

    -- Build NUI-ready result rows
    local rows = {}
    for _, entry in ipairs(snapshot) do
        local gap = ''
        if entry.pos and entry.pos > 1 and finishOrder[entry.pos] and finishOrder[1] then
            local diff = finishOrder[entry.pos].rawTime - finishOrder[1].rawTime
            gap = string.format('+%.2fs', diff)
        elseif entry.pos == 1 then gap = 'WINNER' end

        table.insert(rows, {
            name      = entry.name,
            pos       = entry.pos,
            time      = entry.time,
            gap       = gap,
            dq        = entry.dq,
            dqReason  = entry.dqReason,
        })
    end

    TriggerClientEvent('frcp_f1:client:showResults', -1, {
        results  = rows,
        subtitle = 'FLAME CITY GRAND PRIX',
        delay    = delay,
    })

    -- Also notify via ox_lib for those who don't see NUI
    local lines = ''
    for _, entry in ipairs(snapshot) do
        if entry.dq then
            lines = lines .. string.format('❌ DQ  %s\n', entry.name)
        else
            lines = lines .. string.format('%s  %s  %s\n',
                medals[entry.pos] or ('P'..entry.pos), entry.name, entry.time or '?')
        end
    end
    TriggerClientEvent('ox_lib:notify', -1, {
        title='🏁 Race Results — Flame City GP', description=lines,
        type='inform', duration=delay*1000, position='top',
    })

    SetTimeout(delay*1000, function()
        for id, data in pairs(racers) do
            if data.finished and not data.dq then
                local numId = tonumber(id)
                if numId then TriggerClientEvent('frcp_f1:client:teleportPostRace', numId) end
            end
        end
        racers = {}
        print('^2[F1]^7 Post-race TP sent.')
    end)
end

-- ============================================================
-- 1. NPC MENU REQUEST  (from ox_target)
-- ============================================================
RegisterNetEvent('frcp_f1:server:requestMenuOpen', function()
    local src = source
    if IsOrganiser(src) then
        local list = {}
        for _, pid in ipairs(GetActivePlayers()) do
            local name = GetPlayerName(pid)
            if name then table.insert(list, { id=pid, name=name }) end
        end
        TriggerClientEvent('frcp_f1:client:openOrganizerMenu', src, list)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title='Race Manager', description='Race not open right now.', type='inform'
        })
    end
end)

RegisterNetEvent('frcp_f1:server:requestMyStats', function()
    local src = source
    local cid = GetCid(src)
    GetOrCreateStats(cid, function(stats)
        TriggerClientEvent('frcp_f1:client:openStatsMenu', src, stats)
    end)
end)

-- ============================================================
-- 2. /f1menu COMMAND  (legacy organiser entry)
-- ============================================================
lib.addCommand('f1menu', { help='Open Flame City GP Organiser Panel' }, function(source)
    local src = source
    if not IsOrganiser(src) then
        TriggerClientEvent('ox_lib:notify', src, { title='Access Denied', description=Config.Notify.accessDenied, type='error' })
        return
    end
    local list = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local name = GetPlayerName(pid)
        if name then table.insert(list, { id=pid, name=name }) end
    end
    TriggerClientEvent('frcp_f1:client:openOrganizerMenu', src, list)
end)

-- ============================================================
-- 3. SLOT ASSIGNMENT
-- ============================================================
RegisterNetEvent('frcp_f1:server:assignSlot', function(slot, targetId)
    local src = source
    if not IsOrganiser(src) then return end
    targetId = tonumber(targetId); slot = tonumber(slot)
    if not targetId or not slot or slot < 1 or slot > #Config.GridSpots then
        TriggerClientEvent('ox_lib:notify', src, { title='Invalid Input', type='error' }); return
    end
    local name = GetPlayerName(targetId)
    if not name then
        TriggerClientEvent('ox_lib:notify', src, {
            title='Not Found', description='ID '..targetId..' not online', type='error' }); return
    end

    -- Item check
    if Config.Items.enabled then
        if not HasItem(targetId, Config.Items.entryItem) then
            TriggerClientEvent('ox_lib:notify', src, {
                title='Missing Item',
                description=('Player %s needs a %s to enter.'):format(name, Config.Items.entryItem),
                type='error' }); return
        end
        RemoveItem(targetId, Config.Items.entryItem, 1)
    end

    pendingGrid[slot] = targetId
    TriggerClientEvent('frcp_f1:client:slotAssigned', src, slot, targetId, name)
    TriggerClientEvent('ox_lib:notify', src, {
        title='Assigned', description=string.format('P%d → %s (ID %d)', slot, name, targetId), type='success'
    })
end)

RegisterNetEvent('frcp_f1:server:clearGrid', function()
    local src = source
    if not IsOrganiser(src) then return end
    pendingGrid = {}
    TriggerClientEvent('ox_lib:notify', src, { title='Grid Cleared', type='inform' })
end)

-- ============================================================
-- 4. GRID SETUP
-- ============================================================
RegisterNetEvent('frcp_f1:server:setupGrid', function()
    local src = source
    if not IsOrganiser(src) then return end

    TriggerClientEvent('frcp_f1:client:cleanupCars', -1)
    racers={}; finishOrder={}; dqList={}
    raceInProgress=false; raceStartTime=nil; gridAssignments={}

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
                    finishTime=nil, finishPos=nil, pitDone=false,
                    gridSlot=slot,
                }
                gridAssignments[slot] = tid
                placed = placed + 1
            end
        end
    end

    BroadcastLeaderboard()
    TriggerClientEvent('ox_lib:notify', src, {
        title='Grid Ready', description=string.format('%d driver(s) on the grid', placed), type='success'
    })
    print(string.format('^2[F1]^7 Grid set. %d human driver(s).', placed))
end)

-- ============================================================
-- 5a. DEPLOY SAFETY CAR
-- ============================================================
RegisterNetEvent('frcp_f1:server:deploySafetyCar', function()
    local src = source
    if not IsOrganiser(src) then return end
    if next(racers) == nil then
        TriggerClientEvent('ox_lib:notify', src, { title='No Grid', description='Prepare the grid first.', type='error' }); return
    end
    scOrganiser = src
    TriggerClientEvent('frcp_f1:client:spawnSafetyCar', src)
    SetTimeout(1500, function()
        TriggerClientEvent('frcp_f1:client:beginFormationLap', -1)
    end)
    TriggerClientEvent('ox_lib:notify', -1, {
        title='🟡 Safety Car Deployed',
        description='Follow the safety car — race starts when SC returns',
        type='inform', duration=6000,
    })
    print('^3[F1]^7 Safety car deployed by ' .. GetPlayerName(src))
end)

RegisterNetEvent('frcp_f1:server:formationLapDone', function()
    print('^2[F1]^7 Formation lap complete. Returning to grid.')
    local src = source
    TriggerClientEvent('frcp_f1:client:despawnSafetyCar', src)
    for id, data in pairs(racers) do
        local numId = tonumber(id)
        if numId and data.gridSlot then
            local spot = Config.GridSpots[data.gridSlot]
            if spot then TriggerClientEvent('frcp_f1:client:returnToGrid', numId, spot) end
        end
    end
    SetTimeout(4000, function()
        raceInProgress = true
        TriggerClientEvent('frcp_f1:client:startRace', -1)
        print('^2[F1]^7 Race auto-started after formation lap.')
    end)
end)

-- ============================================================
-- 5b. MANUAL START
-- ============================================================
RegisterNetEvent('frcp_f1:server:startGlobalRace', function()
    local src = source
    if not IsOrganiser(src) then return end
    if raceInProgress then
        TriggerClientEvent('ox_lib:notify', src, { title='Already Racing', type='warning' }); return
    end
    if next(racers) == nil then
        TriggerClientEvent('ox_lib:notify', src, { title='No Drivers', description='Set up the grid first.', type='error' }); return
    end
    raceInProgress = true
    TriggerClientEvent('frcp_f1:client:endFormationLap', -1)
    local scSrc = scOrganiser or src
    TriggerClientEvent('frcp_f1:client:despawnSafetyCar', scSrc)
    scOrganiser = nil
    SetTimeout(2000, function()
        TriggerClientEvent('frcp_f1:client:startRace', -1)
    end)
    print('^2[F1]^7 Race force-started by ' .. GetPlayerName(src))
end)

-- ============================================================
-- 5c. AUTO-RACE TRIGGER
-- ============================================================
RegisterNetEvent('frcp_f1:server:autoRaceTrigger', function()
    if raceInProgress then return end
    if next(racers) == nil then return end   -- need a grid set up first
    raceInProgress = true
    TriggerClientEvent('frcp_f1:client:startRace', -1)
    print('^3[F1]^7 Auto-race triggered.')
end)

-- ============================================================
-- 6. RACE CLOCK
-- ============================================================
RegisterNetEvent('frcp_f1:server:raceClockStart', function()
    local key = tostring(source)
    if not racers[key] then return end
    if not raceInProgress then return end
    if not raceStartTime then
        raceStartTime = os.time()
        print('^2[F1]^7 Clock started.')
    end
end)

-- ============================================================
-- 7. PROGRESS UPDATE
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
-- 8. PIT STOP  (server validates, then triggers client animation)
-- ============================================================
RegisterNetEvent('frcp_f1:server:pitStop', function(compound)
    local src = source
    if not Config.TireCompounds[compound] then return end
    local key = tostring(src)
    if racers[key] then racers[key].pitDone = true end
    TriggerClientEvent('frcp_f1:client:doPitStop', src, compound)
    DBG(('Pit stop: %s → %s'):format(GetPlayerName(src), compound))
end)

-- ============================================================
-- 9. DQ
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
        title='DISQUALIFIED', description=name..' — '..reason, type='error'
    })
    BroadcastLeaderboard()
    print(string.format('^1[F1]^7 DQ: %s — %s', name, reason))
    TriggerClientEvent('frcp_f1:client:teleportPostRace', src)

    local total, done = 0, 0
    for _, d in pairs(racers) do total=total+1; if d.finished or d.dq then done=done+1 end end
    if total > 0 and done >= total then
        raceInProgress = false; SendWebhook(); ShowResultsAndTeleport()
    end
end)

-- ============================================================
-- 10. FINISH
-- ============================================================
RegisterNetEvent('frcp_f1:server:finishRace', function()
    local src  = source
    local name = GetPlayerName(src)
    local key  = tostring(src)

    if not racers[key] or racers[key].finished then return end

    local now      = os.time()
    local position = #finishOrder + 1
    local timeStr  = GetRaceTime(now)
    local cid      = GetCid(src)

    racers[key].finished   = true
    racers[key].finishTime = now
    racers[key].finishPos  = position
    table.insert(finishOrder, { id=src, name=name, time=timeStr, rawTime=now-(raceStartTime or now) })

    -- XP & Rating
    local xpEarned  = position == 1 and Config.WinXP     or GetXpForPos(position)
    local rDelta    = position == 1 and Config.RatingWin  or GetRatingForPos(position)
    UpdateStats(cid, xpEarned, rDelta, position == 1)

    -- Prize (winner only)
    if position == 1 then
        exports.ox_inventory:AddItem(src, Config.PrizeItem, Config.PrizeMoney)
        TriggerClientEvent('ox_lib:notify', -1, {
            title='🏁 Race Winner!',
            description=string.format('%s wins!  +$%d  +%d XP', name, Config.PrizeMoney, xpEarned),
            type='success'
        })
    end

    -- Notify the finisher with XP summary
    TriggerClientEvent('ox_lib:notify', src, {
        title=string.format('P%d Finish', position),
        description=string.format('%s  |  +%d XP  |  %+d Rating', timeStr, xpEarned, rDelta),
        type=position == 1 and 'success' or 'inform'
    })

    BroadcastLeaderboard()
    print(string.format('^2[F1]^7 P%d: %s — %s (+%d XP)', position, name, timeStr, xpEarned))

    local total, done = 0, 0
    for _, d in pairs(racers) do total=total+1; if d.finished or d.dq then done=done+1 end end
    if total > 0 and done >= total then
        raceInProgress = false; SendWebhook(); ShowResultsAndTeleport()
    end
end)

-- ============================================================
-- 11. RACE DIRECTOR CAM
-- ============================================================
RegisterNetEvent('frcp_f1:server:getVehicleForCam', function(targetId)
    local src = source
    if not IsOrganiser(src) then return end
    local ped = GetPlayerPed(targetId)
    if not ped or ped == 0 then
        TriggerClientEvent('ox_lib:notify', src, { title='Cam Error', description='Player not found', type='error' }); return
    end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        TriggerClientEvent('ox_lib:notify', src, { title='Cam Error', description='Player not in vehicle', type='error' }); return
    end
    TriggerClientEvent('frcp_f1:client:attachDirectorCam', src, NetworkGetNetworkIdFromEntity(veh))
end)

-- ============================================================
-- 12. FORCE END
-- ============================================================
RegisterNetEvent('frcp_f1:server:forceEnd', function()
    local src = source
    if not IsOrganiser(src) then return end
    TriggerClientEvent('frcp_f1:client:cleanupCars', -1)
    if scOrganiser then TriggerClientEvent('frcp_f1:client:despawnSafetyCar', scOrganiser); scOrganiser=nil end
    racers={}; finishOrder={}; dqList={}
    raceInProgress=false; raceStartTime=nil; pendingGrid={}
    TriggerClientEvent('ox_lib:notify', -1, {
        title='Race Reset', description='Organiser ended the race.', type='warning'
    })
    print('^3[F1]^7 Force end by ' .. GetPlayerName(src))
end)

-- ============================================================
-- 13. COMMANDS
-- ============================================================

-- /f1stats — view own stats in chat
lib.addCommand('f1stats', { help='View your F1 racing statistics' }, function(source)
    local src = source
    local cid = GetCid(src)
    GetOrCreateStats(cid, function(stats)
        TriggerClientEvent('chat:addMessage', src, { args={
            string.format('[F1 Stats]  XP: %d | Rating: %d | Wins: %d | Races: %d',
                stats.xp, stats.rating, stats.wins, stats.races)
        }})
    end)
end)

-- /f1leaderboard — top 10 by rating
lib.addCommand('f1leaderboard', { help='Show F1 rating leaderboard' }, function(source)
    local src = source
    MySQL.Async.fetchAll(
        'SELECT citizenid, xp, rating, wins, races FROM f1_players ORDER BY rating DESC LIMIT 10',
        {},
        function(rows)
            if not rows or #rows == 0 then
                TriggerClientEvent('chat:addMessage', src, { args={'[F1]', 'No stats yet.'} }); return
            end
            TriggerClientEvent('chat:addMessage', src, { args={'[F1]', '─── Top 10 Drivers ───'} })
            for i, row in ipairs(rows) do
                TriggerClientEvent('chat:addMessage', src, { args={
                    string.format('#%d  %s  |  Rating: %d  |  Wins: %d  |  XP: %d',
                        i, row.citizenid, row.rating, row.wins, row.xp)
                }})
            end
        end
    )
end)

-- /f1reward — weekly reward claim
lib.addCommand('f1reward', { help='Claim your weekly F1 reward' }, function(source)
    local src  = source
    local cid  = GetCid(src)
    local now  = os.time()
    local week = 7 * 24 * 3600

    GetOrCreateStats(cid, function(stats)
        if (now - stats.weekly_claimed) < week then
            local hours = math.floor((week - (now - stats.weekly_claimed)) / 3600)
            TriggerClientEvent('ox_lib:notify', src, {
                title='Weekly Reward',
                description=(Config.Notify.weeklyNotReady):gsub('{hours}', hours),
                type='inform'
            }); return
        end

        local r = Config.WeeklyReward
        if r.type == 'money' then
            local p = GetPlayer(src)
            if p then p.Functions.AddMoney(Config.MoneyType, r.money, 'f1-weekly-reward') end
        elseif r.type == 'item' then
            exports.ox_inventory:AddItem(src, r.item.name, r.item.amount)
        end

        MySQL.Async.execute(
            'UPDATE f1_players SET weekly_claimed=@t WHERE citizenid=@cid',
            { ['@t']=now, ['@cid']=cid }
        )
        TriggerClientEvent('ox_lib:notify', src, {
            title='Weekly Reward', description=Config.Notify.weeklyReward, type='success'
        })
    end)
end)

-- /createf1crew — create a crew
lib.addCommand('createf1crew', {
    help='Create an F1 racing crew',
    params={{ name='crewname', help='Crew name', type='string' }}
}, function(source, args)
    if not Config.CrewSystem.enabled then return end
    local src      = source
    local crewName = args.crewname
    if not crewName or crewName == '' then return end

    if not RemoveMoney(src, Config.CrewSystem.createCost) then
        TriggerClientEvent('ox_lib:notify', src, {
            title='Not Enough Money',
            description=Config.Notify.notEnoughMoney, type='error' }); return
    end

    local cid = GetCid(src)
    MySQL.Async.execute(
        'INSERT INTO f1_crews (name, leader, members) VALUES (@n, @l, @m)',
        { ['@n']=crewName, ['@l']=cid, ['@m']=json.encode({cid}) },
        function(rowsChanged)
            if rowsChanged > 0 then
                TriggerClientEvent('ox_lib:notify', src, {
                    title='Crew Created',
                    description=(Config.Notify.crewCreated):gsub('{name}', crewName),
                    type='success'
                })
            end
        end
    )
end)

-- ============================================================
-- 14. PLAYER DROPPED — clean up active race slot
-- ============================================================
AddEventHandler('playerDropped', function()
    local src = source
    local key = tostring(src)
    if racers[key] then
        racers[key].dq       = true
        racers[key].dqReason = 'Disconnected'
        table.insert(dqList, { name=racers[key].name, reason='Disconnected' })
        BroadcastLeaderboard()
        DBG('Player ' .. src .. ' dropped mid-race — marked DQ.')
    end
end)

print('^2[FRCP_F1]^7 Server v2.0 loaded.')
