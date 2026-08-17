# Changelog

All notable changes are documented here. This project follows [Semantic Versioning](https://semver.org/).

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

[1.1.1]: https://github.com/xSkyLiN3/weapon-inspector-amx/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/xSkyLiN3/weapon-inspector-amx/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/xSkyLiN3/weapon-inspector-amx/releases/tag/v1.0.0
