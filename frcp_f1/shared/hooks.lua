--[[
    fcrp_f1 — shared/hooks.lua
    Open function hooks. Override any of these in your own resource
    without touching core files.

    SERVER hooks live in OpenServerFunctions.
    CLIENT hooks live in OpenClientFunctions.
]]

-- ── SERVER ───────────────────────────────────────────────────
OpenServerFunctions = {

    -- Return false to block a driver from being assigned a grid slot.
    -- source = server id, slot = grid position (1 = pole)
    CanAssignSlot = function(source, slot)
        return true
    end,

    -- Called after a driver is placed on the grid (car spawned).
    OnDriverGridded = function(source, slot, citizenId)
    end,

    -- Called when a driver finishes the race.
    -- position = P1/P2 etc, raceTime = "1:32.45", xpEarned, ratingDelta
    OnRaceFinish = function(source, position, raceTime, xpEarned, ratingDelta)
    end,

    -- Called when a driver is disqualified.
    OnDriverDQ = function(source, reason)
    end,

    -- Called when the race session fully ends (everyone finished or DQ'd).
    OnRaceSessionEnd = function(finishOrder, dqList)
    end,

    -- Called when a pit stop is confirmed server-side.
    -- compound = 'soft' | 'medium' | 'hard'
    OnPitStop = function(source, compound)
    end,

    -- Called when an achievement is unlocked.
    OnAchievementUnlocked = function(source, achievementKey, achievementData)
    end,
}

-- ── CLIENT ───────────────────────────────────────────────────
OpenClientFunctions = {

    -- Return false to block the local player from receiving a startRace event.
    CanStartRace = function()
        return true
    end,

    -- Called each time the local player passes a checkpoint.
    OnCheckpointPassed = function(cpIndex, totalCPs)
    end,

    -- Called when the local player completes a lap.
    OnLapComplete = function(lapNumber, lapTimeMs)
    end,

    -- Called when the local player finishes the race.
    OnRaceFinish = function(position, raceTimeMs)
    end,

    -- Called when the local player enters the pit lane zone.
    OnPitEntry = function()
    end,

    -- Called when the local player exits the pit lane zone.
    OnPitExit = function(compound)
    end,
}
