#!/usr/bin/env python3
"""F8 注釈チケットの world.json からマップチップ選択をオフライン再現・検証する道具。

ゲームと同じ手順（床マスク → 自動壁(ring) → TRBL trit キー → wallMap → autoRules 第一マッチ）で
フロア全セルのチップを再計算する。ルール案の「実フロア全セル差分」を JSON に書く前に取るのが主用途。

使い方（examples/fe_rogue で実行）:
  python3 debug/replay_tiles.py <world.json>
      校正モード: cellsInRect の実描画と再計算を突き合わせる。まずこれで一致を確認する。
      （manual タイル由来のチップは再計算に写らないので「dump にだけ余分」として現れる = 正常）

  python3 debug/replay_tiles.py <world.json> --cell 22,18
      セル調査: 5x5 IntGrid・trit キー・wallMap の引き先・発火ルール名を表示する。

  python3 debug/replay_tiles.py <world.json> --rules 候補.json --diff
      ルール案（material の autoRules と同形式のリスト）を末尾に足した場合の全セル差分。
      --prepend を付けると先頭挿入（既存ルールより先に評価。既存が先勝ちするセルを奪う案のとき）。

  python3 debug/replay_tiles.py <world.json> --rules 候補.json --render out.png
      差分セル周辺の before/after を実タイルセットで並べて描画（差分セルに枠）。

  python3 debug/replay_tiles.py <world.json> --without-rules 名前1,名前2 --diff --render out.png
      適用済みルールを外した状態を before にする（修正後の before/after 画像を作り直す用）。

前提: world.json に materialId と床/void 区別（MapFloorInfo）が入っていること。
"""
import json
import os
import subprocess
import sys
import tempfile

FLOOR_GLYPHS = set(".PE+Ci")   # 地図で床の上に重なる記号（駒・カーソル・宝箱・床アイテム）
TILE = 26
FLOOR_CHIP = (5, 6)            # プレビュー用の代表床チップ（実際の床装飾はマップごとに変わる）


def repo_paths(world_path):
    base = os.path.dirname(os.path.abspath(world_path))
    while not os.path.isdir(os.path.join(base, "assets")):
        parent = os.path.dirname(base)
        if parent == base:
            sys.exit("assets/ が見つからない。examples/fe_rogue 配下の world.json を渡してください。")
        base = parent
    return base


class Repro:
    """world.json 1 枚ぶんの盤面と material を持ち、チップ選択を再計算する。"""

    def __init__(self, world_path):
        self.world = json.load(open(world_path))
        if self.world.get("materialId") is None:
            sys.exit("materialId が無い world.json（旧形式）。新しい注釈でやり直してください。")
        base = repo_paths(world_path)
        self.tileset_path = os.path.join(base, "assets", "sprites", "tileset_dungeon_green.png")
        mat_path = os.path.join(base, "assets", "materials",
                                self.world["materialId"] + ".material.json")
        material = json.load(open(mat_path))
        self.wall_map = {k: tuple(v) for k, v in material["wallMap"].items()}
        self.rules = material["autoRules"]
        self.render_java = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "WallSceneRender.java")

        rows = self.world["map"]
        self.height, self.width = len(rows), len(rows[0])
        self.floor = {(x, y) for y, row in enumerate(rows)
                      for x, ch in enumerate(row) if ch in FLOOR_GLYPHS}
        self.walls = set()
        for x in range(self.width):
            for y in range(self.height):
                if (x, y) in self.floor:
                    continue
                if any((x + dx, y + dy) in self.floor
                       for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx, dy) != (0, 0)):
                    self.walls.add((x, y))

    def trit(self, x, y):
        if (x, y) in self.walls: return "W"
        if (x, y) in self.floor: return "F"
        return "E"

    def key(self, x, y):
        return (self.trit(x, y - 1) + self.trit(x + 1, y)
                + self.trit(x, y + 1) + self.trit(x - 1, y))

    def int_grid(self, x, y):
        if x < 0 or x >= self.width or y < 0 or y >= self.height: return 0
        if (x, y) in self.floor: return 1
        if (x, y) in self.walls: return 2
        return 0

    def rule_matches(self, pattern, cx, cy):
        for i, want in enumerate(pattern):
            val = self.int_grid(cx + i % 5 - 2, cy + i // 5 - 2)
            if want == 0: continue
            if want == 1000001:
                if val == 0: return False
            elif want == -1000001:
                if val != 0: return False
            elif want > 0:
                if val != want: return False
            else:
                if val == -want: return False
        return True

    def firing_rule(self, x, y, rules):
        for rule in rules:
            if rule["srcX"] < 0 or rule["srcY"] < 0:
                continue
            if self.rule_matches(rule["pattern"], x, y):
                return rule
        return None

    def chips_at(self, x, y, rules):
        """壁層のチップ列（wallMap → 第一マッチ autoRule）。床装飾と manual タイルは含まない。"""
        out = []
        if (x, y) in self.walls:
            src = self.wall_map.get(self.key(x, y))
            if src:
                out.append((src[0] // TILE, src[1] // TILE))
        rule = self.firing_rule(x, y, rules)
        if rule:
            out.append((rule["srcX"] // TILE, rule["srcY"] // TILE))
        return out

    # ── 各モード ──

    def calibrate(self):
        print(f"material={self.world['materialId']} floor={len(self.floor)}"
              f" walls={len(self.walls)} grid={self.width}x{self.height}")
        print("--- cellsInRect（dump の実描画 vs 再計算）---")
        for cell in self.world["cellsInRect"]:
            x, y = cell["pos"]["x"], cell["pos"]["y"]
            dumped = [(c["x"], c["y"]) for c in cell["chips"]]
            computed = self.chips_at(x, y, self.rules)
            mark = "OK" if all(c in dumped for c in computed) else "MISMATCH"
            wall_key = self.key(x, y) if (x, y) in self.walls else "-"
            print(f"  ({x:2},{y:2}) {cell['terrain']:5} key={wall_key:4}"
                  f" dump={dumped} computed={computed} {mark}")

    def inspect(self, x, y, after_rules):
        print(f"--- ({x},{y}) の 5x5 IntGrid（0=void 1=床 2=壁）---")
        for row in range(y - 2, y + 3):
            print("   ", " ".join(str(self.int_grid(col, row)) for col in range(x - 2, x + 3)))
        if (x, y) in self.walls:
            k = self.key(x, y)
            print(f"trit key = {k} -> wallMap {self.wall_map.get(k)}")
        else:
            print("trit key = -（壁セルでない）")
        for label, rules in [("現行", self.rules), ("変更後", after_rules)]:
            rule = self.firing_rule(x, y, rules)
            name = rule["name"] if rule else "なし"
            print(f"{label}ルール: {name} / chips = {self.chips_at(x, y, rules)}")

    def diff(self, after_rules):
        changed = []
        for x in range(self.width):
            for y in range(self.height):
                before = self.chips_at(x, y, self.rules)
                after = self.chips_at(x, y, after_rules)
                if before != after:
                    changed.append((x, y, before, after))
        print(f"--- 全セル差分: {len(changed)} セル ---")
        for x, y, before, after in changed:
            k = self.key(x, y) if (x, y) in self.walls else "-"
            print(f"  ({x},{y}) key={k} {before} -> {after}")
        return changed

    def render(self, after_rules, changed, out_png, pad):
        if not changed:
            print("差分セルが無いので描画しない（--region 相当が欲しければ --cell で調査を）")
            return
        xs = [c[0] for c in changed]; ys = [c[1] for c in changed]
        x0, x1 = max(0, min(xs) - pad), min(self.width, max(xs) + pad + 1)
        y0, y1 = max(0, min(ys) - pad), min(self.height, max(ys) + pad + 1)
        marks = [(x - x0, y - y0) for x, y, _, _ in changed]
        lines = []
        for title, rules in [("BEFORE (bug)", self.rules), ("AFTER (fix)", after_rules)]:
            lines.append(f"PANEL {x1 - x0} {y1 - y0} {title}")
            for x in range(x0, x1):
                for y in range(y0, y1):
                    if (x, y) in self.floor:
                        lines.append(f"TILE {x - x0} {y - y0} {FLOOR_CHIP[0]} {FLOOR_CHIP[1]}")
                    for cx, cy in self.chips_at(x, y, rules):
                        lines.append(f"TILE {x - x0} {y - y0} {cx} {cy}")
            for mx, my in marks:
                lines.append(f"MARK {mx} {my}")
            lines.append("END")
        tmp = tempfile.mkdtemp()
        scene = os.path.join(tmp, "scene.txt")
        open(scene, "w").write("\n".join(lines) + "\n")
        subprocess.run(["javac", "-encoding", "UTF-8", "-d", tmp, self.render_java], check=True)
        subprocess.run(["java", "-cp", tmp, "WallSceneRender",
                        scene, self.tileset_path, out_png], check=True)
        print(f"wrote {out_png}  (region x{x0}..{x1 - 1} y{y0}..{y1 - 1})")


def parse_args(argv):
    opts = {"world": None, "rules": None, "without": [], "diff": False,
            "render": None, "cell": None, "pad": 4, "prepend": False}
    it = iter(argv)
    for arg in it:
        if arg == "--rules": opts["rules"] = next(it)
        elif arg == "--without-rules": opts["without"] = next(it).split(",")
        elif arg == "--diff": opts["diff"] = True
        elif arg == "--render": opts["render"] = next(it)
        elif arg == "--cell": opts["cell"] = tuple(int(v) for v in next(it).split(","))
        elif arg == "--pad": opts["pad"] = int(next(it))
        elif arg == "--prepend": opts["prepend"] = True
        elif opts["world"] is None: opts["world"] = arg
        else: sys.exit(f"不明な引数: {arg}")
    if opts["world"] is None:
        sys.exit(__doc__)
    return opts


def main():
    opts = parse_args(sys.argv[1:])
    repro = Repro(opts["world"])

    # 変更後ルール列を組む: --without-rules で名前除去 → --rules で候補を追加
    # （既定は末尾 = 既存先勝ち。--prepend で先頭 = 候補が先勝ち）
    after_rules = [r for r in repro.rules if r["name"] not in opts["without"]]
    if opts["rules"]:
        candidates = json.load(open(opts["rules"]))
        after_rules = candidates + after_rules if opts["prepend"] else after_rules + candidates
    if opts["without"]:
        # before/after を入れ替える: 「外した状態」が before、現行 material が after
        repro.rules, after_rules = after_rules, repro.rules

    repro.calibrate()
    if opts["cell"]:
        repro.inspect(opts["cell"][0], opts["cell"][1], after_rules)
    if opts["diff"] or opts["render"]:
        changed = repro.diff(after_rules)
        if opts["render"]:
            repro.render(after_rules, changed, opts["render"], opts["pad"])


if __name__ == "__main__":
    main()
