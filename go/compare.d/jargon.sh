# lint-jargon の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate jargon bin/lint-jargon.py -- jargon
run_gate jargon-all bin/lint-jargon.py --all -- jargon --all
run_gate jargon-all-warn bin/lint-jargon.py --all --show-warn -- jargon --all --show-warn
run_gate jargon-selftest bin/lint-jargon.py --self-test -- jargon --self-test
run_gate_split jargon bin/lint-jargon.py -- jargon
run_gate_split jargon-all-warn bin/lint-jargon.py --all --show-warn -- jargon --all --show-warn
run_fixtures_go jargon lint-jargon.py
