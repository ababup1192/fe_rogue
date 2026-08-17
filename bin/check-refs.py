#!/usr/bin/env python3
"""参照の存在検査 — 「文章や Makefile が指す先が実在するか」を機械が照らす。

wiz_lick の骨組みセッションで、リリースバンドルから bin/gen-api-digest.py・docs/ 一式・
reference-*.sh が漏れて、Makefile とテンプレの参照が宙に浮いた (誰も気づかず、エージェント
はソース unzip に戻った)。参照と実体のずれは人任せの目視では見つからないので、
コミット時 (check-docs-sync 経由) とリリース作成時に必ずここを通す。

検査は 4 面 + バンドル:
  1. engine Makefile が書く bin/* ・ docs/* が実在するか
  2. templates/*/Makefile と mk/*.mk の $(ENGINE)/bin/* ・ $(ENGINE)/docs/* が engine に実在するか。
     ゲーム側 bin/* の参照は sync-agents の配布リスト (Makefile の cp 行) に載っているか
  3. agents-pack/AGENTS.core.md・settings.json が存在を前提とするパス
     (rules・bin のツール・engine docs・フック) が実在し、配布リストに載っているか
  4. templates/*/ が 1 本ずつ複製元として成り立つか (Makefile・flix.toml・project.json・
     src の .flix・reference/title.png)。バンドルでも同じ物差しを当てる

  python3 bin/check-refs.py                 # リポ自身を検査 (check-docs-sync が呼ぶ)
  python3 bin/check-refs.py --bundle DIR    # ステージ済みバンドル DIR に必須物が揃っているか
                                            # (Studio の stage-engine 後に呼ぶ想定)
  python3 bin/check-refs.py --bundle DIR --windows   # 同上。bash 前提の物だけ免除する

バンドルの必須物一覧 BUNDLE_REQUIRED はここが唯一の実体。同梱物を増やしたら
この一覧と Studio 側 stage-engine の cp を一緒に更新する。

標準ライブラリだけで動く (Windows / macOS / Linux 共通)。
"""

import glob
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# バンドル (Studio 同梱 engine/) に必ず入っている物。「走らせる手」に加えて、
# AGENTS.core.md・テンプレ Makefile・api ダイジェストが参照する先を全部含む。
# flix.jar / lib は Studio 側が別経路で足すのでここでは見ない。
BUNDLE_REQUIRED = [
    "Makefile",
    "flix.toml",
    "bin/flix",
    "bin/checkd",
    "bin/explain-error",
    "bin/gen-api-digest.py",
    "bin/reference-update.sh",
    "bin/reference-check.sh",
    # 絵の値段の判定。reference-check.sh と status.py が $(ENGINE)/bin/ から呼ぶ。
    # どちらも「無ければ飛ばす」で fail-open するので、同梱し忘れると判定が黙って消える。
    "bin/check-render-budget.py",
    # ゲームの Makefile が include する共通部。バンドルから漏れると include ごと
    # 落ち、make は「そんなファイルは無い」としか言わない — run も status も
    # 打てなくなる（テンプレ側の $(error) ガードが直し方を出すが、Studio 同梱では
    # 直しようが無い）。
    "mk/game.mk",
    "bin/img-digest.py",
    "bin/status.py",
    "bin/lint-view.py",
    "bin/lint-palette.py",
    "bin/lint-sprite.py",
    "bin/lint-anim.py",
    "bin/lint-audio.py",
    "bin/lint-images.py",
    "bin/lint-ui-overflow.py",
    "bin/precommit.py",
    "bin/githooks/pre-commit",
    "bin/sync-agents.py",
    # 3 面図から歩きを彫り出す道具。carve-sprite スキルは全ゲームへ配られ、
    # その手順が $(ENGINE)/bin/carve/carve.py を直に叩く。スキルだけ届いて
    # 道具が届かないと、実行して初めて「ファイルが無い」で気づく。
    "bin/carve/carve.py",
    "docs/api-digest.md",
    "docs/api-digest/engine.md",
    "docs/api-digest/engine_world.md",
    "docs/api-digest/engine_tools.md",
    "docs/module-index.md",
    "docs/engine-module-index.md",
    "docs/doc-conventions.md",
    "docs/glossary.md",
    "docs/shader-doc.md",
    "docs/checkd.md",
    ".claude/hooks/after-flix-edit.py",
    ".claude/hooks/session-diet.py",
    "agents-pack/AGENTS.core.md",
    "agents-pack/settings.json",
    "agents-pack/manifest.json",
    "agents-pack/codex-hooks.json",
    "agents-pack/rules/drawing.md",
    "agents-pack/rules/flix.md",
    "templates/game-starter/Makefile",
    "engine_full/flix.toml",
    "engine_full/artifact/engine_full.fpkg",
]

# Windows 版の zip にだけ入らない物と、その代わりに要る物。
# bin/flix は同梱 JRE と隣の flix.jar を呼ぶ bash のラッパで、Windows では走らない。
# あちらは mk/game.mk が java と bin/flix.jar を直に叩くので、jar の方を必須にする。
# reference-*.sh も bash 前提 (絵の焼き直しは Windows では打てない、が今の割り切り)。
BUNDLE_SKIP_ON_WINDOWS = {"bin/flix", "bin/reference-update.sh", "bin/reference-check.sh"}
BUNDLE_WINDOWS_EXTRA = ["bin/flix.jar"]

# 文章・Makefile から拾うパス片。変数展開やプレースホルダ入りは照合しない。
PATH_RE = re.compile(r"(?<![\w$.:/-])(bin|docs)/[A-Za-z0-9_*/.-]+")
SKIP_MARKS = ("$(", "__", "...", "<", ">")


def extract_paths(text):
    found = set()
    for m in PATH_RE.finditer(text):
        tok = m.group(0).rstrip(".,;:)'\"`")
        if any(s in tok for s in SKIP_MARKS):
            continue
        found.add(tok)
    return found


def exists_in(base: Path, rel: str) -> bool:
    if "*" in rel:
        return bool(glob.glob(str(base / rel)))
    return (base / rel).exists()


def strip_mk_comments(text):
    """# 以降の説明文と、echo/printf の文字列の中身を落とす。

    どちらも人向けの文章で、「docs/ と AGENTS.md に残っていないか」のような
    パス風の言い回しをパスと誤認する。実行される参照は recipe の残りにだけある。
    既知の制限: クォートの入れ子・複数行に割れた文字列までは追わない
    (誤検出したら文言の方を軽く直すのも可)。
    """
    out = []
    for ln in text.splitlines():
        ln = re.sub(r"(^|\s)@?#.*$", r"\1", ln)
        ln = re.sub(r"""\b(echo|printf)\s+("[^"]*"|'[^']*')""", r"\1 ''", ln)
        out.append(ln)
    return "\n".join(out)


def sync_agents_dist():
    """sync-agents が実際にゲームへ配るパスの集合を返す。

    配布リストの source of truth は agents-pack/manifest.json (Makefile と Studio の両実装が
    読む唯一の実体)。src と dst の両方と、dst の親フォルダ (bin/githooks のような
    「フォルダを指す参照」も配布済み扱いにする) を照合先に入れる。"""
    import json
    dist = set()
    try:
        with open(ROOT / "agents-pack" / "manifest.json", encoding="utf-8") as fh:
            m = json.load(fh)
    except (OSError, ValueError):
        return dist
    for key in ("copy", "copyIfAbsent", "copyDirs"):
        for e in m.get(key, []):
            for rel in (e.get("src", ""), e.get("dst", "")):
                if not rel:
                    continue
                dist.add(rel)
                parent = re.sub(r"/[^/]+$", "", rel)
                while "/" in parent:
                    dist.add(parent)
                    parent = re.sub(r"/[^/]+$", "", parent)
    return dist


def check_makefile(problems):
    raw = (ROOT / "Makefile").read_text(encoding="utf-8")
    text = strip_mk_comments(raw)
    for rel in sorted(extract_paths(text)):
        if not exists_in(ROOT, rel):
            problems.append("Makefile: {} が実在しません".format(rel))
    dist = sync_agents_dist()
    if not dist:
        problems.append(
            "agents-pack/manifest.json が読み取れません"
            " (配布リストの照合ができない — 形を変えたなら"
            " bin/check-refs.py の sync_agents_dist を追随)")
    return dist


def check_templates(problems, dist):
    targets = sorted(ROOT.glob("templates/*/Makefile")) + sorted(ROOT.glob("mk/*.mk"))
    for mk in targets:
        text = strip_mk_comments(mk.read_text(encoding="utf-8"))
        rel_mk = mk.relative_to(ROOT).as_posix()
        # $(ENGINE)/bin/... や $(ENGINE)/docs/... は engine リポの実体を指す。
        for m in re.finditer(r"\$\(ENGINE\)/((?:bin|docs)/[A-Za-z0-9_*/.-]+)", text):
            rel = m.group(1).rstrip(".,;:)'\"`")
            # bin/flix.jar は Windows 経路の手動配置（Studio 同梱 JRE が直接叩く）。
            # macOS/Linux は nix の jar を bin/flix ラッパが解決するので、
            # engine に実体が無いのが正常。
            if rel == "bin/flix.jar":
                continue
            if not exists_in(ROOT, rel):
                problems.append("{}: $(ENGINE)/{} が engine に実在しません".format(rel_mk, rel))
        # ゲーム側 bin/* の参照は new-game 時に sync-agents が配る。配布リスト
        # (engine Makefile の cp 行) に無い物を参照すると、産まれたゲームで転ぶ。
        for rel in sorted(extract_paths(text)):
            if not rel.startswith("bin/"):
                continue
            if not exists_in(ROOT, rel):
                problems.append("{}: {} が engine に実在しません".format(rel_mk, rel))
            elif rel not in ("bin/flix", "bin/flix.jar") and rel not in dist:
                problems.append(
                    "{}: {} は sync-agents の配布リスト (engine Makefile の cp 行) に"
                    "見当たりません — 産まれたゲームに配られず参照が宙に浮きます".format(rel_mk, rel))


def check_agents_pack(problems, dist):
    core = ROOT / "agents-pack" / "AGENTS.core.md"
    text = core.read_text(encoding="utf-8")
    rel_core = core.relative_to(ROOT).as_posix()
    for rel in sorted(extract_paths(text)):
        if rel.startswith("docs/"):
            # 「engine リポの docs/...」の決まり。バンドル欠損の主犯だった参照。
            if not exists_in(ROOT, rel):
                problems.append("{}: {} が engine に実在しません".format(rel_core, rel))
        elif rel.startswith("bin/"):
            if not exists_in(ROOT, rel):
                problems.append("{}: {} が engine に実在しません".format(rel_core, rel))
            elif rel not in dist:
                problems.append(
                    "{}: {} が sync-agents の配布リスト (cp 行) に"
                    "見当たりません".format(rel_core, rel))
    # rules の決まり (.claude/rules/xxx.md) は agents-pack/rules が実体。
    for m in re.finditer(r"\.claude/rules/([A-Za-z0-9_-]+\.md)", text):
        if not (ROOT / "agents-pack" / "rules" / m.group(1)).exists():
            problems.append(
                "{}: .claude/rules/{} の実体が agents-pack/rules にありません".format(
                    rel_core, m.group(1)))
    # settings.json の決まりと、そのフックの実体。
    settings = ROOT / "agents-pack" / "settings.json"
    if ".claude/settings.json" in text and not settings.exists():
        problems.append("{}: agents-pack/settings.json がありません".format(rel_core))
    if settings.exists():
        for m in re.finditer(r"\.claude/hooks/([A-Za-z0-9_.-]+\.py)",
                             settings.read_text(encoding="utf-8")):
            hook = ".claude/hooks/" + m.group(1)
            if not (ROOT / hook).exists():
                problems.append("agents-pack/settings.json: {} が実在しません".format(hook))
            elif hook not in dist:
                problems.append(
                    "agents-pack/settings.json: {} が sync-agents の配布リスト (cp 行) に"
                    "見当たりません".format(hook))


# テンプレ 1 本が複製元として成り立つのに要る物。数え上げた templates/*/ の全部に当てるので、
# テンプレを足すときにこの一覧を足す必要は無い (足し忘れが無言で通るのを防ぐのが狙い)。
TEMPLATE_REQUIRED = ["Makefile", "flix.toml", "project.json", "reference/title.png"]


def check_templates_shape(problems, base: Path, label: str):
    """base/templates/*/ の 1 本ずつが複製元として成り立つかを見る。

    new-game はテンプレを丸ごと写すだけなので、欠けた物はゲームが生まれた後に
    初めて分かる (make が include で落ちる・Studio のジャンルカードが顔無しになる)。
    """
    dirs = sorted(p for p in (base / "templates").glob("*") if p.is_dir())
    if not dirs:
        problems.append("{}: templates/ にテンプレが 1 本もありません".format(label))
        return dirs
    for d in dirs:
        name = d.name
        for rel in TEMPLATE_REQUIRED:
            if not (d / rel).exists():
                problems.append("{}: templates/{}/{} がありません".format(label, name, rel))
        if not list(d.glob("src/*.flix")):
            problems.append("{}: templates/{}/src に .flix がありません".format(label, name))
    return dirs


GENESIS_STARTER_RE = re.compile(r'starter\s*=\s*"([^"]*)"')


def find_genesis(base: Path):
    """バンドルの置き場所から Studio の Genesis.flix を探す (見つからなければ None)。

    バンドルは Studio の中の深い所 (app/src-tauri/resources/engine) に作られるが、
    段数を直に書くと Studio 側の置き場所が変わった日に黙って検査が消える。
    server/src/Genesis.flix を目印に親を遡る。
    """
    for parent in [base] + list(base.parents)[:6]:
        cand = parent / "server" / "src" / "Genesis.flix"
        if cand.is_file():
            return cand
    return None


def check_genesis_starters(problems, base: Path, template_dirs):
    """Studio のジャンルカードの starter と、同梱テンプレの集合を両方向で突き合わせる。

    片方向だけだと、Genesis に無いテンプレ (Studio から一生選べない) も、
    テンプレの無い starter (選んだ瞬間に複製が転ぶ) も、どちらも無言で通る。
    """
    genesis = find_genesis(base)
    if genesis is None:
        print("[check-refs] Genesis 対照は飛ばしました (Studio の外のバンドル)")
        return
    text = genesis.read_text(encoding="utf-8")
    declared = {m.group(1) for m in GENESIS_STARTER_RE.finditer(text) if m.group(1)}
    present = {"templates/" + d.name for d in template_dirs}
    if declared == present:
        print("[check-refs] Genesis 対照 OK: starter {} 件 = テンプレ {} 本 ({})".format(
            len(declared), len(present), genesis))
        return
    for rel in sorted(declared - present):
        problems.append(
            "{}: starter = \"{}\" のテンプレがバンドルにありません"
            " (Studio でそのジャンルを選ぶと複製が転びます)".format(genesis, rel))
    for rel in sorted(present - declared):
        problems.append(
            "{}: {} がどのジャンルの starter にもなっていません"
            " (Studio から選べないテンプレです)".format(genesis, rel))


def hooks_in_settings(base: Path):
    """base/agents-pack/settings.json が名指しするフックの実体パス。読めなければ空。"""
    try:
        text = (base / "agents-pack" / "settings.json").read_text(encoding="utf-8")
    except OSError:
        return []
    return sorted({".claude/hooks/" + m.group(1)
                   for m in re.finditer(r"\.claude/hooks/([A-Za-z0-9_.-]+\.py)", text)})


def check_bundle_manifest(problems):
    """BUNDLE_REQUIRED 自身の書き損じ (リポに無い物を必須と言う) を止める。"""
    for rel in BUNDLE_REQUIRED:
        if not exists_in(ROOT, rel):
            problems.append(
                "BUNDLE_REQUIRED: {} がこのリポにありません (一覧の書き損じ?)".format(rel))


def check_bundle(bundle_dir, windows=False):
    base = Path(bundle_dir)
    if not base.is_dir():
        print("バンドルが見つかりません: {}".format(bundle_dir), file=sys.stderr)
        return 1
    required = [r for r in BUNDLE_REQUIRED if not (windows and r in BUNDLE_SKIP_ON_WINDOWS)]
    if windows:
        required += BUNDLE_WINDOWS_EXTRA
    # フックの実体は settings.json が名指しする分だけ要る。手書きの一覧に足すのを
    # 忘れると、産まれたゲームに「呼ぶ先の無いフック」が付き、走らせるまで気づかない。
    # 一覧を減らす向きには効かない (導出したぶんを足すだけ)。
    required += [rel for rel in hooks_in_settings(base) if rel not in required]
    missing = [rel for rel in required if not exists_in(base, rel)]
    if missing:
        print("[check-refs] バンドル欠損 {} 件 ({}):".format(len(missing), bundle_dir),
              file=sys.stderr)
        for rel in missing:
            print("  {}".format(rel), file=sys.stderr)
        print("同梱リスト (Studio の stage-engine) に cp を足してください。"
              "必須一覧は bin/check-refs.py の BUNDLE_REQUIRED。", file=sys.stderr)
        return 1
    problems = []
    dirs = check_templates_shape(problems, base, bundle_dir)
    check_genesis_starters(problems, base, dirs)
    if problems:
        for p in problems:
            print(p, file=sys.stderr)
        return 1
    print("OK: バンドルに必須 {} 点が揃っています ({}{}・テンプレ {} 本)".format(
        len(required), bundle_dir, " / Windows" if windows else "", len(dirs)))
    return 0


def main(argv):
    if "--bundle" in argv:
        i = argv.index("--bundle")
        if i + 1 >= len(argv):
            print("usage: check-refs.py --bundle DIR [--windows]", file=sys.stderr)
            return 2
        return check_bundle(argv[i + 1], windows="--windows" in argv)

    problems = []
    dist = check_makefile(problems)
    check_templates(problems, dist)
    check_agents_pack(problems, dist)
    check_templates_shape(problems, ROOT, "engine")
    check_bundle_manifest(problems)

    if problems:
        for p in problems:
            print(p, file=sys.stderr)
        print("\n参照した先を実在させるか、参照の方を直してください。", file=sys.stderr)
        return 1
    print("OK: Makefile / templates / agents-pack の参照は全て実在します")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
