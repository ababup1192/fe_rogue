#!/bin/sh
# make reference-check の中身。生成したばかりの gallery/*.png を reference/SHA256SUMS.txt と突き合わせる。
#
# shasum -c は「一覧に載っている名前」しか見ないので、増えた絵を黙って見逃す。
# 名前の集合そのものを先に比べて、増減も退行として落とす。
set -eu

cd "${1:-.}"

sums=reference/SHA256SUMS.txt

if [ ! -f "$sums" ]; then
	echo "リファレンス画像がまだありません: $sums がありません。" >&2
	echo "いまの絵を基準にしてよければ make reference-update を実行してください。" >&2
	exit 1
fi

if [ ! -d gallery ]; then
	echo "error: gallery/ がありません。先に make render-all を実行してください" >&2
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 一覧の行は "<ハッシュ>  <ファイル名>" 形式。名前だけ取り出して並べ替える。
sed 's/^[0-9a-f]*  //' "$sums" | sort > "$tmp/expected"
(cd gallery && ls *.png 2>/dev/null || true) | sort > "$tmp/actual"

if ! diff -q "$tmp/expected" "$tmp/actual" > /dev/null; then
	echo "reference-check NG: 絵の顔ぶれが変わりました" >&2
	comm -13 "$tmp/expected" "$tmp/actual" | sed 's/^/  増えた: /' >&2
	comm -23 "$tmp/expected" "$tmp/actual" | sed 's/^/  消えた: /' >&2
	echo "  意図した変更なら make reference-update でリファレンス画像を更新してください。" >&2
	exit 1
fi

(cd gallery && shasum -a 256 -c ../"$sums")
echo "reference-check OK: $(wc -l < "$tmp/expected" | tr -d ' ') 枚すべてリファレンス画像と一致しました"
