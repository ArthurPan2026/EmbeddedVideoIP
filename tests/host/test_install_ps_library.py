from __future__ import annotations

import sys
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from install_ps_library import BEGIN, END, install  # noqa: E402


class InstallPsLibraryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app_src = Path(self.temp.name) / "app" / "src"
        self.app_src.mkdir(parents=True)
        self.config = self.app_src / "UserConfig.cmake"
        self.config.write_text(
            "set(USER_INCLUDE_DIRECTORIES)\nset(USER_COMPILE_SOURCES)\n",
            encoding="utf-8",
        )

    def test_install_is_versioned_and_idempotent(self) -> None:
        outputs = install(ROOT, self.app_src)
        self.assertEqual(len(outputs), 5)
        once = self.config.read_text(encoding="utf-8")
        self.assertEqual(once.count(BEGIN), 1)
        self.assertEqual(once.count(END), 1)
        self.assertIn("list(APPEND USER_INCLUDE_DIRECTORIES", once)
        self.assertIn("Video/Lib/Src/video_out.c", once)
        self.assertIn("Video/Lib/XilinxZynq7000/video_out_xilinx.c", once)
        self.assertEqual(install(ROOT, self.app_src), outputs)
        self.assertEqual(self.config.read_text(encoding="utf-8"), once)
        self.assertEqual(
            (self.app_src / "Video/Lib/Src/video_out.c").read_bytes(),
            (ROOT / "software/video_out.c").read_bytes(),
        )

    def test_rejects_collision_before_modifying_config(self) -> None:
        target = self.app_src / "Video/Lib/Inc/video_out.h"
        target.parent.mkdir(parents=True)
        target.write_text("user-owned file\n", encoding="utf-8")
        before = self.config.read_bytes()
        with self.assertRaisesRegex(ValueError, "collision"):
            install(ROOT, self.app_src)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(target.read_text(encoding="utf-8"), "user-owned file\n")

    def test_respects_complete_manual_configuration(self) -> None:
        original = '''set(USER_INCLUDE_DIRECTORIES
    "${CMAKE_CURRENT_SOURCE_DIR}/Video/Lib/Inc"
    "${CMAKE_CURRENT_SOURCE_DIR}/Video/Lib/XilinxZynq7000"
)
set(USER_COMPILE_SOURCES
    "Video/Lib/Src/video_out.c"
    "Video/Lib/XilinxZynq7000/video_out_xilinx.c"
)
'''
        self.config.write_text(original, encoding="utf-8")
        install(ROOT, self.app_src)
        self.assertEqual(self.config.read_text(encoding="utf-8"), original)
        self.assertTrue((self.app_src / "Video/Lib/Inc/video_out.h").is_file())

    def test_rejects_partial_manual_configuration(self) -> None:
        self.config.write_text(
            'list(APPEND USER_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/Video/Lib/Inc")\n',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(ValueError, "only part"):
            install(ROOT, self.app_src)
        self.assertFalse((self.app_src / "Video/Lib/Src/video_out.c").exists())


if __name__ == "__main__":
    unittest.main()
