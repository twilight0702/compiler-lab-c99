#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
YACC_DIR="${ROOT_DIR}/src/parser_c99_yacc"
BACKEND_DIR="${ROOT_DIR}/src/backend_intermediate_codegen"
OUT_DIR="${ROOT_DIR}/output/simple_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT_DIR}"

banner() {
  printf '\n==================== %s ====================\n' "$1"
}

usage() {
  cat <<USAGE
Usage:
  $0 <input.c> [--lex path/to/c99.l] [--yacc path/to/c99.y] [--frontend-only]
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

INPUT_C=""
LEX_FILE="${YACC_DIR}/c99.l"
YACC_FILE="${YACC_DIR}/c99.y"
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

banner "路径与输入"
echo "[info] input: ${INPUT_C}"
echo "[info] lex:   ${LEX_FILE}"
echo "[info] yacc:  ${YACC_FILE}"
echo "[info] out:   ${OUT_DIR}"

cp "${INPUT_C}" "${OUT_DIR}/input.c"

banner "1/8 build self yacc tool"
cmake -S "${YACC_DIR}" -B "${YACC_DIR}/build" >/dev/null
cmake --build "${YACC_DIR}/build" -j >/dev/null
YACC_TOOL="${YACC_DIR}/build/src/yacc_parse_tool"
if [[ ! -x "${YACC_TOOL}" ]]; then
  echo "yacc_parse_tool not found: ${YACC_TOOL}" >&2
  exit 1
fi
echo "[ok] built: ${YACC_TOOL}"

banner "2/8 emit parser headers from self yacc"
"${YACC_TOOL}" emit "${YACC_FILE}" \
  --emit-y-tab-h "${OUT_DIR}/y.tab.h" \
  --emit-token-cases-inc "${OUT_DIR}/token_cases.inc" >/dev/null
echo "[ok] generated: ${OUT_DIR}/y.tab.h ${OUT_DIR}/token_cases.inc"

banner "3/8 flex"
flex -o "${OUT_DIR}/lex.yy.c" "${LEX_FILE}"
if rg -n "^int yylineno\s*=\s*1;" "${OUT_DIR}/lex.yy.c" >/dev/null 2>&1; then
  sed -i "0,/^int yylineno = 1;/{s/^int yylineno = 1;/\/\* yylineno disabled by pipeline *\//}" "${OUT_DIR}/lex.yy.c"
  echo "[info] patched duplicate yylineno in lex.yy.c"
fi
echo "[ok] generated: ${OUT_DIR}/lex.yy.c"

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
  : > "${OUT_DIR}/frontend_compat.c"
  if [[ ${NEED_YYLINENO_COMPAT} -eq 1 ]]; then
    echo "int yylineno = 1;" >> "${OUT_DIR}/frontend_compat.c"
  fi
  if [[ ${NEED_COLUMN_COMPAT} -eq 1 ]]; then
    echo "int column = 1;" >> "${OUT_DIR}/frontend_compat.c"
  fi
  FRONTEND_COMPAT_OBJ+=("${OUT_DIR}/frontend_compat.c")
  echo "[info] generated frontend_compat.c for missing lexer globals"
fi

banner "4/8 build lexer streamer (yylex direct)"
cat > "${OUT_DIR}/lexer_stream_main.c" <<'C_EOF'
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include "y.tab.h"
int yylex(void);
YYSTYPE yylval;
extern char *yytext;
extern int yyleng;
extern int yylineno;
extern int column;
extern FILE *yyout;
void error(const char *s) { if (s) fprintf(stderr, "lexer error: %s\n", s); }
static const char *token_name(int tok) {
  switch (tok) {
    #include "token_cases.inc"
    default: return NULL;
  }
}
static void printable_char_token(int tok, char buf[16]) {
  unsigned char ch = (unsigned char)tok;
  if (ch == '\\' || ch == '\'') snprintf(buf, 16, "'%c%c'", '\\', ch);
  else if (isprint(ch)) snprintf(buf, 16, "'%c'", ch);
  else snprintf(buf, 16, "'\\x%02X'", ch);
}
static void write_escaped_lexeme(FILE *out, const char *text, int len) {
  int i;
  for (i = 0; i < len; ++i) {
    unsigned char ch = (unsigned char)text[i];
    if (ch == '\\') {
      fputs("\\\\", out);
    } else if (isalnum(ch) || ch == '_' || ispunct(ch)) {
      fputc((int)ch, out);
    } else {
      fprintf(out, "\\x%02X", ch);
    }
  }
}
int main(int argc, char **argv) {
  FILE *echo_sink;
  if (argc != 2) return 1;
  if (!freopen(argv[1], "rb", stdin)) return 2;
  echo_sink = fopen("/dev/null", "wb");
  if (echo_sink) yyout = echo_sink;
  {
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
          return 3;
        }
      }
      tok_col = column - yyleng + 1;
      if (tok_col < 1) tok_col = 1;
      fprintf(stdout, "%s ", name);
      write_escaped_lexeme(stdout, yytext, yyleng);
      fprintf(stdout, " %d %d\n", yylineno, tok_col);
    }
  }
  if (echo_sink) fclose(echo_sink);
  return 0;
}
C_EOF
cc -std=gnu89 -w -I"${OUT_DIR}" "${OUT_DIR}/lexer_stream_main.c" "${OUT_DIR}/lex.yy.c" "${FRONTEND_COMPAT_OBJ[@]}" -lfl -o "${OUT_DIR}/lexer_streamer"
echo "[ok] built: ${OUT_DIR}/lexer_streamer"

banner "5/8 run self yacc frontend"
set +e
"${OUT_DIR}/lexer_streamer" "${OUT_DIR}/input.c" | \
  "${YACC_TOOL}" run "${YACC_FILE}" \
    --parse-tokens-stdin \
    --ast-out "${OUT_DIR}/ast.json" \
    --ast-format json > "${OUT_DIR}/frontend.log" 2>&1
PIPE_RC=(${PIPESTATUS[@]})
if [[ ${PIPE_RC[0]} -ne 0 ]]; then
  FRONTEND_RC=${PIPE_RC[0]}
else
  FRONTEND_RC=${PIPE_RC[1]}
fi
set -e

echo "[ok] log: ${OUT_DIR}/frontend.log"
echo "[info] frontend rc: ${FRONTEND_RC}"
if [[ -f "${OUT_DIR}/ast.json" ]]; then
  echo "[ok] generated: ${OUT_DIR}/ast.json"
fi
if [[ ${FRONTEND_RC} -ne 0 ]]; then
  echo "[warn] self yacc frontend reported non-zero exit (${FRONTEND_RC})"
fi

if [[ "${FRONTEND_ONLY}" -eq 1 ]]; then
  banner "done"
  echo "done(frontend only): ${OUT_DIR}"
  exit 0
fi

banner "6/8 sync runtime tokens"
"${OUT_DIR}/lexer_streamer" "${OUT_DIR}/input.c" > "${OUT_DIR}/runtime.tokens.rich"
echo "[ok] generated: ${OUT_DIR}/runtime.tokens.rich"
LEGACY_TOKENS_DIR="${ROOT_DIR}/c99-yacc-lr-lalr-practice/contracts/yacc/tokens"
mkdir -p "${LEGACY_TOKENS_DIR}"
cp -f "${OUT_DIR}/runtime.tokens.rich" "${LEGACY_TOKENS_DIR}/c99_output.tokens"
echo "[ok] synced legacy token: ${LEGACY_TOKENS_DIR}/c99_output.tokens"
BACKEND_REL_TOKENS_DIR="${BACKEND_DIR}/c99-yacc-lr-lalr-practice/contracts/yacc/tokens"
mkdir -p "${BACKEND_REL_TOKENS_DIR}"
cp -f "${OUT_DIR}/runtime.tokens.rich" "${BACKEND_REL_TOKENS_DIR}/c99_output.tokens"
echo "[ok] synced backend-relative token: ${BACKEND_REL_TOKENS_DIR}/c99_output.tokens"

banner "7/8 export parser traces"
"${OUT_DIR}/lexer_streamer" "${OUT_DIR}/input.c" | "${YACC_TOOL}" run "${YACC_FILE}" \
  --parse-tokens-stdin \
  --ast-out "${OUT_DIR}/ast.json" \
  --ast-format json \
  --export \
  --export-dir "${OUT_DIR}/artifacts" >/dev/null
cp -f "${OUT_DIR}/artifacts/raw/parse_trace_lalr.tsv" "${OUT_DIR}/parse_trace_lalr.tsv"
cp -f "${OUT_DIR}/artifacts/raw/parse_reductions_lalr.txt" "${OUT_DIR}/parse_reductions_lalr.txt"
echo "[ok] generated: ${OUT_DIR}/parse_trace_lalr.tsv"

banner "8/8 backend (maven exec)"
if [[ -f "${BACKEND_DIR}/pom.xml" ]]; then
  (
    cd "${BACKEND_DIR}"
    mvn -q -DskipTests exec:java \
      -Dexec.mainClass=com.compiler.backend.Main \
      -Dexec.args="${OUT_DIR}"
  ) | tee "${OUT_DIR}/backend.log"
  echo "[ok] backend log: ${OUT_DIR}/backend.log"
  banner "done"
  echo "done(frontend+backend): ${OUT_DIR}"
else
  echo "backend not found, frontend done: ${OUT_DIR}"
fi
