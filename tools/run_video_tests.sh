#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vivado_bin="${VIVADO_BIN:-/tools/AMDDesignTools/2025.2.1/Vivado/bin}"
python_bin="${PYTHON_BIN:-python3}"
out_root="$repo_root/out/tests"
hdl="$repo_root/ip/video_pipeline_1_0/hdl"
mkdir -p "$out_root"

run_xsim() {
  local name="$1"
  shift
  local run_dir="$out_root/$name"
  local -a verilog_sources=()
  local source
  local use_synthesis_primitives=0
  mkdir -p "$run_dir"
  for source in "$@"; do
    if [[ "$source" == "--define-synthesis" ]]; then
      use_synthesis_primitives=1
    else
      verilog_sources+=("$source")
    fi
  done
  (
    cd "$run_dir"
    if (("${#verilog_sources[@]}" > 0)); then
      if ((use_synthesis_primitives)); then
        "$vivado_bin/xvlog" -d SYNTHESIS -sv -work work "${verilog_sources[@]}"
      else
        "$vivado_bin/xvlog" -sv -work work "${verilog_sources[@]}"
      fi
    fi
    "$vivado_bin/xelab" "work.$name" -L work -L unisim -s "${name}_snapshot"
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
run_xsim tb_axis_video_nn_scaler_output_dims \
  "$hdl/axis_video_nn_scaler.sv" "$repo_root/tests/rtl/tb_axis_video_nn_scaler_output_dims.sv"
run_xsim tb_axis_video_nn_scaler_native_input \
  "$hdl/axis_video_nn_scaler.sv" "$repo_root/tests/rtl/tb_axis_video_nn_scaler_native_input.sv"
run_xsim tb_axis_video_nn_scaler_native_input_bram \
  "$hdl/axis_video_nn_scaler.sv" "$repo_root/tests/rtl/tb_axis_video_nn_scaler_native_input.sv"
run_xsim tb_video_bram_rgb565_reader \
  "$hdl/video_bram_rgb565_reader.sv" "$repo_root/tests/rtl/tb_video_bram_rgb565_reader.sv"
run_xsim tb_video_pipeline_v1_0 \
  "$hdl/axis_video_nn_scaler.sv" "$hdl/axis_rgb888.sv" \
  "$hdl/axis_video_mux3.sv" "$hdl/video_bram_rgb565_reader.sv" \
  "$hdl/axi_lite_video_regs.sv" "$hdl/video_pipeline_v1_0.sv" \
  "$repo_root/tests/rtl/tb_video_pipeline_v1_0.sv"
run_xsim tb_video_pipeline_output_mode \
  "$hdl/axis_video_nn_scaler.sv" "$hdl/axis_rgb888.sv" \
  "$hdl/axis_video_mux3.sv" "$hdl/video_bram_rgb565_reader.sv" \
  "$hdl/axi_lite_video_regs.sv" "$hdl/video_pipeline_v1_0.sv" \
  "$repo_root/tests/rtl/tb_video_pipeline_output_mode.sv"
run_xsim tb_video_pipeline_static_profile \
  "$hdl/axis_video_nn_scaler.sv" "$hdl/axis_rgb888.sv" \
  "$hdl/axis_video_mux3.sv" "$hdl/video_bram_rgb565_reader.sv" \
  "$hdl/axi_lite_video_regs.sv" "$hdl/video_pipeline_v1_0.sv" \
  "$repo_root/tests/rtl/tb_video_pipeline_static_profile.sv"
run_xsim tb_hdmi_runtime_status \
  "$hdl/embedded_video_ip_reset_sync.sv" "$hdl/hdmi_runtime_status.sv" \
  "$repo_root/tests/rtl/tb_hdmi_runtime_status.sv"
run_xsim tb_hdmi_gain_bus_cdc \
  "$hdl/embedded_video_ip_reset_sync.sv" "$hdl/hdmi_gain_bus_cdc.sv" \
  "$repo_root/tests/rtl/tb_hdmi_gain_bus_cdc.sv"
run_xsim tb_hdmi_mode_transition_ctrl \
  "$hdl/hdmi_mode_transition_ctrl.sv" "$repo_root/tests/rtl/tb_hdmi_mode_transition_ctrl.sv"
run_xsim tb_hdmi_boot_timing_path \
  "$hdl/hdmi_video_timing_gen.sv" "$hdl/hdmi_mode_transition_ctrl.sv" \
  "$repo_root/tests/rtl/tb_hdmi_boot_timing_path.sv"
run_xsim tb_hdmi_video_timing_gen \
  "$hdl/hdmi_video_timing_gen.sv" "$repo_root/tests/rtl/tb_hdmi_video_timing_gen.sv"
run_xsim tb_hdmi_clock_profile_mux \
  "$hdl/hdmi_clock_profile_mux.sv" "$repo_root/tests/rtl/tb_hdmi_clock_profile_mux.sv"

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
  "$hdl/hdmi_packet_assembler.sv" "$hdl/hdmi_bch_ecc.sv" "$hdl/hdmi_avi_infoframe.sv" \
  "$repo_root/tests/rtl/tb_hdmi_packet_assembler.sv"
run_xsim tb_hdmi_line_slot_scheduler \
  "$hdl/hdmi_line_slot_scheduler.sv" "$repo_root/tests/rtl/tb_hdmi_line_slot_scheduler.sv"
run_xsim tb_hdmi_tmds_mode_mux \
  "$hdl/hdmi_tmds_mode_mux.sv" "$hdl/hdmi_terc4_encoder.sv" \
  "$repo_root/tests/rtl/tb_hdmi_tmds_mode_mux.sv"
run_xsim tb_hdmi_video_encoder \
  "$hdl/hdmi_tmds_video_encoder.sv" "$repo_root/tests/rtl/tb_hdmi_video_encoder.sv"
run_xsim tb_hdmi_color_avi_infoframe \
  "$hdl/hdmi_avi_infoframe.sv" "$repo_root/tests/rtl/tb_hdmi_color_avi_infoframe.sv"
run_xsim tb_hdmi_7series_output_serdes \
  "$hdl/hdmi_tmds_video_encoder.sv" --define-synthesis \
  "$repo_root/tests/rtl/tb_hdmi_7series_output_serdes.sv"
run_xsim tb_hdmi_pcm_packet_source \
  "$hdl/hdmi_pcm_packet_source.sv" "$hdl/audio_pcm_async_fifo.sv" \
  "$hdl/audio_gain_q15.sv" "$hdl/hdmi_audio_sample_packet.sv" \
  "$hdl/hdmi_acr_packet.sv" "$hdl/hdmi_audio_infoframe.sv" \
  "$hdl/hdmi_avi_infoframe.sv" \
  "$repo_root/tests/rtl/tb_hdmi_pcm_packet_source.sv"
run_xsim tb_hdmi_pcm_profile_rates \
  "$hdl/hdmi_pcm_packet_source.sv" "$hdl/audio_pcm_async_fifo.sv" \
  "$hdl/audio_gain_q15.sv" "$hdl/hdmi_audio_sample_packet.sv" \
  "$hdl/hdmi_acr_packet.sv" "$hdl/hdmi_audio_infoframe.sv" \
  "$hdl/hdmi_avi_infoframe.sv" "$repo_root/tests/rtl/tb_hdmi_pcm_profile_rates.sv"
run_xsim tb_embedded_video_ip_7series_tx \
  "$hdl/embedded_video_ip_7series_tx.sv" "$hdl/embedded_video_ip_reset_sync.sv" \
  "$hdl/hdmi_line_slot_scheduler.sv" "$hdl/hdmi_pcm_packet_source.sv" \
  "$hdl/hdmi_packet_assembler.sv" "$hdl/hdmi_tmds_video_encoder.sv" \
  "$hdl/hdmi_tmds_mode_mux.sv" "$hdl/hdmi_terc4_encoder.sv" \
  "$hdl/hdmi_bch_ecc.sv" "$hdl/hdmi_audio_sample_packet.sv" \
  "$hdl/hdmi_audio_infoframe.sv" "$hdl/hdmi_avi_infoframe.sv" "$hdl/hdmi_acr_packet.sv" \
  "$hdl/audio_pcm_async_fifo.sv" "$hdl/audio_gain_q15.sv" \
  "$repo_root/tests/rtl/tb_embedded_video_ip_7series_tx.sv"

gcc -std=c99 -Wall -Wextra -Werror -pedantic \
  -I"$repo_root/software" "$repo_root/software/video_out.c" \
  "$repo_root/tests/host/test_video_out.c" -o "$out_root/test_video_out"
"$out_root/test_video_out"
"$python_bin" --version
"$python_bin" -m unittest discover -s "$repo_root/tests/host" -v
echo "VIDEO_TESTS_PASS"
