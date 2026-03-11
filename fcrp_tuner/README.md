# fcrp_tuner
**Illegal Tuner Shop** — FiveM resource for the Qbox framework.

An underground vehicle modification shop where players with the `tuner` job install illegal performance and cosmetic mods on customer vehicles, paid in dirty cash.

---

## Dependencies
- `qbx_core`
- `ox_lib`
- `oxmysql`
- `ox_inventory`

---

## Features

**Performance**
- Engine Chip — boosts top speed by 15%. Price scales with the vehicle's depot value. Requires an S3 Chip item.
- Drift Chip — reduces traction, increases tyre slip, adds tyre smoke. Mutually exclusive with engine chip. Requires a Drift Chip item.
- Stance Kit — adjustable camber and ride height via a live editor. Requires a Stance Rod item.
- Nitrous Kit — LEFT SHIFT burst. Pressure-based tank (0–100%). Refill with NOS Canister items. 5-minute cooldown after each use.

**Cosmetic**
- Exhaust Mod — anti-lag backfire flames on throttle lift at high RPM.
- Neon Kits — static, rainbow, RGB, and strobe underglow. Colours persist across sessions.
- Fake Plate — display a custom plate. PD can detect it with `/scanplate`.

**Job System**
| Grade | Label | Commission | Can Craft | Owner |
|---|---|---|---|---|
| 0 | Tuner I | 20% | ✗ | ✗ |
| 1 | Tuner II | 30% | ✓ | ✗ |
| 2 | Master Tuner | 30% | ✓ | ✓ |

**Crafting**
Tuner II and above can craft items using `damaged_parts`, collected via `/supplyrun`. No other ingredients required.

| Item | Cost |
|---|---|
| S3 Engine Chip | 4x Damaged Parts |
| Drift Chip | 3x Damaged Parts |
| Stance Rod | 2x Damaged Parts |
| NOS Canister | 2x Damaged Parts |

**Supply Runs**
On-duty tuners use `/supplyrun` to receive a random pickup location across the city. Collect parts and return. 15-minute cooldown per run. Rewards 3–6 damaged parts.

**Police Tools**
- `/checkchip` — check if the vehicle you're in has an engine chip.
- `/removechip` — remove an engine chip from a nearby vehicle.
- `/inspectcar` — full scan of all installed illegal mods on a nearby vehicle.
- `/scanplate` — detect whether a nearby vehicle is running a fake plate.

---

## Installation

1. Drop the `fcrp_tuner` folder into your resources directory.
2. Add `ensure fcrp_tuner` to your `server.cfg`.
3. Run `MySQL/tuner.sql` in your database. If upgrading, run the migration block at the bottom of the file.
4. Add the items from `dependency/items.lua` to your `ox_inventory` items file.
5. Add the job from `dependency/job.lua` to your `qbx_core` jobs configuration.
6. Copy item images from `dependency/images/` into `ox_inventory/web/images/`.
7. Set `Config.DiscordWebhook` in `config.lua` if you want logging.

---

## Configuration

All tunable values live in `config.lua` — prices, boost percentages, install durations, NOS pressure drain, supply run cooldown, ramp locations, and more. No other files need to be edited for basic setup.

---

## Payment

All purchases are taken from the **customer's** dirty cash. The tuner receives a commission cut automatically, paid directly into their inventory as dirty cash. No society account or external paycheck script is needed.

---

## License
Private resource — FCRP. Do not redistribute.
