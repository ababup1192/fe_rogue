#!/usr/bin/env bash
# fe_rogue を macOS の .dmg（JRE 同梱・ダブルクリック起動）にパッケージする。
# macOS 上でのみ実行可能（jpackage はターゲット OS でしか動かない）。
#
# 使い方:  examples/fe_rogue/ で  bash scripts/package-macos-dmg.sh
# 出力:    examples/fe_rogue/dist/fe_rogue-<version>.dmg
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # examples/fe_rogue
STAGE="$HERE/build/jpackage-input"
DEST="$HERE/dist"

echo "==> self-contained jar"
bash "$HERE/scripts/_make-selfcontained-jar.sh" "$HERE/artifact/fe_rogue-all.jar"

echo "==> staging app input ($STAGE)"
# jpackage は --input ディレクトリの中身をまるごとアプリ内 ($APPDIR) にコピーする。
# jar + アセット類を一緒に置き、実行時に -DprojectPath=$APPDIR で絶対解決させる。
rm -rf "$STAGE"; mkdir -p "$STAGE/src/scenes"
cp "$HERE/artifact/fe_rogue-all.jar" "$STAGE/"
cp "$HERE/project.json" "$STAGE/"
cp -R "$HERE/assets" "$STAGE/"
cp -R "$HERE/resources" "$STAGE/"
cp "$HERE"/src/scenes/*.scene.json "$STAGE/src/scenes/"

echo "==> jpackage (.dmg)"
mkdir -p "$DEST"
rm -f "$DEST"/fe_rogue-*.dmg
# $APPDIR は jpackage が実行時に展開するマクロ（シェルに展開させないため単一引用符）。
# macOS は GLFW を main スレッドで動かすため -XstartOnFirstThread、
# ensureMainThread の bin/flix.jar 再起動は配布物に無いので -Dgame.relaunched=true で抑止。
jpackage \
  --type dmg \
  --name fe_rogue \
  --app-version 1.0.0 \
  --input "$STAGE" \
  --main-jar fe_rogue-all.jar \
  --main-class Main \
  --java-options '-DprojectPath=$APPDIR' \
  --java-options '-XstartOnFirstThread' \
  --java-options '-Dgame.relaunched=true' \
  --dest "$DEST"

echo "==> done: $(ls "$DEST"/fe_rogue-*.dmg)"
