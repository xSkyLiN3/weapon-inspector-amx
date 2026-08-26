# Validation matrix

This document separates automated evidence from server and client behavior. A successful compilation is not presented as proof of gameplay behavior.

Status values:

- **Passed** — reproduced and recorded for the current commit.
- **Pending** — required before tagging v1.1.2.
- **Not applicable** — intentionally outside the plugin's supported scope.

## Automated checks

| Check | Status | Evidence |
|---|---|---|
| AMX Mod X 1.10.0.5478 compilation | Pending | GitHub Actions run for the pull request |
| Two clean compilations are byte-identical | Pending | GitHub Actions comparison |
| Two deterministic release packages are byte-identical | Pending | GitHub Actions comparison |
| Release manifest contains only documented project files | Pending | Package listing in GitHub Actions |
| Source diff has no whitespace errors | Pending | Local verification before push |

## Dedicated-server smoke checks

| Scenario | Expected result | Status |
|---|---|---|
| Load with required AMX Mod X modules | Plugin reports v1.1.2 without load errors | Pending |
| Default viewmodel without inspect sequence | Model is cached as unsupported; weapon behavior is unchanged | Pending |
| Valid custom viewmodel with `inspect` or `lookat` label | Sequence and duration are detected once and cached | Pending |
| Invalid or truncated model | File is rejected without a server error | Pending |
| `wi_enabled 0` | Hooks do not alter input or weapon timing; an active inspect is cancelled | Pending |
| Invalid `wi_impulse_mode` | Unrelated impulses are not intercepted | Pending |
| `wi_reload_config` | Model and keyword caches rebuild without errors | Pending |
| Public API forced inspect during a busy window | Request is rejected until the busy window ends | Pending |

## Client-visible checks

| Scenario | Expected result | Status |
|---|---|---|
| Manual and configured impulse activation | Inspect starts only for an allowed, supported model | Pending |
| AK-47-style single inspect sequence | Animation plays and returns to a normal idle | Pending |
| M4A1/USP silenced and unsilenced variants | A state-appropriate inspect sequence is preferred | Pending |
| Primary attack, reload or weapon switch during inspect | Inspect is cancelled and gameplay action continues normally | Pending |
| Secondary attack / zoom | Inspect is blocked or cancelled without forcing animation sequence 0 | Pending |
| Death, disconnect and plugin disable | Player state is cleared without visible stale animation | Pending |
| Cooldown and anti-spam limits | Repeated activation is rejected without blocking normal input | Pending |

Custom test models are used only in a private licensed Counter-Strike installation and are not distributed by this repository.

## Portfolio promotion gate

Weapon Inspector should remain a historical secondary project until the dedicated-server matrix passes. It can be presented as a validated technical demo after the critical client-visible paths pass and a short, unedited demonstration records supported-model inspect, unsupported-model no-interference and attack/reload/zoom cancellation.
