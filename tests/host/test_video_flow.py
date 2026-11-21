from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools"))
import video_flow
from rtl_manifest import load_rtl_manifest

UTILIZATION_FIXTURE = """\
| Slice LUTs*                | 100 |     0 |          0 | 53200 | 0.19 |
| Slice Registers            | 80  |     0 |          0 | 106400 | 0.08 |
| LUT as Distributed RAM      | 20  |     0 |            |        |      |
| Unique Control Sets        | 12  |       |          0 | 13300 | 0.09 |
| Block RAM Tile             | 1   |     0 |          0 | 140 | 0.71 |
| DSPs                       | 2   |     0 |          0 | 220 | 0.91 |
"""
TIMING_FIXTURE = """\
| Design Timing Summary
    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints
      1.000        0.000                      0                   10        0.100        0.000                      0                   10        0.500        0.000                       0                   10
Setup :            0  Failing Endpoints,  Worst Slack        1.000ns,  Total Violation        0.000ns
Hold  :            0  Failing Endpoints,  Worst Slack        0.100ns,  Total Violation        0.000ns
"""


def write_synth_fixture(output_dir: Path, name: str = "fixture",
                        checkpoint_name: str = "video_pipeline.dcp",
                        timing_report: str = TIMING_FIXTURE) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "utilization.rpt").write_text(UTILIZATION_FIXTURE, encoding="utf-8")
    (output_dir / "timing_summary.rpt").write_text(timing_report, encoding="utf-8")
    (output_dir / "clock_interaction.rpt").write_text("clock interaction fixture\n", encoding="utf-8")
    (output_dir / "ignored_timing_exceptions.rpt").write_text("ignored exceptions fixture\n", encoding="utf-8")
    (output_dir / "methodology.rpt").write_text("methodology fixture\n", encoding="utf-8")
    (output_dir / "cdc.rpt").write_text("CDC fixture\n", encoding="utf-8")
    (output_dir / "bus_skew.rpt").write_text("bus skew fixture\n", encoding="utf-8")
    (output_dir / checkpoint_name).write_bytes(f"dcp-{name}".encode("ascii"))


class VideoFlowProfileTests(unittest.TestCase):
    def test_profile_parameter_maps(self) -> None:
        self.assertEqual(video_flow.synth_profile_generics("generic"), {})
        lutram = video_flow.synth_profile_generics("vdma_scaler_lutram")
        self.assertEqual(lutram["MAX_INPUT_WIDTH"], 640)
        self.assertEqual(lutram["MAX_INPUT_HEIGHT"], 480)
        self.assertEqual(lutram["OUTPUT_WIDTH"], 640)
        self.assertEqual(lutram["OUTPUT_HEIGHT"], 480)
        self.assertEqual(lutram["ENABLE_BRAM_SOURCE"], 0)
        self.assertEqual(lutram["ENABLE_HLS_SOURCE"], 0)
        self.assertEqual(lutram["ENABLE_VDMA_SOURCE"], 1)
        self.assertEqual(lutram["SOURCE_SELECT_MODE"], 1)
        self.assertEqual(lutram["FIXED_SOURCE"], 2)
        self.assertEqual(lutram["FORMAT_SELECT_MODE"], 1)
        self.assertEqual(lutram["FIXED_FORMAT"], 2)
        self.assertEqual(lutram["MAX_SCALER_INPUT_WIDTH"], 640)
        self.assertEqual(lutram["MAX_SCALER_INPUT_HEIGHT"], 480)
        self.assertEqual(lutram["ENABLE_SCALER"], 1)
        self.assertEqual(lutram["LINE_BUFFER_IMPLEMENTATION"], 0)

        bram = video_flow.synth_profile_generics("vdma_scaler_bram")
        self.assertEqual(bram["MAX_SCALER_INPUT_WIDTH"], 640)
        self.assertEqual(bram["ENABLE_SCALER"], 1)
        self.assertEqual(bram["LINE_BUFFER_IMPLEMENTATION"], 1)

        passthrough = video_flow.synth_profile_generics("passthrough")
        self.assertEqual(passthrough["ENABLE_BRAM_SOURCE"], 0)
        self.assertEqual(passthrough["ENABLE_HLS_SOURCE"], 0)
        self.assertEqual(passthrough["ENABLE_VDMA_SOURCE"], 1)
        self.assertEqual(passthrough["SOURCE_SELECT_MODE"], 1)
        self.assertEqual(passthrough["FIXED_SOURCE"], 2)
        self.assertEqual(passthrough["FORMAT_SELECT_MODE"], 1)
        self.assertEqual(passthrough["FIXED_FORMAT"], 2)
        self.assertEqual(passthrough["OUTPUT_WIDTH"], 640)
        self.assertEqual(passthrough["OUTPUT_HEIGHT"], 480)
        self.assertEqual(passthrough["ENABLE_SCALER"], 0)
        self.assertNotIn("MAX_SCALER_INPUT_WIDTH", passthrough)

        audio_off = video_flow.synth_profile_generics("composite_audio_off")
        audio_on = video_flow.synth_profile_generics("composite_audio_on")
        self.assertEqual(audio_off["ENABLE_HDMI_AUDIO"], 0)
        self.assertEqual(audio_on["ENABLE_HDMI_AUDIO"], 1)
        self.assertEqual(audio_off["MAX_SCALER_INPUT_WIDTH"], 240)
        self.assertEqual(audio_off["MAX_SCALER_INPUT_HEIGHT"], 160)
        self.assertEqual(
            {key: value for key, value in audio_off.items() if key != "ENABLE_HDMI_AUDIO"},
            {key: value for key, value in audio_on.items() if key != "ENABLE_HDMI_AUDIO"},
        )
        self.assertEqual(video_flow.synth_checkpoint_name("composite_audio_on"), "embedded_video_ip.dcp")
        self.assertEqual(video_flow.synth_checkpoint_name("vdma_scaler_lutram"), "video_pipeline.dcp")

        with self.assertRaises(video_flow.FlowError):
            video_flow.synth_profile_generics("unknown")

    def test_synth_tcl_adds_validated_generic_pairs(self) -> None:
        synth_tcl = (REPO_ROOT / "tools/synth_core.tcl").read_text(encoding="utf-8")
        self.assertEqual(synth_tcl.count("lappend synth_command -generic"), 1)
        self.assertIn("lappend synth_command -generic $generic", synth_tcl)
        self.assertIn("eval $synth_command", synth_tcl)
        self.assertNotIn("synth_design {*}$synth_command", synth_tcl)
        self.assertIn('puts "VIDEO_SYNTH_COMMAND: $synth_command"', synth_tcl)

    def test_synth_report_parser_collects_resources_and_setup_hold(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            utilization = root / "utilization.rpt"
            timing = root / "timing_summary.rpt"
            utilization.write_text(UTILIZATION_FIXTURE, encoding="utf-8")
            timing.write_text(TIMING_FIXTURE, encoding="utf-8")
            metrics = video_flow.parse_synth_reports(utilization, timing)

        self.assertEqual(metrics["resources"], {
            "lut": 100, "ff": 80, "lutram": 20,
            "bram_tiles": 1, "dsp": 2, "control_sets": 12,
        })
        self.assertEqual(metrics["timing"]["wns_ns"], 1.0)
        self.assertEqual(metrics["timing"]["whs_ns"], 0.1)
        self.assertTrue(metrics["timing"]["all_timing_pass"])

    def test_command_synth_forwards_selected_generics_and_profile_path(self) -> None:
        vivado = Path("/fake/vivado")
        args = SimpleNamespace(vivado=str(vivado), part="xc7z020clg400-1", profile="vdma_scaler_lutram")
        with patch.object(video_flow, "resolve_vivado", return_value=vivado), patch.object(video_flow, "vivado_version", return_value="2025.2.1"), patch.object(video_flow, "input_manifest", return_value={"rtl": "sha"}), patch.object(video_flow, "run_stage") as run_stage:
            video_flow.command_synth(args)

        command = run_stage.call_args.args[1]
        self.assertEqual(run_stage.call_args.args[0], "synth")
        self.assertIn("profiles/vdma_scaler_lutram", Path(command[command.index("-tclargs") + 3]).as_posix())
        forwarded = set(command[command.index("-tclargs") + 4:])
        self.assertIn("ENABLE_BRAM_SOURCE=0", forwarded)
        self.assertIn("ENABLE_HLS_SOURCE=0", forwarded)
        self.assertIn("ENABLE_VDMA_SOURCE=1", forwarded)
        self.assertIn("FIXED_SOURCE=2", forwarded)
        self.assertIn("FIXED_FORMAT=2", forwarded)
        self.assertIn("MAX_SCALER_INPUT_WIDTH=640", forwarded)
        self.assertIn("MAX_SCALER_INPUT_HEIGHT=480", forwarded)
        self.assertIn("ENABLE_SCALER=1", forwarded)
        self.assertIn("LINE_BUFFER_IMPLEMENTATION=0", forwarded)
        self.assertEqual(run_stage.call_args.kwargs["profile"], "vdma_scaler_lutram")

    def test_command_synth_uses_composite_script_and_audio_static_parameter(self) -> None:
        vivado = Path("/fake/vivado")
        args = SimpleNamespace(vivado=str(vivado), part="xc7z020clg400-1", profile="composite_audio_on")
        with patch.object(video_flow, "resolve_vivado", return_value=vivado), patch.object(video_flow, "vivado_version", return_value="2025.2.1"), patch.object(video_flow, "input_manifest", return_value={"rtl": "sha"}), patch.object(video_flow, "run_stage") as run_stage:
            video_flow.command_synth(args)

        command = run_stage.call_args.args[1]
        self.assertTrue(any("synth_composite.tcl" in arg for arg in command))
        self.assertIn("profiles/composite_audio_on", Path(command[command.index("-tclargs") + 4]).as_posix())
        self.assertIn("ENABLE_HDMI_AUDIO=1", command)
        self.assertEqual(run_stage.call_args.kwargs["success_marker"], "EMBEDDED_VIDEO_IP_SYNTH_PASS")

    def test_composite_ooc_timing_is_recorded_without_signoff_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            part = "xc7z020clg400-1"
            profile = "composite_audio_off"
            timing = TIMING_FIXTURE.replace(
                "0.100        0.000                      0                   10",
                "-2.182       -4.365                      2                   10",
            ).replace(
                "Hold  :            0  Failing Endpoints,  Worst Slack        0.100ns,  Total Violation        0.000ns",
                "Hold  :            2  Failing Endpoints,  Worst Slack       -2.182ns,  Total Violation       -4.365ns",
            )

            def runner(command, cwd, text, capture_output, check, env):
                output_dir = video_flow.synth_profile_output_dir(part, profile, root)
                write_synth_fixture(
                    output_dir, profile, "embedded_video_ip.dcp", timing
                )
                return SimpleNamespace(
                    returncode=0,
                    stdout="EMBEDDED_VIDEO_IP_SYNTH_PASS: profile=composite_audio_off\n",
                    stderr="",
                )

            video_flow.run_stage(
                "synth", ["vivado", "synth_composite.tcl"], Path("/fake/vivado"),
                {"package": "sha"}, part, root=root, tool_version="2025.2.1",
                profile=profile, runner=runner,
                success_marker="EMBEDDED_VIDEO_IP_SYNTH_PASS",
            )
            record = video_flow.read_manifest(root)["stages"]["synth:composite_audio_off"]
            self.assertFalse(record["qor"]["timing"]["hold_pass"])
            self.assertFalse(record["qor"]["timing_signoff"])
            self.assertIn("pre-route OOC", record["qor"]["timing_scope"])

    def test_profiles_use_independent_cache_keys_and_output_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            part = "xc7z020clg400-1"
            calls: list[str] = []

            def runner_for(profile: str):
                def runner(command, cwd, text, capture_output, check, env):
                    calls.append(profile)
                    output_dir = video_flow.synth_profile_output_dir(part, profile, root)
                    write_synth_fixture(output_dir, profile)
                    return SimpleNamespace(
                        returncode=0,
                        stdout=f"VIDEO_SYNTH_PASS: profile={profile}\\n",
                        stderr="",
                    )
                return runner

            inputs = {"rtl": "same-inputs"}
            for profile in ("generic", "vdma_scaler_lutram", "vdma_scaler_bram", "passthrough"):
                command = ["vivado", "synth_core.tcl", profile]
                video_flow.run_stage(
                    "synth", command, Path("/fake/vivado"), inputs, part,
                    root=root, tool_version="2025.2.1", profile=profile,
                    runner=runner_for(profile), success_marker="VIDEO_SYNTH_PASS",
                )

            generic_dir = root / "build/fpga-flow/synth" / part
            lutram_dir = root / "build/fpga-flow/synth" / part / "profiles/vdma_scaler_lutram"
            bram_dir = root / "build/fpga-flow/synth" / part / "profiles/vdma_scaler_bram"
            passthrough_dir = root / "build/fpga-flow/synth" / part / "profiles/passthrough"
            generic_before = (generic_dir / "utilization.rpt").read_text(encoding="utf-8")
            self.assertEqual((lutram_dir / "utilization.rpt").read_text(encoding="utf-8"), UTILIZATION_FIXTURE)
            self.assertTrue((bram_dir / "qor.json").is_file())
            self.assertEqual(
                json.loads((bram_dir / "qor.json").read_text(encoding="utf-8"))["profile"],
                "vdma_scaler_bram",
            )
            self.assertNotEqual(lutram_dir, passthrough_dir)

            hit = video_flow.run_stage(
                "synth", ["vivado", "synth_core.tcl", "vdma_scaler_lutram"], Path("/fake/vivado"),
                inputs, part, root=root, tool_version="2025.2.1", profile="vdma_scaler_lutram",
                runner=runner_for("vdma_scaler_lutram"), success_marker="VIDEO_SYNTH_PASS",
            )
            self.assertFalse(hit)
            self.assertEqual(calls, ["generic", "vdma_scaler_lutram", "vdma_scaler_bram", "passthrough"])
            self.assertEqual((generic_dir / "utilization.rpt").read_text(encoding="utf-8"), generic_before)

            manifest = video_flow.read_manifest(root)
            self.assertEqual(
                set(manifest["stages"]),
                {"synth:generic", "synth:vdma_scaler_lutram", "synth:vdma_scaler_bram", "synth:passthrough"},
            )

class CompositeResetPolarityTests(unittest.TestCase):
    def test_vsync_observation_does_not_disconnect_timing_interface(self):
        root = Path(__file__).resolve().parents[2]
        script = (root / "tools/package_composite_ip.tcl").read_text(encoding="utf-8")
        wrapper = (root / "ip/video_pipeline_1_0/hdl/embedded_video_ip_timing_gen_wrapper.v").read_text(encoding="utf-8")
        self.assertIn("connect_bd_net [get_bd_pins $timing_gen/vsync_raw] $video_vsync_raw_port", script)
        self.assertNotIn("connect_bd_net [get_bd_pins $timing_gen/VSYNC] $video_vsync_raw_port", script)
        self.assertIn("assign vsync_raw = VSYNC;", wrapper)

    def test_hdmi_pixel_reset_constant_is_inactive_for_aux_polarity(self):
        root = Path(__file__).resolve().parents[2]
        script = (root / "tools" / "package_composite_ip.tcl").read_text(encoding="utf-8")
        self.assertIn("CONFIG.C_AUX_RESET_HIGH {1}", script)
        self.assertIn("CONFIG.C_EXT_RESET_HIGH {1}", script)
        self.assertIn("connect_bd_net [get_bd_pins $zero/dout] [get_bd_pins $rst/aux_reset_in]", script)
        self.assertIn("CONFIG.C_OPERATION {or}", script)
        self.assertIn("$pixel_reset_hold_port [get_bd_pins $reset_or/Op2]", script)
        self.assertIn("[get_bd_pins $reset_or/Res] $pixel_reset_ext_port [get_bd_pins $rst/ext_reset_in]", script)


class VideoFlowInputPartitionTests(unittest.TestCase):
    def make_source_tree(self, root: Path) -> None:
        files = [
            "tools/video_flow.py",
            "tools/package_ip.tcl",
            "tools/package_composite_ip.tcl",
            "tools/package_all.tcl",
            "tools/generate_package_metadata.py",
            "tools/validate_ip_catalog.tcl",
            "tools/synth_core.tcl",
            "tools/synth_composite.tcl",
            "tools/run_video_tests.sh",
            "tools/rtl_manifest.py",
            "tools/install_ps_library.py",
            "ip/video_pipeline_1_0/hdl/axis_video_nn_scaler.sv",
            "ip/video_pipeline_1_0/hdl/axis_rgb888.sv",
            "ip/video_pipeline_1_0/hdl/axis_video_mux3.sv",
            "ip/video_pipeline_1_0/hdl/video_bram_rgb565_reader.sv",
            "ip/video_pipeline_1_0/hdl/axi_lite_video_regs.sv",
            "ip/video_pipeline_1_0/hdl/video_pipeline_v1_0.sv",
            "ip/video_pipeline_1_0/hdl/video_pipeline_v1_0_wrapper.v",
            "ip/video_pipeline_1_0/hdl/embedded_video_ip_top.v",
            "ip/video_pipeline_1_0/hdl/embedded_video_ip_timing_gen_wrapper.v",
            "ip/video_pipeline_1_0/constraints/embedded_video_ip_clocks.xdc",
            "ip/video_pipeline_1_0/hdl/audio_event_pulse_sync.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_gain_bus_cdc.sv",
            "ip/video_pipeline_1_0/hdl/audio_gain_q15.sv",
            "ip/video_pipeline_1_0/hdl/audio_pcm_async_fifo.sv",
            "ip/video_pipeline_1_0/hdl/embedded_video_ip_reset_sync.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_runtime_status.sv",
            "ip/video_pipeline_1_0/hdl/embedded_video_ip_7series_tx.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_acr_packet.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_audio_infoframe.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_avi_infoframe.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_audio_sample_packet.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_bch_ecc.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_line_slot_scheduler.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_packet_assembler.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_pcm_packet_source.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_terc4_encoder.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_tmds_mode_mux.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_tmds_symbol_encoder.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_tmds_video_encoder.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_mode_transition_ctrl.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_video_timing_gen.sv",
            "ip/video_pipeline_1_0/hdl/hdmi_clock_profile_mux.sv",
            "ip_repo/if/tmds_v1_0/tmds.xml",
            "ip_repo/if/tmds_v1_0/tmds_rtl.xml",
            "fpga-project.toml",
            "contracts/video_contract.json",
            "contracts/pcm_contract.json",
            "software/video_out.c",
            "software/video_out.h",
            "software/platforms/xilinx_zynq7000/video_out_xilinx.c",
            "software/platforms/xilinx_zynq7000/video_out_xilinx.h",
            "software/unrelated_ps.c",
            "VERSION",
            "fpga-project.toml",
            "tools/run_video_tests.py",
            "tests/host/test_video_out.c",
            "tests/host/test_install_ps_library.py",
            "docs/architecture.md",
            "README.md",
        ]
        files.extend(
            source
            for bench in load_rtl_manifest(video_flow.ROOT)
            for source in bench.sources
        )
        files = list(dict.fromkeys(files))
        for relative in files:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"fixture:{relative}\n", encoding="utf-8")
        (root / "fpga-project.toml").write_text(
            (video_flow.ROOT / "fpga-project.toml").read_text(encoding="utf-8"),
            encoding="utf-8",
        )

    def test_synth_inputs_ignore_docs_tests_and_ps_but_track_rtl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_source_tree(root)
            before = video_flow.input_manifest("synth", root)
            selected = set(before)
            self.assertIn("tools/synth_core.tcl", selected)
            self.assertIn("ip/video_pipeline_1_0/constraints/embedded_video_ip_clocks.xdc", selected)
            self.assertIn("ip/video_pipeline_1_0/hdl/video_pipeline_v1_0.sv", selected)
            self.assertNotIn("docs/architecture.md", selected)
            self.assertNotIn("tests/rtl/tb_video_pipeline_v1_0.sv", selected)
            self.assertNotIn("software/video_out.c", selected)

            (root / "docs/architecture.md").write_text("docs changed\n", encoding="utf-8")
            (root / "tests/rtl/tb_video_pipeline_v1_0.sv").write_text("test changed\n", encoding="utf-8")
            (root / "software/video_out.c").write_text("PS changed\n", encoding="utf-8")
            self.assertEqual(video_flow.input_manifest("synth", root), before)

            (root / "ip/video_pipeline_1_0/constraints/embedded_video_ip_clocks.xdc").write_text(
                "timing constraints changed\n", encoding="utf-8"
            )
            self.assertNotEqual(video_flow.input_manifest("synth", root), before)

            (root / "ip/video_pipeline_1_0/hdl/video_pipeline_v1_0.sv").write_text(
                "RTL changed\n", encoding="utf-8"
            )
            self.assertNotEqual(video_flow.input_manifest("synth", root), before)

    def test_package_catalog_and_sim_use_separate_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_source_tree(root)
            package = set(video_flow.input_manifest("package", root))
            sim = set(video_flow.input_manifest("sim", root))

            self.assertIn("tools/package_ip.tcl", package)
            self.assertIn("tools/package_composite_ip.tcl", package)
            self.assertIn("tools/package_all.tcl", package)
            self.assertIn("fpga-project.toml", package)
            self.assertIn("ip_repo/if/tmds_v1_0/tmds.xml", package)
            self.assertIn("ip_repo/if/tmds_v1_0/tmds_rtl.xml", package)
            self.assertFalse(any(path.endswith((".vhd", ".vhdl")) for path in package))
            self.assertFalse(any(path.startswith("third_party/") for path in package))
            self.assertIn("ip/video_pipeline_1_0/hdl/video_pipeline_v1_0_wrapper.v", package)
            self.assertNotIn("docs/architecture.md", package)
            self.assertNotIn("software/video_out.c", package)
            self.assertIn("tests/rtl/tb_video_pipeline_v1_0.sv", sim)
            self.assertIn("ip/video_pipeline_1_0/hdl/hdmi_avi_infoframe.sv", sim)
            self.assertIn("ip/video_pipeline_1_0/hdl/hdmi_gain_bus_cdc.sv", sim)
            self.assertIn("tests/rtl/tb_hdmi_gain_bus_cdc.sv", sim)
            self.assertIn("ip/video_pipeline_1_0/hdl/hdmi_clock_profile_mux.sv", sim)
            self.assertIn("ip/video_pipeline_1_0/hdl/hdmi_mode_transition_ctrl.sv", sim)
            self.assertIn("tests/rtl/tb_hdmi_clock_profile_mux.sv", sim)
            self.assertIn("tests/rtl/tb_hdmi_color_avi_infoframe.sv", sim)
            self.assertIn("tests/rtl/tb_hdmi_7series_output_serdes.sv", sim)
            self.assertIn("tests/rtl/tb_hdmi_pcm_profile_rates.sv", sim)
            self.assertFalse(any(path.endswith((".vhd", ".vhdl")) for path in sim))
            self.assertFalse(any(path.startswith("third_party/") for path in sim))
            self.assertIn("software/video_out.c", sim)
            self.assertIn("software/platforms/xilinx_zynq7000/video_out_xilinx.c", sim)
            self.assertIn("VERSION", sim)
            self.assertNotIn("software/unrelated_ps.c", sim)
            self.assertIn("tools/run_video_tests.sh", sim)
            self.assertIn("tools/run_video_tests.py", sim)
            self.assertIn("tools/rtl_manifest.py", sim)
            self.assertIn("fpga-project.toml", sim)
            self.assertNotIn("docs/architecture.md", sim)
            runner = (video_flow.ROOT / "tools/run_video_tests.sh").read_text(encoding="utf-8")
            manifest = (video_flow.ROOT / "fpga-project.toml").read_text(encoding="utf-8")
            for bench in (
                "tb_hdmi_clock_profile_mux",
                "tb_hdmi_mode_transition_ctrl",
                "tb_hdmi_video_timing_gen",
                "tb_axis_video_nn_scaler_output_dims",
                "tb_video_pipeline_output_mode",
                "tb_hdmi_color_avi_infoframe",
                "tb_hdmi_7series_output_serdes",
                "tb_hdmi_pcm_profile_rates",
            ):
                self.assertIn(f'name = "{bench}"', manifest)
            self.assertIn("run_video_tests.py", runner)
            self.assertNotIn("xvhdl", runner)

            packaged_root = root / "build/fpga-flow/packages/ip_repo/panfpga/video_pipeline"
            composite_root = root / "build/fpga-flow/packages/ip_repo/panfpga/embedded_video_ip"
            for package_root in (packaged_root, composite_root):
                (package_root / "src").mkdir(parents=True)
                (package_root / "component.xml").write_text("<component/>\n", encoding="utf-8")
                (package_root / "src/hdl.sv").write_text("packaged RTL\n", encoding="utf-8")
            catalog = set(video_flow.input_manifest("ip_catalog", root))
            self.assertIn("tools/validate_ip_catalog.tcl", catalog)
            self.assertIn("build/fpga-flow/packages/ip_repo/panfpga/video_pipeline/component.xml", catalog)
            self.assertIn("build/fpga-flow/packages/ip_repo/panfpga/embedded_video_ip/component.xml", catalog)
            self.assertIn("build/fpga-flow/packages/ip_repo/panfpga/video_pipeline/src/hdl.sv", catalog)
            self.assertIn("build/fpga-flow/packages/ip_repo/panfpga/embedded_video_ip/src/hdl.sv", catalog)
            self.assertNotIn("tools/package_ip.tcl", catalog)
            self.assertNotIn("software/video_out.c", catalog)
            before_catalog = video_flow.input_manifest("ip_catalog", root)
            (composite_root / "src/hdl.sv").write_text(
                "packaged RTL changed\n", encoding="utf-8"
            )
            self.assertNotEqual(video_flow.input_manifest("ip_catalog", root), before_catalog)

    def test_package_input_change_does_not_depend_on_documentation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_source_tree(root)
            before = video_flow.input_manifest("package", root)
            (root / "docs/architecture.md").write_text("updated\n", encoding="utf-8")
            self.assertEqual(video_flow.input_manifest("package", root), before)


class VideoFlowCacheTests(unittest.TestCase):
    def make_synth_runner(self, calls: list[list[str]]):
        def runner(command, cwd, text, capture_output, check, env):
            calls.append(command)
            output_dir = Path(cwd) / "synth/xc7z020clg400-1"
            write_synth_fixture(output_dir, f"call-{len(calls)}")
            return SimpleNamespace(
                returncode=0,
                stdout="VIDEO_SYNTH_PASS: part=xc7z020clg400-1\n",
                stderr="",
            )
        return runner

    def test_matching_inputs_and_all_output_hashes_skip_stage_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls: list[list[str]] = []
            runner = Mock(side_effect=self.make_synth_runner(calls))
            inputs = {"ip/video_pipeline_1_0/hdl/core.sv": "abc"}

            executed = video_flow.run_stage(
                "synth", ["vivado", "synth_core.tcl"], Path("/fake/vivado"),
                inputs, "xc7z020clg400-1", root=root, tool_version="2025.2.1",
                runner=runner, success_marker="VIDEO_SYNTH_PASS",
            )
            self.assertTrue(executed)
            self.assertEqual(runner.call_count, 1)

            executed = video_flow.run_stage(
                "synth", ["vivado", "synth_core.tcl"], Path("/fake/vivado"),
                inputs, "xc7z020clg400-1", root=root, tool_version="2025.2.1",
                runner=runner, success_marker="VIDEO_SYNTH_PASS",
            )
            self.assertFalse(executed)
            self.assertEqual(runner.call_count, 1)

    def test_package_cache_hashes_component_and_imported_hdl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls: list[list[str]] = []

            def runner(command, cwd, text, capture_output, check, env):
                calls.append(command)
                for package_root in (
                    root / "build/fpga-flow/packages/ip_repo/panfpga/video_pipeline",
                    root / "build/fpga-flow/packages/ip_repo/panfpga/embedded_video_ip",
                ):
                    (package_root / "src").mkdir(parents=True, exist_ok=True)
                    (package_root / "component.xml").write_text("<component/>\n", encoding="utf-8")
                    (package_root / "src/hdl.sv").write_text(
                        "module video_pipeline; endmodule\n", encoding="utf-8"
                    )
                project_dir = root / "build/fpga-flow/package_composite_project"
                required = (
                    "embedded_video_ip_package.xpr",
                    "embedded_video_ip_package.srcs/sources_1/bd/embedded_video_ip_video_out/embedded_video_ip_video_out.bd",
                    "embedded_video_ip_package.gen/sources_1/bd/embedded_video_ip_video_out/hdl/embedded_video_ip_video_out_wrapper.v",
                    "embedded_video_ip_package.gen/sources_1/bd/embedded_video_ip_video_out/synth/embedded_video_ip_video_out.v",
                )
                for relative in required:
                    path = project_dir / relative
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(f"fixture:{relative}\n", encoding="utf-8")
                return SimpleNamespace(
                    returncode=0,
                    stdout="EMBEDDED_VIDEO_IP_PACKAGE_STAGE_PASS\n",
                    stderr="",
                )

            command = ["vivado", "package_all.tcl"]
            inputs = {"package_sources": "v1"}
            video_flow.run_stage(
                "package", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="EMBEDDED_VIDEO_IP_PACKAGE_STAGE_PASS",
            )
            self.assertFalse(video_flow.run_stage(
                "package", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="EMBEDDED_VIDEO_IP_PACKAGE_STAGE_PASS",
            ))
            self.assertEqual(len(calls), 1)

            (root / "build/fpga-flow/packages/ip_repo/panfpga/embedded_video_ip/src/hdl.sv").write_text(
                "tampered\n", encoding="utf-8"
            )
            self.assertTrue(video_flow.run_stage(
                "package", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="EMBEDDED_VIDEO_IP_PACKAGE_STAGE_PASS",
            ))
            self.assertEqual(len(calls), 2)

    def test_input_change_or_output_tampering_forces_stage_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls: list[list[str]] = []
            runner = Mock(side_effect=self.make_synth_runner(calls))
            command = ["vivado", "synth_core.tcl"]

            video_flow.run_stage(
                "synth", command, Path("/fake/vivado"), {"rtl": "v1"},
                "xc7z020clg400-1", root=root, tool_version="2025.2.1",
                runner=runner, success_marker="VIDEO_SYNTH_PASS",
            )
            video_flow.run_stage(
                "synth", command, Path("/fake/vivado"), {"rtl": "v2"},
                "xc7z020clg400-1", root=root, tool_version="2025.2.1",
                runner=runner, success_marker="VIDEO_SYNTH_PASS",
            )
            self.assertEqual(runner.call_count, 2)

            report = root / "build/fpga-flow/synth/xc7z020clg400-1/timing_summary.rpt"
            report.write_text("tampered\n", encoding="utf-8")
            video_flow.run_stage(
                "synth", command, Path("/fake/vivado"), {"rtl": "v2"},
                "xc7z020clg400-1", root=root, tool_version="2025.2.1",
                runner=runner, success_marker="VIDEO_SYNTH_PASS",
            )
            self.assertEqual(runner.call_count, 3)

    def test_catalog_cache_requires_validation_bd_hash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls: list[list[str]] = []
            bd_path = root / video_flow.CATALOG_BD_REL

            def runner(command, cwd, text, capture_output, check, env):
                calls.append(command)
                bd_path.parent.mkdir(parents=True, exist_ok=True)
                bd_path.write_text("validated BD\\n", encoding="utf-8")
                return SimpleNamespace(
                    returncode=0,
                    stdout="EMBEDDED_VIDEO_IP_CATALOG_PASS\\n",
                    stderr="",
                )

            command = ["vivado", "validate_ip_catalog.tcl"]
            inputs = {"packaged_ip_sha": "v1"}
            video_flow.run_stage(
                "ip_catalog", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="EMBEDDED_VIDEO_IP_CATALOG_PASS",
            )
            self.assertFalse(video_flow.run_stage(
                "ip_catalog", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="EMBEDDED_VIDEO_IP_CATALOG_PASS",
            ))
            self.assertEqual(len(calls), 1)

            bd_path.write_text("tampered\\n", encoding="utf-8")
            self.assertTrue(video_flow.run_stage(
                "ip_catalog", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="EMBEDDED_VIDEO_IP_CATALOG_PASS",
            ))
            self.assertEqual(len(calls), 2)

    def test_sim_cache_checks_each_rtl_run_log(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls: list[list[str]] = []
            (root / "tests/rtl").mkdir(parents=True, exist_ok=True)
            (root / "tests/rtl/tb_fixture.sv").write_text("module tb_fixture; endmodule\n", encoding="utf-8")
            (root / "fpga-project.toml").write_text(
                'schema_version = 1\n\n[[tests.bench]]\n'
                'name = "tb_fixture"\n'
                'sources = ["tests/rtl/tb_fixture.sv"]\n'
                'top = "tb_fixture"\n'
                'artifacts = ["capture.bmp"]\n',
                encoding="utf-8",
            )

            def runner(command, cwd, text, capture_output, check, env):
                calls.append(command)
                for path in video_flow.manifest_output_paths(root):
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("TEST_PASS: fixture\n", encoding="utf-8")
                return SimpleNamespace(
                    returncode=0,
                    stdout="VIDEO_TESTS_PASS\\n",
                    stderr="",
                )

            command = ["run_video_tests.sh"]
            inputs = {"rtl_and_host_tests": "v1"}
            video_flow.run_stage(
                "sim", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="VIDEO_TESTS_PASS",
            )
            self.assertFalse(video_flow.run_stage(
                "sim", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="VIDEO_TESTS_PASS",
            ))
            self.assertEqual(len(calls), 1)

            altered = video_flow.manifest_output_paths(root)[0]
            altered.write_text("tampered\\n", encoding="utf-8")
            self.assertTrue(video_flow.run_stage(
                "sim", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="VIDEO_TESTS_PASS",
            ))
            self.assertEqual(len(calls), 2)

            bmp_path = video_flow.manifest_output_paths(root)[1]
            bmp_path.write_bytes(b"tampered BMP")
            self.assertTrue(video_flow.run_stage(
                "sim", command, Path("/fake/vivado"), inputs,
                root=root, tool_version="2025.2.1", runner=runner,
                success_marker="VIDEO_TESTS_PASS",
            ))
            self.assertEqual(len(calls), 3)

    def test_missing_required_output_prevents_cache_hit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls: list[list[str]] = []
            runner = Mock(side_effect=self.make_synth_runner(calls))
            command = ["vivado", "synth_core.tcl"]
            inputs = {"rtl": "v1"}

            video_flow.run_stage(
                "synth", command, Path("/fake/vivado"), inputs,
                "xc7z020clg400-1", root=root, tool_version="2025.2.1",
                runner=runner, success_marker="VIDEO_SYNTH_PASS",
            )
            (root / "build/fpga-flow/synth/xc7z020clg400-1/video_pipeline.dcp").unlink()
            video_flow.run_stage(
                "synth", command, Path("/fake/vivado"), inputs,
                "xc7z020clg400-1", root=root, tool_version="2025.2.1",
                runner=runner, success_marker="VIDEO_SYNTH_PASS",
            )
            self.assertEqual(runner.call_count, 2)


if __name__ == "__main__":
    unittest.main()
