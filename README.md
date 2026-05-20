# compiler-lab-c99

> 编译原理专题实践实验项目一键运行脚本

一个用于验证 C99 编译前端到中间代码生成的端到端实验项目。  
通过统一脚本串联词法分析、语法分析与后端中间代码生成流程，并输出可追踪的中间产物。

## 功能概览

- 一键执行完整流水线：`lex -> yacc parse -> intermediate codegen`
- 自动准备/校验依赖仓库（seulex、c99-yacc-lr-lalr-practice、IntermediateCodeGeneration）
- 支持跳过仓库远端新提交检查：`--skip-repo-check`
- 输出结构化产物：token、解析日志、解析轨迹、Jimple 中间代码
- 支持自定义 `.l/.y` 文件覆盖默认语法定义

## 环境依赖

脚本会在启动时检查以下工具：

- `git`
- `cmake`
- `gcc` / `g++` / `cc`
- `java` / `javac`
- `awk` / `sed` / `find`
- `mvn`（可选，缺失时回退为 `javac + 本地 jar`）

说明：

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

### 3. 跳过仓库远端提交检查

适用于离线环境、网络受限，或你明确只想使用当前本地子仓库代码时：

```bash
./run_full_pipeline.sh --skip-repo-check test_input/sample_pipeline_valid.c
```

## 输出说明

每次运行会生成独立目录：`output/<timestamp>_<case_name>/`

核心产物包括：

- `tokens/runtime.tokens`：token 类型序列（纯文本）
- `tokens/runtime.tokens.rich`：token + 词素 + 位置信息
- `tokens/normalized.tokens.tsv`：标准化 token 表格
- `tokens/normalized.tokens.json`：标准化 token JSON
- `parser/yacc_parse.log`：语法分析日志
- `backend/raw/parse_trace_lalr.tsv`：LALR 解析轨迹
- `backend/raw/parse_reductions_lalr.txt`：规约记录
- `backend/output.jimple`：后端输出的中间代码
- `backend/intermediate_codegen.log`：后端执行日志

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
  脚本会尝试 `javac` 回退；若后端仓库缺少依赖 jar，请安装 Maven。

- `Missing required command`  
  根据报错安装缺失工具后重试。

- 后端仓库路径/远端不一致  
  脚本会提示 `origin mismatch`，可继续使用本地代码，也可手动调整远端。
