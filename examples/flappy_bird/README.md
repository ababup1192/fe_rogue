# Flappy Bird

Flix で実装した Flappy Bird クローン。Godot 風のシーンツリーアーキテクチャを Flix + LWJGL で再現。

## 必要環境

- devbox（推奨）
- JDK 21
- macOS (Apple Silicon / Intel) / Windows x86_64

## 実行方法

```bash
devbox run -- java -jar bin/flix.jar run
```

## テスト

```bash
devbox run -- java -jar bin/flix.jar test
```

## 操作方法

- **Space** / **マウスクリック** - 羽ばたき（Menu / GameOver アニメ後は Play ボタンと等価）
- **ESC** - 終了

## ゲームルール

- 鳥を操作してパイプの隙間を通り抜ける
- パイプを 1 つ通過するごとにスコア +1
- パイプ・地面に衝突するとゲームオーバー
- ベストスコアはセッション中保持される

## 画面構成

- 解像度: 288 × 512（Flappy Bird オリジナル準拠）
- フェーズ: Menu → Playing → GameOver

## プロジェクト構造

```
src/
  Main.flix                  - エントリーポイント（EngineConfig + 起動）
  scenes/
    Game.flix                - NodeTag enum・trait instance・ゲームループ
    MenuScene.flix           - メニュー画面（Play ボタン・タイトルラベル）
    BirdScene.flix           - 鳥（RigidBody2D・羽ばたき・回転制御）
    PipeScene.flix           - パイプペア（スポーン・スクロール・採点 Area2D）
    GroundScene.flix         - 地面（無限スクロール・衝突）
    CameraScene.flix         - カメラ（追従・シェイク）
    ScoreScene.flix          - スコア表示（数字スプライト）
    GameOverScene.flix       - ゲームオーバー演出・Play ボタン
  engine/
    GameEngine.flix          - エンジン更新パイプライン（process / physics / collision / timers）
    LwjglLayer.flix          - LWJGL + OpenGL + OpenAL レンダリング・オーディオ層
    Vec2.flix / Rect2.flix   - 2D ベクトル・矩形演算
    FontAtlas.flix           - フォントアトラス
    TextLayout.flix          - テキスト整形
    AudioUtil.flix           - オーディオユーティリティ
    RandomUtil.flix          - 乱数ユーティリティ
    scene/
      Scene.flix             - Godot 風シーンツリー
      EngineNode.flix        - ノード enum
      Node.flix / Node2D.flix / CanvasItem.flix / CanvasLayer.flix
      Sprite2D.flix / AnimatedSprite2D.flix / Label2D.flix / ColorRect.flix
      RigidBody2D.flix / StaticBody2D.flix / CharacterBody2D.flix / PhysicsBody2D.flix
      Area2D.flix / CollisionObject2D.flix / CollisionShape2D.flix
      Camera2D.flix / Marker2D.flix / Path2D.flix
      Button.flix / BaseButton.flix / TextureButton.flix / Control.flix
      AudioStreamPlayer.flix / Timer.flix / GPUParticles2D.flix
      VisibleOnScreenNotifier2D.flix
      PhysicsStep.flix        - 物理積分（重力・線形速度）
      AreaEvent.flix / AreaHandler.flix       - 衝突検出
      InputEvent.flix / ButtonEvent.flix      - 入力イベント
      TimerEvent.flix / ScreenNotifyEvent.flix
      NodeBuilder.flix / NodeRemovedHandler.flix / ScreenNotifyHandler.flix
      ProcessMode.flix
test/
  TestVec2.flix / TestRect2.flix / TestTextLayout.flix / TestAudioUtil.flix
  scenes/TestGame.flix       - ゲームロジックのテスト
  engine/scene/              - シーンツリー・物理・衝突・入力・各ノードのテスト
sprites/                     - 鳥・パイプ・地面・背景・ラベル・ボタン・メダル等
audio/                       - 効果音（羽ばたき / 得点 / ヒット / 死亡 / スウッシュ）
fonts/                       - スコア用フォント
```

## 技術スタック

- **Flix 0.71.0** - 関数型プログラミング言語
- **LWJGL 3.3.4** - OpenGL / GLFW / STB / OpenAL バインディング
- **OpenGL 3.3 Core Profile** - シェーダーベースの 2D スプライトレンダリング
- **OpenAL** - 効果音再生
