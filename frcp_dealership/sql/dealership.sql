-- ============================================
--  fd_dealership | dealership.sql
--  Run this in phpMyAdmin before starting
--  the resource for the first time
-- ============================================

CREATE TABLE IF NOT EXISTS `fd_dealership_sold` (
    `model` VARCHAR(50) NOT NULL,
    `sold`  INT(11)     NOT NULL DEFAULT 0,
    PRIMARY KEY (`model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
