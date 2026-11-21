#!/usr/bin/env python3
"""Run the manifest-selected portable RTL subset with Icarus Verilog."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys

from rtl_manifest import load_rtl_manifest
from run_video_tests import _has_failure


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--backend", help="optional Icarus backend directory")
    args = parser.parse_args()
    benches = [bench for bench in load_rtl_manifest(ROOT) if bench.iverilog]
    if not benches:
        raise RuntimeError("RTL manifest has no Icarus-compatible benches")
    failures: list[str] = []
    for bench in benches:
        out = Path(os.environ.get("FPGA_FLOW_OUTPUT_DIR", str(ROOT / "build/fpga-flow"))) / "tests/iverilog" / bench.name
        out.mkdir(parents=True, exist_ok=True)
        command = [args.iverilog]
        if args.backend:
            command.extend(["-B", args.backend])
        command.extend(["-g2012", "-s", bench.top, "-o", str(out / "sim.vvp")])
        command.extend(f"-D{define}" for define in bench.defines)
        command.extend(str(ROOT / source) for source in bench.sources)
        try:
            compiled = subprocess.run(command, cwd=out, capture_output=True, text=True, timeout=120)
            (out / "compile.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
            if compiled.returncode:
                raise RuntimeError("compilation failed")
            simulated = subprocess.run([args.vvp, str(out / "sim.vvp")], cwd=out,
                                       capture_output=True, text=True, timeout=120)
            output = simulated.stdout + simulated.stderr
            (out / "run.log").write_text(output, encoding="utf-8")
            if simulated.returncode or _has_failure(output) or not any(m in output for m in bench.success_markers):
                raise RuntimeError("simulation failed or did not report its pass marker")
            print(f"[IVERILOG-PASS] {bench.name}", flush=True)
        except (OSError, subprocess.TimeoutExpired, RuntimeError) as exc:
            failures.append(f"{bench.name}: {exc}")
            print(f"[IVERILOG-FAIL] {bench.name}: {exc}", file=sys.stderr, flush=True)
    if failures:
        return 1
    print(f"IVERILOG_TESTS_PASS benches={len(benches)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
