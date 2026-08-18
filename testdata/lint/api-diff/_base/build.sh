#!/bin/sh
# 偽の engine リポを $1 に組み、$2 のタグで「1 つ前のリリース」を 1 つ commit + tag する。
#
#   build.sh <置き場> <タグ>
#
# タグを打った後の作業ツリーは呼ぶ側が書き替える（それが「今のバージョン」になる）。
#
# WhyNot: 本物のリポから走らせないのは、api-diff が git archive をリポの根へ叩くため。
# 使い捨ての別リポを組まないと本物の履歴を読んでしまう。ここで commit するのもその中だけ。
set -eu
R=$1
TAG=${2:-}
mkdir -p "$R/engine/src" "$R/engine_world/src" "$R/engine_tools/src" "$R/docs" "$R/bin/lint-rules"

cat > "$R/Makefile" <<'EOF'
VERSION := 0.2.0
EOF

cat > "$R/engine_world/src/PxSpriteDoc.flix" <<'EOF'
mod PxSpriteDoc {
    /// スプライト 1 体。
    pub type alias Sprite = {
        anchor = Vec2.Vec2,
        loop = Loop,
        frames = Map[String, List[String]]
    }
}
EOF

cat > "$R/engine/src/Depth.flix" <<'EOF'
mod Depth {
    pub def world(): Int32 = 0
}
EOF

cat > "$R/engine_tools/src/Bakery.flix" <<'EOF'
mod Bakery {
    pub def bake(): Unit = ()
}
EOF

printf '{}\n' > "$R/docs/fx.schema.json"
printf '{"docKinds":["fx","sprite","shader"]}\n' > "$R/bin/lint-rules/api-diff.json"

git -C "$R" init -q
git -C "$R" add -A
git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    commit -q -m "release" >/dev/null
if [ -n "$TAG" ]; then git -C "$R" tag "$TAG"; fi
