#!/usr/bin/env bash
# fe_rogue を Windows (ROG Xbox Ally 等) / macOS で単体起動できる配布フォルダにまとめる。
#
# 使い方:  examples/fe_rogue/ で  bash scripts/package-dist.sh
# 出力:    examples/fe_rogue/dist/fe_rogue/  （これを ZIP して配布先に置く）
#
# 配布物の起動には JRE 21 が必要。コントローラ操作はエンジン側 (LwjglLayer) が
# GLFW gamepad API で対応済みなので追加設定は不要（操作割当は DISTRIBUTION.md 参照）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # examples/fe_rogue
ROOT="$(cd "$HERE/../.." && pwd)"          # repo root
FLIX="$ROOT/bin/flix"   # ラッパーが devbox(nix)/手動 jar の解決と JVM フラグ付与を担う
OUT="$HERE/dist/fe_rogue"

echo "==> build-fatjar"
( cd "$HERE" && "$FLIX" build-fatjar )

echo "==> assembling $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/natives" "$OUT/src/scenes"

# fatjar（コンパイル済みクラス + 依存 JVM ライブラリ）。ネイティブ .dll/.dylib は
# fatjar には入らないため natives/ に別途同梱し classpath で渡す。
cp "$HERE/artifact/fe_rogue.jar" "$OUT/"

# 実行時に CWD から読まれるアセット類（Fs.FileRead）。相対パス構造を保持する。
cp "$HERE/project.json" "$OUT/"
cp -R "$HERE/assets" "$OUT/"
cp -R "$HERE/resources" "$OUT/"
cp "$HERE"/src/scenes/*.scene.json "$OUT/src/scenes/"

# LWJGL ネイティブ（macOS arm64 + Windows x86_64）を同梱。
# 1 フォルダに両方入れておけば実行時に OS/arch に合うものが選ばれる。
cp "$HERE"/lib/external/lwjgl-*-natives-*.jar "$OUT/natives/"

# Windows ランチャ（ROG Xbox Ally などはこれをダブルクリック/実行）。
cat > "$OUT/run.bat" <<'BAT'
@echo off
REM fe_rogue launcher (Windows / ROG Xbox Ally). JRE 21 が必要。
cd /d "%~dp0"
java -cp "fe_rogue.jar;natives\*" Main
if errorlevel 1 pause
BAT

# macOS 動作確認用ランチャ（配布前のローカルスモークテスト）。
# macOS は GLFW を main スレッドで動かす必要があるため -XstartOnFirstThread を付ける。
# 自動再起動 (ensureMainThread) は配布物では成立しないため -Dgame.relaunched=true で抑止する。
cat > "$OUT/run-macos.sh" <<'SH'
#!/usr/bin/env bash
cd "$(dirname "$0")"
exec java -XstartOnFirstThread -Dgame.relaunched=true -cp "fe_rogue.jar:natives/*" Main
SH
chmod +x "$OUT/run-macos.sh"

echo "==> done"
echo "    Windows: dist/fe_rogue/ を Ally にコピーして run.bat を実行"
echo "    macOS  : (cd dist/fe_rogue && ./run-macos.sh) でローカル確認"
