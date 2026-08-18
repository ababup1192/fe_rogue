#!/bin/sh
# 偽のゲームリポを $1 に組み、git init して 1 回だけ commit する（HEAD を作る）。
#
#   build.sh <置き場>
#
# precommit は `git -C <根> diff --cached -z` でステージを読む。--files は git を
# 一切見ない別の道なので、ステージそのものを裁く道を試すには偽の git リポが要る。
# 本物のリポでは絶対に commit しない。ここで作るのは毎回使い捨ての別リポ。
#
# bin/ には precommit が呼びうる検査の名前を全部置いておく。1 本でも欠けると
# fail-open の 1 行が混ざって、狙ったゲート以外の音が鳴るため（名前があるかだけを見る）。
set -eu
R=$1
mkdir -p "$R/bin/githooks" "$R/bin/lint-rules" "$R/src" "$R/docs/gallery" "$R/assets" "$R/engine/src"

# WhyNot: 本物が居れば写し、居なければ空ファイルで置くのは、この見本が見ているのが
# 「その名前のファイルが在るか」だけで、中身を走らせないため。bin/*.py が消えても
# 見本は同じ形で回る。
for f in fge precommit.py lint-images.py lint-view.py lint-palette.py \
         lint-ui-overflow.py lint-fallback.py lint-f32.py lint-jargon.py \
         gen-api-digest.py; do
  if [ -f "$ENGINE/bin/$f" ]; then cp "$ENGINE/bin/$f" "$R/bin/$f"; else : > "$R/bin/$f"; fi
done

# 規約データ。commit の前に置くのは、後から置くと「新しくステージした物」に混ざるため。
cp -R "$ENGINE/bin/lint-rules/." "$R/bin/lint-rules/"

# 空の Makefile。check-docs-sync ターゲットが無いので配線検査は飛ぶ（fail-open）。
printf 'all:\n\t@true\n' > "$R/Makefile"

cat > "$R/src/Main.flix" <<'EOF'
mod Main {
    pub def main(): Unit = ()
}
EOF

# lint-f32 の EXEMPT が名指す宣言。無いと「古い除外」の音が混ざる。
cat > "$R/engine/src/RenderUtil.flix" <<'EOF'
mod RenderUtil {
    pub def f32(x: Float64): Float32 = Float64.floatValue(x)
}
EOF

git -C "$R" init -q
git -C "$R" add -A
git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    commit -q -m base >/dev/null
