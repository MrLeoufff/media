#!/usr/bin/env python3
"""Génère catalog/index.yml depuis modules/*/module.yml."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def parse_simple_yaml(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#") or raw.lstrip().startswith("- "):
            continue
        if raw.startswith(" ") or raw.startswith("\t"):
            continue
        match = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", raw.strip())
        if not match:
            continue
        key, value = match.groups()
        data[key] = value.strip().strip('"').strip("'")
    return data


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    modules_dir = root / "modules"
    out_file = root / "catalog" / "index.yml"
    out_file.parent.mkdir(parents=True, exist_ok=True)

    entries = []
    for module_yml in sorted(modules_dir.glob("*/module.yml")):
        meta = parse_simple_yaml(module_yml)
        name = meta.get("name") or module_yml.parent.name
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name):
            continue
        entries.append(
            {
                "name": name,
                "displayName": meta.get("displayName", name),
                "version": meta.get("version", "0.0.0"),
                "category": meta.get("category", "-"),
                "description": meta.get("description", ""),
            }
        )

    lines = ["apiVersion: mediastack/catalog/v1", "modules:"]
    for entry in entries:
        desc = entry["description"].replace('"', '\\"')
        lines.extend(
            [
                f"  - name: {entry['name']}",
                f"    displayName: {entry['displayName']}",
                f"    version: \"{entry['version']}\"",
                f"    category: {entry['category']}",
                f"    description: \"{desc}\"",
                "    source: local",
                "",
            ]
        )

    out_file.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    print(f"Wrote {len(entries)} modules -> {out_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
