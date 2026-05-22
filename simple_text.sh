./run_full_pipeline.sh \
  --skip-repo-check \
  --lex  simple_test/cal.l\
  --yacc simple_test/cal.y \
  --frontend-only \
  simple_test/cal_test.txt