# lint-ui-overflow の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate ui-overflow bin/lint-ui-overflow.py -- ui-overflow
run_gate ui-overflow-strict bin/lint-ui-overflow.py --strict -- ui-overflow --strict
run_gate ui-overflow-selftest bin/lint-ui-overflow.py --self-test -- ui-overflow --self-test
run_gate_split ui-overflow bin/lint-ui-overflow.py -- ui-overflow
run_gate_split ui-overflow-strict bin/lint-ui-overflow.py --strict -- ui-overflow --strict
run_gate_split ui-overflow-selftest bin/lint-ui-overflow.py --self-test -- ui-overflow --self-test

# templates/ の探索だけでは 2 ファイルしか通らないので、リポ中の *.ui.json を全部渡す口も見る。
ui_overflow_files=$(find . -name '*.ui.json' -not -path './build/*' -not -path './*/build/*' |
  sort | tr '\n' ' ')
# shellcheck disable=SC2086
run_gate ui-overflow-files bin/lint-ui-overflow.py $ui_overflow_files -- ui-overflow $ui_overflow_files
# shellcheck disable=SC2086
run_gate_split ui-overflow-files bin/lint-ui-overflow.py $ui_overflow_files -- ui-overflow $ui_overflow_files

run_fixtures_go ui-overflow lint-ui-overflow.py
