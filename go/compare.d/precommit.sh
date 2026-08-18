# precommit の突き合わせ。go/compare.sh から読まれる (単体では走らない)。

# 負の見本 (testdata/lint/precommit/) を Python・Go・expected.txt の 3 者で見る。
# WhyNot: 共通の run_fixtures_go を使わないのは、この検査の見本が「使い捨ての偽リポを
# 組んでそこから走らせる」形（$ENGINE / $CASE / $WORK が要る複数行の台本）で、
# run_fixtures_go の「呼び口の 1 行を戻すだけ」では走らないため。
precommit_run_case() { # precommit_run_case <ケースのフォルダ> <出力先> [sed の台本]
  cw=$(mktemp -d)
  # WhyNot: 絶対パスを先に取っておくのは、cd した後の代入の中で相対パスを解き直すと
  # 「そんなフォルダは無い」になり、その文句まで出力に混ざるため。
  abs=$(cd "$1" && pwd)
  if [ -n "${3:-}" ]; then script=$(sed "$3" "$1/cmd.txt"); else script=$(cat "$1/cmd.txt"); fi
  { (cd "$abs" && ENGINE="$ROOT" CASE="$abs" WORK="$cw" sh -c "$script") 2>&1
    echo "exit=$?"; } >"$2"
  rm -rf "$cw"
}

if [ -d testdata/lint/precommit ]; then
  echo "== 負の見本 precommit (Python・Go・expected.txt の 3 者)"
  # 見本の台本は Go を呼ぶ。Python 側は呼び口を偽リポへ写した .py の 1 行に戻す
  # (FGE_GO=0 は Python 版が Go 版へ逸れないよう固定する印)。
  precommit_sed='s|"$ENGINE/bin/fge" precommit --root "$WORK"|FGE_GO=0 python3 "$WORK/bin/precommit.py"|'
  for case_dir in testdata/lint/precommit/*/; do
    case_dir=${case_dir%/}
    [ -f "$case_dir/cmd.txt" ] || continue
    name="lint 見本 ${case_dir#testdata/lint/}"
    precommit_run_case "$case_dir" "$WORK/go.precommit"
    precommit_run_case "$case_dir" "$WORK/py.precommit" "$precommit_sed"
    sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$case_dir/expected.txt" >"$WORK/exp.precommit"
    compare_out "$name (Python と Go)" "$WORK/py.precommit" "$WORK/go.precommit"
    compare_out "$name (Go と expected.txt)" "$WORK/go.precommit" "$WORK/exp.precommit"
  done
fi

# 本物のリポで、Python が受け付ける呼び方をひととおり突き合わせる。
# WhyNot: --files を使うのは、ステージを汚さずに「指定のパスを裁く道」を通せるため
# (本物のリポで git add は絶対にしない)。
run_gate precommit-files-none bin/precommit.py --files -- precommit --files
run_gate_split precommit-files-none bin/precommit.py --files -- precommit --files
run_gate precommit-files-md bin/precommit.py --files README.md \
  -- precommit --files README.md
run_gate_split precommit-files-md bin/precommit.py --files README.md \
  -- precommit --files README.md
run_gate precommit-files-flix bin/precommit.py --files engine/src/Render.flix \
  -- precommit --files engine/src/Render.flix
run_gate_split precommit-files-flix bin/precommit.py --files engine/src/Render.flix \
  -- precommit --files engine/src/Render.flix
run_gate precommit-files-image bin/precommit.py --files gallery/none.png \
  -- precommit --files gallery/none.png
run_gate_split precommit-files-image bin/precommit.py --files gallery/none.png \
  -- precommit --files gallery/none.png
run_gate precommit-files-missing bin/precommit.py --files no/such/file.txt \
  -- precommit --files no/such/file.txt
run_gate_split precommit-files-missing bin/precommit.py --files no/such/file.txt \
  -- precommit --files no/such/file.txt
run_gate precommit-staged bin/precommit.py -- precommit
run_gate_split precommit-staged bin/precommit.py -- precommit
