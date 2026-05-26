#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PATH="${ROOT_DIR}/run_full_pipeline_seulex_inproc.sh"
SEULEX_DIR="${ROOT_DIR}/src/lexer_seulex"
YACC_DIR="${ROOT_DIR}/src/parser_c99_yacc"
BACKEND_DIR="${ROOT_DIR}/src/backend_intermediate_codegen"
OUT_DIR="${ROOT_DIR}/output/$(date +%Y%m%d_%H%M%S_%3N)"
mkdir -p "${OUT_DIR}"
BUILD_DIR="${OUT_DIR}/build"
LOG_DIR="${OUT_DIR}/logs"
REPORT_DIR="${OUT_DIR}/reports"
mkdir -p "${BUILD_DIR}" "${LOG_DIR}" "${REPORT_DIR}"

banner() {
  printf '\n==================== %s ====================\n' "$1"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

usage() {
  cat <<USAGE
Usage:
  $0 <input.c> [--lex path/to/c99.l] [--yacc path/to/c99.y] [--frontend-only] [--skip-repo-check]
USAGE
}

to_abs_path() {
  local p="$1"
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s\n' "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
  fi
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
SKIP_REPO_CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lex)
      shift; LEX_FILE="$1" ;;
    --yacc)
      shift; YACC_FILE="$1" ;;
    --frontend-only)
      FRONTEND_ONLY=1 ;;
    --skip-repo-check)
      SKIP_REPO_CHECK=1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      if [[ -z "${INPUT_C}" ]]; then INPUT_C="$1"; else echo "multiple input files"; exit 1; fi ;;
  esac
  shift
done

INPUT_C=$(to_abs_path "${INPUT_C}")
LEX_FILE=$(to_abs_path "${LEX_FILE}")
YACC_FILE=$(to_abs_path "${YACC_FILE}")

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
ENV_SYNC_TOOL="${ROOT_DIR}/tool/check_env_and_sync.sh"
VIS_PIPELINE_TOOL="${ROOT_DIR}/tool/prepare_yacc_visualization.sh"
CACHE_ROOT="${ROOT_DIR}/.cache"
CACHE_ENTRIES_ROOT="${CACHE_ROOT}/entries"
CACHE_INDEX_ROOT="${CACHE_ROOT}/index"
CACHE_HIT=0
CACHE_REUSED=0
CACHE_KEY=""
CACHE_ENTRY_DIR=""
CACHE_LINK_PATH="${OUT_DIR}/cache"
MANIFEST_PATH="${OUT_DIR}/manifest.json"
RUN_ID=$(basename "${OUT_DIR}")

banner "路径与输入"
echo "[info] input: ${INPUT_C}"
echo "[info] lex:   ${LEX_FILE}"
echo "[info] yacc:  ${YACC_FILE}"
echo "[info] out:   ${OUT_DIR}"
mkdir -p "${CACHE_ROOT}" "${CACHE_ENTRIES_ROOT}" "${CACHE_INDEX_ROOT}"

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

INPUT_HASH=$(sha256_file "${BUILD_DIR}/input.normalized.c")
LEX_HASH=$(sha256_file "${LEX_FILE}")
YACC_HASH=$(sha256_file "${YACC_FILE}")
SCRIPT_HASH=$(sha256_file "${SCRIPT_PATH}")

banner "0/9 env check & repo sync"
if [[ -x "${ENV_SYNC_TOOL}" ]]; then
  if [[ "${FRONTEND_ONLY}" -eq 1 ]]; then
    if [[ "${SKIP_REPO_CHECK}" -eq 1 ]]; then
      "${ENV_SYNC_TOOL}" --root "${ROOT_DIR}" --frontend-only --skip-repo-check
    else
      "${ENV_SYNC_TOOL}" --root "${ROOT_DIR}" --frontend-only
    fi
  else
    if [[ "${SKIP_REPO_CHECK}" -eq 1 ]]; then
      "${ENV_SYNC_TOOL}" --root "${ROOT_DIR}" --skip-repo-check
    else
      "${ENV_SYNC_TOOL}" --root "${ROOT_DIR}"
    fi
  fi
else
  echo "[warn] env/sync tool not found: ${ENV_SYNC_TOOL}"
fi
preflight_check_paths

banner "1/9 build tools"
cmake -S "${SEULEX_DIR}" -B "${SEULEX_DIR}/build" -DSEULEX_BUILD_TESTS=ON 2>&1 | tee "${LOG_DIR}/cmake_seulex_config.log"
cmake --build "${SEULEX_DIR}/build" -j 2>&1 | tee "${LOG_DIR}/cmake_seulex_build.log"
cmake -S "${YACC_DIR}" -B "${YACC_DIR}/build" 2>&1 | tee "${LOG_DIR}/cmake_yacc_config.log"
cmake --build "${YACC_DIR}/build" -j 2>&1 | tee "${LOG_DIR}/cmake_yacc_build.log"

[[ -x "${SEULEX_BIN}" ]] || { echo "SeuLex not found: ${SEULEX_BIN}" >&2; exit 1; }
[[ -x "${YACC_TOOL}" ]] || { echo "yacc_parse_tool not found: ${YACC_TOOL}" >&2; exit 1; }

echo "[ok] built tools"

SEULEX_BIN_HASH=$(sha256_file "${SEULEX_BIN}")
YACC_TOOL_HASH=$(sha256_file "${YACC_TOOL}")
KEY_MATERIAL="${INPUT_HASH}:${LEX_HASH}:${YACC_HASH}:${SCRIPT_HASH}:${SEULEX_BIN_HASH}:${YACC_TOOL_HASH}"
if command -v sha256sum >/dev/null 2>&1; then
  CACHE_KEY=$(printf '%s' "${KEY_MATERIAL}" | sha256sum | awk '{print $1}')
else
  CACHE_KEY=$(printf '%s' "${KEY_MATERIAL}" | shasum -a 256 | awk '{print $1}')
fi
CACHE_ENTRY_DIR="${CACHE_ENTRIES_ROOT}/${CACHE_KEY}"
mkdir -p "${CACHE_ENTRY_DIR}"

ln -sfn "${CACHE_ENTRY_DIR}" "${CACHE_LINK_PATH}"
echo "[ok] cache link: ${CACHE_LINK_PATH} -> ${CACHE_ENTRY_DIR}"
echo "[info] cache key: ${CACHE_KEY}"

if [[ -f "${CACHE_ENTRY_DIR}/meta.json" && -f "${CACHE_ENTRY_DIR}/payload/reports/runtime.tokens.rich" && -f "${CACHE_ENTRY_DIR}/payload/parser_generated.cpp" ]]; then
  CACHE_HIT=1
fi
if [[ ${CACHE_HIT} -eq 1 ]]; then
  echo "[cache] hit: ${CACHE_KEY}"
else
  echo "[cache] miss: ${CACHE_KEY}"
fi

banner "2/9 emit parser headers"
if [[ ${CACHE_HIT} -eq 1 ]]; then
  CACHE_REUSED=1
  cp -af "${CACHE_ENTRY_DIR}/payload/." "${OUT_DIR}/"
  echo "[cache] restored payload to output: ${OUT_DIR}"
else
  "${YACC_TOOL}" emit "${YACC_FILE}" \
    --emit-y-tab-h "${BUILD_DIR}/y.tab.h" \
    --emit-token-cases-inc "${BUILD_DIR}/token_cases.inc" \
    --emit-parser-cpp "${OUT_DIR}/parser_generated.cpp" 2>&1 | tee "${LOG_DIR}/yacc_emit.log"
  cp -f "${BUILD_DIR}/y.tab.h" "${BUILD_DIR}/c99.tab.h"
  echo "[ok] generated: parser_generated.cpp (root), y.tab.h/token_cases.inc (build/)"

  banner "3/9 generate scanner by SeuLex"
  "${SEULEX_BIN}" -o "${OUT_DIR}/lex.yy.c" "${LEX_FILE}" 2>&1 | tee "${LOG_DIR}/seulex_emit.log"
  # Expose yytext for token dumper linkage.
  sed -i 's/^static char yytext\[/char yytext[/' "${OUT_DIR}/lex.yy.c"
  # SeuLex output may call helper functions before their definitions under -std=c11.
  # Inject forward declarations and an error() fallback without modifying .l/.y sources.
  if ! rg -n "^[[:space:]]*void[[:space:]]+comment[[:space:]]*\\(void\\)[[:space:]]*;" "${OUT_DIR}/lex.yy.c" >/dev/null 2>&1; then
    sed -i '/#include ".*tab.h"/a\
void comment(void);\
int check_type(void);\
void error(const char *msg);' "${OUT_DIR}/lex.yy.c"
  fi
  if ! rg -n "^[[:space:]]*void[[:space:]]+error[[:space:]]*\\(" "${OUT_DIR}/lex.yy.c" >/dev/null 2>&1; then
    cat >> "${OUT_DIR}/lex.yy.c" <<'EOF'

void error(const char *msg)
{
    fprintf(stderr, "error: %s\n", msg);
    exit(1);
}
EOF
  fi
  echo "[ok] generated: lex.yy.c (root)"

  banner "5/9 dump full tokens (lexer-only)"
  TOKEN_DUMP_MAIN_C="${BUILD_DIR}/token_dump_main.c"
  TOKEN_DUMPER_BIN="${BUILD_DIR}/token_dumper"
  cat > "${TOKEN_DUMP_MAIN_C}" <<'C_EOF'
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

#include "y.tab.h"

int yylex(void);
extern char yytext[];
extern int yyleng;
extern int yylineno;
extern int column;

void error(const char *s) {
  if (s) {
    fprintf(stderr, "lexer error: %s\n", s);
  }
}

static const char *token_name(int tok) {
  switch (tok) {
#include "token_cases.inc"
    default:
      return NULL;
  }
}

static void printable_char_token(int tok, char buf[16]) {
  unsigned char ch = (unsigned char)tok;
  if (ch == '\\' || ch == '\'') {
    snprintf(buf, 16, "'%c%c'", '\\', ch);
  } else if (isprint(ch)) {
    snprintf(buf, 16, "'%c'", ch);
  } else {
    snprintf(buf, 16, "'\\x%02X'", ch);
  }
}

static void write_escaped_lexeme(FILE *out, const char *src) {
  const unsigned char *p = (const unsigned char *)src;
  while (*p) {
    unsigned char ch = *p++;
    if (ch == '\\') {
      fputs("\\\\", out);
    } else if (ch == '"') {
      fputs("\\\"", out);
    } else if (ch == '\n') {
      fputs("\\n", out);
    } else if (ch == '\t') {
      fputs("\\t", out);
    } else if (ch == '\r') {
      fputs("\\r", out);
    } else if (ch == ' ') {
      fputs("\\s", out);
    } else {
      fputc((int)ch, out);
    }
  }
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "Usage: %s <input.c> <out.tokens>\n", argv[0]);
    return 1;
  }

  if (!freopen(argv[1], "rb", stdin)) {
    perror("freopen stdin");
    return 1;
  }

  FILE *out = fopen(argv[2], "wb");
  if (!out) {
    perror("open out.tokens");
    return 1;
  }

  int tok;
  while ((tok = yylex()) != 0) {
    const char *name = token_name(tok);
    char char_name_buf[16];
    int tok_col;
    if (!name) {
      if (tok >= 0 && tok < 256) {
        printable_char_token(tok, char_name_buf);
        name = char_name_buf;
      } else {
        fprintf(stderr, "Unknown token id: %d\n", tok);
        fclose(out);
        return 2;
      }
    }

    tok_col = column - yyleng + 1;
    if (tok_col < 1) {
      tok_col = 1;
    }
    fprintf(out, "%s ", name);
    write_escaped_lexeme(out, yytext);
    fprintf(out, " %d %d\n", yylineno, tok_col);
  }

  fclose(out);
  return 0;
}
C_EOF

  TOKEN_DUMP_COMPAT_OBJ=""
  if ! rg -n "^[[:space:]]*int[[:space:]]+yylineno[[:space:]]*=" "${LEX_FILE}" >/dev/null 2>&1 || \
     ! rg -n "^[[:space:]]*int[[:space:]]+column[[:space:]]*=" "${LEX_FILE}" >/dev/null 2>&1 || \
     ! rg -n "^[[:space:]]*YYSTYPE[[:space:]]+yylval[[:space:]]*(=|;)" "${LEX_FILE}" >/dev/null 2>&1; then
    TOKEN_DUMP_COMPAT_SRC="${BUILD_DIR}/token_dump_compat.c"
    TOKEN_DUMP_COMPAT_OBJ="${BUILD_DIR}/token_dump_compat.o"
    : > "${TOKEN_DUMP_COMPAT_SRC}"
    echo "#include \"y.tab.h\"" >> "${TOKEN_DUMP_COMPAT_SRC}"
    if ! rg -n "^[[:space:]]*int[[:space:]]+yylineno[[:space:]]*=" "${LEX_FILE}" >/dev/null 2>&1; then
      echo "int yylineno = 1;" >> "${TOKEN_DUMP_COMPAT_SRC}"
    fi
    if ! rg -n "^[[:space:]]*int[[:space:]]+column[[:space:]]*=" "${LEX_FILE}" >/dev/null 2>&1; then
      echo "int column = 1;" >> "${TOKEN_DUMP_COMPAT_SRC}"
    fi
    if ! rg -n "^[[:space:]]*YYSTYPE[[:space:]]+yylval[[:space:]]*(=|;)" "${LEX_FILE}" >/dev/null 2>&1; then
      echo "YYSTYPE yylval;" >> "${TOKEN_DUMP_COMPAT_SRC}"
    fi
    gcc -std=c11 -w -c "${TOKEN_DUMP_COMPAT_SRC}" -o "${TOKEN_DUMP_COMPAT_OBJ}"
  fi

  cc -std=gnu89 -w -I"${BUILD_DIR}" \
    "${TOKEN_DUMP_MAIN_C}" \
    "${OUT_DIR}/lex.yy.c" \
    ${TOKEN_DUMP_COMPAT_OBJ:+${TOKEN_DUMP_COMPAT_OBJ}} \
    -lfl -o "${TOKEN_DUMPER_BIN}"
  "${TOKEN_DUMPER_BIN}" "${BUILD_DIR}/input.normalized.c" "${REPORT_DIR}/runtime.tokens.rich"
  echo "[ok] generated(full token stream): ${REPORT_DIR}/runtime.tokens.rich"

  banner "6/9 run frontend (lexer+parser)"
  VIS_CASE_ID="c99_${RUN_ID}"
  VIS_STEP9_DIR="${REPORT_DIR}/artifacts/yacc/step9/${VIS_CASE_ID}"
  set +e
  "${YACC_TOOL}" run "${YACC_FILE}" \
    --parse-tokens "${REPORT_DIR}/runtime.tokens.rich" \
    --export-dir "${VIS_STEP9_DIR}" 2>&1 | tee "${LOG_DIR}/frontend.log"
  FRONTEND_RC=${PIPESTATUS[0]}
  set -e
  echo "[ok] log: ${LOG_DIR}/frontend.log"
  echo "[info] frontend rc: ${FRONTEND_RC}"
  if [[ ${FRONTEND_RC} -ne 0 ]]; then
    echo "[warn] frontend reported non-zero exit (${FRONTEND_RC})"
  fi

  cp -f "${REPORT_DIR}/runtime.tokens.rich" "${REPORT_DIR}/runtime.tokens.consumed.rich"
  echo "[ok] generated(consumed token stream): ${REPORT_DIR}/runtime.tokens.consumed.rich"

  banner "7/9 export parser traces"
  VIS_ARTIFACTS_ROOT="${REPORT_DIR}/artifacts/yacc"
  VIS_DATA_ROOT="${YACC_DIR}/visualizer/public/data/v1"
  VIS_LATEST_FILE="${VIS_DATA_ROOT}/latest.json"
  if [[ -x "${VIS_PIPELINE_TOOL}" ]]; then
    "${VIS_PIPELINE_TOOL}" \
      --yacc-tool "${YACC_TOOL}" \
      --yacc-file "${YACC_FILE}" \
      --tokens "${REPORT_DIR}/runtime.tokens.rich" \
      --case "${VIS_CASE_ID}" \
      --artifacts-root "${VIS_ARTIFACTS_ROOT}" \
      --visualizer-data-root "${VIS_DATA_ROOT}"
    cat > "${VIS_LATEST_FILE}" <<EOF
{
  "case_id": "${VIS_CASE_ID}",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    echo "[ok] visualizer latest pointer: ${VIS_LATEST_FILE} -> ${VIS_CASE_ID}"
  else
    echo "[warn] visualizer pipeline tool not found: ${VIS_PIPELINE_TOOL}"
  fi
  cp -f "${VIS_ARTIFACTS_ROOT}/step9/${VIS_CASE_ID}/raw/parse_trace_lalr.tsv" "${REPORT_DIR}/parse_trace_lalr.tsv"
  cp -f "${VIS_ARTIFACTS_ROOT}/step9/${VIS_CASE_ID}/raw/parse_reductions_lalr.txt" "${REPORT_DIR}/parse_reductions_lalr.txt"
  echo "[ok] generated: ${REPORT_DIR}/parse_trace_lalr.tsv"
  echo "[ok] visualizer case: ${VIS_CASE_ID}"
  echo "[ok] visualizer data: ${VIS_DATA_ROOT}/${VIS_CASE_ID}"

  rm -rf "${CACHE_ENTRY_DIR}/payload.tmp"
  mkdir -p "${CACHE_ENTRY_DIR}/payload.tmp"
  cp -af "${OUT_DIR}/lex.yy.c" "${CACHE_ENTRY_DIR}/payload.tmp/" 2>/dev/null || true
  cp -af "${OUT_DIR}/parser_generated.cpp" "${CACHE_ENTRY_DIR}/payload.tmp/" 2>/dev/null || true
  cp -af "${OUT_DIR}/build" "${CACHE_ENTRY_DIR}/payload.tmp/" 2>/dev/null || true
  cp -af "${OUT_DIR}/reports" "${CACHE_ENTRY_DIR}/payload.tmp/" 2>/dev/null || true
  rm -rf "${CACHE_ENTRY_DIR}/payload"
  mv "${CACHE_ENTRY_DIR}/payload.tmp" "${CACHE_ENTRY_DIR}/payload"
fi

RUN_NAME="${RUN_ID}"
VIS_CASE_ID="c99_${RUN_NAME}"
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

UTC_NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "${MANIFEST_PATH}" <<EOF
{
  "run_id": "$(json_escape "${RUN_ID}")",
  "timestamp_utc": "$(json_escape "${UTC_NOW}")",
  "input_file": "$(json_escape "${INPUT_C}")",
  "lex_file": "$(json_escape "${LEX_FILE}")",
  "yacc_file": "$(json_escape "${YACC_FILE}")",
  "cache_key": "$(json_escape "${CACHE_KEY}")",
  "cache_hit": ${CACHE_HIT},
  "cache_reused": ${CACHE_REUSED},
  "cache_entry": "$(json_escape "${CACHE_ENTRY_DIR}")"
}
EOF

cat > "${CACHE_ENTRY_DIR}/meta.json" <<EOF
{
  "cache_key": "$(json_escape "${CACHE_KEY}")",
  "updated_at_utc": "$(json_escape "${UTC_NOW}")",
  "input_hash": "$(json_escape "${INPUT_HASH}")",
  "lex_hash": "$(json_escape "${LEX_HASH}")",
  "yacc_hash": "$(json_escape "${YACC_HASH}")",
  "script_hash": "$(json_escape "${SCRIPT_HASH}")",
  "seulex_bin_hash": "$(json_escape "${SEULEX_BIN_HASH}")",
  "yacc_tool_hash": "$(json_escape "${YACC_TOOL_HASH}")",
  "last_run_id": "$(json_escape "${RUN_ID}")",
  "last_output_dir": "$(json_escape "${OUT_DIR}")"
}
EOF

INDEX_JSON_PATH="${CACHE_INDEX_ROOT}/${CACHE_KEY}.json"
INDEX_LOG_PATH="${CACHE_INDEX_ROOT}/${CACHE_KEY}.runs.log"
printf '%s\t%s\t%s\t%s\n' "${UTC_NOW}" "${RUN_ID}" "${OUT_DIR}" "${MANIFEST_PATH}" >> "${INDEX_LOG_PATH}"

RECENT_ASSOCIATIONS_JSON=""
while IFS=$'\t' read -r rec_ts rec_run rec_out rec_manifest; do
  [[ -z "${rec_ts}" ]] && continue
  rec_item="{\"timestamp_utc\":\"$(json_escape "${rec_ts}")\",\"run_id\":\"$(json_escape "${rec_run}")\",\"output_dir\":\"$(json_escape "${rec_out}")\",\"manifest\":\"$(json_escape "${rec_manifest}")\"}"
  if [[ -n "${RECENT_ASSOCIATIONS_JSON}" ]]; then
    RECENT_ASSOCIATIONS_JSON="${RECENT_ASSOCIATIONS_JSON},${rec_item}"
  else
    RECENT_ASSOCIATIONS_JSON="${rec_item}"
  fi
done < <(tail -n 20 "${INDEX_LOG_PATH}")

cat > "${INDEX_JSON_PATH}" <<EOF
{
  "cache_key": "$(json_escape "${CACHE_KEY}")",
  "updated_at_utc": "$(json_escape "${UTC_NOW}")",
  "last_run_id": "$(json_escape "${RUN_ID}")",
  "last_output_dir": "$(json_escape "${OUT_DIR}")",
  "manifest": "$(json_escape "${MANIFEST_PATH}")",
  "cache_entry": "$(json_escape "${CACHE_ENTRY_DIR}")",
  "recent_associations": [${RECENT_ASSOCIATIONS_JSON}]
}
EOF
echo "[ok] manifest: ${MANIFEST_PATH}"
echo "[ok] cache index: ${INDEX_JSON_PATH}"

if [[ "${FRONTEND_ONLY}" -eq 1 ]]; then
  banner "done"
  echo "done(frontend+visualizer only): ${OUT_DIR}"
  exit 0
fi

banner "8/9 backend (maven exec)"
if [[ -f "${BACKEND_DIR}/pom.xml" ]]; then
  (
    cd "${BACKEND_DIR}"
    mvn -DskipTests compile exec:java \
      -Dexec.mainClass=com.compiler.backend.Main \
      -Dexec.args="${REPORT_DIR}"
  ) 2>&1 | tee "${LOG_DIR}/backend.log"
  echo "[ok] backend log: ${LOG_DIR}/backend.log"
else
  echo "backend not found, frontend done: ${OUT_DIR}"
fi

banner "9/9 summary"
echo "[ok] root outputs: ${OUT_DIR}/lex.yy.c"
echo "[ok] build dir: ${BUILD_DIR}"
echo "[ok] logs dir:  ${LOG_DIR}"
echo "[ok] report dir:${REPORT_DIR}"

banner "done"
echo "done(frontend+backend): ${OUT_DIR}"
