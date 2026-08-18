#!/bin/sh
# 偽の engine リポを $1 に組み、$1 で git init して「リリース済みの版」を 1 つ commit + tag する。
#
#   build.sh <置き場> <タグ>
#
# タグを打った後の作業ツリーには、まだリリースしていない pub 宣言を 1 つ足しておく
# （Depth.bands が digest には出るが fpkg には無い、という実際に起きた形）。
# 本物のリポでは絶対に commit しない。ここで作るのは毎回使い捨ての別リポ。
set -eu
R=$1
TAG=${2:-}
mkdir -p "$R/bin" "$R/engine/src" "$R/engine_world/src" "$R/engine_tools/src"

cat > "$R/Makefile" <<'EOF'
VERSION := 0.1.0
EOF

cat > "$R/engine/src/Depth.flix" <<'EOF'
mod Depth {
    pub def world(): Int32 = 0
    pub def ui(): Int32 = 1
}
EOF

cat > "$R/engine_world/src/Board.flix" <<'EOF'
mod Board {
    pub def make(): Unit = ()
}
EOF

cat > "$R/engine_tools/src/Bakery.flix" <<'EOF'
mod Bakery {
    pub def bake(): Unit = ()
}
EOF

git -C "$R" init -q
git -C "$R" add -A
git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    commit -q -m "release" >/dev/null
if [ -n "$TAG" ]; then git -C "$R" tag "$TAG"; fi
