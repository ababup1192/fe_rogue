# status の突き合わせ。go/compare.sh から読まれる (単体では走らない)。
#
# WhyNot: 本物のリポを見る run_gate を置かないのは、この道具の出力が「今この瞬間」に
# 依るため。テスト記録の経過・git の状態・スナップショットの枚数は走らせるたびに変わり、
# 常設すると時刻の変わり目でいつか必ず割れる (偽の不一致で緑が信用されなくなる)。
# かわりに使い捨ての偽リポを組み、更新時刻を固定してから突き合わせる。
#
# 時刻の縛り方は 2 段:
#   1. 見に行くファイルの更新時刻を「いま」から固定の秒数だけ戻した所に置く。
#      境界 (90 秒・1 時間・1 日) から 30 分以上離すので、数秒の遅れでは表示が動かない
#   2. 見出しの「%m-%d %H:%M」だけは実時刻。Go には --now で同じ基準を渡し、
#      さらに Python を前後 2 回走らせて同じ物が出たことを確かめる
#      (2 回が割れたら分をまたいだので、その 1 件は不一致として名前を出す)

# 偽リポは local.mk で engine を指す。外から来た ENGINE が勝つと解決順が変わるので外す。
unset ENGINE

status_root=$WORK/status-fake
mkdir -p "$status_root"

status_setmtime() { # status_setmtime <パス> <Unix 秒>
  python3 -c 'import os,sys; t=float(sys.argv[2]); os.utime(sys.argv[1],(t,t))' "$1" "$2"
}

# 偽リポに git の履歴を入れる (ブランチ名とコミット 3 行を出させる)。
status_git_init() { # status_git_init <偽リポ>
  git init -q -b main "$1" 2>/dev/null || { git init -q "$1"; git -C "$1" symbolic-ref HEAD refs/heads/main; }
  git -C "$1" config user.email "t@example.com"
  git -C "$1" config user.name "偽リポ"
  for msg in "最初のコミット" "2 番目 (日本語)" "3 番目"; do
    git -C "$1" -c commit.gpgsign=false commit -q --allow-empty -m "$msg"
  done
}

status_case() { # status_case <名前> <偽リポ>
  name=$1
  repo=$2
  # 分の変わり目をまたぐと見出しだけが割れる。秒に余裕がある所まで待ってから始める。
  # WhyNot: date +%S を数として比べないのは、"08" が 8 進として読まれて
  # 「値が大きすぎる」で落ちる shell があるため。
  while [ $(($(date +%s) % 60)) -gt 50 ]; do sleep 1; done
  now=$(date +%s)
  ( cd "$repo" && python3 "$ROOT/bin/status.py" ) \
    >"$WORK/py.st-$name.out" 2>"$WORK/py.st-$name.err"
  pyexit=$?
  "$GO" status --root "$repo" --now "$now" \
    >"$WORK/go.st-$name.out" 2>"$WORK/go.st-$name.err"
  goexit=$?
  ( cd "$repo" && python3 "$ROOT/bin/status.py" ) >"$WORK/py2.st-$name.out" 2>/dev/null
  if cmp -s "$WORK/py.st-$name.out" "$WORK/py2.st-$name.out"; then
    compare_out "status 偽リポ $name (stdout)" "$WORK/py.st-$name.out" "$WORK/go.st-$name.out"
  else
    note ng "status 偽リポ $name (時計が動いた: Python 2 回が別物)"
  fi
  compare_out "status 偽リポ $name (stderr)" "$WORK/py.st-$name.err" "$WORK/go.st-$name.err"
  if [ "$pyexit" = "$goexit" ]; then
    note ok "status 偽リポ $name (終了コード)"
  else
    note ng "status 偽リポ $name (終了コード $pyexit vs $goexit)"
  fi
}

echo "== status (使い捨ての偽リポ。更新時刻を固定して Python と Go を突き合わせる)"

now0=$(date +%s)

# --- 1. きれいな木 (git だけ。記録もスナップショットも無い) -------------------
repo=$status_root/clean
mkdir -p "$repo"
status_git_init "$repo"
status_case clean "$repo"

# --- 2. 変更が溜まった木 + テスト記録が古い/新しい + チケット + NOTES ---------
repo=$status_root/dirty
mkdir -p "$repo/.test-logs" "$repo/bin/githooks" \
  "$repo/debug/annotations/2026-08-18-001" "$repo/debug/annotations/2026-08-18-002"
status_git_init "$repo"
for i in 1 2 3 4 5 6 7 8 9 10; do
  echo "変更 $i" >"$repo/変更$i.txt"
done
: >"$repo/.test-logs/engine.log"
: >"$repo/.test-logs/engine_world.log"
: >"$repo/.test-logs/render_gl.log"
: >"$repo/.test-logs/a.log"
: >"$repo/.test-logs/b.log"
: >"$repo/.test-logs/c.log"
: >"$repo/.test-logs/d.log"
: >"$repo/.test-logs/e.log"
: >"$repo/.test-logs/f.log"
: >"$repo/.test-logs/落ちた.log"
: >"$repo/.test-logs/落ちた.fail"
: >"$repo/.test-logs/render-title.fail"
: >"$repo/.test-logs/render-battle.fail"
printf '# 見出し\n\n注釈のまとめ 1 行目。ここは 60 文字で切られるので長めに書いておく必要がある。\n' \
  >"$repo/debug/annotations/2026-08-18-001/README.md"
printf '\n\n### かさなった見出し\n' >"$repo/debug/annotations/2026-08-18-002/README.md"
printf '# 次やること\n\n- 1 行目\n\n- 2 行目はとても長い行にして 80 文字で切られることを確かめる。あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほ\n- 3 行目\n- 4 行目\n- 5 行目\n- 6 行目\n- 7 行目 (ここは出ない)\n' \
  >"$repo/NOTES.md"
status_setmtime "$repo/.test-logs/engine.log" $((now0 - 30))          # たった今
status_setmtime "$repo/.test-logs/engine_world.log" $((now0 - 1800))  # 30分前
status_setmtime "$repo/.test-logs/render_gl.log" $((now0 - 19800))    # 5時間前
status_setmtime "$repo/.test-logs/a.log" $((now0 - 475200))           # 5日前
status_setmtime "$repo/.test-logs/落ちた.log" $((now0 - 19800))
status_setmtime "$repo/debug/annotations/2026-08-18-001" $((now0 - 9000))
status_setmtime "$repo/debug/annotations/2026-08-18-002" $((now0 - 5400))
status_setmtime "$repo/NOTES.md" $((now0 - 475200))
status_case dirty "$repo"

# --- 3. ゲームリポ (スナップショットが欠けている・pack と lib のズレ・画風が未定) ---
repo=$status_root/game
mkdir -p "$repo/reference" "$repo/gallery"
status_git_init "$repo"
for f in title battle field shop menu; do
  printf 'これは %s の絵のつもり\n' "$f" >"$repo/gallery/$f.png"
done
printf 'これは余った絵\n' >"$repo/gallery/よけい.png"
{
  # 1 枚だけ本物のハッシュ・1 枚はわざと違うハッシュ・4 枚は gallery に無い
  printf '%s  title.png\n' "$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$repo/gallery/title.png")"
  printf '%064d  battle.png\n' 0
  printf '%064d  無い1.png\n' 1
  printf '%064d  無い2.png\n' 2
  printf '%064d  無い3.png\n' 3
  printf '%064d  無い4.png\n' 4
} >"$repo/reference/SHA256SUMS.txt"
printf 'ENGINE := %s\n' "$ROOT" >"$repo/local.mk"
printf '# agents-pack (engine v0.0.1) の見出し行\n\n本文\n' >"$repo/AGENTS.md"
printf '[dependencies]\n"github:ababup1192/flix_game_engine" = { version = "0.0.2" }\n' >"$repo/flix.toml"
printf '## この画面の画風\n\n最初に決めて、ここに書く\n' >"$repo/AGENTS.local.md"
printf 'total=12\tstatic=2\n' >"$repo/gallery/title.items.tsv"
printf 'total=30\tstatic=0\n' >"$repo/gallery/battle.items.tsv"
status_case game "$repo"

# --- 4. engine が見つからない (local.mk が無い先を指す) -----------------------
repo=$status_root/no-engine
mkdir -p "$repo/gallery"
status_git_init "$repo"
printf 'ENGINE := %s\n' "$status_root/どこにも無い" >"$repo/local.mk"
printf '# agents-pack (engine v0.0.1)\n' >"$repo/AGENTS.md"
printf '"github:ababup1192/flix_game_engine" = { version = "0.0.2" }\n' >"$repo/flix.toml"
printf 'これは絵\n' >"$repo/gallery/a.png"
status_case no-engine "$repo"

# --- 5. git が無い (git 区画が丸ごと黙る) ------------------------------------
repo=$status_root/no-git
mkdir -p "$repo"
printf '引き継ぎ\n' >"$repo/NOTES.md"
status_setmtime "$repo/NOTES.md" $((now0 - 19800))
status_case no-git "$repo"

# --- 6. 予算オーバー (budget NG の 1 行 + 詳細 3 行) --------------------------
repo=$status_root/budget-ng
mkdir -p "$repo/gallery" "$repo/reference"
status_git_init "$repo"
printf 'ENGINE := %s\n' "$ROOT" >"$repo/local.mk"
for f in a b c d e; do
  printf '絵\n' >"$repo/gallery/$f.png"
  printf 'total=9999\tstatic=0\n' >"$repo/gallery/$f.items.tsv"
done
status_case budget-ng "$repo"

# --- 7. 40 行を超えて切られる ------------------------------------------------
repo=$status_root/too-long
mkdir -p "$repo/.test-logs" "$repo/debug/annotations"
status_git_init "$repo"
i=1
while [ "$i" -le 30 ]; do
  : >"$repo/.test-logs/落ちる$i.log"
  : >"$repo/.test-logs/落ちる$i.fail"
  status_setmtime "$repo/.test-logs/落ちる$i.log" $((now0 - 19800))
  i=$((i + 1))
done
printf '# 長い引き継ぎ\n- 1\n- 2\n- 3\n- 4\n- 5\n- 6\n' >"$repo/NOTES.md"
status_setmtime "$repo/NOTES.md" $((now0 - 19800))
status_case too-long "$repo"
