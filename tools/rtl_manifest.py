"""Validated declarative RTL regression manifest support.

The manifest is the single source of truth for bench names, sources and
per-bench execution metadata used by the video regression runner and flow
fingerprints.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import tomllib


SCHEMA_VERSION = 1
DEFAULT_SUCCESS_MARKERS = ("TEST_PASS:", "BMP_PASS:")
_ALLOWED_SUFFIXES = {".sv", ".v", ".vhd", ".vhdl"}


class RTLManifestError(ValueError):
    """The declarative RTL manifest is malformed or unsafe."""


@dataclass(frozen=True)
class RTLBench:
    name: str
    top: str
    sources: tuple[str, ...]
    defines: tuple[str, ...]
    success_markers: tuple[str, ...]
    output_log: str
    timeout_seconds: int | None
    parallel: bool
    resources: tuple[str, ...]
    suite: str | None = None


def _safe_relative(value: object, where: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise RTLManifestError(f"{where} must be a non-empty string")
    text = value.strip().replace("\\", "/")
    path = Path(text)
    if path.is_absolute() or ".." in path.parts or "\\x00" in text:
        raise RTLManifestError(f"{where} must be a project-relative path: {value!r}")
    return path.as_posix()


def _string_list(value: object, where: str, *, default: tuple[str, ...] = ()) -> tuple[str, ...]:
    if value is None:
        return default
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise RTLManifestError(f"{where} must be a non-empty string array")
    result = tuple(item.strip() for item in value)
    if len(set(result)) != len(result):
        raise RTLManifestError(f"{where} must not contain duplicates")
    return result


def _bool(value: object, where: str, default: bool) -> bool:
    if value is None:
        return default
    if type(value) is not bool:
        raise RTLManifestError(f"{where} must be a boolean")
    return value


def _timeout(value: object, where: str) -> int | None:
    if value is None:
        return None
    if type(value) is not int or value <= 0:
        raise RTLManifestError(f"{where} must be a positive integer")
    return value


def load_rtl_manifest(root: Path) -> tuple[RTLBench, ...]:
    """Load, validate, and resolve the project RTL manifest."""
    manifest_path = root / "tests" / "rtl_manifest.toml"
    try:
        with manifest_path.open("rb") as stream:
            raw: Any = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise RTLManifestError(f"cannot read {manifest_path}: {exc}") from exc
    if raw.get("schema_version") != SCHEMA_VERSION:
        raise RTLManifestError(
            f"unsupported RTL manifest schema in {manifest_path}: "
            f"{raw.get('schema_version')!r}"
        )
    entries = raw.get("bench")
    if not isinstance(entries, list) or not entries:
        raise RTLManifestError("tests/rtl_manifest.toml must contain at least one [[bench]]")
    benches: list[RTLBench] = []
    names: set[str] = set()
    for index, item in enumerate(entries):
        where = f"bench[{index}]"
        if not isinstance(item, dict):
            raise RTLManifestError(f"{where} must be a TOML table")
        name = item.get("name")
        if not isinstance(name, str) or not name.strip() or name in names:
            raise RTLManifestError(f"{where}.name is missing or duplicated: {name!r}")
        name = name.strip()
        top = item.get("top", name)
        if not isinstance(top, str) or not top.strip():
            raise RTLManifestError(f"{where}.top must be a non-empty string")
        top = top.strip()
        sources_raw = item.get("sources")
        if not isinstance(sources_raw, list) or not sources_raw:
            raise RTLManifestError(f"{where}.sources must be a non-empty string array")
        sources = tuple(_safe_relative(value, f"{where}.sources") for value in sources_raw)
        for source in sources:
            path = root / source
            if path.suffix.lower() not in _ALLOWED_SUFFIXES:
                raise RTLManifestError(f"{where}.sources contains unsupported HDL file: {source}")
            if not path.is_file() or path.is_symlink():
                raise RTLManifestError(f"{where}.sources contains missing or linked file: {source}")
        defines = _string_list(item.get("defines"), f"{where}.defines")
        markers = _string_list(
            item.get("success_markers"),
            f"{where}.success_markers",
            default=DEFAULT_SUCCESS_MARKERS,
        )
        if not markers:
            raise RTLManifestError(f"{where}.success_markers must not be empty")
        output_log = _safe_relative(
            item.get("output_log", f"out/tests/{name}/run.log"),
            f"{where}.output_log",
        )
        if not output_log.startswith("out/tests/") or not output_log.endswith("/run.log"):
            raise RTLManifestError(
                f"{where}.output_log must be under out/tests and end in /run.log"
            )
        suite = item.get("suite")
        if suite is not None and (not isinstance(suite, str) or not suite.strip()):
            raise RTLManifestError(f"{where}.suite must be a non-empty string when present")
        resources = _string_list(item.get("resources"), f"{where}.resources")
        bench = RTLBench(
            name=name,
            top=top,
            sources=sources,
            defines=defines,
            success_markers=markers,
            output_log=output_log,
            timeout_seconds=_timeout(item.get("timeout_seconds"), f"{where}.timeout_seconds"),
            parallel=_bool(item.get("parallel"), f"{where}.parallel", True),
            resources=resources,
            suite=suite.strip() if isinstance(suite, str) else None,
        )
        names.add(name)
        benches.append(bench)
    return tuple(benches)


def manifest_source_paths(root: Path) -> tuple[Path, ...]:
    """Return the unique HDL sources referenced by all benches."""
    return tuple(
        root / relative
        for relative in sorted(
            {source for bench in load_rtl_manifest(root) for source in bench.sources}
        )
    )


def manifest_output_paths(root: Path) -> tuple[Path, ...]:
    """Return the unique per-bench log paths declared by the manifest."""
    return tuple(
        root / bench.output_log
        for bench in load_rtl_manifest(root)
    )


def bench_map(root: Path) -> dict[str, RTLBench]:
    benches = load_rtl_manifest(root)
    return {bench.name: bench for bench in benches}
