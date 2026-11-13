#!/usr/bin/env python3
"""Install the paired EmbeddedVideoIP PS library into a Vitis application source tree."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys

BEGIN = "# BEGIN EmbeddedVideoIP PS library"
END = "# END EmbeddedVideoIP PS library"


def _mapping(platform: str) -> dict[Path, Path]:
    if platform != "zynq7000":
        raise ValueError(f"Unsupported PS platform {platform!r}; V1 provides zynq7000 only.")
    return {
        Path("software/video_out.c"): Path("Video/Lib/Src/video_out.c"),
        Path("software/video_out.h"): Path("Video/Lib/Inc/video_out.h"),
        Path("software/platforms/xilinx_zynq7000/video_out_xilinx.c"): Path("Video/Lib/XilinxZynq7000/video_out_xilinx.c"),
        Path("software/platforms/xilinx_zynq7000/video_out_xilinx.h"): Path("Video/Lib/XilinxZynq7000/video_out_xilinx.h"),
    }


def install(repo_root: Path, app_source: Path, platform: str = "zynq7000") -> list[Path]:
    repo_root = repo_root.expanduser().resolve()
    app_source = app_source.expanduser().resolve()
    config = app_source / "UserConfig.cmake"
    if not app_source.is_dir():
        raise ValueError(f"Vitis application source directory does not exist: {app_source}")
    if not config.is_file():
        raise ValueError(f"Vitis application config is missing: {config}")

    mapping = _mapping(platform)
    prepared: list[tuple[Path, Path, bytes]] = []
    for source_rel, target_rel in mapping.items():
        source = repo_root / source_rel
        target = app_source / target_rel
        if not source.is_file():
            raise ValueError(f"Required PS library file is missing: {source}")
        data = source.read_bytes()
        if target.exists() and target.read_bytes() != data:
            raise ValueError(f"PS library install collision; existing file differs: {target}")
        prepared.append((source, target, data))

    config_text = config.read_text(encoding="utf-8")
    begin_count = config_text.count(BEGIN)
    end_count = config_text.count(END)
    if begin_count != end_count or begin_count > 1:
        raise ValueError(f"Vitis config has an incomplete or duplicated EmbeddedVideoIP block: {config}")
    existing = config_text
    if begin_count:
        marker_start = config_text.index(BEGIN)
        line_start = config_text.rfind("\n", 0, marker_start) + 1
        marker_end = config_text.index(END, marker_start) + len(END)
        line_end = config_text.find("\n", marker_end)
        finish = len(config_text) if line_end < 0 else line_end + 1
        existing = config_text[:line_start] + config_text[finish:]

    include_paths = [
        "${CMAKE_CURRENT_SOURCE_DIR}/Video/Lib/Inc",
        "${CMAKE_CURRENT_SOURCE_DIR}/Video/Lib/XilinxZynq7000",
    ]
    source_paths = [
        "Video/Lib/Src/video_out.c",
        "Video/Lib/XilinxZynq7000/video_out_xilinx.c",
    ]
    required_entries = include_paths + source_paths
    present = [entry for entry in required_entries if entry in existing]
    if present and len(present) != len(required_entries):
        raise ValueError("UserConfig.cmake contains only part of the PS library configuration; resolve it manually before install.")

    version = (repo_root / "VERSION").read_text(encoding="utf-8").strip()
    if not version:
        raise ValueError("EmbeddedVideoIP VERSION is empty.")
    config_new = existing
    if not present:
        newline = "\r\n" if "\r\n" in config_text else "\n"
        block_lines = [
            BEGIN,
            f"# version: {version}; paired PS library for the PL IP in ip_repo/.",
            "list(APPEND USER_INCLUDE_DIRECTORIES",
            f'    "{include_paths[0]}"',
            f'    "{include_paths[1]}"',
            ")",
            "list(APPEND USER_COMPILE_SOURCES",
            f'    "{source_paths[0]}"',
            f'    "{source_paths[1]}"',
            ")",
            END,
        ]
        if config_new and not config_new.endswith(("\n", "\r")):
            config_new += newline
        config_new += newline.join(block_lines) + newline

    for _, target, data in prepared:
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            temporary = target.with_name(target.name + ".tmp")
            temporary.write_bytes(data)
            temporary.replace(target)
    if config_new != config_text:
        temporary_config = config.with_name(config.name + ".tmp")
        temporary_config.write_text(config_new, encoding="utf-8", newline="")
        temporary_config.replace(config)
    return [target for _, target, _ in prepared] + [config]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-src", required=True, type=Path,
                        help="Vitis application src directory containing UserConfig.cmake")
    parser.add_argument("--platform", default="zynq7000", choices=("zynq7000",),
                        help="PS platform adapter to install; V1 supports Zynq-7000")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1],
                        help="EmbeddedVideoIP repository root")
    args = parser.parse_args()
    try:
        outputs = install(args.repo, args.app_src, args.platform)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[VIDEO-PS-INSTALL] {exc}", file=sys.stderr)
        return 2
    for output in outputs:
        print(f"VIDEO_PS_LIBRARY_FILE: {output}")
    print(f"VIDEO_PS_LIBRARY_INSTALL_PASS: version={(args.repo / 'VERSION').read_text(encoding='utf-8').strip()} platform={args.platform}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
