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
FLIX="$ROOT/bin/flix.jar"
OUT="${1:-$HERE/artifact/fe_rogue-all.jar}"
WORK="$HERE/build/selfcontained"

echo "==> build-fatjar"
( cd "$HERE" && java -XstartOnFirstThread -jar "$FLIX" build-fatjar )

echo "==> merging natives into one jar"
rm -rf "$WORK"; mkdir -p "$WORK"
( cd "$WORK" && jar xf "$HERE/artifact/fe_rogue.jar" )
for j in "$HERE"/lib/external/lwjgl-*-natives-*.jar; do
    ( cd "$WORK" && jar xf "$j" )
done
# Main-Class を保ったまま再パッケージ。
( cd "$WORK" && jar --create --file "$OUT" --main-class Main . )
rm -rf "$WORK"
echo "==> wrote $OUT"
