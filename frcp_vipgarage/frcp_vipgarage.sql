-- ============================================================
--  frcp_vipgarage  |  sql/frcp_vipgarage.sql
--  Run this on your qbox_dev database ONCE before first start.
--  In MySQL Workbench: File > Open SQL Script, then Execute.
-- ============================================================

CREATE TABLE IF NOT EXISTS `frcp_vip_slots` (
    `slot_id`           INT          NOT NULL AUTO_INCREMENT,
    `owner_citizenid`   VARCHAR(50)  NOT NULL,
    `coords`            LONGTEXT     NOT NULL,   -- JSON { x, y, z, w }
    `vehicle_plate`     VARCHAR(10)  NULL DEFAULT NULL,
    `vehicle_model`     VARCHAR(50)  NULL DEFAULT NULL,
    `vehicle_props`     LONGTEXT     NULL DEFAULT NULL,  -- full ox_lib vehicle props JSON
    `created_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`slot_id`),
    INDEX `idx_owner` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `frcp_vip_access` (
    `id`                INT          NOT NULL AUTO_INCREMENT,
    `owner_citizenid`   VARCHAR(50)  NOT NULL,
    `allowed_citizenid` VARCHAR(50)  NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_grant` (`owner_citizenid`, `allowed_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
