# fcrp_f1 — Flame City Grand Prix
**v2.0** · FiveM F1 racing resource · Qbox + ox_lib + ox_target + oxmysql

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

## Installation

1. Drop `fcrp_f1` into your `resources/` folder
2. Add `ensure fcrp_f1` to your `server.cfg`
3. Start your server — the required database tables are created automatically on first boot
4. Configure everything in `shared/config.lua`

---

## Running a Race

All race control is accessed via `/f1menu` (admin only) or by interacting with the **Race Manager NPC** placed at `Config.RaceManagerNPC.coords`.

### Step 1 — Build the Grid
Open the organiser panel and assign drivers to **P1–P8** slots using their server ID. Press **Prepare Grid** to spawn all cars on their grid spots.

> If `Config.Items.enabled = true`, each driver must have a `racechip` item in their inventory to be placed on the grid.

### Step 2 — Formation Lap
Press **Deploy Safety Car**. The SC leads the full field around the circuit at `Config.FormationLap.maxSpeed` km/h. Once it returns to the start, all cars are teleported back to their grid spots and the race countdown begins automatically.

### Step 3 — Lights Out
The race starts automatically after the formation lap. The **START RACE** button can be used to skip or override the formation lap at any time.

---

## Features

### 🏎️ Configurable F1 Car
Set a single car model for the entire race via `Config.F1CarModel`. All base handling values are defined in `Config.F1BaseHandling` — no editing of handling.meta required. Max performance mods and a unique livery are applied automatically on spawn.

### 🛞 Tire Compound System
Three compounds available — **Soft**, **Medium**, and **Hard** — each with its own:
- Lap life before degradation kicks in
- Drive force and top speed bonus
- Traction curve values
- Degradation penalties when worn

Drivers change tires in the pit lane via an `ox_target` box zone. Compound selection opens a menu. If `Config.PitStop.mandatory = true`, drivers who do not pit will be disqualified at the finish line.

A speed limiter is enforced in the pit lane zone based on `Config.PitStop.speedLimit`.

### ⚡ DRS System
DRS zones are defined in `Config.DRSZones` as entry → exit segments with a lateral corridor radius. Inside a zone, drive force and top speed are boosted and a **DRS OPEN** banner appears on screen.

DRS state is combined with tire compound handling and engine damage multipliers in real time.

### 🔥 Engine Damage
Three tiers based on `GetVehicleEngineHealth`:

| Status | Power |
|---|---|
| WARNING | 85% |
| DAMAGED | 60% |
| CRITICAL | 35% |

Notifications fire on each tier change. Power is factored into handling alongside DRS and tire state.

### 🧭 Race Line
Forza-style directional arrows guide drivers toward the next checkpoint. Configurable segment count and draw distance. Toggle off with `Config.RaceLine.enabled = false`.

### 📺 Live Leaderboard HUD
Top-right HUD shows all drivers sorted by live race position (lap × 1000 + CP). Each driver sees their gap to the leader displayed below their lap counter.

### 🎥 Race Director Camera
Organiser only. Accessible from the panel — enter any driver's server ID to attach a cinematic overhead follow-cam locked to their car. Press **Backspace** to exit.

### 🏆 XP & Rating
Persistent per-player stats stored in `f1_players` (MySQL). Every race updates:
- **XP** — flat reward per finishing position
- **Rating** — Elo-style delta per position (positive for top half, negative for bottom)
- **Wins** and **Races** counters

### 🎁 Weekly Reward
Players claim a configurable weekly reward via `/f1reward`. Cooldown is stored in the database. Reward type can be `money` or `item`.

### 👥 Crew System
Players can create a crew with `/createf1crew <name>` for a configurable money cost. Crew data is stored in `f1_crews` (MySQL).

### 📊 Results Screen
A full-screen NUI overlay appears at race end showing:
- Finishing position with podium colour coding
- Race time and gap to winner
- **XP gained** and **Rating delta** per driver
- DQ'd drivers shown separately with reason

The overlay auto-dismisses after `Config.ResultsScreenDelay` seconds and triggers the post-race teleport.

### 📢 Discord Webhook
Set `Config.DiscordWebhook` to post a race summary embed to your Discord at race end. Includes full podium with times and a DQ list.

---

## Commands

| Command | Permission | Description |
|---|---|---|
| `/f1menu` | Admin | Open the Race Control organiser panel |
| `/f1stats` | All | View your own XP, rating, wins and races in chat |
| `/f1leaderboard` | All | Show the top 10 drivers by rating in chat |
| `/f1reward` | All | Claim your weekly reward |
| `/createf1crew <name>` | All | Create a racing crew |

---

## Configuration Reference (`shared/config.lua`)

### General
| Key | Default | Description |
|---|---|---|
| `Config.F1CarModel` | `` `openwheel1` `` | Car model hash used for every race |
| `Config.LiveryCount` | `11` | Number of liveries on the model (random assignment from 2 onward) |
| `Config.MaxLaps` | `5` | Number of laps |
| `Config.MinPlayers` | `2` | Minimum drivers to allow a race to start |
| `Config.ResultsScreenDelay` | `18` | Seconds the results overlay shows before post-race TP |
| `Config.PrizeMoney` | `100000` | Cash awarded to P1 via ox_inventory |
| `Config.MoneyType` | `'bank'` | `'cash'` or `'bank'` |
| `Config.OrganizerPermission` | `'admin'` | QBX group or ace permission required for organiser panel |
| `Config.Debug` | `false` | Print debug output to server/client console |

### Tire Compounds & Pit Stop
| Key | Description |
|---|---|
| `Config.TireCompounds.soft/medium/hard` | Lap life, force bonus, traction, and degradation values per compound |
| `Config.PitStop.enabled` | Toggle pit stop system |
| `Config.PitStop.mandatory` | DQ drivers who do not pit |
| `Config.PitStop.zone` | `coords`, `size`, and `heading` of the pit lane ox_target box |
| `Config.PitStop.speedLimit` | km/h cap enforced in the pit lane zone |
| `Config.PitStop.stopDuration` | Seconds the car is frozen during the stop |

### DRS
| Key | Default | Description |
|---|---|---|
| `Config.DRSZones` | 2 zones | Array of `{ name, entry, exit, radius }` zone definitions |
| `Config.DRS.driveForceBoost` | `0.45` | Added to `fInitialDriveForce` inside a zone |
| `Config.DRS.topSpeedBoost` | `15.0` | Added to top speed modifier inside a zone |

### XP & Rating
| Key | Default | Description |
|---|---|---|
| `Config.WinXP` | `150` | XP awarded to P1 |
| `Config.RatingWin` | `50` | Rating awarded to P1 |
| `Config.XP` | `{ 100, 80, 60 ... }` | XP table indexed by finishing position |
| `Config.Rating` | `{ 50, 35, 22 ... }` | Rating delta table indexed by finishing position |

### Grid & Circuit
| Key | Description |
|---|---|
| `Config.GridSpots` | Array of `vector4` spawn points (up to 8) |
| `Config.Checkpoints` | Array of `vector3` circuit checkpoints. CP 1 = Start/Finish |
| `Config.PostRaceLocation` | `vector4` where all drivers are teleported after the race |

### NPC
| Key | Description |
|---|---|
| `Config.RaceManagerNPC.enabled` | Toggle the Race Manager NPC |
| `Config.RaceManagerNPC.coords` | `vector4` spawn location |
| `Config.RaceManagerNPC.model` | Ped model name string |
| `Config.RaceManagerNPC.label` | ox_target interaction label |

---

## Database Tables

Both tables are created automatically on resource start.

**`f1_players`** — per-player stats

| Column | Type | Description |
|---|---|---|
| `citizenid` | VARCHAR(50) PK | Qbox citizen ID |
| `xp` | INT | Total XP earned |
| `rating` | INT | Current rating (starts at 1000) |
| `wins` | INT | Total race wins |
| `races` | INT | Total races completed |
| `weekly_claimed` | BIGINT | Unix timestamp of last weekly claim |

**`f1_crews`** — crew registry

| Column | Type | Description |
|---|---|---|
| `id` | INT AUTO_INCREMENT PK | Crew ID |
| `name` | VARCHAR(100) | Crew display name |
| `leader` | VARCHAR(50) | citizenid of the crew leader |
| `members` | TEXT | JSON array of member citizenids |

---

## Upgrading from v1.x

`shared/config.lua` has been fully restructured in v2.0. Do not copy your old config over directly. Instead, open both files side by side and migrate your values into the new keys. Key changes:

- `Config.F1CarModel` — same key, now a hash literal
- `Config.MaxLaps` / `Config.PrizeMoney` — unchanged
- `Config.DRSZones` / `Config.DRS` — unchanged structure
- `Config.EngineHealth` — unchanged
- `Config.GridSpots` / `Config.Checkpoints` — unchanged
- `Config.FormationLap` — unchanged
- `Config.PostRaceLocation` — unchanged
- `Config.DiscordWebhook` / `Config.WebhookBotName` — unchanged
- `Config.OrganizerPermission` — unchanged
- **New in v2.0:** `Config.TireCompounds`, `Config.PitStop`, `Config.RaceLine`, `Config.Items`, `Config.CrewSystem`, `Config.WeeklyReward`, `Config.XP`, `Config.Rating`, `Config.RaceManagerNPC`, `Config.AutoRace`, `Config.Notify`, `Config.Auth`
