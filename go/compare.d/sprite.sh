# lint-sprite の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate sprite bin/lint-sprite.py -- sprite
run_gate sprite-strict bin/lint-sprite.py --strict -- sprite --strict
run_gate sprite-selftest bin/lint-sprite.py --self-test -- sprite --self-test
run_gate_split sprite bin/lint-sprite.py -- sprite
run_gate_split sprite-strict bin/lint-sprite.py --strict -- sprite --strict
run_gate_split sprite-selftest bin/lint-sprite.py --self-test -- sprite --self-test
run_fixtures_go sprite lint-sprite.py
