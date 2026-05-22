# compiler-lab-c99

> 编译原理专题实践实验项目一键运行脚本

一个用于验证 C99 编译前端到中间代码生成的端到端实验项目。  
通过统一脚本串联词法分析、语法分析与后端中间代码生成流程，并输出可追踪的中间产物。

## 功能概览

- 一键执行完整流水线：`lex -> yacc parse -> intermediate codegen`
- 支持仅运行前端：`lex -> yacc parse`（`--frontend-only`）
- 自动准备/校验依赖仓库（seulex、c99-yacc-lr-lalr-practice、IntermediateCodeGeneration）
- 支持跳过仓库远端新提交检查：`--skip-repo-check`
- 输出结构化产物：token、解析日志、解析轨迹、Jimple 中间代码
- 支持自定义 `.l/.y` 文件覆盖默认语法定义

## 环境依赖

脚本会在启动时检查以下工具（完整模式）：

- `git`
- `cmake`
- `gcc` / `g++` / `cc`
- `java` / `javac`
- `awk` / `sed` / `find`
- `mvn`

说明：

- 若使用 `--frontend-only`，则不要求 `java` / `javac` / `mvn`。
- 主 pipeline 不再依赖 `bison`。
- 若需要执行 `src/parser_c99_yacc` 子仓库中的 bison 对拍测试（tests 2/2f），再单独安装 `bison`。

## 快速开始

### 1. 运行示例

```bash
./run_full_pipeline.sh test_input/sample_pipeline_valid.c
```

### 2. 使用自定义词法/语法文件

```bash
./run_full_pipeline.sh \
  --lex test_input/c99.l \
  --yacc test_input/c99.y \
  test_input/sample_pipeline_valid.c
```

### 3. 仅运行前端（lex+yacc，不运行后端）

```bash
./run_full_pipeline.sh --frontend-only test_input/sample_pipeline_valid.c
# 仅验证前端生成/编译链路（不提供输入 C）
./run_full_pipeline.sh --frontend-only
```

说明：

- 传入 `input.c` 时：会执行前端阶段并输出 token 与 parser 产物
- 未传入 `input.c` 时：执行阶段 1-5，跳过阶段 6-7（不生成 token/parser 运行产物）
- 会跳过后端阶段（Maven 构建与 `output.jimple` 生成）
- 环境检查中不再要求 `java/javac/mvn`
- 仓库准备阶段不再检查/克隆 `IntermediateCodeGeneration`

### 4. 跳过仓库远端提交检查

适用于离线环境、网络受限，或你明确只想使用当前本地子仓库代码时：

```bash
./run_full_pipeline.sh --skip-repo-check test_input/sample_pipeline_valid.c
```

## 脚本流程（run_full_pipeline.sh）

脚本会先做环境检查（完整模式下会校验 `git/cmake/gcc/java/mvn` 等工具可用性），随后进入与日志严格对应的 9 个阶段：

1. 构建 `SeuLex`（`src/lexer_seulex`）  
2. 构建 `yacc_parse_tool`（`src/parser_c99_yacc`）  
3. 用 `SeuLex` 根据 `.l` 生成 `c99.yy.c`  
4. 调用 `yacc_parse_tool emit`，仅导出：
   - `y.tab.h`
   - `token_cases.inc`
5. 编译 `token_dumper`（由脚本生成 `token_dump_main.c`，与 `c99.yy.c` 链接）  
6. 使用编译后的 `token_dumper` 对输入 C 调用 `Seulex`执行词法分析，生成 `runtime.tokens.rich / normalized.tokens.tsv`  
7. 调用 `yacc_parse_tool run`，执行 LR/LALR 解析并导出 parser 产物（trace/reductions/log）  
8. 使用 Maven 构建后端（`src/backend_intermediate_codegen`）  
9. 运行后端，生成 `output.jimple`

若启用 `--frontend-only`：

- 提供 `input.c`：执行阶段 1-7，并跳过阶段 8-9。
- 不提供 `input.c`：执行阶段 1-5，并跳过阶段 6-9。

说明：

- 默认优先使用 `test_input/c99.l` 与 `test_input/c99.y`；若不存在则回退到 `src/parser_c99_yacc/` 下同名文件。  
- `--lex` / `--yacc` 参数优先级最高，会覆盖上述默认选择。
- 在 `--frontend-only` 且未提供 `input.c` 时，仍可用于仅验证 `.l/.y` 变更后的生成链路是否可用。

## 输出说明

每次运行会生成独立目录：`output/<timestamp>_<case_name>/`

核心产物包括：

- `tokens/runtime.tokens.rich`：token + 词素 + 位置信息
- `tokens/normalized.tokens.tsv`：标准化 token 表格
- `parser/yacc_parse.log`：语法分析日志
- `backend/raw/parse_trace_lalr.tsv`：LALR 解析轨迹
- `backend/raw/parse_reductions_lalr.txt`：规约记录
- `backend/output.jimple`：后端输出的中间代码
- `backend/intermediate_codegen.log`：后端执行日志

启用 `--frontend-only` 时，不会生成 `backend/output.jimple` 与 `backend/intermediate_codegen.log`。

## 目录结构

```text
.
├── run_full_pipeline.sh
├── src/
│   ├── lexer_seulex/
│   ├── parser_c99_yacc/
│   └── backend_intermediate_codegen/
├── test_input/
│   ├── c99.l
│   ├── c99.y
│   └── sample_pipeline_valid.c
└── output/
```

## 常见问题

- `mvn: command not found`  
  请安装 Maven 后重试。

- `Missing required command`  
  根据报错安装缺失工具后重试。

- 后端仓库路径/远端不一致  
  脚本会提示 `origin mismatch`，可继续使用本地代码，也可手动调整远端。
