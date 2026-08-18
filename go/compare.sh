#!/bin/sh
# Python 版 (bin/*.py) と Go 版 (bin/fge-go) の出力を突き合わせる。
#
#   sh go/compare.sh          # 全部 (PNG 全数。数分〜数十分かかる)
#   sh go/compare.sh quick    # ゲート 6 本だけ
#
# 数え方: 1 件 = 1 回の突き合わせ。出力が 1 バイトでも違えば不一致として名前を出す。
# sil だけは PNG のバイト比較をしない (Python の zlib と Go の compress/flate は
# 同じ画素から違うバイト列を作る)。かわりに描かれた画素が同じかを見る。
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
GO=$ROOT/bin/fge-go
JOBS=${JOBS:-8}

[ -x "$GO" ] || { echo "bin/fge-go がありません (make go-build)"; exit 1; }

WORK=$(mktemp -d)
RESULTS=$WORK/results
mkdir -p "$RESULTS"
trap 'rm -rf "$WORK"' EXIT

# ok / ng の 1 件を記録する。並列で走るので 1 件 1 ファイルにする。
note() { # note <ok|ng> <名前>
  printf '%s\t%s\n' "$1" "$2" >"$(mktemp "$RESULTS/n.XXXXXXXX")"
}

compare_out() { # compare_out <名前> <py 出力> <go 出力>
  if cmp -s "$2" "$3"; then note ok "$1"; else note ng "$1"; fi
}

echo "== ゲート (出力全文と終了コードをバイト比較)"
run_gate() { # run_gate <名前> <py 引数...> -- <go 引数...>
  name=$1
  shift
  py=""
  while [ "$1" != "--" ]; do py="$py $1"; shift; done
  shift
  # shellcheck disable=SC2086
  python3 $py >"$WORK/py.$name" 2>&1
  pyexit=$?
  "$GO" "$@" >"$WORK/go.$name" 2>&1
  goexit=$?
  compare_out "$name (出力)" "$WORK/py.$name" "$WORK/go.$name"
  if [ "$pyexit" = "$goexit" ]; then
    note ok "$name (終了コード)"
  else
    note ng "$name (終了コード $pyexit vs $goexit)"
  fi
}

run_gate_split() { # run_gate_split <名前> <py 引数...> -- <go 引数...>
  # stdout と stderr を混ぜずに 1 本ずつ比べる。
  # WhyNot: 2>&1 のまとめ比較だけにしないのは、どちらの口に出したかが入れ替わっても
  # まとめた字面は同じになりうるため。
  name=$1
  shift
  py=""
  while [ "$1" != "--" ]; do py="$py $1"; shift; done
  shift
  # shellcheck disable=SC2086
  python3 $py >"$WORK/py.$name.out" 2>"$WORK/py.$name.err"
  pyexit=$?
  "$GO" "$@" >"$WORK/go.$name.out" 2>"$WORK/go.$name.err"
  goexit=$?
  compare_out "$name (stdout)" "$WORK/py.$name.out" "$WORK/go.$name.out"
  compare_out "$name (stderr)" "$WORK/py.$name.err" "$WORK/go.$name.err"
  if [ "$pyexit" = "$goexit" ]; then
    note ok "$name (終了コード)"
  else
    note ng "$name (終了コード $pyexit vs $goexit)"
  fi
}

# 負の見本 (testdata/lint/<検査名>/<ケース名>/) を Python・Go・expected.txt の 3 者で見る。
# WhyNot: 本物のリポで一度も鳴らない判定があるため、ゲートだけでは本体が走らない。
run_fixtures() { # run_fixtures <検査名> <委譲先の .py の名前>
  check=$1
  script=$2
  [ -d "testdata/lint/$check" ] || return 0
  echo "== 負の見本 $check (Python・Go・expected.txt の 3 者)"
  for case_dir in "testdata/lint/$check"/*/; do
    [ -f "$case_dir/cmd.txt" ] || continue
    name="lint 見本 ${case_dir#testdata/lint/}"
    { sh "$case_dir/cmd.txt" 2>&1; echo "exit=$?"; } >"$WORK/py.case"
    sed "s|python3 bin/$(echo "$script" | sed 's/\./\\./g')|\"$GO\" $check|" \
      "$case_dir/cmd.txt" >"$WORK/go.cmd"
    sed 's|^\[exit=\([0-9]*\)\]$|exit=\1|' "$case_dir/expected.txt" >"$WORK/exp.case"
    compare_out "$name (Python と expected.txt)" "$WORK/py.case" "$WORK/exp.case"
    # 委譲先の .py を呼んでいないケース (harness.py 経由など) は Go へ振り替えられない。
    # WhyNot: 黙って通さないのは、書き換わらなかった台本が Python 同士の比較になり、
    # Go を 1 度も走らせないまま「一致」と数えられるため (緑が嘘になる)。
    if cmp -s "$WORK/go.cmd" "$case_dir/cmd.txt"; then
      note ng "$name (Go に振り替えられない: $script を直に呼んでいない)"
      continue
    fi
    { sh -c "$(cat "$WORK/go.cmd")" 2>&1; echo "exit=$?"; } >"$WORK/go.case"
    compare_out "$name (Python と Go)" "$WORK/py.case" "$WORK/go.case"
  done
}

run_gate images bin/lint-images.py -- images
run_gate audio bin/lint-audio.py -- audio
run_gate palette bin/lint-palette.py -- palette
run_gate loop bin/lint-loop.py -- loop
run_gate loop-strict bin/lint-loop.py --strict -- loop --strict
run_gate loop-selftest bin/lint-loop.py --self-test -- loop --self-test

# 検査ごとの突き合わせは go/compare.d/<検査名>.sh に 1 本ずつ置く。
# WhyNot: このファイルへ全員が書き足す形にしないのは、サブコマンドを別々の人が
# 同時に移すとき 1 つのファイルを奪い合うため (go/cmd_*.go と同じ理由)。
for frag in go/compare.d/*.sh; do
  [ -f "$frag" ] || continue
  . "$frag"
done

report() {
  total=$(cat "$RESULTS"/* 2>/dev/null | wc -l | tr -d ' ')
  same=$(cat "$RESULTS"/* 2>/dev/null | grep -c '^ok' | tr -d ' ')
  echo
  echo "$same/$total 件一致"
  bad=$(cat "$RESULTS"/* 2>/dev/null | grep '^ng' | cut -f2-)
  if [ -n "$bad" ]; then
    echo "不一致:"
    echo "$bad" | sed 's/^/  /'
    return 1
  fi
  return 0
}

if [ "${1:-}" = "quick" ]; then
  report
  exit $?
fi

find . -name '*.png' -not -path './build/*' -not -path './*/build/*' | sort >"$WORK/pngs"
echo "== digest --stats ($(wc -l <"$WORK/pngs" | tr -d ' ') 枚を 1 枚ずつ)"

cat >"$WORK/one-stats.sh" <<EOS
#!/bin/sh
png=\$1
tmp=\$(mktemp -d)
python3 "$ROOT/bin/img-digest.py" --stats "\$png" >"\$tmp/py" 2>&1
"$GO" digest --stats "\$png" >"\$tmp/go" 2>&1
if cmp -s "\$tmp/py" "\$tmp/go"; then r=ok; else r=ng; fi
printf '%s\tdigest --stats %s\n' "\$r" "\$png" >"\$(mktemp "$RESULTS/n.XXXXXXXX")"
rm -rf "\$tmp"
EOS
chmod +x "$WORK/one-stats.sh"
xargs -P "$JOBS" -n 1 "$WORK/one-stats.sh" <"$WORK/pngs"

echo "== digest (となりどうしの 2 枚くらべ)"
# となりどうしの組を 1 行 2 個ずつ並べる (xargs -n 2 が 1 組ずつ配れる形)。
awk 'NR>1{print prev; print $0} {prev=$0}' "$WORK/pngs" >"$WORK/pairs.flat"

cat >"$WORK/one-pair.sh" <<EOS
#!/bin/sh
a=\$1
b=\$2
tmp=\$(mktemp -d)
python3 "$ROOT/bin/img-digest.py" "\$a" "\$b" >"\$tmp/py" 2>&1
"$GO" digest "\$a" "\$b" >"\$tmp/go" 2>&1
if cmp -s "\$tmp/py" "\$tmp/go"; then r=ok; else r=ng; fi
printf '%s\tdigest %s %s\n' "\$r" "\$a" "\$b" >"\$(mktemp "$RESULTS/n.XXXXXXXX")"
rm -rf "\$tmp"
EOS
chmod +x "$WORK/one-pair.sh"
xargs -P "$JOBS" -n 2 "$WORK/one-pair.sh" <"$WORK/pairs.flat"

echo "== digest (フォルダくらべ)"
for pair in "bench/gl_parity/debug/soft bench/gl_parity/debug/gl" "gallery gallery"; do
  a=${pair% *}
  b=${pair#* }
  [ -d "$a" ] && [ -d "$b" ] || continue
  python3 bin/img-digest.py "$a" "$b" >"$WORK/py.dir" 2>&1
  "$GO" digest "$a" "$b" >"$WORK/go.dir" 2>&1
  compare_out "digest $a $b" "$WORK/py.dir" "$WORK/go.dir"
done

echo "== sil (書き出した PNG の画素をくらべる)"
# sil は書き出し先が gallery/ 固定なので、2 本同時に走らせると互いの絵を消し合う。
# WhyNot: 黙って続けないのは、消えた絵が「画素が違う」と数えられて、Go の間違いに
#見える偽の不一致が出るため (実測で 6 件出た)。取れなければ理由を出して飛ばす。
SIL_LOCK=$ROOT/gallery/.compare-sil.lock
if mkdir "$SIL_LOCK" 2>/dev/null; then
  # 途中で止まっても gallery/ を元に戻してから作業先を消す (順番が逆だと戻せない)。
  trap 'for m in sil gray bg; do
          [ -d "$WORK/py-$m" ] && [ ! -d "gallery/$m" ] && mv "$WORK/py-$m" "gallery/$m"
        done 2>/dev/null
        rm -rf "$WORK"; rmdir "$SIL_LOCK" 2>/dev/null' EXIT
else
  echo "   (別の compare.sh が gallery/ を使っています。sil は飛ばします)"
  report
  exit $?
fi
for mode in sil gray bg; do
  rm -rf "gallery/$mode"
  python3 bin/sil-png.py --mode "$mode" >"$WORK/py.sil.$mode" 2>&1
  mv "gallery/$mode" "$WORK/py-$mode"
  "$GO" sil --mode "$mode" >"$WORK/go.sil.$mode" 2>&1
  mv "gallery/$mode" "$WORK/go-$mode"
  compare_out "sil --mode $mode (書き出した名前の一覧)" "$WORK/py.sil.$mode" "$WORK/go.sil.$mode"
  for f in "$WORK/py-$mode"/*.png; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    if [ ! -e "$WORK/go-$mode/$base" ]; then
      note ng "sil $mode/$base (Go 側に無い)"
    elif "$GO" digest "$f" "$WORK/go-$mode/$base" 2>&1 |
      grep -qE '一致 \(バイト同一\)|重なる範囲の画素は同一'; then
      note ok "sil $mode/$base"
    else
      note ng "sil $mode/$base (画素が違う)"
    fi
  done
  mv "$WORK/py-$mode" "gallery/$mode"
done

report
