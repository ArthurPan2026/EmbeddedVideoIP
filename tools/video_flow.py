#!/usr/bin/env python3
"""Reproducible build, simulation, packaging, and synthesis flow for Embedded Video IP."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"
MANIFEST = OUT / "manifest.json"
LOCK = json.loads((ROOT / "dependencies.lock.json").read_text(encoding="utf-8"))
DEFAULT_VIVADO = Path("/tools/AMDDesignTools/2025.2.1/Vivado/bin/vivado")


class FlowError(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_files() -> list[Path]:
    result: list[Path] = []
    for base in (ROOT / "ip", ROOT / "software", ROOT / "platforms",
                 ROOT / "tools", ROOT / "tests", ROOT / "docs"):
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file() and "out" not in path.parts and ".git" not in path.parts:
                result.append(path)
    result.extend([ROOT / "README.md", ROOT / "NOTICE.md", ROOT / "VERSION",
                    ROOT / "dependencies.lock.json"])
    return sorted(set(result))


def input_manifest() -> dict[str, str]:
    return {p.relative_to(ROOT).as_posix(): sha256_file(p) for p in source_files()}


def fingerprint(inputs: dict[str, str], vivado_version: str, action: str,
                part: str | None = None) -> str:
    data = {"schema_version": 1, "action": action, "part": part,
            "vivado_version": vivado_version, "inputs": inputs, "lock": LOCK}
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def read_manifest() -> dict[str, Any]:
    if not MANIFEST.is_file():
        return {"schema_version": 1, "stages": {}}
    try:
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise FlowError(f"Cannot read flow manifest: {exc}") from exc
    if not isinstance(data.get("stages"), dict):
        raise FlowError("Invalid flow manifest: stages must be a mapping.")
    return data


def write_manifest(data: dict[str, Any]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data["schema_version"] = 1
    data["generated_at_utc"] = now()
    temp = MANIFEST.with_suffix(".tmp")
    temp.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    temp.replace(MANIFEST)


def resolve_vivado(text: str | None) -> Path:
    candidate = Path(text or os.environ.get("VIVADO_BIN", DEFAULT_VIVADO)).expanduser()
    if candidate.is_dir():
        candidate = candidate / "vivado"
    if not candidate.is_file():
        raise FlowError(f"Vivado executable not found: {candidate}; pass --vivado or set VIVADO_BIN.")
    return candidate.resolve()


def vivado_version(vivado: Path) -> str:
    proc = subprocess.run([str(vivado), "-version"], text=True, capture_output=True, check=False)
    output = proc.stdout + proc.stderr
    if proc.returncode:
        raise FlowError(f"Vivado -version failed: {output.strip()}")
    match = re.search(r"Vivado v([0-9.]+)", output, re.IGNORECASE)
    if not match:
        raise FlowError(f"Cannot parse Vivado version: {output.strip()}")
    return match.group(1)


def run_stage(name: str, command: list[str], vivado: Path,
              inputs: dict[str, str], part: str | None = None) -> None:
    version = vivado_version(vivado)
    required = str(LOCK["vivado"])
    if version != required:
        raise FlowError(f"Vivado {required} is required by dependencies.lock.json; found {version}.")
    input_hash = fingerprint(inputs, version, name, part)
    log_dir = OUT / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / f"{name}.log"
    proc = subprocess.run(command, cwd=OUT, text=True, capture_output=True, check=False)
    log.write_text(proc.stdout + proc.stderr, encoding="utf-8", errors="replace")
    print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    if proc.returncode:
        raise FlowError(f"Stage {name} failed ({proc.returncode}); see {log}.")

    data = read_manifest()
    output_map = {
        "package": [ROOT / "ip_repo/panfpga/video_pipeline/component.xml"],
        "ip_catalog": [OUT / "ip_catalog_validation/video_ip_validation.srcs/sources_1/bd/video_pipeline_ip_validation/video_pipeline_ip_validation.bd"],
        "synth": [OUT / "synth" / (part or "") / name for name in
                  ("utilization.rpt", "timing_summary.rpt", "video_pipeline.dcp")],
    }
    output_files = []
    for path in output_map.get(name, []):
        if path.is_file():
            output_files.append({"path": path.relative_to(ROOT).as_posix(), "sha256": sha256_file(path)})
    data.setdefault("stages", {})[name] = {
        "status": "succeeded", "completed_at_utc": now(),
        "input_sha256": input_hash, "inputs": inputs,
        "vivado_version": version, "part": part,
        "command": command, "log": log.relative_to(ROOT).as_posix(),
        "outputs": output_files,
    }
    write_manifest(data)
    print(f"VIDEO_FLOW_STAGE_PASS: {name}")


def command_sim(_: argparse.Namespace) -> None:
    script = ROOT / "tools/run_video_tests.sh"
    env = os.environ.copy()
    env["VIVADO_BIN"] = str(resolve_vivado(None).parent)
    proc = subprocess.run([str(script)], cwd=ROOT, env=env, text=True, capture_output=True, check=False)
    print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    if proc.returncode:
        raise FlowError("Video simulation or host driver tests failed.")
    data = read_manifest()
    sim_log = OUT / "tests/video-tests.log"
    sim_log.parent.mkdir(parents=True, exist_ok=True)
    sim_log.write_text(proc.stdout + proc.stderr, encoding="utf-8")
    inputs = input_manifest()
    version = vivado_version(resolve_vivado(None))
    data = read_manifest()
    data.setdefault("stages", {})["sim"] = {
        "status": "succeeded", "completed_at_utc": now(),
        "input_sha256": fingerprint(inputs, version, "sim"),
        "inputs": inputs, "vivado_version": version,
        "log": "out/tests/video-tests.log",
        "outputs": [{"path": sim_log.relative_to(ROOT).as_posix(),
                     "sha256": sha256_file(sim_log)}],
    }
    write_manifest(data)


def command_package(args: argparse.Namespace, validate: bool = False) -> None:
    vivado = resolve_vivado(args.vivado)
    version = vivado_version(vivado)
    inputs = input_manifest()
    package = [str(vivado), "-mode", "batch", "-source", str(ROOT / "tools/package_ip.tcl"),
               "-tclargs", str(ROOT), str(ROOT / "ip_repo")]
    run_stage("package", package, vivado, inputs)
    if validate:
        validation = [str(vivado), "-mode", "batch",
                      "-source", str(ROOT / "tools/validate_ip_catalog.tcl"),
                      "-tclargs", str(ROOT), str(ROOT / "ip_repo")]
        run_stage("ip_catalog", validation, vivado, input_manifest())


def command_synth(args: argparse.Namespace) -> None:
    vivado = resolve_vivado(args.vivado)
    part = args.part
    inputs = input_manifest()
    command = [str(vivado), "-mode", "batch", "-source", str(ROOT / "tools/synth_core.tcl"),
               "-tclargs", str(ROOT), part, str(OUT / "synth" / part)]
    run_stage("synth", command, vivado, inputs, part)


def command_status(_: argparse.Namespace) -> None:
    data = read_manifest()
    stages = data.get("stages", {})
    if not stages:
        print("No completed stages.")
        return
    current = input_manifest()
    for name, record in sorted(stages.items()):
        action = "sim" if name == "sim" else name
        try:
            version = vivado_version(resolve_vivado(None))
            expected = fingerprint(current, version, action, record.get("part"))
        except FlowError:
            expected = ""
        outputs_ok = all(
            (ROOT / item.get("path", "")).is_file() and
            sha256_file(ROOT / item["path"]) == item.get("sha256")
            for item in record.get("outputs", [])
        )
        state = "fresh" if record.get("input_sha256") == expected and record.get("status") == "succeeded" and outputs_ok else "stale"
        print(f"{name}: {state} (Vivado {record.get('vivado_version')}, part {record.get('part')})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("doctor")
    p.add_argument("--vivado")
    p = sub.add_parser("sim")
    p = sub.add_parser("package")
    p.add_argument("--vivado")
    p = sub.add_parser("validate")
    p.add_argument("--vivado")
    p = sub.add_parser("synth")
    p.add_argument("--vivado")
    p.add_argument("--part", default="xc7z020clg400-1")
    p = sub.add_parser("build")
    p.add_argument("--vivado")
    p.add_argument("--part", default="xc7z020clg400-1")
    sub.add_parser("status")
    args = parser.parse_args()

    try:
        if args.command == "doctor":
            vivado = resolve_vivado(args.vivado)
            version = vivado_version(vivado)
            if version != str(LOCK["vivado"]):
                raise FlowError(f"Required Vivado {LOCK['vivado']}; found {version}.")
            print(f"VIDEO_FLOW_DOCTOR_PASS: Vivado {version}")
        elif args.command == "sim":
            command_sim(args)
        elif args.command == "package":
            command_package(args)
        elif args.command == "validate":
            command_package(args, validate=True)
        elif args.command == "synth":
            command_synth(args)
        elif args.command == "build":
            command_sim(args)
            command_package(args, validate=True)
            synth_args = argparse.Namespace(vivado=args.vivado, part=args.part)
            command_synth(synth_args)
        elif args.command == "status":
            command_status(args)
        return 0
    except FlowError as exc:
        print(f"[VIDEO-FLOW] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
