# Weapon Inspector (AMX Mod X) 🔍

**Weapon Inspector** adds a clean, modern “inspect weapon” feature to **Counter-Strike 1.6** — entirely **server-side**, using **AMX Mod X** with **Ham Sandwich + Fakemeta (+ CStrike)**.

Players can inspect the weapon they’re holding and see the model’s **real inspect animation** (if the model has one). No client-side modifications are required.

If a model does not support inspect animations, the plugin simply **does nothing** for that model — no interference, no forced animations, no idle manipulation.

---

## Quick Summary ✅

- 🎬 Plays the real inspect animation embedded in the weapon’s viewmodel
- 🧠 No hardcoded animation IDs
- 🛡️ Safe behavior: cancels cleanly on shooting, switching weapons, reload, zoom, death
- 🎮 Multiple activation options: Impulse or manual bind
- ⚙️ Configurable duration clamps, cooldowns, anti-spam
- 🧊 Model support gate (unsupported models are cached and skipped)

---

## Why This Plugin? ⭐

Many servers use custom `v_models`, and each model may contain different animation indices. Hardcoding animation IDs is fragile and unreliable.

Weapon Inspector avoids that by:

- Reading the model’s sequence list at runtime
- Detecting inspect sequences by configurable keywords
- Calculating duration using the model’s own frame/FPS data
- Caching results per model path

Result: **Works across many custom models without manual tuning.**

---

## What Players See 🎮

When a player triggers Inspect:

- The weapon plays an inspect-style animation (if available)
- The animation completes naturally
- Normal gameplay resumes automatically

Inspect is blocked in situations where it would break timing (zoomed, reloading, attacking, etc.).

---

## Key Features ✨

- 🔎 Automatic inspect detection (keyword-based)
- 🎞️ Real animation timing (frames + FPS)
- 🔇 Silencer-aware behavior (M4A1 / USP)
- 🎯 Scoped/zoom protection
- 🧊 Support gate for models without inspect animations
- ⏱️ Cooldown + busy windows (deploy/reload/fire)
- 🧯 Safe cancellation system
- 🧩 Developer API (natives + multi-forwards)
- 🧰 Admin debug tools

---

## Activation 🕹️

CVAR:

    wi_impulse_mode

| Mode | Behavior |
|------|----------|
| 0 | Manual bind only |
| 1 | Impulse 100 (Flashlight key) |
| 2 | Impulse 201 |

Manual bind (always available):

    bind f "inspect"

---

## Configuration ⚙️

Example:

    wi_enabled "1"
    wi_impulse_mode "1"

    wi_deploy_cooldown "1.0"
    wi_reload_cooldown "0.0"

    wi_dur_min "0.1"
    wi_dur_max "16.0"

    wi_max_per_sec "3"

    wi_log_models "0"
    wi_announce "0"

### CVAR Reference

| CVAR | Description |
|------|------------|
| wi_enabled | Enable/disable plugin |
| wi_impulse_mode | Activation method |
| wi_deploy_cooldown | Delay after weapon deploy |
| wi_reload_cooldown | Extra delay after reload |
| wi_dur_min | Minimum duration clamp |
| wi_dur_max | Maximum duration clamp |
| wi_max_per_sec | Anti-spam limit |
| wi_log_models | Log model analysis |
| wi_announce | Show hint message |

---

## Inspect Keywords (`inspect_list.ini`) 🗂️

Path:

    addons/amxmodx/configs/inspect_list.ini

Rules:
- One keyword per line
- Case-insensitive
- Lines starting with ; or // are comments

Default:

    inspect
    lookat
    examine
    check

---

## Installation 📦

1. Compile `weapon_inspector.sma`
2. Move `.amxx` to:

       addons/amxmodx/plugins/

3. Add to:

       addons/amxmodx/configs/plugins.ini

       weapon_inspector.amxx

4. Restart server or change map

---

# Technical Details 🧠

## Model Support Gate 🧊

Before any inspect logic runs:

- The model file is validated (exists, size check, Studio header magic)
- Sequences are extracted once
- Support result is cached

Unsupported models are permanently skipped.

---

## Duration Calculation ⏱️

Duration is calculated from model data:

    duration = frames / fps

Safety measures:

- FPS is sanity-clamped
- Frame count chosen via heuristic
- Final duration clamped between min/max CVARs

---

## Natural Idle Philosophy 🎞️

The plugin does NOT spam idle animations.

Instead, it extends:

    m_flTimeWeaponIdle

When inspect ends, the engine resumes its normal idle cycle automatically.

---

## Silencer Awareness 🔇

For M4A1 and USP:

- Prefers sequences tagged `_sil` or `_unsil`
- Falls back safely if pool missing
- Blacklists attach/detach sequences

---

## Scoped / Zoom Handling 🎯

Inspect is blocked while zoomed using:

    cs_get_user_zoom()

Prevents animation conflicts and view glitches.

---

## Busy Windows & Cooldown Policy 🛑

Two time gates:

- Cooldown (cannot start inspect before this time)
- Busy (weapon still in animation window)

Extended by:

- Deploy
- Reload
- Primary/secondary attack
- Inspect cancellation

---

## Hooks Used 🪝

- client_impulse (impulse activation)
- FM_PlayerPreThink (lifecycle management)
- Ham_Weapon_PrimaryAttack (POST)
- Ham_Weapon_SecondaryAttack (POST)
- Ham_Item_Deploy (POST)
- Ham_Weapon_Reload (POST)

---

## Model Parsing 📄

The plugin reads:

- numseq
- seqindex
- sequence names
- FPS
- frame counts

Cached per model using Trie + Array structures.

---

## Developer API 🧩

Include:

    #include <weapon_inspector>

Natives:

    wi_is_inspecting( id )
    wi_force_inspect( id )
    wi_block_inspect( id, Float:duration )
    wi_get_inspect_timeleft( id )

Forwards:

    wi_inspect_start_pre( id, weapon, seq )
    wi_inspect_start( id, weapon, seq )
    wi_inspect_end( id )

---

## License 📜

MIT License

---

## Author 👤

SkyLiN3
