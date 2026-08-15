#!/usr/bin/env python3
"""絵の値段（1 場面が組んだ描き物の数）を裁く。

型検査もテストもリファレンス画像のバイト比較も、遅い絵を止められない
（box 列と 1 コマ 1 クアッドは画素が同一なので、ハッシュは 1 ビットも動かない）。
今まで速さを見ていたのは人の目だけだった — その穴を埋める検査。

読む物（HeadlessRender が PNG の隣へ常時書く）:
  gallery/<場面>.items.tsv   total=<n>\tpasses=<n>\tsurfaces=<n>
  gallery/<場面>.static.tsv  static=<n>        タイル層・静的層を CPU 投影したぶん
基準（git 追跡）:
  reference/ITEMS.tsv        <場面>\tdynamic=<n>\tstatic=<n>   生成物
  reference/ITEMS.caps.tsv   <場面>\tcap=<n>\tnote=<理由>      手書き（再生成しない）

判定（動的 = total − static）:
  ① 硬い上限   動的 >= cap（既定 2000）→ 赤。基準が無くても効く
  ② ドリフト   基準があり 動的 > max(基準 × 1.5, 基準 + 200) → 赤
  ③ sanity     static > total / items.tsv 無しの static.tsv → 赤

使い方:
  check-render-budget.py <ゲームのルート>              reference-check から。gallery を裁く
  check-render-budget.py <ルート> --gate <旧ITEMS.tsv>  reference-update から。基準の更新を裁く
  check-render-budget.py <ルート> --brief              status.py から。直し方の助言を出さない
"""

import os
import sys

# docs/performance.md:29 の R3「動的 PlacedItem < 2000 個/フレーム」から借りた既定値。
# 同 43-46 の「絶対視しない」に従い、場面ごとに ITEMS.caps.tsv で上書きできる。
DEFAULT_CAP = 2000

# 事故は 9〜46 倍の桁で来る（box 列時代の dq_map は現行の 45.7 倍）ので、
# 誤検知と見逃しの間はいくらでも広く取れる。絵を 1 つ足したくらいでは鳴らない幅にする。
DRIFT_FACTOR = 1.5
DRIFT_FLOOR = 200


def read_kv(path):
    """`k=v\tk=v` 1 行のサイドカーを dict で返す。読めなければ None。"""
    try:
        with open(path, encoding="utf-8") as f:
            line = f.readline().strip()
    except OSError:
        return None
    out = {}
    for part in line.split("\t"):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def read_table(path, want):
    """`名前\tk=v...` の表を {名前: {k: v}} で返す。無ければ空。"""
    rows = {}
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            cells = line.split("\t")
            fields = {}
            for cell in cells[1:]:
                if "=" in cell:
                    k, v = cell.split("=", 1)
                    fields[k.strip()] = v.strip()
            if all(k in fields for k in want):
                rows[cells[0]] = fields
    return rows


def as_int(fields, key, fallback=0):
    try:
        return int(fields.get(key, fallback))
    except (TypeError, ValueError):
        return fallback


def scene_names(gallery):
    """gallery/*.png の名前集合。サイドカーの残骸を基準に混ぜないための唯一の正。"""
    if not os.path.isdir(gallery):
        return []
    return sorted(f[:-4] for f in os.listdir(gallery) if f.endswith(".png"))


def measure(gallery, names):
    """場面ごとの (動的, 静的, 計測できたか, 異常の理由)。"""
    out = {}
    for name in names:
        items = read_kv(os.path.join(gallery, f"{name}.items.tsv"))
        static_kv = read_kv(os.path.join(gallery, f"{name}.static.tsv"))
        static = as_int(static_kv, "static") if static_kv else 0
        if items is None:
            # 古い engine で焼いた gallery。黙らせないが、落としもしない。
            out[name] = (None, static, False,
                         "静的層の申告だけがあり計測がありません（残骸か呼び順の誤り）"
                         if static_kv else None)
            continue
        total = as_int(items, "total")
        if static > total:
            out[name] = (None, static, True,
                         f"静的層の申告 {static} が総数 {total} を超えています")
            continue
        out[name] = (total - static, static, True, None)
    return out


def caps_of(root):
    rows = read_table(os.path.join(root, "reference", "ITEMS.caps.tsv"), ("cap",))
    caps, bad = {}, []
    for name, fields in rows.items():
        if not fields.get("note"):
            bad.append(name)
            continue
        caps[name] = as_int(fields, "cap", DEFAULT_CAP)
    return caps, bad


def baseline_of(path):
    rows = read_table(path, ("dynamic",))
    return {name: as_int(fields, "dynamic") for name, fields in rows.items()}


def drift_limit(base):
    return max(int(base * DRIFT_FACTOR), base + DRIFT_FLOOR)


def judge(root, gallery_dir, baseline_path, gate):
    """裁く。(赤の行, 注意の行, 計測できた場面数) を返す。"""
    gallery = os.path.join(root, gallery_dir)
    names = scene_names(gallery)
    stats = measure(gallery, names)
    caps, capless = caps_of(root)
    base = baseline_of(baseline_path)

    red, note = [], []
    for name in capless:
        red.append(f"{name}: ITEMS.caps.tsv の cap に note がありません"
                   f"（なぜ上限を上げるのかを書かないと、上限は意味を失います）")

    measured = 0
    for name in names:
        dynamic, _static, ok, reason = stats[name]
        if reason:
            red.append(f"{name}: {reason}")
            continue
        if not ok or dynamic is None:
            note.append(f"{name}: 予算 未計測（古い engine で焼いた絵）")
            continue
        measured += 1
        cap = caps.get(name, DEFAULT_CAP)
        if dynamic >= cap:
            red.append(f"{name}: 動的 {dynamic} 個 ≥ 上限 {cap} 個"
                       f"{'' if name in caps else '（既定）'}")
            continue
        if name in base:
            limit = drift_limit(base[name])
            if dynamic > limit:
                verb = "基準として焼けません" if gate else "増えすぎです"
                red.append(f"{name}: 動的 {dynamic} 個 — 基準 {base[name]} 個から"
                           f"{limit} 個を超えて増えたので{verb}")
    return red, note, measured


def main(argv):
    root = argv[1] if len(argv) > 1 and not argv[1].startswith("--") else "."
    gate = "--gate" in argv
    # status.py は 1 画面に収めるのが仕事なので、直し方の助言は要らない（見つけた物だけ）。
    brief = "--brief" in argv
    if gate:
        i = argv.index("--gate")
        baseline_path = argv[i + 1] if len(argv) > i + 1 else ""
        gallery_dir = "gallery"
    else:
        baseline_path = os.path.join(root, "reference", "ITEMS.tsv")
        gallery_dir = "gallery"

    red, note, measured = judge(root, gallery_dir, baseline_path, gate)

    for line in note:
        print(f"[budget] {line}")

    if red:
        head = "reference-update 中止: 絵の値段" if gate else "reference-check NG: 絵の値段"
        print(f"{head}", file=sys.stderr)
        for line in red:
            print(f"  {line}", file=sys.stderr)
        if brief:
            return 1
        if gate:
            print("  意図した増加なら make reference-update BUDGET=accept で明示してください。",
                  file=sys.stderr)
            print("  上限そのものを場面ごとに上げるなら reference/ITEMS.caps.tsv に"
                  "cap と note を書いてください。", file=sys.stderr)
        else:
            print("  盤や群れを毎フレーム組んでいないか確かめてください"
                  "（逆引き: docs/module-index.md）。", file=sys.stderr)
            print("  意図した増加なら make reference-update BUDGET=accept で基準を更新します。",
                  file=sys.stderr)
        return 1

    if measured:
        print(f"budget OK: {measured} 場面すべて予算の内側です")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
