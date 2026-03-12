-- ══════════════════════════════════════════════════════════════
--  fcrp_tuner  |  tuner.sql
--  Run this once in your database to set up all required tables.
-- ══════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
--  VEHICLE MODS TABLE
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `fcrp_tuner_mods` (
    `plate`              VARCHAR(15)  NOT NULL,
    `engine_chip`        TINYINT(1)   NOT NULL DEFAULT 0,
    `drift_chip`         TINYINT(1)   NOT NULL DEFAULT 0,
    `nos`                TINYINT(1)   NOT NULL DEFAULT 0,
    `nos_pressure`       FLOAT        NOT NULL DEFAULT 1.0 COMMENT '0.0 = empty, 1.0 = full',
    `nos_cooldown_until` BIGINT       NOT NULL DEFAULT 0,
    `neon_mode`          VARCHAR(16)  DEFAULT NULL COMMENT 'static | rainbow | rgb | strobe',
    `neon_r`             SMALLINT     DEFAULT NULL,
    `neon_g`             SMALLINT     DEFAULT NULL,
    `neon_b`             SMALLINT     DEFAULT NULL,
    `stance_camber`      FLOAT        DEFAULT NULL,
    `stance_height`      FLOAT        DEFAULT NULL,
    `stance_wheeldist`   FLOAT        DEFAULT NULL,
    `has_exhaust`        TINYINT(1)   NOT NULL DEFAULT 0,
    `fake_plate`         VARCHAR(15)  DEFAULT NULL COMMENT 'Custom plate text. NULL = real plate shown.',
    `vehicle_value`      INT          NOT NULL DEFAULT 0 COMMENT 'Vehicle value in dollars for chip price bonus',
    -- Original handling values captured before engine chip is applied
    `orig_speed`         FLOAT        DEFAULT NULL COMMENT 'fInitialDriveMaxFlatVel before engine chip',
    `orig_force`         FLOAT        DEFAULT NULL COMMENT 'fInitialDriveForce before engine chip',
    `orig_inertia`       FLOAT        DEFAULT NULL COMMENT 'fDriveInertia before engine chip',
    -- Original handling values captured before drift chip is applied
    `orig_traction_max`  FLOAT        DEFAULT NULL COMMENT 'fTractionCurveMax before drift chip',
    `orig_traction_min`  FLOAT        DEFAULT NULL COMMENT 'fTractionCurveMin before drift chip',
    `orig_traction_loss` FLOAT        DEFAULT NULL COMMENT 'fTractionLossMult before drift chip',
    `orig_drag`          FLOAT        DEFAULT NULL COMMENT 'fInitialDragCoeff before drift chip',
    `orig_drive_force`   FLOAT        DEFAULT NULL COMMENT 'fInitialDriveForce before drift chip',
    `orig_steering_lock` FLOAT        DEFAULT NULL COMMENT 'fSteeringLock before drift chip',
    `orig_anti_roll`     FLOAT        DEFAULT NULL COMMENT 'fAntiRollBarForce before drift chip',
    PRIMARY KEY (`plate`),
    INDEX `idx_engine_chip` (`engine_chip`),
    INDEX `idx_drift_chip`  (`drift_chip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='fcrp_tuner — per-vehicle mod state, persisted across reconnects';


-- ─────────────────────────────────────────────
--  OX_INVENTORY ITEMS
--  Your server uses flat-file items (items.lua / items folder).
--  Add the following entries manually to your ox_inventory items file:
--
--  { name = 's3_chip',          label = 'S3 Engine Chip',   weight = 500,  stack = false, close = true  }
--  { name = 'drift_chip',       label = 'Drift Chip',        weight = 500,  stack = false, close = true  }
--  { name = 'stance_rod',       label = 'Stance Rod',        weight = 800,  stack = false, close = true  }
--  { name = 'nos_canister',     label = 'NOS Canister',      weight = 1200, stack = false, close = true  }
--  { name = 'damaged_parts',    label = 'Damaged Parts',     weight = 500,  stack = true,  close = false }
--  { name = 'electronic_parts', label = 'Electronic Parts',  weight = 300,  stack = true,  close = false }
--  { name = 'metal_scrap',      label = 'Metal Scrap',       weight = 600,  stack = true,  close = false }
--  { name = 'rubber',           label = 'Rubber',            weight = 400,  stack = true,  close = false }
--  { name = 'compressed_gas',   label = 'Compressed Gas',    weight = 900,  stack = true,  close = false }
-- ─────────────────────────────────────────────

-- ─────────────────────────────────────────────
--  MIGRATION  (run once on existing installs)
--  Safe to run multiple times — ADD COLUMN IF NOT EXISTS is idempotent.
-- ─────────────────────────────────────────────

ALTER TABLE `fcrp_tuner_mods`
    ADD COLUMN IF NOT EXISTS `nos_pressure`       FLOAT       NOT NULL DEFAULT 1.0,
    ADD COLUMN IF NOT EXISTS `fake_plate`         VARCHAR(15) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `vehicle_value`      INT         NOT NULL DEFAULT 0,
    -- Engine chip originals (stock handling values captured at install time)
    ADD COLUMN IF NOT EXISTS `orig_speed`         FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_force`         FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_inertia`       FLOAT       DEFAULT NULL,
    -- Drift chip originals
    ADD COLUMN IF NOT EXISTS `orig_traction_max`  FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_traction_min`  FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_traction_loss` FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_drag`          FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_drive_force`   FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_steering_lock` FLOAT       DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `orig_anti_roll`     FLOAT       DEFAULT NULL;

-- Seed pressure for any existing NOS installs (treat them as full)
UPDATE `fcrp_tuner_mods` SET `nos_pressure` = 1.0 WHERE `nos` = 1 AND `nos_pressure` = 0;
