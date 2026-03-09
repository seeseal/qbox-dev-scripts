-- ============================================
--  tebex_tickets | tickets.sql
--  Run this in phpMyAdmin before starting
--  the resource for the first time
-- ============================================

CREATE TABLE IF NOT EXISTS `player_tickets` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(50)  NOT NULL,
    `ticket_type` VARCHAR(10)  NOT NULL,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_ticket_type` (`ticket_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
--  Optional: ticket history table
--  Keeps a permanent log of every ticket
--  that was ever consumed
-- ============================================

CREATE TABLE IF NOT EXISTS `player_ticket_history` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(50)  NOT NULL,
    `ticket_type` VARCHAR(10)  NOT NULL,
    `used_at`     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;