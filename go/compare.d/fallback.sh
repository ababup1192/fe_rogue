# lint-fallback の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate fallback bin/lint-fallback.py -- fallback
run_gate fallback-all bin/lint-fallback.py --all -- fallback --all
run_gate fallback-strict bin/lint-fallback.py --strict -- fallback --strict
run_gate fallback-selftest bin/lint-fallback.py --self-test -- fallback --self-test
run_gate_split fallback bin/lint-fallback.py -- fallback
run_gate_split fallback-all bin/lint-fallback.py --all -- fallback --all
run_gate_split fallback-strict bin/lint-fallback.py --strict -- fallback --strict
run_gate_split fallback-selftest bin/lint-fallback.py --self-test -- fallback --self-test
run_fixtures_go fallback lint-fallback.py stale-exempt-fires

# 「古い除外検出」の見本だけは別扱い。Go 版は使い捨ての偽リポへ規約データを写して
# exempt を差し替えるが、Python 版にはその口が無い。
# WhyNot: この足場を testdata/ の harness.py に置かないのは、見本を Python 抜きで
# 回せる形に保つため。Python を鳴らす足場は Python が残っている間だけ要る物なので、
# 突き合わせの道具であるここに置く。
fallback_stale_case() {
  dir=testdata/lint/fallback/stale-exempt-fires
  [ -f "$dir/cmd.txt" ] || return 0
  name="lint 見本 fallback/stale-exempt-fires"
  fw=$(mktemp -d)
  { (ENGINE=$ROOT CASE=$ROOT/$dir WORK=$fw sh "$dir/cmd.txt") 2>&1
    echo "exit=$?"; } >"$WORK/go.fbcase"
  rm -rf "$fw"
  { python3 - "$dir/Sample.flix" <<'PYEOF'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("lint_fallback_compare", "bin/lint-fallback.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.EXEMPT = {"Ghost.flix::ghostFn": "テスト用: 実在しない除外エントリ"}
hits = mod.file_hits([sys.argv[1]])
live = {h.key for h in hits}
stale = sorted(set(mod.EXEMPT) - live)
raise SystemExit(mod.report(mod.violations(hits), len(hits), True, stale))
PYEOF
    echo "exit=$?"; } >"$WORK/py.fbcase" 2>&1
  sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$dir/expected.txt" >"$WORK/exp.fbcase"
  compare_out "$name (Go と expected.txt)" "$WORK/go.fbcase" "$WORK/exp.fbcase"
  compare_out "$name (Python と Go)" "$WORK/py.fbcase" "$WORK/go.fbcase"
}
fallback_stale_case
