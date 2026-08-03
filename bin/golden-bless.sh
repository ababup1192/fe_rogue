#!/bin/sh
# make golden の中身。いまの gallery/*.png を golden/ に写し、SHA256SUMS.txt を作り直す。
#
# golden の PNG 本体は git に入れず（.gitignore）、この一覧だけを追跡する。
# 一覧があれば「絵が変わっていないか」は clone 直後でも確かめられる。
# 手元の golden PNG は残るので、make diff の左右比較は今までどおり効く。
set -eu

cd "${1:-.}"

if [ ! -d gallery ]; then
	echo "error: gallery/ がありません。先に make bake を実行してください" >&2
	exit 1
fi

count=$(find gallery -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
	echo "error: gallery/*.png が 1 枚もありません。先に make bake を実行してください" >&2
	exit 1
fi

mkdir -p golden
cp gallery/*.png golden/
(cd golden && shasum -a 256 *.png > SHA256SUMS.txt)

echo "blessed: golden/*.png と golden/SHA256SUMS.txt を更新しました ($count 枚)"
