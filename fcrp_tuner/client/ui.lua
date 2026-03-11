-- ╔══════════════════════════════════════════════╗
-- ║       fcrp_tuner  |  client/ui.lua          ║
-- ║     NUI bridge — sends data to html/index   ║
-- ╚══════════════════════════════════════════════╝

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function Send(type, data)
    SendNUIMessage({ type = type, data = data })
end

-- ─────────────────────────────────────────────
--  SHOP MENU
-- ─────────────────────────────────────────────

function UI_OpenShop(items, subtitle)
    SetNuiFocus(true, true)
    Send('openShop', { items = items, subtitle = '' })
end

function UI_CloseShop()
    SetNuiFocus(false, false)
    Send('closeShop', {})
end

RegisterNUICallback('shopClosed', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('shopAction', function(data, cb)
    cb('ok')
    TriggerEvent('fcrp_tuner:client:shopAction', data.action, data.data or {})
end)

-- ─────────────────────────────────────────────
--  STANCE EDITOR
-- ─────────────────────────────────────────────

function UI_OpenStance()
    Send('openStance', {})
end

function UI_CloseStance()
    Send('closeStance', {})
end

function UI_UpdateStance(selected, height, camberF, camberR)
    local cfg = Config.StanceKit
    Send('updateStance', {
        selected   = selected,
        height     = height,
        camberf    = camberF,
        camberr    = camberR,
        heightMin  = cfg.rideHeightMin,
        heightMax  = cfg.rideHeightMax,
        camberMin  = cfg.camberMin,
        camberMax  = cfg.camberMax,
    })
end

-- ─────────────────────────────────────────────
--  NOS HUD
-- ─────────────────────────────────────────────

function UI_ShowNos(show)
    SendNUIMessage({ type = 'showNos', show = show })
end

function UI_UpdateNos(state, progress, countdown)
    Send('updateNos', {
        state     = state,       -- 'ready' | 'active' | 'empty' | 'cooldown'
        progress  = progress,    -- 0.0 – 1.0
        countdown = countdown,   -- string e.g. "4.2s" or "28m 30s"
    })
end
