#!/usr/bin/env python3
"""stages.stage.json の機械検査 — クリア可能性(罠ゼロ)と流れ(単調さ)。

使い方: python3 tools/check_stages.py  (または make stages)

検査 1: 構造 — 行長一致 / P・G 各 1 / 左右端が閉じている / ギミックの下に支えがある
検査 2: 罠ゼロ — 立てるマスを節点、移動を有向辺とするグラフで
        (a) P から到達できるか(順方向 BFS)
        (b) 到達できる全マスから G へ戻れるか(**逆向き** BFS)
        (b) が本命 — 「落ちたら出られない穴」は (a) では見つからない。
        画面外へ落ちられる列(最下段が開いている)はチェックポイント復帰なので罠でない。
検査 3: 流れ — 平地の最長 / 見せ場(コイン・敵・ギミック)が無い 10 列窓

移動モデルは src/MotionDoc.flix の既定値に安全マージンを掛けた値。
歩ける・登れる・跳べるを控えめに見積もるので、ここで通れば人間には必ず通れる。
"""
import json
import sys
from collections import deque

SOLID = set("#X")
STAND_ON = set("#X=~!")     # この上には立てる
GIMMICK = set("oS~!cabz=T")

# 移動できる範囲は player.motion.json から導く。ここを手で写すと、手触りを
# 調整したときに検査だけ古い数値で通り続け、「機械検査は OK なのに登れない面」
# が出る(Flix のテストが期待値を Doc から導いているのと同じ理由)。
# 掛けている係数は「見積もりの安全マージン」だけで、これは調整対象ではない。
def _motion():
    try:
        with open("assets/player.motion.json") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


_M = _motion()
_JUMP_TILES = _M.get("jumpHeightTiles", 4.4)
CLIMB = int(_JUMP_TILES * 0.7)               # 登れる段差(控えめに見積もる)
JUMP_W = int(_JUMP_TILES + 1)                # 跳び越せる穴の幅
SPRING_UP = int(_M.get("springTiles", 9.0))  # バネで上がれる高さ
SPRING_W = 3                                 # バネで届く横のずれ


def load():
    with open("assets/stages.stage.json") as f:
        return json.load(f)["stages"]


def grid_of(rows):
    return {(x, y): ch for y, r in enumerate(rows) for x, ch in enumerate(r)}


def solid_at(g, x, y, W):
    if x < 0 or x >= W:
        return True          # 面の外は壁
    return g.get((x, y), ".") in SOLID


def standables(g, W, H):
    out = set()
    for (x, y), ch in g.items():
        if ch in SOLID:
            continue
        if g.get((x, y + 1), ".") in STAND_ON:
            out.add((x, y))
    return out


def edges(stand, g, W, H):
    """立てるマス間の有向辺。落下は自由・登りは CLIMB まで・穴は JUMP_W まで。"""
    by_col = {}
    for (x, y) in stand:
        by_col.setdefault(x, []).append(y)
    out = {c: set() for c in stand}

    def clear_between(x, ya, yb):
        return all(not solid_at(g, x, yy, W) for yy in range(min(ya, yb), max(ya, yb) + 1))

    for (x, y) in stand:
        spring = g.get((x, y)) == "S"
        for dx in range(-JUMP_W, JUMP_W + 1):
            tx = x + dx
            for ty in by_col.get(tx, []):
                if (tx, ty) == (x, y):
                    continue
                rise = y - ty          # 正 = 上る
                if abs(dx) <= 1:
                    ok = rise <= CLIMB and clear_between(tx, y, ty)
                elif abs(dx) <= JUMP_W:
                    ok = rise <= CLIMB
                else:
                    ok = False
                if not ok and spring and abs(dx) <= SPRING_W and rise <= SPRING_UP:
                    ok = True
                if ok:
                    out[(x, y)].add((tx, ty))
    return out


def bfs(starts, adj):
    seen = set(s for s in starts if s in adj)
    q = deque(seen)
    while q:
        for nxt in adj[q.popleft()]:
            if nxt not in seen:
                seen.add(nxt)
                q.append(nxt)
    return seen


def reverse(adj):
    rev = {k: set() for k in adj}
    for a, outs in adj.items():
        for b in outs:
            rev[b].add(a)
    return rev


def ground_top(g, x, H):
    for y in range(H):
        if g.get((x, y), ".") in SOLID:
            return y
    return None


def check(stage):
    name, rows = stage["name"], stage["rows"]
    H, W = len(rows), max(len(r) for r in rows)
    errs, warns = [], []
    if any(len(r) != W for r in rows):
        errs.append("行長が不揃い")
    g = grid_of(rows)

    ps = [c for c, ch in g.items() if ch == "P"]
    gs = [c for c, ch in g.items() if ch == "G"]
    if len(ps) != 1 or len(gs) != 1:
        errs.append(f"P={len(ps)} G={len(gs)}(各 1 が必要)")
        return name, errs, warns, ""
    if any(rows[y][0] not in SOLID or rows[y][W - 1] not in SOLID for y in range(H)):
        warns.append("左右端に開きがある")
    for (x, y), ch in g.items():
        if ch in "oScGabz" and g.get((x, y + 1), ".") not in STAND_ON and ch not in "ob":
            if y + 1 < H:
                warns.append(f"{ch} が宙に浮いている ({x},{y})")
                break

    stand = standables(g, W, H)
    adj = edges(stand, g, W, H)
    start = min((c for c in stand),
                key=lambda c: (abs(c[0] - ps[0][0]) + abs(c[1] - ps[0][1])))
    goal = min((c for c in stand),
               key=lambda c: (abs(c[0] - gs[0][0]) + abs(c[1] - gs[0][1])))

    forward = bfs([start], adj)
    if goal not in forward:
        errs.append("P から G へ到達できない")
    to_goal = bfs([goal], reverse(adj))

    # 画面外へ落ちられる位置はチェックポイント復帰なので罠ではない。
    open_cols = {x for x in range(W) if rows[H - 1][x] not in SOLID}

    def can_fall_out(c):
        x, y = c
        return any(abs(x - ox) <= JUMP_W and all(
            not solid_at(g, ox, yy, W) for yy in range(y + 1, H)) for ox in open_cols)

    trapped = sorted(c for c in forward if c not in to_goal and not can_fall_out(c))
    if trapped:
        errs.append(f"落ちると出られない場所 {len(trapped)} マス 例 {trapped[:5]}")

    tops = [ground_top(g, x, H) for x in range(W)]
    longest, cur = 1, 1
    for a, b in zip(tops, tops[1:]):
        cur = cur + 1 if a == b else 1
        longest = max(longest, cur)
    if longest > 10:
        warns.append(f"平地が単調(最長 {longest} 列)")
    dead = [x0 for x0 in range(0, W - 10, 10)
            if not any(g.get((x, y)) in GIMMICK
                       for x in range(x0, x0 + 10) for y in range(H))]
    if dead:
        warns.append(f"見せ場が無い 10 列窓: {dead}")

    coins = sum(1 for ch in g.values() if ch == "o")
    enemies = sum(1 for ch in g.values() if ch in "abz")
    info = (f"{W}x{H} コイン{coins} 敵{enemies} 立てる{len(stand)} "
            f"到達{len(forward)} 平地最長{longest}")
    return name, errs, warns, info


def main():
    ok = True
    for st in load():
        name, errs, warns, info = check(st)
        print(f"[{'NG' if errs else ('WARN' if warns else 'OK')}] {name} {info}")
        for e in errs:
            print(f"  NG: {e}")
        for w in warns:
            print(f"  warn: {w}")
        ok = ok and not errs
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
