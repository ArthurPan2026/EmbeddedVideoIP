#!/usr/bin/env python3
"""Create versioned, consumer-sized EmbeddedVideoIP release archives."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


PS_FILES = {
    "software/video_out.c": "Video/Lib/Src/video_out.c",
    "software/video_out.h": "Video/Lib/Inc/video_out.h",
    "software/platforms/xilinx_zynq7000/video_out_xilinx.c": "Video/Lib/XilinxZynq7000/video_out_xilinx.c",
    "software/platforms/xilinx_zynq7000/video_out_xilinx.h": "Video/Lib/XilinxZynq7000/video_out_xilinx.h",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_zip(path: Path, files: list[tuple[Path, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(path, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        for source, name in sorted(files, key=lambda item: item[1]):
            if not source.is_file() or source.is_symlink():
                raise FileNotFoundError(source)
            info = ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, source.read_bytes())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ip-repo", type=Path, default=None)
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--vivado-version", required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    dependency_repo = None
    if args.ip_repo is None and "FPGA_FLOW_DEPENDENCIES_JSON" in os.environ:
        outputs = json.loads(os.environ["FPGA_FLOW_DEPENDENCIES_JSON"]).get("package", {}).get("outputs", {})
        matches = [name for name in outputs if name.endswith("/packages/ip_repo")]
        if len(matches) != 1:
            raise ValueError("package dependency must provide exactly one IP repository")
        dependency_repo = root / matches[0]
    ip_repo = (args.ip_repo or dependency_repo or root / "build/fpga-flow/packages/ip_repo").resolve()
    output = (args.output or root / "build/fpga-flow/releases").resolve()
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    ip_root = ip_repo / "panfpga/embedded_video_ip"
    component = ip_root / "component.xml"
    metadata_path = ip_root / "PACKAGE_METADATA.json"
    if not component.is_file() or not metadata_path.is_file():
        raise SystemExit("Run the Vivado package stage before creating release archives.")
    package_metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    try:
        component_root = ET.parse(component).getroot()
    except (ET.ParseError, OSError) as exc:
        raise SystemExit(f"Invalid packaged component.xml: {exc}") from exc
    revision_text = next((element.text for element in component_root.iter()
                          if element.tag.endswith("}coreRevision")), None)
    if revision_text is None or not revision_text.isdigit():
        raise SystemExit("Packaged component.xml has no numeric xilinx:coreRevision")
    core_revision = int(revision_text)
    try:
        source_commit = subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        source_commit = "working-tree"

    ip_files: list[tuple[Path, str]] = []
    ip_prefix = "embedded-video-ip/"
    for base in (ip_root, ip_repo / "if"):
        for source in sorted(base.rglob("*")):
            if source.is_file() and not source.is_symlink():
                ip_files.append((source, ip_prefix + "ip_repo/" + source.relative_to(ip_repo).as_posix()))
    for license_name in ("CERN-OHL-W-2.0.txt",):
        source = root / "LICENSES" / license_name
        if not source.is_file():
            raise SystemExit(f"Required package document is missing: {source}")
        ip_files.append((source, ip_prefix + "LICENSES/" + license_name))
    ip_files.append((root / "docs/ip-package-quickstart.md", ip_prefix + "README.md"))
    ip_files.append((root / "VERSION", ip_prefix + "VERSION"))
    ip_payload = {
        "schema_version": 1,
        "product": "EmbeddedVideoIP Vivado IP",
        "version": version,
        "vlnv": "panfpga.org:video:embedded_video_ip:1.0",
        "core_revision": core_revision,
        "vivado_version": args.vivado_version,
        "source_commit": source_commit,
        "canonical_source_sha256": package_metadata["canonical_source"]["sha256"],
        "package_files": {name: sha256(source.read_bytes()) for source, name in ip_files},
    }
    ip_manifest = json.dumps(ip_payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    ip_manifest_source = output / "release-ip-metadata.json"
    ip_manifest_source.parent.mkdir(parents=True, exist_ok=True)
    ip_manifest_source.write_text(ip_manifest, encoding="utf-8", newline="\n")
    ip_files.append((ip_manifest_source, ip_prefix + "RELEASE-METADATA.json"))
    ip_name = f"EmbeddedVideoIP-{version}-vivado-{args.vivado_version}.zip"
    ip_archive = output / ip_name
    write_zip(ip_archive, ip_files)

    ps_files: list[tuple[Path, str]] = []
    ps_prefix = "embedded-video-ip-ps-zynq7000/"
    for source_rel, package_rel in PS_FILES.items():
        ps_files.append((root / source_rel, ps_prefix + package_rel))
    ps_readme = output / "release-ps-readme.md"
    ps_readme.write_text(
        "# EmbeddedVideoIP Zynq-7000 PS 库\n\n"
        f"版本为 {version}。\n\n"
        "将 Video/Lib 加入 Vitis 应用源码树。"
        "头文件路径加入 Video/Lib/Inc 和 Video/Lib/XilinxZynq7000，"
        "编译 Video/Lib/Src/video_out.c 与 "
        "Video/Lib/XilinxZynq7000/video_out_xilinx.c。\n",
        encoding="utf-8",
        newline="\n",
    )
    ps_files.extend([
        (ps_readme, ps_prefix + "README.md"),
        (root / "VERSION", ps_prefix + "VERSION"),
        (root / "LICENSES/Apache-2.0.txt", ps_prefix + "LICENSES/Apache-2.0.txt"),
    ])
    ps_payload = {
        "schema_version": 1,
        "product": "EmbeddedVideoIP Zynq-7000 PS Library",
        "version": version,
        "source_commit": source_commit,
        "package_files": {name: sha256(source.read_bytes()) for source, name in ps_files},
    }
    ps_manifest = output / "release-ps-metadata.json"
    ps_manifest.write_text(
        json.dumps(ps_payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    ps_files.append((ps_manifest, ps_prefix + "RELEASE-METADATA.json"))
    ps_name = f"EmbeddedVideoIP-PS-Zynq7000-{version}.zip"
    ps_archive = output / ps_name
    write_zip(ps_archive, ps_files)

    sums = [f"{sha256(archive.read_bytes())}  {archive.name}" for archive in (ip_archive, ps_archive)]
    (output / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="ascii")
    print(f"IP_PACKAGE={ip_archive}")
    print(f"PS_PACKAGE={ps_archive}")
    print(f"SHA256SUMS={output / 'SHA256SUMS'}")
    print("EMBEDDED_VIDEO_IP_RELEASE_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
