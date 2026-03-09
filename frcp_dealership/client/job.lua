-- ============================================
--  frcp_dealership | client/job.lua  v2.0
--
--  WHAT THIS FILE DOES (plain English):
--  ─────────────────────────────────────
--  Sets up three physical zones inside the
--  dealership that employees can interact with:
--
--  1. CLOCK-IN / CLOCK-OUT ZONE
--     Walk up and press E to go on or off duty.
--     Going on duty opens the employee panel
--     in the NUI and sets your job duty flag.
--
--  2. STASH ZONE
--     Only accessible while on duty.
--     Opens the shared employee stash (ox_inventory).
--
--  3. CHANGING ROOM ZONE
--     Only accessible while on duty.
--     Either applies your uniform outfit or opens
--     a clothing selection menu.
--
--  All zones use ox_target so players see a
--  context-menu prompt rather than a key hint.
-- ============================================

local isOnDuty    = false
local savedOutfit = nil  -- stores the player's civilian outfit before putting on uniform

-- ============================================
--  Helper: is the local player a dealership employee?
-- ============================================

local function isEmployee()
    local player = exports.qbx_core:GetPlayerData()
    return player and player.job and player.job.name == Config.JobName
end

local function getGradeData()
    local player = exports.qbx_core:GetPlayerData()
    if not player or not player.job then return nil end
    return Config.JobGrades[player.job.grade.level]
end

-- ============================================
--  Save current outfit (before uniform)
-- ============================================

local function saveCurrentOutfit()
    local ped = PlayerPedId()
    savedOutfit = {}
    -- Save all main clothing components
    local components = {3, 4, 5, 6, 7, 8, 9, 10, 11}
    for _, comp in ipairs(components) do
        table.insert(savedOutfit, {
            component = comp,
            drawable  = GetPedDrawableVariation(ped, comp),
            texture   = GetPedTextureVariation(ped, comp),
        })
    end
end

-- ============================================
--  Apply uniform outfit
-- ============================================

local function applyUniform()
    if #Config.EmployeeOutfit == 0 then
        -- No outfit configured — open ox_lib context menu to let them pick
        lib.notify({ type = 'inform', title = 'Changing Room', description = 'No uniform configured. Contact your admin.' })
        return
    end

    local ped = PlayerPedId()
    saveCurrentOutfit()

    for _, item in ipairs(Config.EmployeeOutfit) do
        SetPedComponentVariation(ped, item.component, item.drawable, item.texture, 0)
    end

    lib.notify({ type = 'success', title = 'Changing Room', description = 'Uniform on. Looking sharp!' })
end

-- ============================================
--  Restore civilian outfit
-- ============================================

local function restoreOutfit()
    if not savedOutfit then return end
    local ped = PlayerPedId()
    for _, item in ipairs(savedOutfit) do
        SetPedComponentVariation(ped, item.component, item.drawable, item.texture, 0)
    end
    savedOutfit = nil
    lib.notify({ type = 'inform', title = 'Changing Room', description = 'Uniform removed.' })
end

-- ============================================
--  Clock In
-- ============================================

local function clockIn()
    if not isEmployee() then
        lib.notify({ type = 'error', description = 'You are not a FlameDrive employee.' })
        return
    end
    if isOnDuty then
        lib.notify({ type = 'inform', description = 'You are already on duty.' })
        return
    end

    isOnDuty = true
    exports.qbx_core:SetDuty(true)

    lib.notify({
        type        = 'success',
        title       = 'FlameDrive Motors',
        description = 'You are now on duty. Use the stash and changing room nearby.',
        duration    = 6000
    })
end

-- ============================================
--  Clock Out
-- ============================================

local function clockOut()
    if not isOnDuty then
        lib.notify({ type = 'inform', description = 'You are not currently on duty.' })
        return
    end

    isOnDuty = false
    exports.qbx_core:SetDuty(false)

    -- Auto-remove uniform when clocking out
    if savedOutfit then restoreOutfit() end

    lib.notify({
        type        = 'inform',
        title       = 'FlameDrive Motors',
        description = 'You are now off duty.',
        duration    = 5000
    })
end

-- ============================================
--  ZONE 1 — Clock-In / Clock-Out
-- ============================================

exports.ox_target:addBoxZone({
    coords  = Config.OnDutyCoords,
    size    = vec3(1.5, 1.5, 2.0),
    rotation = 0,
    options = {
        {
            label    = "Clock In",
            icon     = "fas fa-sign-in-alt",
            distance = 2.0,
            canInteract = function()
                return isEmployee() and not isOnDuty
            end,
            onSelect = function()
                clockIn()
            end
        },
        {
            label    = "Clock Out",
            icon     = "fas fa-sign-out-alt",
            distance = 2.0,
            canInteract = function()
                return isEmployee() and isOnDuty
            end,
            onSelect = function()
                clockOut()
            end
        },
    }
})

-- ============================================
--  ZONE 2 — Employee Stash
-- ============================================

exports.ox_target:addBoxZone({
    coords  = Config.StashCoords,
    size    = vec3(1.5, 1.5, 2.0),
    rotation = 0,
    options = {
        {
            label    = "Employee Stash",
            icon     = "fas fa-box",
            distance = 2.0,
            canInteract = function()
                return isEmployee() and isOnDuty
            end,
            onSelect = function()
                exports.ox_inventory:openInventory('stash', {
                    id     = Config.StashId,
                    slots  = Config.StashSlots,
                    weight = Config.StashWeight,
                })
            end
        },
        {
            label    = "Stash (Off Duty — Access Denied)",
            icon     = "fas fa-lock",
            distance = 2.0,
            canInteract = function()
                return isEmployee() and not isOnDuty
            end,
            onSelect = function()
                lib.notify({ type = 'error', description = 'You must be on duty to access the stash.' })
            end
        },
    }
})

-- ============================================
--  ZONE 3 — Changing Room
-- ============================================

exports.ox_target:addBoxZone({
    coords  = Config.ChangingRoomCoords,
    size    = vec3(1.5, 1.5, 2.0),
    rotation = 0,
    options = {
        {
            label    = "Put On Uniform",
            icon     = "fas fa-tshirt",
            distance = 2.0,
            canInteract = function()
                return isEmployee() and isOnDuty and savedOutfit == nil
            end,
            onSelect = function()
                applyUniform()
            end
        },
        {
            label    = "Remove Uniform",
            icon     = "fas fa-user",
            distance = 2.0,
            canInteract = function()
                return isEmployee() and isOnDuty and savedOutfit ~= nil
            end,
            onSelect = function()
                restoreOutfit()
            end
        },
        {
            label    = "Changing Room (Off Duty — Access Denied)",
            icon     = "fas fa-lock",
            distance = 2.0,
            canInteract = function()
                return isEmployee() and not isOnDuty
            end,
            onSelect = function()
                lib.notify({ type = 'error', description = 'Clock in first to use the changing room.' })
            end
        },
    }
})

-- ============================================
--  Boss Menu — ox_target on a boss desk/object
--  Uses ox_lib context menu for actions
-- ============================================

-- We attach boss menu to a zone near the on-duty marker
-- !! CHANGE ME !! — set coords to your boss desk location
local BOSS_DESK_COORDS = vec3(-950.5, -491.5, 35.84)

exports.ox_target:addBoxZone({
    coords   = BOSS_DESK_COORDS,
    size     = vec3(1.5, 1.5, 1.2),
    rotation = 0,
    options  = {
        {
            label    = "Boss Menu",
            icon     = "fas fa-briefcase",
            distance = 2.0,
            canInteract = function()
                local gradeData = getGradeData()
                return gradeData and gradeData.isBoss and isOnDuty
            end,
            onSelect = function()
                openBossMenu()
            end
        }
    }
})

function openBossMenu()
    lib.registerContext({
        id    = 'flamedrive_boss_menu',
        title = '🔑 GM Panel — FlameDrive Motors',
        options = {
            {
                title       = '💰 Society Fund',
                description = 'View balance and withdraw funds',
                icon        = 'fas fa-piggy-bank',
                onSelect    = function()
                    TriggerServerEvent('frcp_dealership:server:getSocietyBalance')
                end
            },
            {
                title       = '👔 Hire Employee',
                description = 'Enter the server ID of the player to hire',
                icon        = 'fas fa-user-plus',
                onSelect    = function()
                    local input = lib.inputDialog('Hire Employee', {
                        { type = 'number', label = 'Player Server ID', required = true }
                    })
                    if input and input[1] then
                        TriggerServerEvent('frcp_dealership:server:hire', tonumber(input[1]))
                    end
                end
            },
            {
                title       = '🚪 Fire Employee',
                description = 'Enter the server ID of the player to fire',
                icon        = 'fas fa-user-minus',
                onSelect    = function()
                    local input = lib.inputDialog('Fire Employee', {
                        { type = 'number', label = 'Player Server ID', required = true }
                    })
                    if input and input[1] then
                        TriggerServerEvent('frcp_dealership:server:fire', tonumber(input[1]))
                    end
                end
            },
            {
                title       = '⬆️ Promote Employee',
                description = 'Enter the server ID to promote',
                icon        = 'fas fa-arrow-up',
                onSelect    = function()
                    local input = lib.inputDialog('Promote Employee', {
                        { type = 'number', label = 'Player Server ID', required = true }
                    })
                    if input and input[1] then
                        TriggerServerEvent('frcp_dealership:server:promote', tonumber(input[1]))
                    end
                end
            },
            {
                title       = '⬇️ Demote Employee',
                description = 'Enter the server ID to demote',
                icon        = 'fas fa-arrow-down',
                onSelect    = function()
                    local input = lib.inputDialog('Demote Employee', {
                        { type = 'number', label = 'Player Server ID', required = true }
                    })
                    if input and input[1] then
                        TriggerServerEvent('frcp_dealership:server:demote', tonumber(input[1]))
                    end
                end
            },
            {
                title       = '📋 Staff Online',
                description = 'See who is clocked in',
                icon        = 'fas fa-users',
                onSelect    = function()
                    TriggerEvent('chat:addMessage', { args = { '/fdstaff' } })
                    ExecuteCommand('fdstaff')
                end
            },
        }
    })
    lib.showContext('flamedrive_boss_menu')
end

-- ============================================
--  Society balance received — open withdraw dialog
-- ============================================

RegisterNetEvent('frcp_dealership:client:receiveSocietyBalance', function(balance)
    lib.registerContext({
        id    = 'flamedrive_society_menu',
        title = '💰 Society Fund',
        options = {
            {
                title       = 'Current Balance',
                description = '$' .. tostring(balance),
                icon        = 'fas fa-dollar-sign',
                disabled    = true,
            },
            {
                title       = 'Withdraw Funds',
                description = 'Max single withdrawal: $' .. tostring(Config.MaxWithdrawal),
                icon        = 'fas fa-hand-holding-usd',
                onSelect    = function()
                    local input = lib.inputDialog('Withdraw from Society Fund', {
                        { type = 'number', label = 'Amount to withdraw', required = true, min = 1, max = Config.MaxWithdrawal }
                    })
                    if input and input[1] then
                        TriggerServerEvent('frcp_dealership:server:withdrawSociety', tonumber(input[1]))
                    end
                end
            },
        }
    })
    lib.showContext('flamedrive_society_menu')
end)

-- ============================================
--  Test Drive — Salesperson initiates via target
--  Player must be nearby a customer
-- ============================================

-- This zone is near the vehicle display area so a
-- salesperson can click a nearby customer
-- We add a player target so salesperson can click on
-- a customer ped and offer them a test drive

exports.ox_target:addGlobalPlayer({
    {
        label    = "Offer Test Drive",
        icon     = "fas fa-car",
        distance = 3.0,
        canInteract = function(entity)
            -- Only show if caller is a salesperson-grade employee and on duty
            local gradeData = getGradeData()
            return gradeData and gradeData.canTestDrive and isOnDuty
        end,
        onSelect = function(data)
            -- data.entity is the target player's ped
            local targetServerId = GetPlayerServerId(NetworkGetEntityOwner(data.entity))
            if not targetServerId or targetServerId == GetPlayerServerId(PlayerId()) then return end

            -- Let salesperson pick a vehicle
            local options = {}
            for _, v in ipairs(Config.Vehicles) do
                table.insert(options, { label = v.label .. ' (' .. v.tier .. ')', value = v.model })
            end

            local input = lib.inputDialog('Start Test Drive', {
                { type = 'number', label = 'Vehicle number (1-' .. #Config.Vehicles .. ')', required = true, min = 1, max = #Config.Vehicles }
            })

            if input and input[1] then
                local idx = tonumber(input[1])
                if Config.Vehicles[idx] then
                    TriggerServerEvent('frcp_dealership:server:startTestDrive', Config.Vehicles[idx].model, targetServerId)
                end
            end
        end
    }
})

print("^2[frcp_dealership] client/job.lua loaded.^0")
