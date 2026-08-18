# check-render-budget の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
#
# 引数なし・--brief・--gate の 3 通りをリポ自身の gallery で見る。
run_gate render-budget bin/check-render-budget.py -- check-render-budget
run_gate render-budget-brief bin/check-render-budget.py --brief -- check-render-budget --brief
run_gate render-budget-gate bin/check-render-budget.py . --gate reference/ITEMS.tsv \
  -- check-render-budget . --gate reference/ITEMS.tsv
run_gate_split render-budget bin/check-render-budget.py -- check-render-budget
run_gate_split render-budget-brief bin/check-render-budget.py --brief -- check-render-budget --brief
run_gate_split render-budget-gate bin/check-render-budget.py . --gate reference/ITEMS.tsv \
  -- check-render-budget . --gate reference/ITEMS.tsv

# 負の見本 (testdata/lint/check-render-budget/) を Python・Go・expected.txt の 3 者で見る。
# WhyNot: 共通の run_fixtures_go を使わないのは、この見本の cwd がケースのフォルダで、
# 呼び口が $ENGINE 経由の 1 行になっているため。
if [ -d testdata/lint/check-render-budget ]; then
  echo "== 負の見本 check-render-budget (Python・Go・expected.txt の 3 者)"
  for case_dir in testdata/lint/check-render-budget/*/; do
    [ -f "$case_dir/cmd.txt" ] || continue
    name="lint 見本 ${case_dir#testdata/lint/}"
    ( cd "$case_dir" || exit 1
      ENGINE=$ROOT sh cmd.txt 2>&1
      echo "exit=$?" ) >"$WORK/go.rbcase"
    ( cd "$case_dir" || exit 1
      sed "s|\"\$ENGINE/bin/fge\" check-render-budget --root \"\$ENGINE\"|python3 \"\$ENGINE/bin/check-render-budget.py\"|" \
        cmd.txt >"$WORK/rb.cmd"
      ENGINE=$ROOT sh "$WORK/rb.cmd" 2>&1
      echo "exit=$?" ) >"$WORK/py.rbcase"
    sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$case_dir/expected.txt" >"$WORK/exp.rbcase"
    compare_out "$name (Python と Go)" "$WORK/py.rbcase" "$WORK/go.rbcase"
    compare_out "$name (Go と expected.txt)" "$WORK/go.rbcase" "$WORK/exp.rbcase"
  done
fi
