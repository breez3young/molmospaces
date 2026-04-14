#!/bin/bash

set -euo pipefail

export MUJOCO_GL=egl
export PYOPENGL_PLATFORM=egl
export MUJOCO_EGL_DEVICE_ID=0
export JAX_PLATFORMS=cpu

export MUJOCO_INSTALL_DIR="$(python - <<'PY'
import pathlib
import mujoco

print(pathlib.Path(mujoco.__file__).resolve().parent)
PY
)"

export MLSPACES_ASSETS_DIR=/gemini/platform/public/embodiedAI/users/zhangyang/workspace/molmospaces/assets
export WANDB_API_KEY=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
prts_config=molmo_spaces.evaluation.configs.evaluation_configs:PRTSPolicyEvalConfig

python - <<'PY'
import ctypes
import sys

try:
  ctypes.CDLL("libvulkan.so.1")
except OSError as e:
  print("[ERROR] Missing Vulkan runtime: libvulkan.so.1")
  print(f"        {e}")
  print("[FIX]   sudo apt-get update && sudo apt-get install -y libvulkan1 mesa-vulkan-drivers")
  sys.exit(1)
PY

if [[ ! -f "${MUJOCO_INSTALL_DIR}/pbr.filamat" ]]; then
  echo "[ERROR] MuJoCo filament resource missing: ${MUJOCO_INSTALL_DIR}/pbr.filamat"
  echo "[FIX]   Reinstall mujoco in this env: pip install -U --force-reinstall mujoco"
  exit 1
fi

# close
python molmo_spaces/evaluation/eval_main.py $prts_config \
  --benchmark_dir assets/benchmarks/molmospaces-bench-v1/ithor/FrankaCloseDataGenConfig/FrankaCloseDataGenConfig_20260123_json_benchmark \
  --idx 0
  # --num_workers 8

# open
# python molmo_spaces/evaluation/eval_main.py $prts_config \
#   --benchmark_dir assets/benchmarks/molmospaces-bench-v1/ithor/FrankaOpenDataGenConfig/FrankaOpenDataGenConfig_20260123_json_benchmark

# # pick
# python molmo_spaces/evaluation/eval_main.py $prts_config \
#   --benchmark_dir assets/benchmarks/molmospaces-bench-v1/procthor-10k/FrankaPickDroidMiniBench/FrankaPickDroidMiniBench_json_benchmark_20251231

# # pnp
# python molmo_spaces/evaluation/eval_main.py $prts_config \
#   --benchmark_dir assets/benchmarks/molmospaces-bench-v1/procthor-10k/FrankaPickandPlaceDroidMiniBench/FrankaPickandPlaceDroidMiniBench_20260111_json_benchmark