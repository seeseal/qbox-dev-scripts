# Changelog — frcp_dealership

All notable changes to this script are documented here.  
Format: `[version] — date — description`

---

## [2.0.0] — Job System Update

### Added
- **Job system** — 4 grades: Trainee (0), Salesperson (1), Sales Manager (2), General Manager (3)
- **Clock-in / Clock-out** zone via ox_target at `Config.OnDutyCoords`
- **Shared employee stash** via ox_inventory, accessible on-duty only
- **Changing room** zone — applies GTA V ped component outfit or shows notice if none configured
- **Boss desk** zone — ox_target opens GM context menu (hire, fire, promote, demote, fund, staff list)
- **Society fund** — every sale auto-splits into configurable society % + gov tax %
- **Society fund DB** — `frcp_dealership_society` (balance) + `frcp_dealership_transactions` (full log)
- **Boss withdrawal** — GM can withdraw up to `Config.MaxWithdrawal` per transaction via NUI or boss desk
- **Test drive system** — salesperson targets nearby player, picks vehicle, timed drive starts
- **Test drive HUD** — countdown timer drawn on screen for the customer
- **Test drive boundary** — if customer exceeds `Config.TestDriveRadius` metres, drive ends automatically
- **Test drive cleanup** — server-side tracking; drive cancelled cleanly if player disconnects
- `/fdstaff` command — lists all online employees and grades (available to all employees)
- `/endtestdrive [id]` command — staff can force-end a customer's test drive
- **NUI tab bar** — catalog / employee panel / GM office (tabs shown based on job grade)
- **Employee badge** in NUI header showing current grade when on duty
- **GM Office NUI tab** — society balance, withdraw button, hire/fire/promote/demote buttons with server ID input
- **Employee Panel NUI tab** — role info, duty status, test drive info, employee rules
- Discord webhook logs for: hire, fire, promote, demote, withdrawal
- All purchase Discord logs now include society fund split breakdown
- `sql/v2_upgrade.sql` — migration file for new tables
- `server/job.lua`, `server/society.lua`, `server/testdrive.lua` — new server files
- `client/job.lua`, `client/testdrive.lua` — new client files
- `Config.JobName`, `Config.JobGrades`, `Config.SocietyPercent`, `Config.TaxPercent` — new config keys
- `Config.GovBankAccount`, `Config.MaxWithdrawal` — new config keys
- `Config.OnDutyCoords`, `Config.StashCoords`, `Config.ChangingRoomCoords` — new location config keys
- `Config.TestDriveDuration`, `Config.TestDriveRadius`, `Config.TestDriveStart`, `Config.TestDriveReturn` — new test drive config
- `Config.EmployeeOutfit`, `Config.StashId`, `Config.StashSlots`, `Config.StashWeight` — new stash/outfit config
- `BOSS_DESK_COORDS` in `client/job.lua` — configurable boss desk location

### Changed
- `fxmanifest.lua` — version bumped to `2.0.0`, new server/client file declarations added, `ox_inventory` added to dependencies
- `server/main.lua` — `finalizePurchase` now fires `frcp_dealership:server:depositSale` after successful insert
- `server/main.lua` — `getCatalog` handler now passes `isEmployee`, `isBoss`, `jobGrade` to NUI
- `client/main.lua` — added NUI callbacks for `getSocietyBalance`, `withdrawSociety`, `startTestDrive`, `hirePlayer`, `firePlayer`, `promotePlayer`, `demotePlayer`
- `html/index.html` — added tab bar, employee panel tab, GM office tab, staff modal, withdraw modal
- `html/style.css` — added tab bar styles, job panel styles, boss panel styles, society balance box, staff action cards
- `html/script.js` — added tab switching, employee/boss state, society balance display, staff modal logic, withdraw modal logic

### Unchanged from v1
- All vehicle catalog data in `config.lua`
- Tier definitions (Standard / Elite / Apex)
- Purchase flow, cooldown logic, plate generation
- Supply tracking and live UI updates
- `/clearcooldown` admin command
- Original NUI catalog tab (tier filter, category filter, sort, vehicle cards, confirm modal)
- `sql/dealership.sql` (original v1 table — untouched)

---

## [1.2.1] — Base Dealership

### Summary
Initial working version of FlameDrive Motors. Three-tier dealership with NUI, supply limits, Elite cooldowns, ticket integration, Discord webhook logging, and full refund safety logic.

### Features
- Three vehicle tiers: Standard, Elite, Apex
- Custom NUI: purple/blue Flame City theme, tier filter, category filter, sort
- Server-wide supply limits per vehicle model
- Live supply broadcast to all open UIs on purchase
- Elite 30-minute repurchase cooldown, DB-persisted across restarts
- Unique plate generation with up to 5 retry attempts on collision
- Full refund: ticket refunded if money fails, both refunded if DB insert fails
- Ticket integration via `frcp_tickets` exports
- Discord webhook log on every purchase via `frcp_webhook`
- `/clearcooldown [id]` admin command
- `frcp_dealership_sold` and `frcp_dealership_cooldowns` DB tables

---

*Flame City Dev — internal changelog. Not for public release.*
