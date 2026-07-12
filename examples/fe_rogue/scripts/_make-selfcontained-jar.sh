#!/usr/bin/env bash
# build-fatjar の成果物に LWJGL ネイティブ (.dll/.dylib) をマージして
# 単体で動く self-contained jar を作る。
#
# build-fatjar はクラス + JVM 依存は入れるが [jar-dependencies] のネイティブを含めない。
# LWJGL は classpath 上の "<os>/<arch>/...so|dll|dylib" リソースから native をロードするので、
# ネイティブ jar の中身を fatjar に展開して 1 つの jar にまとめれば、
# `java -jar` だけで（natives フォルダや -cp 指定なしで）両 OS で動く。
#
# 出力: $1（指定が無ければ artifact/fe_rogue-all.jar）
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # examples/fe_rogue
ROOT="$(cd "$HERE/../.." && pwd)"
FLIX="$ROOT/bin/flix"   # ラッパーが devbox(nix)/手動 jar の解決と JVM フラグ付与を担う
OUT="${1:-$HERE/artifact/fe_rogue-all.jar}"
WORK="$HERE/build/selfcontained"

echo "==> build-fatjar"
( cd "$HERE" && "$FLIX" build-fatjar )

echo "==> merging natives into one jar"
rm -rf "$WORK"; mkdir -p "$WORK"
( cd "$WORK" && jar xf "$HERE/artifact/fe_rogue.jar" )
for j in "$HERE"/lib/external/lwjgl-*-natives-*.jar; do
    ( cd "$WORK" && jar xf "$j" )
done
# テストクラスを除外（`flix test` の生成物が build/class 経由で fatjar に混入し
# 数万クラス分肥大化する）。Flix はテストモジュールを `TestXxx/` という
# トップレベルのディレクトリに固める（中身は Clo$... という名前）。Main からは
# 参照されないので、トップレベルの Test* ディレクトリごと削除する。
# 注: Fs/Eff$FileTest.class のような実依存クラスは Test 始まりでないので残る。
find "$WORK" -maxdepth 1 -type d -name 'Test*' -exec rm -rf {} +
# Main-Class を保ったまま再パッケージ。
( cd "$WORK" && jar --create --file "$OUT" --main-class Main . )
rm -rf "$WORK"
echo "==> wrote $OUT"
