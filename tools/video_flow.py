#!/usr/bin/env python3
"""Reproducible build, simulation, packaging, and synthesis flow for Embedded Video IP."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping

ROOT = Path(__file__).resolve().parents[1]
try:
    from tools.rtl_manifest import manifest_output_paths, manifest_source_paths
except ModuleNotFoundError:  # direct script/import compatibility
    from rtl_manifest import manifest_output_paths, manifest_source_paths
def output_root(root: Path = ROOT) -> Path:
    return Path(os.environ.get("FPGA_FLOW_OUTPUT_DIR", str(root / "build/fpga-flow")))


OUT = output_root()
MANIFEST = OUT / "manifest.json"
MANIFEST_SCHEMA_VERSION = 3
INPUT_PARTITION_VERSION = 4
PROJECT_CONFIG = tomllib.loads((ROOT / "fpga-project.toml").read_text(encoding="utf-8"))
VIVADO_VERSION = str(PROJECT_CONFIG["tools"]["vivado_version"])
PRODUCT_VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
DEFAULT_VIVADO = Path("vivado")
PACKAGE_REPO = OUT / "packages/ip_repo"

PACKAGE_HDL_FILES = (
    "axis_video_nn_scaler.sv",
    "axis_video_nn_scaler_prefetch.sv",
    "axis_rgb888.sv",
    "axis_video_mux3.sv",
    "video_bram_rgb565_reader.sv",
    "axi_lite_video_regs.sv",
    "video_pipeline_v1_0.sv",
    "video_pipeline_v1_0_wrapper.v",
)
SYNTH_HDL_FILES = (
    "axis_video_nn_scaler.sv",
    "axis_video_nn_scaler_prefetch.sv",
    "axis_rgb888.sv",
    "axis_video_mux3.sv",
    "video_bram_rgb565_reader.sv",
    "axi_lite_video_regs.sv",
    "video_pipeline_v1_0.sv",
)
CONTRACT_FILES = ("contracts/video_contract.json", "contracts/pcm_contract.json")
SIM_SOFTWARE_FILES = (
    "video_out.c",
    "video_out.h",
    "platforms/xilinx_zynq7000/video_out_xilinx.c",
    "platforms/xilinx_zynq7000/video_out_xilinx.h",
)
CATALOG_BD_REL = Path(
    "build/fpga-flow/ip_catalog_validation_feature_profile/embedded_video_ip_catalog_validation.srcs/sources_1/bd/"
    "embedded_video_ip_catalog_validation/embedded_video_ip_catalog_validation.bd"
)
SIM_LOG_REL = Path("build/fpga-flow/tests/video-tests.log")
SIM_MANIFEST_REL = Path("fpga-project.toml")
SYNTH_REPORT_NAMES = ("utilization.rpt", "timing_summary.rpt", "qor.json")
_VDMA_SCALER_PROFILE = {
    "MAX_INPUT_WIDTH": 640,
    "MAX_INPUT_HEIGHT": 480,
    "OUTPUT_WIDTH": 640,
    "OUTPUT_HEIGHT": 480,
    "ENABLE_BRAM_SOURCE": 0,
    "ENABLE_HLS_SOURCE": 0,
    "ENABLE_VDMA_SOURCE": 1,
    "SOURCE_SELECT_MODE": 1,
    "FIXED_SOURCE": 2,
    "FORMAT_SELECT_MODE": 1,
    "FIXED_FORMAT": 2,
    "MAX_SCALER_INPUT_WIDTH": 640,
    "MAX_SCALER_INPUT_HEIGHT": 480,
    "ENABLE_SCALER": 1,
}
_COMPOSITE_VIDEO_PROFILE = {
    "MAX_INPUT_WIDTH": 640,
    "MAX_INPUT_HEIGHT": 480,
    "ENABLE_BRAM_SOURCE": 0,
    "ENABLE_HLS_SOURCE": 0,
    "ENABLE_VDMA_SOURCE": 1,
    "SOURCE_SELECT_MODE": 1,
    "FIXED_SOURCE": 2,
    "FORMAT_SELECT_MODE": 1,
    "FIXED_FORMAT": 2,
    "MAX_SCALER_INPUT_WIDTH": 240,
    "MAX_SCALER_INPUT_HEIGHT": 160,
    "ENABLE_SCALER": 1,
    "LINE_BUFFER_IMPLEMENTATION": 0,
}
SYNTH_PROFILE_GENERICS: dict[str, dict[str, int]] = {
    "generic": {},
    "vdma_scaler_lutram": {
        **_VDMA_SCALER_PROFILE,
        "LINE_BUFFER_IMPLEMENTATION": 0,
    },
    "vdma_scaler_bram": {
        **_VDMA_SCALER_PROFILE,
        "LINE_BUFFER_IMPLEMENTATION": 1,
    },
    "passthrough": {
        "MAX_INPUT_WIDTH": 640,
        "MAX_INPUT_HEIGHT": 480,
        "OUTPUT_WIDTH": 640,
        "OUTPUT_HEIGHT": 480,
        "ENABLE_BRAM_SOURCE": 0,
        "ENABLE_HLS_SOURCE": 0,
        "ENABLE_VDMA_SOURCE": 1,
        "SOURCE_SELECT_MODE": 1,
        "FIXED_SOURCE": 2,
        "FORMAT_SELECT_MODE": 1,
        "FIXED_FORMAT": 2,
        "ENABLE_SCALER": 0,
    },
    "composite_audio_off": {**_COMPOSITE_VIDEO_PROFILE, "ENABLE_HDMI_AUDIO": 0},
    "composite_audio_on": {**_COMPOSITE_VIDEO_PROFILE, "ENABLE_HDMI_AUDIO": 1},
}
COMPOSITE_SYNTH_PROFILES = {"composite_audio_off", "composite_audio_on"}
IGNORED_DIRS = {".git", ".Xil", "__pycache__", ".cache", "build"}
IGNORED_SUFFIXES = {".pyc", ".pyo"}


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


def sha256_json(value: object) -> str:
    data = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def _tree_files(base: Path) -> list[Path]:
    """Return deterministic regular files below a source/package directory."""
    if base.is_file() and not base.is_symlink():
        return [base]
    if not base.is_dir():
        return []
    result: list[Path] = []
    for current, directories, names in os.walk(base, followlinks=False):
        current_path = Path(current)
        directories[:] = sorted(
            name for name in directories
            if name not in IGNORED_DIRS and not (current_path / name).is_symlink()
        )
        for name in sorted(names):
            path = current_path / name
            if (path.is_file() and not path.is_symlink()
                    and path.suffix.lower() not in IGNORED_SUFFIXES):
                result.append(path)
    return sorted(result, key=lambda path: path.as_posix())


def _require_files(paths: Iterable[Path], stage: str) -> list[Path]:
    result = sorted(set(paths), key=lambda path: path.as_posix())
    missing = [path for path in result if not path.is_file() or path.is_symlink()]
    if missing:
        shown = ", ".join(str(path) for path in missing[:5])
        raise FlowError(f"Missing {stage} input(s): {shown}")
    return result


def stage_input_paths(stage: str, root: Path = ROOT,
                      profile: str | None = None) -> list[Path]:
    """选择会影响当前构建阶段的文件。"""
    hdl_dir = root / "ip/video_pipeline_1_0/hdl"
    common = [root / "tools/video_flow.py", root / "fpga-project.toml"]

    if stage == "package":
        package_hdl = [
            path for path in _tree_files(hdl_dir)
            if path.suffix.lower() in {".sv", ".v"}
        ]
        paths = [
            *common,
            root / "tools/package_all.tcl",
            root / "tools/package_ip.tcl",
            root / "tools/package_composite_ip.tcl",
            root / "tools/generate_package_metadata.py",
            root / "ip/video_pipeline_1_0/constraints/embedded_video_ip_clocks.xdc",
            root / "VERSION",
            *(root / name for name in CONTRACT_FILES),
            *package_hdl,
            *_tree_files(root / "ip_repo/if"),
        ]
    elif stage == "ip_catalog":
        package_roots = [
            output_root(root) / "packages/ip_repo/panfpga/video_pipeline",
            output_root(root) / "packages/ip_repo/panfpga/embedded_video_ip",
        ]
        package_files = []
        for package_root in package_roots:
            if not (package_root / "component.xml").is_file():
                raise FlowError(f"Packaged IP is missing; run the package stage first: {package_root}")
            package_files.extend(_tree_files(package_root))
        package_files.extend(_tree_files(root / "ip_repo/if"))
        paths = [*common, root / "tools/validate_ip_catalog.tcl", *package_files]
    elif stage == "sim":
        bench_sources = manifest_source_paths(root)
        paths = [
            *common,
            *_tree_files(root / "tools"),
            *_tree_files(root / "tests/host"),
            root / SIM_MANIFEST_REL,
            root / "VERSION",
            *(root / name for name in CONTRACT_FILES),
            *bench_sources,
            hdl_dir / "embedded_video_ip_top.v",
            hdl_dir / "embedded_video_ip_timing_gen_wrapper.v",
            *(root / "software" / name for name in SIM_SOFTWARE_FILES),
        ]
    elif stage == "synth":
        paths = [
            *common,
            root / "tools/synth_core.tcl",
            root / "ip/video_pipeline_1_0/constraints/embedded_video_ip_clocks.xdc",
            *(hdl_dir / name for name in SYNTH_HDL_FILES),
        ]
        if profile in COMPOSITE_SYNTH_PROFILES:
            package_outputs = stage_output_paths("package", root)
            paths.extend([
                root / "tools/synth_composite.tcl",
                *package_outputs,
            ])
    else:
        raise FlowError(f"Unknown stage input partition: {stage!r}")

    return _require_files(paths, stage)


def input_manifest(stage: str, root: Path = ROOT,
                   profile: str | None = None) -> dict[str, str]:
    """计算当前阶段源码的 SHA-256，排除无关文件。"""
    paths = stage_input_paths(stage, root, profile)
    return {
        path.relative_to(root).as_posix(): sha256_file(path)
        for path in paths
    }


def synth_profile_generics(profile: str) -> dict[str, int]:
    try:
        return dict(SYNTH_PROFILE_GENERICS[profile])
    except KeyError as exc:
        raise FlowError(f"Unknown synthesis profile: {profile!r}") from exc


def synth_profile_output_dir(part: str, profile: str, root: Path = ROOT) -> Path:
    synth_profile_generics(profile)
    base = output_root(root) / "synth" / part
    return base if profile == "generic" else base / "profiles" / profile


def synth_checkpoint_name(profile: str) -> str:
    return "embedded_video_ip.dcp" if profile in COMPOSITE_SYNTH_PROFILES else "video_pipeline.dcp"


def synth_output_names(profile: str) -> tuple[str, ...]:
    if profile in COMPOSITE_SYNTH_PROFILES:
        return (
            "utilization.rpt", "timing_summary.rpt", "clock_interaction.rpt",
            "ignored_timing_exceptions.rpt", "methodology.rpt", "cdc.rpt",
            "bus_skew.rpt", synth_checkpoint_name(profile), "qor.json",
        )
    return (*SYNTH_REPORT_NAMES[:2], synth_checkpoint_name(profile), SYNTH_REPORT_NAMES[2])


def stage_manifest_key(name: str, profile: str | None = None) -> str:
    if name == "synth":
        return f"synth:{profile or 'generic'}"
    return name


def fingerprint(inputs: dict[str, str], vivado_version: str, action: str,
                part: str | None = None, profile: str | None = None) -> str:
    data = {
        "manifest_schema_version": MANIFEST_SCHEMA_VERSION,
        "input_partition_version": INPUT_PARTITION_VERSION,
        "product_version": PRODUCT_VERSION,
        "action": action,
        "part": part,
        "profile": profile,
        "vivado_version": vivado_version,
        "vivado_required": VIVADO_VERSION,
        "python_version": sys.version.split()[0] if action == "sim" else None,
        "inputs": inputs,
    }
    return sha256_json(data)


def read_manifest(root: Path = ROOT) -> dict[str, Any]:
    manifest = output_root(root) / "manifest.json"
    if not manifest.is_file():
        return {"schema_version": MANIFEST_SCHEMA_VERSION, "stages": {}}
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise FlowError(f"Cannot read flow manifest: {exc}") from exc
    if not isinstance(data, dict) or not isinstance(data.get("stages"), dict):
        raise FlowError("Invalid flow manifest: stages must be a mapping.")
    return data


def write_manifest(data: dict[str, Any], root: Path = ROOT) -> None:
    manifest = output_root(root) / "manifest.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    data["schema_version"] = MANIFEST_SCHEMA_VERSION
    data["product_version"] = PRODUCT_VERSION
    data["generated_at_utc"] = now()
    temp = manifest.with_suffix(".tmp")
    temp.write_text(json.dumps(data, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    temp.replace(manifest)


def resolve_vivado(text: str | None) -> Path:
    value = text or os.environ.get("VIVADO_BIN", str(DEFAULT_VIVADO))
    candidate = Path(value).expanduser()
    if candidate.is_dir():
        candidate = candidate / "vivado"
    if not candidate.is_absolute():
        resolved = shutil.which(value)
        if resolved:
            candidate = Path(resolved)
    if not candidate.is_file():
        raise FlowError(f"Vivado executable not found: {value}; pass --vivado or set VIVADO_BIN.")
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


def stage_output_paths(name: str, root: Path = ROOT, part: str | None = None,
                       profile: str | None = None) -> list[Path]:
    if name == "package":
        core_root = output_root(root) / "packages/ip_repo/panfpga/video_pipeline"
        composite_root = output_root(root) / "packages/ip_repo/panfpga/embedded_video_ip"
        paths = [*_tree_files(core_root), *_tree_files(composite_root), *_tree_files(root / "ip_repo/if")]
        if not (core_root / "component.xml").is_file():
            raise FlowError(f"Internal video IP is missing: {core_root / 'component.xml'}")
        if not (composite_root / "component.xml").is_file():
            raise FlowError(f"Composite IP is missing: {composite_root / 'component.xml'}")
        return paths
    if name == "ip_catalog":
        return [output_root(root) / CATALOG_BD_REL.relative_to("build/fpga-flow")]
    if name == "sim":
        paths = [output_root(root) / "tests/video-tests.log"]
        paths.extend(output_root(root) / path.relative_to(root / "build/fpga-flow")
                     for path in manifest_output_paths(root))
        return paths
    if name == "synth":
        if not part:
            raise FlowError("Synthesis output validation requires a part.")
        selected_profile = profile or "generic"
        output_dir = synth_profile_output_dir(part, selected_profile, root)
        return [output_dir / output for output in synth_output_names(selected_profile)]
    raise FlowError(f"Unknown stage output partition: {name!r}")


def output_manifest(name: str, root: Path = ROOT, part: str | None = None,
                    profile: str | None = None) -> list[dict[str, str]]:
    paths = stage_output_paths(name, root, part, profile)
    missing = [path for path in paths if not path.is_file() or path.is_symlink()]
    if missing:
        shown = ", ".join(str(path) for path in missing)
        raise FlowError(f"Stage {name} did not produce required output(s): {shown}")
    return [
        {"path": path.relative_to(root).as_posix(), "sha256": sha256_file(path)}
        for path in sorted(paths, key=lambda path: path.as_posix())
    ]


def output_fingerprint(outputs: list[dict[str, str]]) -> str:
    return sha256_json(outputs)


def _parse_utilization_count(report: str, site: str, default: int | None = None) -> int:
    for line in report.splitlines():
        if not line.lstrip().startswith("|"):
            continue
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if len(columns) >= 2 and columns[0] == site:
            try:
                return int(columns[1].replace(",", ""))
            except ValueError as exc:
                raise FlowError(f"Invalid utilization count for {site}: {columns[1]!r}") from exc
    if default is not None:
        return default
    raise FlowError(f"Utilization report is missing the {site!r} row.")


def parse_synth_reports(utilization_path: Path, timing_path: Path) -> dict[str, Any]:
    """Extract resource and setup/hold metrics from Vivado OOC reports."""
    try:
        utilization = utilization_path.read_text(encoding="utf-8", errors="replace")
        timing = timing_path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise FlowError(f"Cannot read synthesis report: {exc}") from exc

    resources = {
        "lut": _parse_utilization_count(utilization, "Slice LUTs*"),
        "ff": _parse_utilization_count(utilization, "Slice Registers"),
        "lutram": _parse_utilization_count(utilization, "LUT as Distributed RAM", default=0),
        "bram_tiles": _parse_utilization_count(utilization, "Block RAM Tile"),
        "dsp": _parse_utilization_count(utilization, "DSPs"),
        "control_sets": _parse_utilization_count(utilization, "Unique Control Sets"),
    }

    summary_pos = timing.find("Design Timing Summary")
    if summary_pos < 0:
        raise FlowError("Timing report is missing the Design Timing Summary section.")
    number = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"
    summary_text = timing[summary_pos:]
    summary_with_hold_pattern = re.compile(
        rf"(?m)^\s*({number})\s+({number})\s+\d+\s+\d+\s+"
        rf"({number})\s+({number})\s+\d+\s+\d+\s+"
        rf"({number})\s+({number})\s+\d+\s+\d+\s*$"
    )
    summary_without_hold_pattern = re.compile(
        rf"(?m)^\s*({number})\s+({number})\s+\d+\s+\d+\s+"
        rf"({number})\s+({number})\s+\d+\s+\d+\s*$"
    )
    summary_match = summary_with_hold_pattern.search(summary_text)
    summary_has_hold = summary_match is not None
    if summary_match is None:
        summary_match = summary_without_hold_pattern.search(summary_text)
    if summary_match is None:
        raise FlowError("Timing report has no parseable WNS/TNS summary row.")

    def timing_value(value: str) -> float | None:
        return None if value == "NA" else float(value)

    detail_pattern = re.compile(
        rf"(?m)^\s*(Setup|Hold)\s*:\s*(NA|\d+)\s+Failing Endpoints,\s*"
        rf"Worst Slack\s+(NA|{number})\s*(?:ns)?\s*,\s*"
        rf"Total Violation\s+(NA|{number})\s*(?:ns)?"
    )
    details: dict[str, tuple[int | None, float | None, float | None]] = {}
    for match in detail_pattern.finditer(timing):
        failing = None if match.group(2) == "NA" else int(match.group(2))
        details[match.group(1).lower()] = (
            failing, timing_value(match.group(3)), timing_value(match.group(4))
        )
    setup = details.get("setup")
    hold = details.get("hold")
    values = summary_match.groups()
    wns, tns = float(values[0]), float(values[1])
    whs = float(values[2]) if summary_has_hold else (hold[1] if hold else None)
    ths = float(values[3]) if summary_has_hold else (hold[2] if hold else None)
    setup_pass = wns >= 0.0 and abs(tns) < 0.0005 and (setup is None or setup[0] == 0)
    hold_pass = None if whs is None or ths is None else (
        whs >= 0.0 and abs(ths) < 0.0005 and (hold is None or hold[0] == 0)
    )
    return {
        "resources": resources,
        "timing": {
            "wns_ns": wns,
            "tns_ns": tns,
            "whs_ns": whs,
            "ths_ns": ths,
            "setup_failing_endpoints": setup[0] if setup else None,
            "hold_failing_endpoints": hold[0] if hold else None,
            "setup_pass": setup_pass,
            "hold_pass": hold_pass,
            "all_timing_pass": setup_pass and hold_pass is True,
        },
    }


def write_synth_qor(root: Path, part: str, profile: str, tool_version: str,
                    input_hash: str) -> dict[str, Any]:
    output_dir = synth_profile_output_dir(part, profile, root)
    metrics = parse_synth_reports(
        output_dir / "utilization.rpt", output_dir / "timing_summary.rpt"
    )
    metrics.update({
        "schema_version": 1,
        "product_version": PRODUCT_VERSION,
        "stage": "synth",
        "profile": profile,
        "part": part,
        "vivado_version": tool_version,
        "timing_scope": (
            "pre-route OOC synthesis; compare profiles only, not board signoff"
            if profile in COMPOSITE_SYNTH_PROFILES else "OOC core synthesis"
        ),
        "timing_signoff": False if profile in COMPOSITE_SYNTH_PROFILES else None,
        "input_sha256": input_hash,
        "report_sha256": {
            "utilization.rpt": sha256_file(output_dir / "utilization.rpt"),
            "timing_summary.rpt": sha256_file(output_dir / "timing_summary.rpt"),
            **({
                "clock_interaction.rpt": sha256_file(output_dir / "clock_interaction.rpt"),
                "ignored_timing_exceptions.rpt": sha256_file(output_dir / "ignored_timing_exceptions.rpt"),
                "methodology.rpt": sha256_file(output_dir / "methodology.rpt"),
                "cdc.rpt": sha256_file(output_dir / "cdc.rpt"),
                "bus_skew.rpt": sha256_file(output_dir / "bus_skew.rpt"),
            } if profile in COMPOSITE_SYNTH_PROFILES else {}),
            synth_checkpoint_name(profile): sha256_file(output_dir / synth_checkpoint_name(profile)),
        },
    })
    (output_dir / "qor.json").write_text(
        json.dumps(metrics, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    return metrics


def outputs_match(name: str, record: Mapping[str, Any], root: Path = ROOT,
                  part: str | None = None, profile: str | None = None) -> bool:
    recorded = record.get("outputs")
    recorded_fingerprint = record.get("output_sha256")
    if not isinstance(recorded, list) or not recorded or not isinstance(recorded_fingerprint, str):
        return False
    try:
        current = output_manifest(name, root, part, profile)
    except (FlowError, OSError, ValueError):
        return False
    return current == recorded and output_fingerprint(current) == recorded_fingerprint


def stage_cache_valid(name: str, record: Mapping[str, Any], input_hash: str,
                      vivado_version_text: str, root: Path = ROOT,
                      part: str | None = None, profile: str | None = None) -> bool:
    return (
        record.get("status") == "succeeded"
        and record.get("input_partition_version") == INPUT_PARTITION_VERSION
        and record.get("input_sha256") == input_hash
        and record.get("vivado_version") == vivado_version_text
        and (name != "sim" or record.get("python_version") == sys.version.split()[0])
        and record.get("part") == part
        and record.get("profile") == profile
        and outputs_match(name, record, root, part, profile)
    )


def run_stage(name: str, command: list[str], vivado: Path,
              inputs: dict[str, str], part: str | None = None, *,
              root: Path = ROOT, tool_version: str | None = None,
              profile: str | None = None,
              runner: Callable[..., Any] | None = None,
              env: dict[str, str] | None = None,
              success_marker: str | None = None) -> bool:
    """Run a stage only when its input fingerprint or required output hashes are stale.

    Returns True when the stage command ran, False on a verified cache hit.
    """
    if name == "synth":
        profile = profile or "generic"
        synth_profile_generics(profile)
    elif profile is not None:
        raise FlowError(f"Profiles are only supported for synthesis, not {name!r}.")

    stage_key = stage_manifest_key(name, profile)
    version = tool_version if tool_version is not None else vivado_version(vivado)
    required = VIVADO_VERSION
    if version != required:
        raise FlowError(f"Vivado {required} is required by fpga-project.toml; found {version}.")
    input_hash = fingerprint(inputs, version, name, part, profile)
    managed = "FPGA_FLOW_RUN_DIR" in os.environ
    data = {"stages": {}} if managed else read_manifest(root)
    stages = data.setdefault("stages", {})
    if not isinstance(stages, dict):
        stages = {}
        data["stages"] = stages

    previous = stages.get(stage_key)
    if isinstance(previous, dict) and stage_cache_valid(
            name, previous, input_hash, version, root, part, profile):
        print(f"VIDEO_FLOW_CACHE_HIT: {stage_key}")
        return False

    out_root = output_root(root)
    log_dir = out_root / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_name = name if profile is None else f"{name}-{profile}"
    log = log_dir / f"{log_name}.log"
    process = (runner or subprocess.run)(
        command, cwd=out_root, text=True, capture_output=True, check=False, env=env
    )
    stdout = process.stdout or ""
    stderr = process.stderr or ""
    output = stdout + stderr
    log.write_text(output, encoding="utf-8", errors="replace")
    print(stdout, end="")
    if stderr:
        print(stderr, end="", file=sys.stderr)
    if process.returncode:
        raise FlowError(f"Stage {name} failed ({process.returncode}); see {log}.")
    if success_marker is not None and success_marker not in output:
        raise FlowError(f"Stage {name} returned success without {success_marker}; see {log}.")

    if name == "sim":
        sim_log = output_root(root) / "tests/video-tests.log"
        sim_log.parent.mkdir(parents=True, exist_ok=True)
        sim_log.write_text(output, encoding="utf-8", errors="replace")

    qor = None
    if name == "synth":
        if part is None:
            raise FlowError("Synthesis QoR collection requires a part.")
        qor = write_synth_qor(root, part, profile or "generic", version, input_hash)
        timing = qor["timing"]
        if profile not in COMPOSITE_SYNTH_PROFILES and not timing["setup_pass"]:
            raise FlowError(
                f"Synthesis setup timing failed for {profile}: "
                f"WNS={timing['wns_ns']} ns, TNS={timing['tns_ns']} ns."
            )

    outputs = output_manifest(name, root, part, profile)
    stages[stage_key] = {
        "status": "succeeded",
        "stage": name,
        "profile": profile,
        "input_partition_version": INPUT_PARTITION_VERSION,
        "product_version": PRODUCT_VERSION,
        "python_version": sys.version.split()[0] if name == "sim" else None,
        "completed_at_utc": now(),
        "input_sha256": input_hash,
        "inputs": inputs,
        "vivado_version": version,
        "part": part,
        "command": command,
        "log": log.relative_to(root).as_posix(),
        "outputs": outputs,
        "output_sha256": output_fingerprint(outputs),
        **({"qor": qor} if qor is not None else {}),
    }
    if not managed:
        write_manifest(data, root)
    print(f"VIDEO_FLOW_STAGE_PASS: {stage_key}")
    return True


def command_sim(_: argparse.Namespace) -> None:
    vivado = resolve_vivado(None)
    version = vivado_version(vivado)
    script = ROOT / "tools/run_video_tests.sh"
    env = os.environ.copy()
    env["VIVADO_BIN"] = str(vivado.parent)
    env["PYTHON_BIN"] = sys.executable
    inputs = input_manifest("sim")
    # Release regression uses the standalone xelab -a -R runner by default.
    run_stage(
        "sim", [str(script)], vivado, inputs, tool_version=version,
        env=env, success_marker="VIDEO_TESTS_PASS",
    )


def command_package(args: argparse.Namespace, validate: bool = False) -> None:
    vivado = resolve_vivado(args.vivado)
    version = vivado_version(vivado)
    package = [
        str(vivado), "-mode", "batch", "-source", str(ROOT / "tools/package_all.tcl"),
        "-tclargs", str(ROOT), str(output_root() / "packages/ip_repo"),
        str(output_root() / "package_composite_project"),
    ]
    package_env = os.environ.copy()
    package_env["VIDEO_IP_PACKAGE_WORK_DIR"] = str(output_root() / "package_project_static_profile")
    run_stage(
        "package", package, vivado, input_manifest("package"),
        tool_version=version, env=package_env, success_marker="EMBEDDED_VIDEO_IP_PACKAGE_STAGE_PASS",
    )
    if validate:
        validation = [
            str(vivado), "-mode", "batch",
            "-source", str(ROOT / "tools/validate_ip_catalog.tcl"),
            "-tclargs", str(ROOT), str(output_root() / "packages/ip_repo"),
            str(output_root() / "ip_catalog_validation_feature_profile"),
        ]
        run_stage(
            "ip_catalog", validation, vivado, input_manifest("ip_catalog"),
            tool_version=version, success_marker="EMBEDDED_VIDEO_IP_CATALOG_PASS",
        )


def command_synth(args: argparse.Namespace) -> None:
    vivado = resolve_vivado(args.vivado)
    version = vivado_version(vivado)
    part = args.part
    profile = getattr(args, "profile", "generic")
    generics = synth_profile_generics(profile)
    output_dir = synth_profile_output_dir(part, profile)
    generic_args = [f"{name}={value}" for name, value in generics.items()]
    if profile in COMPOSITE_SYNTH_PROFILES:
        script = ROOT / "tools/synth_composite.tcl"
        command = [
            str(vivado), "-mode", "batch", "-source", str(script),
            "-tclargs", str(ROOT), str(output_root() / "packages/ip_repo"), part,
            str(output_dir), profile, *generic_args,
        ]
    else:
        script = ROOT / "tools/synth_core.tcl"
        command = [
            str(vivado), "-mode", "batch", "-source", str(script),
            "-tclargs", str(ROOT), part, str(output_dir), profile, *generic_args,
        ]
    success_marker = (
        "EMBEDDED_VIDEO_IP_SYNTH_PASS"
        if profile in COMPOSITE_SYNTH_PROFILES else "VIDEO_SYNTH_PASS"
    )
    run_stage(
        "synth", command, vivado, input_manifest("synth", profile=profile),
        part, tool_version=version, profile=profile,
        success_marker=success_marker,
    )


def command_status(_: argparse.Namespace) -> None:
    data = read_manifest()
    stages = data.get("stages", {})
    if not stages:
        print("No completed stages.")
        return
    try:
        version = vivado_version(resolve_vivado(None))
    except FlowError:
        version = ""
    for stage_key, record in sorted(stages.items()):
        if not isinstance(record, dict):
            print(f"{stage_key}: stale (invalid stage record)")
            continue
        stage = str(record.get("stage") or stage_key.split(":", 1)[0])
        part = record.get("part")
        profile = record.get("profile")
        if stage == "synth":
            profile = str(profile or (stage_key.split(":", 1)[1] if ":" in stage_key else "generic"))
            try:
                synth_profile_generics(profile)
            except FlowError:
                print(f"{stage_key}: stale (unknown profile)")
                continue
        try:
            current = input_manifest(stage, ROOT, profile=profile)
            expected = fingerprint(current, version, stage, part, profile)
            state = (
                "fresh" if version and stage_cache_valid(
                    stage, record, expected, version, ROOT, part, profile
                ) else "stale"
            )
        except (FlowError, OSError, ValueError):
            state = "stale"
        print(f"{stage_key}: {state} (Vivado {record.get('vivado_version')}, part {part}, profile {profile})")
        qor = record.get("qor")
        if stage == "synth" and isinstance(qor, dict):
            resources = qor.get("resources", {})
            timing = qor.get("timing", {})
            if isinstance(resources, dict) and isinstance(timing, dict):
                print(
                    "  QoR: "
                    f"LUT={resources.get('lut')} FF={resources.get('ff')} "
                    f"LUTRAM={resources.get('lutram')} BRAM={resources.get('bram_tiles')} "
                    f"DSP={resources.get('dsp')} WNS={timing.get('wns_ns')} ns "
                    f"TNS={timing.get('tns_ns')} ns WHS={timing.get('whs_ns')} ns "
                    f"THS={timing.get('ths_ns')} ns"
                )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("doctor")
    p.add_argument("--vivado")
    sub.add_parser("sim")
    p = sub.add_parser("package")
    p.add_argument("--vivado")
    p = sub.add_parser("validate")
    p.add_argument("--vivado")
    p = sub.add_parser("synth")
    p.add_argument("--vivado")
    p.add_argument("--part", default="xc7z020clg400-1")
    p.add_argument("--profile", choices=tuple(SYNTH_PROFILE_GENERICS), default="generic")
    p = sub.add_parser("build")
    p.add_argument("--vivado")
    p.add_argument("--part", default="xc7z020clg400-1")
    p.add_argument("--profile", choices=tuple(SYNTH_PROFILE_GENERICS), default="generic")
    sub.add_parser("status")
    args = parser.parse_args()

    try:
        if args.command == "doctor":
            vivado = resolve_vivado(args.vivado)
            version = vivado_version(vivado)
            if version != VIVADO_VERSION:
                raise FlowError(f"Required Vivado {VIVADO_VERSION}; found {version}.")
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
            synth_args = argparse.Namespace(vivado=args.vivado, part=args.part, profile=args.profile)
            command_synth(synth_args)
        elif args.command == "status":
            command_status(args)
        return 0
    except FlowError as exc:
        print(f"[VIDEO-FLOW] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
