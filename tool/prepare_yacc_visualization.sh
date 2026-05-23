#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 --yacc-tool <path> --yacc-file <path> --tokens <path> --case <case_id> \
     --artifacts-root <dir> --visualizer-data-root <dir> [--python python3]
USAGE
}

YACC_TOOL=""
YACC_FILE=""
TOKENS_FILE=""
CASE_ID="c99"
ARTIFACTS_ROOT=""
VIS_DATA_ROOT=""
PYTHON_BIN="python3"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yacc-tool)
      shift; YACC_TOOL="${1:-}" ;;
    --yacc-file)
      shift; YACC_FILE="${1:-}" ;;
    --tokens)
      shift; TOKENS_FILE="${1:-}" ;;
    --case)
      shift; CASE_ID="${1:-}" ;;
    --artifacts-root)
      shift; ARTIFACTS_ROOT="${1:-}" ;;
    --visualizer-data-root)
      shift; VIS_DATA_ROOT="${1:-}" ;;
    --python)
      shift; PYTHON_BIN="${1:-}" ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 1 ;;
  esac
  shift
done

if [[ -z "${YACC_TOOL}" || -z "${YACC_FILE}" || -z "${TOKENS_FILE}" || -z "${ARTIFACTS_ROOT}" || -z "${VIS_DATA_ROOT}" ]]; then
  usage
  exit 1
fi

if [[ ! -x "${YACC_TOOL}" ]]; then
  echo "yacc tool not executable: ${YACC_TOOL}" >&2
  exit 1
fi
if [[ ! -f "${YACC_FILE}" ]]; then
  echo "yacc file not found: ${YACC_FILE}" >&2
  exit 1
fi
if [[ ! -f "${TOKENS_FILE}" ]]; then
  echo "tokens file not found: ${TOKENS_FILE}" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
VIS_PREPARE_PY="${ROOT_DIR}/src/parser_c99_yacc/scripts/yacc_visualizer_prepare.py"

if [[ ! -f "${VIS_PREPARE_PY}" ]]; then
  echo "visualizer convert script not found: ${VIS_PREPARE_PY}" >&2
  exit 1
fi

STEP9_DIR="${ARTIFACTS_ROOT}/step9/${CASE_ID}"
STEP10_DIR="${ARTIFACTS_ROOT}/step10/${CASE_ID}"
mkdir -p "${STEP9_DIR}" "${STEP10_DIR}" "${VIS_DATA_ROOT}"

echo "[vis] export step9 -> ${STEP9_DIR}"
"${YACC_TOOL}" run "${YACC_FILE}" \
  --parse-tokens "${TOKENS_FILE}" \
  --export \
  --export-dir "${STEP9_DIR}" >/dev/null

echo "[vis] export step10 -> ${STEP10_DIR}"
"${YACC_TOOL}" run "${YACC_FILE}" \
  --export \
  --export-dir "${STEP10_DIR}" >/dev/null

echo "[vis] convert artifacts -> frontend data"
"${PYTHON_BIN}" "${VIS_PREPARE_PY}" \
  --case "${CASE_ID}" \
  --artifacts-root "${ARTIFACTS_ROOT}" \
  --output-root "${VIS_DATA_ROOT}" >/dev/null

echo "[vis] done: ${VIS_DATA_ROOT}/${CASE_ID}"
