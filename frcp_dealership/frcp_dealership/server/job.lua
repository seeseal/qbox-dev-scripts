-- ============================================
--  frcp_dealership | server/job.lua  v2.0
--
--  WHAT THIS FILE DOES (plain English):
--  ─────────────────────────────────────
--  • Handles all job management:
--    hire, fire, promote, demote players
--  • Only a boss-grade employee can run these
--  • All actions are logged to Discord
--  • /fdstaff — boss command to list employees
-- ============================================

local QBX = exports.qbx_core

-- ============================================
--  Helper: is this player a boss?
-- ============================================

local function isBoss(src)
    local player = QBX:GetPlayer(src)
    if not player then return false end
    local job = player.PlayerData.job
    if not job or job.name ~= Config.JobName then return false end
    local gradeData = Config.JobGrades[job.grade.level]
    return gradeData and gradeData.isBoss or false
end

local function notify(src, ntype, description)
    TriggerClientEvent('ox_lib:notify', src, {
        type        = ntype,
        title       = "FlameDrive HR",
        description = description,
        duration    = 6000
    })
end

-- ============================================
--  Hire Player
--  Puts a player into the job at grade 0 (Trainee)
-- ============================================

RegisterNetEvent('frcp_dealership:server:hire', function(targetId)
    local src    = source
    if not isBoss(src) then
        notify(src, 'error', 'You do not have permission to hire.')
        return
    end

    local target = QBX:GetPlayer(targetId)
    if not target then
        notify(src, 'error', 'Player not found or not online.')
        return
    end

    local targetCid  = target.PlayerData.citizenid
    local targetName = target.PlayerData.charinfo.firstname .. " " .. target.PlayerData.charinfo.lastname
    local bossCid    = QBX:GetPlayer(src).PlayerData.citizenid

    -- Check they don't already work here
    if target.PlayerData.job and target.PlayerData.job.name == Config.JobName then
        notify(src, 'error', targetName .. ' already works at FlameDrive.')
        return
    end

    -- Set job in Qbox
    target.Functions.SetJob(Config.JobName, 0)

    notify(src, 'success', targetName .. ' hired as Trainee.')
    notify(targetId, 'success', 'Welcome to FlameDrive Motors! Report to your manager to get started.')

    -- Discord log
    exports.frcp_webhook:Send(
        "dealership",
        "👔 Employee Hired",
        "**New Employee:** " .. targetName .. " (`" .. targetCid .. "`)" ..
        "\n**Role:** Trainee" ..
        "\n**Hired By:** `" .. bossCid .. "`",
        3066993
    )

    print("^2[frcp_dealership] " .. bossCid .. " hired " .. targetCid .. " as Trainee^0")
end)

-- ============================================
--  Fire Player
-- ============================================

RegisterNetEvent('frcp_dealership:server:fire', function(targetId)
    local src    = source
    if not isBoss(src) then
        notify(src, 'error', 'You do not have permission to fire.')
        return
    end

    local target = QBX:GetPlayer(targetId)
    if not target then
        notify(src, 'error', 'Player not found or not online.')
        return
    end

    if target.PlayerData.job and target.PlayerData.job.name ~= Config.JobName then
        notify(src, 'error', 'That player does not work at FlameDrive.')
        return
    end

    local targetCid  = target.PlayerData.citizenid
    local targetName = target.PlayerData.charinfo.firstname .. " " .. target.PlayerData.charinfo.lastname
    local bossCid    = QBX:GetPlayer(src).PlayerData.citizenid

    -- Qbox unemployed job is usually "unemployed" grade 0
    target.Functions.SetJob('unemployed', 0)

    notify(src, 'success', targetName .. ' has been let go.')
    notify(targetId, 'error', 'You have been let go from FlameDrive Motors.')

    exports.frcp_webhook:Send(
        "dealership",
        "🚪 Employee Fired",
        "**Employee:** " .. targetName .. " (`" .. targetCid .. "`)" ..
        "\n**Fired By:** `" .. bossCid .. "`",
        15158332  -- red colour
    )

    print("^2[frcp_dealership] " .. bossCid .. " fired " .. targetCid .. "^0")
end)

-- ============================================
--  Promote Player (increases grade by 1)
-- ============================================

RegisterNetEvent('frcp_dealership:server:promote', function(targetId)
    local src    = source
    if not isBoss(src) then
        notify(src, 'error', 'You do not have permission to promote.')
        return
    end

    local target = QBX:GetPlayer(targetId)
    if not target then
        notify(src, 'error', 'Player not found.')
        return
    end

    local job = target.PlayerData.job
    if not job or job.name ~= Config.JobName then
        notify(src, 'error', 'That player does not work at FlameDrive.')
        return
    end

    local currentGrade = job.grade.level
    local newGrade     = currentGrade + 1
    local newGradeData = Config.JobGrades[newGrade]

    if not newGradeData then
        notify(src, 'error', 'That employee is already at the highest rank.')
        return
    end

    local targetCid  = target.PlayerData.citizenid
    local targetName = target.PlayerData.charinfo.firstname .. " " .. target.PlayerData.charinfo.lastname
    local bossCid    = QBX:GetPlayer(src).PlayerData.citizenid
    local oldLabel   = Config.JobGrades[currentGrade].label

    target.Functions.SetJob(Config.JobName, newGrade)

    notify(src, 'success', targetName .. ' promoted to ' .. newGradeData.label .. '.')
    notify(targetId, 'success', 'Congratulations! You have been promoted to ' .. newGradeData.label .. '.')

    exports.frcp_webhook:Send(
        "dealership",
        "⬆️ Employee Promoted",
        "**Employee:** " .. targetName .. " (`" .. targetCid .. "`)" ..
        "\n**From:** " .. oldLabel ..
        "\n**To:** " .. newGradeData.label ..
        "\n**Promoted By:** `" .. bossCid .. "`",
        3066993
    )
end)

-- ============================================
--  Demote Player (decreases grade by 1)
-- ============================================

RegisterNetEvent('frcp_dealership:server:demote', function(targetId)
    local src    = source
    if not isBoss(src) then
        notify(src, 'error', 'You do not have permission to demote.')
        return
    end

    local target = QBX:GetPlayer(targetId)
    if not target then
        notify(src, 'error', 'Player not found.')
        return
    end

    local job = target.PlayerData.job
    if not job or job.name ~= Config.JobName then
        notify(src, 'error', 'That player does not work at FlameDrive.')
        return
    end

    local currentGrade = job.grade.level
    if currentGrade <= 0 then
        notify(src, 'error', 'Cannot demote below Trainee. Use Fire instead.')
        return
    end

    local newGrade    = currentGrade - 1
    local newLabel    = Config.JobGrades[newGrade].label
    local oldLabel    = Config.JobGrades[currentGrade].label
    local targetCid   = target.PlayerData.citizenid
    local targetName  = target.PlayerData.charinfo.firstname .. " " .. target.PlayerData.charinfo.lastname
    local bossCid     = QBX:GetPlayer(src).PlayerData.citizenid

    target.Functions.SetJob(Config.JobName, newGrade)

    notify(src, 'success', targetName .. ' demoted to ' .. newLabel .. '.')
    notify(targetId, 'error', 'You have been demoted to ' .. newLabel .. '.')

    exports.frcp_webhook:Send(
        "dealership",
        "⬇️ Employee Demoted",
        "**Employee:** " .. targetName .. " (`" .. targetCid .. "`)" ..
        "\n**From:** " .. oldLabel ..
        "\n**To:** " .. newLabel ..
        "\n**Demoted By:** `" .. bossCid .. "`",
        15158332
    )
end)

-- ============================================
--  /fdstaff — list all online employees
--  Available to all dealership employees
-- ============================================

lib.addCommand('fdstaff', {
    help = 'List all online FlameDrive employees',
    restricted = false,
}, function(src)
    local caller = QBX:GetPlayer(src)
    if not caller then return end

    if not caller.PlayerData.job or caller.PlayerData.job.name ~= Config.JobName then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'You are not a FlameDrive employee.' })
        return
    end

    local players = QBX:GetPlayers()
    local list    = {}

    for _, id in ipairs(players) do
        local p = QBX:GetPlayer(id)
        if p and p.PlayerData.job and p.PlayerData.job.name == Config.JobName then
            local gradeData = Config.JobGrades[p.PlayerData.job.grade.level]
            table.insert(list, {
                name  = p.PlayerData.charinfo.firstname .. " " .. p.PlayerData.charinfo.lastname,
                grade = gradeData and gradeData.label or "Unknown",
                id    = id
            })
        end
    end

    if #list == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type = 'inform', description = 'No FlameDrive employees are currently online.' })
        return
    end

    -- Build a nice alert dialog showing the staff list
    local staffText = ""
    for _, emp in ipairs(list) do
        staffText = staffText .. "• " .. emp.name .. " — " .. emp.grade .. " (ID: " .. emp.id .. ")\n"
    end

    TriggerClientEvent('frcp_dealership:client:showStaffList', src, staffText, #list)
end)


-- ============================================
--  /fdsales — all-time sales leaderboard
--  Available to all employees + boss.
--  Prints top 10 to their screen.
-- ============================================

lib.addCommand('fdsales', {
    help       = 'View FlameDrive all-time sales leaderboard',
    restricted = false,
}, function(src)
    local caller = exports.qbx_core:GetPlayer(src)
    if not caller then return end

    if not caller.PlayerData.job or caller.PlayerData.job.name ~= Config.JobName then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error', description = 'You are not a FlameDrive employee.'
        })
        return
    end

    MySQL.query([[
        SELECT citizenid, COUNT(*) as sales, SUM(price) as revenue
        FROM frcp_dealership_sales_log
        GROUP BY citizenid
        ORDER BY sales DESC
        LIMIT 10
    ]], {}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'inform', description = 'No sales have been recorded yet.'
            })
            return
        end

        -- Build text lines, resolve offline player names from DB async
        local lines   = {}
        local pending = #result
        local medals  = { "🥇", "🥈", "🥉" }

        for i, row in ipairs(result) do
            local idx = i
            MySQL.query(
                "SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1",
                { row.citizenid },
                function(r)
                    local name = row.citizenid
                    -- Try online first
                    local p = exports.qbx_core:GetPlayerByCitizenId(row.citizenid)
                    if p then
                        local ci = p.PlayerData.charinfo
                        name = ci.firstname .. " " .. ci.lastname
                    elseif r and r[1] and r[1].charinfo then
                        local ok, ci = pcall(json.decode, r[1].charinfo)
                        if ok and ci then
                            name = (ci.firstname or '') .. ' ' .. (ci.lastname or '')
                        end
                    end

                    local medal = medals[idx] or (idx .. ".")
                    local rev   = row.revenue and ("$" .. math.floor(row.revenue)) or "$0"
                    lines[idx]  = medal .. " **" .. name .. "** — " ..
                                  row.sales .. " sales · " .. rev

                    pending = pending - 1
                    if pending == 0 then
                        -- Sort by index and join
                        local text = ""
                        for j = 1, #result do
                            if lines[j] then text = text .. lines[j] .. "\n" end
                        end
                        TriggerClientEvent('frcp_dealership:client:showStaffList', src,
                            text, #result)
                    end
                end
            )
        end
    end)
end)

print("^2[frcp_dealership] server/job.lua loaded.^0")
