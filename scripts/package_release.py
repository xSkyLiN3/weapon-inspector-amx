#!/usr/bin/env python3
"""Create the deterministic Weapon Inspector release archive."""

# SPDX-FileCopyrightText: 2026 Cristobal Vergara
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import argparse
import os
from pathlib import Path
import zipfile


FIXED_ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
PROJECT_FILES = (
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "THIRD_PARTY_NOTICES.md",
    "VERSION",
    "addons/amxmodx/configs/inspect_list.ini",
    "addons/amxmodx/configs/weapon_inspector.cfg",
    "addons/amxmodx/configs/weapon_inspector_models.ini",
    "addons/amxmodx/scripting/include/weapon_inspector.inc",
    "addons/amxmodx/scripting/weapon_inspector.sma",
    "docs/validation.md",
    "scripts/build.ps1",
    "scripts/package_release.py",
)
PLUGIN_ARCHIVE_PATH = "addons/amxmodx/plugins/weapon_inspector.amxx"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plugin",
        required=True,
        type=Path,
        help="Path to the compiled weapon_inspector.amxx file.",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="Destination ZIP path.",
    )
    return parser.parse_args()


def zip_entry(name: str) -> zipfile.ZipInfo:
    entry = zipfile.ZipInfo(name, FIXED_ZIP_TIMESTAMP)
    entry.create_system = 3
    entry.compress_type = zipfile.ZIP_STORED
    entry.external_attr = (0o100644 & 0xFFFF) << 16
    return entry


def main() -> int:
    args = parse_args()
    repository_root = Path(__file__).resolve().parent.parent
    plugin = args.plugin.resolve(strict=True)
    output = args.output.resolve()

    if not plugin.is_file() or plugin.stat().st_size == 0:
        raise ValueError(f"Compiled plugin is missing or empty: {plugin}")

    sources = {archive_path: repository_root / archive_path for archive_path in PROJECT_FILES}
    sources[PLUGIN_ARCHIVE_PATH] = plugin

    missing = [str(path) for path in sources.values() if not path.is_file()]
    if missing:
        raise FileNotFoundError("Release input missing: " + ", ".join(missing))

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")

    try:
        with zipfile.ZipFile(temporary, "w", allowZip64=False) as archive:
            for archive_path in sorted(sources):
                archive.writestr(zip_entry(archive_path), sources[archive_path].read_bytes())
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)

    print(f"Created {output} ({output.stat().st_size} bytes)")
    for archive_path in sorted(sources):
        print(archive_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
