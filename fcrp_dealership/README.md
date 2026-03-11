# frcp_dealership

**FlameDrive Motors** — The official Flame City dealership script.  
A fully custom vehicle sales system built on Qbox, ox_inventory, ox_lib, ox_target and oxmysql.

> Part of the `qbox-dev-scripts` monorepo. Lives in the `[custom]` folder on the server.

---

## Version

| | |
|---|---|
| **Current** | `v2.0.0` — Job System Update |
| **Previous** | `v1.2.1` — Base Dealership |
| **Framework** | Qbox (qbx_core) |
| **Last Updated** | 2025 |

---

## What This Script Does

FlameDrive Motors replaces the default PDM/EDM with a **three-tier vehicle dealership** that doubles as a **fully functional job** with roles, a shared stash, a changing room, test drives, and an automatic society fund that splits every sale between the dealership fund and the government tax account.

### Tiers

| Tier | Ticket Required | Money Required | Notes |
|---|---|---|---|
| **Standard** | ❌ | ✅ IC cash | Anyone can buy |
| **Elite** | ✅ Elite Ticket (Tebex) | ✅ IC cash | 30-min repurchase cooldown |
| **Apex** | ✅ Apex Ticket (Tebex) | ❌ Free IC | Server-wide supply limit |

### Job Grades

| Grade | Label | Can Sell | Can Test Drive | Is Boss |
|---|---|---|---|---|
| 0 | Trainee | ❌ | ✅ | ❌ |
| 1 | Salesperson | ✅ | ✅ | ❌ |
| 2 | Sales Manager | ✅ | ✅ | ❌ |
| 3 | General Manager | ✅ | ✅ | ✅ |

---

## Features

### 🚗 Dealership (v1 — carried forward)
- Custom NUI with purple/blue Flame City theme
- Three tiers: Standard, Elite, Apex
- Server-wide supply limits per vehicle
- Live stock updates across all open UIs
- Elite repurchase cooldown (DB-persisted across restarts)
- Automatic unique plate generation with collision checking
- Full refund logic if plate generation or DB insert fails
- Discord webhook log on every purchase

### 👔 Job System (v2 — new)
- 4 job grades with configurable permissions
- **Clock-in / Clock-out** zone using ox_target
- **Shared employee stash** (ox_inventory) — on-duty only
- **Changing room** — applies uniform outfit or prompts if none configured
- **Boss desk** — ox_target zone opens GM context menu
- Hire / Fire / Promote / Demote via in-world menu or NUI boss panel
- `/fdstaff` — lists all online employees with grade
- `/endtestdrive [id]` — staff command to end a customer's test drive early
- `/clearcooldown [id]` — admin command (unchanged from v1)
- All HR actions Discord-logged (hire, fire, promote, demote)

### 💰 Society Fund (v2 — new)
- Every sale **automatically splits** into society fund % + gov tax %
- Configurable split ratio (default: 80% fund / 20% tax)
- GM can check balance and withdraw up to a configurable cap per transaction
- Full transaction log in `frcp_dealership_transactions` table
- All withdrawals Discord-logged with before/after balance

### 🏎️ Test Drives (v2 — new)
- Salesperson targets a nearby customer via ox_target → picks a vehicle
- Timed (default: 5 minutes, configurable)
- On-screen countdown HUD drawn for the customer
- Boundary check every second — if customer exceeds radius, drive ends automatically
- Car is deleted and customer is teleported back to return coords on end
- Server-side tracking — cleans up on player disconnect

---

## Dependencies

| Resource | Purpose |
|---|---|
| `qbx_core` | Player data, job management, money |
| `oxmysql` | All database operations |
| `ox_lib` | Notifications, context menus, input dialogs, commands |
| `ox_inventory` | Shared employee stash |
| `ox_target` | All world interaction zones and NPC |
| `frcp_tickets` | Elite / Apex ticket checks and consumption |
| `frcp_webhook` | Discord logging across 6 channels |

---

## File Structure

```
frcp_dealership/
├── fxmanifest.lua
├── config.lua                  ← All custom values live here
├── client/
│   ├── main.lua                ← NUI, blip, NPC, vehicle spawn
│   ├── job.lua                 ← Clock-in, stash, changing room, boss menu
│   └── testdrive.lua           ← Timer HUD, boundary check, auto-recall
├── server/
│   ├── main.lua                ← Purchase logic, plate generation, supply tracking
│   ├── job.lua                 ← Hire, fire, promote, demote
│   ├── society.lua             ← Fund balance, auto-deposit, withdrawal
│   └── testdrive.lua           ← Drive tracking, disconnect cleanup
├── html/
│   ├── index.html              ← NUI layout (3 tabs)
│   ├── style.css               ← Purple/blue Flame City theme
│   ├── script.js               ← All NUI logic
│   └── fa-subset.css           ← Font Awesome icon subset (no CDN)
└── sql/
    ├── dealership.sql          ← Original v1 tables
    └── v2_upgrade.sql          ← v2 new tables (run once on upgrade)
```

---

## Database Tables

| Table | Purpose |
|---|---|
| `frcp_dealership_sold` | Tracks how many of each vehicle model have been sold |
| `frcp_dealership_cooldowns` | Elite purchase cooldowns per player, persisted across restarts |
| `frcp_dealership_society` | Single-row society fund balance |
| `frcp_dealership_transactions` | Full log of all deposits and withdrawals |

---

## Installation

### 1. Register the Job in Qbox

Open `qbx_core/shared/jobs.lua` and add the following inside the jobs table:

```lua
flamedrive = {
    label = 'FlameDrive Motors',
    grades = {
        [0] = { label = 'Trainee' },
        [1] = { label = 'Salesperson' },
        [2] = { label = 'Sales Manager' },
        [3] = { label = 'General Manager', isboss = true },
    }
}
```

> **Alternative:** If your server uses the database for jobs, uncomment and run the SQL INSERT statements at the bottom of `sql/v2_upgrade.sql`.

### 2. Run the SQL

In phpMyAdmin (database: `qbox_dev`), run:

```
sql/v2_upgrade.sql
```

This creates three new tables. It uses `CREATE TABLE IF NOT EXISTS` — safe to run even if tables already exist. Your v1 data is untouched.

### 3. Configure `config.lua`

Every line marked `!! CHANGE ME !!` must be updated before starting the resource.

| Setting | What to Change |
|---|---|
| `Config.JobName` | Must match the job name you registered in step 1 (e.g. `"flamedrive"`) |
| `Config.Location` | Coords of the salesperson NPC and map blip |
| `Config.SpawnPoint` | Where purchased vehicles spawn |
| `Config.OnDutyCoords` | Where the clock-in/out ox_target zone appears |
| `Config.StashCoords` | Where the shared employee stash ox_target zone appears |
| `Config.ChangingRoomCoords` | Where the changing room ox_target zone appears |
| `Config.TestDriveStart` | Where test drive cars spawn |
| `Config.TestDriveReturn` | Where customers are teleported when a test drive ends |
| `Config.SocietyPercent` | % of each sale that goes to the society fund (default: `80`) |
| `Config.TaxPercent` | % of each sale logged as gov tax (default: `20`) |
| `Config.MaxWithdrawal` | Max amount a GM can withdraw in one transaction |
| `Config.GovBankAccount` | Bank account name for gov tax (integrate your banking script) |

Also update `BOSS_DESK_COORDS` near the bottom of `client/job.lua` to match your boss desk location.

### 4. (Optional) Configure Uniform

In `config.lua`, populate `Config.EmployeeOutfit` with GTA V ped component IDs for your uniform:

```lua
Config.EmployeeOutfit = {
    { component = 11, drawable = 15, texture = 0 }, -- jacket
    { component = 8,  drawable = 58, texture = 0 }, -- shirt
    { component = 4,  drawable = 18, texture = 0 }, -- trousers
}
```

If left empty, the changing room will show a "No uniform configured" notification. You can still use ox_lib clothing menus separately.

### 5. (Optional) Integrate Gov Tax Payment

Open `server/society.lua` and find the comment block labelled `── GOV TAX ──`. Uncomment and adjust the line for your banking script to auto-pay the tax cut on every sale.

### 6. Deploy

```
# On your Windows dev server
# Replace the old frcp_dealership folder with this one, then:

restart frcp_dealership
```

---

## Commands

| Command | Who Can Use | What It Does |
|---|---|---|
| `/fdstaff` | All employees | Lists all online FlameDrive employees and their grades |
| `/endtestdrive [id]` | All employees | Force-ends a customer's active test drive |
| `/clearcooldown [id]` | Admins (`group.admin`) | Clears Elite repurchase cooldown for a player |

---

## How Money Flows (Plain English)

When a player buys a car for **$100,000** with an 80/20 split:

```
Player's bank       −$100,000
Society fund        +$80,000   → saved to frcp_dealership_society
Gov tax             +$20,000   → logged, paid via your banking script
Discord             → full embed with split breakdown
```

The GM can then:
1. Walk to the boss desk → open Boss Menu → click GM Office tab in NUI
2. Click "Refresh Balance" to see current fund
3. Click "Withdraw" → enter amount → money goes to their bank account

---

## NUI Tabs

| Tab | Visible To | Contents |
|---|---|---|
| **Vehicle Catalog** | Everyone | Full vehicle browser with tier/category filters and sort |
| **Employee Panel** | Employees only | Role info, duty status, test drive instructions, rules |
| **GM Office** | General Manager only | Society fund balance, withdraw button, hire/fire/promote/demote |

---

## Discord Webhook Channels Used

All logs go through `frcp_webhook` using `exports.frcp_webhook:Send()`.

| Channel Key | Events Logged |
|---|---|
| `dealership` | Vehicle purchases (with fund split), society withdrawals, HR actions |

---

## Testing Checklist

After deploying, run through this in order on your dev server:

- [ ] `/setjob [id] flamedrive 3` — give yourself GM grade
- [ ] Walk to `Config.OnDutyCoords` — see "Clock In" in ox_target
- [ ] Clock in → walk to stash → ox_inventory shared stash opens
- [ ] Walk to changing room → uniform on/off works
- [ ] Walk to boss desk → Boss Menu opens via ox_lib context
- [ ] Open NUI (click NPC) → Employee Panel tab visible, GM Office tab visible
- [ ] GM Office → Refresh Balance → shows $0
- [ ] Buy a Standard vehicle as any player → Discord log appears → balance updates
- [ ] GM withdraws from fund → Discord log appears → money in bank
- [ ] Give a second player grade 1 → have them target a customer → start test drive
- [ ] Confirm timer HUD appears on customer screen
- [ ] Wait for timer or drive out of bounds → car deleted, customer teleported back
- [ ] `/fdstaff` → lists online employees

---

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for full version history.

---

## Notes for Future Phases

- `frcp_tuner` — vehicle upgrade job, will use society fund pattern from this script
- `frcp_vipgarage` — reserved garage, will check job grade for access tiers
- Society fund pattern (`frcp_dealership_society` + `frcp_dealership_transactions`) is the template for all future job fund systems

---

*Flame City Dev — internal use only. Not for public release.*
