# 負の見本を Python・Go・expected.txt の 3 者で見るための共通の口。
# go/compare.sh から読まれる (単体では走らない)。名前が 00- なのは、下の関数を使う
# 検査の断片より先に読ませるため (断片は go/compare.d/*.sh の名前順に読まれる)。
#
# compare.sh 自身が持つ run_fixtures とは向きが逆。見本の cmd.txt はもう Go を呼ぶので、
# Python 側は呼び口を bin/<検査>.py へ戻してから走らせる。
run_fixtures_go() { # run_fixtures_go <検査名> <戻す先の .py の名前> [別扱いにするケース名...]
  fx_check=$1
  fx_script=$2
  shift 2
  fx_skip=" $* "
  [ -d "testdata/lint/$fx_check" ] || return 0
  echo "== 負の見本 $fx_check (Python・Go・expected.txt の 3 者)"
  for case_dir in "testdata/lint/$fx_check"/*/; do
    case_dir=${case_dir%/}
    [ -f "$case_dir/cmd.txt" ] || continue
    case $fx_skip in *" ${case_dir##*/} "*) continue ;; esac
    name="lint 見本 ${case_dir#testdata/lint/}"
    { sh "$case_dir/cmd.txt" 2>&1; echo "exit=$?"; } >"$WORK/go.case"
    sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$case_dir/expected.txt" >"$WORK/exp.case"
    compare_out "$name (Go と expected.txt)" "$WORK/go.case" "$WORK/exp.case"
    sed "s|^bin/fge $fx_check |python3 bin/$fx_script |" "$case_dir/cmd.txt" >"$WORK/py.cmd"
    # WhyNot: 黙って通さないのは、書き換わらなかった台本が Go 同士の比較になり、
    # Python を 1 度も走らせないまま「一致」と数えられるため (緑が嘘になる)。
    if cmp -s "$WORK/py.cmd" "$case_dir/cmd.txt"; then
      note ng "$name (Python へ戻せない: bin/fge $fx_check を直に呼んでいない)"
      continue
    fi
    { sh "$WORK/py.cmd" 2>&1; echo "exit=$?"; } >"$WORK/py.case"
    compare_out "$name (Python と Go)" "$WORK/py.case" "$WORK/go.case"
  done
}
