# Shape Survivors — 設計書

Flix（関数型プログラミング・代数的エフェクト）を**ゲームエンジンを題材に学ぶ**ブログ記事シリーズの **第一弾**。
ゲームは学習の「乗り物」であり、最終目的は読者が Flix の FP/Effect を使いこなせるようになること。

対象読者：他言語（JS/Python/Java 等）の経験はあるが、関数型プログラミングは初めて。

---

## なぜ「オートシューター」なのか

Vampire Survivors 風オートシューターは、面白さの密度が高いのに、**構造が FP 教材として理想的**：

- 敵の大群 ＝ **リスト**（`List[Enemy]`）
- 1 フレーム ＝ 前フレームの**純粋関数**（`step(world): World`）
- 画像アセット不要 — 図形（円・三角・矩形）＋ SDF フォントだけで成立しうる

「動くだけで敵が溶けていく」快感を、命令型なら可変配列＋for ループ＋手動削除でやるところを、
FP では `List.map` / `List.filter` / `List.foldLeft` の純粋変換で書く。それを**数百体の敵で視覚的に**体感させられる。

---

## 1. コアループ（削り切った理想系）

> **動く → 勝手に敵が溶ける → XP を拾う → レベルアップで3択 → 強くなる → もっと湧く → さらに生き延びる**

死守する面白さ ＝〈**オート攻撃 × 大群 × レベルアップの雪だるま**〉。これ以外は全部削る。

### 仕様
| 要素 | 内容 |
|---|---|
| 自機 | 図形 1 つ。WASD/矢印で移動。**攻撃ボタンなし**。最大 HP（初期 3〜5） |
| 武器 | **Whip（薙ぎ）**。一定間隔で**向いている左右に「広い矩形の面」で薙ぐ**（VS の Whip 同様、オートエイムなし）。矩形内の敵 HP を即時に削る AoE。multiShot で両側薙ぎ |
| 敵 | 1 種。画面端からスポーン → 自機へ追尾。被弾で死亡＋XP ジェムをドロップ。自機接触でこちらが被弾（短い無敵） |
| XP/レベル | ジェム取得で XP 加算。満タンで**一時停止 → 3 択の強化** |
| 強化 | `Damage / FireRate / MultiShot / MoveSpeed / MaxHp` の 5 種から毎回ランダム 3 提示 |
| 激化 | 時間経過で**スポーン間隔**を下げる（湧きが濃くなる） |
| 決着 | HP0 でゲームオーバー。**生存時間＝スコア**。リスタートで別ビルドを試す（ラン制） |

### 削ったもの（初回プレイの面白さに影響しないと判断）
多彩な武器・武器進化／敵種の多様性（数と速度で代替）／マップ・地形（固定 1 画面）／
スクロールカメラ／永続強化（メタ進行）／パッシブアイテム。

---

## 2. ここで教える Flix（FP）＝作る順

第一弾は **不変性・リスト・純粋関数** で完結。effect / trait は第二弾以降に温存。
唯一 `\ Math.Random`（ランダムな湧き）だけ「型に副作用が出る最初の一例」として**読むだけ**で見せる。

| 概念 | ゲーム内の登場箇所 |
|---|---|
| Record と不変更新 `{f = v \| p}` | 自機の位置・HP・XP を「書き換えず作り直す」 |
| **List ＋ 高階関数（本丸）** | 大群 `List[Enemy]`：湧き = `Cons`、移動 = `List.map`、死亡/画面外 = `List.filter` |
| 純粋な `step(world): World` | 下記パイプ全体。シグネチャに `\` が無い＝副作用なしを型で確認 |
| Option | 最近敵 `List.minimumBy`／`None` なら撃たない |
| fold | 被弾解決・XP 合算・ダメージ集計を `foldLeft` |
| ADT ＋ パターンマッチ | `enum Upgrade` を `match` で適用（レベルアップ画面が教材） |

```
step(world) =
    world
      |> spawnEnemies     // 端に湧かす（ここだけ \ Math.Random）
      |> moveEnemies      // enemies |> List.map(寄せる)
      |> autoFire         // 最近敵 = minimumBy → Option、Some なら撃つ
      |> moveProjectiles  // List.map
      |> resolveHits      // 命中した敵を filter で消す、XP は foldLeft
      |> collectXp
      |> cullDead         // List.filter(alive)
```

---

## 3. アーキテクチャ：エンジン本来の Scene ＋ trait dispatch ＋ effect（ハイブリッド）

エンジン本来の流儀（dodge/fe_rogue）に寄せつつ、オートシューター特有の「毎フレーム湧き死ぬ数百の
動的エンティティ」を破綻させないためのハイブリッド。

- **静的構造（背景・HUD）**：`scene.json` ＋ engine ノード（`SceneLoader.loadSceneWithFont`）。
  回4 のレベルアップ UI も engine の Panel/ItemList/MenuHandler を使えてスケールする。
- **動的な群れ（敵・弾）**：純粋 `Model.World` の `List` を `WorldDriver(Model.World)` ノード **1 個**に
  抱えさせる（1 体 1 ノードにしない）。衝突・移動は純粋層でテスト可能なまま。描画だけ毎フレーム図形ノードへ展開。
- **局面（Playing/GameOver）**：`GamePhaseState` effect（`Game.start` の region 内 `Ref`）。
- **Game.flix**：`NodeTag` ＋ trait instance（`Node`/`InputHandler`）は **dispatch に徹し**、
  `process` を `WorldScene` へ委譲。`gameLoop` は engine パイプライン（`process → handleInput → render`）を呼ぶだけ。
- **純粋層（game/）は無改変**：`Update.step` は `World -> World` の純粋関数のまま、`flix test` がエンジン無しで回る。

> なぜ群れを 1 体 1 ノードにしないか：engine の `EngineNode` は閉じた固定集合でカスタムノードを足せず、
> `render` は毎フレーム全ノードを 3 回 preorder 走査する。数百ノード化すると走査固定費が比例増し、かつ
> 衝突が engine 機構へ移って「純粋ロジックを値だけでテストできる」最大の教材価値が消える。
> （architecture review より。`Scene.flix` preorderPaths/processAll, `GameEngine.flix:302-343` 根拠）

### 正直な整理：このゲームの核は中央集権 MVU。scene+dispatch が実際に買ったもの
飾らずに言うと：
- **ゲームの核 `Update.step` は中央集権の純粋関数（MVU の update）**。群れロジックは横断的
  （衝突＝敵×弾の総当たり、最近敵＝全敵走査、スポーン上限＝総数）なので、中央集権が正しい形。
- engine には **per-node dispatch**（独立エンティティが自ノードの `process` で動く。例：dodge の
  `PlayerScene.physicsProcess`）もあるが、群れは独立エンティティではないので**使わない**。
- したがって、このゲームで **scene+dispatch 移行が実際に買ったのは `GamePhaseState`(effect) と
  `scene.json`(静的構造) の 2 点**だけ。trait dispatch 層が実体を持つのは UI/局面/入力の統合まわりで、
  ゲームの核（群れシミュ）は MVU のまま。これはこのジャンルの性質なので、そう正直に書く
  （「dispatch でゲームロジックを分散している」と取り繕わない）。
- 教材としては、**per-node dispatch は「独立エンティティが主役のゲーム」で別途教える**のが素直。

---

## 4. ビルド進行（記事ミニシリーズ4本想定）

各回 ＝「明確な楽しさの追加」＝「明確な FP 概念の追加」。

| 回 | 追加される楽しさ | 主に学ぶ FP |
|---|---|---|
| 1 | 自機が動き、敵が湧いて**追ってくる**（“生きてる”感） | Record 更新／`List.map`／湧きで `\ Math.Random` を読む |
| 2 | **勝手に敵が溶ける**（オート攻撃が刺さる瞬間） | `Option`（最近敵）／弾の `List`／`List.filter`（命中） |
| 3 | 被弾・HP・**ゲームオーバー＋生存タイマー** | 純粋 `step` 完成／`foldLeft`／`enum Phase` ＋ match |
| 4 | XP・**レベルアップ3択でビルドが育つ**（中毒ループ完成） | `enum Upgrade` ＋ パターンマッチ／不変な強化適用 |

---

## 5. 現在の状態（回2まで実装済み）

`src/scenes/Game.flix` は MVU（純粋 `step`/`view` ＋ 副作用 `gameLoop`）で実装中。

- **描画**：自機＝円（Arc2D）、敵・弾＝四角（Polygon2D、1個1ポリゴン）。
  円は1個32ポリゴンなので、数百体の群れは四角で描いて描画コストを約1/32に抑える。
- **回1**：自機が WASD/矢印で動き、敵（赤い四角）が画面端からランダムに湧いて追尾。
  → Record 不変更新／`List.map`（全敵追尾）／`List.foldLeft`（描画）／`\ Math.Random`（湧き位置のみ）。
- **回2**：オート攻撃。自機が**向いている方向**（最後に動いた方向＝`aimFrom`）へ弾（黄）を発射、
  命中した敵と弾を `List.filter`/`List.count` で除去。倒した数を HUD に表示。multiShot は `Vec2.rotated` で扇状に。
  → 向きを World に持つ／`List.filter`（命中・画面外の除去）。
- **回3**：被弾で HP-1（1秒無敵・自機が白く点滅）、HP0 で `Phase.GameOver` に遷移して停止、
  Enter で再挑戦。HUD に HP・生存時間（スコア）・kills。
  → `enum Phase` ＋ パターンマッチ（局面で挙動を分岐）／純粋 `step` の完成（被弾・死亡・生存時間も World の作り直し）。

- **回4a**：ステータス（移動/連射/弾数/最大HP）を World に持ち、`enum Upgrade.Kind` ＋ 純粋 `apply` で強化。
  multiShot は近い敵から順に N 発。
- **XPジェム**：敵を倒すと緑のジェムを落とし、自機が近づくと吸い寄せられ（magnet）、触れると XP（pickup）。
  → `List` 操作の実践（ドロップ＝`map`、吸引＝`map`、回収＝`filter` で二分）。位置取りの駆け引きが生まれる。
- **激化**：スポーン間隔を生存時間の純粋関数 `spawnIntervalAt(elapsed)` に（0.8→下限0.15）。時間で湧きが濃くなる。
- **敵の種類（ADT）**：`enum EnemyKind { Grunt, Tank }`。Tank は HP 4・遅く・大きく（紫）・ジェムを多く落とす。
  敵に `kind`/`hp` を持たせ、`Damage` 強化（5種目）で弾の威力を上げて固い敵を速く倒す。
  → **ADT＋パターンマッチ**で種類別パラメータ（速度/HP/見た目/ドロップ）。「純粋 List 設計は種類が増えても
  ノードを増やさずフィールド追加だけ」を実演。命中は各敵の HP を `List.count`×`damage` で削る。
- **回4b**：強化を**プレイヤーが3択で選ぶ** engine UI。`GamePhase.LevelUp` でポーズ（paused=true）し、
  `ItemList`（focused）を重ねて `GameEngine.handleMenus` が ↑↓/Enter を処理、`MenuEvent.MenuHandler`
  が `onItemConfirmed` で確定 → `Upgrade.apply` ＋ メニュー除去 ＋ `put(Playing)` で再開（世界は保持）。
  選択肢は ItemList の `NodeTag.LevelUpMenu(choices)` に持たせる。
  → **ここが scene+dispatch（engine の per-node メニュー dispatch）が本当に活きる回**。
  「横断ロジックは中央集権の純粋層、UI は engine dispatch」という正直な整理が実際に噛み合う。

### ファイル構成（純粋 game/ ＋ presentation scenes/ ＋ scene.json）
依存は一方向 **Model ← Update ←（NodeTag/WorldScene/Game）**。`game/` はエンジン非依存。

| ファイル | mod | 役割 | エンジン依存 |
|---|---|---|---|
| `src/game/Model.flix` | Model | 状態（World/Enemy/Projectile）・定数・`initialWorld` | なし（Vec2 のみ） |
| `src/game/Update.flix` | Update | `step` パイプライン＋全ロジック（**中央集権の純粋関数＝MVU の update**） | なし（Model/Vec2 のみ） |
| `src/game/Upgrade.flix` | Upgrade | 強化の種類（enum Kind）＋ `apply`（World へ適用・純粋） | なし（Model のみ） |
| `src/scenes/Game.flix` | （root）＋ Game | `GamePhase`/`GamePhaseState`/`NodeTag`/trait instance（dispatch）＋ start/gameLoop/applyPhaseChange | あり |
| `src/scenes/WorldScene.flix` | WorldScene | `WorldDriver` の `process`（Update 駆動）＋ `syncVisual`（World→図形）＋ scene.json ロード | あり |
| `src/scenes/StageScene.scene.json` | – | 静的構造（背景 ColorRect・HUD Label2D）の宣言 | – |
| `test/TestGame.flix` | – | Model/Update だけを値でテスト（5本green） | なし |

> 教材的な肝：**ゲームの本体（game/）はエンジンを import しない**。だから `flix test` がウィンドウ無しで回る。
> `WorldDriver(Model.World)` が「engine ノード中心」と「純粋ロジック」を 1 点で橋渡しする。

### コード構成（説明しやすさ重視のリファクタ済み）
- `step` は **純粋ステージ `World -> World` のパイプライン**：
  `movePlayer |> moveEnemies |> spawn |> moveProjectiles |> autoFire |> resolveHits |> takeContactDamage |> advanceClock`。
  上の「step のパイプライン図」がそのままコードに出る。各段は差分だけ更新（`{f = v | world}`）。
- `view` も `addBackground |> addCircles |> addPlayer |> addHud (|> addGameOverOverlay)` の小関数合成。
- 色は `f32` を 1 箇所に閉じ込めるため定数化（`enemyColor()` 等）。
- `test/TestGame.flix`：純粋関数（`movePlayer`/`nearestEnemy`/`step`）を**エンジン無し・値だけ**でテスト（`flix test`）。
  → 「純粋に保つ」と、ウィンドウを開かず値の比較だけで検証できる、という purity の見返りを体感する教材。

> 落とし穴メモ：`from` は Flix の予約語。引数名に使うとパース崩れ → `origin` 等に。
> `FontAtlas` はトップレベル型（`GameEngine.FontAtlas` ではない）。
> macOS の GUI 起動には example 直下の `bin -> ../../bin` シンボリックリンクが必須。

### 動かし方
```sh
# リポジトリルートで一度だけ（エンジンを lib/ に配布）
make sync

# ゲームディレクトリで
cd examples/shape_survivors
java -jar ../../bin/flix.jar build   # 型チェック
java -jar ../../bin/flix.jar run     # ウィンドウ起動
java -jar ../../bin/flix.jar test    # テスト
# devbox 環境なら: devbox run -- java -jar ../../bin/flix.jar run
```

開発は main から切った worktree（ブランチ `shape-survivors`）で行う。
