# BLOXSTRIKE: Neon Arena

A complete Roblox shooting game written in **Luau**, plus a **browser version** with
a login screen. Blocky neon arena, wave-spawning enemies, a raycast blaster with
recoil, reload, ADS, tracers, hitmarkers, damage numbers, and a score leaderboard.

```
BLOXSTRIKE/
├─ default.project.json          # Rojo project (optional, one-click sync)
├─ src/                          # Roblox game source (Luau)
│  ├─ ReplicatedStorage/ShooterConfig.lua        (ModuleScript)
│  ├─ ServerScriptService/ShooterServer.server.lua   (Script)
│  └─ StarterPlayerScripts/ShooterClient.client.lua  (LocalScript)
└─ web/                          # Browser version of the game
   ├─ index.html
   ├─ style.css
   └─ game.js
```

## Part 1 — Roblox game (manual paste, 5 minutes)

Roblox can't be published from a plain script/CI; you upload from **Roblox Studio**
signed into your account. Steps:

1. Open **Roblox Studio** → **New Baseplate**.
2. In the **Explorer** window:
   - Create a **ModuleScript** inside `ReplicatedStorage`, name it `ShooterConfig`,
     and paste the contents of `src/ReplicatedStorage/ShooterConfig.lua`.
   - Create a **Script** inside `ServerScriptService`, name it `ShooterServer`,
     and paste `src/ServerScriptService/ShooterServer.server.lua`.
   - Create a **LocalScript** inside `StarterPlayer > StarterPlayerScripts`,
     name it `ShooterClient`, and paste
     `src/StarterPlayerScripts/ShooterClient.client.lua`.
3. Press **Play** (F5). The arena, enemies and weapon build themselves.
4. To publish: **File → Publish to Roblox As…**, pick a name (e.g. *BLOXSTRIKE:
   Neon Arena*), then **Create**.

### Controls

| Action | Input |
| --- | --- |
| Move | W A S D |
| Jump | Space |
| Shoot | Left Mouse (automatic) |
| Aim (zoom) | Hold Right Mouse |
| Reload | R |

### Without Studio / automated (Rojo)

If you have [Rojo](https://rojo.space):

```bash
rojo serve            # then connect from the Rojo Studio plugin
# or
rojo build -o BLOXSTRIKE.rbxlx
```

## Part 2 — Browser game (login required)

The `web/` folder is a **standalone** HTML5 Canvas shooter. Open `web/index.html`
in any browser (or serve it) — you must **register / log in** before you can play.

```bash
# quick local server
cd web && python3 -m http.server 8000
# now open http://localhost:8000
```

> **Note on the login:** the browser build stores accounts in the browser's
> `localStorage` — it gates play and remembers your high score, but it is **not**
> real server-side authentication. For production auth (real accounts, passwords,
> sessions) you need a backend (Node/Express, Supabase, Firebase Auth, etc.). The
> game logic is ready to bolt that onto.

### Controls (browser)

| Action | Input |
| --- | --- |
| Move | W A S D / Arrow keys |
| Aim | Mouse |
| Shoot | Left Mouse (hold) |
| Reload | R |
| Pause | Esc |

## Tuning

All gameplay values live in `ShooterConfig.lua` (Roblox) and `CONFIG` near the top
of `web/game.js` (browser): damage, fire rate, mag size, enemy count, arena size,
colors, and more.

## License

MIT — do whatever you want.
