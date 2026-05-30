#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
PIPELINE_SCRIPT="${ROOT_DIR}/run_full_pipeline_seulex_inproc.sh"
CASE_DIR="${ROOT_DIR}/test_input/c99_batch_cases"
LOG_DIR="${ROOT_DIR}/output/c99_batch_logs"
mkdir -p "${LOG_DIR}"

if [[ ! -x "${PIPELINE_SCRIPT}" ]]; then
  echo "[error] pipeline script not executable: ${PIPELINE_SCRIPT}" >&2
  exit 1
fi

cases=(
  "case01_ptr_array_controlflow.c"
  "case02_loop_if.c"
  "case03_array_and_call.c"
  "case04_nested_control.c"
  "case05_recursion_like_call_chain.c"
)

declare -a passed=()
declare -a failed=()

echo "============= C99 batch tests start ============="

for case_file in "${cases[@]}"; do
  input_path="${CASE_DIR}/${case_file}"
  case_log="${LOG_DIR}/${case_file%.c}.log"

  echo
  echo "============= running ${case_file} ============="
  if "${PIPELINE_SCRIPT}" "${input_path}" --skip-repo-check 2>&1 | tee "${case_log}"; then
    passed+=("${case_file}")
    echo "[PASS] ${case_file}"
  else
    failed+=("${case_file}")
    echo "[FAIL] ${case_file} (see ${case_log})"
  fi
  echo "============= done ${case_file} ============="
done

echo
echo "============= C99 batch summary ============="
echo "passed: ${#passed[@]}"
for x in "${passed[@]}"; do echo "  - ${x}"; done
echo "failed: ${#failed[@]}"
for x in "${failed[@]}"; do echo "  - ${x}"; done

if [[ ${#failed[@]} -ne 0 ]]; then
  exit 1
fi
