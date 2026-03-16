--[[
╔══════════════════════════════════════════════════════════════════╗
║          FLAME CITY F1 — shared/debug.lua  |  v3.0              ║
║   Centralised debug & diagnostics utility                        ║
║   Loaded via shared_scripts — works on BOTH client & server      ║
║                                                                  ║
║   USAGE:                                                         ║
║     Set Config.Debug = true  in shared/config.lua               ║
║     All DBG() / DBGW() / DBGE() calls will then print.          ║
║     /f1debug  command runs a full live diagnostics report.       ║
╚══════════════════════════════════════════════════════════════════╝
]]

-- ─────────────────────────────────────────────────────────────────
-- COLOUR CODES  (FiveM console)
-- ─────────────────────────────────────────────────────────────────
local C = {
    reset   = '^7',
    tag     = '^5',   -- cyan   — prefix label
    info    = '^3',   -- yellow — info
    ok      = '^2',   -- green  — success / pass
    warn    = '^8',   -- orange — warning
    err     = '^1',   -- red    — error
    section = '^6',   -- purple — section headers
    dim     = '^9',   -- grey   — verbose / low priority
}

local PREFIX = C.tag .. '[FCRP_F1]' .. C.reset

-- ─────────────────────────────────────────────────────────────────
-- CORE LOG FUNCTIONS
-- ─────────────────────────────────────────────────────────────────

--- Standard debug message — only prints when Config.Debug is true
---@param ... any
function DBG(...)
    if not Config or not Config.Debug then return end
    local ctx = IsDuplicityVersion() and '[SRV]' or '[CLI]'
    print(PREFIX .. C.info .. ctx .. ' ' .. C.reset .. table.concat({...}, ' '))
end

--- Warning — always prints regardless of Config.Debug
---@param ... any
function DBGW(...)
    local ctx = IsDuplicityVersion() and '[SRV]' or '[CLI]'
    print(PREFIX .. C.warn .. ctx .. ' ⚠ ' .. C.reset .. table.concat({...}, ' '))
end

--- Error — always prints regardless of Config.Debug
---@param ... any
function DBGE(...)
    local ctx = IsDuplicityVersion() and '[SRV]' or '[CLI]'
    print(PREFIX .. C.err .. ctx .. ' ✖ ' .. C.reset .. table.concat({...}, ' '))
end

--- Section header — groups related debug output visually
---@param title string
function DBG_SECTION(title)
    if not Config or not Config.Debug then return end
    print('\n' .. PREFIX .. C.section ..
          ' ══════ ' .. string.upper(title) .. ' ══════' .. C.reset)
end

--- Table dump — pretty prints a Lua table to console
---@param tbl table
---@param label? string
---@param depth? integer
function DBG_TABLE(tbl, label, depth)
    if not Config or not Config.Debug then return end
    depth = depth or 0
    local indent = string.rep('  ', depth)
    if label then
        print(PREFIX .. C.info .. ' [TABLE] ' .. tostring(label) .. C.reset)
    end
    if type(tbl) ~= 'table' then
        print(indent .. C.dim .. tostring(tbl) .. C.reset); return
    end
    for k, v in pairs(tbl) do
        if type(v) == 'table' then
            print(indent .. C.tag .. tostring(k) .. ':' .. C.reset)
            DBG_TABLE(v, nil, depth + 1)
        else
            print(indent .. C.tag .. tostring(k) .. C.reset
                .. ' = ' .. C.info .. tostring(v) .. C.reset)
        end
    end
end

--- NUI message logger — wraps SendNUIMessage to log every payload
---@param payload table
function DBG_NUI(payload)
    if not Config or not Config.Debug then return end
    DBG('[NUI →] action=' .. tostring(payload.action))
    if Config.DebugVerbose then
        DBG_TABLE(payload, 'NUI payload')
    end
end

-- ─────────────────────────────────────────────────────────────────
-- EVENT TRACE  (wrap TriggerEvent calls for visibility)
-- ─────────────────────────────────────────────────────────────────

--- Log a net event being triggered
---@param direction string  'cl→sv' | 'sv→cl' | 'sv→all'
---@param eventName string
---@param ... any
function DBG_EVENT(direction, eventName, ...)
    if not Config or not Config.Debug then return end
    local args = {...}
    local argStr = ''
    for i, v in ipairs(args) do
        argStr = argStr .. (i > 1 and ', ' or '') .. tostring(v)
    end
    DBG(string.format('[EVENT %s] %s(%s)', direction, eventName, argStr))
end

-- ─────────────────────────────────────────────────────────────────
-- CLIENT-SIDE DIAGNOSTICS  (only registers on client)
-- ─────────────────────────────────────────────────────────────────
if not IsDuplicityVersion() then

    --- Run a full client-side environment check and print results
    local function RunClientDiagnostics()
        local results = {}
        local pass, fail, warn = 0, 0, 0

        local function check(label, value, expected, isWarn)
            local ok  = (expected == nil) and (value ~= nil and value ~= false)
                     or (value == expected)
            local sym = ok and (C.ok .. '✔') or (isWarn and (C.warn .. '?') or (C.err .. '✖'))
            results[#results+1] = string.format(
                '  %s %s%s %s→ %s',
                sym, C.reset, label, C.dim, tostring(value) .. C.reset
            )
            if ok then pass = pass + 1
            elseif isWarn then warn = warn + 1
            else fail = fail + 1 end
        end

        print('\n' .. PREFIX .. C.section
              .. ' ══════ CLIENT DIAGNOSTICS ══════' .. C.reset)

        -- ── Config checks ────────────────────────────────────────
        print(PREFIX .. C.info .. ' CONFIG' .. C.reset)
        check('Config loaded',            type(Config) == 'table')
        check('Config.Debug',             Config and Config.Debug,              nil, true)
        check('Config.MoneyType',         Config and Config.MoneyType ~= nil)
        check('Config.MaxLaps',           Config and (Config.MaxLaps or 0) > 0)
        check('Config.MinPlayers',        Config and (Config.MinPlayers or 0) >= 2)
        check('Config.F1CarModel',        Config and Config.F1CarModel ~= nil)
        check('Config.GridSpots count',   Config and #(Config.GridSpots or {}) >= 2)
        check('Config.TireCompounds',     Config and Config.TireCompounds ~= nil)
        check('Config.DRSZones',          Config and Config.DRSZones and #Config.DRSZones > 0)
        check('Config.Checkpoints',       Config and Config.Checkpoints and #Config.Checkpoints > 0)
        check('Config.Achievements',      Config and Config.Achievements and #Config.Achievements > 0)
        check('Config.PrizeMoney',        Config and (Config.PrizeMoney or 0) > 0)

        -- ── Exports / Dependencies ────────────────────────────────
        print(PREFIX .. C.info .. ' DEPENDENCIES' .. C.reset)

        local function safeExport(resource, fn)
            local ok, res = pcall(function() return exports[resource] end)
            return ok and res ~= nil
        end

        check('qbx_core export',     safeExport('qbx_core'))
        check('ox_lib export',       safeExport('ox_lib'))
        check('ox_target export',    safeExport('ox_target'))
        check('ox_inventory export', safeExport('ox_inventory'))

        local function resState(name)
            return GetResourceState(name)
        end

        check('qbx_core started',    resState('qbx_core')    == 'started')
        check('ox_lib started',      resState('ox_lib')      == 'started')
        check('ox_target started',   resState('ox_target')   == 'started')
        check('ox_inventory started',resState('ox_inventory')== 'started')
        check('oxmysql started',     resState('oxmysql')     == 'started')
        check('fcrp_f1 started',     resState('fcrp_f1')     == 'started')

        -- ── NUI / UI ──────────────────────────────────────────────
        print(PREFIX .. C.info .. ' NUI' .. C.reset)
        check('html/index.html exists', LoadResourceFile('fcrp_f1', 'html/index.html') ~= nil)

        -- ── Player state ──────────────────────────────────────────
        print(PREFIX .. C.info .. ' PLAYER STATE' .. C.reset)
        local ped = PlayerPedId()
        check('Ped valid',           ped and ped ~= 0)
        check('Not dead',            not IsEntityDead(ped))
        check('Has model loaded',    HasModelLoaded(GetEntityModel(ped)))
        local inVeh = IsPedInAnyVehicle(ped, false)
        check('In vehicle',          inVeh, nil, true)
        if inVeh then
            local veh    = GetVehiclePedIsIn(ped, false)
            local model  = GetEntityModel(veh)
            local isF1   = Config and (model == Config.F1CarModel)
            check('Vehicle is F1 car',   isF1, nil, true)
        end

        -- ── Summary ───────────────────────────────────────────────
        print(PREFIX .. C.section .. ' ══════ RESULT ══════' .. C.reset)
        for _, line in ipairs(results) do print(line) end
        print(string.format(
            '\n  %s✔ %d pass%s  %s⚠ %d warn%s  %s✖ %d fail%s\n',
            C.ok, pass, C.reset, C.warn, warn, C.reset, C.err, fail, C.reset
        ))

        if fail > 0 then
            DBGW('Diagnostics finished with ' .. fail .. ' failure(s). Check above for details.')
        else
            DBG(C.ok .. 'All critical checks passed.' .. C.reset)
        end
    end

    -- ─────────────────────────────────────────────────────────────
    -- /f1debug  CLIENT COMMAND
    -- ─────────────────────────────────────────────────────────────
    RegisterCommand('f1debug', function()
        RunClientDiagnostics()
    end, false)

    -- ─────────────────────────────────────────────────────────────
    -- /f1nuitest  — send a fake showResults NUI message for UI testing
    -- ─────────────────────────────────────────────────────────────
    RegisterCommand('f1nuitest', function(_, args)
        local action = args[1] or 'showResults'
        DBG('[NUI TEST] Sending test action: ' .. action)

        if action == 'showResults' then
            SendNUIMessage({
                action   = 'showResults',
                subtitle = 'DEBUG · TEST RACE',
                delay    = 20,
                xpTable  = Config and Config.XP or {100,80,60,40,25,15,8,4},
                mmrTable = Config and Config.MmrGain or {50,35,22,12,4,-4,-10,-18},
                winXp    = Config and Config.XP and Config.XP[1] or 100,
                flHolder = 'Shadow_FCG',
                flTime   = '1:32.441',
                results  = {
                    {pos=1, name='Shadow_FCG',  time='15:32.441', gap='WINNER'},
                    {pos=2, name='NightRacer7', time='15:35.112', gap='+2.671'},
                    {pos=3, name='Driver_You',  time='15:38.820', gap='+6.379'},
                    {pos=4, name='Velo_King',   time='15:42.001', gap='+9.560'},
                    {pos=nil, name='FCG_Rookie', dq=true, dqReason='Left vehicle'},
                },
            })
            SetNuiFocus(false, false)

        elseif action == 'showStats' then
            SendNUIMessage({
                action  = 'showStats',
                stats   = {
                    mmr=1847, xp=2340, wins=12, podiums=23,
                    races=38, fastest_laps=7, best_lap_ms=92441,
                },
                history = {
                    {position=1, race_time='15:32.441', best_lap='1:32.441', tyre_used='Soft',   race_date=os.time()},
                    {position=2, race_time='15:35.112', best_lap='1:33.102', tyre_used='Medium', race_date=os.time()},
                    {position=3, race_time='15:38.820', best_lap='1:34.009', tyre_used='Hard',   race_date=os.time()},
                    {position=5, race_time='16:02.750', best_lap='1:36.441', tyre_used='Soft',   race_date=os.time()},
                    {position=0, dq=1, dq_reason='Left vehicle', tyre_used='Hard',               race_date=os.time()},
                },
            })
            SetNuiFocus(true, true)

        elseif action == 'showLeaderboard' then
            SendNUIMessage({
                action = 'showLeaderboard',
                rows = {
                    {citizenid='Shadow_FCG',  mmr=2410, wins=31, races=54, podiums=48},
                    {citizenid='NightRacer7', mmr=2287, wins=24, races=51, podiums=40},
                    {citizenid='Driver_You',  mmr=1847, wins=12, races=38, podiums=23},
                    {citizenid='Velo_King',   mmr=1720, wins=9,  races=35, podiums=19},
                    {citizenid='ThrottleX',   mmr=1615, wins=7,  races=31, podiums=15},
                },
            })
            SetNuiFocus(true, true)

        elseif action == 'organizer' then
            SendNUIMessage({
                action     = 'openOrganizerMenu',
                playerList = {
                    {id=1, name='Shadow_FCG'},
                    {id=2, name='NightRacer7'},
                    {id=3, name='Driver_You'},
                },
                slotLabels = {
                    [1] = 'Shadow_FCG',
                    [2] = 'NightRacer7',
                },
            })
            SetNuiFocus(true, true)

        elseif action == 'spec' then
            SendNUIMessage({action='specUpdate', name='Shadow_FCG', info='LAP 3 · P1'})

        elseif action == 'cam' then
            SendNUIMessage({action='camMode', label='Follow'})

        elseif action == 'hide' then
            SendNUIMessage({action='hideResults'})
            SendNUIMessage({action='specHide'})
            SendNUIMessage({action='camHide'})
            SetNuiFocus(false, false)
        else
            print(PREFIX .. C.warn .. ' Unknown test action: ' .. action)
            print(PREFIX .. C.info .. ' Available: showResults | showStats | showLeaderboard | organizer | spec | cam | hide')
        end
    end, false)

    -- Print usage tip on resource start
    AddEventHandler('onClientResourceStart', function(res)
        if res ~= GetCurrentResourceName() then return end
        if Config and Config.Debug then
            print('\n' .. PREFIX .. C.ok
                  .. ' Debug mode is ON. Commands available:' .. C.reset)
            print('  ' .. C.info .. '/f1debug' .. C.reset
                  .. '                 — run full client diagnostics')
            print('  ' .. C.info .. '/f1nuitest [action]' .. C.reset
                  .. '  — test NUI panels: showResults | showStats | showLeaderboard | organizer | spec | cam | hide')
            print('  ' .. C.info .. '/f1debug_server' .. C.reset
                  .. '          — run server-side diagnostics (chat command)\n')
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────
-- SERVER-SIDE DIAGNOSTICS  (only registers on server)
-- ─────────────────────────────────────────────────────────────────
if IsDuplicityVersion() then

    local function RunServerDiagnostics(src)
        local results = {}
        local pass, fail, warn = 0, 0, 0

        local function check(label, value, expected, isWarn)
            local ok  = (expected == nil) and (value ~= nil and value ~= false)
                     or (value == expected)
            local sym = ok and '✔' or (isWarn and '?' or '✖')
            results[#results+1] = {sym=sym, ok=ok, warn=(not ok and isWarn), label=label, val=tostring(value)}
            if ok then pass = pass + 1
            elseif isWarn then warn = warn + 1
            else fail = fail + 1 end
        end

        -- Config
        check('Config.Debug',             Config.Debug,           nil, true)
        check('Config.MoneyType',         Config.MoneyType        ~= nil)
        check('Config.OrganizerPerm',     Config.OrganizerPermission ~= nil)
        check('Config.MaxLaps > 0',       (Config.MaxLaps or 0)   > 0)
        check('Config.MinPlayers >= 2',   (Config.MinPlayers or 0) >= 2)
        check('Config.GridSpots >= 2',    #(Config.GridSpots or {}) >= 2)
        check('Config.Checkpoints',       #(Config.Checkpoints or {}) > 0)
        check('Config.TireCompounds',     Config.TireCompounds    ~= nil)
        check('Config.PrizeMoney > 0',    (Config.PrizeMoney or 0) > 0)
        check('Config.Items',             Config.Items            ~= nil)
        check('Config.PitStop',           Config.PitStop          ~= nil)
        check('Config.DRSZones',          #(Config.DRSZones or {}) > 0)

        -- Resources
        local function rs(name) return GetResourceState(name) == 'started' end
        check('qbx_core started',    rs('qbx_core'))
        check('ox_lib started',      rs('ox_lib'))
        check('ox_target started',   rs('ox_target'))
        check('ox_inventory started',rs('ox_inventory'))
        check('oxmysql started',     rs('oxmysql'))

        -- oxmysql ping
        local dbOk = false
        MySQL.Async.fetchScalar('SELECT 1', {}, function(v)
            dbOk = (v == 1)
        end)
        Wait(500)
        check('oxmysql connection',  dbOk)

        -- Active players
        local online = #GetActivePlayers()
        check('Players online',      online >= 0, nil, true)

        -- Print to server console
        DBG_SECTION('SERVER DIAGNOSTICS')
        for _, r in ipairs(results) do
            local col = r.ok and C.ok or (r.warn and C.warn or C.err)
            print(string.format('  %s%s %s%s → %s',
                col, r.sym, C.reset, r.label, C.dim .. r.val .. C.reset))
        end
        print(string.format(
            '\n  %s✔ %d pass%s  %s⚠ %d warn%s  %s✖ %d fail%s\n',
            C.ok, pass, C.reset, C.warn, warn, C.reset, C.err, fail, C.reset
        ))

        -- Also send to the requesting player's chat if online
        if src and src > 0 then
            local lines = {}
            for _, r in ipairs(results) do
                lines[#lines+1] = string.format('%s %s → %s', r.sym, r.label, r.val)
            end
            lines[#lines+1] = string.format('✔ %d pass | ⚠ %d warn | ✖ %d fail', pass, warn, fail)
            TriggerClientEvent('chat:addMessage', src, {
                color  = {168, 85, 247},
                multiline = true,
                args   = {'[FCRP_F1 Debug]', table.concat(lines, '\n')},
            })
        end
    end

    -- /f1debug_server  — run diagnostics from in-game chat (admin only)
    lib.addCommand('f1debug_server', {
        help = 'Run FCRP F1 server diagnostics (admin only)',
    }, function(source)
        local src = source
        if not IsOrganiser(src) and src ~= 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title='Access Denied', type='error'
            }); return
        end
        RunServerDiagnostics(src)
    end)

    -- Also run diagnostics automatically on resource start if Debug = true
    AddEventHandler('onServerResourceStart', function(res)
        if res ~= GetCurrentResourceName() then return end
        print(PREFIX .. C.ok .. ' Resource started (v3.0)' .. C.reset)
        if Config.Debug then
            Wait(1500) -- give oxmysql a moment
            RunServerDiagnostics(0)
        end
    end)
end
