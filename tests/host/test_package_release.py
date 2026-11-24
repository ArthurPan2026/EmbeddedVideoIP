from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]


class ReleasePackageTests(unittest.TestCase):
    def test_ip_and_ps_archives_are_minimal_and_reproducible(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            project = work / "project"
            output = work / "release"
            package = project / "build/fpga-flow/packages/ip_repo"
            composite = package / "panfpga/embedded_video_ip"
            interface = package / "if/tmds_v1_0"
            composite.mkdir(parents=True)
            (composite / "src").mkdir()
            interface.mkdir(parents=True)
            (composite / "component.xml").write_text(
                '<spirit:component xmlns:spirit="urn:spirit" xmlns:xilinx="urn:xilinx">'
                '<xilinx:coreRevision>5</xilinx:coreRevision></spirit:component>\n', encoding="utf-8"
            )
            (composite / "src/core.sv").write_text("module core; endmodule\n", encoding="utf-8")
            (composite / "PACKAGE_METADATA.json").write_text(
                '{"canonical_source":{"sha256":"canonical-hash"}}\n', encoding="utf-8"
            )
            (interface / "tmds.xml").write_text("<interface/>\n", encoding="utf-8")
            (project / "VERSION").write_text("0.3.0-dev.2\n", encoding="utf-8")
            licenses = project / "LICENSES"
            licenses.mkdir()
            (licenses / "CERN-OHL-W-2.0.txt").write_text("hardware license\n", encoding="utf-8")
            (licenses / "Apache-2.0.txt").write_text("software license\n", encoding="utf-8")
            (project / "docs").mkdir()
            (project / "docs/ip-package-quickstart.md").write_text("Install guide\n", encoding="utf-8")
            for source in (
                "software/video_out.c",
                "software/video_out.h",
                "software/platforms/xilinx_zynq7000/video_out_xilinx.c",
                "software/platforms/xilinx_zynq7000/video_out_xilinx.h",
            ):
                path = project / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("/* source */\n", encoding="utf-8")

            command = [
                sys.executable, str(ROOT / "tools/package_release.py"),
                "--root", str(project), "--output", str(output),
                "--vivado-version", "2025.2.1",
            ]
            subprocess.run(command, check=True, capture_output=True, text=True)
            sums_first = (output / "SHA256SUMS").read_bytes()
            archives = sorted(output.glob("*.zip"))
            self.assertEqual(len(archives), 2)
            ip_archive = next(path for path in archives if "-vivado-" in path.name)
            ps_archive = next(path for path in archives if "-PS-" in path.name)
            with zipfile.ZipFile(ip_archive) as archive:
                names = set(archive.namelist())
                self.assertIn("embedded-video-ip/ip_repo/panfpga/embedded_video_ip/component.xml", names)
                self.assertIn("embedded-video-ip/ip_repo/if/tmds_v1_0/tmds.xml", names)
                self.assertIn("embedded-video-ip/LICENSES/CERN-OHL-W-2.0.txt", names)
                release_meta = json.loads(archive.read("embedded-video-ip/RELEASE-METADATA.json"))
                self.assertEqual(release_meta["core_revision"], 5)
                self.assertNotIn("embedded-video-ip/tests/testbench.sv", names)
            with zipfile.ZipFile(ps_archive) as archive:
                names = set(archive.namelist())
                self.assertIn("embedded-video-ip-ps-zynq7000/Video/Lib/Src/video_out.c", names)
                self.assertIn("embedded-video-ip-ps-zynq7000/LICENSES/Apache-2.0.txt", names)
                self.assertNotIn("embedded-video-ip-ps-zynq7000/software/unrelated.c", names)
            subprocess.run(command, check=True, capture_output=True, text=True)
            self.assertEqual((output / "SHA256SUMS").read_bytes(), sums_first)
            for archive in archives:
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                self.assertIn(digest.encode("ascii"), sums_first)


if __name__ == "__main__":
    unittest.main()
