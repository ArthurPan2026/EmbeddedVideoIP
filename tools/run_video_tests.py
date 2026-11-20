#!/usr/bin/env python3
"""Run the declarative EmbeddedVideoIP RTL and host regression manifest."""
from __future__ import annotations

import argparse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Iterable

from rtl_manifest import RTLBench, RTLManifestError, load_rtl_manifest


ROOT = Path(__file__).resolve().parents[1]


def load_manifest() -> tuple[RTLBench, ...]:
    return load_rtl_manifest(ROOT)


def _fingerprint(bench: RTLBench, vivado_bin: Path) -> str:
    digest = hashlib.sha256()
    digest.update(bench.name.encode("utf-8"))
    digest.update(b"\0")
    digest.update(bench.top.encode("utf-8"))
    digest.update(b"\0")
    digest.update("\n".join(bench.defines).encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(vivado_bin.resolve()).encode("utf-8"))
    for source in bench.sources:
        path = ROOT / source
        digest.update(source.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def run_checked(command: list[str], cwd: Path, log, timeout_seconds: int | None) -> None:
    print("[VIDEO-RUN] " + " ".join(command), flush=True)
    result = subprocess.run(
        command,
        cwd=cwd,
        stdout=log,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout_seconds,
    )
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}")


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
    return (
        state.get("status") == "passed"
        and state.get("fingerprint") == fingerprint
        and _success_marker(log_path.read_text(encoding="utf-8", errors="replace"), bench) is not None
    )


def run_bench(bench: RTLBench, vivado_bin: Path, out_root: Path, *, resume: bool = True) -> None:
    run_dir = out_root / bench.name
    run_dir.mkdir(parents=True, exist_ok=True)
    fingerprint = _fingerprint(bench, vivado_bin)
    if resume and _resume_hit(bench, run_dir, fingerprint):
        print(f"[VIDEO-CACHE] {bench.name}", flush=True)
        return
    log_path = run_dir / "run.log"
    try:
        with log_path.open("w", encoding="utf-8") as log:
            xvlog = [str(vivado_bin / "xvlog")]
            for define in bench.defines:
                xvlog.extend(["-d", define])
            xvlog.extend(["-sv", "-work", "work", *(str(ROOT / source) for source in bench.sources)])
            run_checked(xvlog, run_dir, log, bench.timeout_seconds)
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
                run_dir,
                log,
                bench.timeout_seconds,
            )
            run_checked(
                [str(vivado_bin / "xsim"), f"{bench.name}_snapshot", "-runall"],
                run_dir,
                log,
                bench.timeout_seconds,
            )
        output = log_path.read_text(encoding="utf-8", errors="replace")
        marker = _success_marker(output, bench)
        if marker is None:
            raise RuntimeError(
                f"{bench.name} did not report one of the pass markers: "
                + ", ".join(bench.success_markers)
            )
    except Exception:
        (run_dir / "bench.json").write_text(
            json.dumps(
                {"name": bench.name, "fingerprint": fingerprint, "status": "failed"},
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        raise
    (run_dir / "bench.json").write_text(
        json.dumps(
            {
                "name": bench.name,
                "top": bench.top,
                "fingerprint": fingerprint,
                "status": "passed",
                "success_markers": list(bench.success_markers),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"[VIDEO-PASS] {bench.name}", flush=True)


def _run_benches(benches: Iterable[RTLBench], vivado_bin: Path, out_root: Path, jobs: int, resume: bool) -> None:
    pending = list(benches)
    if jobs <= 1 or len(pending) <= 1:
        for bench in pending:
            run_bench(bench, vivado_bin, out_root, resume=resume)
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
                future = pool.submit(run_bench, bench, vivado_bin, out_root, resume=resume)
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
    _run_benches(benches, vivado_bin, out_root, args.jobs, not args.no_resume)

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
    print("VIDEO_TESTS_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
