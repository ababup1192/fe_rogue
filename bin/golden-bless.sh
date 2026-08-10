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
# 一覧に載せるのは bake が焼いた絵（= gallery にある名前）だけ。golden/ へ手で置いた
# PNG（Studio のジャンル札が読む title.png 等）まで載せると、bench が gallery と
# 名前の集合を突き合わせるため「消えた」扱いで必ず落ちる。
(cd gallery && ls *.png) | sort | (cd golden && xargs shasum -a 256 > SHA256SUMS.txt)

echo "blessed: golden/*.png と golden/SHA256SUMS.txt を更新しました ($count 枚)"
