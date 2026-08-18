#!/usr/bin/env python3
"""git commit の直前に走るゲート (bin/githooks/pre-commit の本体)。

文章で頼むだけだと守られない決まりを、コミットの瞬間に機械が止める:

  1. 生成した絵の混入    今回ステージした画像が置き場の決まりの外なら止める。
                         過去から追跡されている違反は止めない (1 行知らせるだけ)
  2. 規約の配線ずれ      AGENTS.md / docs/ / .claude/ / *.flix を触ったコミットは
                         make check-docs-sync (api-digest のずれ検出を含む) を通す
  3. 矩形だけの View     ステージした View が box と circle だけなら止める
  4. 解けない意味色      ステージに *.sprite.json / *.theme.json があれば
                         lint-palette を通す
  5. 文字のはみ出す形    ステージに *.ui.json があれば lint-ui-overflow を
                         そのファイルだけに通す (折り返し宣言漏れを止める)
  6. 独自の比喩語        今回書き足したコメント・文章に、bin/lint-jargon.py の
                         WORDS の語が混ざっていたら止める。既存の行は見ない
  7. 読み込み中の bug!   今回書き足した行が *OrBug 以外の関数の中で bug! を呼んで
                         いたら止める (docs/error-handling.md の決まり 2)。
                         残すと決めた bug! は bin/lint-fallback.py の EXEMPT
  8. pub 面の Float32     engine / engine_world / engine_tools の *.flix を触ったら
                         pub 面 (型・関数・eff の op) に Float32 が無いか検査する。
                         残すと決めた Float32 は bin/lint-f32.py の EXEMPT

使い方:
  通常は git が bin/githooks/pre-commit 経由で呼ぶ (配線は make hooks)
  python3 bin/fge precommit --files a.png b.flix   # ステージの代わりに指定して試す
  git commit --no-verify                           # どうしても迂回したいとき

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
"""

import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def tool(name):
    """bin/ の検査スクリプトの場所。無ければ None (ゲームリポで pack が古い・
    未配布でもコミットは止めない。fail-open で 1 行知らせるだけ)。"""
    path = ROOT / "bin" / name
    if path.is_file():
        return path
    print(f"[pre-commit] bin/{name} が無いのでその検査は飛ばします"
          " (engine の make sync-agents GAME=... で配り直せます)")
    return None


def load_lint_images():
    """置き場の決まり (allowed 等) を bin/lint-images.py から借りる。二重管理しない。"""
    path = tool("lint-images.py")
    if path is None:
        return None
    spec = importlib.util.spec_from_file_location("lint_images", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def staged_files():
    out = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--cached", "--name-only",
         "--diff-filter=ACMR", "-z"],
        capture_output=True, text=True, check=True,
    ).stdout
    return [p for p in out.split("\0") if p]


def run(cmd):
    """出力をそのまま見せて終了コードを返す。"""
    return subprocess.run(cmd, cwd=ROOT).returncode


def run_lint(name, sub, *args):
    """bin/ の検査を bin/fge 経由で走らせる。無ければ 0 (fail-open)。"""
    if tool(name) is None:
        return 0
    return run([sys.executable, str(ROOT / "bin" / "fge"), sub, *args])


def human(n):
    if n >= 1024 * 1024:
        return f"{n / 1024 / 1024:.1f}MB"
    return f"{n / 1024:.0f}KB"


def check_staged_images(staged, li):
    """今回ステージした画像だけを、置き場と大きさの決まりに照らす。"""
    problems = []
    if li is None:
        return problems
    imgs = [p for p in staged if p.lower().endswith(li.IMAGE_EXTS)]
    for p in imgs:
        if not li.allowed(p):
            problems.append(
                f"{p} — 追跡してよい置き場ではありません。生成した絵は git に入れない決まりです。"
                f"人に見せる絵なら docs/gallery/ へ (上限あり)"
            )
            continue
        full = ROOT / p
        size = full.stat().st_size if full.exists() else 0
        if p.startswith("docs/gallery/") and size > li.GALLERY_MAX_FILE_BYTES:
            problems.append(
                f"{p} が {human(size)} — 1 枚の上限 {human(li.GALLERY_MAX_FILE_BYTES)}"
                f" (docs/gallery/README.md)"
            )
    # 過去分の違反はここでは止めない。画像を触るコミットのときだけ 1 行知らせる。
    if imgs and not problems:
        legacy = subprocess.run(
            [sys.executable, str(ROOT / "bin" / "fge"), "images"],
            capture_output=True, cwd=ROOT,
        )
        if legacy.returncode != 0:
            print("[pre-commit] 注意: 過去から追跡されている絵に違反が残っています"
                  " (このコミットは止めません): python3 bin/fge images で一覧")
    return problems


def needs_docs_sync(staged):
    # docs/gallery/ の絵だけのコミットでは走らせない: 引き金は文章と規約の実体だけ。
    triggers = (".claude/", "agents-pack/", "templates/",
                "bin/gen-rules.py", "bin/gen-api-digest.py", "bin/check-api-index.py",
                "bin/check-refs.py")
    for p in staged:
        # Makefile は bin/・docs/ への参照を大量に持つ (check-refs の検査対象)。
        if p == "Makefile" or p.endswith("/Makefile"):
            return True
        if p.startswith(triggers) or p.endswith((".md", ".flix")):
            return True
    return False


def has_docs_sync_target():
    """make に check-docs-sync ターゲットが在るか。無い・make 自体が無いなら
    1 行知らせてスキップ (ゲートの都合でコミットを壊さない。fail-open)。"""
    try:
        # -q は実行せずに「ターゲットとして解決できるか」だけ見る (無ければ exit 2)
        probe = subprocess.run(["make", "-q", "check-docs-sync"],
                               cwd=ROOT, capture_output=True)
    except OSError:
        print("[pre-commit] make が見つからないので配線検査 (check-docs-sync) は飛ばします")
        return False
    if probe.returncode == 2:
        print("[pre-commit] make check-docs-sync が無いので配線検査は飛ばします")
        return False
    return True


def main():
    if len(sys.argv) > 2 and sys.argv[1] == "--files":
        staged = sys.argv[2:]
    else:
        staged = staged_files()
    if not staged:
        return 0

    failed = False
    li = load_lint_images()

    problems = check_staged_images(staged, li)
    if problems:
        failed = True
        print(f"[pre-commit] 画像 {len(problems)} 件:")
        for m in problems:
            print(f"  {m}")

    flix = [p for p in staged if p.endswith(".flix")]
    if flix:
        if run_lint("lint-view.py", "view", *flix) != 0:
            failed = True

    if any(p.endswith((".sprite.json", ".theme.json")) or "palette" in p
           for p in staged):
        if run_lint("lint-palette.py", "palette") != 0:
            failed = True

    ui = [p for p in staged if p.endswith(".ui.json")]
    if ui:
        if run_lint("lint-ui-overflow.py", "ui-overflow", "--strict", *ui) != 0:
            failed = True

    if flix:
        # 引数は渡さない: lint-fallback 自身がステージの + 行だけを読む (既存の bug! は叩かない)
        if run_lint("lint-fallback.py", "fallback") != 0:
            failed = True

    if any(p.startswith(("engine/src/", "engine_world/src/", "engine_tools/src/"))
           for p in flix):
        # 引数は渡さない: pub 面は宣言 1 つが複数ファイルに散らないので全量が速く、
        # 別のファイルの型を変えた巻き添えで pub 面へ Float32 が出た場合も拾える
        if run_lint("lint-f32.py", "f32") != 0:
            failed = True

    prose = [p for p in staged
             if p.endswith((".md", ".flix", ".elm", ".json", ".py"))
             or p == "Makefile" or p.endswith("/Makefile")]
    if prose:
        # 引数は渡さない: lint-jargon 自身がステージの + 行だけを読む (既存の行は叩かない)
        if run_lint("lint-jargon.py", "jargon") != 0:
            failed = True

    if needs_docs_sync(staged) and has_docs_sync_target():
        if run(["make", "-s", "check-docs-sync"]) != 0:
            failed = True

    if failed:
        print("[pre-commit] 止めました。直してから再コミット"
              " (どうしても通すなら git commit --no-verify)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
