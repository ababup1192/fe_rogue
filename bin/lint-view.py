#!/usr/bin/env python3
"""View が矩形と円だけになっていないかを検査する。

絵の下限 4 性質（面に階調か質感 / 主役が背景から分離 / 層が分かれている /
時間が流れている）は box と circle では作れない。人の目視より前に機械が声を出す。

  python3 bin/lint-view.py                 # templates/ と examples/ を全部見る
  python3 bin/lint-view.py path/to/View.flix ...  # 指定ファイルだけ見る

標準ライブラリだけで動く（Windows / macOS / Linux 共通）。
"""

import re
import sys
from pathlib import Path

# 矩形系 = box と circle。これだけで組んだ画面は下限を満たせない。
RECT = re.compile(
    r"(?:Render\.(?:box|circle|boxAt|circleAt)|Item\.(?:Box|Circle))\b"
)

# 階調・質感・分離・層・時間のどれかを作れる部品。
RICH = re.compile(
    r"(?:Render\.(?:star|ellipse|sector|ngon|vgrad|gradPolygon|striped|checker"
    r"|glowAt|outline|outlineA|shaderFill|turned|turnedAll|clipped|clippedAll"
    r"|zShifted|zShiftedAll|fadeAll|overItem)"
    r"|PxSprite|PxShade|Material|Scatter|FxDoc|Fx\.|Anim|Sway|Daylight|Mirror"
    r"|TileLayer|DualGrid|Terrain|ShaderDoc|UiShape|Color\.(?:warm|cool))\b"
)

# 部品が少ないうちは判定しない（下請け関数・小さな HUD で誤爆させない）。
MIN_DRAWS = 5
# 矩形系がこの割合を超えたら指摘する。
RECT_PCT = 80

HINT = """絵の下限 4 性質（面に階調か質感 / 主役が背景から分離 / 層が分かれている /
時間が流れている）を、それぞれどの部品で満たしているか答えてください。
満たせていないなら .claude/skills/visual-dict/reference.md と unused-parts.md を
読んでから直してください。star / ellipse / vgrad / gradPolygon / striped /
PxShade / Material / Scatter / ShaderDoc は既に実装もテストもあります。"""


def is_view(path: Path) -> bool:
    name = path.name
    if not name.endswith(".flix"):
        return False
    if "View" in name:
        return True
    return path.parent.name == "bake"


def exempt_reason(src: str):
    """`// lint-view: 対象外 — 理由` が書いてあればその理由を返す。

    黙って除外はしない。理由を書かせ、走らせた人には除外した件数を見せる。
    """
    for line in src.splitlines():
        stripped = line.strip()
        if not stripped.startswith("//"):
            continue
        if "lint-view:" in stripped and "対象外" in stripped:
            _, _, tail = stripped.partition("対象外")
            return tail.lstrip(" —-–:").strip() or "（理由が書かれていません）"
    return None


def check(path: Path):
    """(矩形数, 総数) を返す。判定対象外なら None。"""
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    # コメント行は数えない（doc コメントに部品名が並ぶだけで合格にしない）。
    body = "\n".join(
        ln for ln in src.splitlines() if not ln.lstrip().startswith("//")
    )
    rect = len(RECT.findall(body))
    rich = len(RICH.findall(body))
    total = rect + rich
    if total < MIN_DRAWS:
        return None
    return rect, total


def main(argv):
    if argv:
        targets = [Path(a) for a in argv]
    else:
        root = Path(__file__).resolve().parent.parent
        targets = [
            p
            for base in ("templates", "examples")
            for p in (root / base).rglob("*.flix")
        ]

    bad = []
    skipped = []
    for path in targets:
        if not path.is_file() or not is_view(path):
            continue
        try:
            src = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        reason = exempt_reason(src)
        if reason is not None:
            skipped.append((path, reason))
            continue
        result = check(path)
        if result is None:
            continue
        rect, total = result
        if rect * 100 > total * RECT_PCT:
            bad.append((path, rect, total))

    for path, reason in skipped:
        print("除外: {} — {}".format(path.as_posix(), reason))

    if not bad:
        print("OK: 矩形だけの View はありません（除外 {} 件）".format(len(skipped)))
        return 0

    for path, rect, total in bad:
        print(
            "{}: 描画がほぼ矩形と円だけです（矩形系 {} / 全体 {}）".format(
                path.as_posix(), rect, total
            ),
            file=sys.stderr,
        )
    print("", file=sys.stderr)
    print(HINT, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
