#!/bin/sh
# make reference-update の中身。いまの gallery/*.png を reference/ に写し、SHA256SUMS.txt を作り直す。
#
# リファレンス画像の PNG 本体は git に入れず（.gitignore）、この一覧だけを追跡する。
# 一覧があれば「絵が変わっていないか」は clone 直後でも確かめられる。
# 手元のリファレンス画像 PNG は残るので、make diff の左右比較は今までどおり効く。
set -eu

cd "${1:-.}"

if [ ! -d gallery ]; then
	echo "error: gallery/ がありません。先に make render-all を実行してください" >&2
	exit 1
fi

count=$(find gallery -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
	echo "error: gallery/*.png が 1 枚もありません。先に make render-all を実行してください" >&2
	exit 1
fi

mkdir -p reference

# 絵を写す前に値段を裁く。WhyNot: cp のあとに置かない — 拒否したときに
# 「PNG と SHA だけ新しく、基準の数だけ古い」割れた状態が残る。
# 上限を超えた値は基準にできない（初回の実装が遅くても、基準化でスキップしない）。
# 意図した増加は make reference-update BUDGET=accept で明示する
# （GNU make はコマンドラインで渡した変数を recipe の環境へ渡すので、ここに届く）。
fge="$(dirname "$0")/fge"
if [ -x "$fge" ] && [ "${BUDGET:-}" != "accept" ]; then
	"$fge" check-render-budget . --gate reference/ITEMS.tsv
fi

cp gallery/*.png reference/
# 一覧に載せるのは render が描き出した絵（= gallery にある名前）だけ。reference/ へ手で置いた
# PNG（Studio のジャンルカードが読む title.png 等）まで載せると、reference-check が gallery と
# 名前の集合を突き合わせるため「消えた」扱いで必ず落ちる。
(cd gallery && ls *.png) | sort | (cd reference && xargs shasum -a 256 > SHA256SUMS.txt)

# 絵の値段の基準。行にするのは gallery にある PNG の名前だけ — 改名で残ったサイドカーや
# シルエット（*_sil）の残骸を基準に混ぜない。手書きの例外（ITEMS.caps.tsv）はここで作り直さない。
(cd gallery && ls *.png) | sed 's/\.png$//' | sort | while read -r name; do
	items="gallery/$name.items.tsv"
	[ -f "$items" ] || continue
	total=$(sed -n 's/.*total=\([0-9]*\).*/\1/p' "$items")
	static=0
	if [ -f "gallery/$name.static.tsv" ]; then
		static=$(sed -n 's/.*static=\([0-9]*\).*/\1/p' "gallery/$name.static.tsv")
	fi
	printf '%s\tdynamic=%s\tstatic=%s\n' "$name" "$((total - static))" "$static"
done > reference/ITEMS.tsv

echo "updated: reference/*.png と reference/SHA256SUMS.txt を更新しました ($count 枚)"
if [ -s reference/ITEMS.tsv ]; then
	echo "updated: reference/ITEMS.tsv（絵の値段の基準）も更新しました"
fi
