#!/bin/bash

which python

device_id=3
export MLSPACES_ASSETS_DIR=/data/zhangyang/workspace/molmospaces/assets
export WANDB_API_KEY=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

export PRTS_POLICY_PORT=10301

prts_config=molmo_spaces.evaluation.configs.evaluation_configs:PRTSPolicyEvalConfig

# close
# CUDA_VISIBLE_DEVICES=$device_id python molmo_spaces/evaluation/eval_main.py $prts_config \
#   --benchmark_dir assets/benchmarks/molmospaces-bench-v1/ithor/FrankaCloseDataGenConfig/FrankaCloseDataGenConfig_20260123_json_benchmark \
#   --num_workers 4

# open
# python molmo_spaces/evaluation/eval_main.py $prts_config \
#   --benchmark_dir assets/benchmarks/molmospaces-bench-v1/ithor/FrankaOpenDataGenConfig/FrankaOpenDataGenConfig_20260123_json_benchmark \
#   --num_workers 4

# pick
python molmo_spaces/evaluation/eval_main.py $prts_config \
  --benchmark_dir assets/benchmarks/molmospaces-bench-v1/procthor-10k/FrankaPickDroidMiniBench/FrankaPickDroidMiniBench_json_benchmark_20251231 \
  --num_workers 4

# # pnp
# CUDA_VISIBLE_DEVICES=3 python molmo_spaces/evaluation/eval_main.py $prts_config \
#   --benchmark_dir assets/benchmarks/molmospaces-bench-v1/procthor-10k/FrankaPickandPlaceDroidMiniBench/FrankaPickandPlaceDroidMiniBench_20260111_json_benchmark \
#   --num_workers 4