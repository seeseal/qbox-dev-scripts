# fcrp_tuner — Command Reference

---

## Tuner Job Commands

### `/tunerduty`
Toggle on or off duty as a tuner.

- Must have the `tuner` job.
- Going **on duty** activates the ramp zone and shows shop blips on the map.
- Going **off duty** hides blips and locks the shop — customers cannot be served.
- Supply runs also require on-duty status.

---

### `/supplyrun`
Dispatch a supply run to collect `damaged_parts` for crafting.

- Must have the `tuner` job and be **on duty**.
- Sends you to a random pickup location across the city.
- Press **E** at the marked location to collect parts (8-second progress bar).
- Rewards **3–6 damaged parts** on completion.
- **15-minute cooldown** between runs.
- Only one active run per player at a time.

---

## Police Commands

### `/checkchip`
Check whether the vehicle you are currently seated in has an engine chip installed.

- Restricted to the `police` job.
- Result is shown as a notification and logged to Discord.

---

### `/removechip`
Remove an engine chip from the nearest vehicle (within 5m).

- Restricted to the `police` job.
- Removes the chip from the database and resets the vehicle's top speed on all clients.
- Logged to Discord.

---

### `/inspectcar`
Perform a full illegal mod scan on the nearest vehicle (within 10m).

- Restricted to the `police` job.
- Lists every installed mod: engine chip, drift chip, nitrous (with tank %), neon type, stance kit, exhaust mod, and fake plate.
- Shows the real plate even if a fake plate is active.
- Logged to Discord.

---

### `/scanplate`
Scan the nearest vehicle's plate (within 8m) to check for a fake plate.

- Restricted to the `police` job.
- If a fake plate is detected, reveals the real registered plate.
- If the plate appears legitimate, confirms it as clean.
- Logged to Discord.

---

## Shop Interactions

The tuner shop is opened by pressing **E** while driving over a ramp zone (on duty).  
All purchases are made through the in-game NUI menu — no chat commands required.

| Action | How |
|---|---|
| Open shop | Drive onto ramp · press **E** |
| Close shop | Press **ESC** or click ✕ |
| Stance editor — select property | **↑ / ↓** arrow keys |
| Stance editor — adjust value | **← / →** arrow keys |
| Stance editor — fast adjust | **SHIFT + ← / →** |
| Stance editor — save | **ENTER** |
| Stance editor — cancel | **BACKSPACE** |
| Activate nitrous | **LEFT SHIFT** (driver only, while installed) |
