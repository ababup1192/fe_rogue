# lint-view の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate view bin/lint-view.py -- view
run_gate view-strict bin/lint-view.py --strict -- view --strict
run_gate_split view bin/lint-view.py -- view
run_gate_split view-strict bin/lint-view.py --strict -- view --strict
run_fixtures_go view lint-view.py
