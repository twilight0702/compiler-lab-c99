#!/usr/bin/env bash
# 开启严格模式：
# -e: 任一命令失败立即退出
# -u: 使用未定义变量时报错
# -o pipefail: 管道中任一命令失败则整体失败
set -euo pipefail

# 脚本根目录与核心路径定义
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_DIR="${ROOT_DIR}/src"
OUT_ROOT="${ROOT_DIR}/output"

# 三个子仓库在本地的固定目录名（避免路径散落在脚本中）
SEULEX_DIR="${SRC_DIR}/lexer_seulex"
YACC_DIR="${SRC_DIR}/parser_c99_yacc"
BACKEND_DIR="${SRC_DIR}/backend_intermediate_codegen"

# 三个上游仓库地址
SEULEX_REPO_URL="https://github.com/ZhangYin256/seulex.git"
YACC_REPO_URL="https://github.com/twilight0702/c99-yacc-lr-lalr-practice.git"
BACKEND_REPO_URL="https://github.com/LJR-12138/IntermediateCodeGeneration.git"

usage() {
  cat <<USAGE
Usage:
  $0 [--auto-pull] [--skip-repo-check] [--frontend-only] [--lex <path/to/file.l>] [--yacc <path/to/file.y>] [<input.c>]

Example:
  $0 sample_complex_input.c
  $0 --frontend-only sample_complex_input.c
  $0 --frontend-only
  $0 --auto-pull --lex src/parser_c99_yacc/c99.l --yacc src/parser_c99_yacc/c99.y sample_complex_input.c
  $0 --skip-repo-check sample_complex_input.c
USAGE
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# 统一命令执行方式：
# 若系统存在 stdbuf，则强制行缓冲，避免长时间无输出给人“卡住”感
line_buffer_run() {
  if have_cmd stdbuf; then
    stdbuf -oL -eL "$@"
  else
    "$@"
  fi
}

# 输出长分割行，强调阶段边界，便于在长日志中快速定位
# 示例：
# ==================== [阶段 1/9] 构建 SeuLex ====================
stage_banner() {
  local title="$1"
  printf '\n%s\n' "==================== ${title} ===================="
}

require_cmd() {
  local cmd="$1"
  if ! have_cmd "$cmd"; then
    echo "[ERROR] Missing required command: ${cmd}" >&2
    exit 1
  fi
}

check_basic_env() {
  local frontend_only="$1"
  stage_banner "环境检查：校验必需工具"
  require_cmd git
  require_cmd cmake
  require_cmd gcc
  require_cmd g++
  require_cmd cc
  require_cmd awk
  require_cmd sed
  require_cmd find
  if [[ "${frontend_only}" != "1" ]]; then
    require_cmd java
    require_cmd javac
    require_cmd mvn
  fi

  echo "[信息] 工具版本如下："
  echo "  - gcc:    $(gcc --version | head -n1)"
  echo "  - cmake:  $(cmake --version | head -n1)"
  if [[ "${frontend_only}" != "1" ]]; then
    echo "  - java:   $(java -version 2>&1 | head -n1)"
    echo "  - javac:  $(javac -version 2>&1 | head -n1)"
    echo "  - maven:  $(mvn -version 2>&1 | head -n1)"
  fi

}

clone_or_check_repo() {
  # 参数说明：
  # $1 本地目录、$2 远程仓库 URL、$3 展示名称、$4 是否自动 pull、$5 是否跳过远端检查
  local local_dir="$1"
  local repo_url="$2"
  local name="$3"
  local auto_pull="$4"
  local skip_repo_check="$5"

  if [[ ! -d "${local_dir}" ]]; then
    echo "[仓库] 克隆 ${name} -> ${local_dir}"
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
    echo "[警告] ${name} 的 origin 地址与预期不一致"
    echo "       期望: ${repo_url}"
    echo "       实际: ${current_remote}"
  fi

  if [[ "${skip_repo_check}" == "1" ]]; then
    echo "[仓库] 跳过 ${name} 的远端更新检查（--skip-repo-check）"
    return
  fi

  echo "[仓库] 检查 ${name} 是否有远端更新..."
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
  echo "[仓库] ${name} 本地  HEAD: ${local_head}"
  echo "[仓库] ${name} 远端  HEAD: ${remote_head} (${upstream})"

  if [[ "${behind}" -gt 0 ]]; then
    echo "[仓库] ${name} 落后于 ${upstream}，共 ${behind} 个提交"
    if [[ "${auto_pull}" == "1" ]]; then
      echo "[Repo] Auto-pull enabled, pulling latest with --ff-only..."
      git -C "${local_dir}" pull --ff-only
    elif [[ -t 0 ]]; then
      read -r -p "       是否立即拉取最新提交？[y/N]: " ans
      ans=${ans:-N}
      if [[ "${ans}" =~ ^[Yy]$ ]]; then
        git -C "${local_dir}" pull --ff-only
      else
        echo "[ERROR] ${name} 落后于远端，请先 pull 后重试。" >&2
        exit 1
      fi
    else
      echo "[ERROR] ${name} 落后于远端，且当前无 TTY 无法交互。请使用 --auto-pull 或手动 pull。" >&2
      exit 1
    fi
  else
    echo "[仓库] ${name} 在分支 ${branch} 上已是最新"
  fi

  if [[ "${ahead}" -gt 0 ]]; then
    echo "[仓库] ${name} 相对 ${upstream} 本地超前 ${ahead} 个提交"
  fi
}

prepare_repos() {
  # 创建 src 目录并准备三个依赖仓库
  local auto_pull="$1"
  local skip_repo_check="$2"
  local frontend_only="$3"
  mkdir -p "${SRC_DIR}"
  clone_or_check_repo "${SEULEX_DIR}" "${SEULEX_REPO_URL}" "seulex" "${auto_pull}" "${skip_repo_check}"
  clone_or_check_repo "${YACC_DIR}" "${YACC_REPO_URL}" "c99-yacc-lr-lalr-practice" "${auto_pull}" "${skip_repo_check}"
  if [[ "${frontend_only}" != "1" ]]; then
    clone_or_check_repo "${BACKEND_DIR}" "${BACKEND_REPO_URL}" "IntermediateCodeGeneration" "${auto_pull}" "${skip_repo_check}"
  fi
}

ensure_clean_cmake_build_dir() {
  # 避免同一个 build 目录指向了“错误源码目录”导致 CMake 缓存污染
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
  # 执行完整流水线：
  # 1) 构建工具链 2) 生成词法器 3) 产出 token
  # 4) 运行语法分析 5) 运行后端中间代码生成
  local input_c="${1:-}"
  local lex_file_override="$2"
  local yacc_file_override="$3"
  local frontend_only="$4"

  local has_input_c="0"
  local abs_input=""
  local case_name="frontend_only"
  if [[ -n "${input_c}" ]]; then
    if [[ ! -f "${input_c}" ]]; then
      echo "[ERROR] Input C file not found: ${input_c}" >&2
      exit 1
    fi
    has_input_c="1"
    abs_input=$(cd "$(dirname "${input_c}")" && pwd)/"$(basename "${input_c}")"
    case_name=$(basename "${input_c}")
    case_name="${case_name%.*}"
  fi

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

  # 默认优先使用 test_input 下的词法/语法文件，便于本地调试；
  # 若不存在则回退到 parser 子仓库内的默认文件。
  local lex_file="${YACC_DIR}/c99.l"
  local yacc_file="${YACC_DIR}/c99.y"
  if [[ -f "${ROOT_DIR}/test_input/c99.l" ]]; then
    lex_file="${ROOT_DIR}/test_input/c99.l"
  fi
  if [[ -f "${ROOT_DIR}/test_input/c99.y" ]]; then
    yacc_file="${ROOT_DIR}/test_input/c99.y"
  fi
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
  local normalized_tsv="${tokens_dir}/normalized.tokens.tsv"

  local parser_log="${parse_dir}/yacc_parse.log"
  local backend_log="${backend_dir}/intermediate_codegen.log"
  local parser_export_dir="${parse_dir}/artifacts/yacc/step9/custom_case"

  local parser_contract_tokens="${YACC_DIR}/contracts/yacc/tokens/c99_${case_name}.tokens"
  local backend_legacy_tokens_dir="${ROOT_DIR}/c99-yacc-lr-lalr-practice/contracts/yacc/tokens"
  local backend_legacy_tokens_backend="${backend_legacy_tokens_dir}/c99_backend.tokens"
  local backend_legacy_tokens_case="${backend_legacy_tokens_dir}/c99_${case_name}.tokens"

  stage_banner "阶段 1/9：构建 SeuLex"
  ensure_clean_cmake_build_dir "${SEULEX_DIR}" "${seulex_build}"
  line_buffer_run cmake -S "${SEULEX_DIR}" -B "${seulex_build}"
  line_buffer_run cmake --build "${seulex_build}" -j

  stage_banner "阶段 2/9：构建 yacc_parse_tool"
  ensure_clean_cmake_build_dir "${YACC_DIR}" "${yacc_build}"
  line_buffer_run cmake -S "${YACC_DIR}" -B "${yacc_build}"
  line_buffer_run cmake --build "${yacc_build}" -j

  stage_banner "阶段 3/9：使用 SeuLex 生成 scanner"
  line_buffer_run "${seulex_build}/SeuLex" -o "${generated_yy_c}" "${lex_file}"
  # 让 yytext 从 static 变为全局可见，供 token_dump_main.c 引用
  sed -i 's/^static char yytext\[SEULEX_YYTEXT_MAX\];/char yytext[SEULEX_YYTEXT_MAX];/' "${generated_yy_c}"

  stage_banner "阶段 4/9：导出 parser 头文件与 token 映射"
  line_buffer_run "${yacc_build}/src/yacc_parse_tool" emit "${yacc_file}" \
    --emit-y-tab-h "${generated_y_tab_h}" \
    --emit-token-cases-inc "${token_cases_inc}"

  # 动态生成 token 导出程序：
  # 读取词法输出，记录 token 名称、lexeme、行列，供后续 parser/backend 使用
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

  stage_banner "阶段 5/9：构建 token 导出程序"
  echo "[阶段5] 编译输入源码:"
  echo "        - ${token_dump_main_c}"
  echo "        - ${generated_yy_c}"
  echo "[阶段5] 目标可执行文件: ${token_dumper_bin}"
  if ! line_buffer_run cc -std=gnu89 -w -DECHO='((void)0)' -I"${generated_dir}" \
    "${token_dump_main_c}" "${generated_yy_c}" -lfl -o "${token_dumper_bin}"; then
    # 某些环境没有 libfl，自动降级重试
    echo "[警告] 使用 -lfl 构建失败，尝试不链接 -lfl 重新构建"
    if ! line_buffer_run cc -std=gnu89 -w -DECHO='((void)0)' -I"${generated_dir}" \
      "${token_dump_main_c}" "${generated_yy_c}" -o "${token_dumper_bin}"; then
      # 某些 scanner（如 simple_test/cal.l）未定义 yylineno/column/yylval，
      # 尝试添加兼容性符号定义
      echo "[警告] 仍链接失败，尝试添加兼容性符号定义"
      local compat_c="${generated_dir}/token_dumper_compat.c"
      cat > "${compat_c}" <<'COMPAT_EOF'
/* Compatibility definitions for scanners that don't provide these symbols
   (e.g. simple calculator lex files without yylineno/column tracking). */
int yylval = 0;
int yylineno = 1;
int column = 1;
COMPAT_EOF
      line_buffer_run cc -std=gnu89 -w -DECHO='((void)0)' -I"${generated_dir}" \
        "${token_dump_main_c}" "${generated_yy_c}" "${compat_c}" -o "${token_dumper_bin}"
    fi
  fi
  echo "[阶段5] 编译完成: ${token_dumper_bin}"

  if [[ "${has_input_c}" == "1" ]]; then
    stage_banner "阶段 6/9：运行 Seulex 进行词法分析，生成 token 文件"
    # 先去掉预处理指令行，减少对 lexer 的干扰
    echo "[阶段6] 预处理输入文件（去除以 # 开头的预处理行）"
    echo "        - 原始输入: ${abs_input}"
    echo "        - 预处理后: ${lex_input_c}"
    awk '!/^[[:space:]]*#/' "${abs_input}" > "${lex_input_c}"
    echo "[阶段6] 运行 token_dumper 生成 rich token"
    line_buffer_run "${token_dumper_bin}" "${lex_input_c}" "${tokens_rich}"
    # 产出标准化 TSV，便于调试和人工查看
    echo "[阶段6] 生成标准化 TSV: ${normalized_tsv}"
    awk 'BEGIN{OFS="\t"; print "index","type","lexeme","line","col"} {print NR-1,$1,$2,$3,$4}' \
      "${tokens_rich}" > "${normalized_tsv}"
    echo "[阶段6] 产物统计:"
    echo "        - rich token 行数: $(wc -l < "${tokens_rich}")"
    echo "        - tsv token 行数:  $(($(wc -l < "${normalized_tsv}") - 1))"

    stage_banner "阶段 7/9：运行 yacc parser（LR/LALR）"
    mkdir -p "$(dirname "${parser_contract_tokens}")"
    cp -f "${tokens_rich}" "${parser_contract_tokens}"
    # 兼容旧版 IntermediateCodeGeneration 的 token 路径约定
    mkdir -p "${backend_legacy_tokens_dir}"
    cp -f "${tokens_rich}" "${backend_legacy_tokens_backend}"
    cp -f "${tokens_rich}" "${backend_legacy_tokens_case}"
    mkdir -p "${parser_export_dir}"

    pushd "${ROOT_DIR}" >/dev/null
    line_buffer_run "${yacc_build}/src/yacc_parse_tool" run "${yacc_file}" \
      --parse-tokens "${tokens_rich}" \
      --export \
      --export-dir "${parser_export_dir}" \
      | tee "${parser_log}"
    popd >/dev/null

    cp -f "${parser_export_dir}/raw/parse_trace_lalr.tsv" "${backend_raw_dir}/parse_trace_lalr.tsv"
    cp -f "${parser_export_dir}/raw/parse_reductions_lalr.txt" "${backend_raw_dir}/parse_reductions_lalr.txt"
    cp -f "${normalized_tsv}" "${backend_dir}/normalized.tokens.tsv"
  else
    echo "[信息] 未提供 input.c：跳过阶段 6/9 和 7/9（token 生成与 parser 运行）"
  fi

  local backend_cp_file="${backend_dir}/backend.classpath"
  local backend_cp=""

  if [[ "${frontend_only}" != "1" ]]; then
    stage_banner "阶段 8/9：使用 Maven 构建后端并解析依赖"
    pushd "${BACKEND_DIR}" >/dev/null
    line_buffer_run mvn -DskipTests compile dependency:build-classpath -Dmdep.outputFile="${backend_cp_file}"
    popd >/dev/null
    backend_cp="${BACKEND_DIR}/target/classes:$(cat "${backend_cp_file}")"

    stage_banner "阶段 9/9：生成中间代码"
    line_buffer_run java -cp "${backend_cp}" com.compiler.backend.Main "${backend_raw_dir}/" \
      | tee "${backend_log}"

    if [[ -f "${backend_dir}/output.jimple" ]]; then
      :
    elif [[ -f "${backend_raw_dir%/raw}/output.jimple" ]]; then
      cp -f "${backend_raw_dir%/raw}/output.jimple" "${backend_dir}/output.jimple"
    fi
  else
    echo "[信息] 已启用 --frontend-only：跳过阶段 8/9（后端构建与中间代码生成）"
  fi

  cat > "${run_dir}/README.txt" <<README_EOF
Run Directory: ${run_dir}
Input C File: ${abs_input:-<not provided>}

Key outputs:
- Tokens (rich):    tokens/runtime.tokens.rich (仅提供 input.c 时生成)
- Tokens (norm):    tokens/normalized.tokens.tsv (仅提供 input.c 时生成)
- Parse log:        parser/yacc_parse.log (仅提供 input.c 时生成)
- Parse traces:     backend/raw/parse_trace_lalr.tsv (仅提供 input.c 时生成)
- Parse reductions: backend/raw/parse_reductions_lalr.txt (仅提供 input.c 时生成)
README_EOF

  if [[ "${frontend_only}" != "1" ]]; then
    cat >> "${run_dir}/README.txt" <<README_EOF
- Jimple output:    backend/output.jimple
- Backend log:      backend/intermediate_codegen.log
README_EOF
  fi

  stage_banner "流水线完成"
  echo "[完成] Pipeline 执行结束"
  echo "       输出目录: ${run_dir}"
}

main() {
  # 命令行参数解析：
  # --auto-pull        仓库落后时自动 pull --ff-only
  # --skip-repo-check  跳过远端更新检查
  # --lex/--yacc       覆盖默认词法/语法文件
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local input_c=""
  local lex_file_override=""
  local yacc_file_override=""
  local auto_pull="0"
  local skip_repo_check="0"
  local frontend_only="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto-pull)
        auto_pull="1"
        ;;
      --skip-repo-check)
        skip_repo_check="1"
        ;;
      --frontend-only)
        frontend_only="1"
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

  if [[ -z "${input_c}" && "${frontend_only}" != "1" ]]; then
    echo "[ERROR] Missing input C file" >&2
    usage
    exit 1
  fi

  check_basic_env "${frontend_only}"
  prepare_repos "${auto_pull}" "${skip_repo_check}" "${frontend_only}"
  run_pipeline "${input_c}" "${lex_file_override}" "${yacc_file_override}" "${frontend_only}"
}

main "$@"
