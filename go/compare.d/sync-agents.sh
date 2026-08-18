# sync-agents の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
#
# WhyNot: 本物のゲームのリポへ配って見ないのは、この道具が他のリポへ書き込む側だから。
# engine 側 (配り元) は読むだけなのでリポをそのまま使い、配り先だけ使い捨てにする。

run_gate sync-agents-check-manifest bin/sync-agents.py --check-manifest -- sync-agents --check-manifest
run_gate_split sync-agents-check-manifest bin/sync-agents.py --check-manifest -- sync-agents --check-manifest
run_gate sync-agents-nogame bin/sync-agents.py -- sync-agents
run_gate_split sync-agents-nogame bin/sync-agents.py -- sync-agents
run_gate sync-agents-help bin/sync-agents.py --help -- sync-agents --help
run_gate_split sync-agents-help bin/sync-agents.py --help -- sync-agents --help
run_gate sync-agents-h bin/sync-agents.py -h -- sync-agents -h
run_gate sync-agents-bogus bin/sync-agents.py --bogus -- sync-agents --bogus
run_gate_split sync-agents-bogus bin/sync-agents.py --bogus -- sync-agents --bogus
run_gate sync-agents-extra bin/sync-agents.py x y -- sync-agents x y
run_gate sync-agents-novalue bin/sync-agents.py --game -- sync-agents --game
run_gate_split sync-agents-novalue bin/sync-agents.py --game -- sync-agents --game
run_gate sync-agents-novalue-version bin/sync-agents.py --version -- sync-agents --version
run_gate sync-agents-abbrev bin/sync-agents.py --c -- sync-agents --c
run_gate sync-agents-abbrev-game bin/sync-agents.py --ga /nope/xyz -- sync-agents --ga /nope/xyz
run_gate sync-agents-missing-game bin/sync-agents.py --game /nope/xyz -- sync-agents --game /nope/xyz
run_gate_split sync-agents-missing-game bin/sync-agents.py --game /nope/xyz -- sync-agents --game /nope/xyz
run_gate sync-agents-missing-game-slash bin/sync-agents.py --game=/nope//xyz/ -- sync-agents --game=/nope//xyz/

# 配った木そのものを比べる。偽リポ 2 つ (Python 用・Go 用) へ配って中身と実行ビットを見る。
# WhyNot: $WORK をそのまま使わずに symlink を辿った形にするのは、Python 側の ROOT が
# Path(__file__).resolve() で /private/var... に化けて、読めなかったファイルの
# 名前を出すときだけ字面がずれるため。
sa=$(cd "$WORK" && pwd -P)/sync-agents
mkdir -p "$sa"

sa_files() { # sa_files <木> — ファイルとフォルダの一覧
  (cd "$1" && find . | LC_ALL=C sort)
}
sa_exec() { # sa_exec <木> — 実行ビットが立っているファイルの一覧
  (cd "$1" && find . -type f -perm -u+x | LC_ALL=C sort)
}

sa_round() { # sa_round <名前> <py 側> <go 側> <version>
  label=$1
  pyg=$2
  gog=$3
  ver=$4
  python3 bin/sync-agents.py --game "$pyg" --version "$ver" >"$WORK/py.sa.$label" 2>&1
  pyexit=$?
  "$GO" sync-agents --game "$gog" --version "$ver" >"$WORK/go.sa.$label" 2>&1
  goexit=$?
  # 報告には配り先のパスが出るので、そこだけ均してから比べる。
  sed "s|$pyg|GAME|g" "$WORK/py.sa.$label" >"$WORK/py.sa.$label.norm"
  sed "s|$gog|GAME|g" "$WORK/go.sa.$label" >"$WORK/go.sa.$label.norm"
  compare_out "sync-agents $label (配りの報告)" "$WORK/py.sa.$label.norm" "$WORK/go.sa.$label.norm"
  if [ "$pyexit" = "$goexit" ]; then
    note ok "sync-agents $label (終了コード)"
  else
    note ng "sync-agents $label (終了コード $pyexit vs $goexit)"
  fi
  sa_files "$pyg" >"$WORK/py.sa.$label.files"
  sa_files "$gog" >"$WORK/go.sa.$label.files"
  compare_out "sync-agents $label (配ったファイルの一覧)" "$WORK/py.sa.$label.files" "$WORK/go.sa.$label.files"
  sa_exec "$pyg" >"$WORK/py.sa.$label.exec"
  sa_exec "$gog" >"$WORK/go.sa.$label.exec"
  compare_out "sync-agents $label (実行ビット)" "$WORK/py.sa.$label.exec" "$WORK/go.sa.$label.exec"
  if diff -r "$pyg" "$gog" >"$WORK/sa.$label.diff" 2>&1; then
    note ok "sync-agents $label (配った中身)"
  else
    note ng "sync-agents $label (配った中身が違う)"
  fi
}

echo "== sync-agents (使い捨ての偽リポへ配って木ごと突き合わせ)"
mkdir -p "$sa/plain-py" "$sa/plain-go"
sa_round plain "$sa/plain-py" "$sa/plain-go" 9.9.9
# 2 回目は copyIfAbsent が黙る (冪等)。
sa_round plain-again "$sa/plain-py" "$sa/plain-go" 9.9.9

mkdir -p "$sa/local-py" "$sa/local-go"
for side in py go; do
  printf 'ゲーム固有の決まり\n\n- 何か\n\n\n' >"$sa/local-$side/AGENTS.local.md"
done
sa_round local "$sa/local-py" "$sa/local-go" 0.0.1

# manifest が壊れているときの断り方。engine 側を使い捨ての根にして見る。
# WhyNot: 本物の agents-pack/manifest.json を触らないのは、読むだけと決めているため。
echo "== sync-agents --check-manifest (壊れた manifest)"
sa_root() { # sa_root <名前> <manifest の中身>
  name=$1
  body=$2
  for side in py go; do
    r=$sa/root-$name-$side
    mkdir -p "$r/bin/lint-rules" "$r/agents-pack/skills/alpha" "$r/agents-pack/rules" "$r/docs"
    cp bin/sync-agents.py "$r/bin/"
    cp bin/lint-rules/sync-agents.json "$r/bin/lint-rules/"
    printf 'description: "使い捨ての skill。テストに使う。"\n' >"$r/agents-pack/skills/alpha/SKILL.md"
    printf 'AGENTS core\n' >"$r/agents-pack/AGENTS.core.md"
    printf '.claude/skills/alpha/SKILL.md\n' >"$r/agents-pack/rules/ok.md"
    printf '.claude/skills/nope/SKILL.md と .claude/skills/alpha/SKILL.md\n' >"$r/docs/link.md"
    printf '%s' "$body" >"$r/agents-pack/manifest.json"
  done
  python3 "$sa/root-$name-py/bin/sync-agents.py" --check-manifest \
    >"$WORK/py.sa.cm.$name.out" 2>"$WORK/py.sa.cm.$name.err"
  pyexit=$?
  "$GO" sync-agents --root "$sa/root-$name-go" --check-manifest \
    >"$WORK/go.sa.cm.$name.out" 2>"$WORK/go.sa.cm.$name.err"
  goexit=$?
  sed "s|$sa/root-$name-py|ROOT|g" "$WORK/py.sa.cm.$name.err" >"$WORK/py.sa.cm.$name.err.norm"
  sed "s|$sa/root-$name-go|ROOT|g" "$WORK/go.sa.cm.$name.err" >"$WORK/go.sa.cm.$name.err.norm"
  compare_out "sync-agents --check-manifest $name (stdout)" "$WORK/py.sa.cm.$name.out" "$WORK/go.sa.cm.$name.out"
  compare_out "sync-agents --check-manifest $name (stderr)" \
    "$WORK/py.sa.cm.$name.err.norm" "$WORK/go.sa.cm.$name.err.norm"
  if [ "$pyexit" = "$goexit" ]; then
    note ok "sync-agents --check-manifest $name (終了コード)"
  else
    note ng "sync-agents --check-manifest $name (終了コード $pyexit vs $goexit)"
  fi
}

sa_root ok '{"copy":[{"src":"bin/sync-agents.py","dst":"bin/sync-agents.py"}],"copyIfAbsent":[],"copyDirs":[]}'
sa_root missing-src '{"copy":[{"src":"bin/nope.py","dst":"bin/nope.py"}],"copyIfAbsent":[{"src":"bin/also-nope","dst":"x"}],"copyDirs":[]}'
sa_root empty ''
sa_root trailing-comma '{"copy":[],"copyIfAbsent":[],"copyDirs":[],}'
sa_root no-comma '{"copy":[] "copyIfAbsent":[]}'
sa_root single-quote "{'copy':[]}"
sa_root extra-data '{"copy":[],"copyIfAbsent":[],"copyDirs":[]} x'
sa_root unterminated '{"copy":[],"copyIfAbsent":[],"copyDirs":['
sa_root bad-escape '{"copy":"a\qb"}'
sa_root bad-unicode-escape '{"copy":"a\u12"}'
sa_root not-list '{"copy":{},"copyIfAbsent":[],"copyDirs":[]}'
sa_root missing-key '{"copyIfAbsent":[],"copyDirs":[]}'
sa_root elem-not-dict '{"copy":["bin/fge"],"copyIfAbsent":[],"copyDirs":[]}'
sa_root elem-no-dst '{"copy":[{"src":"bin/fge"}],"copyIfAbsent":[],"copyDirs":[]}'
sa_root elem-number '{"copy":[12],"copyIfAbsent":[],"copyDirs":[]}'
sa_root elem-nested '{"copy":[{"srcs":["a","b"],"n":1.5,"ok":true,"no":null}],"copyIfAbsent":[],"copyDirs":[]}'
sa_root elem-quote "{\"copy\":[\"it's\"],\"copyIfAbsent\":[],\"copyDirs\":[]}"
sa_root two-lines '{
  "copy": [] "copyIfAbsent": []
}'

# manifest そのものが無いとき (OSError の字面)。
for side in py go; do
  r=$sa/root-nofile-$side
  mkdir -p "$r/bin/lint-rules" "$r/agents-pack"
  cp bin/sync-agents.py "$r/bin/"
  cp bin/lint-rules/sync-agents.json "$r/bin/lint-rules/"
done
python3 "$sa/root-nofile-py/bin/sync-agents.py" --check-manifest \
  >"$WORK/py.sa.cm.nofile.out" 2>"$WORK/py.sa.cm.nofile.err"
pyexit=$?
"$GO" sync-agents --root "$sa/root-nofile-go" --check-manifest \
  >"$WORK/go.sa.cm.nofile.out" 2>"$WORK/go.sa.cm.nofile.err"
goexit=$?
sed "s|$sa/root-nofile-py|ROOT|g" "$WORK/py.sa.cm.nofile.err" >"$WORK/py.sa.cm.nofile.err.norm"
sed "s|$sa/root-nofile-go|ROOT|g" "$WORK/go.sa.cm.nofile.err" >"$WORK/go.sa.cm.nofile.err.norm"
compare_out "sync-agents --check-manifest nofile (stderr)" \
  "$WORK/py.sa.cm.nofile.err.norm" "$WORK/go.sa.cm.nofile.err.norm"
if [ "$pyexit" = "$goexit" ]; then
  note ok "sync-agents --check-manifest nofile (終了コード)"
else
  note ng "sync-agents --check-manifest nofile (終了コード $pyexit vs $goexit)"
fi

# manifest がフォルダのとき (別の errno)。
for side in py go; do
  mkdir -p "$sa/root-isdir-$side/bin/lint-rules" "$sa/root-isdir-$side/agents-pack/manifest.json"
  cp bin/sync-agents.py "$sa/root-isdir-$side/bin/"
  cp bin/lint-rules/sync-agents.json "$sa/root-isdir-$side/bin/lint-rules/"
done
python3 "$sa/root-isdir-py/bin/sync-agents.py" --check-manifest >/dev/null 2>"$WORK/py.sa.cm.isdir.err"
pyexit=$?
"$GO" sync-agents --root "$sa/root-isdir-go" --check-manifest >/dev/null 2>"$WORK/go.sa.cm.isdir.err"
goexit=$?
sed "s|$sa/root-isdir-py|ROOT|g" "$WORK/py.sa.cm.isdir.err" >"$WORK/py.sa.cm.isdir.err.norm"
sed "s|$sa/root-isdir-go|ROOT|g" "$WORK/go.sa.cm.isdir.err" >"$WORK/go.sa.cm.isdir.err.norm"
compare_out "sync-agents --check-manifest isdir (stderr)" \
  "$WORK/py.sa.cm.isdir.err.norm" "$WORK/go.sa.cm.isdir.err.norm"
if [ "$pyexit" = "$goexit" ]; then
  note ok "sync-agents --check-manifest isdir (終了コード)"
else
  note ng "sync-agents --check-manifest isdir (終了コード $pyexit vs $goexit)"
fi

# 使い捨ての根から配る (skill 一覧・description の切り出し・AGENTS.md の組み立て)。
echo "== sync-agents (使い捨ての根から配る)"
for side in py go; do
  r=$sa/pack-$side
  mkdir -p "$r/bin/lint-rules" "$r/agents-pack/rules" "$r/docs" "$r/game/bin"
  cp bin/sync-agents.py "$r/bin/"
  cp bin/lint-rules/sync-agents.json "$r/bin/lint-rules/"
  printf '# core\n\n本文\n\n\n' >"$r/agents-pack/AGENTS.core.md"
  printf 'x\n' >"$r/agents-pack/rules/a.md"
  mkdir -p "$r/agents-pack/skills/beta" "$r/agents-pack/skills/alpha" "$r/agents-pack/skills/no-skill-md"
  printf -- '---\nname: beta\ndescription: "能書き。〜のときに使う。補足。"\n---\n' \
    >"$r/agents-pack/skills/beta/SKILL.md"
  printf -- '---\ndescription: 引き金の無い説明\n---\n' >"$r/agents-pack/skills/alpha/SKILL.md"
  printf 'x\n' >"$r/bin/lint-fake.py"
  chmod +x "$r/bin/lint-fake.py"
  printf 'y\n' >"$r/bin/plain.txt"
  printf '{"copy":[{"src":"bin/lint-fake.py","dst":"bin/lint-fake.py"},{"src":"bin/plain.txt","dst":"bin/plain.txt"}],"copyIfAbsent":[{"src":"bin/plain.txt","dst":".claude/settings.json"}],"copyDirs":[{"src":"agents-pack/skills","dst":".claude/skills"},{"src":"agents-pack/rules","dst":".claude/rules"}]}' \
    >"$r/agents-pack/manifest.json"
done
python3 "$sa/pack-py/bin/sync-agents.py" --game "$sa/pack-py/game" --version 1.2.3 \
  >"$WORK/py.sa.pack" 2>&1
pyexit=$?
"$GO" sync-agents --root "$sa/pack-go" --game "$sa/pack-go/game" --version 1.2.3 \
  >"$WORK/go.sa.pack" 2>&1
goexit=$?
sed "s|$sa/pack-py|PACK|g" "$WORK/py.sa.pack" >"$WORK/py.sa.pack.norm"
sed "s|$sa/pack-go|PACK|g" "$WORK/go.sa.pack" >"$WORK/go.sa.pack.norm"
compare_out "sync-agents pack (配りの報告)" "$WORK/py.sa.pack.norm" "$WORK/go.sa.pack.norm"
if [ "$pyexit" = "$goexit" ]; then
  note ok "sync-agents pack (終了コード)"
else
  note ng "sync-agents pack (終了コード $pyexit vs $goexit)"
fi
sa_files "$sa/pack-py/game" >"$WORK/py.sa.pack.files"
sa_files "$sa/pack-go/game" >"$WORK/go.sa.pack.files"
compare_out "sync-agents pack (配ったファイルの一覧)" "$WORK/py.sa.pack.files" "$WORK/go.sa.pack.files"
sa_exec "$sa/pack-py/game" >"$WORK/py.sa.pack.exec"
sa_exec "$sa/pack-go/game" >"$WORK/go.sa.pack.exec"
compare_out "sync-agents pack (実行ビット)" "$WORK/py.sa.pack.exec" "$WORK/go.sa.pack.exec"
if diff -r "$sa/pack-py/game" "$sa/pack-go/game" >"$WORK/sa.pack.diff" 2>&1; then
  note ok "sync-agents pack (配った中身)"
else
  note ng "sync-agents pack (配った中身が違う)"
fi
