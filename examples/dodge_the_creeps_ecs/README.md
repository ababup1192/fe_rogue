# dodge_the_creeps — ECS版（単層スパイク）

`examples/dodge_the_creeps`（Godot 流の scene-tree 版）を、**不変 World ＋ 純粋 System** の単層 ECS で組み直したもの。エンジン（engine_core）には一切手を入れず、ゲーム側だけで ECS を実装している。

## アーキテクチャ

- **World**（`src/ecs/World.flix`）= ゲーム状態の唯一の正。component ごとの `Map[EntityId, _]` を持つ不変 enum。player と mob は同じ `positions`/`velocities`/`sprites` を共有する。
- **System**（`src/systems/`）= すべて `World -> World`。move/anim/despawn/collision/phase は純粋、spawn は `\ Math.Random`、player input は `\ GameEngine.Game`。移動は「意図→積分→制約」に分解（input が velocity を設定 → `moveSystem` が `Query.updateWith2` で全 entity を一律積分 → `clampPlayerSystem` が player だけ画面内へ）。
- **共有 lib `flix_engine_world`** = `EntityId`／`Query`（`Map[EntityId,_]` 上の join/update）／`Collision`（`Collider` component＋空間グリッド broadphase＋`detectCollisions`、narrowphase は engine の `checkOverlap` 再利用）を提供。どの ECS ゲームも depend して `Collider` を付け衝突ペアを読むだけ＝Bevy の物理プラグイン相当。衝突を各プロジェクトで書かない。
- **描画**（`src/render/RenderWorld.flix`）= `World -> List[GameEngine.Drawable]` の射影。scene-tree を介さず `Game.renderCommands` に直接渡す。テキストも `Label2D.toDrawables`（純粋）でノード無しに描く。
- **ループ**（`src/Game.flix`）= 自前。`process/handleCollisions/handleTimers/handleButtons` 等の scene-tree ヘルパは使わない。

## 操作

- `WASD` / 矢印 … 移動
- `Enter` / `Space` または Start クリック … 開始 / 再開
- `X` … pause（sim System を止めるだけ）
- `Z` … 巻き戻し（約30フレーム前へ）
- `Esc` … 終了

## 正直な before/after（LOC 実測）

| | 現行 (node-tree) | ECS版 |
|---|---:|---:|
| src | 821 | **880 (+59)** |
| test | 196 | **270 (+74)** |
| 　うち描画 | engine にタダで委譲 (0) | `RenderWorld` 108 を自前実装 |
| gameplay logic | Scene 各所に散在 | `systems/` 345（純粋 System） |

**ECS版は行数では縮まない（むしろ +59）。** 誇張せず言うと:

- **消えた**: mob のノード部分木構築・`VisibleOnScreenNotifier2D`＋ハンドラ・`Area2D`＋collision layer/mask・RigidBody 物理・5 つの Timer ノード＋`TimerHandler`・`GamePhaseState` effect。
- **移った/書き直した**: AnimatedSprite2D のフレーム送り → `animSystem`、画面端 spawn 幾何 → `mobSpawnSystem`、**描画 → `RenderWorld`（node 版は engine の scene-tree にタダで委譲していた分を自前実装）**。
- **足した（node 版に無い機能）**: 巻き戻し（`history`）・pause・決定論ヘッドレス。

つまり ECS の勝ちは **行数でも生の速度でもない**（Flix は不変なので ECS の高速反復の旨味は出ない）。勝ちは2点だけ、しかしそれは本物:

1. **gameplay が純粋 System なので testable**。`test/systems/` の 23 テストは scene を組まず、純粋関数を直接、または最小モック（seeded Random / no-op Audio / mock Game）を注入して検証する。
2. **node 版に不可能な payoff**。`test/systems/TestHeadlessRun.flix` は seeded Random＋mock Game＋固定 dt で**ゲーム全体を値として** 16 フレーム回し、`score==1 かつ GameOver` をゴールデン値でアサートする。巻き戻しも World が不変値だから `List[World]` を持つだけで成立する。可変状態に縛られた node 版にはどちらもできない。

## いつ scene-tree（二層）を残すか

このサンプルが**単層**（HUD も World に入れて即時描画）なのは、**dodge の HUD が平坦だから**（独立した 3 要素・階層/カスケード/レイアウト/フォーカス無し）。

`src/Game.flix` の `buttonHit` 周辺コメントの通り、Start ボタンの当たり判定を手書きできるのは 1 要素だからにすぎない。これが**ネスト/重なりのある UI**（最前面優先・親子の可視伝播・フォーカス scope・入力 bubbling）になると、それらは scene-tree が無料で提供するものを全部手書きする羽目になる。

→ **平坦 UI は単層が素直、複雑 UI は scene-tree（二層）が正解。** 後者の実例は `examples/fe_rogue` の `ItemMenuScene`/`TradeMenuScene`（カーソル・フォーカス・複数選択・ペイン間 mark）。本サンプルは「単層がどこまで通用するかの下限」を示す教材であって、二層の否定ではない。

## 設計メモ：純粋 ECS の schedule は data-driven にできる（が、ここでは無理）

純粋な ECS では System の並び（schedule）を `List[World -> World]` という**データ**として持て、並べ替えるだけで挙動が変わる（例: `damage→reaper` と `reaper→damage` で生死が変わる）。本サンプルはこれを**採用していない**。理由は `playerInputSystem`（`\ GameEngine.Game`）と `spawnSystem`（`\ Math.Random`）が effectful で、`damage`/`move` のような純粋 System と**同じ `List[World -> World]` に揃わない**から。

つまり「schedule をデータとして扱える」のは sim が完全純粋なとき。IO/乱数が混ざると一様性が崩れ、`src/Game.flix` の `stepSystems` のように手で `|>` 連結する（effect が型に出るのは利点でもある）。`Query` コンビネータのような**純粋な部品**は問題なく持ち込めるが、**schedule の data 化は純粋 ECS 固有の特典**、という切り分け。

## ビルド / テスト / 実行

```
./bin/flix build
./bin/flix test     # 23 tests
./bin/flix run
```
