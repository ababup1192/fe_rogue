#!/usr/bin/env python3
"""壁の autoRule をアンカー候補 material（base_room + room_*）へ一括反映する。

ダンジョンの wallMap / autoRules は「アンカー部屋（modulePaths 先頭 = 常に部屋）」の material が
フロア全体に適用されるため、ルール追加は base_room + room_1〜18 の 18 ファイル全部に入れる。
pathway_* はアンカーになれないので対象外。

使い方（examples/fe_rogue で実行）:
  python3 debug/apply_wall_rules.py add 候補.json     # 末尾に追加（同名があれば skip = 冪等）
  python3 debug/apply_wall_rules.py remove ルール名    # 名前で全ファイルから除去
  python3 debug/apply_wall_rules.py list              # ルール構成をファイルのグループごとに表示

候補.json は material の autoRules と同形式のリスト:
  [{"name": "...", "pattern": [25個の int], "size": 5, "srcX": 104, "srcY": 26, "v": 2}, ...]
pattern は 5x5 行優先で、0=不問 / 1=床 / 2=壁 / -1000001=空(void)要求 / 1000001=非空要求。
末尾追加 = 既存ルールが先勝ちなので、既にどれかのルールが発火するセルは変化しない。

書き込みは json.dumps(indent=2, sort_keys=True) + 改行（既存ファイルと byte 一致する整形）。
反映はフロア生成時の焼き込みなので、実行中のゲームには再起動 / 次フロアから。
"""
import json
import glob
import os
import sys


def material_dir():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "..", "assets", "materials")


def targets():
    d = material_dir()
    return sorted(glob.glob(os.path.join(d, "base_room.material.json"))
                  + glob.glob(os.path.join(d, "room_*.material.json")))


def save(path, data):
    open(path, "w").write(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


def add(rules_path):
    new_rules = json.load(open(rules_path))
    for rule in new_rules:
        assert len(rule["pattern"]) == 25 and rule["size"] == 5, f"pattern 形式不正: {rule['name']}"
    for path in targets():
        data = json.load(open(path))
        names = {r["name"] for r in data["autoRules"]}
        added = [r for r in new_rules if r["name"] not in names]
        data["autoRules"].extend(added)
        save(path, data)
        print(f"{os.path.basename(path)} -> {len(data['autoRules'])} rules (+{len(added)})")


def remove(name):
    for path in targets():
        data = json.load(open(path))
        before = len(data["autoRules"])
        data["autoRules"] = [r for r in data["autoRules"] if r["name"] != name]
        save(path, data)
        print(f"{os.path.basename(path)} -> {len(data['autoRules'])} rules (-{before - len(data['autoRules'])})")


def show():
    groups = {}
    for path in targets():
        data = json.load(open(path))
        sig = tuple(r["name"] for r in data["autoRules"])
        groups.setdefault(sig, []).append(os.path.basename(path))
    for sig, files in groups.items():
        print(f"{len(files)} files ({files[0]} ...): {len(sig)} rules")
        for name in sig:
            print(f"   {name}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    mode = sys.argv[1]
    if mode == "add":
        add(sys.argv[2])
    elif mode == "remove":
        remove(sys.argv[2])
    elif mode == "list":
        show()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
