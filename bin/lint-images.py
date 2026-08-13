#!/usr/bin/env python3
"""git に入れる絵が増えすぎていないか見張るゲート。

生成した絵 (各ゲームの gallery/ と reference/*.png) は git 管理外にしてある。PNG/GIF は
生成し直すたび丸ごと別の実体になり、差分圧縮も効かないまま履歴に積み上がるためで、
放っておくと clone が何十 MB も重くなる。このゲートは、その決まりが守られているかを見る。

追跡してよい絵は 3 種類だけ:
  展示    人に見せる絵 (docs/gallery/) とブランド素材 (docs/brand/)
  素材    ゲームが実行時に読む画像 (assets/) とアプリのアイコン
  例外    templates/*/reference/title.png … Studio のジャンルカードのサムネイルが実体を読む

使い方: python3 bin/lint-images.py [ルート]   (既定のルートはこのファイルの親の親)
決まりが破れていれば 1 行ずつ挙げて終了コード 1。
"""

import os
import subprocess
import sys

IMAGE_EXTS = (".png", ".gif", ".jpg", ".jpeg", ".webp", ".bmp")

# 展示場 docs/gallery/ の上限 (docs/gallery/README.md に同じ数字を書いてある)。
GALLERY_MAX_FILES = 20
GALLERY_MAX_FILE_BYTES = 300 * 1024
GALLERY_MAX_TOTAL_BYTES = 4 * 1024 * 1024

# 追跡画像の総量。ここを超えたら「どこかで生成した絵が紛れ込んだ」と疑う。
TRACKED_MAX_TOTAL_BYTES = 8 * 1024 * 1024

# 追跡してよい絵の置き場。パスの前方一致か、末尾一致で判定する。
ALLOWED_PREFIXES = (
    "docs/gallery/",
    "docs/brand/",
    "editor_app/src-tauri/icons/",
)
ALLOWED_SUBSTRINGS = (
    "/assets/",
)
ALLOWED_SUFFIXES = (
    "/reference/title.png",
)


def human(n):
    if n >= 1024 * 1024:
        return f"{n / 1024 / 1024:.1f}MB"
    return f"{n / 1024:.0f}KB"


def tracked_images(root):
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "-z"],
        capture_output=True, text=True, check=True,
    ).stdout
    paths = [p for p in out.split("\0") if p.lower().endswith(IMAGE_EXTS)]
    return sorted(paths)


def allowed(path):
    if path.startswith(ALLOWED_PREFIXES):
        return True
    if path.endswith(ALLOWED_SUFFIXES):
        return True
    return any(s in path for s in ALLOWED_SUBSTRINGS)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems = []

    paths = tracked_images(root)
    sizes = {}
    for p in paths:
        full = os.path.join(root, p)
        sizes[p] = os.path.getsize(full) if os.path.exists(full) else 0

    # 1. 置き場の決まり
    for p in paths:
        if not allowed(p):
            problems.append(
                f"{p} ({human(sizes[p])}) — 追跡してよい置き場ではありません。"
                f"人に見せる絵なら docs/gallery/ へ移してください"
            )

    # 2. 展示場の上限
    gallery = [p for p in paths if p.startswith("docs/gallery/")]
    total = sum(sizes[p] for p in gallery)
    if len(gallery) > GALLERY_MAX_FILES:
        problems.append(
            f"docs/gallery/ が {len(gallery)} 枚 — 上限 {GALLERY_MAX_FILES} 枚。"
            f"古いものを落としてください"
        )
    for p in gallery:
        if sizes[p] > GALLERY_MAX_FILE_BYTES:
            problems.append(
                f"{p} が {human(sizes[p])} — 1 枚の上限 {human(GALLERY_MAX_FILE_BYTES)}。"
                f"寸法を整数分の 1 に縮めてください (docs/gallery/README.md)"
            )
    if total > GALLERY_MAX_TOTAL_BYTES:
        problems.append(
            f"docs/gallery/ の合計が {human(total)} — 上限 {human(GALLERY_MAX_TOTAL_BYTES)}"
        )

    # 3. 追跡画像の総量
    grand = sum(sizes.values())
    if grand > TRACKED_MAX_TOTAL_BYTES:
        problems.append(
            f"追跡している絵の合計が {human(grand)} — 上限 {human(TRACKED_MAX_TOTAL_BYTES)}。"
            f"生成した絵が紛れ込んでいないか git ls-files で確かめてください"
        )

    if problems:
        print(f"[lint-images] {len(problems)} 件:")
        for m in problems:
            print(f"  {m}")
        return 1

    print(
        f"[lint-images] OK — 追跡 {len(paths)} 枚 / {human(grand)} "
        f"(展示場 docs/gallery/ は {len(gallery)} 枚 / {human(total)})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
