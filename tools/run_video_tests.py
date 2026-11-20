#!/usr/bin/env python3
"""Run the declarative EmbeddedVideoIP RTL and host regression manifest."""
from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from dataclasses import asdict
import hashlib
from itertools import groupby
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
from typing import Iterable

from rtl_manifest import RTLBench, RTLManifestError, load_rtl_manifest


ROOT = Path(__file__).resolve().parents[1]


def load_manifest() -> tuple[RTLBench, ...]:
    return load_rtl_manifest(ROOT)


def _hash_file(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _vivado_version(vivado_bin: Path) -> str:
    proc = subprocess.run([str(vivado_bin / "vivado"), "-version"], capture_output=True,
                          text=True, timeout=30, check=False)
    output = (proc.stdout + "\n" + proc.stderr).strip()
    if proc.returncode or not re.search(r"(?i)vivado\s+v\d", output):
        raise RuntimeError(f"cannot identify Vivado version: {output[-1000:]}")
    return output


def _fingerprint(bench: RTLBench, vivado_bin: Path, tool_version: str) -> str:
    data = {"schema_version": 2, "bench": asdict(bench), "vivado_bin": str(vivado_bin.resolve()),
            "vivado_version": tool_version, "runner_sha256": _hash_file(Path(__file__)),
            "manifest_reader_sha256": _hash_file(ROOT / "tools/rtl_manifest.py"),
            "sources": {source: _hash_file(ROOT / source) for source in bench.sources}}
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def run_checked(command: list[str], cwd: Path, log, timeout_seconds: int | None) -> None:
    print("[VIDEO-RUN] " + " ".join(command), flush=True)
    proc = subprocess.Popen(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                            start_new_session=(os.name == "posix"))
    try:
        code = proc.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as exc:
        if os.name == "posix":
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        else:
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            else:
                proc.kill()
            proc.wait()
        raise RuntimeError(f"command timed out after {timeout_seconds}s: {' '.join(command)}") from exc
    if code:
        raise RuntimeError(f"command failed ({code}): {' '.join(command)}")


def _success_marker(output: str, bench: RTLBench) -> str | None:
    for marker in bench.success_markers:
        if marker in output:
            return marker
    return None


def _resume_hit(bench: RTLBench, run_dir: Path, fingerprint: str) -> bool:
    state_path = run_dir / "bench.json"
    log_path = run_dir / "run.log"
    if not state_path.is_file() or not log_path.is_file():
        return False
    try:
        state = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    text = log_path.read_text(encoding="utf-8", errors="replace")
    expected = state.get("output_hashes")
    paths = [log_path, *(run_dir / name for name in bench.artifacts)]
    if not isinstance(expected, dict) or any(path.is_symlink() or not path.is_file() for path in paths):
        return False
    return (
        state.get("status") == "passed"
        and state.get("fingerprint") == fingerprint
        and not _has_failure(text)
        and _success_marker(text, bench) is not None
        and expected == {path.relative_to(run_dir).as_posix(): _hash_file(path) for path in paths}
    )


def _has_failure(text: str) -> bool:
    return bool(re.search(r"(?im)^\s*(?:.*\bTEST_FAIL\b|ERROR:|FATAL(?:_ERROR)?:|Fatal:)", text))


def _write_state(run_dir: Path, payload: dict[str, object]) -> None:
    temporary = run_dir / "bench.json.tmp"
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, run_dir / "bench.json")


def run_bench(bench: RTLBench, vivado_bin: Path, out_root: Path, tool_version: str, *, resume: bool = True) -> None:
    run_dir = out_root / Path(bench.output_log).relative_to("out/tests").parent
    run_dir.mkdir(parents=True, exist_ok=True)
    fingerprint = _fingerprint(bench, vivado_bin, tool_version)
    if resume and _resume_hit(bench, run_dir, fingerprint):
        print(f"[VIDEO-CACHE] {bench.name}", flush=True)
        return
    log_path = run_dir / "run.log"
    _write_state(run_dir, {"name": bench.name, "fingerprint": fingerprint, "status": "running"})
    for artifact in bench.artifacts:
        (run_dir / artifact).unlink(missing_ok=True)
    try:
        with tempfile.TemporaryDirectory(prefix=".work-", dir=run_dir) as temporary:
            workspace = Path(temporary)
            with log_path.open("w", encoding="utf-8") as log:
                for vhdl, group in groupby(bench.sources, key=lambda source: Path(source).suffix.lower() in {".vhd", ".vhdl"}):
                    command = [str(vivado_bin / ("xvhdl" if vhdl else "xvlog"))]
                    if not vhdl:
                        for define in bench.defines:
                            command.extend(["-d", define])
                        command.append("-sv")
                    command.extend(["-work", "work", *(str(ROOT / source) for source in group)])
                    run_checked(command, workspace, log, bench.timeout_seconds or 900)
                run_checked(
                    [
                        str(vivado_bin / "xelab"),
                        f"work.{bench.top}",
                        "-L",
                        "work",
                        "-L",
                        "unisim",
                        "-s",
                        f"{bench.name}_snapshot",
                    ],
                    workspace,
                    log,
                    bench.timeout_seconds or 900,
                )
                run_checked(
                    [str(vivado_bin / "xsim"), f"{bench.name}_snapshot", "-runall"],
                    workspace,
                    log,
                    bench.timeout_seconds or 900,
                )
            output = log_path.read_text(encoding="utf-8", errors="replace")
            if _has_failure(output):
                raise RuntimeError(f"{bench.name} reported a simulation failure; see {log_path}")
            marker = _success_marker(output, bench)
            if marker is None:
                raise RuntimeError(
                    f"{bench.name} did not report one of the pass markers: "
                    + ", ".join(bench.success_markers)
                )
            generated = [(workspace / name, run_dir / name) for name in bench.artifacts]
            if any(source.is_symlink() or not source.is_file() for source, _ in generated):
                raise RuntimeError(f"{bench.name} did not produce every declared artifact")
            if _fingerprint(bench, vivado_bin, tool_version) != fingerprint:
                raise RuntimeError(f"{bench.name} inputs changed during simulation")
            for source, destination in generated:
                destination.parent.mkdir(parents=True, exist_ok=True)
                if destination.is_symlink():
                    raise RuntimeError(f"refusing to replace linked artifact: {destination}")
                os.replace(source, destination)
            outputs = [log_path, *(destination for _, destination in generated)]
    except Exception as exc:
        _write_state(run_dir, {"name": bench.name, "fingerprint": fingerprint,
                               "status": "failed", "error": str(exc)})
        raise
    _write_state(run_dir, {"name": bench.name, "top": bench.top, "fingerprint": fingerprint,
                           "status": "passed", "output_hashes": {
                               path.relative_to(run_dir).as_posix(): _hash_file(path) for path in outputs}})
    print(f"[VIDEO-PASS] {bench.name}", flush=True)


def _run_benches(benches: Iterable[RTLBench], vivado_bin: Path, out_root: Path, jobs: int, resume: bool, tool_version: str) -> None:
    pending = list(benches)
    if jobs <= 1 or len(pending) <= 1:
        for bench in pending:
            run_bench(bench, vivado_bin, out_root, tool_version, resume=resume)
        return
    active: dict[object, tuple[RTLBench, set[str]]] = {}
    completed: set[str] = set()
    resources: set[str] = set()
    with ThreadPoolExecutor(max_workers=jobs, thread_name_prefix="video-rtl") as pool:
        while pending or active:
            launched = False
            for bench in list(pending):
                if not bench.parallel:
                    if active:
                        continue
                bench_resources = set(bench.resources)
                if bench_resources & resources:
                    continue
                if any(not item.parallel for item, _ in active.values()):
                    continue
                future = pool.submit(run_bench, bench, vivado_bin, out_root, tool_version, resume=resume)
                active[future] = (bench, bench_resources)
                resources.update(bench_resources)
                pending.remove(bench)
                launched = True
                if len(active) >= jobs:
                    break
            if active:
                done, _ = wait(tuple(active), return_when=FIRST_COMPLETED)
                for future in done:
                    bench, bench_resources = active.pop(future)
                    resources.difference_update(bench_resources)
                    future.result()
                    completed.add(bench.name)
            elif pending and not launched:
                raise RuntimeError("RTL manifest benches cannot be scheduled due to resource constraints")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--vivado-bin",
        default=os.environ.get("VIVADO_BIN", "/tools/AMDDesignTools/2025.2.1/Vivado/bin"),
    )
    parser.add_argument("--python", default=os.environ.get("PYTHON_BIN", sys.executable))
    parser.add_argument("--jobs", type=int, default=int(os.environ.get("VIDEO_TEST_JOBS", "1")))
    parser.add_argument("--bench", action="append", help="run only the named bench; repeatable")
    parser.add_argument("--no-resume", action="store_true")
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    try:
        benches = list(load_manifest())
    except RTLManifestError as exc:
        print(f"VIDEO_MANIFEST_ERROR: {exc}", file=sys.stderr)
        return 2
    if args.bench:
        selected = set(args.bench)
        known = {bench.name for bench in benches}
        unknown = sorted(selected - known)
        if unknown:
            parser.error("unknown bench: " + ", ".join(unknown))
        benches = [bench for bench in benches if bench.name in selected]
    vivado_bin = Path(args.vivado_bin)
    out_root = ROOT / "out" / "tests"
    out_root.mkdir(parents=True, exist_ok=True)
    tool_version = _vivado_version(vivado_bin)
    _run_benches(benches, vivado_bin, out_root, args.jobs, not args.no_resume, tool_version)

    test_video_out = out_root / "test_video_out"
    subprocess.run(
        [
            "gcc",
            "-std=c99",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-pedantic",
            f"-I{ROOT / 'software'}",
            str(ROOT / "software/video_out.c"),
            str(ROOT / "tests/host/test_video_out.c"),
            "-o",
            str(test_video_out),
        ],
        check=True,
    )
    subprocess.run([str(test_video_out)], check=True)
    subprocess.run(
        [args.python, "-m", "unittest", "discover", "-s", str(ROOT / "tests/host"), "-v"],
        check=True,
    )
    print("VIDEO_SELECTED_TESTS_PASS" if args.bench else "VIDEO_TESTS_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
