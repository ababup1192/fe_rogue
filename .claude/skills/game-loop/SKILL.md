---
name: game-loop
description: "Game.flix の start と gameLoop の書き方ガイド。起動時の常駐ハンドラ設定（フェーズ Ref・エディタ・横断 effect）、フレーム毎の固定パイプライン、エディタ・ホットリロード統合、Scene への委譲ルールを含む。start / gameLoop / applyPhaseChange を編集するときに参照する"
user-invocable: false
---

# start / gameLoop の書き方

`Game.flix` の `start` と `gameLoop` は **ゲーム全体の制御の中心**。
ここに書くべき内容と Scene に委譲すべき内容の境界を明確にする。

## 区分

| 場所 | 責務 |
|---|---|
| `start` | 起動時に 1 回だけ実行。**ゲーム全体に渡って効く設定**（region・Ref・常駐ハンドラ・カスタム effect の注入） |
| `gameLoop` | **毎フレーム必ず走る固定パイプライン**（終了判定 → 入力 → 更新 → 描画 → 再帰） |
| `XxxScene` | **Scene に閉じたロジック**（その Scene のノード、状態、応答、スポーン） |

判断基準:
- 特定の Scene に閉じている → **Scene に置く**
- 複数の Scene を跨ぐ / アプリ全体に渡る → **start の handler に置く**（中身は Scene 関数の呼び出しのみ）
- フレーム毎に必ず走る固定処理 → **gameLoop に置く**

## start — 起動時の常駐セットアップ

```flix
pub def start(fontAtlas: FontAtlas): Unit \ {...} =
    region rc {
        let phaseRef = Ref.fresh(rc, GamePhase.Menu);
        run {
            gameLoop(fontAtlas, GamePhase.Menu, buildMenuScene(fontAtlas, ...))
        } with Editor.withState(rc)            // (1) エディタ・ホットリロードの常駐
          with handler XxxStateChanged {       // (2) シーン横断の状態通知
            def emit(newState, scene, k) =
                k(CameraScene.handleXxxStateChange(newState, scene))
          } with handler GamePhaseState {       // (3) フェーズの読み書き
            def get(k) = k(Ref.get(phaseRef))
            def put(target, k) = { Ref.put(target, phaseRef); k() }
          } with handler SpawnRequest {         // (4) ライフサイクル副作用要求
            def request(scene, k) = k(YyyScene.spawnRandom(scene))
          }
    }
```

start に置く 4 種:

1. **region + Ref** — フェーズなど「ゲーム全体で 1 つしか持てない状態」の格納場所
2. **エディタ・ホットリロードの常駐** (`Editor.withState`) — フレーム間で生き続けるエディタ内部状態
3. **シーン横断の状態通知 handler** — 1 つの Scene だけでは決められない処理を集約
   （例: 衝突 → カメラシェイク + フェーズ遷移）
4. **ライフサイクル副作用 handler** — process / ready などから出される副作用要求の実体
   （例: `Math.Random` を伴う動的スポーン）

各 handler の中身は **1〜2 行で Scene の関数を呼ぶだけ**。条件判定・計算は Scene 側に置く。

❌ NG: handler 内に Scene 固有の判定ロジックを書く

```flix
} with handler XxxStateChanged {
    def emit(newState, scene, k) = {
        let intensity = if (newState == ...) 5.0 else 3.0;  // ← Scene の判断
        let next = scene |> CameraScene.applyShake(intensity, ...);
        k(next)
    }
}
```

✅ OK: 値の選択も含めて Scene 側に委譲

```flix
} with handler XxxStateChanged {
    def emit(newState, scene, k) = k(CameraScene.handleXxxStateChange(newState, scene))
}
```

## gameLoop — フレーム毎の固定パイプライン

```flix
def gameLoop(fontAtlas, previousPhase, scene): Unit \ {...} =
    if (GameEngine.Game.shouldClose() or
        GameEngine.Game.isKeyPressed(GameEngine.Key.Escape)) ()
    else {
        let dt = GameEngine.Game.getDeltaTime();
        // (1) エディタ入力を最優先で処理（F1 トグル等を今フレームに反映）
        let afterEditor = Editor.handleInput(scene);
        // (2) エディタ ON 中はゲーム更新をスキップ
        let updated = if (Editor.isOn()) afterEditor
                      else afterEditor
                          |> GameEngine.process(delta = dt, paused = false)
                          |> GameEngine.physicsProcess(delta = dt, paused = false, gravity = ...)
                          |> GameEngine.handleInput
                          |> GameEngine.handleButtons
                          |> GameEngine.handleCollisions;
        // (3) フェーズ差分 + ホットリロード判定
        let currentPhase = GamePhaseState.get();
        let reload = Editor.pollReload() and currentPhase != GamePhase.GameOver;
        let next = if (currentPhase != previousPhase or reload)
                       applyPhaseChange(currentPhase, fontAtlas, updated)
                   else updated;
        // (4) エディタオーバーレイ合成 → 描画
        GameEngine.render(Editor.applyOverlay(fontAtlas, next));
        gameLoop(fontAtlas, currentPhase, next)
    }
```

7 つの段階（順番が意味を持つ）:

1. **終了判定** — shouldClose / Escape
2. **エディタ入力** — `Editor.handleInput`（最優先。F1 トグルを今フレームに反映するため）
3. **エディタ ON ならゲーム更新スキップ** — `Editor.isOn()`
4. **エンジンパイプライン**（5 段固定）:
    - `process` — 通常更新。Node の `process` redef を全ノードで呼ぶ
    - `physicsProcess` — 物理積分 + Node の `physicsProcess` redef
    - `handleInput` — `InputHandler` を発火
    - `handleButtons` — `ButtonHandler` を発火
    - `handleCollisions` — `AreaHandler` を発火
5. **フェーズ差分検出** + **ホットリロード判定** → `applyPhaseChange`
6. **エディタオーバーレイ合成** → `GameEngine.render`
7. **末尾再帰** — 現在の phase を次フレームの `previousPhase` に渡す

ここに書くのは「エンジンが提供するパイプライン段階を順に呼ぶこと」だけ。
**各段階で動くロジックの中身は trait instance / 各 Scene の `process` 等で実装される**。

❌ NG: gameLoop に Scene 固有の処理を割り込ませる

```flix
let updated = afterEditor |> GameEngine.process(...) |> ...;
// ❌ XxxScene の状態判定を gameLoop に書いている
let after = if (someCondition) XxxScene.someAction(updated) else updated;
```

✅ OK: 入力は `handleInput` が `InputHandler` を発火 → `InputHandler` が `XxxScene.input` を呼ぶ
（gameLoop は何も知らないまま流れる）

## エディタ・ホットリロードとの統合

エディタ（ビジュアル編集 / シーン JSON のホットリロード）は **アプリ全体に常駐する仕組み** なので、start と gameLoop の各所に組み込む。Scene 側には置かない。

| 場所 | 役割 |
|---|---|
| `start: Editor.withState(rc)` | エディタ内部状態（Ref / watcher）を region に確保。フレーム間で生き続ける |
| `gameLoop: Editor.handleInput` | エディタトグル・編集操作を最優先で処理 |
| `gameLoop: Editor.isOn()` | エディタ ON 時にゲーム更新を停止 |
| `gameLoop: Editor.pollReload()` | シーン JSON 変更を検知してフェーズ再構築をトリガー |
| `gameLoop: Editor.applyOverlay(fontAtlas, scene)` | エディタ UI を描画直前に合成（シーンには永続化しない） |

注意: ホットリロードはフルリビルドのフェーズでだけ安全に発火できる。
**オーバーレイ追加方式のフェーズ（GameOver 等）では握り潰す** — 再実行すると overlay が二重・三重に重なるため。

## applyPhaseChange — フェーズ別の組み立て

`gameLoop` から呼ばれ、phase に応じて Scene を組み立てる。
**ここでも Scene 固有のロジックは展開しない**（Scene の構築関数を呼ぶだけ）。

```flix
def applyPhaseChange(phase, fontAtlas, scene): Scene[NodeTag] \ {...} =
    match phase {
        case GamePhase.Playing  => buildPlayingScene(fontAtlas, ...)  // フルリビルド
        case GamePhase.Menu     => buildMenuScene(fontAtlas, ...)     // フルリビルド
        case GamePhase.GameOver => GameOverScene.enterGameOver(...)   // 既存にオーバーレイ
    }
```

判断指針: 状態をリセットしたい遷移 → フルリビルド / 既存状態を残したい遷移 → オーバーレイ追加

## Scene 委譲ルール（要約）

start / gameLoop は **配線役** に徹する。

| やる | やらない |
|---|---|
| Scene の構築関数を順に呼ぶ | Scene 内部のノード位置・速度を直接いじる |
| handler の中で Scene の関数を 1〜2 行呼ぶ | handler の中で条件分岐や数値計算をする |
| エンジンパイプラインを順に呼ぶ | パイプラインの間に Scene 固有処理を挟む |
| フェーズ差分を検出して `applyPhaseChange` を呼ぶ | `applyPhaseChange` の中で Scene の組み立てロジックを展開する |

判断に迷ったら: **「この処理はどの Scene にも持っていけないか？」** を先に問う。
1 つの Scene に閉じれば、そこに置く。
複数 Scene を跨ぐ場合のみ start の handler を経由させる（中身は呼び出しのみ）。
