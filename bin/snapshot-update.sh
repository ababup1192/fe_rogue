#!/bin/sh
# make snapshot-update の中身。いまの gallery/*.png を snapshot/ に写し、SHA256SUMS.txt を作り直す。
#
# スナップショットの PNG 本体は git に入れず（.gitignore）、この一覧だけを追跡する。
# 一覧があれば「絵が変わっていないか」は clone 直後でも確かめられる。
# 手元のスナップショット PNG は残るので、make diff の左右比較は今までどおり効く。
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

mkdir -p snapshot
cp gallery/*.png snapshot/
# 一覧に載せるのは bake が生成した絵（= gallery にある名前）だけ。snapshot/ へ手で置いた
# PNG（Studio のジャンルカードが読む title.png 等）まで載せると、snapshot-check が gallery と
# 名前の集合を突き合わせるため「消えた」扱いで必ず落ちる。
(cd gallery && ls *.png) | sort | (cd snapshot && xargs shasum -a 256 > SHA256SUMS.txt)

echo "updated: snapshot/*.png と snapshot/SHA256SUMS.txt を更新しました ($count 枚)"
