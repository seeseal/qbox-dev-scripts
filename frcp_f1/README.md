# 🏎️ FCRP F1 — Flame City Grand Prix
> **v3.0** · Qbox · ox_target · oxmysql · ox_lib

A fully custom Formula 1 racing system for FiveM roleplay servers built on the Qbox framework. Features a complete race lifecycle — from grid assignment and formation laps through to live telemetry, pit stops, DRS zones, and a purple-themed NUI dashboard.

---

## 📋 Table of Contents

- [Features](#-features)
- [Dependencies](#-dependencies)
- [Installation](#-installation)
- [File Structure](#-file-structure)
- [Configuration](#-configuration)
- [NUI Dashboard](#-nui-dashboard)
- [Commands](#-commands)
- [Debug & Diagnostics](#-debug--diagnostics)
- [Database](#-database)
- [Permissions](#-permissions)
- [Credits](#-credits)

---

## ✨ Features

| System | Details |
|---|---|
| **Race Lifecycle** | Grid assignment → Formation lap → Safety car → Lights out → Live race → Results |
| **NUI Dashboard** | Purple-themed in-game UI — Dashboard, Career Stats, Leaderboard, Race Control |
| **MMR / ELO** | True ELO-style rating starting at 1500, scales with field size |
| **XP System** | Position-based XP rewards, fastest lap bonus |
| **Tire Compounds** | Soft / Medium / Hard — each with unique grip, speed, and degradation |
| **Pit Stops** | Mandatory stop mechanic with timed freeze, compound selection UI |
| **DRS Zones** | Configurable activation zones, drive force + top speed boost |
| **Sector Timing** | S1 / S2 / S3 splits tracked per lap |
| **Fastest Lap** | Purple sector strip on results — bonus XP awarded |
| **Director Cam** | 4 camera modes (Follow, Helicopter, TV Cam, Onboard) — F6 cycles |
| **Spectator Mode** | Join any live race as a spectator, cycle drivers with arrow keys |
| **Achievements** | 20+ unlockable achievements tracked per player |
| **Race History** | Last 10 races stored per player with full stats |
| **Safety Car** | Deployable SC for formation lap procedure |
| **Engine Damage** | Progressive warning → damaged → critical health states |
| **Race Line** | Optional on-track racing line guide |
| **Item Gate** | Optional `racechip` item requirement per entry |
| **Debug Suite** | Full diagnostics, NUI test commands, 4-flag verbose logging |

---

## 📦 Dependencies

```
qbx_core
ox_lib
ox_target
ox_inventory
oxmysql
```

All dependencies must be **started before** `fcrp_f1` in your `server.cfg`.

---

## 🔧 Installation

**1. Drop the resource**
```
resources/[fcrp]/fcrp_f1/
```

**2. Add to `server.cfg`**
```cfg
ensure fcrp_f1
```

**3. Add ox_inventory items** (if `Config.Items.enabled = true`)
```lua
-- In your ox_inventory items file
['racechip'] = {
    label  = 'Race Chip',
    weight = 50,
    stack  = true,
    close  = true,
},
['money'] = { ... }  -- already exists in most servers
```

**4. Restart the server** — database tables are created automatically on first start.

---

## 📁 File Structure

```
fcrp_f1/
├── fxmanifest.lua
├── shared/
│   ├── config.lua          — all gameplay settings (edit this)
│   ├── debug.lua           — debug utilities, /f1debug, /f1nuitest
│   └── hooks.lua           — server hooks for external integrations
├── client/
│   ├── main.lua            — client-side race logic
│   └── nui_callbacks.lua   — NUI ↔ Lua bridge callbacks
├── server/
│   └── main.lua            — server-side race logic + database
└── html/
    ├── index.html          — NUI dashboard (purple theme)
    └── assets/
        └── style.css       — legacy stylesheet (fallback)
```

---

## ⚙️ Configuration

Everything is controlled from `shared/config.lua`. Key sections:

### General
```lua
Config.Debug        = false   -- master debug switch
Config.DebugVerbose = false   -- full NUI payload + table dumps
Config.DebugNUI     = false   -- log every SendNUIMessage action
Config.DebugEvents  = false   -- log every net event trigger

Config.MoneyType    = 'bank'  -- 'cash' | 'bank'
```

### Race Rules
```lua
Config.MaxLaps         = 5
Config.MinPlayers      = 2
Config.LapInvalidDist  = 40.0   -- metres off-course before lap is flagged invalid
Config.LapInvalidTime  = 6      -- consecutive seconds off-course to trigger DQ
```

### Prizes & MMR
```lua
Config.PrizeMoney  = 100000
Config.DefaultMMR  = 1500
Config.FastestLapXP = 15

--          P1   P2   P3   P4   P5   P6   P7   P8
Config.XP  = { 100, 80, 60, 40, 25, 15,  8,  4 }
Config.MmrGain = { 50, 35, 22, 12, 4, -4, -10, -18 }
```

### Tire Compounds
```lua
Config.TireCompounds = {
    soft   = { laps=3,  driveForce=0.12, topSpeedBonus=5.0,  ... },
    medium = { laps=6,  driveForce=0.05, topSpeedBonus=2.0,  ... },
    hard   = { laps=10, driveForce=0.00, topSpeedBonus=0.0,  ... },
}
```

### Pit Stop
```lua
Config.PitStop = {
    enabled      = true,
    mandatory    = true,       -- DQ at finish if no pit stop made
    speedLimit   = 80.0,       -- km/h speed limit in pit lane
    stopDuration = 4,          -- seconds frozen during tire change
    zone         = { coords=..., size=..., heading=... },
}
```

---

## 🖥️ NUI Dashboard

The in-game UI opens automatically when interacting with the paddock NPC or pressing **F5**.

| Panel | How to open | Contents |
|---|---|---|
| **Dashboard** | Default / F5 | Race status, live bars, career snapshot, quick actions |
| **Career Stats** | Sidebar icon | MMR, XP, wins, podiums, races, fastest laps, best lap, race history table |
| **Leaderboard** | Sidebar icon | Top 20 drivers by MMR with animated rating bars |
| **Race Control** | Sidebar icon (admin) | Grid slot assignment, safety car, race start, director cam, force end |

### NUI Message Actions (for external integrations)

```lua
-- Show the stats panel
SendNUIMessage({ action='showStats', stats={...}, history={...} })

-- Show the leaderboard panel
SendNUIMessage({ action='showLeaderboard', rows={...} })

-- Show the organizer panel
SendNUIMessage({ action='openOrganizerMenu', playerList={...}, slotLabels={...} })

-- Show post-race results overlay
SendNUIMessage({ action='showResults', results={...}, subtitle='...', delay=20 })

-- Spectator HUD
SendNUIMessage({ action='specUpdate', name='Driver', info='LAP 3 · P1' })
SendNUIMessage({ action='specHide' })

-- Director cam indicator
SendNUIMessage({ action='camMode', label='Follow' })
SendNUIMessage({ action='camHide' })
```

---

## 💬 Commands

### Player Commands
| Command | Key | Description |
|---|---|---|
| `/f1menu` | — | Open Race Manager (stats for players, control panel for admins) |
| — | `F5` | Open NUI dashboard |
| — | `← →` | Cycle spectator targets |
| — | `F6` | Cycle director camera mode |
| — | `Backspace` | Exit director camera |

### Admin Commands
| Command | Permission | Description |
|---|---|---|
| `/f1menu` | `admin` | Opens Race Control panel |
| `/f1debug_server` | `admin` | Runs server-side diagnostics report |

### Debug Commands *(only available when `Config.Debug = true`)*
| Command | Description |
|---|---|
| `/f1debug` | Full client diagnostics — checks config, dependencies, resource states, NUI, ped |
| `/f1nuitest showResults` | Fires a fake results overlay with sample data |
| `/f1nuitest showStats` | Opens the stats panel with sample career data |
| `/f1nuitest showLeaderboard` | Opens the leaderboard with sample data |
| `/f1nuitest organizer` | Opens the Race Control panel with sample grid |
| `/f1nuitest spec` | Shows the spectator HUD |
| `/f1nuitest cam` | Shows the director cam indicator |
| `/f1nuitest hide` | Hides all NUI overlays and releases NUI focus |

---

## 🔍 Debug & Diagnostics

Set `Config.Debug = true` in `shared/config.lua` to enable the full debug suite.

### Log Functions (available globally on client + server)

```lua
DBG(...)          -- info log  — only fires when Config.Debug = true
DBGW(...)         -- warning   — always fires
DBGE(...)         -- error     — always fires
DBG_TABLE(t, lbl) -- pretty-print a table to console
DBG_SECTION(str)  -- prints a visual section divider
DBG_NUI(payload)  -- logs a NUI payload (verbose if Config.DebugVerbose = true)
DBG_EVENT(dir, event, ...) -- logs a net event trigger
```

### Console Output Example
```
[FCRP_F1] [SRV] requestMyStats cid=ABC123 src=3
[FCRP_F1] [SRV] Sending stats NUI: mmr=1847 races=38 history_rows=5
[FCRP_F1] [CLI] [NUI →] action=showStats
```

### Diagnostic Checks (`/f1debug`)
- Config values loaded and valid
- All dependency resources started (`qbx_core`, `ox_lib`, `ox_target`, `ox_inventory`, `oxmysql`)
- All exports accessible
- `html/index.html` file exists
- Player ped valid, not dead
- Vehicle model matches `Config.F1CarModel`

---

## 🗄️ Database

Three tables are created automatically on first resource start.

### `f1_players`
Stores per-player career stats.

| Column | Type | Description |
|---|---|---|
| `citizenid` | VARCHAR(50) | Primary key |
| `mmr` | INT | Current MMR rating (default 1500) |
| `xp` | INT | Total XP earned |
| `wins` | INT | Race wins |
| `races` | INT | Total races completed |
| `podiums` | INT | Top-3 finishes |
| `fastest_laps` | INT | Fastest lap awards |
| `best_lap_ms` | INT | All-time best lap in milliseconds |
| `achievements` | JSON | Unlocked achievement keys |
| `mmr_history` | JSON | Last 20 MMR delta entries |

### `f1_race_history`
One row per driver per race.

| Column | Type | Description |
|---|---|---|
| `race_id` | VARCHAR(20) | Unique race identifier (e.g. `F1-20260316-4821`) |
| `citizenid` | VARCHAR(50) | Driver citizen ID |
| `position` | INT | Finishing position |
| `race_time` | VARCHAR(20) | Total race time string |
| `best_lap` | VARCHAR(20) | Best lap time string |
| `tyre_used` | VARCHAR(20) | Final compound used |
| `pit_count` | INT | Number of pit stops |
| `drs_count` | INT | Number of DRS activations |
| `xp_earned` | INT | XP awarded this race |
| `mmr_delta` | INT | MMR change this race |
| `dq` | TINYINT | 1 if disqualified |
| `dq_reason` | VARCHAR(100) | Reason for disqualification |

### `f1_crews`
Optional crew/team grouping (reserved for future use).

---

## 🔐 Permissions

```lua
Config.OrganizerPermission = 'admin'  -- 'admin' | 'superadmin' | nil (dev mode)
```

Set to `nil` during development to allow any player to open the Race Control panel. In production always set to `'admin'` or `'superadmin'`.

The permission is checked via both **Ace permissions** (`IsPlayerAceAllowed`) and **Qbox player group** as a fallback.

---

## 📝 Credits

| Role | Name |
|---|---|
| Development | FCRP Dev Team |
| Framework | [Qbox](https://github.com/qbox-project) |
| UI Library | [ox_lib](https://github.com/overextended/ox_lib) |
| Targeting | [ox_target](https://github.com/overextended/ox_target) |
| Database | [oxmysql](https://github.com/overextended/oxmysql) |
| Inventory | [ox_inventory](https://github.com/overextended/ox_inventory) |

---

*Flame City Roleplay · Season 3 · Built for FiveM*
