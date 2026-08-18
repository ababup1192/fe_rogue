# check-api-released の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate check-api-released bin/check-api-released.py -- check-api-released
run_gate check-api-released-needle bin/check-api-released.py depth -- check-api-released depth
run_gate_split check-api-released bin/check-api-released.py -- check-api-released
run_gate_split check-api-released-needle bin/check-api-released.py depth -- check-api-released depth

# 負の見本 (testdata/lint/check-api-released/) を Python・Go・expected.txt の 3 者で見る。
# WhyNot: 共通の run_fixtures_go を使わないのは、この検査の見本が「使い捨ての git リポを
# 組んで tag まで打つ」形（$ENGINE / $CASE / $WORK が要る）で、run_fixtures_go の
# 「呼び口の 1 行を戻すだけ」では走らないため。
apireleased_run_case() { # apireleased_run_case <ケースのフォルダ> <出力先> [sed の台本]
  cw=$(mktemp -d)
  # WhyNot: CASE を先に絶対パスへ直すのは、cd した後の subshell で相対パスを解くと
  # 「そんなフォルダは無い」の 1 行が出力に混ざるため。
  cabs=$(cd "$1" && pwd)
  if [ -n "${3:-}" ]; then script=$(sed "$3" "$1/cmd.txt"); else script=$(cat "$1/cmd.txt"); fi
  { (cd "$cabs" && ENGINE="$ROOT" CASE="$cabs" WORK="$cw" sh -c "$script") 2>&1
    echo "exit=$?"; } >"$2"
  rm -rf "$cw"
}

if [ -d testdata/lint/check-api-released ]; then
  echo "== 負の見本 check-api-released (Python・Go・expected.txt の 3 者)"
  # 見本の台本は Go を呼ぶ。Python 側は呼び口を .py へ戻し、規約フォルダを写す行を
  # .py を写す行に替える（Python 版は偽リポの bin/ に置いた .py 自身から根を決めるため）。
  apireleased_sed='s|cp -R "$ENGINE/bin/lint-rules" "$WORK/bin/"|cp "$ENGINE/bin/check-api-released.py" "$WORK/bin/"|
s|"$ENGINE/bin/fge" check-api-released --root "$WORK"|python3 "$WORK/bin/check-api-released.py"|'
  for case_dir in testdata/lint/check-api-released/*/; do
    case_dir=${case_dir%/}
    [ -f "$case_dir/cmd.txt" ] || continue
    name="lint 見本 ${case_dir#testdata/lint/}"
    apireleased_run_case "$case_dir" "$WORK/go.apireleased"
    apireleased_run_case "$case_dir" "$WORK/py.apireleased" "$apireleased_sed"
    sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$case_dir/expected.txt" >"$WORK/exp.apireleased"
    compare_out "$name (Python と Go)" "$WORK/py.apireleased" "$WORK/go.apireleased"
    compare_out "$name (Go と expected.txt)" "$WORK/go.apireleased" "$WORK/exp.apireleased"
  done
fi
