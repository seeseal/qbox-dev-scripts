-- ============================================================
--  FLAME CITY F1 — server/main.lua  v3.0
--  Qbox + oxmysql | ox_lib
-- ============================================================

-- ── Race session state ───────────────────────────────────────
local racers          = {}   -- [str(src)] = { name, cid, lap, cp, score, finished, dq, dqReason,
                              --                finishTime, finishPos, pitDone, gridSlot,
                              --                fastestLapMs, currentLapStart, lapTimes }
local raceInProgress  = false
local raceStartTime   = nil
local finishOrder     = {}   -- { id, name, time, rawTime }
local dqList          = {}
local pendingGrid     = {}   -- [slot] = serverId
local gridAssignments = {}   -- [slot] = serverId (for formation lap TP)
local scOrganiser     = nil
local fastestLapHolder= nil  -- citizenId who holds the fastest lap
local fastestLapMs    = nil  -- ms value

-- ── Race session ID ──────────────────────────────────────────
local function NewRaceId()
    return string.format('F1-%s-%04d', os.date('%Y%m%d'), math.random(1000, 9999))
end
local currentRaceId = NewRaceId()

-- ============================================================
-- DB INIT
-- ============================================================
CreateThread(function()
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS f1_players (
            citizenid      VARCHAR(50)  PRIMARY KEY,
            mmr            INT          NOT NULL DEFAULT 1500,
            xp             INT          NOT NULL DEFAULT 0,
            wins           INT          NOT NULL DEFAULT 0,
            races          INT          NOT NULL DEFAULT 0,
            podiums        INT          NOT NULL DEFAULT 0,
            fastest_laps   INT          NOT NULL DEFAULT 0,
            best_lap_ms    INT          DEFAULT NULL,
            stats          JSON         NOT NULL DEFAULT '{}',
            achievements   JSON         NOT NULL DEFAULT '{}',
            mmr_history    JSON         NOT NULL DEFAULT '[]',
            weekly_claimed BIGINT       NOT NULL DEFAULT 0
        )
    ]], {})

    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS f1_race_history (
            id           INT          AUTO_INCREMENT PRIMARY KEY,
            race_id      VARCHAR(20)  NOT NULL,
            citizenid    VARCHAR(50)  NOT NULL,
            position     INT          NOT NULL,
            total_laps   INT          NOT NULL DEFAULT 0,
            race_time    VARCHAR(20),
            best_lap     VARCHAR(20),
            sector_times JSON         NOT NULL DEFAULT '[]',
            tyre_used    VARCHAR(20),
            pit_count    INT          NOT NULL DEFAULT 0,
            drs_count    INT          NOT NULL DEFAULT 0,
            engine_ok    TINYINT(1)   NOT NULL DEFAULT 1,
            xp_earned    INT          NOT NULL DEFAULT 0,
            mmr_delta    INT          NOT NULL DEFAULT 0,
            dq           TINYINT(1)   NOT NULL DEFAULT 0,
            dq_reason    VARCHAR(100),
            race_date    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_cid (citizenid),
            INDEX idx_race (race_id)
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

    print('^2[FCRP_F1]^7 DB tables ensured (v3.0)')
end)

-- ============================================================
-- HELPERS
-- ============================================================
local function DBG(...)
    if Config.Debug then print('[FCRP_F1][SRV]', ...) end
end

local function FmtTime(ms)
    if not ms then return '?' end
    local secs = ms / 1000
    return string.format('%d:%06.3f', math.floor(secs / 60), secs % 60)
end

local function FmtRaceTime(ts)
    if not raceStartTime then return '?' end
    local secs = ts - raceStartTime
    return string.format('%d:%05.2f', math.floor(secs / 60), secs % 60)
end

local function RacerScore(d)
    return ((d.lap or 1) - 1) * 1000 + (d.cp or 1)
end

local function IsOrganiser(src)
    if not Config.OrganizerPermission then return true end
    if IsPlayerAceAllowed(src, Config.OrganizerPermission) then return true end
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok and p then
        local g = p.PlayerData.group
        if g and (g == 'admin' or g == 'superadmin' or g == Config.OrganizerPermission) then return true end
    end
    return false
end

local function GetQBPlayer(src)
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return (ok and p) or nil
end

local function GetCid(src)
    local p = GetQBPlayer(src)
    return p and p.PlayerData.citizenid or tostring(src)
end

local function AddMoney(src, amount)
    local p = GetQBPlayer(src)
    if p then p.Functions.AddMoney(Config.MoneyType, amount, 'f1-prize') end
end

local function RemoveMoney(src, amount)
    local p = GetQBPlayer(src)
    if not p then return false end
    if p.Functions.GetMoney(Config.MoneyType) < amount then return false end
    p.Functions.RemoveMoney(Config.MoneyType, amount, 'f1-fee')
    return true
end

local function HasItem(src, item)
    local p = GetQBPlayer(src)
    return p and p.Functions.GetItemByName(item) ~= nil
end

local function RemoveItem(src, item, amt)
    local p = GetQBPlayer(src)
    if p then p.Functions.RemoveItem(item, amt or 1) end
end

-- ── Leaderboard snapshot ─────────────────────────────────────
local function BuildSnapshot()
    local list = {}
    for id, d in pairs(racers) do
        list[#list+1] = {
            id=id, name=d.name, lap=d.lap, cp=d.cp,
            score=RacerScore(d), finished=d.finished, dq=d.dq,
            time=(d.finishTime and FmtRaceTime(d.finishTime) or nil),
            pos=d.finishPos, dqReason=d.dqReason,
        }
    end
    table.sort(list, function(a,b)
        if a.finished ~= b.finished then return a.finished end
        if a.dq ~= b.dq then return not a.dq end
        return (a.score or 0) > (b.score or 0)
    end)
    return list
end

local function BroadcastLeaderboard()
    local snap = BuildSnapshot()
    local leaderScore = (snap[1] and snap[1].score) or 0
    for _, pid in ipairs(GetActivePlayers()) do
        local key = tostring(pid)
        local gap = nil
        if racers[key] then
            if snap[1] and snap[1].id == key then
                gap = 'LEADER'
            else
                local diff = leaderScore - RacerScore(racers[key])
                gap = diff > 0 and string.format('+%d CP', diff) or 'LEADER'
            end
        end
        TriggerClientEvent('fcrp_f1:cl:updateLeaderboard', pid, snap, gap)
    end
end

-- ============================================================
-- DB: PLAYER STATS
-- ============================================================
local function GetOrCreate(cid, cb)
    MySQL.Async.fetchAll(
        'SELECT * FROM f1_players WHERE citizenid=@c', { ['@c']=cid },
        function(rows)
            if rows and rows[1] then
                cb(rows[1])
            else
                MySQL.Async.execute(
                    'INSERT INTO f1_players (citizenid) VALUES (@c)',
                    { ['@c']=cid },
                    function()
                        cb({ citizenid=cid, mmr=1500, xp=0, wins=0, races=0, podiums=0,
                             fastest_laps=0, best_lap_ms=nil,
                             stats='{}', achievements='{}', mmr_history='[]', weekly_claimed=0 })
                    end
                )
            end
        end
    )
end

-- ── ELO-style MMR calculation ────────────────────────────────
local function CalcMmrDelta(position, totalDrivers, isDQ)
    if isDQ then return Config.MmrLostBase * (totalDrivers + 1) end
    local base = Config.MmrGain[position] or (Config.MmrLostBase * position)
    -- Scale win bonus by field size (more drivers = more rewarding to win)
    if position == 1 and totalDrivers > 2 then
        base = base + math.floor((totalDrivers - 2) * 5)
    end
    return base
end

-- ── Persist race result ──────────────────────────────────────
local function PersistResult(cid, src, raceData, position, isDQ, xpEarned, mmrDelta)
    local totalDrivers = 0
    for _ in pairs(racers) do totalDrivers = totalDrivers + 1 end

    GetOrCreate(cid, function(stats)
        -- Update flat columns
        local newMmr       = math.max(0, (stats.mmr or 1500) + mmrDelta)
        local newXp        = (stats.xp or 0) + xpEarned
        local newWins      = (stats.wins or 0) + (position == 1 and 1 or 0)
        local newRaces     = (stats.races or 0) + 1
        local newPodiums   = (stats.podiums or 0) + ((position <= 3 and not isDQ) and 1 or 0)
        local newFL        = (stats.fastest_laps or 0) + ((raceData and raceData.setFastestLap) and 1 or 0)
        local newBestLap   = stats.best_lap_ms
        if raceData and raceData.fastestLapMs then
            if not newBestLap or raceData.fastestLapMs < newBestLap then
                newBestLap = raceData.fastestLapMs
            end
        end

        -- MMR history (cap at MaxMmrHistory)
        local mmrHist = {}
        local ok, parsed = pcall(json.decode, stats.mmr_history or '[]')
        if ok and parsed then mmrHist = parsed end
        table.insert(mmrHist, 1, { mmr=newMmr, delta=mmrDelta, date=os.date('%Y-%m-%d') })
        if #mmrHist > Config.MaxMmrHistory then
            while #mmrHist > Config.MaxMmrHistory do table.remove(mmrHist) end
        end

        -- Stat JSON increments
        local statObj = {}
        local ok2, s2 = pcall(json.decode, stats.stats or '{}')
        if ok2 and s2 then statObj = s2 end
        statObj.pit_stops  = (statObj.pit_stops or 0) + (raceData and raceData.pitCount or 0)
        statObj.drs_uses   = (statObj.drs_uses or 0) + (raceData and raceData.drsCount or 0)
        statObj.clean_races= (statObj.clean_races or 0) + ((raceData and raceData.engineOk) and 1 or 0)
        statObj.consec_wins= position == 1 and ((statObj.consec_wins or 0) + 1) or 0

        MySQL.Async.execute([[
            UPDATE f1_players SET
                mmr=@mmr, xp=@xp, wins=@w, races=@r, podiums=@p,
                fastest_laps=@fl, best_lap_ms=@bl,
                stats=@st, mmr_history=@mh
            WHERE citizenid=@c
        ]], {
            ['@mmr']=newMmr, ['@xp']=newXp, ['@w']=newWins, ['@r']=newRaces,
            ['@p']=newPodiums, ['@fl']=newFL, ['@bl']=newBestLap,
            ['@st']=json.encode(statObj), ['@mh']=json.encode(mmrHist), ['@c']=cid
        })

        -- Race history row
        MySQL.Async.execute([[
            INSERT INTO f1_race_history
                (race_id,citizenid,position,total_laps,race_time,best_lap,
                 sector_times,tyre_used,pit_count,drs_count,engine_ok,
                 xp_earned,mmr_delta,dq,dq_reason)
            VALUES (@rid,@cid,@pos,@laps,@rt,@bl,@st,@ty,@pc,@dc,@eo,@xp,@md,@dq,@dr)
        ]], {
            ['@rid']=currentRaceId, ['@cid']=cid, ['@pos']=position,
            ['@laps']=Config.MaxLaps,
            ['@rt']=(raceData and raceData.raceTime or nil),
            ['@bl']=(raceData and raceData.bestLapStr or nil),
            ['@st']=json.encode(raceData and raceData.sectorTimes or {}),
            ['@ty']=(raceData and raceData.tyre or 'medium'),
            ['@pc']=(raceData and raceData.pitCount or 0),
            ['@dc']=(raceData and raceData.drsCount or 0),
            ['@eo']=(raceData and raceData.engineOk and 1 or 0),
            ['@xp']=xpEarned, ['@md']=mmrDelta,
            ['@dq']=(isDQ and 1 or 0), ['@dr']=(isDQ and raceData and raceData.dqReason or nil),
        })

        -- Check achievements
        CheckAchievements(src, cid, newWins, newRaces, newPodiums, newFL, newMmr, statObj, stats.achievements or '{}')
    end)
end

-- ============================================================
-- ACHIEVEMENTS
-- ============================================================
local function UnlockAchievement(src, cid, key)
    local def = nil
    for _, a in ipairs(Config.Achievements) do
        if a.key == key then def = a; break end
    end
    if not def then return end

    -- Persist
    MySQL.Async.fetchAll('SELECT achievements FROM f1_players WHERE citizenid=@c', {['@c']=cid}, function(rows)
        if not rows or not rows[1] then return end
        local obj = {}
        local ok, parsed = pcall(json.decode, rows[1].achievements or '{}')
        if ok and parsed then obj = parsed end
        if obj[key] then return end   -- already unlocked
        obj[key] = os.time()
        MySQL.Async.execute('UPDATE f1_players SET achievements=@a WHERE citizenid=@c',
            {['@a']=json.encode(obj), ['@c']=cid})
        -- Notify player
        local msg = (Config.Notify.achievement):gsub('{label}', def.icon..' '..def.label)
        TriggerClientEvent('ox_lib:notify', src, {
            title='Achievement Unlocked', description=msg, type='success', duration=6000
        })
        if OpenServerFunctions and OpenServerFunctions.OnAchievementUnlocked then
            OpenServerFunctions.OnAchievementUnlocked(src, key, def)
        end
        DBG('Achievement unlocked:', cid, key)
    end)
end

function CheckAchievements(src, cid, wins, races, podiums, fastestLaps, mmr, statObj, achieveJson)
    local existing = {}
    local ok, parsed = pcall(json.decode, achieveJson or '{}')
    if ok and parsed then existing = parsed end

    local function Try(key)
        if not existing[key] then UnlockAchievement(src, cid, key) end
    end

    -- Wins
    if wins >= 1   then Try('win_1')   end
    if wins >= 5   then Try('win_5')   end
    if wins >= 25  then Try('win_25')  end
    if wins >= 50  then Try('win_50')  end
    -- Podiums
    if podiums >= 10 then Try('podium_10') end
    if podiums >= 50 then Try('podium_50') end
    -- Races
    if races >= 10  then Try('races_10')  end
    if races >= 50  then Try('races_50')  end
    if races >= 100 then Try('races_100') end
    -- Fastest laps
    if fastestLaps >= 1  then Try('fastest_lap_1')  end
    if fastestLaps >= 10 then Try('fastest_lap_10') end
    -- Pit stops
    local pits = statObj.pit_stops or 0
    if pits >= 5  then Try('pit_5')  end
    if pits >= 25 then Try('pit_25') end
    -- Clean races
    local clean = statObj.clean_races or 0
    if clean >= 1  then Try('clean_race_1')  end
    if clean >= 10 then Try('clean_race_10') end
    -- DRS
    local drs = statObj.drs_uses or 0
    if drs >= 50 then Try('drs_50') end
    -- MMR
    if mmr >= 2000 then Try('mmr_2000') end
    if mmr >= 3000 then Try('mmr_3000') end
    -- Consecutive wins
    local cw = statObj.consec_wins or 0
    if cw >= 3 then Try('hat_trick') end
end

-- ============================================================
-- DISCORD WEBHOOK
-- ============================================================
local function SendWebhook()
    if not Config.DiscordWebhook or Config.DiscordWebhook == 'YOUR_WEBHOOK_URL_HERE' then return end
    local medals = {'🥇','🥈','🥉'}
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

    local flLine = fastestLapHolder and
        string.format('\n**⚡ Fastest Lap:** %s — `%s`', fastestLapHolder, FmtTime(fastestLapMs)) or ''

    local desc = string.format('**%s**  ·  Race ID: `%s`\n\n**🏁 Results**\n%s%s\n**🚫 Disqualified**\n%s',
        os.date('%d %b %Y · %H:%M'), currentRaceId, podium, flLine, dqLines)

    local body = {
        username = Config.WebhookBotName or 'Flame City GP',
        embeds   = {{ title='Flame City Grand Prix — Race Summary', description=desc,
                      color=16766720, footer={ text='fcrp_f1 v3.0 · FiveM' } }}
    }
    if Config.WebhookAvatar and Config.WebhookAvatar ~= '' then body.avatar_url = Config.WebhookAvatar end

    PerformHttpRequest(Config.DiscordWebhook,
        function(code) print(code==204 and '^2[F1]^7 Webhook OK' or '^1[F1]^7 Webhook HTTP '..tostring(code)) end,
        'POST', json.encode(body), {['Content-Type']='application/json'})
end

-- ============================================================
-- RESULTS SCREEN
-- ============================================================
local function ShowResultsAndTeleport()
    local snap  = BuildSnapshot()
    local delay = Config.ResultsScreenDelay or 20
    local medals= {'🥇','🥈','🥉'}

    local rows = {}
    for _, entry in ipairs(snap) do
        local gap = ''
        if entry.pos and entry.pos > 1 and finishOrder[entry.pos] and finishOrder[1] then
            gap = string.format('+%.2fs', finishOrder[entry.pos].rawTime - finishOrder[1].rawTime)
        elseif entry.pos == 1 then gap = 'WINNER' end

        rows[#rows+1] = {
            name=entry.name, pos=entry.pos, time=entry.time, gap=gap,
            dq=entry.dq, dqReason=entry.dqReason,
        }
    end

    TriggerClientEvent('fcrp_f1:cl:showResults', -1, {
        results  = rows,
        subtitle = string.format('FLAME CITY GRAND PRIX  ·  %s', currentRaceId),
        delay    = delay,
        flHolder = fastestLapHolder,
        flTime   = FmtTime(fastestLapMs),
        xpTable  = Config.XP,
        mmrTable = Config.MmrGain,
        winXp    = Config.WinXP or Config.XP[1],
    })

    -- ox_lib notify backup
    local lines = ''
    for _, e in ipairs(snap) do
        if e.dq then
            lines = lines .. string.format('❌ DQ  %s\n', e.name)
        else
            lines = lines .. string.format('%s  %s  %s\n',
                medals[e.pos] or ('P'..e.pos), e.name, e.time or '?')
        end
    end
    TriggerClientEvent('ox_lib:notify', -1, {
        title='🏁 Race Results — '..currentRaceId, description=lines,
        type='inform', duration=delay*1000, position='top',
    })

    SetTimeout(delay * 1000, function()
        for id, data in pairs(racers) do
            if data.finished and not data.dq then
                local numId = tonumber(id)
                if numId then TriggerClientEvent('fcrp_f1:cl:teleportPostRace', numId) end
            end
        end
        racers = {}
        currentRaceId = NewRaceId()   -- ready for next session
        print('^2[F1]^7 Session ended. New race ID: '..currentRaceId)
    end)
end

-- ── Check if all done ────────────────────────────────────────
local function CheckSessionEnd()
    local total, done = 0, 0
    for _, d in pairs(racers) do
        total = total + 1
        if d.finished or d.dq then done = done + 1 end
    end
    if total > 0 and done >= total then
        raceInProgress = false
        SendWebhook()
        ShowResultsAndTeleport()
        if OpenServerFunctions and OpenServerFunctions.OnRaceSessionEnd then
            OpenServerFunctions.OnRaceSessionEnd(finishOrder, dqList)
        end
    end
end

-- ============================================================
-- NPC MENU REQUEST
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:requestMenuOpen', function()
    local src = source
    if IsOrganiser(src) then
        local list = {}
        for _, pid in ipairs(GetActivePlayers()) do
            local n = GetPlayerName(pid)
            if n then list[#list+1] = {id=pid, name=n} end
        end
        TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu', src, list)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title='Race Manager', description='No active race right now.', type='inform'
        })
    end
end)

RegisterNetEvent('fcrp_f1:sv:requestMyStats', function()
    local src = source
    local cid = GetCid(src)
    GetOrCreate(cid, function(stats)
        -- Fetch last 5 race history entries
        MySQL.Async.fetchAll([[
            SELECT position, race_time, best_lap, tyre_used,
                   pit_count, xp_earned, mmr_delta, dq, race_date
            FROM f1_race_history WHERE citizenid=@c
            ORDER BY race_date DESC LIMIT 5
        ]], {['@c']=cid}, function(history)
            TriggerClientEvent('fcrp_f1:cl:openStatsMenu', src, stats, history or {})
        end)
    end)
end)

RegisterNetEvent('fcrp_f1:sv:requestLeaderboard', function()
    local src = source
    MySQL.Async.fetchAll([[
        SELECT citizenid, mmr, xp, wins, races, podiums, fastest_laps, best_lap_ms
        FROM f1_players ORDER BY mmr DESC LIMIT 20
    ]], {}, function(rows)
        TriggerClientEvent('fcrp_f1:cl:showLeaderboard', src, rows or {})
    end)
end)

-- ============================================================
-- /f1menu  COMMAND
-- ============================================================
lib.addCommand('f1menu', {help='Open Race Control panel'}, function(source)
    local src = source
    if not IsOrganiser(src) then
        TriggerClientEvent('ox_lib:notify', src, {title='Access Denied', type='error'}); return
    end
    local list = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local n = GetPlayerName(pid)
        if n then list[#list+1] = {id=pid, name=n} end
    end
    TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu', src, list)
end)

-- ============================================================
-- SLOT ASSIGNMENT
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:assignSlot', function(slot, targetId)
    local src = source
    if not IsOrganiser(src) then return end
    targetId = tonumber(targetId); slot = tonumber(slot)
    if not targetId or not slot or slot < 1 or slot > #Config.GridSpots then
        TriggerClientEvent('ox_lib:notify', src, {title='Invalid Input', type='error'}); return
    end
    local name = GetPlayerName(targetId)
    if not name then
        TriggerClientEvent('ox_lib:notify', src, {title='Not Found', description='ID '..targetId..' not online', type='error'}); return
    end
    if Config.Items.enabled then
        if not HasItem(targetId, Config.Items.entryItem) then
            TriggerClientEvent('ox_lib:notify', src, {
                title='Missing Item',
                description=string.format('%s needs a %s', name, Config.Items.entryItem),
                type='error'}); return
        end
        RemoveItem(targetId, Config.Items.entryItem, 1)
    end
    if OpenServerFunctions and OpenServerFunctions.CanAssignSlot then
        if not OpenServerFunctions.CanAssignSlot(targetId, slot) then
            TriggerClientEvent('ox_lib:notify', src, {title='Blocked by hook', type='error'}); return
        end
    end
    pendingGrid[slot] = targetId
    TriggerClientEvent('fcrp_f1:cl:slotAssigned', src, slot, targetId, name)
    TriggerClientEvent('ox_lib:notify', src, {
        title='Assigned', description=string.format('P%d → %s (ID %d)', slot, name, targetId), type='success'
    })
end)

RegisterNetEvent('fcrp_f1:sv:clearGrid', function()
    local src = source
    if not IsOrganiser(src) then return end
    pendingGrid = {}
    TriggerClientEvent('ox_lib:notify', src, {title='Grid Cleared', type='inform'})
end)

-- ============================================================
-- GRID SETUP
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:setupGrid', function()
    local src = source
    if not IsOrganiser(src) then return end

    TriggerClientEvent('fcrp_f1:cl:cleanupCars', -1)
    racers={}; finishOrder={}; dqList={}
    raceInProgress=false; raceStartTime=nil; gridAssignments={}
    fastestLapHolder=nil; fastestLapMs=nil
    currentRaceId = NewRaceId()

    local placed = 0
    for slot = 1, #Config.GridSpots do
        local tid  = pendingGrid[slot]
        local spot = Config.GridSpots[slot]
        if tid then
            local name = GetPlayerName(tid)
            if name then
                local cid = GetCid(tid)
                TriggerClientEvent('fcrp_f1:cl:spawnYourCar', tid, spot)
                racers[tostring(tid)] = {
                    name=name, cid=cid, lap=1, cp=1, score=1,
                    finished=false, dq=false, dqReason=nil,
                    finishTime=nil, finishPos=nil, pitDone=false, gridSlot=slot,
                    fastestLapMs=nil, currentLapStart=nil, lapTimes={},
                    sectorTimes={}, currentSectorStart=nil,
                    drsCount=0, engineOk=true, pitCount=0, currentTyre='medium',
                    setFastestLap=false,
                }
                gridAssignments[slot] = tid
                placed = placed + 1
                if OpenServerFunctions and OpenServerFunctions.OnDriverGridded then
                    OpenServerFunctions.OnDriverGridded(tid, slot, cid)
                end
            end
        end
    end

    BroadcastLeaderboard()
    TriggerClientEvent('ox_lib:notify', src, {
        title='Grid Ready',
        description=string.format('%d driver(s) on the grid — Race %s', placed, currentRaceId),
        type='success'
    })
    print(string.format('^2[F1]^7 Grid set. %d drivers. Race ID: %s', placed, currentRaceId))
end)

-- ============================================================
-- SAFETY CAR / FORMATION LAP
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:deploySafetyCar', function()
    local src = source
    if not IsOrganiser(src) then return end
    if next(racers) == nil then
        TriggerClientEvent('ox_lib:notify', src, {title='No Grid', description='Prepare grid first.', type='error'}); return
    end
    scOrganiser = src
    TriggerClientEvent('fcrp_f1:cl:spawnSafetyCar', src)
    SetTimeout(1500, function()
        TriggerClientEvent('fcrp_f1:cl:beginFormationLap', -1)
    end)
    TriggerClientEvent('ox_lib:notify', -1, {
        title='🟡 Safety Car', description='Follow the SC — race starts when it returns.', type='inform', duration=6000
    })
end)

RegisterNetEvent('fcrp_f1:sv:formationLapDone', function()
    local src = source
    TriggerClientEvent('fcrp_f1:cl:despawnSafetyCar', src)
    for id, data in pairs(racers) do
        local numId = tonumber(id)
        if numId and data.gridSlot then
            local spot = Config.GridSpots[data.gridSlot]
            if spot then TriggerClientEvent('fcrp_f1:cl:returnToGrid', numId, spot) end
        end
    end
    SetTimeout(4000, function()
        raceInProgress = true
        TriggerClientEvent('fcrp_f1:cl:startRace', -1)
        print('^2[F1]^7 Race started after formation lap.')
    end)
end)

RegisterNetEvent('fcrp_f1:sv:startGlobalRace', function()
    local src = source
    if not IsOrganiser(src) then return end
    if raceInProgress then
        TriggerClientEvent('ox_lib:notify', src, {title='Already Racing', type='warning'}); return
    end
    if next(racers) == nil then
        TriggerClientEvent('ox_lib:notify', src, {title='No Drivers', type='error'}); return
    end
    raceInProgress = true
    TriggerClientEvent('fcrp_f1:cl:endFormationLap', -1)
    TriggerClientEvent('fcrp_f1:cl:despawnSafetyCar', scOrganiser or src)
    scOrganiser = nil
    SetTimeout(2000, function()
        TriggerClientEvent('fcrp_f1:cl:startRace', -1)
    end)
    print('^2[F1]^7 Race force-started by '..GetPlayerName(src))
end)

-- ============================================================
-- RACE CLOCK
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:raceClockStart', function()
    local key = tostring(source)
    if not racers[key] or not raceInProgress then return end
    if not raceStartTime then
        raceStartTime = os.time()
        -- Initialise lap start times for everyone
        for _, d in pairs(racers) do
            d.currentLapStart   = raceStartTime
            d.currentSectorStart= raceStartTime
        end
        print('^2[F1]^7 Race clock started. ID: '..currentRaceId)
    end
end)

-- ============================================================
-- PROGRESS UPDATE
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:updateProgress', function(lap, cp)
    local key = tostring(source)
    if not racers[key] then return end
    racers[key].lap   = lap
    racers[key].cp    = cp
    racers[key].score = RacerScore(racers[key])
    BroadcastLeaderboard()
end)

-- ============================================================
-- LAP TIMING  (client sends lap time in ms on each lap complete)
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:lapComplete', function(lapMs, sectorData)
    local src = source
    local key = tostring(src)
    if not racers[key] then return end

    local d = racers[key]
    d.lapTimes[#d.lapTimes+1] = lapMs
    d.sectorTimes = sectorData or {}

    -- Check fastest lap of race
    if not fastestLapMs or lapMs < fastestLapMs then
        fastestLapMs    = lapMs
        fastestLapHolder= d.name
        d.setFastestLap = true
        d.fastestLapMs  = lapMs
        -- Award XP bonus and notify everyone
        local xpBonus = Config.FastestLapXP or 15
        TriggerClientEvent('ox_lib:notify', -1, {
            title = '💜 Fastest Lap',
            description = string.format('%s — %s  (+%d XP)', d.name, FmtTime(lapMs), xpBonus),
            type = 'inform', duration = 5000,
        })
        -- Give XP immediately (will also be counted in final PersistResult)
        MySQL.Async.execute('UPDATE f1_players SET xp=xp+@b WHERE citizenid=@c',
            {['@b']=xpBonus, ['@c']=d.cid})
        -- Tell the client to show purple sector flash
        TriggerClientEvent('fcrp_f1:cl:fastestLapSet', src, lapMs)
    end
    DBG(string.format('Lap complete: %s  %s', d.name, FmtTime(lapMs)))
end)

-- ============================================================
-- PIT STOP
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:pitStop', function(compound)
    local src = source
    if not Config.TireCompounds[compound] then return end
    local key = tostring(src)
    if racers[key] then
        racers[key].pitDone    = true
        racers[key].pitCount   = (racers[key].pitCount or 0) + 1
        racers[key].currentTyre= compound
    end
    TriggerClientEvent('fcrp_f1:cl:doPitStop', src, compound)
    if OpenServerFunctions and OpenServerFunctions.OnPitStop then
        OpenServerFunctions.OnPitStop(src, compound)
    end
    DBG(GetPlayerName(src)..' pitted for '..compound)
end)

-- ============================================================
-- DRS COUNTER
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:drsUsed', function()
    local key = tostring(source)
    if racers[key] then
        racers[key].drsCount = (racers[key].drsCount or 0) + 1
    end
end)

-- ============================================================
-- ENGINE DAMAGE FLAG
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:engineDamaged', function()
    local key = tostring(source)
    if racers[key] then racers[key].engineOk = false end
end)

-- ============================================================
-- DQ
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:dqPlayer', function(reason)
    local src  = source
    local name = GetPlayerName(src)
    local key  = tostring(src)

    if racers[key] then
        racers[key].dq       = true
        racers[key].dqReason = reason
        table.insert(dqList, {name=name, reason=reason})
    end

    TriggerClientEvent('ox_lib:notify', -1, {
        title='DISQUALIFIED', description=name..' — '..reason, type='error'
    })
    BroadcastLeaderboard()
    TriggerClientEvent('fcrp_f1:cl:teleportPostRace', src)

    -- Persist DQ result
    local d   = racers[key] or {}
    local cid = d.cid or GetCid(src)
    local totalDrivers = 0; for _ in pairs(racers) do totalDrivers = totalDrivers+1 end
    local mmrDelta = CalcMmrDelta(totalDrivers + 1, totalDrivers, true)
    d.dqReason = reason
    PersistResult(cid, src, d, totalDrivers + 1, true, 0, mmrDelta)

    if OpenServerFunctions and OpenServerFunctions.OnDriverDQ then
        OpenServerFunctions.OnDriverDQ(src, reason)
    end

    CheckSessionEnd()
end)

-- ============================================================
-- FINISH
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:finishRace', function(clientData)
    local src  = source
    local name = GetPlayerName(src)
    local key  = tostring(src)

    if not racers[key] or racers[key].finished then return end

    local now      = os.time()
    local position = #finishOrder + 1
    local timeStr  = FmtRaceTime(now)
    local cid      = racers[key].cid or GetCid(src)
    local d        = racers[key]

    d.finished   = true
    d.finishTime = now
    d.finishPos  = position

    -- Merge client-reported data (lap times, sector times, tyre, counts)
    if clientData then
        d.fastestLapMs = clientData.fastestLapMs or d.fastestLapMs
        d.sectorTimes  = clientData.sectorTimes  or d.sectorTimes
        d.currentTyre  = clientData.tyre          or d.currentTyre
        d.pitCount     = clientData.pitCount       or d.pitCount
        d.drsCount     = clientData.drsCount       or d.drsCount
        d.engineOk     = clientData.engineOk ~= nil and clientData.engineOk or d.engineOk
    end
    d.raceTime     = timeStr
    d.bestLapStr   = d.fastestLapMs and FmtTime(d.fastestLapMs) or nil

    table.insert(finishOrder, {id=src, name=name, time=timeStr, rawTime=now-(raceStartTime or now)})

    -- Calc rewards
    local totalDrivers = 0; for _ in pairs(racers) do totalDrivers = totalDrivers+1 end
    local xpEarned = Config.XP[position] or (Config.XP[#Config.XP] or 1)
    if position == 1 then xpEarned = Config.WinXP or xpEarned end
    if d.setFastestLap then xpEarned = xpEarned + (Config.FastestLapXP or 0) end
    local mmrDelta = CalcMmrDelta(position, totalDrivers, false)

    PersistResult(cid, src, d, position, false, xpEarned, mmrDelta)

    -- Prize
    if position == 1 then
        exports.ox_inventory:AddItem(src, Config.PrizeItem, Config.PrizeMoney)
        TriggerClientEvent('ox_lib:notify', -1, {
            title='🏁 Race Winner!',
            description=string.format('%s wins!  +$%d  +%d XP', name, Config.PrizeMoney, xpEarned),
            type='success'
        })
    end

    -- Personal finish notify
    local mmrSign = mmrDelta >= 0 and '+' or ''
    TriggerClientEvent('ox_lib:notify', src, {
        title=string.format('P%d Finish', position),
        description=string.format('%s  |  +%d XP  |  %s%d MMR', timeStr, xpEarned, mmrSign, mmrDelta),
        type=(position == 1) and 'success' or 'inform'
    })

    BroadcastLeaderboard()
    print(string.format('^2[F1]^7 P%d: %s — %s (+%d XP, %+d MMR)', position, name, timeStr, xpEarned, mmrDelta))

    if OpenServerFunctions and OpenServerFunctions.OnRaceFinish then
        OpenServerFunctions.OnRaceFinish(src, position, timeStr, xpEarned, mmrDelta)
    end

    CheckSessionEnd()
end)

-- ============================================================
-- RACE DIRECTOR CAM
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:getVehicleForCam', function(targetId)
    local src = source
    if not IsOrganiser(src) then return end
    local ped = GetPlayerPed(targetId)
    if not ped or ped == 0 then
        TriggerClientEvent('ox_lib:notify', src, {title='Cam Error', description='Player not found', type='error'}); return
    end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        TriggerClientEvent('ox_lib:notify', src, {title='Cam Error', description='Not in vehicle', type='error'}); return
    end
    TriggerClientEvent('fcrp_f1:cl:attachDirectorCam', src, NetworkGetNetworkIdFromEntity(veh))
end)

-- ============================================================
-- FORCE END
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:forceEnd', function()
    local src = source
    if not IsOrganiser(src) then return end
    TriggerClientEvent('fcrp_f1:cl:cleanupCars', -1)
    if scOrganiser then TriggerClientEvent('fcrp_f1:cl:despawnSafetyCar', scOrganiser); scOrganiser=nil end
    racers={}; finishOrder={}; dqList={}
    raceInProgress=false; raceStartTime=nil; pendingGrid={}
    fastestLapHolder=nil; fastestLapMs=nil
    currentRaceId = NewRaceId()
    TriggerClientEvent('ox_lib:notify', -1, {title='Race Reset', description='Organiser ended session.', type='warning'})
    print('^3[F1]^7 Force end by '..GetPlayerName(src))
end)

-- ============================================================
-- COMMANDS
-- ============================================================
lib.addCommand('f1stats', {help='View your F1 stats'}, function(source)
    local src = source
    local cid = GetCid(src)
    GetOrCreate(cid, function(stats)
        TriggerClientEvent('chat:addMessage', src, {args={
            string.format('[F1]  MMR: %d | XP: %d | Wins: %d | Races: %d | Podiums: %d | FL: %d',
                stats.mmr, stats.xp, stats.wins, stats.races, stats.podiums, stats.fastest_laps)
        }})
    end)
end)

lib.addCommand('f1top', {help='F1 MMR leaderboard'}, function(source)
    local src = source
    MySQL.Async.fetchAll(
        'SELECT citizenid, mmr, wins, races FROM f1_players ORDER BY mmr DESC LIMIT 10',
        {}, function(rows)
            if not rows or #rows == 0 then
                TriggerClientEvent('chat:addMessage', src, {args={'[F1]', 'No data yet.'}}); return
            end
            TriggerClientEvent('chat:addMessage', src, {args={'[F1]', '── Top 10 Drivers ──'}})
            for i, row in ipairs(rows) do
                TriggerClientEvent('chat:addMessage', src, {args={
                    string.format('#%d  %s  MMR: %d  Wins: %d  Races: %d',
                        i, row.citizenid, row.mmr, row.wins, row.races)
                }})
            end
        end
    )
end)

lib.addCommand('f1reward', {help='Claim weekly F1 reward'}, function(source)
    local src = source
    local cid = GetCid(src)
    local now, week = os.time(), 7*24*3600
    GetOrCreate(cid, function(stats)
        if (now - stats.weekly_claimed) < week then
            local hours = math.floor((week - (now - stats.weekly_claimed)) / 3600)
            TriggerClientEvent('ox_lib:notify', src, {
                title='Weekly Reward',
                description=(Config.Notify.weeklyNotReady):gsub('{hours}', hours),
                type='inform'}); return
        end
        local r = Config.WeeklyReward
        if r.type == 'money' then
            local p = GetQBPlayer(src)
            if p then p.Functions.AddMoney(Config.MoneyType, r.money, 'f1-weekly') end
        elseif r.type == 'item' then
            exports.ox_inventory:AddItem(src, r.item.name, r.item.amount)
        end
        MySQL.Async.execute('UPDATE f1_players SET weekly_claimed=@t WHERE citizenid=@c',
            {['@t']=now, ['@c']=cid})
        TriggerClientEvent('ox_lib:notify', src, {title='Weekly Reward', description=Config.Notify.weeklyReward, type='success'})
    end)
end)

lib.addCommand('createf1crew', {
    help='Create an F1 crew',
    params={{ name='crewname', help='Crew name', type='string' }}
}, function(source, args)
    if not Config.CrewSystem.enabled then return end
    local src, name = source, args.crewname
    if not name or name == '' then return end
    if not RemoveMoney(src, Config.CrewSystem.createCost) then
        TriggerClientEvent('ox_lib:notify', src, {title='Not Enough Money', type='error'}); return
    end
    local cid = GetCid(src)
    MySQL.Async.execute(
        'INSERT INTO f1_crews (name,leader,members) VALUES (@n,@l,@m)',
        {['@n']=name, ['@l']=cid, ['@m']=json.encode({cid})},
        function(rc)
            if rc > 0 then
                TriggerClientEvent('ox_lib:notify', src, {
                    title='Crew Created',
                    description=(Config.Notify.crewCreated):gsub('{name}', name),
                    type='success'
                })
            end
        end
    )
end)

-- ============================================================
-- AUTO-RACE SCHEDULE  (day-of-week + time)
-- ============================================================
local scheduledWarned = {}  -- prevent duplicate warnings

CreateThread(function()
    while true do
        Wait(30000)
        if Config.RaceSchedule then
            local day  = os.date('%A')  -- 'Monday' etc
            local hh   = tonumber(os.date('%H'))
            local mm   = tonumber(os.date('%M'))
            local now  = string.format('%02d:%02d', hh, mm)

            local schedule = Config.RaceSchedule[day] or {}
            for _, entry in ipairs(schedule) do
                -- Warn 10 minutes before
                local warnH, warnM = hh, mm + 10
                if warnM >= 60 then warnH = warnH + 1; warnM = warnM - 60 end
                local warnKey = entry.time..'_warn'
                local warnTime= string.format('%02d:%02d', warnH, warnM)

                if warnTime == entry.time and not scheduledWarned[warnKey] then
                    scheduledWarned[warnKey] = true
                    TriggerClientEvent('ox_lib:notify', -1, {
                        title='🏁 Official Race',
                        description=(Config.Notify.scheduleWarning):gsub('{mins}', '10'),
                        type='inform', duration=8000
                    })
                end
                -- Trigger race
                if now == entry.time then
                    if not raceInProgress and next(racers) ~= nil then
                        raceInProgress = true
                        TriggerClientEvent('fcrp_f1:cl:startRace', -1)
                        print('^3[F1]^7 Scheduled race started: '..day..' '..entry.time)
                        scheduledWarned = {}  -- reset for next round
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- PLAYER DISCONNECT — fix the session-softlock bug
-- ============================================================
AddEventHandler('playerDropped', function()
    local src = source
    local key = tostring(src)
    if not racers[key] then return end

    local d   = racers[key]
    d.dq       = true
    d.dqReason = 'Disconnected'
    table.insert(dqList, {name=d.name, reason='Disconnected'})

    -- Persist disconnect as DNF
    local totalDrivers = 0; for _ in pairs(racers) do totalDrivers = totalDrivers+1 end
    local mmrDelta = CalcMmrDelta(totalDrivers + 1, totalDrivers, true)
    PersistResult(d.cid, src, d, totalDrivers + 1, true, 0, mmrDelta)

    BroadcastLeaderboard()
    TriggerClientEvent('ox_lib:notify', -1, {
        title='Driver Out', description=d.name..' disconnected.', type='warning'
    })
    DBG('Player '..src..' dropped mid-race — DQ applied, session checked.')

    -- This now correctly fires even when the last human is gone
    CheckSessionEnd()
end)

print('^2[FCRP_F1]^7 Server v3.0 loaded.')
