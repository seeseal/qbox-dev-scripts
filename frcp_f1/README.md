# frcp_f1 — Flame City Grand Prix
FiveM F1 racing resource built on QBX Core + ox_lib.

## Dependencies
- `qbx_core`
- `ox_lib`
- `frcp_webhook`

## Installation
Drop `frcp_f1` into your resources folder and add `ensure frcp_f1` to `server.cfg`.

## Usage
Type `/f1menu` in-game as an admin to open the Race Control panel.

### Step 1 — Grid
Assign drivers to P1–P8 slots by entering their server ID. Empty slots are automatically filled with NPC bot drivers. Press **Prepare Grid** to spawn all cars.

### Step 2 — Formation Lap
Press **Deploy Safety Car**. The SC leads the field around the full circuit once, then automatically returns to the start line, teleports all cars back to their grid spots, and begins the race countdown. No manual input needed.

### Step 3 — Race
Starts automatically after the formation lap. The **Start Race** button can be used to skip or override the formation lap.

---

## Features

### NPC Bots
- Fills empty grid slots up to P8
- Names: `BOT_Verstappin`, `BOT_Hamiltun`, `BOT_Leclairc`, `BOT_Norriss`, `BOT_Saainz`, `BOT_Russull`, `BOT_Alonzo`, `BOT_Piastrii`, `BOT_Cheeco`, `BOT_Hulkenburg`
- Team livery colors matched to 2025 F1 teams
- Race using GTA's internal race AI (drive style `1074528293`) — no braking on straights
- Appear on the live leaderboard in real time

### DRS
Defined in `Config.DRSZones`. On entry, `fInitialDriveForce` and top speed are boosted. HUD shows **DRS OPEN** in green.

### Engine Damage
Three tiers based on `GetVehicleEngineHealth`:
- **WARNING** — 85% power
- **DAMAGED** — 60% power  
- **CRITICAL** — 35% power

### Live Leaderboard
Top-right HUD showing all drivers sorted by race position. Gap to leader shown below your lap counter.

### Race Director Camera
Organiser only. Opens via the menu — enter any driver's server ID for a cinematic overhead follow-cam. Press Backspace to exit.

### Results
After all drivers finish, a `lib.notify` broadcast shows the full podium with times and gaps. Finishers are teleported after `Config.ResultsScreenDelay` seconds. DQ'd players are teleported instantly.

### Discord Webhook
Set `Config.DiscordWebhook` in `shared/config.lua`. Fires at race end with podium and DQ list.

---

## Config (`shared/config.lua`)

| Key | Default | Description |
|-----|---------|-------------|
| `Config.MaxLaps` | `1` | Number of laps |
| `Config.PrizeMoney` | `1000` | Cash paid to P1 winner |
| `Config.ResultsScreenDelay` | `18` | Seconds before post-race TP |
| `Config.OrganizerPermission` | `"admin"` | QBX group or ace perm |
| `Config.FormationLap.enabled` | `true` | Toggle formation lap |
| `Config.FormationLap.maxSpeed` | `160.0` | SC speed in km/h |
| `Config.DRSZones` | see config | Array of DRS zone definitions |
| `Config.GridSpots` | 8 spots | Add/remove `vector4` rows to change grid size |
| `Config.Checkpoints` | 3 CPs | Circuit definition |
