-- ============================================================
--  FLAME CITY F1 — server/main.lua
--  v4.1  |  Qbox · oxmysql · ox_lib
--
--  V4.1 additions:
--    • Full Crew System  (create, invite, accept, kick, leave, disband,
--                         transfer captain, crew XP, tag on HUD)
--    • Entry Fee System  (per-session fee, pot payout to P1, organiser
--                         can set fee via NUI before assigning slots)
--    • Live HUD enrichment  (tyre + crew tag in leaderboard snapshot,
--                            sv:requestLiveHUD for spectator panel)
-- ============================================================

-- ─────────────────────────────────────────────────────────────────
-- RACE SESSION STATE
-- ─────────────────────────────────────────────────────────────────
local racers          = {}     -- [str(src)] = racer data table
local raceInProgress  = false
local raceStartTime   = nil
local finishOrder     = {}     -- { id, name, time, rawTime }
local dqList          = {}
local pendingGrid     = {}     -- [slot] = serverId
local gridAssignments = {}     -- [slot] = serverId
local scOrganiser     = nil
local fastestLapHolder= nil
local fastestLapMs    = nil

-- ─────────────────────────────────────────────────────────────────
-- ENTRY FEE SESSION STATE
-- ─────────────────────────────────────────────────────────────────
local currentEntryFee = 0      -- fee charged per driver this session
local feePot          = 0      -- accumulated pot from all assigned drivers
local feePayers       = {}     -- [cid] = amount paid (for refund on clearGrid)

-- ─────────────────────────────────────────────────────────────────
-- CREW INVITE CACHE  (in-memory, TTL 5 minutes)
-- ─────────────────────────────────────────────────────────────────
local pendingInvites  = {}     -- [inviteeSrc] = { crewId, crewName, inviterName, expires }

-- ─────────────────────────────────────────────────────────────────
-- SPECTATORS
-- ─────────────────────────────────────────────────────────────────
local spectators = {}          -- [src] = true

-- ─────────────────────────────────────────────────────────────────
-- RACE ID
-- ─────────────────────────────────────────────────────────────────
local function NewRaceId()
    return string.format('F1-%s-%04d', os.date('%Y%m%d'), math.random(1000, 9999))
end
local currentRaceId = NewRaceId()

-- ============================================================
-- DATABASE INIT  (idempotent — safe to run on every server start)
-- ============================================================
CreateThread(function()

    -- ── Core player stats ────────────────────────────────────
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
            crew_id        INT          DEFAULT NULL,
            stats          JSON         NOT NULL DEFAULT '{}',
            achievements   JSON         NOT NULL DEFAULT '{}',
            mmr_history    JSON         NOT NULL DEFAULT '[]',
            weekly_claimed BIGINT       NOT NULL DEFAULT 0
        )
    ]], {})

    -- ── Safe migration: add crew_id if upgrading from v3 ─────
    MySQL.Async.execute([[
        ALTER TABLE f1_players
        ADD COLUMN IF NOT EXISTS crew_id INT DEFAULT NULL
    ]], {})

    -- ── Race history ──────────────────────────────────────────
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
            INDEX idx_cid  (citizenid),
            INDEX idx_race (race_id)
        )
    ]], {})

    -- ── Crews ────────────────────────────────────────────────
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS f1_crews (
            id          INT          AUTO_INCREMENT PRIMARY KEY,
            name        VARCHAR(100) NOT NULL UNIQUE,
            tag         VARCHAR(6)   NOT NULL DEFAULT '',
            color       VARCHAR(7)   NOT NULL DEFAULT '#a855f7',
            leader_cid  VARCHAR(50)  NOT NULL,
            members     JSON         NOT NULL DEFAULT '[]',
            xp          INT          NOT NULL DEFAULT 0,
            description VARCHAR(200) NOT NULL DEFAULT '',
            created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
        )
    ]], {})

    -- ── Safe migration: upgrade v3 f1_crews schema ────────────
    MySQL.Async.execute("ALTER TABLE f1_crews ADD COLUMN IF NOT EXISTS tag         VARCHAR(6)   NOT NULL DEFAULT ''",       {})
    MySQL.Async.execute("ALTER TABLE f1_crews ADD COLUMN IF NOT EXISTS color       VARCHAR(7)   NOT NULL DEFAULT '#a855f7'", {})
    MySQL.Async.execute("ALTER TABLE f1_crews ADD COLUMN IF NOT EXISTS xp          INT          NOT NULL DEFAULT 0",         {})
    MySQL.Async.execute("ALTER TABLE f1_crews ADD COLUMN IF NOT EXISTS description VARCHAR(200) NOT NULL DEFAULT ''",        {})
    MySQL.Async.execute("ALTER TABLE f1_crews ADD COLUMN IF NOT EXISTS created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP", {})
    -- Rename leader → leader_cid if old schema exists (best-effort)
    MySQL.Async.execute("ALTER TABLE f1_crews CHANGE COLUMN IF EXISTS leader leader_cid VARCHAR(50) NOT NULL", {})

    print('^2[FCRP_F1]^7 DB tables ensured (v4.1)')
end)

-- ============================================================
-- HELPERS
-- ============================================================

--- Debug log — only prints when Config.Debug = true
local function DBG(...)
    if Config and Config.Debug then
        print('^5[FCRP_F1]^3[SRV]^7', ...)
    end
end

--- Warning — always prints
local function DBGW(...)
    print('^5[FCRP_F1]^8[SRV ⚠]^7', ...)
end

--- Format milliseconds as M:SS.mmm
local function FmtMs(ms)
    if not ms then return '?' end
    local s = ms / 1000
    return string.format('%d:%06.3f', math.floor(s / 60), s % 60)
end

--- Format elapsed seconds as M:SS.mm
local function FmtRaceTime(ts)
    if not raceStartTime then return '?' end
    local s = ts - raceStartTime
    return string.format('%d:%05.2f', math.floor(s / 60), s % 60)
end

--- Race position score (higher = further ahead)
local function RacerScore(d)
    return ((d.lap or 1) - 1) * 1000 + (d.cp or 1)
end

--- Check if source is a race organiser
local function IsOrganiser(src)
    if not Config.OrganizerPermission then return true end
    if IsPlayerAceAllowed(src, Config.OrganizerPermission) then return true end
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    if ok and p then
        local g = p.PlayerData.group
        if g and (g == 'admin' or g == 'superadmin' or g == Config.OrganizerPermission) then
            return true
        end
    end
    return false
end

--- Safe Qbox player fetch
local function GetQBPlayer(src)
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return (ok and p) or nil
end

--- Get citizenid from server source
local function GetCid(src)
    local p = GetQBPlayer(src)
    return p and p.PlayerData.citizenid or tostring(src)
end

--- Add money to player
local function AddMoney(src, amount, reason)
    local p = GetQBPlayer(src)
    if p then p.Functions.AddMoney(Config.MoneyType, amount, reason or 'f1-reward') end
end

--- Remove money from player — returns true on success
local function RemoveMoney(src, amount, reason)
    local p = GetQBPlayer(src)
    if not p then return false end
    if p.Functions.GetMoney(Config.MoneyType) < amount then return false end
    p.Functions.RemoveMoney(Config.MoneyType, amount, reason or 'f1-fee')
    return true
end

--- Check if player has item
local function HasItem(src, item)
    local p = GetQBPlayer(src)
    return p and p.Functions.GetItemByName(item) ~= nil
end

--- Remove item from player
local function RemoveItem(src, item, amt)
    local p = GetQBPlayer(src)
    if p then p.Functions.RemoveItem(item, amt or 1) end
end

--- Notify a single player
local function Notify(src, title, desc, ntype, duration)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = title,
        description = desc,
        type        = ntype or 'inform',
        duration    = duration or 4000,
    })
end

--- Notify all players
local function NotifyAll(title, desc, ntype, duration)
    TriggerClientEvent('ox_lib:notify', -1, {
        title       = title,
        description = desc,
        type        = ntype or 'inform',
        duration    = duration or 4000,
    })
end

-- ============================================================
-- LEADERBOARD SNAPSHOT
-- Includes tyre + crew tag for NUI live HUD (V4.1)
-- ============================================================
local function BuildSnapshot()
    local list = {}
    for id, d in pairs(racers) do
        list[#list+1] = {
            id        = id,
            name      = d.name,
            lap       = d.lap,
            cp        = d.cp,
            score     = RacerScore(d),
            finished  = d.finished,
            dq        = d.dq,
            time      = (d.finishTime and FmtRaceTime(d.finishTime) or nil),
            pos       = d.finishPos,
            dqReason  = d.dqReason,
            -- V4.1 additions
            tyre      = d.currentTyre or 'medium',
            crewTag   = d.crewTag or '',
            pitDone   = d.pitDone or false,
            drsActive = d.drsActive or false,
        }
    end
    table.sort(list, function(a, b)
        if a.finished ~= b.finished then return a.finished end
        if a.dq       ~= b.dq       then return not a.dq end
        return (a.score or 0) > (b.score or 0)
    end)
    return list
end

--- Broadcast leaderboard + gap to all players
local function BroadcastLeaderboard()
    local snap       = BuildSnapshot()
    local leaderScore= (snap[1] and snap[1].score) or 0
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
-- PLAYER RECORD  (INSERT IGNORE + re-SELECT for race safety)
-- ============================================================
local function GetOrCreate(cid, cb)
    MySQL.Async.execute(
        'INSERT IGNORE INTO f1_players (citizenid) VALUES (@c)',
        { ['@c'] = cid },
        function()
            MySQL.Async.fetchAll(
                'SELECT * FROM f1_players WHERE citizenid=@c',
                { ['@c'] = cid },
                function(rows)
                    if rows and rows[1] then
                        cb(rows[1])
                    else
                        DBGW('GetOrCreate: row missing after INSERT IGNORE for cid=' .. tostring(cid))
                        cb({
                            citizenid   = cid, mmr = 1500, xp = 0, wins = 0,
                            races       = 0,   podiums = 0, fastest_laps = 0,
                            best_lap_ms = nil, crew_id = nil,
                            stats       = '{}', achievements = '{}',
                            mmr_history = '[]', weekly_claimed = 0,
                        })
                    end
                end
            )
        end
    )
end

-- ============================================================
-- ELO MMR CALCULATION
-- ============================================================
local function CalcMmrDelta(position, totalDrivers, isDQ)
    if isDQ then
        return Config.MmrLostBase * (totalDrivers + 1)
    end
    local base = Config.MmrGain[position] or (Config.MmrLostBase * position)
    -- Larger field = more rewarding win
    if position == 1 and totalDrivers > 2 then
        base = base + math.floor((totalDrivers - 2) * 5)
    end
    return base
end

-- ============================================================
-- PERSIST RACE RESULT
-- ============================================================
local function PersistResult(cid, src, raceData, position, isDQ, xpEarned, mmrDelta)
    local totalDrivers = 0
    for _ in pairs(racers) do totalDrivers = totalDrivers + 1 end

    GetOrCreate(cid, function(stats)
        local newMmr     = math.max(0, (stats.mmr or 1500) + mmrDelta)
        local newXp      = (stats.xp or 0) + xpEarned
        local newWins    = (stats.wins or 0) + (position == 1 and 1 or 0)
        local newRaces   = (stats.races or 0) + 1
        local newPodiums = (stats.podiums or 0) + ((position <= 3 and not isDQ) and 1 or 0)
        local newFL      = (stats.fastest_laps or 0) + ((raceData and raceData.setFastestLap) and 1 or 0)
        local newBestLap = stats.best_lap_ms
        if raceData and raceData.fastestLapMs then
            if not newBestLap or raceData.fastestLapMs < newBestLap then
                newBestLap = raceData.fastestLapMs
            end
        end

        -- MMR history (cap)
        local mmrHist = {}
        local ok1, parsed = pcall(json.decode, stats.mmr_history or '[]')
        if ok1 and parsed then mmrHist = parsed end
        table.insert(mmrHist, 1, { mmr = newMmr, delta = mmrDelta, date = os.date('%Y-%m-%d') })
        while #mmrHist > (Config.MaxMmrHistory or 20) do table.remove(mmrHist) end

        -- Stat JSON
        local statObj = {}
        local ok2, s2 = pcall(json.decode, stats.stats or '{}')
        if ok2 and s2 then statObj = s2 end
        statObj.pit_stops   = (statObj.pit_stops   or 0) + (raceData and raceData.pitCount   or 0)
        statObj.drs_uses    = (statObj.drs_uses    or 0) + (raceData and raceData.drsCount   or 0)
        statObj.clean_races = (statObj.clean_races or 0) + ((raceData and raceData.engineOk) and 1 or 0)
        statObj.consec_wins = position == 1 and ((statObj.consec_wins or 0) + 1) or 0

        MySQL.Async.execute([[
            UPDATE f1_players
            SET mmr=@mmr, xp=@xp, wins=@w, races=@r, podiums=@p,
                fastest_laps=@fl, best_lap_ms=@bl, stats=@st, mmr_history=@mh
            WHERE citizenid=@c
        ]], {
            ['@mmr']=newMmr,            ['@xp']=newXp,
            ['@w']=newWins,             ['@r']=newRaces,
            ['@p']=newPodiums,          ['@fl']=newFL,
            ['@bl']=newBestLap,         ['@st']=json.encode(statObj),
            ['@mh']=json.encode(mmrHist), ['@c']=cid,
        })

        -- Race history row
        MySQL.Async.execute([[
            INSERT INTO f1_race_history
                (race_id,citizenid,position,total_laps,race_time,best_lap,
                 sector_times,tyre_used,pit_count,drs_count,engine_ok,
                 xp_earned,mmr_delta,dq,dq_reason)
            VALUES (@rid,@cid,@pos,@laps,@rt,@bl,@st,@ty,@pc,@dc,@eo,@xp,@md,@dq,@dr)
        ]], {
            ['@rid'] = currentRaceId,
            ['@cid'] = cid,
            ['@pos'] = position,
            ['@laps']= Config.MaxLaps,
            ['@rt']  = (raceData and raceData.raceTime   or nil),
            ['@bl']  = (raceData and raceData.bestLapStr or nil),
            ['@st']  = json.encode(raceData and raceData.sectorTimes or {}),
            ['@ty']  = (raceData and raceData.currentTyre or 'medium'),
            ['@pc']  = (raceData and raceData.pitCount  or 0),
            ['@dc']  = (raceData and raceData.drsCount  or 0),
            ['@eo']  = (raceData and raceData.engineOk  and 1 or 0),
            ['@xp']  = xpEarned,
            ['@md']  = mmrDelta,
            ['@dq']  = (isDQ and 1 or 0),
            ['@dr']  = (isDQ and raceData and raceData.dqReason or nil),
        })

        -- Crew XP: award crew XP for podium finishes
        if not isDQ and position <= 3 and stats.crew_id then
            local crewXp = position == 1 and 50 or (position == 2 and 30 or 15)
            MySQL.Async.execute(
                'UPDATE f1_crews SET xp = xp + @x WHERE id = @id',
                { ['@x'] = crewXp, ['@id'] = stats.crew_id }
            )
            DBG(string.format('Crew %d +%d XP (P%d finish by %s)', stats.crew_id, crewXp, position, cid))
        end

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

    MySQL.Async.fetchAll(
        'SELECT achievements FROM f1_players WHERE citizenid=@c',
        { ['@c'] = cid },
        function(rows)
            if not rows or not rows[1] then return end
            local obj = {}
            local ok, parsed = pcall(json.decode, rows[1].achievements or '{}')
            if ok and parsed then obj = parsed end
            if obj[key] then return end
            obj[key] = os.time()
            MySQL.Async.execute(
                'UPDATE f1_players SET achievements=@a WHERE citizenid=@c',
                { ['@a'] = json.encode(obj), ['@c'] = cid }
            )
            local msg = (Config.Notify.achievement):gsub('{label}', def.icon .. ' ' .. def.label)
            Notify(src, 'Achievement Unlocked', msg, 'success', 6000)
            if OpenServerFunctions and OpenServerFunctions.OnAchievementUnlocked then
                OpenServerFunctions.OnAchievementUnlocked(src, key, def)
            end
            DBG('Achievement unlocked: ' .. cid .. ' → ' .. key)
        end
    )
end

function CheckAchievements(src, cid, wins, races, podiums, fl, mmr, statObj, achieveJson)
    local existing = {}
    local ok, parsed = pcall(json.decode, achieveJson or '{}')
    if ok and parsed then existing = parsed end
    local function Try(key)
        if not existing[key] then UnlockAchievement(src, cid, key) end
    end
    if wins    >= 1   then Try('win_1')        end
    if wins    >= 5   then Try('win_5')        end
    if wins    >= 25  then Try('win_25')       end
    if wins    >= 50  then Try('win_50')       end
    if podiums >= 10  then Try('podium_10')    end
    if podiums >= 50  then Try('podium_50')    end
    if races   >= 10  then Try('races_10')     end
    if races   >= 50  then Try('races_50')     end
    if races   >= 100 then Try('races_100')    end
    if fl      >= 1   then Try('fastest_lap_1')  end
    if fl      >= 10  then Try('fastest_lap_10') end
    local pits  = statObj.pit_stops   or 0
    local clean = statObj.clean_races or 0
    local drs   = statObj.drs_uses    or 0
    local cw    = statObj.consec_wins or 0
    if pits  >= 5   then Try('pit_5')          end
    if pits  >= 25  then Try('pit_25')         end
    if clean >= 1   then Try('clean_race_1')   end
    if clean >= 10  then Try('clean_race_10')  end
    if drs   >= 50  then Try('drs_50')         end
    if mmr   >= 2000 then Try('mmr_2000')      end
    if mmr   >= 3000 then Try('mmr_3000')      end
    if cw    >= 3   then Try('hat_trick')      end
end

-- ============================================================
-- DISCORD WEBHOOK
-- ============================================================
local function SendWebhook()
    if not Config.DiscordWebhook or Config.DiscordWebhook == 'YOUR_WEBHOOK_URL_HERE' then return end
    local medals  = { '🥇', '🥈', '🥉' }
    local podium  = ''
    local dqLines = ''
    for i, e in ipairs(finishOrder) do
        podium = podium .. string.format('%s  **%s** — `%s`\n', medals[i] or (i .. '.'), e.name, e.time)
    end
    if podium  == '' then podium  = '*No finishers*\n' end
    for _, e in ipairs(dqList) do
        dqLines = dqLines .. string.format('❌  **%s** — %s\n', e.name, e.reason)
    end
    if dqLines == '' then dqLines = '*None*\n' end
    local flLine = fastestLapHolder and
        string.format('\n**⚡ Fastest Lap:** %s — `%s`', fastestLapHolder, FmtMs(fastestLapMs)) or ''
    local potLine = feePot > 0 and
        string.format('\n**💰 Prize Pot:** $%s (entry fee $%s × %d drivers)',
            feePot, currentEntryFee, feePot / math.max(currentEntryFee, 1)) or ''
    local desc = string.format(
        '**%s**  ·  Race `%s`\n\n**🏁 Results**\n%s%s%s\n**🚫 Disqualified**\n%s',
        os.date('%d %b %Y · %H:%M'), currentRaceId,
        podium, flLine, potLine, dqLines
    )
    local body = {
        username   = Config.WebhookBotName or 'Flame City GP',
        embeds     = {{
            title       = 'Flame City Grand Prix — Race Summary',
            description = desc,
            color       = 11141290,   -- purple
            footer      = { text = 'fcrp_f1 v4.1 · FiveM' },
        }},
    }
    if Config.WebhookAvatar and Config.WebhookAvatar ~= '' then
        body.avatar_url = Config.WebhookAvatar
    end
    PerformHttpRequest(
        Config.DiscordWebhook,
        function(code)
            if code == 204 then
                print('^2[F1]^7 Webhook sent OK')
            else
                DBGW('Webhook HTTP ' .. tostring(code))
            end
        end,
        'POST', json.encode(body), { ['Content-Type'] = 'application/json' }
    )
end

-- ============================================================
-- RESULTS SCREEN + TELEPORT
-- ============================================================
local function ShowResultsAndTeleport()
    local snap  = BuildSnapshot()
    local delay = Config.ResultsScreenDelay or 20
    local rows  = {}

    for _, entry in ipairs(snap) do
        local gap = ''
        if entry.pos and entry.pos > 1 and finishOrder[entry.pos] and finishOrder[1] then
            gap = string.format('+%.2fs', finishOrder[entry.pos].rawTime - finishOrder[1].rawTime)
        elseif entry.pos == 1 then
            gap = 'WINNER'
        end
        rows[#rows+1] = {
            name      = entry.name,
            pos       = entry.pos,
            time      = entry.time,
            gap       = gap,
            dq        = entry.dq,
            dqReason  = entry.dqReason,
            crewTag   = entry.crewTag,
        }
    end

    TriggerClientEvent('fcrp_f1:cl:showResults_NUI', -1, {
        results  = rows,
        subtitle = string.format('FLAME CITY GRAND PRIX  ·  %s', currentRaceId),
        delay    = delay,
        flHolder = fastestLapHolder,
        flTime   = FmtMs(fastestLapMs),
        xpTable  = Config.XP,
        mmrTable = Config.MmrGain,
        winXp    = Config.WinXP or Config.XP[1],
        feePot   = feePot,          -- V4.1: show pot on results screen
        entryFee = currentEntryFee,
    })

    -- Notify spectators race is over
    for specSrc in pairs(spectators) do
        TriggerClientEvent('fcrp_f1:cl:raceEnded', specSrc)
    end
    spectators = {}

    -- Teleport after delay
    SetTimeout(delay * 1000, function()
        for id, data in pairs(racers) do
            if data.finished and not data.dq then
                local numId = tonumber(id)
                if numId then
                    TriggerClientEvent('fcrp_f1:cl:teleportPostRace', numId)
                end
            end
        end
        -- Reset fee state
        feePot          = 0
        currentEntryFee = Config.EntryFee and Config.EntryFee.defaultAmount or 0
        feePayers       = {}
        racers          = {}
        currentRaceId   = NewRaceId()
        print('^2[F1]^7 Session ended. New race ID: ' .. currentRaceId)
    end)
end

--- Check if all racers have finished or been DQ'd
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
-- ─────────────────────────────────────────────────────────────
--  CREW SYSTEM  (V4.1)
-- ─────────────────────────────────────────────────────────────
-- ============================================================

--- Helper: fetch crew row by id
local function GetCrew(crewId, cb)
    MySQL.Async.fetchAll(
        'SELECT * FROM f1_crews WHERE id=@id',
        { ['@id'] = crewId },
        function(rows)
            cb(rows and rows[1] or nil)
        end
    )
end

--- Helper: decode members JSON array
local function DecodeMembers(membersJson)
    local ok, list = pcall(json.decode, membersJson or '[]')
    return (ok and list) or {}
end

--- Helper: check if cid is in members array
local function IsMember(members, cid)
    for _, v in ipairs(members) do
        if v == cid then return true end
    end
    return false
end

--- Helper: remove cid from members array
local function RemoveMember(members, cid)
    local out = {}
    for _, v in ipairs(members) do
        if v ~= cid then out[#out+1] = v end
    end
    return out
end

-- ── REQUEST CREW PANEL DATA ───────────────────────────────────
-- Sends all crew data needed to render the NUI Crews panel.
-- Fetches player's current crew (if any), plus all crew rows
-- for the leaderboard portion.
RegisterNetEvent('fcrp_f1:sv:requestCrewPanel', function()
    local src = source
    local cid = GetCid(src)
    DBG('requestCrewPanel cid=' .. cid)

    GetOrCreate(cid, function(stats)
        local crewId = stats.crew_id

        -- Fetch top crews for leaderboard
        MySQL.Async.fetchAll(
            'SELECT id, name, tag, color, leader_cid, members, xp FROM f1_crews ORDER BY xp DESC LIMIT 20',
            {},
            function(crewRows)
                local myCrew = nil

                -- If player is in a crew, find their row
                if crewId then
                    for _, cr in ipairs(crewRows or {}) do
                        if cr.id == crewId then
                            myCrew = cr
                            break
                        end
                    end
                    -- If not in top 20, fetch directly
                    if not myCrew then
                        MySQL.Async.fetchAll(
                            'SELECT id, name, tag, color, leader_cid, members, xp, description FROM f1_crews WHERE id=@id',
                            { ['@id'] = crewId },
                            function(r)
                                myCrew = r and r[1] or nil
                            end
                        )
                        Wait(100)
                    end
                end

                -- Check if player has a pending invite
                local invite = pendingInvites[src]
                local inviteData = nil
                if invite and os.time() < invite.expires then
                    inviteData = {
                        crewId    = invite.crewId,
                        crewName  = invite.crewName,
                        inviterName = invite.inviterName,
                    }
                elseif invite then
                    pendingInvites[src] = nil   -- expired
                end

                TriggerClientEvent('fcrp_f1:cl:openCrewPanel_NUI', src, {
                    myCrew     = myCrew,
                    crews      = crewRows or {},
                    myCrewId   = crewId,
                    invite     = inviteData,
                    isLeader   = myCrew and (myCrew.leader_cid == cid) or false,
                })
            end
        )
    end)
end)

-- ── CREATE CREW ───────────────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:createCrew', function(data)
    local src  = source
    local cid  = GetCid(src)
    local name = tostring(data.name or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
    local tag  = tostring(data.tag  or ''):upper():sub(1, 6)
    local color= tostring(data.color or '#a855f7')

    DBG('createCrew cid=' .. cid .. ' name=' .. name .. ' tag=' .. tag)

    if not Config.CrewSystem.enabled then
        Notify(src, 'Crew System', 'Crews are currently disabled.', 'error'); return
    end
    if name == '' or #name < 3 or #name > 100 then
        Notify(src, 'Invalid Name', 'Crew name must be 3–100 characters.', 'error'); return
    end
    if tag == '' or #tag < 2 then
        Notify(src, 'Invalid Tag', 'Tag must be 2–6 characters.', 'error'); return
    end
    -- Validate hex color
    if not color:match('^#%x%x%x%x%x%x$') then
        color = '#a855f7'
    end

    GetOrCreate(cid, function(stats)
        if stats.crew_id then
            Notify(src, 'Already in Crew', 'Leave your current crew first.', 'error'); return
        end

        if not RemoveMoney(src, Config.CrewSystem.createCost, 'f1-crew-create') then
            Notify(src, 'Not Enough Money',
                string.format('Creating a crew costs $%d.', Config.CrewSystem.createCost), 'error')
            return
        end

        MySQL.Async.execute(
            'INSERT INTO f1_crews (name, tag, color, leader_cid, members) VALUES (@n,@t,@c,@l,@m)',
            {
                ['@n'] = name,
                ['@t'] = tag,
                ['@c'] = color,
                ['@l'] = cid,
                ['@m'] = json.encode({ cid }),
            },
            function(rowsAffected, insertId)
                if not insertId or insertId == 0 then
                    Notify(src, 'Name Taken', 'A crew with that name already exists.', 'error')
                    -- Refund
                    AddMoney(src, Config.CrewSystem.createCost, 'f1-crew-refund')
                    return
                end
                MySQL.Async.execute(
                    'UPDATE f1_players SET crew_id=@id WHERE citizenid=@c',
                    { ['@id'] = insertId, ['@c'] = cid }
                )
                local msg = (Config.Notify.crewCreated):gsub('{name}', name)
                Notify(src, 'Crew Created', msg, 'success', 5000)
                DBG('Crew created: ' .. name .. ' [' .. tag .. '] id=' .. tostring(insertId) .. ' by ' .. cid)
            end
        )
    end)
end)

-- ── INVITE PLAYER TO CREW ─────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:inviteToCrew', function(targetSrc)
    local src    = source
    local cid    = GetCid(src)
    local tSrc   = tonumber(targetSrc)
    local tName  = tSrc and GetPlayerName(tSrc) or nil

    if not tSrc or not tName then
        Notify(src, 'Not Found', 'Player not online.', 'error'); return
    end
    if tSrc == src then
        Notify(src, 'Invalid', 'You cannot invite yourself.', 'error'); return
    end

    GetOrCreate(cid, function(stats)
        if not stats.crew_id then
            Notify(src, 'No Crew', 'You are not in a crew.', 'error'); return
        end

        GetCrew(stats.crew_id, function(crew)
            if not crew then
                Notify(src, 'Crew Error', 'Could not find your crew.', 'error'); return
            end
            if crew.leader_cid ~= cid then
                Notify(src, 'Not Captain', 'Only the crew captain can send invites.', 'error'); return
            end
            local members = DecodeMembers(crew.members)
            if #members >= (Config.CrewSystem.maxMembers or 8) then
                Notify(src, 'Crew Full',
                    string.format('Max %d members reached.', Config.CrewSystem.maxMembers or 8), 'error')
                return
            end

            local tCid = GetCid(tSrc)
            if IsMember(members, tCid) then
                Notify(src, 'Already Member', tName .. ' is already in your crew.', 'error'); return
            end

            -- Check target is not already in a different crew
            GetOrCreate(tCid, function(tStats)
                if tStats.crew_id then
                    Notify(src, 'Already in Crew', tName .. ' is already in a crew.', 'error'); return
                end

                -- Store invite in memory
                pendingInvites[tSrc] = {
                    crewId      = stats.crew_id,
                    crewName    = crew.name,
                    inviterName = GetPlayerName(src),
                    inviterCid  = cid,
                    expires     = os.time() + 300,   -- 5-minute TTL
                }

                -- Notify invitee via NUI
                TriggerClientEvent('fcrp_f1:cl:crewInviteReceived', tSrc, {
                    crewName    = crew.name,
                    crewTag     = crew.tag,
                    crewColor   = crew.color,
                    inviterName = GetPlayerName(src),
                })

                Notify(src, 'Invite Sent',
                    string.format('Invited %s to %s [%s].', tName, crew.name, crew.tag), 'success')
                DBG('Crew invite: ' .. cid .. ' → ' .. tCid .. ' for crew ' .. crew.name)
            end)
        end)
    end)
end)

-- ── ACCEPT CREW INVITE ────────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:acceptCrewInvite', function()
    local src  = source
    local cid  = GetCid(src)
    local inv  = pendingInvites[src]

    if not inv then
        Notify(src, 'No Invite', 'You have no pending crew invite.', 'error'); return
    end
    if os.time() >= inv.expires then
        pendingInvites[src] = nil
        Notify(src, 'Invite Expired', 'The invite expired. Ask them to re-invite.', 'error'); return
    end

    GetOrCreate(cid, function(stats)
        if stats.crew_id then
            pendingInvites[src] = nil
            Notify(src, 'Already in Crew', 'Leave your current crew before joining another.', 'error')
            return
        end

        GetCrew(inv.crewId, function(crew)
            if not crew then
                pendingInvites[src] = nil
                Notify(src, 'Crew Gone', 'That crew no longer exists.', 'error'); return
            end

            local members = DecodeMembers(crew.members)
            if #members >= (Config.CrewSystem.maxMembers or 8) then
                pendingInvites[src] = nil
                Notify(src, 'Crew Full', 'The crew is now full.', 'error'); return
            end

            members[#members+1] = cid
            MySQL.Async.execute(
                'UPDATE f1_crews SET members=@m WHERE id=@id',
                { ['@m'] = json.encode(members), ['@id'] = inv.crewId }
            )
            MySQL.Async.execute(
                'UPDATE f1_players SET crew_id=@id WHERE citizenid=@c',
                { ['@id'] = inv.crewId, ['@c'] = cid }
            )
            pendingInvites[src] = nil

            Notify(src, 'Crew Joined',
                string.format('Welcome to %s [%s]!', crew.name, crew.tag), 'success', 5000)
            -- Let the inviter know
            local inviterSrc = nil
            for _, pid in ipairs(GetActivePlayers()) do
                if GetCid(pid) == inv.inviterCid then inviterSrc = pid; break end
            end
            if inviterSrc then
                Notify(inviterSrc, 'New Member',
                    string.format('%s joined %s!', GetPlayerName(src), crew.name), 'success')
            end
            DBG('Crew accept: ' .. cid .. ' joined crew ' .. crew.name)
        end)
    end)
end)

-- ── DECLINE CREW INVITE ───────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:declineCrewInvite', function()
    local src = source
    local inv = pendingInvites[src]
    pendingInvites[src] = nil
    if inv then
        Notify(src, 'Invite Declined', 'You declined the crew invite.', 'inform')
    end
end)

-- ── LEAVE CREW ────────────────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:leaveCrew', function()
    local src = source
    local cid = GetCid(src)

    GetOrCreate(cid, function(stats)
        if not stats.crew_id then
            Notify(src, 'No Crew', 'You are not in a crew.', 'error'); return
        end

        GetCrew(stats.crew_id, function(crew)
            if not crew then
                -- Stale crew_id — just clear it
                MySQL.Async.execute('UPDATE f1_players SET crew_id=NULL WHERE citizenid=@c', { ['@c']=cid })
                Notify(src, 'Left Crew', 'Cleared stale crew membership.', 'inform')
                return
            end

            local members = DecodeMembers(crew.members)

            if crew.leader_cid == cid then
                -- Captain is leaving
                if #members <= 1 then
                    -- Last member — disband the whole crew
                    MySQL.Async.execute('DELETE FROM f1_crews WHERE id=@id', { ['@id'] = crew.id })
                    MySQL.Async.execute('UPDATE f1_players SET crew_id=NULL WHERE citizenid=@c', { ['@c']=cid })
                    Notify(src, 'Crew Disbanded', crew.name .. ' was disbanded (no members left).', 'inform')
                    DBG('Crew disbanded (leader left, empty): ' .. crew.name)
                else
                    -- Auto-transfer captaincy to the next member
                    local newLeader = nil
                    for _, mcid in ipairs(members) do
                        if mcid ~= cid then newLeader = mcid; break end
                    end
                    local newMembers = RemoveMember(members, cid)
                    MySQL.Async.execute(
                        'UPDATE f1_crews SET leader_cid=@l, members=@m WHERE id=@id',
                        { ['@l']=newLeader, ['@m']=json.encode(newMembers), ['@id']=crew.id }
                    )
                    MySQL.Async.execute('UPDATE f1_players SET crew_id=NULL WHERE citizenid=@c', { ['@c']=cid })
                    Notify(src, 'Left Crew',
                        string.format('You left %s. Captaincy transferred.', crew.name), 'inform')
                    -- Notify new captain if online
                    for _, pid in ipairs(GetActivePlayers()) do
                        if GetCid(pid) == newLeader then
                            Notify(pid, 'New Captain',
                                'You are now the captain of ' .. crew.name .. '!', 'success')
                            break
                        end
                    end
                    DBG('Crew captain left, transferred to: ' .. tostring(newLeader))
                end
            else
                -- Regular member leaving
                local newMembers = RemoveMember(members, cid)
                MySQL.Async.execute(
                    'UPDATE f1_crews SET members=@m WHERE id=@id',
                    { ['@m']=json.encode(newMembers), ['@id']=crew.id }
                )
                MySQL.Async.execute('UPDATE f1_players SET crew_id=NULL WHERE citizenid=@c', { ['@c']=cid })
                Notify(src, 'Left Crew', 'You left ' .. crew.name .. '.', 'inform')
                DBG('Member left crew: ' .. cid .. ' from ' .. crew.name)
            end
        end)
    end)
end)

-- ── KICK CREW MEMBER ──────────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:kickCrewMember', function(targetCid)
    local src    = source
    local cid    = GetCid(src)
    targetCid    = tostring(targetCid or '')

    if targetCid == '' or targetCid == cid then
        Notify(src, 'Invalid', 'You cannot kick yourself. Use /leavecrew.', 'error'); return
    end

    GetOrCreate(cid, function(stats)
        if not stats.crew_id then
            Notify(src, 'No Crew', 'You are not in a crew.', 'error'); return
        end

        GetCrew(stats.crew_id, function(crew)
            if not crew or crew.leader_cid ~= cid then
                Notify(src, 'Not Captain', 'Only the captain can kick members.', 'error'); return
            end

            local members = DecodeMembers(crew.members)
            if not IsMember(members, targetCid) then
                Notify(src, 'Not in Crew', targetCid .. ' is not in your crew.', 'error'); return
            end

            local newMembers = RemoveMember(members, targetCid)
            MySQL.Async.execute(
                'UPDATE f1_crews SET members=@m WHERE id=@id',
                { ['@m']=json.encode(newMembers), ['@id']=crew.id }
            )
            MySQL.Async.execute('UPDATE f1_players SET crew_id=NULL WHERE citizenid=@c', { ['@c']=targetCid })

            Notify(src, 'Member Kicked', targetCid .. ' was removed from ' .. crew.name .. '.', 'inform')
            -- Notify kicked player if online
            for _, pid in ipairs(GetActivePlayers()) do
                if GetCid(pid) == targetCid then
                    Notify(pid, 'Kicked', 'You were removed from ' .. crew.name .. '.', 'warn')
                    break
                end
            end
            DBG('Crew kick: ' .. targetCid .. ' from ' .. crew.name .. ' by ' .. cid)
        end)
    end)
end)

-- ── DISBAND CREW ─────────────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:disbandCrew', function()
    local src = source
    local cid = GetCid(src)

    GetOrCreate(cid, function(stats)
        if not stats.crew_id then
            Notify(src, 'No Crew', 'You are not in a crew.', 'error'); return
        end

        GetCrew(stats.crew_id, function(crew)
            if not crew then
                MySQL.Async.execute('UPDATE f1_players SET crew_id=NULL WHERE citizenid=@c', { ['@c']=cid })
                return
            end
            if crew.leader_cid ~= cid then
                Notify(src, 'Not Captain', 'Only the captain can disband the crew.', 'error'); return
            end

            local members = DecodeMembers(crew.members)
            -- Clear crew_id for ALL members
            for _, mcid in ipairs(members) do
                MySQL.Async.execute('UPDATE f1_players SET crew_id=NULL WHERE citizenid=@c', { ['@c']=mcid })
            end
            MySQL.Async.execute('DELETE FROM f1_crews WHERE id=@id', { ['@id']=crew.id })

            Notify(src, 'Crew Disbanded', crew.name .. ' has been disbanded.', 'inform', 5000)
            -- Notify all online members
            for _, pid in ipairs(GetActivePlayers()) do
                local pcid = GetCid(pid)
                if pcid ~= cid and IsMember(members, pcid) then
                    Notify(pid, 'Crew Disbanded', crew.name .. ' was disbanded by the captain.', 'warn')
                end
            end
            DBG('Crew disbanded: ' .. crew.name .. ' by ' .. cid)
        end)
    end)
end)

-- ── TRANSFER CAPTAINCY ────────────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:transferCaptain', function(targetCid)
    local src  = source
    local cid  = GetCid(src)
    targetCid  = tostring(targetCid or '')

    GetOrCreate(cid, function(stats)
        if not stats.crew_id then
            Notify(src, 'No Crew', 'You are not in a crew.', 'error'); return
        end
        GetCrew(stats.crew_id, function(crew)
            if not crew or crew.leader_cid ~= cid then
                Notify(src, 'Not Captain', 'Only the captain can transfer captaincy.', 'error'); return
            end
            local members = DecodeMembers(crew.members)
            if not IsMember(members, targetCid) then
                Notify(src, 'Not in Crew', targetCid .. ' is not in your crew.', 'error'); return
            end
            MySQL.Async.execute(
                'UPDATE f1_crews SET leader_cid=@l WHERE id=@id',
                { ['@l']=targetCid, ['@id']=crew.id }
            )
            Notify(src, 'Captaincy Transferred',
                'Captain role given to ' .. targetCid .. '.', 'success')
            for _, pid in ipairs(GetActivePlayers()) do
                if GetCid(pid) == targetCid then
                    Notify(pid, 'New Captain', 'You are now captain of ' .. crew.name .. '!', 'success')
                    break
                end
            end
        end)
    end)
end)

-- ── UPDATE CREW DESCRIPTION ───────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:updateCrewDescription', function(desc)
    local src  = source
    local cid  = GetCid(src)
    desc       = tostring(desc or ''):sub(1, 200)

    GetOrCreate(cid, function(stats)
        if not stats.crew_id then return end
        GetCrew(stats.crew_id, function(crew)
            if not crew or crew.leader_cid ~= cid then
                Notify(src, 'Not Captain', 'Only the captain can edit the description.', 'error'); return
            end
            MySQL.Async.execute(
                'UPDATE f1_crews SET description=@d WHERE id=@id',
                { ['@d']=desc, ['@id']=crew.id }
            )
            Notify(src, 'Description Updated', 'Crew description saved.', 'success')
        end)
    end)
end)

-- ============================================================
-- ─────────────────────────────────────────────────────────────
--  ENTRY FEE SYSTEM  (V4.1)
-- ─────────────────────────────────────────────────────────────
-- ============================================================

-- Initialise fee from config on load
CreateThread(function()
    currentEntryFee = (Config.EntryFee and Config.EntryFee.defaultAmount) or 0
end)

-- ── ORGANISER SETS ENTRY FEE ─────────────────────────────────
RegisterNetEvent('fcrp_f1:sv:setEntryFee', function(amount)
    local src = source
    if not IsOrganiser(src) then return end
    if raceInProgress then
        Notify(src, 'Race Active', 'Cannot change fee during a race.', 'error'); return
    end
    amount = tonumber(amount) or 0
    amount = math.max(0, math.floor(amount))

    -- Refund any already-paid fees if grid was partially set
    for refundCid, paid in pairs(feePayers) do
        -- Find the online player with this cid
        for _, pid in ipairs(GetActivePlayers()) do
            if GetCid(pid) == refundCid then
                AddMoney(pid, paid, 'f1-fee-refund')
                Notify(pid, 'Entry Fee Refunded',
                    string.format('Fee changed to $%d — your $%d was refunded.', amount, paid), 'inform')
                break
            end
        end
    end
    feePot    = 0
    feePayers = {}

    currentEntryFee = amount
    -- Clear current grid assignments so organiser re-assigns with new fee
    pendingGrid = {}

    local msg = amount > 0
        and string.format('Entry fee set to $%d. Grid cleared.', amount)
        or  'Entry fee removed. Grid cleared.'
    Notify(src, 'Entry Fee Updated', msg, 'success')

    -- Refresh organizer panel with new fee state
    local list = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local n = GetPlayerName(pid)
        if n then list[#list+1] = {id=pid, name=n} end
    end
    TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu_NUI', src, list, {}, currentEntryFee, feePot)
    DBG('Entry fee set to ' .. amount .. ' by src=' .. src)
end)

-- ── REQUEST LIVE HUD DATA ─────────────────────────────────────
-- Used by spectators and the NUI live panel to get current race state.
RegisterNetEvent('fcrp_f1:sv:requestLiveHUD', function()
    local src = source
    if not raceInProgress then
        TriggerClientEvent('fcrp_f1:cl:liveHUDUpdate', src, nil); return
    end
    local snap = BuildSnapshot()
    TriggerClientEvent('fcrp_f1:cl:liveHUDUpdate', src, {
        snapshot    = snap,
        raceId      = currentRaceId,
        maxLaps     = Config.MaxLaps,
        feePot      = feePot,
        entryFee    = currentEntryFee,
        flHolder    = fastestLapHolder,
        flTime      = FmtMs(fastestLapMs),
        totalDrivers= #snap,
    })
end)

-- ============================================================
-- NPC MENU REQUEST
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:requestMenuOpen', function()
    local src = source
    DBG('requestMenuOpen src=' .. src)

    if IsOrganiser(src) then
        local list    = {}
        local slotMap = {}
        for _, pid in ipairs(GetActivePlayers()) do
            local n = GetPlayerName(pid)
            if n then list[#list+1] = {id=pid, name=n} end
        end
        for slot, sid in pairs(pendingGrid) do
            slotMap[slot] = GetPlayerName(sid) or tostring(sid)
        end
        TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu_NUI', src, list, slotMap, currentEntryFee, feePot)
    else
        -- Regular player → open their stats
        local cid = GetCid(src)
        GetOrCreate(cid, function(stats)
            MySQL.Async.fetchAll([[
                SELECT position, race_time, best_lap, tyre_used,
                       pit_count, xp_earned, mmr_delta, dq, dq_reason, race_date
                FROM f1_race_history WHERE citizenid=@c
                ORDER BY race_date DESC LIMIT 10
            ]], { ['@c']=cid }, function(history)
                TriggerClientEvent('fcrp_f1:cl:openStatsMenu_NUI', src, stats, history or {})
            end)
        end)
    end
end)

RegisterNetEvent('fcrp_f1:sv:requestMyStats', function()
    local src = source
    local cid = GetCid(src)
    DBG('requestMyStats cid=' .. cid)
    GetOrCreate(cid, function(stats)
        MySQL.Async.fetchAll([[
            SELECT position, race_time, best_lap, tyre_used,
                   pit_count, xp_earned, mmr_delta, dq, dq_reason, race_date
            FROM f1_race_history WHERE citizenid=@c
            ORDER BY race_date DESC LIMIT 10
        ]], { ['@c']=cid }, function(history)
            TriggerClientEvent('fcrp_f1:cl:openStatsMenu_NUI', src, stats, history or {})
        end)
    end)
end)

RegisterNetEvent('fcrp_f1:sv:requestLeaderboard', function()
    local src = source
    DBG('requestLeaderboard src=' .. src)
    MySQL.Async.fetchAll([[
        SELECT p.citizenid, p.mmr, p.xp, p.wins, p.races, p.podiums,
               p.fastest_laps, p.best_lap_ms, c.tag AS crew_tag, c.color AS crew_color
        FROM f1_players p
        LEFT JOIN f1_crews c ON c.id = p.crew_id
        ORDER BY p.mmr DESC LIMIT 20
    ]], {}, function(rows)
        TriggerClientEvent('fcrp_f1:cl:showLeaderboard_NUI', src, rows or {})
    end)
end)

-- ============================================================
-- /f1menu  COMMAND  (admin only, opens race control panel)
-- ============================================================
lib.addCommand('f1menu', { help = 'Open Race Control panel' }, function(source)
    local src = source
    if not IsOrganiser(src) then
        Notify(src, 'Access Denied', Config.Notify.accessDenied, 'error'); return
    end
    local list    = {}
    local slotMap = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local n = GetPlayerName(pid)
        if n then list[#list+1] = {id=pid, name=n} end
    end
    for slot, sid in pairs(pendingGrid) do
        slotMap[slot] = GetPlayerName(sid) or tostring(sid)
    end
    TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu_NUI', src, list, slotMap, currentEntryFee, feePot)
end)

-- ============================================================
-- SLOT ASSIGNMENT  (with entry fee collection)
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:assignSlot', function(slot, targetId)
    local src = source
    if not IsOrganiser(src) then return end

    targetId = tonumber(targetId)
    slot     = tonumber(slot)

    if not targetId or not slot or slot < 1 or slot > #Config.GridSpots then
        Notify(src, 'Invalid Input', 'Bad slot or player ID.', 'error'); return
    end

    local name = GetPlayerName(targetId)
    if not name then
        Notify(src, 'Not Found', 'Player ID ' .. targetId .. ' is not online.', 'error'); return
    end

    -- Item gate
    if Config.Items.enabled then
        if not HasItem(targetId, Config.Items.entryItem) then
            Notify(src, 'Missing Item',
                string.format('%s needs a %s to enter.', name, Config.Items.entryItem), 'error')
            return
        end
        RemoveItem(targetId, Config.Items.entryItem, 1)
    end

    -- ── Entry fee collection ──────────────────────────────────
    if currentEntryFee > 0 then
        local targetCid = GetCid(targetId)
        -- Don't double-charge if re-assigning the same player
        if not feePayers[targetCid] then
            if not RemoveMoney(targetId, currentEntryFee, 'f1-entry-fee') then
                Notify(src, 'Insufficient Funds',
                    string.format('%s cannot afford the $%d entry fee.', name, currentEntryFee), 'error')
                Notify(targetId, 'Entry Fee',
                    string.format('You need $%d to enter this race.', currentEntryFee), 'error')
                return
            end
            feePayers[targetCid] = currentEntryFee
            feePot = feePot + currentEntryFee
            DBG(string.format('Entry fee collected: $%d from %s — pot now $%d', currentEntryFee, name, feePot))
            Notify(targetId, 'Entry Fee Paid',
                string.format('$%d entry fee paid. Prize pot: $%d', currentEntryFee, feePot), 'inform')
        end
    end

    -- Hook guard
    if OpenServerFunctions and OpenServerFunctions.CanAssignSlot then
        if not OpenServerFunctions.CanAssignSlot(targetId, slot) then
            Notify(src, 'Blocked', 'Assignment blocked by server hook.', 'error'); return
        end
    end

    -- Assign
    pendingGrid[slot] = targetId
    TriggerClientEvent('fcrp_f1:cl:slotAssigned', src, slot, targetId, name)
    Notify(src, 'Assigned',
        string.format('P%d → %s (ID %d)', slot, name, targetId), 'success')

    -- Refresh organizer panel
    local list    = {}
    local slotMap = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local n = GetPlayerName(pid)
        if n then list[#list+1] = {id=pid, name=n} end
    end
    for s, sid in pairs(pendingGrid) do
        slotMap[s] = GetPlayerName(sid) or tostring(sid)
    end
    TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu_NUI', src, list, slotMap, currentEntryFee, feePot)
end)

-- ── CLEAR ALL GRID SLOTS  (with fee refunds) ─────────────────
RegisterNetEvent('fcrp_f1:sv:clearGrid', function()
    local src = source
    if not IsOrganiser(src) then return end

    -- Refund entry fees
    for refundCid, paid in pairs(feePayers) do
        for _, pid in ipairs(GetActivePlayers()) do
            if GetCid(pid) == refundCid then
                AddMoney(pid, paid, 'f1-fee-refund')
                Notify(pid, 'Entry Fee Refunded', string.format('$%d refunded — grid cleared.', paid), 'inform')
                break
            end
        end
    end
    feePot    = 0
    feePayers = {}
    pendingGrid = {}

    DBG('clearGrid by src=' .. src)
    Notify(src, 'Grid Cleared', 'All slots and fees have been reset.', 'inform')

    local list = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local n = GetPlayerName(pid)
        if n then list[#list+1] = {id=pid, name=n} end
    end
    TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu_NUI', src, list, {}, currentEntryFee, feePot)
end)

-- ── CLEAR SINGLE SLOT  (with fee refund) ─────────────────────
RegisterNetEvent('fcrp_f1:sv:clearSlot', function(slot)
    local src = source
    if not IsOrganiser(src) then return end

    slot = tonumber(slot)
    if not slot or slot < 1 or slot > #Config.GridSpots then
        DBGW('clearSlot: invalid slot=' .. tostring(slot)); return
    end

    local sid = pendingGrid[slot]
    if sid then
        -- Refund fee for this driver
        local refundCid = GetCid(sid)
        local paid      = feePayers[refundCid]
        if paid then
            AddMoney(sid, paid, 'f1-fee-refund')
            Notify(sid, 'Entry Fee Refunded', string.format('$%d refunded — removed from grid.', paid), 'inform')
            feePot = math.max(0, feePot - paid)
            feePayers[refundCid] = nil
        end
    end

    pendingGrid[slot] = nil
    DBG('Slot ' .. slot .. ' cleared by src=' .. src)

    local list    = {}
    local slotMap = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local n = GetPlayerName(pid)
        if n then list[#list+1] = {id=pid, name=n} end
    end
    for s, sid2 in pairs(pendingGrid) do
        slotMap[s] = GetPlayerName(sid2) or tostring(sid2)
    end
    TriggerClientEvent('fcrp_f1:cl:openOrganizerMenu_NUI', src, list, slotMap, currentEntryFee, feePot)
end)

-- ============================================================
-- GRID SETUP  (spawn F1 cars on grid spots)
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:setupGrid', function()
    local src = source
    if not IsOrganiser(src) then return end

    TriggerClientEvent('fcrp_f1:cl:cleanupCars', -1)
    racers         = {}; finishOrder = {}; dqList = {}
    raceInProgress = false; raceStartTime = nil; gridAssignments = {}
    fastestLapHolder = nil; fastestLapMs = nil
    currentRaceId  = NewRaceId()

    local placed = 0
    for slot = 1, #Config.GridSpots do
        local tid  = pendingGrid[slot]
        local spot = Config.GridSpots[slot]
        if tid then
            local name = GetPlayerName(tid)
            if name then
                local cid = GetCid(tid)
                -- Fetch crew tag for HUD display
                local crewTag = ''
                MySQL.Async.fetchAll(
                    'SELECT c.tag FROM f1_players p LEFT JOIN f1_crews c ON c.id=p.crew_id WHERE p.citizenid=@c',
                    { ['@c']=cid },
                    function(rows)
                        if rows and rows[1] and rows[1].tag then crewTag = rows[1].tag end
                    end
                )
                Wait(50)   -- allow the async to complete before we use crewTag

                TriggerClientEvent('fcrp_f1:cl:spawnYourCar', tid, spot)
                racers[tostring(tid)] = {
                    name            = name,
                    cid             = cid,
                    lap             = 1,
                    cp              = 1,
                    score           = 1,
                    finished        = false,
                    dq              = false,
                    dqReason        = nil,
                    finishTime      = nil,
                    finishPos       = nil,
                    pitDone         = false,
                    gridSlot        = slot,
                    fastestLapMs    = nil,
                    setFastestLap   = false,
                    currentLapStart = nil,
                    lapTimes        = {},
                    sectorTimes     = {},
                    currentSectorStart = nil,
                    drsCount        = 0,
                    drsActive       = false,
                    engineOk        = true,
                    pitCount        = 0,
                    currentTyre     = 'medium',
                    crewTag         = crewTag,   -- V4.1
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
    Notify(src, 'Grid Ready',
        string.format('%d driver(s) on the grid — Race %s', placed, currentRaceId), 'success')
    print(string.format('^2[F1]^7 Grid set. %d drivers. Race %s. Pot: $%d',
        placed, currentRaceId, feePot))
end)

-- ============================================================
-- SAFETY CAR / FORMATION LAP
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:deploySafetyCar', function()
    local src = source
    if not IsOrganiser(src) then return end
    if next(racers) == nil then
        Notify(src, 'No Grid', 'Set up the grid first.', 'error'); return
    end
    scOrganiser = src
    TriggerClientEvent('fcrp_f1:cl:spawnSafetyCar', src)
    SetTimeout(1500, function()
        TriggerClientEvent('fcrp_f1:cl:beginFormationLap', -1)
    end)
    NotifyAll('🟡 Safety Car Deployed',
        'Follow the safety car — race starts when it returns.', 'inform', 6000)
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

-- ============================================================
-- FORCE START (manual lights out by organiser)
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:startGlobalRace', function()
    local src = source
    if not IsOrganiser(src) then return end
    if raceInProgress then
        Notify(src, 'Already Racing', 'Race is already in progress.', 'warning'); return
    end
    if next(racers) == nil then
        Notify(src, 'No Drivers', 'Grid is empty. Set up the grid first.', 'error'); return
    end
    raceInProgress = true
    TriggerClientEvent('fcrp_f1:cl:endFormationLap', -1)
    TriggerClientEvent('fcrp_f1:cl:despawnSafetyCar', scOrganiser or src)
    scOrganiser = nil
    SetTimeout(2000, function()
        TriggerClientEvent('fcrp_f1:cl:startRace', -1)
    end)
    print('^2[F1]^7 Race force-started by ' .. GetPlayerName(src))
end)

-- ============================================================
-- RACE CLOCK  (first racer to fire this sets the global timer)
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:raceClockStart', function()
    local key = tostring(source)
    if not racers[key] or not raceInProgress then return end
    if not raceStartTime then
        raceStartTime = os.time()
        for _, d in pairs(racers) do
            d.currentLapStart    = raceStartTime
            d.currentSectorStart = raceStartTime
        end
        print('^2[F1]^7 Race clock started. ID: ' .. currentRaceId)
    end
end)

-- ============================================================
-- PROGRESS UPDATE  (client fires on each checkpoint pass)
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
-- LAP TIMING
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:lapComplete', function(lapMs, sectorData)
    local src = source
    local key = tostring(src)
    if not racers[key] then return end

    local d = racers[key]
    d.lapTimes[#d.lapTimes+1] = lapMs
    d.sectorTimes = sectorData or {}

    -- Fastest lap of the race
    if not fastestLapMs or lapMs < fastestLapMs then
        fastestLapMs    = lapMs
        fastestLapHolder= d.name
        d.setFastestLap = true
        d.fastestLapMs  = lapMs
        local xpBonus   = Config.FastestLapXP or 15
        NotifyAll('💜 Fastest Lap',
            string.format('%s — %s  (+%d XP)', d.name, FmtMs(lapMs), xpBonus), 'inform', 5000)
        MySQL.Async.execute(
            'UPDATE f1_players SET xp=xp+@b WHERE citizenid=@c',
            { ['@b']=xpBonus, ['@c']=d.cid }
        )
        TriggerClientEvent('fcrp_f1:cl:fastestLapSet', src, lapMs)
    end
    DBG(string.format('Lap: %s  %s', d.name, FmtMs(lapMs)))
end)

-- ============================================================
-- PIT STOP
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:pitStop', function(compound)
    local src = source
    if not Config.TireCompounds[compound] then return end
    local key = tostring(src)
    if racers[key] then
        racers[key].pitDone     = true
        racers[key].pitCount    = (racers[key].pitCount  or 0) + 1
        racers[key].currentTyre = compound
    end
    TriggerClientEvent('fcrp_f1:cl:doPitStop', src, compound)
    if OpenServerFunctions and OpenServerFunctions.OnPitStop then
        OpenServerFunctions.OnPitStop(src, compound)
    end
    BroadcastLeaderboard()   -- update tyre indicator for spectators
    DBG(GetPlayerName(src) .. ' pitted → ' .. compound)
end)

-- ============================================================
-- DRS TRACKING
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:drsUsed', function()
    local key = tostring(source)
    if racers[key] then
        racers[key].drsCount  = (racers[key].drsCount or 0) + 1
        racers[key].drsActive = true
        -- Reset DRS flag after 2 seconds
        local src = source
        SetTimeout(2000, function()
            if racers[tostring(src)] then
                racers[tostring(src)].drsActive = false
            end
        end)
    end
end)

-- ============================================================
-- ENGINE DAMAGE
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:engineDamaged', function()
    local key = tostring(source)
    if racers[key] then racers[key].engineOk = false end
end)

-- ============================================================
-- DISQUALIFY PLAYER
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:dqPlayer', function(reason)
    local src  = source
    local name = GetPlayerName(src)
    local key  = tostring(src)

    if not racers[key] then return end

    racers[key].dq       = true
    racers[key].dqReason = reason
    table.insert(dqList, { name = name, reason = reason })

    NotifyAll('DISQUALIFIED', name .. ' — ' .. reason, 'error')
    BroadcastLeaderboard()
    TriggerClientEvent('fcrp_f1:cl:teleportPostRace', src)

    local d   = racers[key]
    local cid = d.cid or GetCid(src)
    local totalDrivers = 0
    for _ in pairs(racers) do totalDrivers = totalDrivers + 1 end
    local mmrDelta = CalcMmrDelta(totalDrivers + 1, totalDrivers, true)
    d.dqReason = reason
    PersistResult(cid, src, d, totalDrivers + 1, true, 0, mmrDelta)

    if OpenServerFunctions and OpenServerFunctions.OnDriverDQ then
        OpenServerFunctions.OnDriverDQ(src, reason)
    end
    CheckSessionEnd()
end)

-- ============================================================
-- FINISH RACE
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

    -- Merge client-reported telemetry
    if clientData then
        d.fastestLapMs = clientData.fastestLapMs or d.fastestLapMs
        d.sectorTimes  = clientData.sectorTimes  or d.sectorTimes
        d.currentTyre  = clientData.tyre         or d.currentTyre
        d.pitCount     = clientData.pitCount      or d.pitCount
        d.drsCount     = clientData.drsCount      or d.drsCount
        d.engineOk     = (clientData.engineOk ~= nil) and clientData.engineOk or d.engineOk
    end
    d.raceTime   = timeStr
    d.bestLapStr = d.fastestLapMs and FmtMs(d.fastestLapMs) or nil

    table.insert(finishOrder, {
        id      = src,
        name    = name,
        time    = timeStr,
        rawTime = now - (raceStartTime or now),
    })

    -- Rewards
    local totalDrivers = 0
    for _ in pairs(racers) do totalDrivers = totalDrivers + 1 end
    local xpEarned = Config.XP[position] or (Config.XP[#Config.XP] or 1)
    if position == 1 then xpEarned = Config.WinXP or xpEarned end
    if d.setFastestLap then xpEarned = xpEarned + (Config.FastestLapXP or 0) end
    local mmrDelta = CalcMmrDelta(position, totalDrivers, false)

    PersistResult(cid, src, d, position, false, xpEarned, mmrDelta)

    -- Prize money
    if position == 1 then
        exports.ox_inventory:AddItem(src, Config.PrizeItem, Config.PrizeMoney)
        -- Entry fee pot payout
        if feePot > 0 then
            AddMoney(src, feePot, 'f1-pot-prize')
            NotifyAll('💰 Prize Pot Won!',
                string.format('%s wins the $%d prize pot!', name, feePot), 'success', 6000)
            DBG(string.format('Pot $%d paid to %s', feePot, name))
        end
        NotifyAll('🏁 Race Winner!',
            string.format('%s wins!  +$%d  +%d XP', name, Config.PrizeMoney, xpEarned), 'success')
    end

    -- Personal result notify
    local mmrSign = mmrDelta >= 0 and '+' or ''
    Notify(src, string.format('P%d Finish', position),
        string.format('%s  |  +%d XP  |  %s%d MMR', timeStr, xpEarned, mmrSign, mmrDelta),
        position == 1 and 'success' or 'inform')

    BroadcastLeaderboard()
    print(string.format('^2[F1]^7 P%d: %s — %s (+%d XP, %+d MMR)',
        position, name, timeStr, xpEarned, mmrDelta))

    if OpenServerFunctions and OpenServerFunctions.OnRaceFinish then
        OpenServerFunctions.OnRaceFinish(src, position, timeStr, xpEarned, mmrDelta)
    end
    CheckSessionEnd()
end)

-- ============================================================
-- RACE DIRECTOR CAMERA
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:getVehicleForCam', function(targetId)
    local src = source
    if not IsOrganiser(src) then return end
    local ped = GetPlayerPed(targetId)
    if not ped or ped == 0 then
        Notify(src, 'Cam Error', 'Player not found.', 'error'); return
    end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        Notify(src, 'Cam Error', 'Target is not in a vehicle.', 'error'); return
    end
    TriggerClientEvent('fcrp_f1:cl:attachDirectorCam', src, NetworkGetNetworkIdFromEntity(veh))
end)

-- ============================================================
-- FORCE END / RESET
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:forceEnd', function()
    local src = source
    if not IsOrganiser(src) then return end

    TriggerClientEvent('fcrp_f1:cl:cleanupCars', -1)
    if scOrganiser then
        TriggerClientEvent('fcrp_f1:cl:despawnSafetyCar', scOrganiser)
        scOrganiser = nil
    end

    -- Refund fees on force end
    for refundCid, paid in pairs(feePayers) do
        for _, pid in ipairs(GetActivePlayers()) do
            if GetCid(pid) == refundCid then
                AddMoney(pid, paid, 'f1-fee-refund')
                Notify(pid, 'Fee Refunded', string.format('$%d refunded — race was cancelled.', paid), 'inform')
                break
            end
        end
    end
    feePot    = 0
    feePayers = {}

    racers = {}; finishOrder = {}; dqList = {}
    raceInProgress = false; raceStartTime = nil; pendingGrid = {}
    fastestLapHolder = nil; fastestLapMs = nil
    currentRaceId = NewRaceId()

    NotifyAll('Race Reset', 'Organiser ended the session.', 'warning')
    print('^3[F1]^7 Force end by ' .. GetPlayerName(src))
end)

-- ============================================================
-- SPECTATOR SYSTEM
-- ============================================================
lib.addCommand('f1spectate', { help = 'Spectate the live F1 race' }, function(source)
    local src = source
    if racers[tostring(src)] then
        Notify(src, 'Spectator Mode', 'You are registered as a driver.', 'error'); return
    end
    if not raceInProgress then
        Notify(src, 'No Race', 'No race is currently in progress.', 'error'); return
    end

    local targets = {}
    for id, d in pairs(racers) do
        if not d.dq and not d.finished then
            local numId = tonumber(id)
            if numId then
                local ped = GetPlayerPed(numId)
                local veh = ped and GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then
                    targets[#targets+1] = {
                        name    = d.name,
                        netId   = NetworkGetNetworkIdFromEntity(veh),
                        lap     = d.lap   or 1,
                        pos     = #targets + 1,
                        tyre    = d.currentTyre or 'medium',
                        crewTag = d.crewTag or '',
                    }
                end
            end
        end
    end

    if #targets == 0 then
        Notify(src, 'No Drivers', 'No drivers are currently on track.', 'error'); return
    end

    spectators[src] = true
    TriggerClientEvent('fcrp_f1:cl:startSpectating', src, targets)
    print(string.format('^3[F1]^7 %s is spectating.', GetPlayerName(src)))
end)

-- Periodic spectator target update (every 2s)
CreateThread(function()
    while true do
        Wait(2000)
        if raceInProgress and next(spectators) ~= nil then
            local targets = {}
            for id, d in pairs(racers) do
                if not d.dq then
                    local numId = tonumber(id)
                    if numId then
                        local ped = GetPlayerPed(numId)
                        local veh = ped and GetVehiclePedIsIn(ped, false)
                        if veh and veh ~= 0 then
                            targets[#targets+1] = {
                                name    = d.name,
                                netId   = NetworkGetNetworkIdFromEntity(veh),
                                lap     = d.lap   or 1,
                                pos     = #targets + 1,
                                tyre    = d.currentTyre or 'medium',
                                crewTag = d.crewTag or '',
                            }
                        end
                    end
                end
            end
            if #targets > 0 then
                for specSrc in pairs(spectators) do
                    TriggerClientEvent('fcrp_f1:cl:specTargetsUpdate', specSrc, targets)
                end
            end
        end
    end
end)

-- ============================================================
-- COMMANDS
-- ============================================================
lib.addCommand('f1stats', { help = 'View your F1 career stats' }, function(source)
    local src = source
    local cid = GetCid(src)
    GetOrCreate(cid, function(stats)
        TriggerClientEvent('chat:addMessage', src, { args = {
            string.format('[F1]  MMR: %d | XP: %d | Wins: %d | Races: %d | Podiums: %d | FL: %d',
                stats.mmr, stats.xp, stats.wins, stats.races, stats.podiums, stats.fastest_laps)
        }})
    end)
end)

lib.addCommand('f1top', { help = 'F1 MMR leaderboard (top 10)' }, function(source)
    local src = source
    MySQL.Async.fetchAll(
        'SELECT citizenid, mmr, wins, races FROM f1_players ORDER BY mmr DESC LIMIT 10',
        {},
        function(rows)
            if not rows or #rows == 0 then
                TriggerClientEvent('chat:addMessage', src, { args = { '[F1]', 'No data yet.' } })
                return
            end
            TriggerClientEvent('chat:addMessage', src, { args = { '[F1]', '── Top 10 Drivers ──' } })
            for i, row in ipairs(rows) do
                TriggerClientEvent('chat:addMessage', src, { args = {
                    string.format('#%d  %s  MMR: %d  Wins: %d  Races: %d',
                        i, row.citizenid, row.mmr, row.wins, row.races)
                }})
            end
        end
    )
end)

-- Weekly reward (net event + command both route to same logic)
local function ClaimWeeklyReward(src)
    local cid = GetCid(src)
    local now, week = os.time(), 7 * 24 * 3600
    GetOrCreate(cid, function(stats)
        if (now - (stats.weekly_claimed or 0)) < week then
            local hours = math.floor((week - (now - (stats.weekly_claimed or 0))) / 3600)
            Notify(src, 'Weekly Reward',
                (Config.Notify.weeklyNotReady):gsub('{hours}', hours), 'inform')
            return
        end
        local r = Config.WeeklyReward
        if r.type == 'money' then
            AddMoney(src, r.money, 'f1-weekly')
        elseif r.type == 'item' then
            exports.ox_inventory:AddItem(src, r.item.name, r.item.amount)
        end
        MySQL.Async.execute(
            'UPDATE f1_players SET weekly_claimed=@t WHERE citizenid=@c',
            { ['@t'] = now, ['@c'] = cid }
        )
        Notify(src, 'Weekly Reward', Config.Notify.weeklyReward, 'success')
    end)
end

RegisterNetEvent('fcrp_f1:sv:claimWeeklyReward', function()
    ClaimWeeklyReward(source)
end)
RegisterNetEvent('f1reward', function()
    ClaimWeeklyReward(source)
end)

lib.addCommand('f1reward', { help = 'Claim your weekly F1 reward' }, function(source)
    ClaimWeeklyReward(source)
end)

-- ============================================================
-- PLAYER DISCONNECT HANDLER
-- ============================================================
AddEventHandler('playerDropped', function()
    local src = source
    spectators[src] = nil
    pendingInvites[src] = nil

    local key = tostring(src)
    if not racers[key] then return end

    local d   = racers[key]
    d.dq       = true
    d.dqReason = 'Disconnected'
    table.insert(dqList, { name = d.name, reason = 'Disconnected' })

    local totalDrivers = 0
    for _ in pairs(racers) do totalDrivers = totalDrivers + 1 end
    local mmrDelta = CalcMmrDelta(totalDrivers + 1, totalDrivers, true)
    PersistResult(d.cid, src, d, totalDrivers + 1, true, 0, mmrDelta)

    BroadcastLeaderboard()
    NotifyAll('Driver Out', d.name .. ' disconnected from the race.', 'warning')
    DBG('Player ' .. src .. ' dropped mid-race — DQ applied.')
    CheckSessionEnd()
end)

-- ============================================================
-- PLAYER NEEDS MAINTENANCE
-- ============================================================
RegisterNetEvent('fcrp_f1:sv:maintainNeeds', function()
    local src = source
    if not Config.RaceNeeds or not Config.RaceNeeds.enabled then return end
    if not racers[tostring(src)] then return end
    local p = GetQBPlayer(src)
    if not p then return end
    p.Functions.SetMetaData('stress', Config.RaceNeeds.stress)
    p.Functions.SetMetaData('hunger', Config.RaceNeeds.hunger)
    p.Functions.SetMetaData('thirst', Config.RaceNeeds.thirst)
    TriggerClientEvent('hud:client:UpdateNeeds', src, Config.RaceNeeds.hunger, Config.RaceNeeds.thirst)
    DBG('Needs maintained for src=' .. src)
end)

-- ============================================================
-- AUTO-RACE SCHEDULER  (bug-fixed in v3.1, unchanged in v4.1)
-- ============================================================
local scheduledWarned  = {}
local scheduledStarted = {}

local function DoScheduledRace(entry, raceId)
    TriggerClientEvent('fcrp_f1:cl:cleanupCars', -1)
    racers = {}; finishOrder = {}; dqList = {}
    raceInProgress = false; raceStartTime = nil; gridAssignments = {}
    fastestLapHolder = nil; fastestLapMs = nil
    feePot = 0; feePayers = {}
    currentEntryFee = entry.entryFee or 0
    currentRaceId = raceId

    local players = GetActivePlayers()
    local placed  = 0
    pendingGrid   = {}

    for i, pid in ipairs(players) do
        if i > #Config.GridSpots then break end
        local name = GetPlayerName(pid)
        if name then
            pendingGrid[i] = pid
            placed = placed + 1
        end
    end

    if placed < (Config.MinPlayers or 2) then
        DBGW('Scheduled race ' .. raceId .. ' cancelled — only ' .. placed .. ' players online.')
        NotifyAll('Race Cancelled',
            'Not enough players online for the scheduled race.', 'warn', 8000)
        return
    end

    -- Collect entry fees if applicable
    if currentEntryFee > 0 then
        for slot, pid in pairs(pendingGrid) do
            local cid = GetCid(pid)
            if RemoveMoney(pid, currentEntryFee, 'f1-scheduled-entry') then
                feePayers[cid] = currentEntryFee
                feePot = feePot + currentEntryFee
            else
                pendingGrid[slot] = nil   -- can't afford, remove from grid
                placed = placed - 1
                Notify(pid, 'Entry Fee', 'Could not afford entry fee — removed from grid.', 'error')
            end
        end
    end

    for slot = 1, #Config.GridSpots do
        local tid  = pendingGrid[slot]
        local spot = Config.GridSpots[slot]
        if tid then
            local name = GetPlayerName(tid)
            if name then
                local cid      = GetCid(tid)
                local crewTag  = ''
                MySQL.Async.fetchAll(
                    'SELECT c.tag FROM f1_players p LEFT JOIN f1_crews c ON c.id=p.crew_id WHERE p.citizenid=@c',
                    { ['@c']=cid }, function(rows)
                        if rows and rows[1] and rows[1].tag then crewTag = rows[1].tag end
                    end
                )
                Wait(50)
                TriggerClientEvent('fcrp_f1:cl:spawnYourCar', tid, spot)
                racers[tostring(tid)] = {
                    name=name, cid=cid, lap=1, cp=1, score=1,
                    finished=false, dq=false, dqReason=nil,
                    finishTime=nil, finishPos=nil, pitDone=false, gridSlot=slot,
                    fastestLapMs=nil, setFastestLap=false,
                    currentLapStart=nil, lapTimes={}, sectorTimes={}, currentSectorStart=nil,
                    drsCount=0, drsActive=false, engineOk=true, pitCount=0,
                    currentTyre='medium', crewTag=crewTag,
                }
                gridAssignments[slot] = tid
                if OpenServerFunctions and OpenServerFunctions.OnDriverGridded then
                    OpenServerFunctions.OnDriverGridded(tid, slot, cid)
                end
            end
        end
    end

    BroadcastLeaderboard()
    NotifyAll('🏁 Race Starting',
        string.format('Scheduled Grand Prix — %d drivers | Pot: $%d', placed, feePot), 'inform', 6000)
    Wait(3000)
    scOrganiser = nil
    TriggerClientEvent('fcrp_f1:cl:spawnSafetyCar', GetActivePlayers()[1] or -1)
    Wait(1500)
    TriggerClientEvent('fcrp_f1:cl:beginFormationLap', -1)
    print(string.format('^2[F1]^7 Scheduled race %s launched — %d drivers, pot $%d.',
        raceId, placed, feePot))
end

CreateThread(function()
    while true do
        Wait(10000)
        if not Config.RaceSchedule then goto continue end

        local day  = os.date('%A')
        local hh   = tonumber(os.date('%H'))
        local mm   = tonumber(os.date('%M'))
        local now  = string.format('%02d:%02d', hh, mm)

        local warnH, warnM = hh, mm - 10
        if warnM < 0 then warnH = warnH - 1; warnM = warnM + 60 end
        if warnH < 0 then warnH = 23 end
        local warnBase = string.format('%02d:%02d', warnH, warnM)

        local schedule = Config.RaceSchedule[day] or {}
        for _, entry in ipairs(schedule) do
            local raceKey = day .. '_' .. entry.time
            local warnKey = raceKey .. '_warn'

            if warnBase == entry.time and not scheduledWarned[warnKey] then
                scheduledWarned[warnKey] = true
                NotifyAll('🏁 Race in 10 minutes',
                    (Config.Notify.scheduleWarning):gsub('{mins}', '10'), 'inform', 8000)
            end

            if now == entry.time and not scheduledStarted[raceKey] then
                scheduledStarted[raceKey] = true
                if raceInProgress then
                    DBGW('Scheduled ' .. raceKey .. ' skipped — race already in progress.')
                else
                    local raceId = NewRaceId()
                    CreateThread(function() DoScheduledRace(entry, raceId) end)
                end
            end
        end

        if now == '00:00' then
            scheduledWarned  = {}
            scheduledStarted = {}
            DBG('Scheduler reset at midnight.')
        end

        ::continue::
    end
end)

-- ── Expire stale invites every 60s ───────────────────────────
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, inv in pairs(pendingInvites) do
            if now >= inv.expires then
                pendingInvites[src] = nil
                -- Gently notify if still online
                if GetPlayerName(src) then
                    Notify(src, 'Invite Expired',
                        'Your crew invite from ' .. inv.crewName .. ' expired.', 'inform')
                end
            end
        end
    end
end)

-- ============================================================
-- DEBUG COMMAND  (server-side diagnostics, admin only)
-- ============================================================
lib.addCommand('f1debug_server', { help = 'Run FCRP F1 server diagnostics' }, function(source)
    local src = source
    if not IsOrganiser(src) and src ~= 0 then
        Notify(src, 'Access Denied', 'Admin only.', 'error'); return
    end

    local lines = {
        string.format('Version: v4.1  |  Race: %s  |  In progress: %s', currentRaceId, tostring(raceInProgress)),
        string.format('Racers: %d  |  Spectators: %d  |  Pending grid: %d',
            (function() local c=0; for _ in pairs(racers) do c=c+1 end; return c end)(),
            (function() local c=0; for _ in pairs(spectators) do c=c+1 end; return c end)(),
            (function() local c=0; for _ in pairs(pendingGrid) do c=c+1 end; return c end)()
        ),
        string.format('Entry fee: $%d  |  Pot: $%d  |  Payers: %d',
            currentEntryFee, feePot,
            (function() local c=0; for _ in pairs(feePayers) do c=c+1 end; return c end)()
        ),
        string.format('Fastest lap: %s — %s',
            tostring(fastestLapHolder), FmtMs(fastestLapMs)),
    }

    for _, line in ipairs(lines) do
        print('^5[FCRP_F1 DEBUG]^7 ' .. line)
    end

    if src > 0 then
        TriggerClientEvent('chat:addMessage', src, {
            color = {168, 85, 247}, multiline = true,
            args  = { '[FCRP_F1 v4.1]', table.concat(lines, '\n') },
        })
    end
end)

print('^2[FCRP_F1]^7 Server v4.1 loaded — Crews · EntryFees · LiveHUD')
