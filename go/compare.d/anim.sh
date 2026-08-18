# lint-anim の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate anim bin/lint-anim.py -- anim
run_gate anim-strict bin/lint-anim.py --strict -- anim --strict
run_gate anim-selftest bin/lint-anim.py --self-test -- anim --self-test
run_gate_split anim bin/lint-anim.py -- anim
run_gate_split anim-strict bin/lint-anim.py --strict -- anim --strict
run_gate_split anim-selftest bin/lint-anim.py --self-test -- anim --self-test
run_fixtures_go anim lint-anim.py
