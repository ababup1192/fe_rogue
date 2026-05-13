# Flappy Bird 再現計画

## Context

参考実装（Godot 3.x / GDScript）の Flappy Bird を、既存の Flix 2D エンジン上で忠実に再現する。
現在のプロジェクトは「Dodge the Creeps」スタイルのゲームロジックが入っているため、
`src/scenes/` 配下を Flappy Bird 用に作り替える。エンジン側は基本そのまま使う。

---

## 参考実装の要点

| 項目 | 値 |
|---|---|
| 画面サイズ | 144 x 256（テスト時 288x512） |
| スクロール方式 | 鳥が右方向に speed=50 で移動、カメラが追従 |
| 重力 | Godot デフォルト(980) × gravity_scale=5.0 |
| Flap | velocity.y = -150, angular_velocity = -3 |
| 回転制限 | -30° まで（falling 時 angular_velocity = +1.5） |
| パイプ gap | 上下 sprite が中心から ±101。衝突 Rect(13,80)。gap 中心は Y=55〜145 のランダム |
| パイプ間隔 | X 方向に 91px ずつ |
| コイン | パイプ間の Area2D（Rect 2x21）。通過で score+1 |
| 地面 | StaticBody2D、width=168、y=256 |
| 鳥の衝突 | CircleShape2D radius=6.5 |

### 鳥の状態マシン

```
Flying（メニュー）→ Flapping（プレイ中）→ Hit（パイプ衝突）→ Grounded（地面着地）
```

---

## 画面サイズの決定

参考実装は 144x256 で全スプライトサイズが設計されている。
現在のプロジェクトは 480x720 だが、スプライトがそのまま使えるよう **288 x 512**（2倍スケール）を採用する。
物理パラメータは全て 2 倍にスケールする。

| パラメータ | 元 (144x256) | 2x (288x512) |
|---|---|---|
| bird speed | 50 | 100 |
| flap velocity.y | -150 | -300 |
| angular_velocity (flap) | -3 | -3（角度は不変） |
| angular_velocity (fall) | 1.5 | 1.5 |
| rotation clamp | -30° | -30° |
| pipe gap center Y | 55〜145 | 110〜290 |
| pipe sprite offset | ±101 | ±202 |
| pipe collision rect | 13x80 | 26x160 |
| coin collision rect | 2x21 | 4x42 |
| pipe spacing X | 91 | 182 |
| ground width | 168 | 336 |
| ground Y | 256 | 512 |
| bird collision circle | r=6.5 | r=13 |
| camera offset | (-36, 0) | (-72, 0) |
| gravity_scale | 5.0 | 1.0（Godot 3.x 基準重力 98×5=490、2x で 980。エンジン重力 980×1.0=980） |

---

## Scene 構成

現在の `PlayerScene` / `MobScene` / `HUDScene` を削除し、以下に差し替える：

### 1. BirdScene（鳥）

```
bird (RigidBody2DWithState) — NodeTag.Bird(BirdData)
  └── sprite (AnimSprite2DWithState) — NodeTag.NoTag
```

- **BirdData**: `{ state: BirdState, speed: Float64 }`
- **BirdState**: `Flying | Flapping | Hit | Grounded`
- RigidBody2D: gravity_scale=5.0, CircleShape2D(r=13)
- AnimatedSprite2D: bird_orange_0/1/2（3フレーム、5FPS）
- process で状態に応じた挙動を分岐

### 2. PipeScene（パイプ1組）

StaticBody2D は shape を1つしか持てないため、上下を別ノードにする：

```
pipe_N_top (StaticBody2DWithState) — NodeTag.Pipe
  └── sprite (Sprite2DWithState) — NodeTag.NoTag
pipe_N_bottom (StaticBody2DWithState) — NodeTag.Pipe
  └── sprite (Sprite2DWithState) — NodeTag.NoTag
pipe_N_coin (Area2DWithState) — NodeTag.Coin
```

- group: "pipes"（一括削除用）
- カメラ左端を超えたら削除 → process で判定

### 3. GroundScene（地面タイル）

```
ground_N (StaticBody2DWithState) — NodeTag.Ground
  └── sprite (Sprite2DWithState) — NodeTag.NoTag
```

- group: "grounds"
- カメラ左端を超えたら再スポーン

### 4. BackgroundScene（背景）

```
background (CanvasLayerWithState, layer=-1) — NodeTag.NoTag
  └── sprite (Sprite2DWithState) — NodeTag.NoTag
```

### 5. HUDScene（UI）

```
hud (CanvasLayerWithState, layer=1) — NodeTag.NoTag
  ├── score_label (Label2DWithState) — NodeTag.ScoreLabel(score)
  ├── instruction_button (ButtonWithState) — NodeTag.InstructionButton
  └── gameover_container (ControlWithState) — NodeTag.GameOverContainer
      ├── gameover_label (Sprite2DWithState) — NodeTag.NoTag
      ├── score_panel (Sprite2DWithState) — NodeTag.NoTag
      └── play_button (ButtonWithState) — NodeTag.PlayButton
```

---

## NodeTag 再設計

```flix
pub enum BirdState with Eq, ToString {
    case Flying
    case Flapping
    case Hit
    case Grounded
}

pub enum NodeTag with Eq, ToString {
    case Bird(BirdData)
    case Pipe
    case Coin
    case Ground
    case ScoreLabel(Int32)
    case InstructionButton
    case PlayButton
    case GameOverContainer
    case NoTag
}
```

---

## GamePhase

```flix
pub enum GamePhase with Eq, ToString {
    case Menu
    case Playing
    case GameOver
}
```

- **Menu**: 鳥は Flying 状態（ボビングアニメ、重力なし）。InstructionButton 表示。
- **Playing**: 鳥は Flapping 状態。パイプ生成開始。flap 入力受付。
- **GameOver**: 鳥は Hit → Grounded。GameOver UI 表示。PlayButton で Menu へ。

---

## 実装フェーズ

### Phase 1: 鳥 + 重力 + Flap

**ゴール**: 鳥が重力で落下し、スペースキーで羽ばたく手触りを確認

**対象ファイル**:
- `src/scenes/BirdScene.flix`（新規）
- `src/scenes/Game.flix`（書き換え）
- `src/Main.flix`（画面サイズ・アセット調整）

**やること**:
1. BirdScene モジュール作成（RigidBody2D + AnimatedSprite2D）
2. Game.flix を Flappy Bird 用に書き換え（GamePhase, NodeTag, gameLoop）
3. Main.flix の screenWidth/Height を 288x512 に変更
4. 鳥を画面中央付近に配置、重力で落下させる
5. スペースキー / クリックで flap（velocity.y セット）
6. 回転制御（falling 時に angular_velocity、-30° clamp）

**確認**: `devbox run -- java -jar bin/flix.jar run` で鳥が落下・flap できること

### Phase 2: 地面

**ゴール**: 地面が表示され、鳥が地面で止まる

**対象ファイル**:
- `src/scenes/GroundScene.flix`（新規）
- `src/scenes/Game.flix`（地面追加）

**やること**:
1. GroundScene モジュール作成（StaticBody2D + Sprite2D）
2. 鳥の RigidBody2D と地面の衝突判定（AreaHandler で検知）
3. 地面タイルの無限スクロール（カメラ左端を超えたら右端に再配置）
4. Hit/Grounded 時に地面スクロール停止

**確認**: 鳥が地面で止まること。地面がスクロールすること。

### Phase 3: カメラ + 横スクロール

**ゴール**: 鳥が右に移動し、カメラが追従する

**対象ファイル**:
- `src/scenes/Game.flix`（カメラ追加）

**やること**:
1. Camera2D をシーンに追加（FixedTopLeft、offset=(-72, 0)）
2. 鳥の X 位置にカメラを追従させる（process で position.x = bird.position.x）
3. 背景を CanvasLayer(layer=-1) でカメラ非連動にする

**確認**: 鳥が右に進み、カメラが追従すること

### Phase 4: パイプ

**ゴール**: パイプが生成・スクロールされ、衝突で Hit 状態になる

**対象ファイル**:
- `src/scenes/PipeScene.flix`（新規）
- `src/scenes/Game.flix`（パイプスポーン追加）

**やること**:
1. PipeScene モジュール作成（上下 StaticBody2D + Sprite2D）
2. Flapping 開始時にパイプ 3 本を初期スポーン
3. パイプ削除時に新パイプを追加（リサイクル方式）
4. パイプ Y 位置のランダム化
5. 鳥とパイプの衝突判定 → Hit 状態遷移

**確認**: パイプが右から流れてくること。衝突で鳥が Hit になること。

### Phase 5: スコアリング

**ゴール**: パイプ間通過でスコア加算

**対象ファイル**:
- `src/scenes/PipeScene.flix`（coin Area2D 追加）
- `src/scenes/Game.flix`（スコア処理）

**やること**:
1. 各パイプ組の中央に Coin（Area2D）を配置
2. 鳥が Coin を通過 → score+1、sfx_point 再生
3. HUD のスコア表示を更新

**確認**: パイプ通過でスコアが増えること

### Phase 6: HUD + ゲームオーバー

**ゴール**: スコア表示、ゲームオーバー画面、リプレイ

**対象ファイル**:
- `src/scenes/HUDScene.flix`（書き換え）
- `src/scenes/Game.flix`（GameOver フロー）

**やること**:
1. スコア表示（数字スプライトを並べる or Label2D）
2. ゲームオーバー時: game_over ラベル + スコアパネル + メダル表示
3. Play ボタンでリスタート
4. メダル判定（10:bronze, 20:silver, 30:gold, 50:platinum）

**確認**: ゲームオーバー → スコア表示 → リプレイが動作すること

### Phase 7: メインメニュー

**ゴール**: タイトル画面の実装

**対象ファイル**:
- `src/scenes/Game.flix`（Menu フェーズ実装）
- `src/scenes/HUDScene.flix`（メニュー UI）

**やること**:
1. Menu フェーズ: 鳥は Flying 状態（重力なし、ボビングアニメ）
2. "Flappy Bird" ロゴ表示
3. Play / Score / Rate ボタン
4. InstructionButton タップ → Flapping 開始

**確認**: メニュー → タップ → プレイ → ゲームオーバー → メニュー のフルループ

### Phase 8: 効果音 + 演出

**ゴール**: サウンドとカメラシェイクの追加

**対象ファイル**:
- `src/scenes/Game.flix`
- `src/scenes/BirdScene.flix`

**やること**:
1. sfx_wing（flap 時）、sfx_hit（パイプ衝突）、sfx_die（死亡）、sfx_point（スコア）
2. sfx_swooshing（ステージ遷移）
3. カメラシェイク（Hit/Grounded 時）
4. ゲームオーバー UI のフェードインアニメーション

**確認**: 全 SE が正しいタイミングで鳴ること

---

## 削除するファイル

- `src/scenes/PlayerScene.flix`
- `src/scenes/MobScene.flix`
- 既存の HUDScene.flix は書き換え

---

## エンジン側の変更（必要に応じて）

1. **RigidBody2D と StaticBody2D の衝突応答**: 現在のエンジンは Area2D ベースの検知のみ。
   鳥(RigidBody2D) と パイプ/地面(StaticBody2D) の衝突は `AreaEvent` で検知できるが、
   鳥に Area2D の子ノードが必要（monitoring=true）。
   → BirdScene に Area2D 子ノードを追加して衝突検知する方式で対応。

2. **画面サイズ変更**: Main.flix の screenWidth/Height を 288x512 に変更。

---

## 検証方法

各フェーズ完了時に:
```bash
devbox run -- java -jar bin/flix.jar test
devbox run -- java -jar bin/flix.jar run
```

最終的なフルループ確認:
1. 起動 → メニュー画面が表示される
2. タップ → 鳥が Flapping 開始、パイプ生成
3. スペース/クリックで flap、パイプを避ける
4. パイプ通過でスコア+1、sfx_point
5. パイプ/地面に衝突 → Hit → Grounded → ゲームオーバー
6. Play ボタン → メニューに戻る
7. 再プレイ可能
