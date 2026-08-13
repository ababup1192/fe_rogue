#!/usr/bin/env python3
"""View が矩形と円だけになっていないかを検査する。

絵の下限 5 性質（面に階調か質感 / 主役が背景から分離 / 層が分かれている /
時間が流れている）は box と circle では作れない。人の目視より前に機械が声を出す。

  python3 bin/lint-view.py                 # templates/ を全部見る
  python3 bin/lint-view.py path/to/View.flix ...  # 指定ファイルだけ見る

標準ライブラリだけで動く（Windows / macOS / Linux 共通）。
"""

import re
import sys
from pathlib import Path

# 矩形系 = box と circle。これだけで組んだ画面は下限を満たせない。
# 図形プリミティブは Render から RawDraw へ移設済み（旧名 Render.* も過渡期のため両対応）。
RECT = re.compile(
    r"(?:(?:Render|RawDraw)\.(?:box|boxAt|orBoxAt|circle|circleAt)|Item\.Box)\b"
)

# 階調・質感・分離・層・時間のどれかを作れる部品。
RICH = re.compile(
    r"(?:(?:Render|RawDraw)\.(?:star|ellipse\w*|sector|ngon)"
    r"|Render\.(?:vgrad|gradPolygon|striped|checker"
    r"|glowAt|outline|outlineA|shaderFill|turned|turnedAll|clipped|clippedAll"
    r"|zShifted|zShiftedAll|fadeAll|overItem)"
    r"|PxSprite|PxShade|Material|Scatter|FxDoc|Fx\.|Anim|Sway|Daylight|Mirror"
    r"|TileLayer|DualGrid|Terrain|ShaderDoc|UiShape|Color\.(?:warm|cool))\b"
)

# 部品が少ないうちは判定しない（下請け関数・小さな HUD で誤爆させない）。
MIN_DRAWS = 5
# 矩形系がこの割合を超えたら指摘する。
RECT_PCT = 80

# 行き先の目安。長い説明はしない — 1 行で足りる案内だけ。
DESTINATIONS = (
    "空・水面→vgrad/gradPolygon、パネル→outline+rounded、"
    "キャラ・物→PxSprite+PxShade、面の質感→shader.json"
)

HINT = (
    "絵の下限 5 性質を満たせていません。"
    "{} （詳細は .claude/skills/visual-dict/reference.md）"
).format(DESTINATIONS)


def rect_counts(src: str):
    """コメントを除いた本文で、RECT にマッチした関数名ごとの回数を数える。"""
    body = "\n".join(
        ln for ln in src.splitlines() if not ln.lstrip().startswith("//")
    )
    counts = {}
    for m in RECT.finditer(body):
        name = m.group(0).rsplit(".", 1)[-1]
        counts[name] = counts.get(name, 0) + 1
    return counts


def is_target(path: Path) -> bool:
    # 名前では絞らない — 名前を変えるとスキップできる穴になる。
    # 描画をほとんど含まないファイルは MIN_DRAWS で除外される。
    return path.name.endswith(".flix")


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


def hud_smell(project_dir: Path):
    """HUD の匂い: view（world 側）に文字を直書きしているのに withHudView が無い。

    world 側の文字は、爆発などの高い z の絵に隠されうる（HUD の範囲に乗らない）。
    強制はしない — 警告だけ出して、直すかどうかは人が決める。
    """
    src = project_dir / "src"
    if not src.is_dir():
        return None
    uses_text = False
    has_hud = False
    for p in src.rglob("*.flix"):
        try:
            body = "\n".join(
                ln
                for ln in p.read_text(encoding="utf-8", errors="replace").splitlines()
                if not ln.lstrip().startswith("//")
            )
        except OSError:
            continue
        if "withHudView" in body:
            has_hud = True
        if p.parent.name != "render" and re.search(r"Render\.text|TextDraw\.", body):
            uses_text = True
    if uses_text and not has_hud:
        return (
            "警告: {} — 文字（Render.text / TextDraw）を world 側の絵に直書きしていますが"
            " withHudView がありません。スコアや案内文は App.withHudView に繋ぐと、"
            "world 側の z がどれだけ大きくても必ず手前に出ます（警告のみ・失敗にはしません）"
        ).format(project_dir.as_posix())
    return None


def project_root_of(path: Path):
    """検査対象のファイルからゲーム 1 本の根（src の親）を探す。無ければ None。"""
    for parent in path.parents:
        if parent.name == "src":
            return parent.parent
    return None


def main(argv):
    if argv:
        targets = [Path(a) for a in argv]
    else:
        root = Path(__file__).resolve().parent.parent
        targets = [
            p
            for base in ("templates",)
            for p in (root / base).rglob("*.flix")
        ]

    bad = []
    skipped = []
    for path in targets:
        if not path.is_file() or not is_target(path):
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

    # HUD の匂い（ゲーム 1 本ごとに 1 回だけ・警告のみで exit code に効かせない）。
    seen_roots = set()
    for path in targets:
        if not path.is_file() or not is_target(path):
            continue
        root_dir = project_root_of(path)
        if root_dir is None or root_dir in seen_roots:
            continue
        seen_roots.add(root_dir)
        smell = hud_smell(root_dir)
        if smell:
            print(smell)

    if not bad:
        print("OK: 矩形だけの View はありません（除外 {} 件）".format(len(skipped)))
        return 0

    for path, rect, total in bad:
        try:
            src = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            src = ""
        counts = rect_counts(src)
        detected = "、".join(
            "{} が {} 回".format(name, n) for name, n in sorted(counts.items())
        )
        print(
            "{}: 描画がほぼ矩形と円だけです（矩形系 {} / 全体 {}）— {}。{}".format(
                path.as_posix(), rect, total, detected, DESTINATIONS
            ),
            file=sys.stderr,
        )
    print("", file=sys.stderr)
    print(HINT, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
