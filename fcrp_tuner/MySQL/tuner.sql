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
    PRIMARY KEY (`plate`),
    INDEX `idx_engine_chip` (`engine_chip`),
    INDEX `idx_drift_chip`  (`drift_chip`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='fcrp_tuner — per-vehicle mod state, persisted across reconnects';


-- ─────────────────────────────────────────────
--  OX_INVENTORY ITEMS
--  Add these to your ox_inventory items.lua / items folder
--  if they are not already defined.
--
--  The INSERT IGNORE below adds them to the standard
--  ox_inventory `items` table used by some server setups.
--  If your setup uses flat-file items, add them manually.
-- ─────────────────────────────────────────────

INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `stack`, `close`, `description`) VALUES
    ('s3_chip',           'S3 Engine Chip',   500,  false, true,  'An illegal performance chip that boosts top speed by 15%.'),
    ('drift_chip',        'Drift Chip',        500,  false, true,  'Reduces traction and makes wheels spin more freely.'),
    ('stance_rod',        'Stance Rod',        800,  false, true,  'Adjustable suspension rod used to tune camber and ride height.'),
    ('nos_canister',      'NOS Canister',      1200, false, true,  'Pressurised nitrous oxide. Use while in a vehicle to refill the NOS kit.'),
    ('electronic_parts',  'Electronic Parts',  300,  true,  false, 'Various electronic components used in chip crafting.'),
    ('metal_scrap',       'Metal Scrap',       600,  true,  false, 'Salvaged metal pieces used in fabrication.'),
    ('rubber',            'Rubber',            400,  true,  false, 'High-grade rubber used in drift chip assembly.'),
    ('compressed_gas',    'Compressed Gas',    900,  true,  false, 'Pressurised gas cylinder used to fill NOS canisters.');

-- ─────────────────────────────────────────────
--  MIGRATION  (run once on existing installs)
--  Safe to run multiple times — ADD COLUMN IF NOT EXISTS is idempotent.
-- ─────────────────────────────────────────────

ALTER TABLE `fcrp_tuner_mods`
    ADD COLUMN IF NOT EXISTS `nos_pressure`   FLOAT       NOT NULL DEFAULT 1.0
        COMMENT '0.0 = empty, 1.0 = full. Drains per activation, refilled by nos_canister item.',
    ADD COLUMN IF NOT EXISTS `fake_plate`     VARCHAR(15) DEFAULT NULL
        COMMENT 'Custom plate text displayed on the vehicle. NULL = real plate shown.',
    ADD COLUMN IF NOT EXISTS `vehicle_value`  INT         NOT NULL DEFAULT 0
        COMMENT 'Vehicle value in dollars, reported by client on ramp entry for chip price bonus.';

-- Seed pressure for any existing NOS installs (treat them as full)
UPDATE `fcrp_tuner_mods` SET `nos_pressure` = 1.0 WHERE `nos` = 1 AND `nos_pressure` = 0;

-- Insert damaged_parts into ox_inventory items table (if using DB-backed items)
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `stack`, `close`, `description`) VALUES
    ('damaged_parts', 'Damaged Parts', 500, true, false, 'Salvaged components from supply runs. Used to craft tuner chips and kits.');
