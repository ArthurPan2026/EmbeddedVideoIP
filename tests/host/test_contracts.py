from __future__ import annotations

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ContractTests(unittest.TestCase):
    def _load(self, name: str) -> dict:
        return json.loads((ROOT / "contracts" / name).read_text(encoding="utf-8"))

    def test_video_contract_is_machine_readable(self) -> None:
        contract = self._load("video_contract.json")
        self.assertEqual(contract["max_output_width"], 1280)
        self.assertEqual(contract["max_output_height"], 720)
        self.assertEqual(contract["input_format"], "RGB565")
        self.assertEqual(contract["output_format"], "RGB888")
        self.assertEqual(contract["line_buffer_mode"], {"lutram": 0, "bram": 1})

    def test_pcm_contract_covers_16_to_24_bit_left_alignment(self) -> None:
        contract = self._load("pcm_contract.json")
        self.assertEqual(contract["sample_width_bits"], 24)
        self.assertEqual(contract["source_width_bits"], 16)
        self.assertEqual(contract["left_channel"], "TDATA[15:0]")
        self.assertEqual(contract["right_channel"], "TDATA[31:16]")
        for vector in contract["vectors"]:
            raw = int(vector["source_hex"], 16)
            signed = raw - (1 << 16) if raw & 0x8000 else raw
            expected = signed << 8
            self.assertEqual(expected & 0xFFFFFF, int(vector["expected_hex24"], 16))

    def test_contracts_are_referenced_by_the_documented_flow(self) -> None:
        flow = (ROOT / "tools/video_flow.py").read_text(encoding="utf-8")
        self.assertIn("contracts", flow)
        self.assertTrue((ROOT / "contracts/video_contract.json").is_file())
        self.assertTrue((ROOT / "contracts/pcm_contract.json").is_file())


if __name__ == "__main__":
    unittest.main()
