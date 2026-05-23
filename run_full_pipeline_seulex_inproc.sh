#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
SEULEX_DIR="${ROOT_DIR}/src/lexer_seulex"
YACC_DIR="${ROOT_DIR}/src/parser_c99_yacc"
BACKEND_DIR="${ROOT_DIR}/src/backend_intermediate_codegen"
OUT_DIR="${ROOT_DIR}/output/seulex_codegen_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT_DIR}"
BUILD_DIR="${OUT_DIR}/build"
LOG_DIR="${OUT_DIR}/logs"
REPORT_DIR="${OUT_DIR}/reports"
mkdir -p "${BUILD_DIR}" "${LOG_DIR}" "${REPORT_DIR}"

banner() {
  printf '\n==================== %s ====================\n' "$1"
}

usage() {
  cat <<USAGE
Usage:
  $0 <input.c> [--lex path/to/c99.l] [--yacc path/to/c99.y] [--frontend-only]
USAGE
}

preflight_check_paths() {
  local failed=0
  if [[ ! -d "${SEULEX_DIR}" ]]; then
    echo "[error] lexer_seulex dir not found: ${SEULEX_DIR}" >&2
    failed=1
  fi
  if [[ ! -d "${YACC_DIR}" ]]; then
    echo "[error] parser_c99_yacc dir not found: ${YACC_DIR}" >&2
    failed=1
  fi
  if [[ ! -f "${DRIVER_CPP}" ]]; then
    echo "[error] driver cpp not found: ${DRIVER_CPP}" >&2
    failed=1
  fi
  if [[ ${failed} -ne 0 ]]; then
    echo "[hint] repository layout is invalid or submodules are missing." >&2
    echo "[hint] try: git submodule update --init --recursive" >&2
    exit 1
  fi
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

INPUT_C=""
LEX_FILE="${ROOT_DIR}/test_input/c99.l"
YACC_FILE="${ROOT_DIR}/test_input/c99.y"
FRONTEND_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lex)
      shift; LEX_FILE="$1" ;;
    --yacc)
      shift; YACC_FILE="$1" ;;
    --frontend-only)
      FRONTEND_ONLY=1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      if [[ -z "${INPUT_C}" ]]; then INPUT_C="$1"; else echo "multiple input files"; exit 1; fi ;;
  esac
  shift
done

if [[ -z "${INPUT_C}" || ! -f "${INPUT_C}" ]]; then
  echo "input C file not found: ${INPUT_C}" >&2
  exit 1
fi
if [[ ! -f "${LEX_FILE}" || ! -f "${YACC_FILE}" ]]; then
  echo "lex/yacc file not found" >&2
  exit 1
fi

SEULEX_BIN="${SEULEX_DIR}/build/SeuLex"
YACC_TOOL="${YACC_DIR}/build/src/yacc_parse_tool"
DRIVER_CPP="${ROOT_DIR}/tool/seulex_yacc_codegen_driver.cpp"
ENV_SYNC_TOOL="${ROOT_DIR}/tool/check_env_and_sync.sh"
VIS_PIPELINE_TOOL="${ROOT_DIR}/tool/prepare_yacc_visualization.sh"
CACHE_ROOT="${ROOT_DIR}/.cache/seulex_codegen"

banner "路径与输入"
echo "[info] input: ${INPUT_C}"
echo "[info] lex:   ${LEX_FILE}"
echo "[info] yacc:  ${YACC_FILE}"
echo "[info] out:   ${OUT_DIR}"
mkdir -p "${CACHE_ROOT}"

cp "${INPUT_C}" "${OUT_DIR}/input.c"
cp "${OUT_DIR}/input.c" "${BUILD_DIR}/input.normalized.c"
# c99 frontend does not support preprocessor directives, drop leading # lines.
sed -i '/^[[:space:]]*#/d' "${BUILD_DIR}/input.normalized.c"
if [[ -s "${BUILD_DIR}/input.normalized.c" ]]; then
  LAST_BYTE_HEX=$(tail -c 1 "${BUILD_DIR}/input.normalized.c" | od -An -t x1 | tr -d ' \n')
  if [[ "${LAST_BYTE_HEX}" != "0a" ]]; then
    printf '\n' >> "${BUILD_DIR}/input.normalized.c"
    echo "[info] input normalized: appended trailing newline"
  fi
fi

banner "0/9 env check & repo sync"
if [[ -x "${ENV_SYNC_TOOL}" ]]; then
  if [[ "${FRONTEND_ONLY}" -eq 1 ]]; then
    "${ENV_SYNC_TOOL}" --root "${ROOT_DIR}" --frontend-only
  else
    "${ENV_SYNC_TOOL}" --root "${ROOT_DIR}"
  fi
else
  echo "[warn] env/sync tool not found: ${ENV_SYNC_TOOL}"
fi
preflight_check_paths

banner "1/9 build tools"
cmake -S "${SEULEX_DIR}" -B "${SEULEX_DIR}/build" -DSEULEX_BUILD_TESTS=ON >/dev/null
cmake --build "${SEULEX_DIR}/build" -j >/dev/null
cmake -S "${YACC_DIR}" -B "${YACC_DIR}/build" >/dev/null
cmake --build "${YACC_DIR}/build" -j >/dev/null

[[ -x "${SEULEX_BIN}" ]] || { echo "SeuLex not found: ${SEULEX_BIN}" >&2; exit 1; }
[[ -x "${YACC_TOOL}" ]] || { echo "yacc_parse_tool not found: ${YACC_TOOL}" >&2; exit 1; }
[[ -f "${DRIVER_CPP}" ]] || { echo "driver cpp not found: ${DRIVER_CPP}" >&2; exit 1; }

echo "[ok] built tools"

banner "2/9 emit parser artifacts"
PIPE_KEY=$(cat "${LEX_FILE}" "${YACC_FILE}" "${DRIVER_CPP}" | sha256sum | awk '{print $1}')
CACHE_DIR="${CACHE_ROOT}/${PIPE_KEY}"
if [[ -f "${CACHE_DIR}/frontend" && -f "${CACHE_DIR}/parser_generated.cpp" && -f "${CACHE_DIR}/lex.yy.c" && -f "${CACHE_DIR}/y.tab.h" && -f "${CACHE_DIR}/token_cases.inc" ]]; then
  banner "2/9 cache restore"
  cp -f "${CACHE_DIR}/parser_generated.cpp" "${OUT_DIR}/parser_generated.cpp"
  cp -f "${CACHE_DIR}/lex.yy.c" "${OUT_DIR}/lex.yy.c"
  cp -f "${CACHE_DIR}/y.tab.h" "${BUILD_DIR}/y.tab.h"
  cp -f "${CACHE_DIR}/token_cases.inc" "${BUILD_DIR}/token_cases.inc"
  cp -f "${CACHE_DIR}/c99.tab.h" "${BUILD_DIR}/c99.tab.h"
  cp -f "${CACHE_DIR}/frontend" "${BUILD_DIR}/frontend"
  echo "[ok] cache hit: restored parser/lexer/frontend"
else
  "${YACC_TOOL}" emit "${YACC_FILE}" \
    --emit-y-tab-h "${BUILD_DIR}/y.tab.h" \
    --emit-token-cases-inc "${BUILD_DIR}/token_cases.inc" \
    --emit-parser-cpp "${OUT_DIR}/parser_generated.cpp" >/dev/null
  cp -f "${BUILD_DIR}/y.tab.h" "${BUILD_DIR}/c99.tab.h"
  echo "[ok] generated: parser_generated.cpp (root), y.tab.h/token_cases.inc (build/)"

  banner "3/9 generate scanner by SeuLex"
  "${SEULEX_BIN}" -o "${OUT_DIR}/lex.yy.c" "${LEX_FILE}" >/dev/null
  # Expose yytext to the fixed driver wrapper.
  sed -i 's/^static char yytext\[/char yytext[/' "${OUT_DIR}/lex.yy.c"
  echo "[ok] generated: lex.yy.c (root)"

  banner "4/9 build fixed frontend"
  cp -f "${DRIVER_CPP}" "${BUILD_DIR}/frontend_codegen_driver.cpp"
  gcc -std=c11 -w -I"${BUILD_DIR}" -Dyylex=raw_yylex -c "${OUT_DIR}/lex.yy.c" -o "${BUILD_DIR}/lex.yy.o"

FRONTEND_COMPAT_OBJ=()
NEED_YYLINENO_COMPAT=0
NEED_COLUMN_COMPAT=0
  if ! rg -n "^[[:space:]]*int[[:space:]]+yylineno[[:space:]]*=" "${LEX_FILE}" >/dev/null 2>&1; then
    NEED_YYLINENO_COMPAT=1
  fi
  if ! rg -n "^[[:space:]]*int[[:space:]]+column[[:space:]]*=" "${LEX_FILE}" >/dev/null 2>&1; then
    NEED_COLUMN_COMPAT=1
  fi
  if [[ ${NEED_YYLINENO_COMPAT} -eq 1 || ${NEED_COLUMN_COMPAT} -eq 1 ]]; then
    : > "${BUILD_DIR}/frontend_compat.c"
    if [[ ${NEED_YYLINENO_COMPAT} -eq 1 ]]; then
      echo "int yylineno = 1;" >> "${BUILD_DIR}/frontend_compat.c"
    fi
    if [[ ${NEED_COLUMN_COMPAT} -eq 1 ]]; then
      echo "int column = 1;" >> "${BUILD_DIR}/frontend_compat.c"
    fi
    gcc -std=c11 -w -c "${BUILD_DIR}/frontend_compat.c" -o "${BUILD_DIR}/frontend_compat.o"
    FRONTEND_COMPAT_OBJ+=("${BUILD_DIR}/frontend_compat.o")
    echo "[info] generated frontend_compat.c for missing lexer globals"
  fi

  g++ -std=c++17 -I"${BUILD_DIR}" \
    "${OUT_DIR}/parser_generated.cpp" \
    "${BUILD_DIR}/frontend_codegen_driver.cpp" \
    "${BUILD_DIR}/lex.yy.o" \
    "${FRONTEND_COMPAT_OBJ[@]}" \
    -o "${BUILD_DIR}/frontend"
  echo "[ok] built: ${BUILD_DIR}/frontend"

  mkdir -p "${CACHE_DIR}"
  cp -f "${OUT_DIR}/parser_generated.cpp" "${CACHE_DIR}/parser_generated.cpp"
  cp -f "${OUT_DIR}/lex.yy.c" "${CACHE_DIR}/lex.yy.c"
  cp -f "${BUILD_DIR}/y.tab.h" "${CACHE_DIR}/y.tab.h"
  cp -f "${BUILD_DIR}/token_cases.inc" "${CACHE_DIR}/token_cases.inc"
  cp -f "${BUILD_DIR}/c99.tab.h" "${CACHE_DIR}/c99.tab.h"
  cp -f "${BUILD_DIR}/frontend" "${CACHE_DIR}/frontend"
  echo "[ok] cache saved: ${CACHE_DIR}"
fi

banner "5/9 run frontend (lexer+parser)"
set +e
"${BUILD_DIR}/frontend" "${BUILD_DIR}/input.normalized.c" "${REPORT_DIR}/runtime.tokens.rich" | tee "${LOG_DIR}/frontend.log"
FRONTEND_RC=${PIPESTATUS[0]}
set -e
echo "[ok] log: ${LOG_DIR}/frontend.log"
echo "[info] frontend rc: ${FRONTEND_RC}"
if [[ ${FRONTEND_RC} -ne 0 ]]; then
  echo "[warn] frontend reported non-zero exit (${FRONTEND_RC})"
fi

echo "[ok] generated: ${REPORT_DIR}/runtime.tokens.rich"
RUN_NAME=$(basename "${OUT_DIR}")
LEGACY_TOKENS_DIR="${ROOT_DIR}/c99-yacc-lr-lalr-practice/contracts/yacc/tokens"
mkdir -p "${LEGACY_TOKENS_DIR}"
cp -f "${REPORT_DIR}/runtime.tokens.rich" "${LEGACY_TOKENS_DIR}/c99_output.tokens"
cp -f "${REPORT_DIR}/runtime.tokens.rich" "${LEGACY_TOKENS_DIR}/c99_${RUN_NAME}.tokens"
echo "[ok] synced legacy token: ${LEGACY_TOKENS_DIR}/c99_output.tokens"
BACKEND_REL_TOKENS_DIR="${BACKEND_DIR}/c99-yacc-lr-lalr-practice/contracts/yacc/tokens"
mkdir -p "${BACKEND_REL_TOKENS_DIR}"
cp -f "${REPORT_DIR}/runtime.tokens.rich" "${BACKEND_REL_TOKENS_DIR}/c99_output.tokens"
cp -f "${REPORT_DIR}/runtime.tokens.rich" "${BACKEND_REL_TOKENS_DIR}/c99_${RUN_NAME}.tokens"
echo "[ok] synced backend-relative token: ${BACKEND_REL_TOKENS_DIR}/c99_output.tokens"

banner "6/9 export parser traces"
VIS_CASE_ID="c99_${RUN_NAME}"
VIS_ARTIFACTS_ROOT="${REPORT_DIR}/artifacts/yacc"
VIS_DATA_ROOT="${YACC_DIR}/visualizer/public/data/v1"
if [[ -x "${VIS_PIPELINE_TOOL}" ]]; then
  "${VIS_PIPELINE_TOOL}" \
    --yacc-tool "${YACC_TOOL}" \
    --yacc-file "${YACC_FILE}" \
    --tokens "${REPORT_DIR}/runtime.tokens.rich" \
    --case "${VIS_CASE_ID}" \
    --artifacts-root "${VIS_ARTIFACTS_ROOT}" \
    --visualizer-data-root "${VIS_DATA_ROOT}"
else
  echo "[warn] visualizer pipeline tool not found: ${VIS_PIPELINE_TOOL}"
fi
cp -f "${VIS_ARTIFACTS_ROOT}/step9/${VIS_CASE_ID}/raw/parse_trace_lalr.tsv" "${REPORT_DIR}/parse_trace_lalr.tsv"
cp -f "${VIS_ARTIFACTS_ROOT}/step9/${VIS_CASE_ID}/raw/parse_reductions_lalr.txt" "${REPORT_DIR}/parse_reductions_lalr.txt"
echo "[ok] generated: ${REPORT_DIR}/parse_trace_lalr.tsv"
echo "[ok] visualizer case: ${VIS_CASE_ID}"
echo "[ok] visualizer data: ${VIS_DATA_ROOT}/${VIS_CASE_ID}"

if [[ "${FRONTEND_ONLY}" -eq 1 ]]; then
  banner "done"
  echo "done(frontend+visualizer only): ${OUT_DIR}"
  exit 0
fi

banner "7/9 backend (maven exec)"
if [[ -f "${BACKEND_DIR}/pom.xml" ]]; then
  (
    cd "${BACKEND_DIR}"
    mvn -q -DskipTests exec:java \
      -Dexec.mainClass=com.compiler.backend.Main \
      -Dexec.args="${REPORT_DIR}"
  ) | tee "${LOG_DIR}/backend.log"
  echo "[ok] backend log: ${LOG_DIR}/backend.log"
else
  echo "backend not found, frontend done: ${OUT_DIR}"
fi

banner "8/9 summary"
echo "[ok] root outputs: ${OUT_DIR}/lex.yy.c ${OUT_DIR}/parser_generated.cpp"
echo "[ok] build dir: ${BUILD_DIR}"
echo "[ok] logs dir:  ${LOG_DIR}"
echo "[ok] report dir:${REPORT_DIR}"

banner "done"
echo "done(frontend+backend): ${OUT_DIR}"
