# Flix Game Engine

A 2D game engine written in [Flix](https://flix.dev/). Games are built around
a single immutable `World` value: systems are pure functions run each frame by
a Bevy-style `App`, and every frame is rendered from the `World`. Rendering,
input, and audio are a from-scratch implementation on top of LWJGL
(OpenGL 3.3 Core / GLFW / OpenAL).

The engine ships as a reusable library, with real games living under `examples/`,
in a monorepo layout. The recommended one is **fe_rogue** (a Fire Emblem-style
SRPG + roguelike).

> 日本語版は[下](#flix-game-engine-日本語)にあります。

## Requirements

- **devbox** (recommended — fetches JDK 21 + GNU make automatically)
- **JDK 21**
- **GNU make**
- Supported OS: macOS (Apple Silicon / Intel) / Windows x86_64
- Flix **0.75.1** compiler (`bin/flix.jar`) — download it yourself (see below)

## Setup

First, download the Flix 0.75.1 compiler and place it at `bin/flix.jar`:

```bash
curl -L -o bin/flix.jar https://github.com/flix/flix/releases/download/v0.75.1/flix.jar
```

Then set up the toolchain and build the engine packages:

```bash
devbox shell        # fetch JDK 21 + make, and add bin/ to PATH
make sync            # build-pkg all engine packages and distribute (via symlink) to examples & ide
```

Run `make sync` **once on first setup**. Each example resolves the engine through
a relative symlink under `lib/github/ababup1192/.../0.1.0/`, so without it the
dependency cannot be resolved. After editing an engine package, re-run `make sync`
(or the per-package `sync-*` targets; note that `engine_world` / `engine_tools`
build on `engine`, so re-sync them too after editing `engine`).

```bash
make help            # list other targets (sync-engine, etc.)
```

## Recommended game: play fe_rogue

A Fire Emblem-style turn-based strategy RPG (SRPG) with roguelike elements.

- Progress through dungeon floors (move between floors via stairs)
- Player turn → enemy turn cycle, with enemy AI acting automatically
- Equip/use units, weapons, and staves (magic); battle forecast (hit rate / predicted damage)
- Experience and level-ups, consumable items such as potions

### Run

```bash
devbox shell
make sync                 # first time only
cd examples/fe_rogue
flix run                  # bin/flix wrapper (adds -XstartOnFirstThread automatically on macOS)
```

### Controls

| Action | Keyboard | Gamepad (Xbox layout) |
|---|---|---|
| Move cursor | Arrow keys | D-pad / left stick |
| Confirm (move / attack / menu select) | Z | A |
| Menu confirm | Enter | Start |
| Cancel / back | X | B |
| Minimap | M | Y |
| Toggle danger range | Shift | LB |

> Esc is intentionally unmapped, since it triggers quitting the game on the map.

### Packaging for distribution

See [`examples/fe_rogue/DISTRIBUTION.md`](examples/fe_rogue/DISTRIBUTION.md) for
building a JRE-bundled `.dmg` / `.exe` or a jar + launcher.

## Other examples

| Game | Description |
|---|---|
| **breakout** | Breakout clone — the value-based entry tutorial (start here; see its README) |
| **sokoban** | Sokoban with unlimited undo (Worldline) — has a full build-it-yourself TUTORIAL (EN/JA) |
| **fe_rogue** | Fire Emblem-style turn-based SRPG + roguelike (recommended) |
| **liars_room** | Liar logic puzzle — every stage is machine-proven solvable (Datalog) |
| **nobi_patissier** | Pâtissier game (work in progress) |

Every example runs and tests the same way:

```bash
cd examples/<name>
flix run             # launch
flix test            # test
```

## Project layout (monorepo)

```
engine_core/   foundation package: pure types and computation (math, color, text layout, project loading)
render_core/   OpenGL/OpenAL wrapper layer: shaders, textures, SDF fonts, audio (depends on engine_core)
engine/        runtime shell: main loop, LWJGL window/input/audio handlers, asset loading, save data (depends on render_core)
engine_world/  value-based game framework: Bevy-style App, ECS queries, physics, UI widgets, camera rig, Worldline undo/replay (depends on engine)
engine_tools/  dev & test tooling: headless software rasterizer, filmstrip/GIF baking, snapshot viewer, render lint, SFX synth (depends on engine)
ide/           Swing + AWTGLCanvas editor (depends on engine)
examples/      individual games (depend on engine, engine_world, engine_tools)
bin/           flix.jar and the flix wrapper script
flix.toml
src/           root project for the Flix community build: per-file symlinks bundling
               all engine packages into one source tree (regenerate with make sync-root-src)
```

Dependency chain: `engine_core → render_core → engine → (engine_world / engine_tools) → examples`,
with `ide` sitting on `engine`.
`make sync` runs `build-pkg` on each package and distributes it to dependents via
relative symlinks (symlink, not cp — so rebuilding the engine is reflected instantly).

## Development tips

```bash
make sync-engine-core    # build-pkg & distribute engine_core only
make sync-render-core    # build-pkg & distribute render_core only
make sync-engine         # build-pkg & distribute engine only
make sync-engine-world   # build-pkg & distribute engine_world only
make sync-engine-tools   # build-pkg & distribute engine_tools only
make sync-root-src       # regenerate the root src/ symlinks for the Flix community build
make clean-locks         # remove stale *.lock left in the Maven cache by an interrupted flix check
make clean-example-builds # delete examples/*/build/ (speeds up IDE scene loading)
```

## Tech stack

- **Flix 0.75.1** — functional programming language
- **LWJGL** — OpenGL / GLFW / STB / OpenAL bindings
- **OpenGL 3.3 Core Profile** — shader-based 2D rendering
- **OpenAL** — sound effects and BGM playback

## License

[MIT License](LICENSE.md)

---

# Flix Game Engine (日本語)

[Flix](https://flix.dev/) で書く 2D ゲームエンジン。ゲームは不変の `World` 値を中心に組み立てる:
システムは Bevy 風 `App` が毎フレーム実行する純粋関数で、各フレームは `World` から描画を導出する。
描画・入力・音声は LWJGL（OpenGL 3.3 Core / GLFW / OpenAL）を直接叩く自前実装。

エンジンを再利用ライブラリとして提供し、`examples/` 配下に実際のゲームが並ぶ monorepo 構成。
おすすめは **fe_rogue**（ファイアーエムブレム風 SRPG + ローグライク）。

## 必要環境

- **devbox**（推奨。JDK 21 + GNU make を自動取得）
- **JDK 21**
- **GNU make**
- 対応 OS: macOS（Apple Silicon / Intel）/ Windows x86_64
- Flix **0.75.1** コンパイラ（`bin/flix.jar`）— 各自でダウンロードして配置する（下記参照）

## セットアップ

まず Flix 0.75.1 コンパイラをダウンロードして `bin/flix.jar` に配置する:

```bash
curl -L -o bin/flix.jar https://github.com/flix/flix/releases/download/v0.75.1/flix.jar
```

次にツールチェーンを用意し、エンジンパッケージをビルドする:

```bash
devbox shell        # JDK 21 + make を取得し、bin/ を PATH に追加
make sync            # 全エンジンパッケージを build-pkg し、examples・ide へ symlink 配布
```

`make sync` は **初回に必ず一度実行する**。各 example はエンジンを
`lib/github/ababup1192/.../0.1.0/` への相対 symlink 経由で解決するため、これが無いと依存を解決できない。
エンジンパッケージを編集したら `make sync`（またはパッケージ別の `sync-*` ターゲット。
`engine_world` / `engine_tools` は `engine` の上に載るので、`engine` 編集後はそれらも再 sync する）で反映する。

```bash
make help            # 他ターゲット（sync-engine など）を一覧表示
```

## おすすめゲーム: fe_rogue を遊ぶ

ファイアーエムブレム風のターン制シミュレーション RPG（SRPG）＋ローグライク。

- ダンジョン階層を進行（階段でフロア移動）
- プレイヤーターン → 敵ターンのサイクル、敵 AI が自動行動
- ユニット／武器／杖（魔法）の装備・使用、戦闘予報（命中率・予想ダメージ）
- 経験値・レベルアップ、ポーション等の消費アイテム

### 実行

```bash
devbox shell
make sync                 # 初回のみ
cd examples/fe_rogue
flix run                  # bin/flix ラッパ（macOS では -XstartOnFirstThread を自動付与）
```

### 操作方法

| 操作 | キーボード | ゲームパッド（Xbox 配列） |
|---|---|---|
| カーソル移動 | 矢印キー | D-pad / 左スティック |
| 決定（移動確定・攻撃・メニュー選択） | Z | A |
| メニュー確定 | Enter | Start |
| キャンセル / 戻る | X | B |
| ミニマップ | M | Y |
| 危険範囲トグル | Shift | LB |

> Esc はマップ上でゲーム終了を誘発するため、操作には割り当てていない。

### 配布パッケージ化

JRE 同梱の `.dmg` / `.exe` や jar + ランチャの作り方は
[`examples/fe_rogue/DISTRIBUTION.md`](examples/fe_rogue/DISTRIBUTION.md) を参照。

## その他の examples

| ゲーム | 内容 |
|---|---|
| **breakout** | ブロック崩し — 値ベースの入口教材（最初に読むならこれ。README あり） |
| **sokoban** | 無制限アンドゥ（Worldline）の倉庫番 — 組み立て式 TUTORIAL 英日つき |
| **fe_rogue** | FE 風ターン制 SRPG + ローグライク（おすすめ） |
| **liars_room** | 嘘つき論理パズル — 全ステージ機械証明済み（Datalog） |
| **nobi_patissier** | パティシエゲーム（制作中） |

どの example も同じ手順で実行・テストできる:

```bash
cd examples/<name>
flix run             # 起動
flix test            # テスト
```

## プロジェクト構成（monorepo）

```
engine_core/   数学・色・テキストレイアウト・プロジェクト読み込みなど純粋な型と計算の土台パッケージ
render_core/   OpenGL/OpenAL ラッパレイヤ: シェーダ・テクスチャ・SDF フォント・音声（engine_core 依存）
engine/        ランタイムの殻: メインループ・LWJGL の窓/入力/音声ハンドラ・アセット読み込み・セーブデータ（render_core 依存）
engine_world/  値ベースのゲームフレームワーク: Bevy 風 App・ECS クエリ・物理・UI 部品・カメラリグ・Worldline undo/リプレイ（engine 依存）
engine_tools/  開発・テスト用ツール: headless ソフトラスタライザ・コマ撮り/GIF bake・スナップショットビューア・RenderLint・効果音合成（engine 依存）
ide/           Swing + AWTGLCanvas ベースのエディタ（engine 依存）
examples/      各ゲーム（engine・engine_world・engine_tools 依存）
bin/           flix.jar と flix ラッパスクリプト
flix.toml
src/           Flix コミュニティビルド用のルートプロジェクト: 全エンジンパッケージを
               1 ソースツリーに束ねるファイル単位 symlink 集（make sync-root-src で再生成）
```

依存チェーンは `engine_core → render_core → engine →（engine_world / engine_tools）→ examples`、
`ide` は `engine` の上に載る。
`make sync` が各パッケージを `build-pkg` し、依存先へ相対 symlink で配布する
（cp ではなく symlink なので、エンジンを再ビルドすれば即座に反映される）。

## 開発 Tips

```bash
make sync-engine-core    # engine_core だけ build-pkg & 配布
make sync-render-core    # render_core だけ build-pkg & 配布
make sync-engine         # engine だけ build-pkg & 配布
make sync-engine-world   # engine_world だけ build-pkg & 配布
make sync-engine-tools   # engine_tools だけ build-pkg & 配布
make sync-root-src       # コミュニティビルド用ルート src/ symlink 集を再生成
make clean-locks         # flix check 中断で残った Maven cache の *.lock を削除
make clean-example-builds # examples/*/build/ を削除（IDE のシーン読み込み高速化用）
```

## 技術スタック

- **Flix 0.75.1** — 関数型プログラミング言語
- **LWJGL** — OpenGL / GLFW / STB / OpenAL バインディング
- **OpenGL 3.3 Core Profile** — シェーダーベースの 2D レンダリング
- **OpenAL** — 効果音・BGM 再生

## ライセンス

[MIT License](LICENSE.md)
