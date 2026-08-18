# lint-f32 の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate f32 bin/lint-f32.py -- f32
run_gate f32-selftest bin/lint-f32.py --self-test -- f32 --self-test
run_gate_split f32 bin/lint-f32.py -- f32
run_gate_split f32-selftest bin/lint-f32.py --self-test -- f32 --self-test

# 負の見本 (testdata/lint/f32/) を Python・Go・expected.txt の 3 者で見る。
# WhyNot: 共通の run_fixtures_go を使わないのは、Python 版にファイルを渡す口も
# 除外一覧を差し替える口も無く、呼び口の 1 行を戻すだけでは鳴らせないため
# (Go 版は --root と --exempt-json でそのまま呼べる)。
# WhyNot: この足場を testdata/ の harness.py に置かないのは、見本を Python 抜きで
# 回せる形に保つため。Python を鳴らす足場は Python が残っている間だけ要る物なので、
# 突き合わせの道具であるここに置く。
f32_case() { # f32_case <ケース名> <除外一覧の JSON>
  dir=testdata/lint/f32/$1
  [ -f "$dir/cmd.txt" ] || return 0
  name="lint 見本 f32/$1"
  { python3 - "$dir/Sample.flix" "$2" <<'PYEOF'
import importlib.util
import json
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("lint_f32_compare", "bin/lint-f32.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.EXEMPT = json.loads(sys.argv[2])
raise SystemExit(mod.report(mod.scan_source(Path(sys.argv[1]), "Sample.flix")))
PYEOF
    echo "exit=$?"; } >"$WORK/py.f32case" 2>&1
  { (CASE=$ROOT/$dir sh "$dir/cmd.txt") 2>&1
    echo "exit=$?"; } >"$WORK/go.f32case"
  sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$dir/expected.txt" >"$WORK/exp.f32case"
  compare_out "$name (Python と Go)" "$WORK/py.f32case" "$WORK/go.f32case"
  compare_out "$name (Go と expected.txt)" "$WORK/go.f32case" "$WORK/exp.f32case"
}

if [ -d testdata/lint/f32 ]; then
  echo "== 負の見本 f32 (Python・Go・expected.txt の 3 者)"
  f32_case float32-pub-fires '{}'
  f32_case float32-exempt-no-fire '{"Demo.setScale": "テスト用: 除外による無効化の見本"}'
  f32_case stale-exempt-fires '{"Ghost.longGoneFn": "テスト用: 実在しない除外エントリ"}'
fi
