# check-api-index の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate check-api-index bin/check-api-index.py -- check-api-index
run_gate_split check-api-index bin/check-api-index.py -- check-api-index

# 負の見本 (testdata/lint/check-api-index/) を Python・Go・expected.txt の 3 者で見る。
# WhyNot: 共通の run_fixtures_go を使わないのは、この検査の見本が「使い捨ての偽リポを
# 組んでそこから走らせる」形（$ENGINE / $CASE / $WORK が要る）で、run_fixtures_go の
# 「呼び口の 1 行を戻すだけ」では走らないため。
apiindex_run_case() { # apiindex_run_case <ケースのフォルダ> <出力先> [sed の台本]
  cw=$(mktemp -d)
  # WhyNot: CASE を先に絶対パスへ直すのは、cd した後の subshell で相対パスを解くと
  # 「そんなフォルダは無い」の 1 行が出力に混ざるため。
  cabs=$(cd "$1" && pwd)
  if [ -n "${3:-}" ]; then script=$(sed "$3" "$1/cmd.txt"); else script=$(cat "$1/cmd.txt"); fi
  { (cd "$cabs" && ENGINE="$ROOT" CASE="$cabs" WORK="$cw" sh -c "$script") 2>&1
    echo "exit=$?"; } >"$2"
  rm -rf "$cw"
}

if [ -d testdata/lint/check-api-index ]; then
  echo "== 負の見本 check-api-index (Python・Go・expected.txt の 3 者)"
  # 見本の台本は Go を呼ぶ。Python 側は呼び口を .py へ戻し、規約フォルダを写す行を
  # .py を写す行に替える（Python 版は偽リポの bin/ に置いた .py 自身から根を決めるため）。
  apiindex_sed='s|cp -R "$ENGINE/bin/lint-rules" "$WORK/bin/"|cp "$ENGINE/bin/check-api-index.py" "$WORK/bin/"|
s|"$ENGINE/bin/fge" check-api-index --root "$WORK"|python3 "$WORK/bin/check-api-index.py"|'
  for case_dir in testdata/lint/check-api-index/*/; do
    case_dir=${case_dir%/}
    [ -f "$case_dir/cmd.txt" ] || continue
    name="lint 見本 ${case_dir#testdata/lint/}"
    apiindex_run_case "$case_dir" "$WORK/go.apiindex"
    apiindex_run_case "$case_dir" "$WORK/py.apiindex" "$apiindex_sed"
    sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$case_dir/expected.txt" >"$WORK/exp.apiindex"
    compare_out "$name (Python と Go)" "$WORK/py.apiindex" "$WORK/go.apiindex"
    compare_out "$name (Go と expected.txt)" "$WORK/go.apiindex" "$WORK/exp.apiindex"
  done
fi
