#!/bin/bash
#
# One-click aggregator for the OLD/flat eval_output layout, where each
# timestamped run is one task and all task runs sit side-by-side:
#
#   <eval_output_dir>/<timestamp>/house_*
#
# Task type is inferred from the benchmark name in running_log.log:
#   FrankaCloseDataGenConfig            -> close
#   FrankaOpenDataGenConfig             -> open
#   FrankaPickDroidMiniBench            -> pick
#   FrankaPickandPlaceDroidMiniBench    -> pnp
#
# For each task it picks the latest timestamped run and exports a CSV.
#
# Usage:
#   bash scripts/aggregate_results_old.sh <eval_output_dir> [policy_name] [tasks] [output_dir]
#
# Example:
#   bash scripts/aggregate_results_old.sh eval_output/PRTS-full-quantile-PRTSPolicyEvalConfig

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

EVAL_OUTPUT_DIR="${1:?usage: aggregate_results_old.sh <eval_output_dir> [policy_name] [tasks] [output_dir]}"
POLICY_NAME="${2:-PRTS}"
TASKS="${3:-pick,pnp,open,close}"
OUTPUT_DIR="${4:-${EVAL_OUTPUT_DIR}/csv_results}"

mkdir -p "${OUTPUT_DIR}"

IFS=',' read -ra TASK_LIST <<< "${TASKS}"

echo "[aggregate_results_old] eval_output_dir = ${EVAL_OUTPUT_DIR}"
echo "[aggregate_results_old] policy_name     = ${POLICY_NAME}"
echo "[aggregate_results_old] tasks           = ${TASKS}"
echo "[aggregate_results_old] output_dir      = ${OUTPUT_DIR}"
echo

POLICY_LOWER="$(echo "${POLICY_NAME}" | tr '[:upper:]' '[:lower:]')"

bench_to_task() {
    case "$1" in
        *FrankaCloseDataGenConfig*) echo "close" ;;
        *FrankaOpenDataGenConfig*) echo "open" ;;
        *FrankaPickandPlaceDroidMiniBench*) echo "pnp" ;;
        *FrankaPickDroidMiniBench*) echo "pick" ;;
        *) echo "" ;;
    esac
}

declare -A TASK_RUN  # task -> latest matching run dir

for RUN_DIR in $(ls -1d "${EVAL_OUTPUT_DIR}"/*/ 2>/dev/null | sort); do
    RUN_DIR="${RUN_DIR%/}"
    LOG="${RUN_DIR}/running_log.log"
    [ -f "${LOG}" ] || continue
    BENCH=$(grep -oE "Franka[A-Za-z]+(DataGenConfig|MiniBench)" "${LOG}" | head -1)
    TASK=$(bench_to_task "${BENCH}")
    [ -z "${TASK}" ] && continue
    # Sorted by timestamp ascending -> last write wins (latest run).
    TASK_RUN["${TASK}"]="${RUN_DIR}"
done

FAILED=()
for TASK in "${TASK_LIST[@]}"; do
    RUN="${TASK_RUN[${TASK}]:-}"
    if [ -z "${RUN}" ]; then
        echo "[skip] ${TASK}: no run dir found under ${EVAL_OUTPUT_DIR}"
        FAILED+=("${TASK}")
        continue
    fi
    OUTPUT_CSV="${OUTPUT_DIR}/${TASK}_${POLICY_LOWER}.csv"
    echo "=== ${TASK} ==="
    echo "  run    : ${RUN}"
    echo "  csv    : ${OUTPUT_CSV}"
    python scripts/benchmarks/eval_to_csv.py \
        "${RUN}" \
        "${POLICY_NAME}" \
        --success-condition both \
        --output-csv "${OUTPUT_CSV}"
    echo
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "[aggregate_results_old] skipped tasks: ${FAILED[*]}"
fi
echo "[aggregate_results_old] done. CSVs in: ${OUTPUT_DIR}"
