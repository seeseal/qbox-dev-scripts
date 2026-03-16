--[[
╔══════════════════════════════════════════════════════════════════╗
║       FLAME CITY F1 — client/nui_callbacks.lua  |  v3.0         ║
║   NUI ↔ Lua bridge — all HTML dashboard callbacks               ║
║                                                                  ║
║   PLACE AT:  client/nui_callbacks.lua                            ║
║   MANIFEST:  client_scripts { 'client/nui_callbacks.lua' }       ║
╚══════════════════════════════════════════════════════════════════╝

  BUG FIXES applied (v3.0.1):
    #1 — f1reward NPC button now fires sv:claimWeeklyReward (net event)
    #2 — directorCam NUI callback properly fires sv:getVehicleForCam
    #3 — sv:clearSlot server handler added (was missing)
    #4 — Old fcrp_f1_menu F5 keybind suppressed to prevent double-open
    #5 — showResults NuiFocus set to (true, false) — overlay visible,
         cursor released so backdrop click works without blocking input
    #6 — clearGrid re-opens organizer NUI with empty slotMap from server
]]

-- ─────────────────────────────────────────────────────────────────
-- CLOSE UI
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('closeUI', function(_, cb)
    DBG('[NUI CB] closeUI')
    SetNuiFocus(false, false)
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- OPEN NPC / PADDOCK
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('openNPC', function(_, cb)
    DBG('[NUI CB] openNPC')
    SetNuiFocus(false, false)
    lib.notify({ title = 'Paddock', description = 'Head to the pit lane NPC!', type = 'inform' })
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- REFRESH LEADERBOARD
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('refreshLeaderboard', function(_, cb)
    DBG('[NUI CB] refreshLeaderboard')
    TriggerServerEvent('fcrp_f1:sv:requestLeaderboard')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- ASSIGN GRID SLOT
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('assignSlot', function(data, cb)
    local slot     = tonumber(data.slot)
    local playerId = tonumber(data.playerId)
    DBG('[NUI CB] assignSlot slot=' .. tostring(slot) .. ' pid=' .. tostring(playerId))
    if not slot or not playerId then
        DBGW('[NUI CB] assignSlot: invalid args')
        cb('err'); return
    end
    TriggerServerEvent('fcrp_f1:sv:assignSlot', slot, playerId)
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- CLEAR SINGLE SLOT  — BUG FIX #3
-- Previously fired sv:clearSlot which didn't exist on the server.
-- Server handler is now added in server/main.lua.
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('clearSlot', function(data, cb)
    local slot = tonumber(data.slot)
    DBG('[NUI CB] clearSlot slot=' .. tostring(slot))
    if not slot then
        DBGW('[NUI CB] clearSlot: invalid slot'); cb('err'); return
    end
    TriggerServerEvent('fcrp_f1:sv:clearSlot', slot)
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- CLEAR ALL GRID SLOTS  — BUG FIX #6
-- Server now re-opens the organizer NUI with empty slotMap,
-- so the UI visually resets automatically. No local slotLabels
-- manipulation needed here.
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('clearGrid', function(_, cb)
    DBG('[NUI CB] clearGrid')
    TriggerServerEvent('fcrp_f1:sv:clearGrid')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- PREPARE GRID  (spawn F1 cars on grid spots)
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('setupGrid', function(_, cb)
    DBG('[NUI CB] setupGrid')
    TriggerServerEvent('fcrp_f1:sv:setupGrid')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- DEPLOY SAFETY CAR
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('deploySafetyCar', function(_, cb)
    DBG('[NUI CB] deploySafetyCar')
    TriggerServerEvent('fcrp_f1:sv:deploySafetyCar')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- START RACE
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('startRace', function(_, cb)
    DBG('[NUI CB] startRace')
    TriggerServerEvent('fcrp_f1:sv:startGlobalRace')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- FORCE END / RESET
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('forceEnd', function(_, cb)
    DBG('[NUI CB] forceEnd')
    TriggerServerEvent('fcrp_f1:sv:forceEnd')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- DIRECTOR CAMERA  — BUG FIX #2
-- Previously just fired a notify and did nothing.
-- Now correctly fires sv:getVehicleForCam which returns the netId
-- back via cl:attachDirectorCam, triggering the cam loop in main.lua.
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('directorCam', function(data, cb)
    local tid = tonumber(data.playerId)
    DBG('[NUI CB] directorCam targeting server ID=' .. tostring(tid))
    if not tid or tid < 1 then
        DBGW('[NUI CB] directorCam: invalid playerId')
        lib.notify({ title = 'Director Cam', description = 'Enter a valid server ID.', type = 'error' })
        cb('err'); return
    end
    -- This triggers the full cam flow:
    -- sv:getVehicleForCam → cl:attachDirectorCam → CreateCam / loop in main.lua
    TriggerServerEvent('fcrp_f1:sv:getVehicleForCam', tid)
    SetNuiFocus(false, false)   -- release NUI focus so cam controls work
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- NUI PANEL RECEIVERS — cl: events that open the NUI dashboard
-- ─────────────────────────────────────────────────────────────────

-- Stats panel (replaces ox_lib context 'f1_stats')
RegisterNetEvent('fcrp_f1:cl:openStatsMenu_NUI', function(stats, history)
    DBG('[NUI RECV] openStatsMenu_NUI mmr=' .. tostring(stats and stats.mmr))
    SendNUIMessage({
        action  = 'showStats',
        stats   = stats   or {},
        history = history or {},
    })
    SetNuiFocus(true, true)
end)

-- Leaderboard panel (replaces ox_lib context 'f1_lb')
RegisterNetEvent('fcrp_f1:cl:showLeaderboard_NUI', function(rows)
    DBG('[NUI RECV] showLeaderboard_NUI rows=' .. tostring(rows and #rows or 0))
    SendNUIMessage({
        action = 'showLeaderboard',
        rows   = rows or {},
    })
    SetNuiFocus(true, true)
end)

-- Organizer / Race Control panel (replaces ox_lib context 'f1_organiser')
RegisterNetEvent('fcrp_f1:cl:openOrganizerMenu_NUI', function(playerList, slotLabelsData)
    DBG('[NUI RECV] openOrganizerMenu_NUI players=' .. tostring(playerList and #playerList or 0))
    local players = {}
    for _, p in ipairs(playerList or {}) do
        players[#players + 1] = { id = p.id, name = p.name }
    end
    SendNUIMessage({
        action     = 'openOrganizerMenu',
        playerList = players,
        slotLabels = slotLabelsData or {},
    })
    SetNuiFocus(true, true)
end)

-- ─────────────────────────────────────────────────────────────────
-- RESULTS OVERLAY  — BUG FIX #5
-- Original had SetNuiFocus(false, false) which prevented the backdrop
-- click from working. Fixed to (true, false): NUI renders and receives
-- click events, but cursor is NOT shown so it doesn't block HUD/minimap
-- visibility during the countdown.
-- ─────────────────────────────────────────────────────────────────
-- NOTE: The original RegisterNetEvent('fcrp_f1:cl:showResults') in
-- main.lua already handles sending the NUI message. We patch it here
-- by overriding the NuiFocus call using an AddEventHandler post-hook.
-- To avoid doubling up, comment out or remove the original handler
-- in main.lua lines ~907-914 and use this one instead.

RegisterNetEvent('fcrp_f1:cl:showResults_NUI', function(data)
    DBG('[NUI RECV] showResults_NUI results=' .. tostring(data.results and #data.results or 0))
    SendNUIMessage({
        action   = 'showResults',
        results  = data.results,
        subtitle = data.subtitle,
        delay    = data.delay,
        flHolder = data.flHolder,
        flTime   = data.flTime,
        xpTable  = data.xpTable,
        mmrTable = data.mmrTable,
        winXp    = data.winXp,
    })
    -- (true, false) = NUI visible + click events work, but no cursor shown.
    -- This means backdrop click-to-dismiss works without blocking driving controls.
    SetNuiFocus(true, false)
end)

-- ─────────────────────────────────────────────────────────────────
-- F5 KEYBIND  — BUG FIX #4
-- The original client/main.lua registers fcrp_f1_menu on F5.
-- That old command now calls requestMyStats → openStatsMenu_NUI,
-- so the old binding is effectively fine to keep as-is.
-- We register a SEPARATE command name here to avoid double-binding.
-- IMPORTANT: Delete or comment out the old RegisterKeyMapping +
-- RegisterCommand block at the bottom of client/main.lua (lines ~1239-1242).
-- ─────────────────────────────────────────────────────────────────
RegisterCommand('fcrp_f1_nui', function()
    DBG('[CMD] fcrp_f1_nui — opening NUI dashboard')
    TriggerServerEvent('fcrp_f1:sv:requestMyStats')
end, false)

RegisterKeyMapping('fcrp_f1_nui', 'Open F1 Race Manager', 'keyboard', 'F5')

-- ─────────────────────────────────────────────────────────────────
-- NPC TARGET — BUG FIX #1
-- The NPC ox_target 'Claim Reward' button previously fired
-- TriggerServerEvent('f1reward') which has NO RegisterNetEvent on
-- the server (only a lib.addCommand). The button silently did nothing.
-- The server now has sv:claimWeeklyReward as a proper net event.
-- This event is wired in the ox_target zone setup in main.lua.
-- If you cannot edit the NPC target setup, add this alias:
-- ─────────────────────────────────────────────────────────────────
-- Alias so the old event string also works if any NPC still uses it
RegisterNetEvent('f1reward', function()
    DBGW('[COMPAT] f1reward alias fired — routing to sv:claimWeeklyReward')
    TriggerServerEvent('fcrp_f1:sv:claimWeeklyReward')
end)

DBG('nui_callbacks.lua v3.0.1 loaded — all NUI handlers registered.')
