#!/usr/bin/env python3
"""絵の変化を、画像を開かずに数値で掴むダイジェスト。

    python3 bin/img-digest.py old.png new.png     # 2 枚を比べる
    python3 bin/img-digest.py oldDir/ newDir/     # フォルダごと比べる
    python3 bin/img-digest.py oldDir/ newDir/ battle.png door.png
                                                  # 名前を挙げた絵だけ比べる

make bench が不一致の名前を出したら、その名前だけを 3 個目以降の引数に渡せば、
全ファイルを読み直さずに済む。

フォルダ比較では、まずバイト比較で一致した物を 1 行にまとめ、不一致だけ
差分画素率・変化した領域・色数・明るさの数行に要約する。目視は、この数値で
当たりを付けた後の最終確認 1 回に絞れる。

bin/carve/png_read.py を import しないのは、sync-agents がこのファイルを
1 枚だけ他リポへ配るため。デコーダは同じ作り (zlib+struct、8bit 非インター
レースのみ) を内蔵する。GIF と未対応 PNG は数えて飛ばす。
"""

import hashlib
import os
import struct
import sys
import zlib

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}

# 1 画面に収める上限。不一致が多い時は差分画素率の大きい順にここまで。
MAX_DETAIL = 12

BLOCK_NAMES = [
    ["左上", "上", "右上"],
    ["左", "中央", "右"],
    ["左下", "下", "右下"],
]


def unfilter(raw, height, bpp, stride):
    """行ごとの前処理 (filter) を戻す。1 画素ずつ回すと大きい絵で分単位になるので
    filter 0/2 は行まるごと処理する。"""
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        filt = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if filt == 0:
            pass
        elif filt == 2:
            line = bytearray((a + b) & 255 for a, b in zip(line, prev))
        elif filt == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif filt == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif filt == 4:
            for i in range(bpp):
                line[i] = (line[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a = line[i - bpp]
                b = prev[i]
                c = prev[i - bpp]
                p = a + b - c
                pa = p - a if p >= a else a - p
                pb = p - b if p >= b else b - p
                pc = p - c if p >= c else c - p
                if pa <= pb and pa <= pc:
                    near = a
                elif pb <= pc:
                    near = b
                else:
                    near = c
                line[i] = (line[i] + near) & 255
        prev = line
        rows.append(line)
    return rows


def read_png(path):
    """(幅, 高さ, 行ごとの RGBA バイト列) を返す。未対応形式は ValueError。"""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("PNG ではない")
    pos, idat, palette, alpha = 8, b"", None, None
    width = height = depth = kind = None
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, kind, _, _, interlace = struct.unpack(
                ">IIBBBBB", body)
            if interlace:
                raise ValueError("インターレース PNG は未対応")
        elif tag == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif tag == b"tRNS":
            alpha = body
        elif tag == b"IDAT":
            idat += body
        pos += 12 + length
    if depth != 8:
        raise ValueError(f"8bit 以外は未対応 (depth={depth})")
    channels = CHANNELS[kind]
    lines = unfilter(zlib.decompress(idat), height, channels, width * channels)

    rows = []
    for line in lines:
        if kind == 6:
            rows.append(bytes(line))
            continue
        out = bytearray(width * 4)
        if kind == 2:
            for x in range(width):
                out[x * 4:x * 4 + 3] = line[x * 3:x * 3 + 3]
                out[x * 4 + 3] = 255
        elif kind == 3:
            for x in range(width):
                index = line[x]
                r, g, b = palette[index] if palette else (0, 0, 0)
                a = (alpha[index]
                     if alpha and index < len(alpha) else 255)
                out[x * 4:x * 4 + 4] = (r, g, b, a)
        elif kind == 0:
            for x in range(width):
                v = line[x]
                out[x * 4:x * 4 + 4] = (v, v, v, 255)
        else:
            for x in range(width):
                v = line[x * 2]
                out[x * 4:x * 4 + 4] = (v, v, v, line[x * 2 + 1])
        rows.append(bytes(out))
    return width, height, rows


def color_stats(width, height, rows):
    """(色ごとの画素数, 輝度合計) をまとめて取る。2 回走査しないため 1 パス。"""
    counts = {}
    luma = 0
    for row in rows:
        for x in range(width):
            rgb = row[x * 4:x * 4 + 3]
            counts[rgb] = counts.get(rgb, 0) + 1
            luma += 299 * row[x * 4] + 587 * row[x * 4 + 1] + 114 * row[x * 4 + 2]
    return counts, luma / (1000.0 * width * height)


def digest_pair(old_path, new_path):
    """不一致 2 枚の要約行 (文字列の並び) と差分画素率を返す。"""
    ow, oh, old_rows = read_png(old_path)
    nw, nh, new_rows = read_png(new_path)
    lines = []
    if (ow, oh) != (nw, nh):
        lines.append(f"寸法が変わった: {ow}x{oh} -> {nw}x{nh} (重なる範囲だけ比較)")
    w, h = min(ow, nw), min(oh, nh)

    diff = 0
    min_x, min_y, max_x, max_y = w, h, -1, -1
    blocks = [[0] * 3 for _ in range(3)]
    for y in range(h):
        orow, nrow = old_rows[y], new_rows[y]
        if orow[:w * 4] == nrow[:w * 4]:
            continue
        by = min(y * 3 // h, 2)
        for x in range(w):
            if orow[x * 4:x * 4 + 4] != nrow[x * 4:x * 4 + 4]:
                diff += 1
                blocks[by][min(x * 3 // w, 2)] += 1
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y
    total = w * h
    rate = 100.0 * diff / total if total else 0.0

    if diff == 0:
        lines.append("重なる範囲の画素は同一 (差はメタ情報か寸法だけ)")
    else:
        lines.append(f"差分画素 {rate:.1f}% ({diff}/{total}px)  "
                     f"範囲 x={min_x} y={min_y} w={max_x - min_x + 1} h={max_y - min_y + 1}")
        ranked = sorted(
            ((blocks[by][bx], BLOCK_NAMES[by][bx])
             for by in range(3) for bx in range(3)),
            reverse=True)
        top = [name for n, name in ranked if n > 0 and n >= ranked[0][0] * 0.5][:3]
        share = 100.0 * ranked[0][0] / diff
        lines.append(f"差の集中: {'/'.join(top)} (最大ブロックに {share:.0f}%)")

    old_colors, old_luma = color_stats(ow, oh, old_rows)
    new_colors, new_luma = color_stats(nw, nh, new_rows)
    delta_colors = len(new_colors) - len(old_colors)
    color_line = f"色数 {len(old_colors)} -> {len(new_colors)}"
    if abs(delta_colors) >= 8:
        added = sorted(((n, rgb) for rgb, n in new_colors.items()
                        if rgb not in old_colors), reverse=True)[:3]
        if added:
            hexes = " ".join("#%02x%02x%02x" % tuple(rgb) for _, rgb in added)
            color_line += f"  新顔の代表色: {hexes}"
    delta_luma = new_luma - old_luma
    if abs(delta_luma) < 0.5:
        color_line += f"  平均輝度 ほぼ同じ ({old_luma:.1f})"
    elif delta_luma > 0:
        color_line += f"  明るくなった ({old_luma:.1f} -> {new_luma:.1f})"
    else:
        color_line += f"  暗くなった ({old_luma:.1f} -> {new_luma:.1f})"
    lines.append(color_line)
    return lines, rate


def compare_files(old_path, new_path):
    if open(old_path, "rb").read() == open(new_path, "rb").read():
        print("一致 (バイト同一)")
        return 0
    print(f"{os.path.basename(old_path)} -> {os.path.basename(new_path)}: 不一致")
    try:
        lines, _ = digest_pair(old_path, new_path)
    except ValueError as e:
        print(f"  ダイジェスト不可: {e}")
        return 1
    for line in lines:
        print(f"  {line}")
    return 1


def list_images(root):
    """root 以下の PNG/GIF を相対パスで集める。順番を安定させるため sort。"""
    found = {}
    for base, _, names in os.walk(root):
        for name in names:
            low = name.lower()
            if low.endswith(".png") or low.endswith(".gif"):
                full = os.path.join(base, name)
                found[os.path.relpath(full, root).replace(os.sep, "/")] = full
    return dict(sorted(found.items()))


def old_hashes(old_root):
    """スナップショットの SHA256SUMS.txt があれば {ファイル名: ハッシュ} を返す。無ければ None。
    一覧にある名前は旧ファイルを読み直さず、新側のハッシュだけで一致を判定できる。"""
    sums = os.path.join(old_root, "SHA256SUMS.txt")
    if not os.path.isfile(sums):
        return None
    table = {}
    for line in open(sums, encoding="utf-8"):
        parts = line.split(None, 1)
        if len(parts) == 2:
            table[parts[1].strip()] = parts[0]
    return table


def compare_dirs(old_root, new_root, names):
    old_files = list_images(old_root)
    new_files = list_images(new_root)
    if names:
        wanted = set(names)
        keep = lambda rel: rel in wanted or os.path.basename(rel) in wanted
        old_files = {k: v for k, v in old_files.items() if keep(k)}
        new_files = {k: v for k, v in new_files.items() if keep(k)}
        if not (old_files or new_files):
            print("指定した名前の絵がどちらのフォルダにもありません")
            return 1
    gifs = [p for p in set(old_files) | set(new_files) if p.lower().endswith(".gif")]
    only_old = [p for p in old_files if p not in new_files and p not in gifs]
    only_new = [p for p in new_files if p not in old_files and p not in gifs]

    hashes = old_hashes(old_root)
    same = 0
    mismatched = []
    for rel in old_files:
        if rel in gifs or rel not in new_files:
            continue
        if hashes is not None and rel in hashes:
            new_hash = hashlib.sha256(open(new_files[rel], "rb").read()).hexdigest()
            equal = new_hash == hashes[rel]
        else:
            equal = (open(old_files[rel], "rb").read()
                     == open(new_files[rel], "rb").read())
        if equal:
            same += 1
        else:
            mismatched.append(rel)

    if same:
        print(f"一致 {same} 枚 (詳細略)")
    if gifs:
        print(f"GIF {len(gifs)} 本は対象外 (スキップ)")
    for rel in only_old:
        print(f"消えた: {rel} (旧側にだけある)")
    for rel in only_new:
        print(f"増えた: {rel} (新側にだけある)")

    digests = []
    for rel in mismatched:
        try:
            lines, rate = digest_pair(old_files[rel], new_files[rel])
            digests.append((rate, rel, lines))
        except ValueError as e:
            digests.append((0.0, rel, [f"ダイジェスト不可: {e}"]))
    digests.sort(key=lambda t: -t[0])

    for rate, rel, lines in digests[:MAX_DETAIL]:
        print(f"不一致: {rel}")
        for line in lines:
            print(f"  {line}")
    if len(digests) > MAX_DETAIL:
        rest = ", ".join(rel for _, rel, _ in digests[MAX_DETAIL:][:20])
        print(f"他 {len(digests) - MAX_DETAIL} 枚 (差分画素率の小さい順に略): {rest}")

    if not (mismatched or only_old or only_new):
        print("全て一致")
        return 0
    return 1


def main(argv):
    if len(argv) < 2:
        print("使い方: python3 bin/img-digest.py old.png new.png")
        print("        python3 bin/img-digest.py oldDir/ newDir/ [名前...]")
        return 1
    old_path, new_path = argv[0], argv[1]
    names = argv[2:]
    for p in (old_path, new_path):
        if not os.path.exists(p):
            print(f"見つからない: {p}")
            return 1
    if os.path.isdir(old_path) and os.path.isdir(new_path):
        return compare_dirs(old_path, new_path, names)
    if os.path.isfile(old_path) and os.path.isfile(new_path):
        if names:
            print("名前絞り込みはフォルダ比較のときだけ使えます")
            return 1
        return compare_files(old_path, new_path)
    print("片方がファイルで片方がフォルダです。同じ種類どうしで比べてください")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
