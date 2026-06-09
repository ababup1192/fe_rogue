#!/usr/bin/env bash
# ============================================================================
#  Mac だけで Windows 用 .exe パッケージ（JRE 同梱・ダブルクリック起動）を作る。
#
#  jpackage はクロスビルド不可なので使わず、以下を Mac 上で組み立てる:
#    1. self-contained jar（LWJGL ネイティブ込み, scripts/_make-selfcontained-jar.sh）
#    2. Windows 版 JDK を取得（初回のみ DL）
#    3. Windows ランタイムを wine 経由の jlink.exe で生成（縮小）
#    4. jpackage の launcher exe (jpackageapplauncherw.exe) を jmod から取り出す
#    5. jpackage と同じ app-image レイアウトを手で組む（exe + app/ + runtime/ + .cfg）
#
#  → 出力: examples/fe_rogue/dist-win/fe_rogue/  （fe_rogue.exe を実行）
#          examples/fe_rogue/dist-win/fe_rogue-win.zip （Ally へ転送用）
#
#  前提: wine64（`brew install --cask wine-stable` 等）, JDK 21+（flix ビルド用）, ネット接続。
#  注意: 生成物の最終確認は Windows 実機で。Mac では wine で起動確認のみ可能（--test）。
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"           # examples/fe_rogue
WT="$HERE/build/wintools"
JDK_VER="21"
JDK_DIR_GLOB="$WT/jdk-${JDK_VER}"*
OUT="$HERE/dist-win/fe_rogue"
export WINEDEBUG="${WINEDEBUG:--all}"

command -v wine64 >/dev/null || { echo "[ERROR] wine64 が必要です (brew install --cask wine-stable)"; exit 1; }

echo "==> [1/5] self-contained jar"
bash "$HERE/scripts/_make-selfcontained-jar.sh" "$HERE/artifact/fe_rogue-all.jar"

echo "==> [2/5] Windows JDK ${JDK_VER}"
mkdir -p "$WT"
JDK="$(ls -d $JDK_DIR_GLOB 2>/dev/null | head -1 || true)"
if [ -z "$JDK" ]; then
    curl -L -o "$WT/winjdk.zip" \
      "https://api.adoptium.net/v3/binary/latest/${JDK_VER}/ga/windows/x64/jdk/hotspot/normal/eclipse"
    ( cd "$WT" && unzip -q -o winjdk.zip )
    JDK="$(ls -d $JDK_DIR_GLOB | head -1)"
fi
echo "    JDK = $JDK"

echo "==> [3/5] Windows runtime (jlink via wine)"
if [ ! -f "$WT/winruntime/bin/java.exe" ]; then
    rm -rf "$WT/winruntime"
    wine64 "$JDK/bin/jlink.exe" --module-path "$JDK/jmods" \
        --add-modules ALL-MODULE-PATH --output "$WT/winruntime" \
        --no-header-files --no-man-pages --strip-debug
fi

echo "==> [4/5] extract launcher exe"
rm -rf "$WT/launcher"; mkdir -p "$WT/launcher"
# jmod は先頭に 4 バイトのマジックがあり unzip が警告終了(=1)するが中身は取り出せる。
# set -e で中断しないよう `|| true` で握りつぶし、後で実体の有無を確認する。
( cd "$JDK" && unzip -o -j jmods/jdk.jpackage.jmod \
    "classes/jdk/jpackage/internal/resources/jpackageapplauncherw.exe" \
    -d "$WT/launcher" >/dev/null 2>&1 || true )
[ -f "$WT/launcher/jpackageapplauncherw.exe" ] || { echo "[ERROR] launcher exe の取り出しに失敗"; exit 1; }

echo "==> [5/5] assemble app-image"
rm -rf "$OUT"; mkdir -p "$OUT/app/src/scenes"
cp "$HERE/artifact/fe_rogue-all.jar" "$OUT/app/"
cp "$HERE/project.json" "$OUT/app/"
cp -R "$HERE/assets" "$OUT/app/"
cp -R "$HERE/resources" "$OUT/app/"
cp "$HERE"/src/scenes/*.scene.json "$OUT/app/src/scenes/"
cp -R "$WT/winruntime" "$OUT/runtime"
cp "$WT/launcher/jpackageapplauncherw.exe" "$OUT/fe_rogue.exe"
# jpackage 互換 cfg（$APPDIR = app ディレクトリ、ランタイムは sibling runtime/ を自動使用）。
printf '[Application]\napp.classpath=$APPDIR\\fe_rogue-all.jar\napp.mainclass=Main\n\n[JavaOptions]\njava-options=-DprojectPath=$APPDIR\n' \
    > "$OUT/app/fe_rogue.cfg"

( cd "$HERE/dist-win" && rm -f fe_rogue-win.zip && zip -qr fe_rogue-win.zip fe_rogue )
echo "==> done: dist-win/fe_rogue/fe_rogue.exe  (zip: dist-win/fe_rogue-win.zip)"

if [ "${1:-}" = "--test" ]; then
    echo "==> wine smoke test"
    ( cd "$OUT" && wine64 fe_rogue.exe ) || true
fi
