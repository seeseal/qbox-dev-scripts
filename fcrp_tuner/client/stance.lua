-- ╔══════════════════════════════════════════════╗
-- ║      fcrp_tuner  |  client/stance.lua       ║
-- ╚══════════════════════════════════════════════╝

local stanceActive = false

local stanceCamberF   = 0.0
local stanceCamberR   = 0.0
local stanceHeight    = 0.0

local function Notify(msg, ntype, duration)
    lib.notify({ title = msg, type = ntype or 'inform', duration = duration or 3000 })
end

-- ─────────────────────────────────────────────
--  HELPERS
-- ─────────────────────────────────────────────

local function Clamp(v, mn, mx) return math.max(mn, math.min(mx, v)) end

local function ApplyStance(veh, camberF, camberR, height)
    SetVehicleHandlingFloat(veh, 'CHandlingData',    'fSuspensionRaise', height)
    SetVehicleHandlingFloat(veh, 'CCarHandlingData', 'fCamberFront',     camberF)
    SetVehicleHandlingFloat(veh, 'CCarHandlingData', 'fCamberRear',      camberR)
end

local function ClearStance(veh)
    SetVehicleHandlingFloat(veh, 'CHandlingData',    'fSuspensionRaise', 0.0)
    SetVehicleHandlingFloat(veh, 'CCarHandlingData', 'fCamberFront',     0.0)
    SetVehicleHandlingFloat(veh, 'CCarHandlingData', 'fCamberRear',      0.0)
end

local selectedProp = 1

-- ─────────────────────────────────────────────
--  EDITOR THREAD
-- ─────────────────────────────────────────────

local function OpenStanceEditor(veh)
    if stanceActive then return end
    stanceActive = true
    selectedProp = 1

    local cfg = Config.StanceKit

    local function DisableConflicts()
        DisableControlAction(0, 172, true)
        DisableControlAction(0, 173, true)
        DisableControlAction(0, 174, true)
        DisableControlAction(0, 175, true)
        DisableControlAction(0, 191, true)
        DisableControlAction(0, 194, true)
    end

    UI_OpenStance()
    UI_UpdateStance(selectedProp, stanceHeight, stanceCamberF, stanceCamberR)
    Notify('~y~Stance editor open~w~ — arrow keys to adjust, ENTER to save', 'inform', 5000)

    CreateThread(function()
        while stanceActive do
            Wait(0)
            DisableConflicts()

            if IsDisabledControlJustPressed(0, 172) then
                selectedProp = (selectedProp == 1) and 3 or (selectedProp - 1)
                UI_UpdateStance(selectedProp, stanceHeight, stanceCamberF, stanceCamberR)
            elseif IsDisabledControlJustPressed(0, 173) then
                selectedProp = (selectedProp == 3) and 1 or (selectedProp + 1)
                UI_UpdateStance(selectedProp, stanceHeight, stanceCamberF, stanceCamberR)
            end

            local step = (selectedProp == 1) and cfg.rideHeightStep or cfg.camberStep
            local mn   = (selectedProp == 1) and cfg.rideHeightMin  or cfg.camberMin
            local mx   = (selectedProp == 1) and cfg.rideHeightMax  or cfg.camberMax

            if IsControlPressed(0, 21) then step = step * 10 end

            local changed = false
            if IsDisabledControlJustPressed(0, 174) then
                if selectedProp == 1 then
                    stanceHeight  = Clamp(stanceHeight  - step, mn, mx)
                elseif selectedProp == 2 then
                    stanceCamberF = Clamp(stanceCamberF - step, mn, mx)
                else
                    stanceCamberR = Clamp(stanceCamberR - step, mn, mx)
                end
                changed = true
            elseif IsDisabledControlJustPressed(0, 175) then
                if selectedProp == 1 then
                    stanceHeight  = Clamp(stanceHeight  + step, mn, mx)
                elseif selectedProp == 2 then
                    stanceCamberF = Clamp(stanceCamberF + step, mn, mx)
                else
                    stanceCamberR = Clamp(stanceCamberR + step, mn, mx)
                end
                changed = true
            end

            if changed then
                ApplyStance(veh, stanceCamberF, stanceCamberR, stanceHeight)
                UI_UpdateStance(selectedProp, stanceHeight, stanceCamberF, stanceCamberR)
            end

            -- ENTER — save
            if IsDisabledControlJustPressed(0, 191) then
                stanceActive = false
                ApplyStance(veh, stanceCamberF, stanceCamberR, stanceHeight)
                TriggerServerEvent('fcrp_tuner:server:saveStance',
                    NetworkGetNetworkIdFromEntity(veh),
                    stanceCamberF, stanceCamberR, stanceHeight)
                UI_CloseStance()
                Notify(Lang:t('stance_saved'), 'success', 3000)
            end

            -- BACKSPACE — cancel
            if IsDisabledControlJustPressed(0, 194) then
                stanceActive = false
                ClearStance(veh)
                UI_CloseStance()
                Notify(Lang:t('stance_cancelled'), 'error', 3000)
            end
        end
    end)
end

-- ─────────────────────────────────────────────
--  EVENTS
-- ─────────────────────────────────────────────

AddEventHandler('fcrp_tuner:client:openStance', function(veh)
    if not veh or not DoesEntityExist(veh) then
        lib.notify({ title = 'Vehicle not found.', type = 'error', duration = 3000 })
        return
    end
    stanceHeight  = GetVehicleHandlingFloat(veh, 'CHandlingData',    'fSuspensionRaise') or 0.0
    stanceCamberF = GetVehicleHandlingFloat(veh, 'CCarHandlingData', 'fCamberFront')     or 0.0
    stanceCamberR = GetVehicleHandlingFloat(veh, 'CCarHandlingData', 'fCamberRear')      or 0.0
    OpenStanceEditor(veh)
end)

AddEventHandler('fcrp_tuner:client:applyStance', function(veh, camberF, height, camberR)
    if not veh or not DoesEntityExist(veh) then return end
    stanceCamberF = camberF or 0.0
    stanceCamberR = camberR or 0.0
    stanceHeight  = height  or 0.0
    ApplyStance(veh, stanceCamberF, stanceCamberR, stanceHeight)
end)

AddEventHandler('fcrp_tuner:client:stanceRemoved', function(veh)
    if not veh or not DoesEntityExist(veh) then return end
    stanceActive  = false
    stanceCamberF = 0.0
    stanceCamberR = 0.0
    stanceHeight  = 0.0
    ClearStance(veh)
end)
