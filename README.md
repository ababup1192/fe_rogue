# Flix Game Engine

A Godot-style scene-tree 2D game engine written in [Flix](https://flix.dev/).
Rendering, input, and audio are a from-scratch implementation on top of LWJGL
(OpenGL 3.3 Core / GLFW / OpenAL) — no Godot dependency.

The engine ships as a reusable library, with real games living under `examples/`,
in a monorepo layout. The recommended one is **fe_rogue** (a Fire Emblem-style
SRPG + roguelike).

> 日本語版は[下](#flix-game-engine-日本語)にあります。

## Requirements

- **devbox** (recommended — fetches JDK 21 + GNU make automatically)
- **JDK 21**
- **GNU make**
- Supported OS: macOS (Apple Silicon / Intel) / Windows x86_64
- Flix **0.73.0** compiler (`bin/flix.jar`) — download it yourself (see below)

## Setup

First, download the Flix 0.73.0 compiler and place it at `bin/flix.jar`:

```bash
curl -L -o bin/flix.jar https://github.com/flix/flix/releases/download/v0.73.0/flix.jar
```

Then set up the toolchain and build the engine packages:

```bash
devbox shell        # fetch JDK 21 + make, and add bin/ to PATH
make sync            # build-pkg engine_core / render_core / engine and distribute (via symlink) to examples & ide
```

Run `make sync` **once on first setup**. Each example resolves the engine through
a relative symlink under `lib/github/ababup1192/.../0.1.0/`, so without it the
dependency cannot be resolved. After editing the engine, re-run `make sync`
(or `make sync-engine`) to reflect changes immediately.

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
| **fe_rogue** | Fire Emblem-style turn-based SRPG + roguelike (recommended) |
| **flappy_bird** | Flappy Bird clone |
| **escape_game** | Yarn Spinner visual novel + scene editor |
| **dodge_the_creeps** | Dodge-the-enemies game (port of the Godot tutorial) |
| **command_battle** | Simple turn-based command battle |

Every example runs and tests the same way:

```bash
cd examples/<name>
flix run             # launch
flix test            # test
```

## Project layout (monorepo)

```
engine_core/   foundation package: pure types and computation (math, color, assets)
render_core/   OpenGL/OpenAL wrapper layer (depends on engine_core)
engine/        reusable library bundling scene tree, physics, input, audio (depends on render_core)
ide/           Swing + AWTGLCanvas scene editor (depends on engine)
examples/      individual games (depend on engine)
bin/           flix.jar and the flix wrapper script
```

Dependency chain: `engine_core → render_core → engine → (ide / examples)`.
`make sync` runs `build-pkg` on each package and distributes it to dependents via
relative symlinks (symlink, not cp — so rebuilding the engine is reflected instantly).

## Development tips

```bash
make sync-engine-core    # build-pkg & distribute engine_core only
make sync-render-core    # build-pkg & distribute render_core only
make sync-engine         # build-pkg & distribute engine only
make clean-locks         # remove stale *.lock left in the Maven cache by an interrupted flix check
make clean-example-builds # delete examples/*/build/ (speeds up IDE scene loading)
```

## Tech stack

- **Flix 0.73.0** — functional programming language
- **LWJGL** — OpenGL / GLFW / STB / OpenAL bindings
- **OpenGL 3.3 Core Profile** — shader-based 2D rendering
- **OpenAL** — sound effects and BGM playback

## License

[MIT License](LICENSE.md)

---

# Flix Game Engine (日本語)

[Flix](https://flix.dev/) で書く Godot 風シーンツリーの 2D ゲームエンジン。
描画・入力・音声は LWJGL（OpenGL 3.3 Core / GLFW / OpenAL）を直接叩く自前実装で、Godot には依存しない。

エンジンを再利用ライブラリとして提供し、`examples/` 配下に実際のゲームが並ぶ monorepo 構成。
おすすめは **fe_rogue**（ファイアーエムブレム風 SRPG + ローグライク）。

## 必要環境

- **devbox**（推奨。JDK 21 + GNU make を自動取得）
- **JDK 21**
- **GNU make**
- 対応 OS: macOS（Apple Silicon / Intel）/ Windows x86_64
- Flix **0.73.0** コンパイラ（`bin/flix.jar`）— 各自でダウンロードして配置する（下記参照）

## セットアップ

まず Flix 0.73.0 コンパイラをダウンロードして `bin/flix.jar` に配置する:

```bash
curl -L -o bin/flix.jar https://github.com/flix/flix/releases/download/v0.73.0/flix.jar
```

次にツールチェーンを用意し、エンジンパッケージをビルドする:

```bash
devbox shell        # JDK 21 + make を取得し、bin/ を PATH に追加
make sync            # engine_core / render_core / engine を build-pkg し、examples・ide へ symlink 配布
```

`make sync` は **初回に必ず一度実行する**。各 example はエンジンを
`lib/github/ababup1192/.../0.1.0/` への相対 symlink 経由で解決するため、これが無いと依存を解決できない。
エンジンを編集したら `make sync`（または `make sync-engine`）で即反映される。

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
| **fe_rogue** | FE 風ターン制 SRPG + ローグライク（おすすめ） |
| **flappy_bird** | Flappy Bird クローン |
| **escape_game** | Yarn Spinner ビジュアルノベル + シーンエディタ |
| **dodge_the_creeps** | 敵回避ゲーム（Godot チュートリアルの移植） |
| **command_battle** | シンプルなターン制コマンド戦闘 |

どの example も同じ手順で実行・テストできる:

```bash
cd examples/<name>
flix run             # 起動
flix test            # テスト
```

## プロジェクト構成（monorepo）

```
engine_core/   数学・色・アセットなど純粋な型と計算の土台パッケージ
render_core/   engine_core に依存する OpenGL/OpenAL ラッパレイヤ
engine/        シーンツリー・物理・入力・音声をまとめた再利用ライブラリ（render_core 依存）
ide/           Swing + AWTGLCanvas ベースのシーンエディタ（engine 依存）
examples/      各ゲーム（engine 依存）
bin/           flix.jar と flix ラッパスクリプト
```

依存チェーンは `engine_core → render_core → engine →（ide / examples）`。
`make sync` が各パッケージを `build-pkg` し、依存先へ相対 symlink で配布する
（cp ではなく symlink なので、エンジンを再ビルドすれば即座に反映される）。

## 開発 Tips

```bash
make sync-engine-core    # engine_core だけ build-pkg & 配布
make sync-render-core    # render_core だけ build-pkg & 配布
make sync-engine         # engine だけ build-pkg & 配布
make clean-locks         # flix check 中断で残った Maven cache の *.lock を削除
make clean-example-builds # examples/*/build/ を削除（IDE のシーン読み込み高速化用）
```

## 技術スタック

- **Flix 0.73.0** — 関数型プログラミング言語
- **LWJGL** — OpenGL / GLFW / STB / OpenAL バインディング
- **OpenGL 3.3 Core Profile** — シェーダーベースの 2D レンダリング
- **OpenAL** — 効果音・BGM 再生

## ライセンス

[MIT License](LICENSE.md)
