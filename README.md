# compiler-lab-c99

本项目提供一条可复现的 C99 编译实验流水线：  
`SeuLex(.l) + yacc_parse_tool(.y) + Backend(Java/Soot)`。

核心入口脚本是：
- `run_full_pipeline_seulex_inproc.sh`

## 这个系统能做什么

1. 用 `SeuLex` 生成词法分析器源码（`lex.yy.c`）。
2. 用 `yacc_parse_tool` 生成语法分析器源码（`parser_generated.cpp`，无 `main`）。
3. 用固定驱动 `tool/seulex_yacc_codegen_driver.cpp` 联合 `yylex/yyparse` 运行前端。
4. 导出 `runtime.tokens.rich`、`parse_trace_lalr.tsv`、`parse_reductions_lalr.txt`。
5. 调用后端 `src/backend_intermediate_codegen` 生成 `output.jimple`。

## 如何使用

### 完整流程（前端 + 后端）

```bash
./run_full_pipeline_seulex_inproc.sh test_input/sample_pipeline_valid.c
```

### 仅前端

```bash
./run_full_pipeline_seulex_inproc.sh --frontend-only test_input/sample_pipeline_valid.c
```

### 自定义 `.l/.y`

```bash
./run_full_pipeline_seulex_inproc.sh \
  --lex simple_test/cal.l \
  --yacc simple_test/cal.y \
  --frontend-only \
  simple_test/cal_test.txt
```

### 参数

```text
Usage:
  ./run_full_pipeline_seulex_inproc.sh <input.c> [--lex path/to/c99.l] [--yacc path/to/c99.y] [--frontend-only]
```

## 新流程说明（脚本做了哪些事）

`run_full_pipeline_seulex_inproc.sh` 会：

1. 调用 `tool/check_env_and_sync.sh` 检查环境并尝试同步仓库。
2. 构建 `SeuLex` 与 `yacc_parse_tool`。
3. 生成并缓存前端产物（按 `.l/.y/driver` 内容哈希，命中时直接复用，减少 parser 阶段耗时）。
4. 运行前端并导出 token/trace。
5. 自动导出 YACC step9/step10 产物并执行 Python 格式转换，写入前端 `public/data/v1`。
6. 调用后端生成 Jimple。

备注：
- 输入会自动规范化：移除预处理行（`#...`），并保证文件末尾有换行。
- 当 lexer 未定义 `column/yylineno` 时，脚本会自动补兼容定义。

## 输出目录（重点）

每次运行生成：`output/seulex_codegen_YYYYMMDD_HHMMSS/`

根目录仅保留两个核心源码：
- `lex.yy.c`
- `parser_generated.cpp`

其余文件分目录：
- `build/`：中间编译文件与前端可执行
- `logs/`：`frontend.log`、`backend.log`
- `reports/`：`runtime.tokens.rich`、`parse_trace_lalr.tsv`、`parse_reductions_lalr.txt`、`output.jimple`

可视化数据会自动写入：
- `src/parser_c99_yacc/visualizer/public/data/v1/c99_<run_name>/`

然后启动前端即可查看（示例）：

```bash
cd src/parser_c99_yacc/visualizer
npm run dev
# 浏览器打开: http://localhost:5174/?case=c99_<run_name>
```

## 依赖

- `bash`
- `cmake`
- `gcc`/`g++`
- `git`
- `sed`
- `rg`（推荐）
- 完整流程还需要：`mvn`、`java`

## 常见问题

- `input C file not found`：输入路径错误。
- `lex/yacc file not found`：`--lex` / `--yacc` 路径错误。
- 前端报 `syntax error`：优先检查输入是否满足对应 `.y` 文法。
- 后端失败：先看 `output/.../logs/backend.log`。
