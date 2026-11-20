from __future__ import annotations

import unittest
from pathlib import Path

from tools.rtl_manifest import (
    DEFAULT_SUCCESS_MARKERS,
    load_rtl_manifest,
    manifest_output_paths,
    manifest_source_paths,
)


ROOT = Path(__file__).resolve().parents[2]


class RTLManifestTests(unittest.TestCase):
    def test_all_benches_are_unique_and_sources_exist(self) -> None:
        benches = load_rtl_manifest(ROOT)
        self.assertGreaterEqual(len(benches), 25)
        self.assertEqual(len({bench.name for bench in benches}), len(benches))
        for bench in benches:
            self.assertTrue(bench.top)
            self.assertTrue(bench.sources)
            self.assertTrue(set(bench.success_markers) & set(DEFAULT_SUCCESS_MARKERS))
            self.assertTrue(all((ROOT / source).is_file() for source in bench.sources))
            self.assertEqual(bench.output_log, f"out/tests/{bench.name}/run.log")

    def test_manifest_is_the_runner_source_of_truth(self) -> None:
        benches = load_rtl_manifest(ROOT)
        names = {bench.name for bench in benches}
        runner_source = (ROOT / "tools/run_video_tests.py").read_text(encoding="utf-8")
        self.assertIn("load_rtl_manifest", runner_source)
        self.assertNotIn("tb_hdmi_pcm_profile_rates \\", runner_source)
        self.assertEqual(
            {path.relative_to(ROOT).as_posix() for path in manifest_output_paths(ROOT)},
            {f"out/tests/{name}/run.log" for name in names},
        )
        sources = {path.relative_to(ROOT).as_posix() for path in manifest_source_paths(ROOT)}
        self.assertTrue(sources)
        self.assertTrue(all(source in sources for bench in benches for source in bench.sources))

    def test_manifest_source_changes_are_visible_to_flow_inputs(self) -> None:
        import tools.video_flow as video_flow

        selected = set(video_flow.input_manifest("sim", ROOT))
        for path in manifest_source_paths(ROOT):
            self.assertIn(path.relative_to(ROOT).as_posix(), selected)
        self.assertIn("tests/rtl_manifest.toml", selected)
        self.assertIn("tools/rtl_manifest.py", selected)


if __name__ == "__main__":
    unittest.main()
