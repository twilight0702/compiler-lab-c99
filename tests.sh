#!/usr/bin/env bash
set -euo pipefail

# 输出日志：测试一
echo "=============测试一：基础c脚本测试================="

./run_full_pipeline_seulex_inproc.sh test_input/sample_pipeline_valid.c

echo "====================测试一结束========================"

echo "=============测试二：较复杂c脚本测试================="

./run_full_pipeline_seulex_inproc.sh test_input/sample_complex.c \
  --skip-submodule-check \

echo "====================测试二结束========================"

echo "=============测试三：计算器样例测试（仅前端）================="

./run_full_pipeline_seulex_inproc.sh \
  --lex  simple_test/cal.l \
  --yacc simple_test/cal.y \
  --frontend-only \
  --skip-submodule-check \
  simple_test/cal_test.txt

echo "====================测试三结束========================"

echo "=============测试四：mini ctrl 样例================="

./run_full_pipeline_seulex_inproc.sh test_input/boundary_mid_cases/mini_ctrl.c \
    --lex test_input/boundary_mid_cases/mini_ctrl.l \
    --yacc test_input/boundary_mid_cases/mini_ctrl.y \
    --skip-submodule-check

echo "====================测试四结束========================"

echo "=============测试五：mini func 样例================="

./run_full_pipeline_seulex_inproc.sh test_input/boundary_mid_cases/mini_func.c \
    --lex test_input/boundary_mid_cases/mini_func.l \
    --yacc test_input/boundary_mid_cases/mini_func.y \
    --skip-submodule-check

echo "====================测试五结束========================"
