#!/usr/bin/env python3
"""音の名前が 3 つの置き場でそろっているかを検査するゲート。

音 1 つには名前の置き場が 3 つある:
  (a) 書き出し名  — src/render/ の SfxSynth.renderSet に書くタプルの左側 (生成する WAV のファイル名になる)
  (b) project.json — sounds の "name" (ゲームから鳴らすときの論理名) と "path" (WAV の場所)
  (c) コード内リテラル — AudioStreamPlayer.play("x") や withAudio が返す "x"
この 3 つがずれると、エラーは出ないのに音だけ鳴らない・別の音が鳴る。
名前は 1 本にそろえる (論理名 = WAV ファイル名の茎 = 書き出し名)。

検査 (1 つでも NG なら終了コード 1):
  1. sounds の論理名と path のファイル名の茎が違う
  2. sounds の path の WAV が無く、書き出しでも作られない (鳴らせない)
  3. 書き出しで作る WAV がどの sounds の path からも参照されない (生成するだけで鳴らせない)
  4. 再生呼び出し (AudioStreamPlayer.* / GameEngine.Audio.*) のリテラルが sounds に無い
注意 (止めない):
  5. sounds の論理名がコードのどこにも文字列リテラルとして現れない
     (動的に組む名前 — "talk_" + 高さ など — は検出できないため、止めずに知らせるだけ)

使い方: python3 bin/lint-audio.py [ルート]   (既定のルートはこのファイルの親の親)
"""

import json
import os
import re
import sys

EXCLUDED_DIRS = {"build", "lib", ".git", "gallery", ".devbox", "node_modules"}

GAME_ROOTS = ("templates",)

# 音名を直接受け取る再生系呼び出し。第 1 引数の文字列リテラルを「使っている名前」として集める。
CALL_RE = re.compile(
    r'(?:AudioStreamPlayer|GameEngine\.Audio|Audio)\.'
    r'(?:play|stop|playAudio|stopAudio|setVolume|setPitch|setLooping)\(\s*"([^"]+)"'
)

SFX_TUPLE_RE = re.compile(r'\(\s*"([^"]+)"\s*,')
SFX_DIR_RE = re.compile(r'renderSet\([^)"]*"([^"]+)"')


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def flix_files(game_dir):
    """src/ 配下の .flix を (相対パス, 本文) で集める。"""
    found = []
    src = os.path.join(game_dir, "src")
    for current, dirs, files in os.walk(src):
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED_DIRS)
        for name in sorted(files):
            if name.endswith(".flix"):
                full = os.path.join(current, name)
                found.append((os.path.relpath(full, game_dir), read_text(full)))
    return found


def rendered_paths_of(files):
    """renderSet が生成する WAV の game_dir 相対パス (dir/name.wav) を集める。"""
    rendered = set()
    for _, text in files:
        if "renderSet" not in text:
            continue
        tail = text[text.index("renderSet"):]
        dir_match = SFX_DIR_RE.search(tail)
        out_dir = dir_match.group(1) if dir_match else "assets/sfx"
        for name in SFX_TUPLE_RE.findall(tail):
            rendered.add(f"{out_dir}/{name}.wav")
    return rendered


def is_render_file(rel):
    return f"{os.sep}render{os.sep}" in rel or rel.startswith(f"src{os.sep}render{os.sep}")


def check_game(root, game, problems, warnings):
    """1 ゲームぶんの突き合わせ。sounds が無ければ 0 件として素通り。"""
    game_dir = os.path.join(root, game)
    project = read_json(os.path.join(game_dir, "project.json"))
    sounds = project.get("sounds") if isinstance(project, dict) else None
    if not isinstance(sounds, list):
        return 0

    files = flix_files(game_dir)
    game_files = [(rel, text) for rel, text in files if not is_render_file(rel)]
    rendered = rendered_paths_of(files)
    declared = {}
    for entry in sounds:
        if not isinstance(entry, dict):
            continue
        name, path = entry.get("name"), entry.get("path")
        if not isinstance(name, str) or not isinstance(path, str):
            continue
        declared[name] = path
        stem = os.path.splitext(os.path.basename(path))[0]
        if stem != name:
            problems.append(
                f'{game}/project.json: 論理名 "{name}" と WAV の茎 "{stem}" が違う'
                f" (path={path}。名前は 1 本にそろえる)")
        if not os.path.isfile(os.path.join(game_dir, path)) and path not in rendered:
            problems.append(
                f'{game}/project.json: "{name}" の {path} が無く、書き出しでも作られない')

    declared_paths = set(declared.values())
    for path in sorted(rendered):
        if path not in declared_paths:
            problems.append(
                f"{game}: 書き出しが作る {path} がどの sounds の path からも参照されない")

    for rel, text in game_files:
        for name in CALL_RE.findall(text):
            if name not in declared:
                problems.append(
                    f'{game}/{rel}: 再生呼び出しの "{name}" が project.json の sounds に無い')

    all_code = "\n".join(text for _, text in game_files)
    for name in sorted(declared):
        if f'"{name}"' not in all_code:
            warnings.append(
                f'{game}: 論理名 "{name}" がコードのどこにもリテラルで現れない'
                " (動的に組んでいるなら無視してよい)")
    return len(declared)


def game_dirs(root):
    dirs = []
    for group in GAME_ROOTS:
        group_dir = os.path.join(root, group)
        if not os.path.isdir(group_dir):
            continue
        for name in sorted(os.listdir(group_dir)):
            rel = f"{group}/{name}"
            if not os.path.isdir(os.path.join(root, rel)):
                continue
            dirs.append(rel)
    # 生成されたゲームには templates/ が無い。空を返すと
    # 「検査したが問題なし」と見分けが付かず、ゲートが何も言わずに通してしまう。
    if not dirs and os.path.isfile(os.path.join(root, "project.json")):
        dirs.append(".")
    return dirs


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    problems = []
    warnings = []
    sound_count = 0
    for game in game_dirs(root):
        sound_count += check_game(root, game, problems, warnings)

    for line in warnings:
        print(f"注意: {line}")
    if problems:
        for line in problems:
            print(line)
        print(f"NG: {len(problems)} 個の音名のずれ (sounds {sound_count} 件を検査)")
        return 1
    print(f"OK: sounds {sound_count} 件すべて 3 つの置き場 (書き出し名 / project.json / コード) でそろっている")
    return 0


if __name__ == "__main__":
    sys.exit(main())
