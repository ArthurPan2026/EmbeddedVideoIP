#!/usr/bin/env python3
"""Write and verify canonical-source/package identity metadata."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Iterable


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_digest(root: Path, files: Iterable[Path]) -> tuple[str, dict[str, str]]:
    entries: dict[str, str] = {}
    for path in sorted(files, key=lambda item: item.relative_to(root).as_posix()):
        if path.is_file() and not path.is_symlink():
            entries[path.relative_to(root).as_posix()] = sha256(path)
    payload = json.dumps(entries, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return hashlib.sha256(payload).hexdigest(), entries


def canonical_files(root: Path) -> list[Path]:
    selected: list[Path] = []
    for base in (root / "ip/video_pipeline_1_0/hdl", root / "ip/video_pipeline_1_0/constraints"):
        if base.is_dir():
            selected.extend(path for path in base.rglob("*") if path.is_file() and not path.is_symlink())
    return selected


def build_metadata(root: Path, package: Path) -> dict:
    canonical_hash, canonical_entries = tree_digest(root, canonical_files(root))
    package_files = [
        path for path in package.rglob("*")
        if path.is_file() and not path.is_symlink() and path.name != "PACKAGE_METADATA.json"
    ]
    package_hash, package_entries = tree_digest(package, package_files)
    return {
        "schema_version": 1,
        "canonical_source": {
            "root": "ip/video_pipeline_1_0",
            "sha256": canonical_hash,
            "files": canonical_entries,
        },
        "package": {
            "root": package.relative_to(root).as_posix(),
            "sha256": package_hash,
            "files": package_entries,
        },
        "tool": "generate_package_metadata.py",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    package = args.package.resolve()
    metadata_path = package / "PACKAGE_METADATA.json"
    expected = build_metadata(root, package)
    if args.verify:
        if not metadata_path.is_file():
            print(f"missing metadata: {metadata_path}")
            return 2
        actual = json.loads(metadata_path.read_text(encoding="utf-8"))
        if actual != expected:
            print("PACKAGE_METADATA_MISMATCH")
            return 2
        print("PACKAGE_METADATA_PASS")
        return 0
    metadata_path.write_text(json.dumps(expected, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(f"PACKAGE_METADATA_WRITTEN {metadata_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
