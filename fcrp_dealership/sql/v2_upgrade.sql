-- ============================================
--  frcp_dealership | sql/v2_upgrade.sql
--
--  Run this in phpMyAdmin (or any SQL client)
--  ONCE when upgrading from v1 to v2.
--  The original fd_dealership_sold table is
--  untouched — all your existing data is safe.
-- ============================================

-- Society fund balance (single row, id always = 1)
CREATE TABLE IF NOT EXISTS `frcp_dealership_society` (
    `id`      INT(11)  NOT NULL DEFAULT 1,
    `balance` BIGINT   NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Transaction log (deposits + withdrawals)
CREATE TABLE IF NOT EXISTS `frcp_dealership_transactions` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `type`       VARCHAR(20)  NOT NULL COMMENT 'deposit or withdrawal',
    `amount`     BIGINT       NOT NULL DEFAULT 0,
    `citizenid`  VARCHAR(50)  NOT NULL,
    `note`       VARCHAR(255) NOT NULL DEFAULT '',
    `created_at` INT(11)      NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_type`      (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Cooldowns table (already auto-created by server.lua in v1,
-- included here in case you need to run it manually)
CREATE TABLE IF NOT EXISTS `frcp_dealership_cooldowns` (
    `citizenid`    VARCHAR(50) NOT NULL,
    `model`        VARCHAR(50) NOT NULL,
    `purchased_at` INT         NOT NULL,
    PRIMARY KEY (`citizenid`, `model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
--  Qbox Job Registration
--  Run this to register the job in your DB.
--  Only needed if you are NOT using the jobs
--  config file approach in qbx_core.
--  If your server uses jobs.lua in qbx_core
--  add the job there instead (see README).
-- ============================================

-- INSERT IGNORE INTO `jobs` (`name`, `label`) VALUES ('flamedrive', 'FlameDrive Motors');
-- INSERT IGNORE INTO `job_grades` (`jobName`, `grade`, `name`, `label`, `salary`, `isboss`) VALUES
--     ('flamedrive', 0, 'trainee',   'Trainee',         500,  0),
--     ('flamedrive', 1, 'sales',     'Salesperson',     750,  0),
--     ('flamedrive', 2, 'manager',   'Sales Manager',   1000, 0),
--     ('flamedrive', 3, 'gm',        'General Manager', 1500, 1);
