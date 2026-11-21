from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.generate_package_metadata import build_metadata


class PackageMetadataTests(unittest.TestCase):
    def test_canonical_and_package_hashes_are_distinct_and_content_sensitive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            canonical = root / "ip/video_pipeline_1_0/hdl"
            canonical.mkdir(parents=True)
            (canonical / "core.sv").write_text("module core; endmodule\n", encoding="utf-8")
            package = root / "out/packages/ip_repo/panfpga/embedded_video_ip"
            (package / "src").mkdir(parents=True)
            (package / "src/core.sv").write_text("module core; endmodule\n", encoding="utf-8")
            (package / "component.xml").write_text(
                '<component xmlns:s="urn:spirit"><s:name>src/core.sv</s:name></component>\n', encoding="utf-8")
            first = build_metadata(root, package)
            (canonical / "core.sv").write_text("module core; wire x; endmodule\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "differs from canonical"):
                build_metadata(root, package)
            (package / "src/core.sv").write_text("module core; wire x; endmodule\n", encoding="utf-8")
            second = build_metadata(root, package)
            self.assertNotEqual(
                first["canonical_source"]["sha256"],
                second["canonical_source"]["sha256"],
            )
            self.assertNotEqual(first["package"]["sha256"], second["package"]["sha256"])

    def test_generated_constant_vsync_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "ip/video_pipeline_1_0/hdl/core.sv"
            source.parent.mkdir(parents=True)
            source.write_text("module core; endmodule\n")
            package = root / "out/packages/ip_repo/panfpga/embedded_video_ip"
            (package / "src").mkdir(parents=True)
            (package / "src/core.sv").write_text(source.read_text())
            (package / "component.xml").write_text(
                '<component xmlns:s="urn:spirit"><s:name>src/core.sv</s:name></component>')
            (package / "src/embedded_video_ip_video_out.v").write_text(".vtg_vsync(1'b0)")
            with self.assertRaisesRegex(ValueError, "VSYNC is tied"):
                build_metadata(root, package)

    def test_package_metadata_script_is_part_of_package_inputs(self) -> None:
        from tools import video_flow

        selected = set(video_flow.input_manifest("package"))
        self.assertIn("tools/generate_package_metadata.py", selected)


if __name__ == "__main__":
    unittest.main()
