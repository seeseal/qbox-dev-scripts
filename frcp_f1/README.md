# fcrp_f1 — Flame City Grand Prix
**v3.0** · FiveM F1 racing resource · Qbox + ox_lib + ox_target + oxmysql

---

## Dependencies

| Resource | Required |
|---|---|
| `qbx_core` | ✅ |
| `ox_lib` | ✅ |
| `ox_target` | ✅ |
| `oxmysql` | ✅ |
| `ox_inventory` | ✅ |

---

## File Structure

```
fcrp_f1/
├── fxmanifest.lua
├── shared/
│   ├── config.lua       — all settings
│   └── hooks.lua        — open function overrides
├── server/
│   └── main.lua
├── client/
│   └── main.lua
└── html/
    └── index.html       — results NUI overlay
```

---

## Installation

1. Drop the `fcrp_f1` folder into your `resources/` directory
2. Add `ensure fcrp_f1` to your `server.cfg`
3. Start your server — all three database tables are created automatically on first boot
4. Configure everything in `shared/config.lua`

---

## Running a Race

All race control is accessed via `/f1menu` (organiser only) or by interacting with the **Race Manager NPC** at `Config.RaceManagerNPC.coords`. Non-admin players interact with the NPC to view their stats, career history, and the leaderboard.

### Step 1 — Build the Grid
Open the organiser panel and assign drivers to **P1–P8** slots using their server ID. Press **Prepare Grid** to spawn all cars on their grid spots.

> If `Config.Items.enabled = true`, each driver must have a `racechip` item to be placed on the grid — it is consumed on assignment.

### Step 2 — Formation Lap
Press **Deploy Safety Car**. The SC leads the full field around the circuit at `Config.FormationLap.maxSpeed` km/h. Once it returns to the start, all cars are teleported back to their grid spots and the race countdown begins automatically.

### Step 3 — Lights Out
The race starts automatically after the formation lap completes. The **START RACE** button can override or skip the formation lap at any time.

---

## Commands

| Command | Permission | Description |
|---|---|---|
| `/f1menu` | Organiser | Open the Race Control panel |
| `/f1stats` | All | View your own MMR, XP, wins, podiums and fastest laps in chat |
| `/f1top` | All | Show the top 10 drivers by MMR in chat |
| `/f1reward` | All | Claim your weekly reward (7-day cooldown) |
| `/createf1crew <name>` | All | Create a racing crew for a configurable money cost |

The Race Manager NPC also exposes these interactions via ox_target without needing chat commands:
- **Race Manager** — opens the organiser panel (admin) or an info screen (all)
- **My Stats** — opens a career stats menu with last 5 race history entries
- **Leaderboard** — shows the top 20 drivers by MMR
- **Claim Weekly Reward** — same as `/f1reward`

---

## Features

### 🏎️ Configurable F1 Car
A single model is used for every race, set via `Config.F1CarModel`. All base handling values live in `Config.F1BaseHandling` — no `handling.meta` edits needed. Max mods and a unique livery are applied automatically on spawn.

### 🛞 Tire Compound System
Three compounds — Soft, Medium, Hard — each with their own lap life, drive force delta, top speed bonus, traction values, and degradation penalties when worn. Compounds are selected in the pit lane via an ox_target box zone. A HUD indicator shows the current compound and flags `[WORN]` when it degrades.

### 🛑 Pit Stop
Drivers pull into the configurable pit lane zone and select a compound from a context menu. The car is frozen for `Config.PitStop.stopDuration` seconds while the stop is processed, then released. A speed limiter is enforced in the zone. If `Config.PitStop.mandatory = true`, drivers who reach the finish line without pitting are disqualified.

### ⚡ DRS Zones
Defined as entry → exit vector segments with a lateral corridor radius. Inside a zone, drive force and top speed are boosted, a **DRS OPEN** banner appears on screen, and the DRS usage counter increments — tracked per race and persisted in career stats.

### 🔥 Engine Damage
Three power tiers based on `GetVehicleEngineHealth`. Notifications fire on each tier change and power reduction is applied in real time, combined with tire compound and DRS state.

### ⏱️ Sector Timing
The circuit is split into three sectors defined by checkpoint index. Each sector is timed per lap and compared against the driver's personal best. The result is colour-coded on screen — purple for a new personal best, green for close to best, yellow for slower. Sector times are sent to the server and stored in race history.

### 💜 Fastest Lap
The server tracks the fastest individual lap across all drivers. When a new fastest lap is set, all players are notified, the setter receives a configurable XP bonus, and a purple flash appears on the HUD. The fastest lap holder and time are displayed on the results screen.

### ⚠️ Lap Invalidation
If a driver strays more than `Config.LapInvalidDist` metres from any checkpoint corridor for `Config.LapInvalidTime` consecutive seconds, their current lap is flagged as **INVALID**. An on-screen banner shows the status. Invalid laps are excluded from fastest lap calculations but do not result in a DQ.

### 🏆 MMR & XP (True ELO)
MMR starts at 1500. Win rewards scale with field size — beating more drivers earns more. Loss is multiplied by finishing position (`MmrLostBase × position`). XP is awarded per finishing position. Both are persisted per race and contribute to the career totals. DNF and disconnect are scored as last place + 1.

### 🏅 Achievements
20 milestones tracked per player, stored as a JSON blob on the player row. Unlock notifications fire in-game when a milestone is reached.

| Key | Description |
|---|---|
| `win_1` | Win your first race |
| `win_5` | Win 5 races |
| `win_25` | Win 25 races |
| `win_50` | Win 50 races |
| `podium_10` | Reach the podium 10 times |
| `podium_50` | Reach the podium 50 times |
| `races_10` | Complete 10 races |
| `races_50` | Complete 50 races |
| `races_100` | Complete 100 races |
| `fastest_lap_1` | Set the fastest lap in a race |
| `fastest_lap_10` | Set the fastest lap 10 times |
| `pit_5` | Complete 5 pit stops |
| `pit_25` | Complete 25 pit stops |
| `clean_race_1` | Finish a race with no engine damage |
| `clean_race_10` | 10 clean races |
| `drs_50` | Use DRS 50 times |
| `mmr_2000` | Reach 2000 MMR |
| `mmr_3000` | Reach 3000 MMR |
| `hat_trick` | Win 3 consecutive races |
| `iron_man` | Finish without pitting (no-stop strategy) |

### 📊 Race History
Every race result writes a row to `f1_race_history`. The NPC stats menu shows the last 5 races per driver. Stored per row: race ID, position, total laps, race time, best lap, sector times (JSON), tyre used, pit count, DRS count, engine health flag, XP earned, MMR delta, DQ status and reason.

### 🗓️ Official Race Schedule
`Config.RaceSchedule` defines per-day timed race triggers with individual lap counts, entry fees, and prize amounts. A 10-minute advance warning notification fires automatically.

### 🎁 Weekly Reward
Claim with `/f1reward` or via the NPC. Configurable as money or an inventory item. 7-day cooldown stored in the database.

### 👥 Crew System
Create a crew with `/createf1crew <name>` for a configurable money cost. Crew data is stored in `f1_crews` (MySQL).

### 🎥 Race Director Camera
Organiser only. Enter any driver's server ID from the panel to lock a cinematic overhead follow-cam to their car. Press Backspace to exit.

### 🔌 Open Function Hooks
`shared/hooks.lua` exposes `OpenServerFunctions` and `OpenClientFunctions` — override any hook from your own resource without editing core files.

---

## Configuration Reference (`shared/config.lua`)

### General

| Key | Default | Description |
|---|---|---|
| `Config.Debug` | `false` | Print verbose logs to console |
| `Config.MoneyType` | `'bank'` | `'cash'` or `'bank'` |
| `Config.F1CarModel` | `` `openwheel1` `` | Model hash for the race car |
| `Config.LiveryCount` | `11` | Total liveries on the model |
| `Config.MaxLaps` | `5` | Race lap count |
| `Config.MinPlayers` | `2` | Minimum drivers to allow a race start |
| `Config.ResultsScreenDelay` | `20` | Seconds before post-race teleport |
| `Config.LapInvalidDist` | `40.0` | Metres off-course to flag lap invalid |
| `Config.LapInvalidTime` | `6` | Consecutive seconds off-course to trigger |
| `Config.PrizeMoney` | `100000` | Cash paid to P1 via ox_inventory |
| `Config.PrizeItem` | `'money'` | ox_inventory item name for the prize |
| `Config.OrganizerPermission` | `'admin'` | QBX group or ace permission |

### MMR & XP

| Key | Default | Description |
|---|---|---|
| `Config.DefaultMMR` | `1500` | Starting MMR for new players |
| `Config.FastestLapXP` | `15` | Bonus XP for setting the fastest lap |
| `Config.XP` | `{100,80,60...}` | XP table indexed by finishing position |
| `Config.MmrGain` | `{50,35,22...}` | MMR delta table indexed by position |
| `Config.MmrLostBase` | `-8` | Multiplied by position for DNF/DQ |
| `Config.MaxRaceHistory` | `10` | Max race history rows per player |
| `Config.MaxMmrHistory` | `20` | Max MMR history entries in JSON |

### Tire Compounds & Pit Stop

| Key | Description |
|---|---|
| `Config.TireCompounds.soft/medium/hard` | Lap life, force bonus, traction, and degradation per compound |
| `Config.PitStop.enabled` | Toggle pit stop system |
| `Config.PitStop.mandatory` | DQ drivers who finish without pitting |
| `Config.PitStop.zone` | `coords`, `size`, and `heading` of the pit lane ox_target box |
| `Config.PitStop.speedLimit` | km/h cap enforced in the pit lane |
| `Config.PitStop.stopDuration` | Seconds the car is frozen during a stop |

### DRS

| Key | Default | Description |
|---|---|---|
| `Config.DRSZones` | 2 zones | Array of `{ name, entry, exit, radius }` |
| `Config.DRS.driveForceBoost` | `0.45` | Drive force added inside a DRS zone |
| `Config.DRS.topSpeedBoost` | `15.0` | Top speed added inside a DRS zone |

### Sectors

| Key | Default | Description |
|---|---|---|
| `Config.Sectors` | 3 sectors | Array of `{ endCP, label }` — which checkpoint index ends each sector |

### Grid & Circuit

| Key | Description |
|---|---|
| `Config.GridSpots` | Array of `vector4` spawn positions (up to 8) — P1 = index 1 |
| `Config.Checkpoints` | Array of `vector3` circuit checkpoints. CP 1 = Start/Finish line |
| `Config.PostRaceLocation` | `vector4` where all drivers are teleported after the race |
| `Config.FormationLap.enabled` | Toggle the formation lap / safety car |
| `Config.FormationLap.maxSpeed` | km/h cap during the SC lap |

### NPC

| Key | Description |
|---|---|
| `Config.RaceManagerNPC.enabled` | Toggle the Race Manager NPC |
| `Config.RaceManagerNPC.coords` | `vector4` spawn location |
| `Config.RaceManagerNPC.model` | Ped model name string |

### Schedule & Rewards

| Key | Description |
|---|---|
| `Config.RaceSchedule` | Day-of-week table with `{ time, laps, entryFee, prize }` entries |
| `Config.WeeklyReward.type` | `'money'` or `'item'` |
| `Config.WeeklyReward.money` | Amount paid if type is money |
| `Config.WeeklyReward.item` | `{ name, amount }` if type is item |

---

## Database Tables

All three tables are created automatically on resource start.

### `f1_players` — career stats per driver

| Column | Type | Description |
|---|---|---|
| `citizenid` | VARCHAR(50) PK | Qbox citizen ID |
| `mmr` | INT | Current MMR (starts at 1500) |
| `xp` | INT | Total XP earned |
| `wins` | INT | Total race wins |
| `races` | INT | Total races completed |
| `podiums` | INT | Total top-3 finishes |
| `fastest_laps` | INT | Total fastest laps set |
| `best_lap_ms` | INT | Personal best lap in milliseconds |
| `stats` | JSON | Pit stops, DRS uses, clean races, consecutive wins |
| `achievements` | JSON | Unlocked achievement keys with timestamps |
| `mmr_history` | JSON | Last 20 MMR changes with date and delta |
| `weekly_claimed` | BIGINT | Unix timestamp of last weekly reward claim |

### `f1_race_history` — per-race result log

| Column | Type | Description |
|---|---|---|
| `id` | INT AUTO_INCREMENT PK | Row ID |
| `race_id` | VARCHAR(20) | Session ID e.g. `F1-20260316-0742` |
| `citizenid` | VARCHAR(50) | Driver citizen ID |
| `position` | INT | Finishing position |
| `total_laps` | INT | Laps in the race |
| `race_time` | VARCHAR(20) | Total race time string |
| `best_lap` | VARCHAR(20) | Fastest lap time string |
| `sector_times` | JSON | Array of sector time objects |
| `tyre_used` | VARCHAR(20) | Compound at finish |
| `pit_count` | INT | Number of pit stops made |
| `drs_count` | INT | Number of DRS activations |
| `engine_ok` | TINYINT(1) | 1 = no damage, 0 = damage taken |
| `xp_earned` | INT | XP awarded this race |
| `mmr_delta` | INT | MMR change this race |
| `dq` | TINYINT(1) | 1 = disqualified |
| `dq_reason` | VARCHAR(100) | DQ reason string |
| `race_date` | TIMESTAMP | Auto-set to insert time |

### `f1_crews` — crew registry

| Column | Type | Description |
|---|---|---|
| `id` | INT AUTO_INCREMENT PK | Crew ID |
| `name` | VARCHAR(100) | Crew display name |
| `leader` | VARCHAR(50) | citizenid of the crew leader |
| `members` | TEXT | JSON array of member citizenids |

---

## Open Function Hooks (`shared/hooks.lua`)

Override any hook from your own resource — no core file edits needed.

### Server hooks (`OpenServerFunctions`)

```lua
CanAssignSlot = function(source, slot)          -- return false to block grid assignment
OnDriverGridded = function(source, slot, cid)   -- fired after car spawns on grid
OnRaceFinish = function(source, pos, time, xp, mmr) -- fired per driver finish
OnDriverDQ = function(source, reason)           -- fired on disqualification
OnRaceSessionEnd = function(finishOrder, dqList)-- fired when all drivers are done
OnPitStop = function(source, compound)          -- fired when a pit stop is confirmed
OnAchievementUnlocked = function(source, key, data) -- fired on achievement unlock
```

### Client hooks (`OpenClientFunctions`)

```lua
CanStartRace = function()                       -- return false to block race start
OnCheckpointPassed = function(cpIndex, total)   -- fired on each checkpoint hit
OnLapComplete = function(lapNumber, lapTimeMs)  -- fired on each lap completion
OnRaceFinish = function(position, raceTimeMs)   -- fired when the local player finishes
OnPitEntry = function()                         -- fired when player opens tire menu
OnPitExit = function(compound)                  -- fired after pit stop completes
```

---

## Upgrading from v2.0

`shared/config.lua` has been restructured again in v3.0. Do not copy your v2 config directly. Key changes:

- `Config.WinXP` / `Config.RatingWin` replaced by `Config.MmrGain` table and `Config.MmrLostBase`
- `Config.Rating` replaced by `Config.MmrGain` (same index structure)
- `Config.AutoRace` replaced by `Config.RaceSchedule` (day-of-week table)
- New keys: `Config.DefaultMMR`, `Config.FastestLapXP`, `Config.MaxRaceHistory`, `Config.MaxMmrHistory`, `Config.Sectors`, `Config.LapInvalidDist`, `Config.LapInvalidTime`, `Config.Achievements`
- `Config.VehicleTableName`, `Config.EventPrefix`, `Config.FlagProp` removed (not used in v3)
- All event names changed from `frcp_f1:` prefix to `fcrp_f1:` — update any external resources that listen to them
- DB schema changed — the `f1_players` table has new columns. Drop and recreate, or run the migrations below

### Migration SQL (v2 → v3)

```sql
ALTER TABLE f1_players
    ADD COLUMN podiums      INT NOT NULL DEFAULT 0,
    ADD COLUMN fastest_laps INT NOT NULL DEFAULT 0,
    ADD COLUMN best_lap_ms  INT DEFAULT NULL,
    ADD COLUMN stats        JSON NOT NULL DEFAULT '{}',
    ADD COLUMN achievements JSON NOT NULL DEFAULT '{}',
    ADD COLUMN mmr_history  JSON NOT NULL DEFAULT '[]',
    CHANGE COLUMN rating mmr INT NOT NULL DEFAULT 1500;

CREATE TABLE IF NOT EXISTS f1_race_history (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    race_id      VARCHAR(20) NOT NULL,
    citizenid    VARCHAR(50) NOT NULL,
    position     INT NOT NULL,
    total_laps   INT NOT NULL DEFAULT 0,
    race_time    VARCHAR(20),
    best_lap     VARCHAR(20),
    sector_times JSON NOT NULL DEFAULT '[]',
    tyre_used    VARCHAR(20),
    pit_count    INT NOT NULL DEFAULT 0,
    drs_count    INT NOT NULL DEFAULT 0,
    engine_ok    TINYINT(1) NOT NULL DEFAULT 1,
    xp_earned    INT NOT NULL DEFAULT 0,
    mmr_delta    INT NOT NULL DEFAULT 0,
    dq           TINYINT(1) NOT NULL DEFAULT 0,
    dq_reason    VARCHAR(100),
    race_date    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_cid (citizenid),
    INDEX idx_race (race_id)
);
```
