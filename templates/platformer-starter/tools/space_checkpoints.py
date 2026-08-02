#!/usr/bin/env python3
"""中間ポイントを等間隔に置き直す(assets/stages.stage.json を書き換える)。

「死んだら最初から」の正体はコードでなく配置 — 232 列の面に最初の 'c' が
97 列目では、序盤で落ちた人は必ず出発点へ戻る。横に進む面は列で、
登る面は高さで等間隔に置く。

置ける場所の条件: 空きマスで真下が硬く、左右 1 マスも同じ高さの平地
(斜面や穴の縁に旗を立てない)。
"""
import json

PATH = "assets/stages.stage.json"
SOLID = set("#X")
FREE = set(".W")   # 洞窟は "W"(奥の壁)が空きマス — 固いのは "X" だけ
COL_STEP = 34      # 横に進む面: 何列ごとに置くか
ROW_STEP = 11      # 登る面: 何段ごとに置くか


def ground_of(rows, x):
    """列 x の「立てる一番上のマス」(空き / その下が硬い)。無ければ None。"""
    for y in range(len(rows) - 1):
        if rows[y][x] in FREE and rows[y + 1][x] in SOLID:
            return y
    return None


def flat(rows, x, y):
    W = len(rows[0])
    return all(0 <= x + d < W and ground_of(rows, x + d) == y for d in (-1, 0, 1))


def strip_c(rows):
    return [r.replace("c", ".") for r in rows]


def put(rows, x, y):
    rows[y] = rows[y][:x] + "c" + rows[y][x + 1:]


def place_horizontal(rows, W):
    spots = []
    for target in range(COL_STEP, W - 8, COL_STEP):
        for dx in range(0, 7):
            for x in (target - dx, target + dx):
                y = ground_of(rows, x)
                if y is not None and flat(rows, x, y) and rows[y][x] in FREE:
                    spots.append((x, y))
                    break
            else:
                continue
            break
    return spots


def place_vertical(rows, W):
    """登る面: 高さの帯ごとに、その帯で一番左の平地へ 1 つ。"""
    stands = [(x, ground_of(rows, x)) for x in range(W)]
    stands = [(x, y) for x, y in stands if y is not None and flat(rows, x, y)
              and rows[y][x] in FREE]
    if not stands:
        return []
    lo = min(y for _, y in stands)
    spots, band = [], None
    for x, y in sorted(stands, key=lambda p: -p[1]):
        b = (y - lo) // ROW_STEP
        if b != band:
            band, _ = b, spots.append((x, y))
    return spots


def main():
    doc = json.load(open(PATH))
    for st in doc["stages"]:
        rows = strip_c(st["rows"])
        W, H = len(rows[0]), len(rows)
        vertical = H > W // 2
        spots = place_vertical(rows, W) if vertical else place_horizontal(rows, W)
        for x, y in spots:
            put(rows, x, y)
        st["rows"] = rows
        print(f"{st['name']}: {len(spots)} 個 {sorted(spots)}")
    with open(PATH, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
