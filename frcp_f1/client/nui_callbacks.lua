--[[
╔══════════════════════════════════════════════════════════════════╗
║        FLAME CITY F1 — NUI Callbacks Patch (v3.0 UI)            ║
║   Add these to the BOTTOM of your client/main.lua               ║
╚══════════════════════════════════════════════════════════════════╝

  These NUI callbacks let the HTML dashboard communicate back to
  the Lua client. Each button in the new UI triggers one of these.
]]

-- ─────────────────────────────────────────────────────────────────
-- CLOSE UI
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('closeUI', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- OPEN NPC / PADDOCK  (redirect to NPC interaction)
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('openNPC', function(_, cb)
    SetNuiFocus(false, false)
    -- Teleport player to spectator vantage or just close —
    -- optionally re-open the ox_target NPC zone hint
    lib.notify({ title='Paddock', description='Head to the pit lane NPC!', type='inform' })
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- REFRESH LEADERBOARD  (button in leaderboard panel)
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('refreshLeaderboard', function(_, cb)
    TriggerServerEvent('fcrp_f1:sv:requestLeaderboard')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- ASSIGN SLOT  (organiser grid slot button)
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('assignSlot', function(data, cb)
    local slot     = tonumber(data.slot)
    local playerId = tonumber(data.playerId)
    if not slot or not playerId then cb('err'); return end
    TriggerServerEvent('fcrp_f1:sv:assignSlot', slot, playerId)
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- CLEAR SINGLE SLOT
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('clearSlot', function(data, cb)
    local slot = tonumber(data.slot)
    if slot then TriggerServerEvent('fcrp_f1:sv:clearSlot', slot) end
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- CLEAR ALL GRID SLOTS
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('clearGrid', function(_, cb)
    slotLabels = {}
    TriggerServerEvent('fcrp_f1:sv:clearGrid')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- SETUP GRID  (spawn cars on grid spots)
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('setupGrid', function(_, cb)
    TriggerServerEvent('fcrp_f1:sv:setupGrid')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- DEPLOY SAFETY CAR  (formation lap)
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('deploySafetyCar', function(_, cb)
    TriggerServerEvent('fcrp_f1:sv:deploySafetyCar')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- START RACE
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('startRace', function(_, cb)
    TriggerServerEvent('fcrp_f1:sv:startGlobalRace')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- FORCE END
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('forceEnd', function(_, cb)
    TriggerServerEvent('fcrp_f1:sv:forceEnd')
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- DIRECTOR CAMERA
-- ─────────────────────────────────────────────────────────────────
RegisterNUICallback('directorCam', function(data, cb)
    local tid = tonumber(data.playerId)
    if not tid then cb('err'); return end
    -- Reuse the existing director cam logic from the client
    -- You can call OpenDirectorCamWithTarget(tid) if you refactor
    -- that function, or fire the same logic inline:
    local netId = GetPlayerServerId(GetPlayerFromServerId and tid or 0)
    -- Fallback: just notify for now, wire to your cam function
    lib.notify({ title='Director Cam', description='Targeting server ID: '..tid, type='inform' })
    cb('ok')
end)

-- ─────────────────────────────────────────────────────────────────
-- UPDATE: patch openStatsMenu to send NUI instead of ox_lib context
-- ─────────────────────────────────────────────────────────────────
-- Replace the existing RegisterNetEvent('fcrp_f1:cl:openStatsMenu') with:

RegisterNetEvent('fcrp_f1:cl:openStatsMenu_NUI', function(stats, history)
    SendNUIMessage({
        action  = 'showStats',
        stats   = stats,
        history = history,
    })
    SetNuiFocus(true, true)
end)

-- ─────────────────────────────────────────────────────────────────
-- UPDATE: patch showLeaderboard to send NUI instead of ox_lib context
-- ─────────────────────────────────────────────────────────────────
RegisterNetEvent('fcrp_f1:cl:showLeaderboard_NUI', function(rows)
    SendNUIMessage({
        action = 'showLeaderboard',
        rows   = rows,
    })
    SetNuiFocus(true, true)
end)

-- ─────────────────────────────────────────────────────────────────
-- UPDATE: patch openOrganizerMenu to send NUI
-- ─────────────────────────────────────────────────────────────────
RegisterNetEvent('fcrp_f1:cl:openOrganizerMenu_NUI', function(playerList, slotLabelsData)
    -- Format player list for the UI
    local players = {}
    for _, p in ipairs(playerList or {}) do
        players[#players+1] = { id = p.id, name = p.name }
    end
    SendNUIMessage({
        action      = 'openOrganizerMenu',
        playerList  = players,
        slotLabels  = slotLabelsData or slotLabels or {},
    })
    SetNuiFocus(true, true)
end)

-- ─────────────────────────────────────────────────────────────────
-- F5 KEY: open NUI dashboard  (replace the existing command handler)
-- ─────────────────────────────────────────────────────────────────
-- The F5 command now opens the NUI dashboard with player stats.
-- Replace the existing 'fcrp_f1_menu' RegisterCommand with:

RegisterCommand('fcrp_f1_menu_nui', function()
    TriggerServerEvent('fcrp_f1:sv:requestMyStats')   -- will fire cl:openStatsMenu_NUI
end)
RegisterKeyMapping('fcrp_f1_menu_nui', 'Open F1 Race Manager (NUI)', 'keyboard', 'F5')
