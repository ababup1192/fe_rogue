#!/bin/sh
# make snapshot-check の中身。生成したばかりの gallery/*.png を snapshot/SHA256SUMS.txt と突き合わせる。
#
# shasum -c は「一覧に載っている名前」しか見ないので、増えた絵を黙って見逃す。
# 名前の集合そのものを先に比べて、増減も退行として落とす。
set -eu

cd "${1:-.}"

sums=snapshot/SHA256SUMS.txt

if [ ! -f "$sums" ]; then
	echo "スナップショットがまだありません: $sums がありません。" >&2
	echo "いまの絵を基準にしてよければ make snapshot-update を実行してください。" >&2
	exit 1
fi

if [ ! -d gallery ]; then
	echo "error: gallery/ がありません。先に make bake を実行してください" >&2
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 一覧の行は "<ハッシュ>  <ファイル名>" 形式。名前だけ取り出して並べ替える。
sed 's/^[0-9a-f]*  //' "$sums" | sort > "$tmp/expected"
(cd gallery && ls *.png 2>/dev/null || true) | sort > "$tmp/actual"

if ! diff -q "$tmp/expected" "$tmp/actual" > /dev/null; then
	echo "snapshot-check NG: 絵の顔ぶれが変わりました" >&2
	comm -13 "$tmp/expected" "$tmp/actual" | sed 's/^/  増えた: /' >&2
	comm -23 "$tmp/expected" "$tmp/actual" | sed 's/^/  消えた: /' >&2
	echo "  意図した変更なら make snapshot-update でスナップショットを更新してください。" >&2
	exit 1
fi

(cd gallery && shasum -a 256 -c ../"$sums")
echo "snapshot-check OK: $(wc -l < "$tmp/expected" | tr -d ' ') 枚すべてスナップショットと一致しました"
