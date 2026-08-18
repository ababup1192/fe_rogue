# carve / adopt / render / gifs / sheet の突き合わせ。go/compare.sh から読まれる。
#
# **使い捨ての作業先で走らせる。** carve は実行したディレクトリの assets/chars と
# gallery へ、adopt / render / gifs / sheet は bin/ の下へ書き出すので、リポの中で
# 走らせると gallery を上書きする。見本 (3 面図・工程のコマ) はその場で作る。
#
# PNG はバイト比較しない (Python の zlib と Go の compress/flate が同じ画素から
# 違うバイト列を作る)。画素が同じかを digest で見る。GIF と JSON はバイト比較する。

CARVE_WORK=$WORK/carve
mkdir -p "$CARVE_WORK"
if ! python3 go/compare.d/carve-fixture.py "$CARVE_WORK" >/dev/null 2>&1; then
  note ng "carve 見本づくり"
fi
CARVE_VIEWS=$CARVE_WORK/views

# carve_tree は書き出された物を 3 通りで比べる (一覧・画素・バイト)。
carve_tree() { # carve_tree <名前> <py の場> <go の場>
  name=$1
  py=$2
  go=$3
  (cd "$py" && find . -type f | sort) >"$WORK/carve.py.list" 2>/dev/null
  (cd "$go" && find . -type f | sort) >"$WORK/carve.go.list" 2>/dev/null
  compare_out "$name (書き出したファイルの一覧)" "$WORK/carve.py.list" "$WORK/carve.go.list"
  bad=0
  while IFS= read -r rel; do
    [ -f "$go/$rel" ] || { bad=1; continue; }
    case "$rel" in
    *.png)
      if ! "$GO" digest "$py/$rel" "$go/$rel" 2>&1 |
        grep -qE '一致 \(バイト同一\)|重なる範囲の画素は同一'; then
        note ng "$name $rel (画素が違う)"
        bad=1
      fi
      ;;
    *)
      cmp -s "$py/$rel" "$go/$rel" || { note ng "$name $rel (バイトが違う)"; bad=1; }
      ;;
    esac
  done <"$WORK/carve.py.list"
  [ "$bad" = 0 ] && note ok "$name (中身)"
}

# carve_run は carve を「実行したディレクトリ」を分けて 2 回走らせる。
carve_run() { # carve_run <名前> <引数...>
  name=$1
  shift
  py=$CARVE_WORK/py-$name
  go=$CARVE_WORK/go-$name
  rm -rf "$py" "$go"
  mkdir -p "$py" "$go"
  (cd "$py" && python3 "$ROOT/bin/carve/carve.py" "$@" >"$WORK/py.carve.$name.out" 2>"$WORK/py.carve.$name.err")
  pyexit=$?
  (cd "$go" && "$GO" carve "$@" >"$WORK/go.carve.$name.out" 2>"$WORK/go.carve.$name.err")
  goexit=$?
  compare_out "carve $name (stdout)" "$WORK/py.carve.$name.out" "$WORK/go.carve.$name.out"
  compare_out "carve $name (stderr)" "$WORK/py.carve.$name.err" "$WORK/go.carve.$name.err"
  if [ "$pyexit" = "$goexit" ]; then
    note ok "carve $name (終了コード)"
  else
    note ng "carve $name (終了コード $pyexit vs $goexit)"
  fi
  carve_tree "carve $name" "$py" "$go"
}

# carve_bin は bin/ を根にする 4 本 (adopt / render / gifs / sheet) の下ごしらえ。
# Python は自分の置き場から、Go は FGE_ROOT から根を数えるので、同じ形の木を 2 つ作る。
carve_bin_tree() { # carve_bin_tree <場>
  rm -rf "$1"
  mkdir -p "$1/bin/carve" "$1/bin/lint-rules" "$1/bin/assets/chars"
  cp "$ROOT"/bin/carve/*.py "$1/bin/carve/"
  cp "$ROOT/bin/lint-rules/carve.json" "$1/bin/lint-rules/"
}

carve_bin_run() { # carve_bin_run <名前> <py の入口> <go のサブコマンド> <引数...>
  name=$1
  script=$2
  sub=$3
  shift 3
  py=$CARVE_WORK/bpy-$name
  go=$CARVE_WORK/bgo-$name
  python3 "$py/bin/carve/$script" "$@" >"$WORK/py.$name.out" 2>"$WORK/py.$name.err"
  pyexit=$?
  FGE_ROOT=$go "$GO" "$sub" "$@" >"$WORK/go.$name.out" 2>"$WORK/go.$name.err"
  goexit=$?
  compare_out "$name (stdout)" "$WORK/py.$name.out" "$WORK/go.$name.out"
  compare_out "$name (stderr)" "$WORK/py.$name.err" "$WORK/go.$name.err"
  if [ "$pyexit" = "$goexit" ]; then
    note ok "$name (終了コード)"
  else
    note ng "$name (終了コード $pyexit vs $goexit)"
  fi
  carve_tree "$name" "$py/bin/gallery" "$go/bin/gallery"
  [ -d "$py/bin/assets" ] && carve_tree "$name (assets)" "$py/bin/assets" "$go/bin/assets"
}

echo "== carve (3 面図から立体を彫り出す。使い捨ての作業先で走らせる)"
carve_run plain "$CARVE_VIEWS/plain.png" --id t1
carve_run small "$CARVE_VIEWS/green.png" --id g1 --size 24x32 --colors 8
carve_run large "$CARVE_VIEWS/tall.png" --id h1 --size 48x64 --colors 24
carve_run reach "$CARVE_VIEWS/plain.png" --id t2 --reach 5 --size 40x40
carve_run profile "$CARVE_VIEWS/green.png" --id g2 --profile "$CARVE_WORK/prof.json"
carve_run tiny "$CARVE_VIEWS/tall.png" --id h2 --size 16x24 --colors 4 --reach 1

echo "== adopt / render / gifs / sheet"
for name in adopt-plain adopt-small adopt-large; do
  carve_bin_tree "$CARVE_WORK/bpy-$name"
  carve_bin_tree "$CARVE_WORK/bgo-$name"
done
carve_bin_run adopt-plain adopt.py adopt "$CARVE_VIEWS/plain.png" --id ap1
carve_bin_run adopt-small adopt.py adopt "$CARVE_VIEWS/green.png" --id ag1 --size 24x32 --colors 8 --swing 3
carve_bin_run adopt-large adopt.py adopt "$CARVE_VIEWS/tall.png" --id ah1 --size 48x64 --order front,right,back

for name in render-all render-odd; do
  carve_bin_tree "$CARVE_WORK/bpy-$name"
  carve_bin_tree "$CARVE_WORK/bgo-$name"
  cp "$CARVE_WORK/bpy-adopt-large/bin/assets/chars/ah1.sprite.json" "$CARVE_WORK/bpy-$name/bin/assets/chars/"
  cp "$CARVE_WORK/bpy-adopt-large/bin/assets/chars/ah1.sprite.json" "$CARVE_WORK/bgo-$name/bin/assets/chars/"
  cp "$CARVE_WORK/odd.sprite.json" "$CARVE_WORK/bpy-$name/bin/assets/chars/"
  cp "$CARVE_WORK/odd.sprite.json" "$CARVE_WORK/bgo-$name/bin/assets/chars/"
done
carve_bin_run render-all render.py carve-render
carve_bin_run render-odd render.py carve-render "$CARVE_WORK/odd.sprite.json"

for name in gifs-default gifs-1 gifs-stage sheet-shade sheet-none; do
  carve_bin_tree "$CARVE_WORK/bpy-$name"
  carve_bin_tree "$CARVE_WORK/bgo-$name"
  cp -R "$CARVE_WORK/stage/gallery" "$CARVE_WORK/bpy-$name/bin/"
  cp -R "$CARVE_WORK/stage/gallery" "$CARVE_WORK/bgo-$name/bin/"
done
carve_bin_run gifs-default gifs.py carve-gifs
carve_bin_run gifs-1 gifs.py carve-gifs 1
carve_bin_run gifs-stage gifs.py carve-gifs 3 2_陰影
carve_bin_run sheet-shade sheet.py carve-sheet 2_陰影
carve_bin_run sheet-none sheet.py carve-sheet 無い工程

run_gate carve-pngread bin/carve/png_read.py "$CARVE_VIEWS/plain.png" "$CARVE_VIEWS/green.png" \
  -- carve-pngread "$CARVE_VIEWS/plain.png" "$CARVE_VIEWS/green.png"
