# gen-api-digest の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
run_gate api-digest bin/gen-api-digest.py --check -- api-digest --check
run_gate_split api-digest bin/gen-api-digest.py --check -- api-digest --check

# 生成物そのものを比べる。
# WhyNot: Python 版を書き出しモードで走らせないのは、リポの docs/ を上書きするため。
# docs/ に今ある物が Python 版の生成物なので、Go 版を別の場所へ出して突き合わせる。
# 日付行 (生成: YYYY-MM-DD) は Python 側の dateless() と同じく均してから比べる。
echo "== api-digest (生成物を docs/ とバイト比較)"
adg=$WORK/api-digest
"$GO" api-digest --out "$adg" >"$WORK/go.api-digest.write" 2>&1
for rel in api-digest.md api-digest/engine.md api-digest/engine_world.md api-digest/engine_tools.md; do
  if [ ! -f "docs/$rel" ] || [ ! -f "$adg/$rel" ]; then
    note ng "api-digest docs/$rel (どちらかが無い)"
    continue
  fi
  sed 's/生成: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/生成: 0000-00-00/' \
    "docs/$rel" >"$WORK/adg.py"
  sed 's/生成: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/生成: 0000-00-00/' \
    "$adg/$rel" >"$WORK/adg.go"
  compare_out "api-digest docs/$rel" "$WORK/adg.py" "$WORK/adg.go"
done
