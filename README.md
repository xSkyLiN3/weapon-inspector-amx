# Weapon Inspector (AMX Mod X) 🔍

[![Build](https://github.com/xSkyLiN3/weapon-inspector-amx/actions/workflows/build.yml/badge.svg)](https://github.com/xSkyLiN3/weapon-inspector-amx/actions/workflows/build.yml)
[![License: GPL v3+](https://img.shields.io/badge/License-GPL--3.0--or--later-blue.svg)](LICENSE)

**Weapon Inspector** is a server-side AMX Mod X plugin for **Counter-Strike 1.6**. It discovers inspect-like sequences from GoldSrc model metadata instead of relying on fixed animation IDs.

When a viewmodel contains a sequence whose label matches a configured keyword, the plugin can select it, calculate its duration from frame/FPS metadata and play it on request. No client plugin is required; custom models must still be delivered through the server's normal asset-download mechanism.

> **Validation status:** AMX Mod X 1.10 compilation and release packaging are automated. Version 1.1.2 is undergoing private Counter-Strike 1.6 runtime validation. Runtime behavior described below is implementation intent until the validation matrix is complete.

---

## Quick Summary ✅

- 🎬 Selects an embedded sequence whose label matches configured keywords
- 🧠 Discovers inspect sequence IDs from model metadata
- 🛡️ Implements cancellation paths for firing, weapon switch, reload, zoom and death
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

The design targets custom GoldSrc models with compatible sequence labels. Compatibility and visual timing can vary by model.

---

## Expected runtime behavior 🎮

When a player triggers Inspect:

- The weapon plays an inspect-style animation (if available)
- The plugin keeps weapon-idle timing beyond the selected sequence duration
- On completion or cancellation, it selects a known idle sequence when available; otherwise it returns control to the GameDLL

Inspect is blocked in situations where it would break timing (zoomed, reloading, attacking, etc.).

---

## Key Features ✨

- 🔎 Automatic inspect detection (keyword-based)
- 🎞️ Real animation timing (frames + FPS)
- 🔇 Silencer-aware behavior (M4A1 / USP)
- 🎯 Scoped/zoom protection
- 🧊 Support gate for models without inspect animations
- ⏱️ Cooldown + busy windows (deploy/reload/fire)
- 🧯 Explicit cancellation paths
- 🧩 Developer API (natives + multi-forwards)
- 🧰 Admin debug tools

---

## Requirements

- Counter-Strike 1.6 dedicated server
- AMX Mod X 1.10
- Engine, Ham Sandwich, Fakemeta and CStrike modules enabled
- A viewmodel containing an inspect-like sequence (`inspect`, `lookat`, `examine` or `check` by default)

The default Counter-Strike models do not contain inspect animations. Inspect activation is skipped when no matching sequence is found; negative results are cached until configuration reload or plugin/map restart. A no-interference runtime matrix is tracked in [docs/validation.md](docs/validation.md).

---

## Activation 🕹️

CVAR:

    wi_impulse_mode

| Mode | Behavior |
|------|----------|
| 0 | Manual bind only |
| 1 | Impulse 100 (Flashlight key) |
| 2 | Impulse 201 |

Manual command (subject to the per-model `MANUAL_INSPECT` rule):

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
- Lines starting with `;` or `//` are comments

Default:

    inspect
    lookat
    examine
    check

---

## Per-Model Rules (`weapon_inspector_models.ini`) 🧩

This new INI lets you override behavior **per viewmodel path**, without touching code.

Path:

    addons/amxmodx/configs/weapon_inspector_models.ini

### What It Controls

Each model section is the full viewmodel path:

    [ models/custom/v_ak47.mdl ]

Supported keys:

- `AUTO_INSPECT = 0/1`  
  - `1` (default): do nothing special — allow the model’s normal idle behavior  
  - `0`: blocks “baked auto-inspect” idles by forcing a controlled idle loop (requires `IDLE_LOOP_TIME`)

- `MANUAL_INSPECT = 0/1`  
  - `1` (default): allow manual inspect (command/impulse)  
  - `0`: disable manual inspect for this model

- `IDLE_LOOP_TIME = float`  
  Enables the controlled idle loop when `AUTO_INSPECT = 0`.  
  Use small values like `0.60`–`1.00` to prevent idles from reaching an inspect segment baked into the same sequence.

- `IDLE_SEQ_FORCE = -1 / >=0`  
  - `-1` (default): auto-pick idle from idle pool  
  - `>= 0`: force a specific sequence index for the idle loop (only if valid for the model)

### Example

    [ models/custom/v_ak47.mdl ]
    AUTO_INSPECT    = 0
    MANUAL_INSPECT  = 1
    IDLE_SEQ_FORCE  = -1
    IDLE_LOOP_TIME  = 0.80

> Tip: If a model has only one long `idle` animation that contains an inspect moment near the end, set `AUTO_INSPECT = 0` and tune `IDLE_LOOP_TIME` so the idle keeps restarting before reaching that inspect part.

---

## Installation 📦

### Release package

1. Download `weapon-inspector-vX.Y.Z.zip` from the Releases page.
2. Extract its `addons` directory into the server's Counter-Strike directory.
3. Add the plugin to:

       addons/amxmodx/configs/plugins.ini

       weapon_inspector.amxx

4. Review `weapon_inspector.cfg`, then restart the server or change the map.

### Build from source

Download the AMX Mod X 1.10 base package and Counter-Strike addon, then run:

    .\scripts\build.ps1 -AmxxRoot C:\path\to\amxmodx

The script compiles `addons/amxmodx/scripting/weapon_inspector.sma` and writes `weapon_inspector.amxx` to `dist/` by default. The same compilation is executed by GitHub Actions on every pull request and push to `main`.

---

## Administrative Commands

| Command | Access | Description |
|---------|--------|-------------|
| `wi_status` | `ADMIN_RCON` | Shows plugin version and cache/configuration status |
| `wi_reload_config` | `ADMIN_RCON` | Reloads keyword/model rules and clears the model cache |
| `wi_debug <player>` | `ADMIN_RCON` | Shows state, timing, model and sequence information for a player |

Console access and the AMX Mod X `ADMIN_RCON` flag are accepted. Other clients are rejected by `cmd_access`.

---

## Versioning and Releases

This project follows [Semantic Versioning](https://semver.org/). Patch releases contain compatible fixes, minor releases add backward-compatible functionality and major releases may change configuration or API contracts.

Release tags must match the value in `VERSION` (for example, `v1.1.2`). A matching tag compiles the plugin, creates the consistently named `weapon-inspector-v1.1.2.zip` package and publishes it as a GitHub Release asset with a checksum.

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

# Technical Details 🧠

## Model Support Gate 🧊

Before any inspect logic runs:

- The model file is validated (size, Studio magic/version, declared length and bounded sequence table)
- Sequences are extracted once
- Support result is cached

Negative support results are cached until configuration reload or plugin/map restart.

---

## Duration Calculation ⏱️

Duration is calculated from model data:

    duration = frames / fps

Safety measures:

- FPS is sanity-clamped
- Frame count is read from the GoldSrc `numframes` field
- Final duration clamped between min/max CVARs

---

## Natural Idle Philosophy 🎞️

The plugin actively manages:

    m_flTimeWeaponIdle

During inspect, the field is written as a relative duration for CS 1.6 predicted weapon timing. After completion or cancellation, the plugin prefers a detected idle sequence and otherwise releases the timer for the GameDLL.

---

## Silencer Awareness 🔇

For M4A1 and USP:

- Prefers sequences tagged `_sil` or `_unsil`
- Falls back from the matching silencer pool to generic and then opposite-state sequences
- Blacklists attach/detach sequences

---

## Scoped / Zoom Handling 🎯

Inspect is blocked while zoomed using:

    cs_get_user_zoom()

The implementation blocks inspect while zoomed and cancels an active inspect when secondary attack is used. Visual behavior remains part of the runtime validation matrix.

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

GNU GPL version 3 or later. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

## Author 👤

Cristóbal Vergara ([xSkyLiN3](https://github.com/xSkyLiN3))
