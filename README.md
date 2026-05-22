# compiler-lab-c99

> C99 前端（Flex/Bison）到后端（Java/Soot）的一键联调脚本

## 项目说明

本仓库通过 `run_full_pipeline.sh` 把以下链路串起来：

1. `bison` 生成语法分析器
2. `flex` 生成词法分析器
3. 编译并运行前端
4. 导出运行时 token（`runtime.tokens.rich`）
5. 调用 `src/parser_c99_yacc` 的 `yacc_parse_tool` 导出 LALR 轨迹
6. 调用 `src/backend_intermediate_codegen` 生成 `output.jimple`

每次运行会生成独立输出目录：`output/simple_YYYYMMDD_HHMMSS/`。

## 快速开始

### 完整流程（前端 + 后端）

```bash
./run_full_pipeline.sh test_input/sample_pipeline_valid.c
```

### 仅前端

```bash
./run_full_pipeline.sh --frontend-only test_input/sample_pipeline_valid.c
```

### 使用自定义 `.l/.y`

```bash
./run_full_pipeline.sh \
  --lex simple_test/cal.l \
  --yacc simple_test/cal.y \
  --frontend-only \
  simple_test/cal_test.txt
```

## 参数

```text
Usage:
  ./run_full_pipeline.sh <input.c> [--lex path/to/c99.l] [--yacc path/to/c99.y] [--frontend-only]
```

说明：

- `input` 参数必填。
- 默认词法/语法文件：`src/parser_c99_yacc/c99.l` 与 `src/parser_c99_yacc/c99.y`。
- `--frontend-only` 会在第 5 步后退出，不执行 token 导出、trace 导出与后端。

## 环境依赖

完整流程依赖：

- `bash`
- `bison`
- `flex`
- `cc`（或 `gcc`）
- `cmake`
- `rg`（ripgrep）
- `mvn`
- `java`

说明：

- 如果仅使用 `--frontend-only`，后端相关的 `mvn/java` 不会被调用。
- `flex` 链接时使用 `-lfl`，需安装对应开发库。

## 脚本实际流程（8 个阶段）

1. `bison -d` 生成 `y.tab.c / y.tab.h`
2. `flex` 生成 `lex.yy.c`，并处理 `yylineno` 重复定义补丁
3. 检测 `.y` 是否自带 `main`，必要时生成 `frontend_driver.c`
4. 编译前端可执行文件 `frontend`
5. 运行前端并写入 `frontend.log`
6. 生成 `token_dumper` 并导出 `runtime.tokens.rich`
7. 运行 `yacc_parse_tool run --parse-tokens ... --export`，导出 `parse_trace_lalr.tsv`
8. 运行后端 Maven 程序，生成 `output.jimple`

## 输出目录说明

以 `output/simple_YYYYMMDD_HHMMSS/` 为例，常见产物：

- `input.c`：输入副本
- `y.tab.c`, `y.tab.h`, `lex.yy.c`
- `frontend` 与 `frontend.log`
- `runtime.tokens.rich`
- `parse_trace_lalr.tsv`
- `parse_reductions_lalr.txt`
- `artifacts/`（`yacc_parse_tool --export` 原始导出）
- `backend.log`
- `output.jimple`

## 近期修复记录

- 修复了 `yylineno` / `column` 的重复定义链接错误：仅在词法文件缺失定义时才生成 `frontend_compat.c`。
- 修复了 `frontend_compat.c` 被重复加入编译参数导致的重复符号问题。
- 修复了 token 导出乱码：`token_dump_main.c` 中 `yytext` 改为 `extern char *yytext`。
- 修复了 `simple_test/cal.y` 在文件末尾无换行时的 `syntax error`（支持 `calclist exp` 直接归约）。

## 常见问题

- `input C file not found`：检查输入路径。
- `lex/yacc file not found`：检查 `--lex`/`--yacc` 路径。
- 前端 `syntax error`：优先检查输入是否符合对应 `.y` 文法，不一定是脚本错误。
- `mvn` 阶段失败：查看输出目录内 `backend.log`。
