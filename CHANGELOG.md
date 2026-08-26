# Changelog

All notable changes are documented here. This project follows [Semantic Versioning](https://semver.org/).

## [1.1.2] - Unreleased

### Fixed

- Store predicted weapon idle delays using the relative timebase expected by Counter-Strike.
- Make `wi_enabled 0` bypass hooks and cancel active inspections.
- Clear inspection state on death and release the idle timer when disabling mid-animation.
- Reject invalid impulse modes instead of intercepting unrelated impulses.
- Enforce primary/secondary busy windows for forced inspections and use the weapon entity's bodygroup.
- Preserve normal secondary-attack behavior when the active model is unsupported.
- Validate GoldSrc Studio headers, sequence-table bounds, playable sequence indices and INI line lengths before reading them.
- Read animation frame counts from the documented `numframes` field and reject invalid FPS values.

### Changed

- Return idle control to the GameDLL when no safe idle sequence is known.
- License project code as GNU GPL version 3 or later to match AMX Mod X plugin-distribution terms.
- Add deterministic packaging, repeat-build checks and release checksums.

## [1.1.1] - 2026-08-17

### Fixed

- Register public API natives with the matching AMX Mod X handler style.
- Enforce `ADMIN_RCON` access on `wi_status` and `wi_reload_config` as well as `wi_debug`.
- Destroy cached sequence arrays before clearing their tries during configuration reloads.
- Declare and document the Engine module required by the `client_impulse` forward.
- Align the source filename (`weapon_inspector.sma`), compiled plugin (`weapon_inspector.amxx`) and future release asset names.

### Added

- Reproducible AMX Mod X 1.10.0.5478 build and release workflow.
- Local PowerShell build script and checked-in per-model configuration template.

## [1.1.0] - 2026-02-22

### Added

- Per-model rules for automatic/manual inspect behavior and idle-loop control.
- Forced idle sequence support.

### Fixed

- Shotgun reload compatibility for the M3 and XM1014.

## [1.0.0] - 2026-02-11

### Added

- Initial server-side weapon inspection system.
- Model sequence detection and duration calculation.
- Cooldowns, cancellation rules, public natives and forwards.

[1.1.2]: https://github.com/xSkyLiN3/weapon-inspector-amx/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/xSkyLiN3/weapon-inspector-amx/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/xSkyLiN3/weapon-inspector-amx/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/xSkyLiN3/weapon-inspector-amx/releases/tag/v1.0.0
