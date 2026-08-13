#!/usr/bin/env python3
"""ループ GIF の継ぎ目を機械で確かめる (標準ライブラリのみ)。

  python3 bin/lint-loop.py out/frames/bonfire      # コマ列ディレクトリを指定
  python3 bin/lint-loop.py                         # templates/ 配下を全部
  python3 bin/lint-loop.py --strict                # 注意を NG に上げる
  python3 bin/lint-loop.py --self-test             # この lint 自身の検査

見るのは 1 つだけ: **最終コマ → 先頭コマの差分画素率が、通常のコマ間から外れていないか。**
外れていれば、繰り返した瞬間に絵が飛ぶ(継ぎ目が見える)。

入力は bake 済みのコマ PNG ディレクトリ(Bakery.bakeGif が生成する `frames/<名前>/<連番>.png`)。
fade / wipe のような「ループしない演出」のコマ列は最後と最初が違って当然なので、
指摘が出ても継ぎ目の事故ではない — ループ GIF のディレクトリだけを見ること。
"""

import importlib.util
import operator
import os
import re
import sys

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

# 継ぎ目差分率がこの倍率で通常コマ間の最大を超えたら警告
RATIO = 1.5
# 静けさが画風のループでは通常コマ間差分が ≈0 になり、相対閾値だけだと誤爆する。
# 絶対にこの率未満の継ぎ目は常に合格とする。
ABS_FLOOR = 0.005

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "img_digest", os.path.join(_here, "img-digest.py"))
_img = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_img)
read_png = _img.read_png


def load_frame(path):
    """(幅, 高さ, 1 画素 = 1 整数の列) にする。比較を C 速度に落とすため。"""
    width, height, rows = read_png(path)
    return width, height, memoryview(b"".join(rows)).cast("I")


def diff_rate(a, b):
    """2 枚の、色が違う画素の割合。寸法違いは全画素違い扱い。"""
    aw, ah, a_px = a
    bw, bh, b_px = b
    if (aw, ah) != (bw, bh) or aw * ah == 0:
        return 1.0
    if a_px == b_px:
        return 0.0
    return sum(map(operator.ne, a_px, b_px)) / (aw * ah)


def seam_verdict(rates, seam):
    """通常コマ間の差分率の列と継ぎ目差分率から、指摘文か None を返す。"""
    if seam < ABS_FLOOR:
        return None
    ceiling = max(rates) * RATIO
    if seam <= ceiling:
        return None
    return (
        f"継ぎ目(最終→先頭)で画素の {seam:.1%} が変わる "
        f"(通常コマ間の最大 {max(rates):.1%} × {RATIO} = {ceiling:.1%} を超過) "
        "— 繰り返した瞬間に絵が飛ぶ"
    )


def frame_files(directory):
    """`<連番>.png` を番号順に。連番でない PNG は対象外。"""
    named = []
    for name in os.listdir(directory):
        m = re.fullmatch(r"(\d+)\.png", name)
        if m:
            named.append((int(m.group(1)), os.path.join(directory, name)))
    return [p for _, p in sorted(named)]


def check_dir(directory):
    files = frame_files(directory)
    if len(files) < 3:
        return []
    try:
        frames = [load_frame(p) for p in files]
    except ValueError as err:
        return [f"読めない PNG がある: {err}"]
    rates = [diff_rate(a, b) for a, b in zip(frames, frames[1:])]
    note = seam_verdict(rates, diff_rate(frames[-1], frames[0]))
    return [note] if note else []


GAME_ROOTS = ("templates",)
EXCLUDED_DIRS = {".git", "build", "lib", ".devbox", "target", "node_modules"}


def discover(root):
    """templates/ 配下(無ければ自分自身)の frames/*/ を探す。"""
    bases = []
    for group in GAME_ROOTS:
        group_dir = os.path.join(root, group)
        if os.path.isdir(group_dir):
            bases.extend(
                os.path.join(group_dir, n) for n in sorted(os.listdir(group_dir))
                if os.path.isdir(os.path.join(group_dir, n)))
    if not bases:
        bases = [root]
    found = []
    for base in bases:
        for current, dir_names, _ in os.walk(base):
            dir_names[:] = sorted(d for d in dir_names if d not in EXCLUDED_DIRS)
            if os.path.basename(current) == "frames":
                found.extend(
                    os.path.join(current, d) for d in sorted(dir_names))
                dir_names[:] = []
    return found


def _png_bytes(width, height, pixel_of):
    """self-test 用の最小 PNG (RGBA・無圧縮に近い 1 枚)。"""
    import struct
    import zlib

    raw = b""
    for y in range(height):
        raw += b"\x00" + b"".join(
            bytes(pixel_of(x, y)) for x in range(width))

    def chunk(tag, body):
        data = tag + body
        return struct.pack(">I", len(body)) + data + struct.pack(
            ">I", zlib.crc32(data))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def _self_test():
    import tempfile

    ok = []

    def case(name, hit):
        ok.append(("OK  " if hit else "NG  ") + name)

    case("静けさの床: 継ぎ目 0.4% は常に合格",
         seam_verdict([0.0, 0.0], 0.004) is None)
    case("継ぎ目が跳ねると警告",
         seam_verdict([0.02, 0.03], 0.10) is not None)
    case("通常コマ間と同程度なら合格",
         seam_verdict([0.02, 0.03], 0.04) is None)
    case("通常が全て 0 で継ぎ目だけ 1% は警告",
         seam_verdict([0.0, 0.0], 0.01) is not None)

    red = lambda x, y: (255, 0, 0, 255)
    blue = lambda x, y: (0, 0, 255, 255)
    with tempfile.TemporaryDirectory() as tmp:
        loop = os.path.join(tmp, "loop")
        os.mkdir(loop)
        for i, px in enumerate([red, red, red]):
            with open(os.path.join(loop, f"{i}.png"), "wb") as h:
                h.write(_png_bytes(4, 4, px))
        case("同一 3 コマのループは合格", check_dir(loop) == [])

        # 1 コマにつき 1 列ずつ青へ流れ、先頭へ戻らない列(ドリフト)。
        # 通常コマ間は 25% ずつだが、継ぎ目(最終→先頭)は 50% 戻るので警告になる。
        drift = os.path.join(tmp, "drift")
        os.mkdir(drift)
        for i in range(3):
            px = lambda x, y, i=i: (0, 0, 255, 255) if x < i else (255, 0, 0, 255)
            with open(os.path.join(drift, f"{i}.png"), "wb") as h:
                h.write(_png_bytes(4, 4, px))
        case("先頭へ戻らないドリフトは警告", check_dir(drift) != [])

    for line in ok:
        print(line)
    bad = [x for x in ok if x.startswith("NG")]
    print(f"\n{len(ok) - len(bad)}/{len(ok)} 件 OK")
    return 1 if bad else 0


def main(argv):
    if "--self-test" in argv:
        return _self_test()
    strict = "--strict" in argv
    targets = [a for a in argv if not a.startswith("--")]
    root = os.path.dirname(_here)
    if not targets:
        targets = discover(root)
    total = 0
    for path in targets:
        notes = check_dir(path)
        if notes:
            print(f"\n{os.path.relpath(path, root)}")
            for note in notes:
                print(f"  {'NG' if strict else '注意'}: {note}")
            total += len(notes)
    label = "NG" if strict else "注意"
    print(f"\n{len(targets)} ディレクトリ / {label} {total} 件")
    return 1 if (strict and total) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
