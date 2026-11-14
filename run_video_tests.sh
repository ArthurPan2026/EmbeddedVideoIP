#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vivado_bin="${VIVADO_BIN:-/tools/AMDDesignTools/2025.2.1/Vivado/bin}"
out_root="$repo_root/out/tests"
mkdir -p "$out_root"

run_xsim() {
  local name="$1"
  shift
  local run_dir="$out_root/$name"
  mkdir -p "$run_dir"
  (
    cd "$run_dir"
    "$vivado_bin/xvlog" -sv "$@"
    "$vivado_bin/xelab" "$name" -s "${name}_snapshot"
    "$vivado_bin/xsim" "${name}_snapshot" -runall | tee run.log
  )
  if ! grep -q "TEST_PASS:" "$run_dir/run.log"; then
    echo "VIDEO_TEST_FAIL: $name did not report TEST_PASS" >&2
    exit 1
  fi
}

hdl="$repo_root/ip/video_pipeline_1_0/hdl"
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

gcc -std=c99 -Wall -Wextra -Werror -pedantic \
  -I"$repo_root/software" "$repo_root/software/video_out.c" \
  "$repo_root/tests/host/test_video_out.c" -o "$out_root/test_video_out"
"$out_root/test_video_out"
python3 -m unittest discover -s "$repo_root/tests/host" -v
echo "VIDEO_TESTS_PASS"
