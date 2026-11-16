#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vivado_bin="${VIVADO_BIN:-/tools/AMDDesignTools/2025.2.1/Vivado/bin}"
python_bin="${PYTHON_BIN:-python3}"
vivado_root="$(cd "$vivado_bin/.." && pwd)"
out_root="$repo_root/out/tests"
hdl="$repo_root/ip/video_pipeline_1_0/hdl"
third_party="$repo_root/third_party/digilent-rgb2dvi"
mkdir -p "$out_root"

run_xsim() {
  local name="$1"
  shift
  local run_dir="$out_root/$name"
  local -a verilog_sources=()
  local -a vhdl_sources=()
  local source
  local run_glbl=0
  mkdir -p "$run_dir"
  for source in "$@"; do
    if [[ "$source" == "--glbl" ]]; then
      run_glbl=1
    elif [[ "$source" == *.vhd ]]; then
      vhdl_sources+=("$source")
    else
      verilog_sources+=("$source")
    fi
  done
  (
    cd "$run_dir"
    if (("${#vhdl_sources[@]}" > 0)); then
      "$vivado_bin/xvhdl" -work work "${vhdl_sources[@]}"
    fi
    if (("${#verilog_sources[@]}" > 0)); then
      "$vivado_bin/xvlog" -sv -work work "${verilog_sources[@]}"
    fi
    if ((run_glbl)); then
      "$vivado_bin/xvlog" -sv -work work "$vivado_root/data/verilog/src/glbl.v"
      "$vivado_bin/xelab" "work.$name" work.glbl -L work -L unisim -s "${name}_snapshot"
    else
      "$vivado_bin/xelab" "work.$name" -L work -L unisim -s "${name}_snapshot"
    fi
    "$vivado_bin/xsim" "${name}_snapshot" -runall | tee run.log
  )
  if ! grep -q "TEST_PASS:" "$run_dir/run.log"; then
    echo "VIDEO_TEST_FAIL: $name did not report TEST_PASS" >&2
    exit 1
  fi
}

run_xsim tb_axis_video_nn_scaler \
  "$hdl/axis_video_nn_scaler.sv" "$repo_root/tests/rtl/tb_axis_video_nn_scaler.sv"
run_xsim tb_axis_video_nn_scaler_bram \
  "$hdl/axis_video_nn_scaler.sv" "$repo_root/tests/rtl/tb_axis_video_nn_scaler.sv"
run_xsim tb_video_bram_rgb565_reader \
  "$hdl/video_bram_rgb565_reader.sv" "$repo_root/tests/rtl/tb_video_bram_rgb565_reader.sv"
run_xsim tb_video_pipeline_v1_0 \
  "$hdl/axis_video_nn_scaler.sv" "$hdl/axis_rgb888.sv" \
  "$hdl/axis_video_mux3.sv" "$hdl/video_bram_rgb565_reader.sv" \
  "$hdl/axi_lite_video_regs.sv" "$hdl/video_pipeline_v1_0.sv" \
  "$repo_root/tests/rtl/tb_video_pipeline_v1_0.sv"
run_xsim tb_video_pipeline_static_profile \
  "$hdl/axis_video_nn_scaler.sv" "$hdl/axis_rgb888.sv" \
  "$hdl/axis_video_mux3.sv" "$hdl/video_bram_rgb565_reader.sv" \
  "$hdl/axi_lite_video_regs.sv" "$hdl/video_pipeline_v1_0.sv" \
  "$repo_root/tests/rtl/tb_video_pipeline_static_profile.sv"

run_xsim tb_hdmi_primitives \
  "$hdl/audio_gain_q15.sv" "$hdl/hdmi_terc4_encoder.sv" \
  "$hdl/hdmi_bch_ecc.sv" "$hdl/hdmi_tmds_symbol_encoder.sv" \
  "$repo_root/tests/rtl/tb_hdmi_primitives.sv"
run_xsim tb_hdmi_audio_packets \
  "$hdl/hdmi_audio_infoframe.sv" "$hdl/hdmi_audio_sample_packet.sv" \
  "$hdl/hdmi_acr_packet.sv" "$repo_root/tests/rtl/tb_hdmi_audio_packets.sv"
run_xsim tb_audio_pcm_async_fifo \
  "$hdl/audio_pcm_async_fifo.sv" "$repo_root/tests/rtl/tb_audio_pcm_async_fifo.sv"
run_xsim tb_hdmi_packet_assembler \
  "$hdl/hdmi_packet_assembler.sv" "$hdl/hdmi_bch_ecc.sv" \
  "$repo_root/tests/rtl/tb_hdmi_packet_assembler.sv"
run_xsim tb_hdmi_line_slot_scheduler \
  "$hdl/hdmi_line_slot_scheduler.sv" "$repo_root/tests/rtl/tb_hdmi_line_slot_scheduler.sv"
run_xsim tb_hdmi_tmds_mode_mux \
  "$hdl/hdmi_tmds_mode_mux.sv" "$hdl/hdmi_terc4_encoder.sv" \
  "$repo_root/tests/rtl/tb_hdmi_tmds_mode_mux.sv"
run_xsim tb_hdmi_digilent_video_encoder \
  "$third_party/DVI_Constants.vhd" "$third_party/TMDS_Encoder.vhd" \
  "$hdl/hdmi_tmds_video_encoder.sv" "$hdl/hdmi_tmds_symbol_encoder.sv" \
  "$hdl/hdmi_terc4_encoder.sv" "$repo_root/tests/rtl/tb_hdmi_digilent_video_encoder.sv"
run_xsim tb_hdmi_pcm_packet_source \
  "$hdl/hdmi_pcm_packet_source.sv" "$hdl/audio_pcm_async_fifo.sv" \
  "$hdl/audio_gain_q15.sv" "$hdl/hdmi_audio_sample_packet.sv" \
  "$hdl/hdmi_acr_packet.sv" "$hdl/hdmi_audio_infoframe.sv" \
  "$repo_root/tests/rtl/tb_hdmi_pcm_packet_source.sv"
run_xsim tb_embedded_video_ip_7series_tx \
  "$hdl/embedded_video_ip_7series_tx.sv" "$hdl/embedded_video_ip_reset_sync.sv" \
  "$hdl/hdmi_line_slot_scheduler.sv" "$hdl/hdmi_pcm_packet_source.sv" \
  "$hdl/hdmi_packet_assembler.sv" "$hdl/hdmi_tmds_video_encoder.sv" \
  "$hdl/hdmi_tmds_mode_mux.sv" "$hdl/hdmi_terc4_encoder.sv" \
  "$hdl/hdmi_bch_ecc.sv" "$hdl/hdmi_audio_sample_packet.sv" \
  "$hdl/hdmi_audio_infoframe.sv" "$hdl/hdmi_acr_packet.sv" \
  "$hdl/audio_pcm_async_fifo.sv" "$hdl/audio_gain_q15.sv" \
  "$third_party/DVI_Constants.vhd" "$third_party/TMDS_Encoder.vhd" \
  "$third_party/OutputSERDES.vhd" --glbl \
  "$repo_root/tests/rtl/tb_embedded_video_ip_7series_tx.sv"

gcc -std=c99 -Wall -Wextra -Werror -pedantic \
  -I"$repo_root/software" "$repo_root/software/video_out.c" \
  "$repo_root/tests/host/test_video_out.c" -o "$out_root/test_video_out"
"$out_root/test_video_out"
"$python_bin" --version
"$python_bin" -m unittest discover -s "$repo_root/tests/host" -v
echo "VIDEO_TESTS_PASS"
