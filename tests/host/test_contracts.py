from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ContractTests(unittest.TestCase):
    def _load(self, name: str) -> dict:
        return json.loads((ROOT / "contracts" / name).read_text(encoding="utf-8"))

    def test_video_contract_matches_composite_rtl_and_public_api(self) -> None:
        contract = self._load("video_contract.json")
        top = (ROOT / "ip/video_pipeline_1_0/hdl/embedded_video_ip_top.v").read_text()
        tx = (ROOT / "ip/video_pipeline_1_0/hdl/embedded_video_ip_7series_tx.sv").read_text()
        header = (ROOT / "software/video_out.h").read_text()
        for name in ("MAX_INPUT_WIDTH", "MAX_INPUT_HEIGHT"):
            self.assertRegex(top, rf"parameter integer {name}\s*=\s*{contract[name.lower()]}\b")
        for name in ("OUTPUT_WIDTH", "OUTPUT_HEIGHT"):
            self.assertIn(f".{name}({contract['max_' + name.lower()]})", top)
        rtl_vics = {int(value) for value in re.findall(r"active_video_vic\s*(?:<=|=)\s*8'd(\d+)", tx)} - {0}
        self.assertEqual(set(contract["supported_vic"]), rtl_vics)
        for pixel_format in contract["input_formats"]:
            self.assertIn("VIDEO_OUT_PIX_" + pixel_format, header)
        self.assertIn("stride_bytes", header)

    def test_pcm_contract_matches_transport_and_acr_rtl(self) -> None:
        contract = self._load("pcm_contract.json")
        top = (ROOT / "ip/video_pipeline_1_0/hdl/embedded_video_ip_top.v").read_text()
        source = (ROOT / "ip/video_pipeline_1_0/hdl/hdmi_pcm_packet_source.sv").read_text()
        acr = (ROOT / "ip/video_pipeline_1_0/hdl/hdmi_acr_packet.sv").read_text()
        self.assertIn("input wire [47:0] s_axis_audio_pcm_tdata", top)
        self.assertEqual(contract["data_width_bits"], 48)
        self.assertEqual(contract["sample_width_bits"], 24)
        self.assertEqual(contract["channels"], {"left": "TDATA[23:0]", "right": "TDATA[47:24]"})
        self.assertIn("gain_sample_left <= $signed(fifo_rd_data[23:0])", source)
        self.assertIn("gain_sample_right <= $signed(fifo_rd_data[47:24])", source)
        self.assertIn("gain_product_left <= gain_sample_left * gain_coefficient", source)
        self.assertIn("gain_product_right <= gain_sample_right * gain_coefficient", source)
        supported = {int(value.replace("_", "")) for value in re.findall(
            r"AUDIO_SAMPLE_RATE_HZ != ([0-9_]+)", acr)}
        self.assertEqual(set(contract["sample_rates_hz"]), supported)
        self.assertEqual(contract["acr_n"], {"48000": 6144, "96000": 12288, "192000": 24576})


if __name__ == "__main__":
    unittest.main()
