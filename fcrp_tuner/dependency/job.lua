-- ══════════════════════════════════════════════════════════════
--  fcrp_tuner  |  dependency/job.lua
--  Add this job to your qbx_core jobs configuration.
--  File: resources/qbx_core/shared/jobs.lua  (or jobs folder)
-- ══════════════════════════════════════════════════════════════

['tuner'] = {
    label       = 'Illegal Tuner',
    defaultDuty = true,
    offDutyPay  = false,

    grades = {

        -- ─── Grade 0 ───────────────────────────────
        -- Basic installer. 20% commission on all mod sales.
        -- Can install: all chips, stance, NOS, exhaust, neon.
        -- Cannot craft items.
        [0] = {
            label    = 'Tuner I',
            payment  = 0,   -- paid via commission, not salary
        },

        -- ─── Grade 1 ───────────────────────────────
        -- Senior installer. 30% commission.
        -- Unlocks: crafting bench (s3_chip, drift_chip, stance_rod, nos_canister).
        [1] = {
            label    = 'Tuner II',
            payment  = 0,
        },

        -- ─── Grade 2 ───────────────────────────────
        -- Owner / head manager. 30% commission.
        -- Unlocks: craft bench + society stash (fcrp_tuner_society).
        [2] = {
            label    = 'Master Tuner',
            isboss   = true,
            payment  = 0,
        },

    },
},

-- ══════════════════════════════════════════════════════════════
--  NOTES FOR SERVER OWNERS
-- ══════════════════════════════════════════════════════════════
--
--  1.  Grade levels (0, 1, 2) must match Config.JobGrades in
--      fcrp_tuner/config.lua exactly.
--
--  2.  Commission is paid automatically in dirty_cash whenever
--      a tuner completes an install. No external paychecks needed.
--
--  3.  Society stash is an ox_inventory stash named:
--          'fcrp_tuner_society'
--      Only grade 2 (Master Tuner) can open it.
--
--  4.  To assign a player the tuner job in-game (qbx_core):
--          /setjob [id] tuner [grade]
--      Example:
--          /setjob 1 tuner 0    → Tuner I
--          /setjob 1 tuner 1    → Tuner II
--          /setjob 1 tuner 2    → Master Tuner
--
-- ══════════════════════════════════════════════════════════════
