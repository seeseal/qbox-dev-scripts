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
```

---

So your full folder structure for `fd_dealership` should now look like this:
```
fd_dealership/
  fxmanifest.lua
  config.lua
  server.lua
  client.lua        ← empty for now
  sql/
    dealership.sql  ← just created
  html/
    index.html      ← empty for now
    style.css       ← empty for now
    script.js       ← empty for now
```

Save and push.

Commit message:
```
add fd_dealership sql file