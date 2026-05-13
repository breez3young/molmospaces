#!/bin/bash
#
# One-click aggregator for molmospaces evaluation results (new layout).
# For each task (pick / pnp / open / close), finds the latest timestamped run
# under <eval_output_dir>/<task>/<config_name>/ and exports a CSV.
#
# Usage:
#   bash scripts/aggregate_results.sh <eval_output_dir> [policy_name] [config_name] [tasks] [output_dir]
#
# Examples:
#   bash scripts/aggregate_results.sh eval_output/prts_droid_full_mean_std
#   bash scripts/aggregate_results.sh eval_output/prts_droid_full_mean_std PRTS
#   bash scripts/aggregate_results.sh eval_output/prts_droid_full_mean_std PRTS PRTSPolicyEvalConfig "pick,pnp,open,close"

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

EVAL_OUTPUT_DIR="${1:?usage: aggregate_results.sh <eval_output_dir> [policy_name] [config_name] [tasks] [output_dir]}"
POLICY_NAME="${2:-PRTS}"
CONFIG_NAME="${3:-PRTSPolicyEvalConfig}"
TASKS="${4:-pick,pnp,open,close}"
OUTPUT_DIR="${5:-${EVAL_OUTPUT_DIR}/csv_results}"

mkdir -p "${OUTPUT_DIR}"

IFS=',' read -ra TASK_LIST <<< "${TASKS}"

echo "[aggregate_results] eval_output_dir = ${EVAL_OUTPUT_DIR}"
echo "[aggregate_results] policy_name     = ${POLICY_NAME}"
echo "[aggregate_results] config_name     = ${CONFIG_NAME}"
echo "[aggregate_results] tasks           = ${TASKS}"
echo "[aggregate_results] output_dir      = ${OUTPUT_DIR}"
echo

FAILED=()
for TASK in "${TASK_LIST[@]}"; do
    TASK_CONFIG_DIR="${EVAL_OUTPUT_DIR}/${TASK}/${CONFIG_NAME}"
    if [ ! -d "${TASK_CONFIG_DIR}" ]; then
        echo "[skip] ${TASK}: not found at ${TASK_CONFIG_DIR}"
        FAILED+=("${TASK}")
        continue
    fi

    LATEST_RUN="$(ls -1d "${TASK_CONFIG_DIR}"/*/ 2>/dev/null | sort | tail -n 1)"
    LATEST_RUN="${LATEST_RUN%/}"
    if [ -z "${LATEST_RUN}" ]; then
        echo "[skip] ${TASK}: no timestamped run dir under ${TASK_CONFIG_DIR}"
        FAILED+=("${TASK}")
        continue
    fi

    POLICY_LOWER="$(echo "${POLICY_NAME}" | tr '[:upper:]' '[:lower:]')"
    OUTPUT_CSV="${OUTPUT_DIR}/${TASK}_${POLICY_LOWER}.csv"

    echo "=== ${TASK} ==="
    echo "  run    : ${LATEST_RUN}"
    echo "  csv    : ${OUTPUT_CSV}"
    python scripts/benchmarks/eval_to_csv.py \
        "${LATEST_RUN}" \
        "${POLICY_NAME}" \
        --success-condition both \
        --output-csv "${OUTPUT_CSV}"
    echo
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "[aggregate_results] skipped tasks: ${FAILED[*]}"
fi
echo "[aggregate_results] done. CSVs in: ${OUTPUT_DIR}"
