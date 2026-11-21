from __future__ import annotations

import dataclasses
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import run_video_tests as runner
from rtl_manifest import RTLBench


class RegressionRunnerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "src").mkdir()
        (self.root / "tools").mkdir()
        (self.root / "src/bench.sv").write_text("module bench; endmodule\n")
        (self.root / "tools/rtl_manifest.py").write_text("manifest loader\n")
        self.bench = RTLBench(name="bench", top="bench", sources=("src/bench.sv",),
            defines=(), success_markers=("TEST_PASS:",), output_log="build/fpga-flow/tests/bench/run.log",
            timeout_seconds=20, parallel=True, resources=(), artifacts=("frame.bmp",))
        self.patch = patch.object(runner, "ROOT", self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_cache_is_bound_to_version_inputs_and_declared_output_contents(self) -> None:
        out = self.root / "build/fpga-flow/tests/bench"
        out.mkdir(parents=True)
        log = out / "run.log"
        log.write_text("TEST_PASS: done\n")
        frame = out / "frame.bmp"
        frame.write_bytes(b"image")
        fingerprint = runner._fingerprint(self.bench, self.root / "vivado", "Vivado 1")
        (out / "bench.json").write_text(json.dumps({
            "status": "passed", "fingerprint": fingerprint,
            "output_hashes": {"run.log": runner._hash_file(log), "frame.bmp": runner._hash_file(frame)}}))
        self.assertTrue(runner._resume_hit(self.bench, out, fingerprint))
        self.assertNotEqual(fingerprint, runner._fingerprint(self.bench, self.root / "vivado", "Vivado 2"))
        self.assertNotEqual(fingerprint, runner._fingerprint(dataclasses.replace(self.bench, defines=("FLAG",)), self.root / "vivado", "Vivado 1"))
        frame.unlink()
        self.assertFalse(runner._resume_hit(self.bench, out, fingerprint))
        frame.write_bytes(b"image")
        log.write_text("TEST_PASS: done\nTEST_FAIL: failed later\n")
        self.assertFalse(runner._resume_hit(self.bench, out, fingerprint))

    def test_bmp_marker_alone_cannot_pass_a_bench(self) -> None:
        self.assertIsNone(runner._success_marker("BMP_PASS: image\n", self.bench))
        self.assertTrue(runner._has_failure("Fatal: TEST_FAIL: mismatch\n"))


if __name__ == "__main__":
    unittest.main()
