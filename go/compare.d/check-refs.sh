# check-refs の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate check-refs bin/check-refs.py -- check-refs
run_gate_split check-refs bin/check-refs.py -- check-refs
run_gate check-refs-bundle bin/check-refs.py --bundle . -- check-refs --bundle .
run_gate_split check-refs-bundle bin/check-refs.py --bundle . -- check-refs --bundle .
run_gate check-refs-bundle-win bin/check-refs.py --bundle . --windows -- check-refs --bundle . --windows
run_gate_split check-refs-bundle-win bin/check-refs.py --bundle . --windows -- check-refs --bundle . --windows
run_gate check-refs-bundle-missing bin/check-refs.py --bundle nowhere -- check-refs --bundle nowhere
run_gate_split check-refs-bundle-missing bin/check-refs.py --bundle nowhere -- check-refs --bundle nowhere
run_gate check-refs-bundle-usage bin/check-refs.py --bundle -- check-refs --bundle
run_gate_split check-refs-bundle-usage bin/check-refs.py --bundle -- check-refs --bundle

# 負の見本 (testdata/lint/check-refs/) を Python・Go・expected.txt の 3 者で見る。
# WhyNot: 共通の run_fixtures_go を使わないのは、この検査の見本が「使い捨ての偽リポを
# 組んでそこから走らせる」形（$ENGINE / $CASE / $WORK が要る複数行の台本）で、
# run_fixtures_go の「呼び口の 1 行を戻すだけ」では走らないため。
checkrefs_run_case() { # checkrefs_run_case <ケースのフォルダ> <出力先> [sed の台本]
  cw=$(mktemp -d)
  # WhyNot: 絶対パスを先に取っておくのは、cd した後の代入の中で相対パスを解き直すと
  # 「そんなフォルダは無い」になり、その文句まで出力に混ざるため。
  abs=$(cd "$1" && pwd)
  if [ -n "${3:-}" ]; then script=$(sed "$3" "$1/cmd.txt"); else script=$(cat "$1/cmd.txt"); fi
  { (cd "$abs" && ENGINE="$ROOT" CASE="$abs" WORK="$cw" sh -c "$script") 2>&1
    echo "exit=$?"; } >"$2"
  rm -rf "$cw"
}

if [ -d testdata/lint/check-refs ]; then
  echo "== 負の見本 check-refs (Python・Go・expected.txt の 3 者)"
  # 見本の台本は Go を呼ぶ。Python 側は呼び口を .py へ戻し、規約フォルダを写す行を
  # .py を写す行に替える（Python 版は偽リポの bin/ に置いた .py 自身から根を決めるため）。
  checkrefs_sed='s|cp -R "$ENGINE/bin/lint-rules" "$WORK/bin/"|cp "$ENGINE/bin/check-refs.py" "$WORK/bin/"|
s|"$ENGINE/bin/fge" check-refs --root "$WORK"|python3 "$WORK/bin/check-refs.py"|
s|"$ENGINE/bin/fge" check-refs --root "$ENGINE"|python3 "$ENGINE/bin/check-refs.py"|'
  for case_dir in testdata/lint/check-refs/*/; do
    case_dir=${case_dir%/}
    [ -f "$case_dir/cmd.txt" ] || continue
    name="lint 見本 ${case_dir#testdata/lint/}"
    checkrefs_run_case "$case_dir" "$WORK/go.checkrefs"
    checkrefs_run_case "$case_dir" "$WORK/py.checkrefs" "$checkrefs_sed"
    sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$case_dir/expected.txt" >"$WORK/exp.checkrefs"
    compare_out "$name (Python と Go)" "$WORK/py.checkrefs" "$WORK/go.checkrefs"
    compare_out "$name (Go と expected.txt)" "$WORK/go.checkrefs" "$WORK/exp.checkrefs"
  done
fi
