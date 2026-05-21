#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_DIR="${ROOT_DIR}/src"
OUT_ROOT="${ROOT_DIR}/output"

# Clear, stable local names
SEULEX_DIR="${SRC_DIR}/lexer_seulex"
YACC_DIR="${SRC_DIR}/parser_c99_yacc"
BACKEND_DIR="${SRC_DIR}/backend_intermediate_codegen"

SEULEX_REPO_URL="https://github.com/ZhangYin256/seulex.git"
YACC_REPO_URL="https://github.com/twilight0702/c99-yacc-lr-lalr-practice.git"
BACKEND_REPO_URL="https://github.com/LJR-12138/IntermediateCodeGeneration.git"

usage() {
  cat <<USAGE
Usage:
  $0 [--auto-pull] [--skip-repo-check] [--lex <path/to/file.l>] [--yacc <path/to/file.y>] <input.c>

Example:
  $0 sample_complex_input.c
  $0 --auto-pull --lex src/parser_c99_yacc/c99.l --yacc src/parser_c99_yacc/c99.y sample_complex_input.c
  $0 --skip-repo-check sample_complex_input.c
USAGE
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

line_buffer_run() {
  if have_cmd stdbuf; then
    stdbuf -oL -eL "$@"
  else
    "$@"
  fi
}

require_cmd() {
  local cmd="$1"
  if ! have_cmd "$cmd"; then
    echo "[ERROR] Missing required command: ${cmd}" >&2
    exit 1
  fi
}

check_basic_env() {
  echo "[Env] Checking required tools..."
  require_cmd git
  require_cmd cmake
  require_cmd gcc
  require_cmd g++
  require_cmd cc
  require_cmd java
  require_cmd javac
  require_cmd mvn
  require_cmd awk
  require_cmd sed
  require_cmd find

  echo "[Env] Tool versions:"
  echo "  - gcc:    $(gcc --version | head -n1)"
  echo "  - cmake:  $(cmake --version | head -n1)"
  echo "  - java:   $(java -version 2>&1 | head -n1)"
  echo "  - javac:  $(javac -version 2>&1 | head -n1)"
  echo "  - maven:  $(mvn -version 2>&1 | head -n1)"

}

clone_or_check_repo() {
  local local_dir="$1"
  local repo_url="$2"
  local name="$3"
  local auto_pull="$4"
  local skip_repo_check="$5"

  if [[ ! -d "${local_dir}" ]]; then
    echo "[Repo] Cloning ${name} -> ${local_dir}"
    git clone "${repo_url}" "${local_dir}"
    return
  fi

  if [[ ! -d "${local_dir}/.git" ]]; then
    echo "[ERROR] ${local_dir} exists but is not a git repository." >&2
    exit 1
  fi

  local current_remote
  current_remote=$(git -C "${local_dir}" remote get-url origin 2>/dev/null || true)
  if [[ "${current_remote}" != "${repo_url}" ]]; then
    echo "[WARN] ${name} origin mismatch"
    echo "       expected: ${repo_url}"
    echo "       actual:   ${current_remote}"
  fi

  if [[ "${skip_repo_check}" == "1" ]]; then
    echo "[Repo] Skipping remote update check for ${name} (--skip-repo-check)."
    return
  fi

  echo "[Repo] Checking updates for ${name}..."
  if ! git -C "${local_dir}" fetch --quiet origin; then
    echo "[ERROR] fetch failed for ${name}; cannot verify remote commit status" >&2
    exit 1
  fi

  local branch upstream
  branch=$(git -C "${local_dir}" symbolic-ref --short HEAD 2>/dev/null || true)
  if [[ -z "${branch}" ]]; then
    echo "[ERROR] ${name} is in detached HEAD; cannot safely compare with remote." >&2
    exit 1
  fi

  upstream=$(git -C "${local_dir}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [[ -z "${upstream}" ]]; then
    upstream="origin/${branch}"
  fi
  if ! git -C "${local_dir}" rev-parse --verify "${upstream}" >/dev/null 2>&1; then
    echo "[ERROR] ${name} upstream ${upstream} not found; cannot verify remote commit status." >&2
    exit 1
  fi

  local counts ahead behind
  counts=$(git -C "${local_dir}" rev-list --left-right --count HEAD..."${upstream}")
  read -r ahead behind <<< "${counts}"
  ahead=${ahead:-0}
  behind=${behind:-0}

  local local_head remote_head
  local_head=$(git -C "${local_dir}" log -1 --pretty='format:%h %cs %s')
  remote_head=$(git -C "${local_dir}" log -1 --pretty='format:%h %cs %s' "${upstream}")
  echo "[Repo] ${name} local  HEAD: ${local_head}"
  echo "[Repo] ${name} remote HEAD: ${remote_head} (${upstream})"

  if [[ "${behind}" -gt 0 ]]; then
    echo "[Repo] ${name} is behind ${upstream} by ${behind} commit(s)."
    if [[ "${auto_pull}" == "1" ]]; then
      echo "[Repo] Auto-pull enabled, pulling latest with --ff-only..."
      git -C "${local_dir}" pull --ff-only
    elif [[ -t 0 ]]; then
      read -r -p "       Pull latest now? [y/N]: " ans
      ans=${ans:-N}
      if [[ "${ans}" =~ ^[Yy]$ ]]; then
        git -C "${local_dir}" pull --ff-only
      else
        echo "[ERROR] ${name} is behind remote. Please pull latest and re-run." >&2
        exit 1
      fi
    else
      echo "[ERROR] ${name} is behind remote and no TTY for prompt. Re-run with --auto-pull or pull manually." >&2
      exit 1
    fi
  else
    echo "[Repo] ${name} is up-to-date on ${branch}."
  fi

  if [[ "${ahead}" -gt 0 ]]; then
    echo "[Repo] ${name} has ${ahead} local commit(s) ahead of ${upstream}."
  fi
}

prepare_repos() {
  local auto_pull="$1"
  local skip_repo_check="$2"
  mkdir -p "${SRC_DIR}"
  clone_or_check_repo "${SEULEX_DIR}" "${SEULEX_REPO_URL}" "seulex" "${auto_pull}" "${skip_repo_check}"
  clone_or_check_repo "${YACC_DIR}" "${YACC_REPO_URL}" "c99-yacc-lr-lalr-practice" "${auto_pull}" "${skip_repo_check}"
  clone_or_check_repo "${BACKEND_DIR}" "${BACKEND_REPO_URL}" "IntermediateCodeGeneration" "${auto_pull}" "${skip_repo_check}"
}

ensure_clean_cmake_build_dir() {
  local src_dir="$1"
  local build_dir="$2"
  local cache_file="${build_dir}/CMakeCache.txt"
  if [[ -f "${cache_file}" ]]; then
    local cached_src
    cached_src=$(awk -F= '/^CMAKE_HOME_DIRECTORY:INTERNAL=/{print $2}' "${cache_file}" || true)
    if [[ -n "${cached_src}" && "${cached_src}" != "${src_dir}" ]]; then
      echo "[Build] Remove stale CMake cache: ${build_dir}"
      rm -rf "${build_dir}"
    fi
  fi
}

run_pipeline() {
  local input_c="$1"
  local lex_file_override="$2"
  local yacc_file_override="$3"

  if [[ ! -f "${input_c}" ]]; then
    echo "[ERROR] Input C file not found: ${input_c}" >&2
    exit 1
  fi

  local abs_input
  abs_input=$(cd "$(dirname "${input_c}")" && pwd)/"$(basename "${input_c}")"
  local case_name
  case_name=$(basename "${input_c}")
  case_name="${case_name%.*}"

  local ts
  ts=$(date +"%Y%m%d_%H%M%S")
  local run_dir="${OUT_ROOT}/${ts}_${case_name}"
  local build_root="${OUT_ROOT}/build"

  local seulex_build="${build_root}/seulex"
  local yacc_build="${build_root}/yacc"
  local backend_classes="${build_root}/backend_classes"

  local generated_dir="${run_dir}/generated"
  local tokens_dir="${run_dir}/tokens"
  local parse_dir="${run_dir}/parser"
  local backend_dir="${run_dir}/backend"
  local backend_raw_dir="${backend_dir}/raw"

  mkdir -p "${generated_dir}" "${tokens_dir}" "${parse_dir}" "${backend_raw_dir}" "${backend_classes}" "${seulex_build}" "${yacc_build}"

  local lex_file="${YACC_DIR}/c99.l"
  local yacc_file="${YACC_DIR}/c99.y"
  if [[ -n "${lex_file_override}" ]]; then
    lex_file="${lex_file_override}"
  fi
  if [[ -n "${yacc_file_override}" ]]; then
    yacc_file="${yacc_file_override}"
  fi
  if [[ ! -f "${lex_file}" ]]; then
    echo "[ERROR] Lex file not found: ${lex_file}" >&2
    exit 1
  fi
  if [[ ! -f "${yacc_file}" ]]; then
    echo "[ERROR] Yacc file not found: ${yacc_file}" >&2
    exit 1
  fi

  local generated_yy_c="${generated_dir}/c99.yy.c"
  local generated_y_tab_h="${generated_dir}/y.tab.h"
  local token_cases_inc="${generated_dir}/token_cases.inc"
  local token_dump_main_c="${generated_dir}/token_dump_main.c"
  local token_dumper_bin="${generated_dir}/token_dumper"

  local lex_input_c="${tokens_dir}/input_no_preprocessor.c"
  local tokens_rich="${tokens_dir}/runtime.tokens.rich"
  local tokens_plain="${tokens_dir}/runtime.tokens"
  local normalized_tsv="${tokens_dir}/normalized.tokens.tsv"
  local normalized_json="${tokens_dir}/normalized.tokens.json"

  local parser_log="${parse_dir}/yacc_parse.log"
  local backend_log="${backend_dir}/intermediate_codegen.log"
  local parser_export_dir="${parse_dir}/artifacts/yacc/step9/custom_case"

  local parser_contract_tokens="${YACC_DIR}/contracts/yacc/tokens/c99_${case_name}.tokens"
  local backend_legacy_tokens_dir="${ROOT_DIR}/c99-yacc-lr-lalr-practice/contracts/yacc/tokens"
  local backend_legacy_tokens_backend="${backend_legacy_tokens_dir}/c99_backend.tokens"
  local backend_legacy_tokens_case="${backend_legacy_tokens_dir}/c99_${case_name}.tokens"

  echo "[1/9] Build SeuLex"
  ensure_clean_cmake_build_dir "${SEULEX_DIR}" "${seulex_build}"
  line_buffer_run cmake -S "${SEULEX_DIR}" -B "${seulex_build}" >/dev/null
  line_buffer_run cmake --build "${seulex_build}" -j

  echo "[2/9] Build yacc_parse_tool"
  ensure_clean_cmake_build_dir "${YACC_DIR}" "${yacc_build}"
  line_buffer_run cmake -S "${YACC_DIR}" -B "${yacc_build}" >/dev/null
  line_buffer_run cmake --build "${yacc_build}" -j

  echo "[3/9] Generate scanner by SeuLex"
  line_buffer_run "${seulex_build}/SeuLex" -o "${generated_yy_c}" "${lex_file}" >/dev/null
  sed -i 's/^static char yytext\[SEULEX_YYTEXT_MAX\];/char yytext[SEULEX_YYTEXT_MAX];/' "${generated_yy_c}"

  echo "[4/9] Export parser headers from yacc_parse_tool"
  line_buffer_run "${yacc_build}/src/yacc_parse_tool" "${yacc_file}" \
    --emit-y-tab-h "${generated_y_tab_h}" \
    --emit-token-cases-inc "${token_cases_inc}" >/dev/null

  cat > "${token_dump_main_c}" <<'C_EOF'
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

  FILE *in = fopen(argv[1], "rb");
  if (!in) {
    perror("open input.c");
    return 1;
  }
  if (!freopen(argv[1], "rb", stdin)) {
    perror("freopen stdin");
    fclose(in);
    return 1;
  }
  fclose(in);

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

  echo "[5/9] Build token dumper"
  if ! line_buffer_run cc -std=gnu89 -w -DECHO='((void)0)' -I"${generated_dir}" \
    "${token_dump_main_c}" "${generated_yy_c}" -lfl -o "${token_dumper_bin}"; then
    echo "[WARN] build with -lfl failed, retry without -lfl"
    line_buffer_run cc -std=gnu89 -w -DECHO='((void)0)' -I"${generated_dir}" \
      "${token_dump_main_c}" "${generated_yy_c}" -o "${token_dumper_bin}"
  fi

  echo "[6/9] Lex input C -> token files"
  awk '!/^[[:space:]]*#/' "${abs_input}" > "${lex_input_c}"
  line_buffer_run "${token_dumper_bin}" "${lex_input_c}" "${tokens_rich}"
  awk '{print $1}' "${tokens_rich}" > "${tokens_plain}"

  awk 'BEGIN{OFS="\t"; print "index","type","lexeme","line","col"} {print NR-1,$1,$2,$3,$4}' \
    "${tokens_rich}" > "${normalized_tsv}"

  {
    echo "{"
    echo "  \"format\": \"normalized.tokens.v1\"," 
    echo "  \"source\": \"${abs_input}\"," 
    echo "  \"tokens\": ["
    awk 'BEGIN{first=1}
      {
        if (!first) print ",";
        first=0;
        printf "    {\"index\": %d, \"type\": \"%s\", \"lexeme\": \"%s\", \"line\": %d, \"col\": %d}",
               NR-1, $1, $2, $3, $4;
      }
      END{print ""}' "${tokens_rich}"
    echo "  ]"
    echo "}"
  } > "${normalized_json}"

  echo "[7/9] Run yacc parser (LR/LALR)"
  mkdir -p "$(dirname "${parser_contract_tokens}")"
  cp -f "${tokens_rich}" "${parser_contract_tokens}"
  # Backward compatibility for older IntermediateCodeGeneration path conventions.
  mkdir -p "${backend_legacy_tokens_dir}"
  cp -f "${tokens_rich}" "${backend_legacy_tokens_backend}"
  cp -f "${tokens_rich}" "${backend_legacy_tokens_case}"
  mkdir -p "${parser_export_dir}"

  pushd "${ROOT_DIR}" >/dev/null
  line_buffer_run "${yacc_build}/src/yacc_parse_tool" "${yacc_file}" \
    --parse-tokens "${tokens_rich}" \
    --export \
    --export-dir "${parser_export_dir}" \
    | tee "${parser_log}"
  popd >/dev/null

  cp -f "${parser_export_dir}/raw/parse_trace_lalr.tsv" "${backend_raw_dir}/parse_trace_lalr.tsv"
  cp -f "${parser_export_dir}/raw/parse_reductions_lalr.txt" "${backend_raw_dir}/parse_reductions_lalr.txt"
  cp -f "${normalized_tsv}" "${backend_dir}/normalized.tokens.tsv"

  local backend_cp_file="${backend_dir}/backend.classpath"
  local backend_cp=""

  echo "[8/9] Build backend with Maven (resolve deps: soot/opencsv/...)"
  pushd "${BACKEND_DIR}" >/dev/null
  line_buffer_run mvn -q -DskipTests compile dependency:build-classpath -Dmdep.outputFile="${backend_cp_file}"
  popd >/dev/null
  backend_cp="${BACKEND_DIR}/target/classes:$(cat "${backend_cp_file}")"

  echo "[9/9] Generate intermediate code"
  line_buffer_run java -cp "${backend_cp}" com.compiler.backend.Main "${backend_raw_dir}/" \
    | tee "${backend_log}"

  if [[ -f "${backend_dir}/output.jimple" ]]; then
    :
  elif [[ -f "${backend_raw_dir%/raw}/output.jimple" ]]; then
    cp -f "${backend_raw_dir%/raw}/output.jimple" "${backend_dir}/output.jimple"
  fi

  cat > "${run_dir}/README.txt" <<README_EOF
Run Directory: ${run_dir}
Input C File: ${abs_input}

Key outputs:
- Tokens (plain):   tokens/runtime.tokens
- Tokens (rich):    tokens/runtime.tokens.rich
- Tokens (norm):    tokens/normalized.tokens.tsv
- Parse log:        parser/yacc_parse.log
- Parse traces:     backend/raw/parse_trace_lalr.tsv
- Parse reductions: backend/raw/parse_reductions_lalr.txt
- Jimple output:    backend/output.jimple
- Backend log:      backend/intermediate_codegen.log
README_EOF

  echo
  echo "[Done] Pipeline finished"
  echo "       Output root: ${run_dir}"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local input_c=""
  local lex_file_override=""
  local yacc_file_override=""
  local auto_pull="0"
  local skip_repo_check="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-pull)
        auto_pull="1"
        ;;
      --skip-repo-check)
        skip_repo_check="1"
        ;;
      --lex)
        shift
        if [[ $# -eq 0 ]]; then
          echo "[ERROR] --lex requires a file path" >&2
          exit 1
        fi
        lex_file_override="$1"
        ;;
      --yacc)
        shift
        if [[ $# -eq 0 ]]; then
          echo "[ERROR] --yacc requires a file path" >&2
          exit 1
        fi
        yacc_file_override="$1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        echo "[ERROR] Unknown option: $1" >&2
        usage
        exit 1
        ;;
      *)
        if [[ -n "${input_c}" ]]; then
          echo "[ERROR] Multiple input files provided: ${input_c} and $1" >&2
          usage
          exit 1
        fi
        input_c="$1"
        ;;
    esac
    shift
  done

  if [[ -z "${input_c}" ]]; then
    echo "[ERROR] Missing input C file" >&2
    usage
    exit 1
  fi

  check_basic_env
  prepare_repos "${auto_pull}" "${skip_repo_check}"
  run_pipeline "${input_c}" "${lex_file_override}" "${yacc_file_override}"
}

main "$@"
