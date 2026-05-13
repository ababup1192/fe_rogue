# Yarn Spinner Plugin

Flix で実装した [Yarn Spinner](https://www.yarnspinner.dev/) ランタイム + ビジュアルエディタ。`.yarn` 台本を `ysc` でコンパイルし、自前 VM で実行して LWJGL 上に対話 UI を描画する。Godot 風のシーンツリーを Flix + LWJGL で再現したエンジン層の上に乗っている。

## 必要環境

- devbox（推奨）
- JDK 21
- .NET SDK 9（`ysc` 用、devbox が自動で入れる）
- macOS (Apple Silicon / Intel) / Windows x86_64

## セットアップ

`devbox shell` に入った時点で初回のみ `yarn/.bin/ysc` が自動ビルドされる（[YarnSpinner-Console](https://github.com/YarnSpinnerTool/YarnSpinner-Console) を `dotnet publish --self-contained` で単一実行ファイル化）。2 回目以降はキャッシュされたバイナリを使う。

```bash
devbox shell
```

## Yarn 台本のコンパイル

`yarn/story.yarn` を `yarn/output.json` にコンパイルする。`ysc` のエイリアスは `init_hook` で `$PWD/yarn/.bin/ysc` に張ってある。

```bash
cd yarn && ysc compile Project.yarnproject -o output.json
```

実行時は `Game.loadProject` が `yarn/output.json` を読みに行く。

## 実行

```bash
devbox run run
```

## テスト

```bash
devbox run test
```

## 操作方法

- **Space / Enter / クリック** - 会話を進める / 選択肢を確定
- **↑ / ↓** - 選択肢の移動
- **F1** - ビジュアルエディタ ON / OFF
- **ESC** - 終了

### エディタ操作（F1 ON 中）

- **ドラッグ** - ノードの移動
- **ハンドルドラッグ** - リサイズ
- **矢印キー** - 1px 単位の nudge
- **Cmd + Z** - undo
- **保存** - `DialogueScene.scene.json` を書き換えるとホットリロードで反映

## プロジェクト構造

```
src/
  Main.flix                  - エントリーポイント（EngineConfig + 起動）
  game/
    Game.flix                - NodeTag・trait dispatch・gameLoop（7段パイプライン）
  scenes/
    DialogueScene.flix       - 対話 UI のシーン定義
    DialogueScene.scene.json - エディタが書き換えるシーンレイアウト
  yarn/                      - Yarn ランタイム（Flix 実装）
    Yarn.flix                - 公開ファサード
    YarnLoader.flix          - ysc 出力 JSON → YarnProject パーサ
    YarnVM.flix              - 命令実行 VM
    YarnTypes.flix           - Value / Program / Node 等の型
    YarnBuiltins.flix        - 組み込み関数（visited_count 等）
    YarnVariableStorage.flix - 変数ストレージ
    YarnStringTable.flix     - 文字列テーブル
  dialogue/
    Dialogue.flix            - 対話レイヤ（Session / SceneView / Inbox / Runner 連結）
    DialogueRunner.flix      - VM を駆動するランナー
    SceneView.flix           - シーンへの反映層
    StubView.flix            - テスト用スタブ
  editor/
    Editor.flix              - F1 トグル・ホットリロード・undo の入り口
    EditableNode.flix        - 編集対象ノードの抽象
    DragInput.flix / ResizeHandle.flix / KeyboardNudge.flix / Picking.flix
    EditHistory.flix         - undo 履歴
    Overlay.flix             - エディタ UI のオーバーレイ描画
    SceneJsonIndex.flix / SceneSerializer.flix - scene.json 入出力
  engine/                    - エンジン層（シーンツリー・物理・LWJGL レンダラ）
    GameEngine.flix          - 更新パイプライン
    LwjglLayer.flix          - LWJGL + OpenGL + OpenAL
    HotReload.flix           - ファイル監視
    SceneLoader.flix         - scene.json ローダ
    scene/                   - Node / Node2D / Sprite2D / Label2D / RichTextLabel / ...
test/
  yarn/                      - YarnLoader / YarnVM / Builtins / Scenario テスト
  dialogue/                  - DialogueRunner テスト
  engine/                    - シーンツリー・物理・各ノードのテスト
yarn/
  story.yarn                 - サンプル台本
  Project.yarnproject        - Yarn プロジェクト定義
  output.json                - ysc コンパイル済み台本
  .bin/ysc                   - ysc バイナリ（gitignore 済、自動ビルド）
sprites/                     - スプライト
audio/                       - 効果音（talk / tap）
fonts/                       - BestTen-DOT（16px ドット字形）
```

## 技術スタック

- **Flix 0.72.0** - 関数型プログラミング言語（effect system / trait）
- **Yarn Spinner v3** - 台本フォーマット
- **YarnSpinner-Console (ysc)** - `.yarn` → JSON コンパイラ
- **LWJGL 3.3.4** - OpenGL / GLFW / STB / OpenAL バインディング
- **OpenGL 3.3 Core Profile** - シェーダーベースの 2D スプライトレンダリング
- **OpenAL** - 効果音再生
