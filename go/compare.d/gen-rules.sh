# gen-rules の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate gen-rules-check bin/gen-rules.py --check -- gen-rules --check
run_gate_split gen-rules-check bin/gen-rules.py --check -- gen-rules --check

# 生成そのものを比べる。
# WhyNot: リポで直に走らせないのは、この道具が .claude/rules と agents-pack/rules を
# 書き換える側だから。docs/ と bin/ だけを写した使い捨ての根を 2 つ作り、
# Python 版と Go 版にそれぞれ書かせて、出た .md と報告の字面を突き合わせる。
echo "== gen-rules (生成した .md をバイト比較)"
grroot=$WORK/gen-rules
for side in py go; do
  mkdir -p "$grroot/$side/bin/lint-rules"
  cp bin/gen-rules.py "$grroot/$side/bin/"
  cp bin/lint-rules/gen-rules.json "$grroot/$side/bin/lint-rules/"
  cp -R docs "$grroot/$side/docs"
done
python3 "$grroot/py/bin/gen-rules.py" >"$WORK/py.gen-rules.write" 2>&1
"$GO" gen-rules --root "$grroot/go" >"$WORK/go.gen-rules.write" 2>&1
compare_out "gen-rules (書き出しの報告)" "$WORK/py.gen-rules.write" "$WORK/go.gen-rules.write"
for rel in .claude/rules/drawing.md .claude/rules/flix.md .claude/rules/error-handling.md \
  agents-pack/rules/drawing.md agents-pack/rules/flix.md agents-pack/rules/error-handling.md; do
  if [ ! -f "$grroot/py/$rel" ] || [ ! -f "$grroot/go/$rel" ]; then
    note ng "gen-rules $rel (どちらかが無い)"
    continue
  fi
  compare_out "gen-rules $rel" "$grroot/py/$rel" "$grroot/go/$rel"
done

# 2 回目は何も書かない (報告が空) ことも見る。
python3 "$grroot/py/bin/gen-rules.py" >"$WORK/py.gen-rules.again" 2>&1
"$GO" gen-rules --root "$grroot/go" >"$WORK/go.gen-rules.again" 2>&1
compare_out "gen-rules (2 回目の報告)" "$WORK/py.gen-rules.again" "$WORK/go.gen-rules.again"

# --check も使い捨ての根で見る (生成済みなので緑・1 本消せば赤)。
python3 "$grroot/py/bin/gen-rules.py" --check >"$WORK/py.gen-rules.chk" 2>&1
"$GO" gen-rules --root "$grroot/go" --check >"$WORK/go.gen-rules.chk" 2>&1
compare_out "gen-rules --check (使い捨ての根)" "$WORK/py.gen-rules.chk" "$WORK/go.gen-rules.chk"

: >"$grroot/py/.claude/rules/flix.md"
: >"$grroot/go/.claude/rules/flix.md"
python3 "$grroot/py/bin/gen-rules.py" --check >"$WORK/py.gen-rules.stale" 2>&1
pystale=$?
"$GO" gen-rules --root "$grroot/go" --check >"$WORK/go.gen-rules.stale" 2>&1
gostale=$?
compare_out "gen-rules --check (ずれている)" "$WORK/py.gen-rules.stale" "$WORK/go.gen-rules.stale"
if [ "$pystale" = "$gostale" ]; then
  note ok "gen-rules --check (ずれている・終了コード)"
else
  note ng "gen-rules --check (ずれている・終了コード $pystale vs $gostale)"
fi

# 元の doc が無いときの断り方。
rm -f "$grroot/py/docs/flix-conventions.md" "$grroot/go/docs/flix-conventions.md"
python3 "$grroot/py/bin/gen-rules.py" >"$WORK/py.gen-rules.nosrc" 2>&1
pynosrc=$?
"$GO" gen-rules --root "$grroot/go" >"$WORK/go.gen-rules.nosrc" 2>&1
gonosrc=$?
compare_out "gen-rules (元の doc が無い)" "$WORK/py.gen-rules.nosrc" "$WORK/go.gen-rules.nosrc"
if [ "$pynosrc" = "$gonosrc" ]; then
  note ok "gen-rules (元の doc が無い・終了コード)"
else
  note ng "gen-rules (元の doc が無い・終了コード $pynosrc vs $gonosrc)"
fi
