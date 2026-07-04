# Worldline ガイドライン（v1 ドラフト）

Worldline アーキテクチャで作るための指針書 — 理念・原則・語彙・責務の置き場。
語彙は借り物（ECS/Godot）でなくコードベースに自然発生した言葉を採集したもの。
**昇格・倉庫番のタイミングで妥当性を見直す前提のドラフト**。

> 理念（一文）: **World は状態の点、Worldline はその軌跡。Step が世界を進め、Projection が世界を映し、
> Spec が世界を宣言し、Harness が世界を偽装し、Trace が世界を証明する。**

---

## 原則（迷ったらここに戻る）

1. **状態は World へ** — 状態を関数の外・ノード・グローバルに住まわせない。「これを1個保存すれば再現できる」を常に保つ
2. **副作用は縁へ** — ゲームの中身は純粋（Step/Projection）に、画面・音・乱数・時計との接点は effect handler に隔離する。
   乱数すら chokepoint（seeded PRNG）を通す — 決定論は性質でなく規律の帰結
3. **宣言できるものは Spec へ** — 再コンパイルなしで変えたいもの（UI・レベル・シナリオ・演出パラメータ）はデータにする。
   Spec になったものだけが、IDE 編集・ホットリロード・スナップショットの恩恵を受けられる
4. **fixture は嘘をつけない** — テストや画像の状態は必ず本物のコードパス（Step/Projection）で組む。手塗りは実機とズレる
5. **配線とロジックを分ける** — Driver は「いつ・どの順で」だけを持ち、「何をどう変えるか」は Step に置く。gameLoop にロジックを書かない
6. **破綻は機械に検出させる** — golden（変化検知）・RenderLint（幾何破綻）・DIFF（権威一致）・不変条件テスト。
   人間の目は最終審美判断に取っておく
7. **語彙と置き場を一致させる** — ただし層で切り方を変える:
   **ライブラリは語彙で切る**（engine_world のモジュール = 概念）。
   **ゲームは機能（縦スライス）で切り、語彙はファイル名の接尾辞に刻む**（`minimap/MinimapState.flix`・`〜Ui`・`〜Projection`・`〜Driver`）。
   名前が責務の宣言になる — `〜Projection` に副作用を書いたら名前が嘘になる

## 責務の置き場（fe_rogue の現在地図）

| ディレクトリ | 住むもの | 語彙 |
|---|---|---|
| `src/ecs/World.flix` | 状態の点（store 群） | World / Store |
| `src/ecs/resources/` | 単一状態 + handler 注入 | Resource |
| `src/sim/` | 純粋なルール遷移（ターン・フェーズ） | Step |
| `src/systems/` | フレーム駆動の配線 | Driver |
| `src/render/` | World → 描画データ | Projection |
| `src/ui/` + `assets/*.ui.json` | UI（宣言 + frameStep） | Spec + Step |
| `src/game/` | ループ・handler 束・dispatch | 配線（Harness の本番版） |
| `test/snapshots/` | 検証基盤 | Harness / Trace |

---

## World — 状態の点

**定義**: あるフレームにおけるゲーム状態の全体を1つの不変な値にしたもの。「今の世界のすべて」。

- 実物: `src/ecs/World.flix` の `World`（駒・盤面・fx の store 群）、`src/ui/UiStore.flix` の `UiWorld`（UI の store 群）
- 旧語彙: ECS の World に近いが、可変でなく**値**である点が本質的に違う
- 見分け方: 「これを1個保存すれば、その瞬間を完全に再現できるか？」→ Yes なら World
- **Flix でいうと**: 単一ケース enum に包んだ**不変レコード**（`pub enum World { case World({ hp = Map[...], ... }) }`）。
  中身は `Map`/`Set` などの**永続コレクション**。effect 注釈なし = 触っても何も起きないただの値

```flix
pub enum World {
    case World({ hp = Map[Int32, Int32], pos = Map[Int32, Vec2], score = Int32 })
}
// 「今の世界」はこの値1個。保存も比較もコピーも、ただの値としてできる
```

**規模の指針**: World は「巨大な一つの値」であるべきだが「巨大な一つのファイル」である必要はない。
育ったら**スライス合成**にする（`World = { combat = Combat.State, board = Board.State, ... }` —
各スライスが自分のサブレコード+Cmd+accessor を所有し、World.flix は合成の見取り図に徹する。
横断の芯（pos/hp 等）は core スライスへ。スライスは6〜8個程度まで）。小さいうちは1枚でよい。

## Worldline — 世界線（World の軌跡）

**定義**: World が時間とともにたどる軌跡。履歴・巻き戻し・リプレイ・分岐は、すべて世界線上の操作。

- 実物: dodge の `history: List[World]`（Z キー巻き戻し）、決定論リプレイ（同じ seed + 同じ入力 = 同じ世界線）、
  リプレイ GIF（世界線を1コマずつ絵に起こしたもの）、VN 構想の各ルート（分岐した世界線たち）
- 旧語彙: 対応物なし（このアーキテクチャ固有の概念・アーキテクチャ全体の看板）
- 見分け方: 「時間」「歴史」「もしも」を扱っていたら Worldline の話
- **Flix でいうと**: `List[World]`。永続データ構造は**構造共有**するので、履歴を持っても丸コピーにならない（巻き戻しが安価な理由）。
  決定論は「副作用を effect として縁に追い出した」ことの帰結

```flix
let worldline = w3 :: w2 :: w1 :: Nil;      // 履歴 = 世界線（構造共有で安価）
match worldline {
    case _ :: prev :: _ => prev              // 巻き戻し = 1つ遡るだけ
    case _              => w3
}
```

## Store — 状態の束

**定義**: World の中の、1種類の状態を束ねた入れ物。多くは `Map[id, 値]`（誰が何を持つか）。

- 実物: `World` の `hp = Map[EntityId, Int32]` / `weapons` / `visited = Set[Int32]`、`UiWorld` の `texts` / `selection`
- 旧語彙: ECS の component（の格納庫）。ただし archetype 等の性能機構は含意しない
- 見分け方: World のフィールド1個 = だいたい Store 1個
- **Flix でいうと**: `Map[Int32, T]` と **record update 構文** `{ hp = newHp | w }`（変えたいフィールドだけ差し替えた新しい値を作る）。
  「更新」がすべて非破壊なのはこの構文のおかげ

```flix
let hp = Map.get(id, w#hp);                            // 読む
World.World({ hp = Map.insert(id, 10, w#hp) | w })      // 書く = 差分だけ変えた新しい世界を作る
```

## Step — 世界を進める純関数

**定義**: `World -> World`（または dt 等を添えて）の純関数。1フレームぶん、あるいは1つの関心事ぶん世界を進める。

- 実物: `WorldDriver.stepFrame`・`stepWorld`・dodge の `stepSystems`・各 Ui の `frameStep`・`TopBarUi.advance`
- 旧語彙: ECS の system。ただし Step は「純関数である」ことが定義の中心
- 見分け方: 「同じ World を入れたら必ず同じ World が出るか？」→ Yes なら Step
- **Flix でいうと**: **純粋関数が集まる場所**。Flix では effect 注釈のない `def` は**コンパイラが純粋性を保証**する
  （ここが他言語との決定的な違い — 「純粋のつもり」でなく「純粋であることが型検査で証明済み」）。
  Step の連結は `|>` パイプ

```flix
def moveEnemies(w: World): World = ...        // 注釈なし = 純粋（コンパイラが保証）

def stepFrame(dt: Float64, w: World): World =
    w |> spawnEnemies(dt) |> moveEnemies |> resolveCollisions |> cullDead
```

## Driver — フレーム駆動のオーケストレータ

**定義**: gameLoop から毎フレーム呼ばれ、Step の起動・順序・タイミングを司る配線役。ロジックは持たない（持たせない）。

- 実物: `systems/EnemyTurnDriver.flix`・`StairsExitDriver`・`PlayerMovementDriver`
- 旧語彙: 近いものなし（scheduler の一種）
- 見分け方: 「いつ・どの順で」を決めていて「何をどう変えるか」を Step に委ねていれば Driver
- **Flix でいうと**: **effect row を持つ関数**（`def step(...): ... \ {TurnPhase.State, World.Command}`）。
  「この Driver が触ってよい世界の範囲」がシグネチャに全列挙される — FrameAef はその row の名前付き集合

```flix
def step(scene: Scene): Scene \ {TurnPhase.State, EnemyTurn.Queue, World.Command} =
    // ↑ このDriverが触れるのはこの3つだけ、と型が宣言している
    if (TurnPhase.State.get() == Phase.EnemyTurn) advanceQueue(scene) else scene
```

## Resource — 単一の状態

**定義**: 誰か（id）に属さない、世界に1つだけの状態。effect handler（`withState`）経由で読み書きする。

- 実物: `src/ecs/resources/` の全部（`CursorState`・`TurnPhase`・`TopBarState`・`MinimapState`…）
- 旧語彙: ECS/Bevy の Resource とほぼ同じ（ここは借用が自然なので維持）
- 見分け方: 「Map にする必要がない（1個しかない）状態」なら Resource
- **Flix でいうと**: **algebraic effect の定義と handler が集まる場所**。`pub eff State { def get(): Data  def put(d: Data): Unit }` を宣言し、
  `withState(rc)` が **Region + Ref + `run ... with handler`** で実装を注入する。
  「グローバル変数のように使えるが、誰が注入したかが型と構造で明示される」のが教育ポイント

```flix
pub eff State {
    def get(): Data
    def put(d: Data): Unit
}
pub def withState(rc: Region[r]): (Unit -> a \ ef) -> a \ (ef - State) + r =
    thunk -> {
        let ref = Ref.fresh(rc, initial());
        run { thunk() } with handler State {
            def get(k)    = k(Ref.get(ref))
            def put(d, k) = { Ref.put(d, ref); k() }
        }
    }
```

## Projection（射影）— 世界を映す純関数

**定義**: World から出力（描画・音・集計）を導出する純関数。世界を変えず、写すだけ。

- 実物: `render/RenderWorld.flix` の `renderUnits`/`renderFog`/`renderMinimap`、`UiRender.renderUi`、
  `UiExtract.extract`、`SoftRaster`（Drawable → PNG も射影の一種）
- 旧語彙: render system / view。「World → List[Drawable]」という**データを返すだけ**の点が特徴
- 見分け方: 「World を読むだけで、絵（や出力データ）を返す」なら Projection
- **Flix でいうと**: 純粋関数（アセット寸法などが要る時だけ最小の effect row）。`List` の `map`/`flatMap`/`filter` による**データ変換の連鎖**。
  「World → List[Drawable]」という型がそのまま仕様書になっている

```flix
def renderWorld(w: World): List[Drawable] =
    w#pos |> Map.toList |> List.map(p -> spriteAt(p))   // 読むだけ。世界は変わらない
```

## Spec — 宣言資産

**定義**: 構造をコードでなくデータ（JSON 等）で宣言したもの。パースされ、World に spawn される。
IDE 編集・ホットリロード・スナップショットの対象になれるのは Spec だから。

- 実物: `src/ui/assets/*.ui.json`（`UiSpec` がパース）、scene.json、将来の unit.json / arena.json / VN シナリオ
- 旧語彙: asset / prefab / PackedScene
- 見分け方: 「再コンパイルせずに変えられるべきもの」は Spec にする
- **Flix でいうと**: **enum/record によるデータモデリング** + JSON パース。パースは `Result` を **`forM` 構文**（モナド内包）で連鎖し、
  失敗を値として運ぶ（例外を投げない）。「不正な Spec はパースの時点で Err」がエラー設計の教材

```json
{ "name": "menu", "dir": "column", "layer": 7,
  "children": [ { "widget": "text", "text": "こうげき", "meta": "attack" } ] }
```
```flix
forM (spec <- UiSpec.load("Menu.ui.json"))            // 失敗は Err として返る
    yield UiSpec.spawnRoot(spec, ui)                   // 宣言 → World の entity 群へ
```

## Harness — 実行環境の偽装（effect handler の束）

**定義**: 本物のゲームコードを、本物の環境（画面・音・乱数・時計）なしで動かすための handler 一式。
「ゲームは自分がテストの中にいると気づかない」を実現する仕掛け。

- 実物: `test/snapshots/SnapshotHarness.flix`（`withMocks`/`withFullMocks`）、dodge の `runHeadless`、
  構想中の `CombatSandbox.withHarness`
- 旧語彙: mock / test double の束。effect システムがあるから型安全にできる
- 見分け方: 「本物のロジック + 偽物の周辺」という構図なら Harness
- **Flix でいうと**: **`run { thunk() } with handler ...` の積み重ね**。handler は動的スコープで effect を解釈するので、
  同じゲームコードが「本番では音が鳴り、Harness の中では no-op」になる。effect 多相（`\ ef`）の thunk を受ける高階関数が定石。
  **effect システムの威力が最も分かりやすく現れる場所**

```flix
run {
    CombatLogic.resolveAttack(scene)                   // ← 本物のゲームロジック（無改変）
} with handler GameEngine.Audio { def play(_, k) = k() }        // 音: 鳴らさない
  with handler World.RngDraw   { def roll(k)    = k(42) }       // 乱数: 固定 = 決定論
// ロジック自身は自分が偽物の世界に居ることを知らない
```

## Trace — 決定論の記録

**定義**: 世界線の記録。同じ入力からは必ず同じ Trace が出る、という性質を使って回帰を検出する。

- 実物: golden-trace（戦闘の遷移列）、スナップショットの golden（描画の記録）、リプレイファイル（入力の記録）
- 旧語彙: golden file / snapshot（テスト用語）— それを世界線の言葉で言い直したもの
- 見分け方: 「保存しておいて、後で同じものが出るか比べる」なら Trace
- **Flix でいうと**: 純粋性 + seeded PRNG（乱数さえ effect の chokepoint に閉じ込める）の帰結としての決定論。
  golden 比較は**ただの構造的等値比較**（特別な仕掛けは何もない — それが凄い、という教材ポイント）

```flix
let trace = runHeadless(seed = 7i64, inputs);          // 同じ seed + 同じ入力
Assert.assertEq(expected = goldenTrace, trace)          // → 必ず同じ世界線。比較は等値だけ
```

---

## Flix 機能マップ（教材用の逆引き）

| Flix の機能 | この語彙での現れ方 |
|---|---|
| **注釈なし def = 純粋（コンパイラ保証）** | Step / Projection の本体。「純粋な関数が集まる場所」 |
| **effect 宣言 + handler（`run/with`）** | Resource の実装・Harness の全体。「handler が集まる場所」 |
| **effect row（`\ {A, B}`）** | Driver・確定ロジックのシグネチャ。「触れる世界の全列挙」 |
| **Region + Ref** | Resource の内部実装（局所的な可変性を型で閉じ込める） |
| **不変レコード + record update** | World / Store の更新（非破壊） |
| **永続コレクション（Map/Set/List）** | Store の実体・Worldline の履歴（構造共有で安価） |
| **enum によるデータモデリング** | Spec の中間表現・Choice などの閉じた選択肢 |
| **`forM` + Result** | Spec のパース（失敗を値として運ぶ） |
| **`|>` パイプ** | Step の連結・gameLoop のフレームパイプライン |
| **effect 多相（`\ ef`）** | Harness が任意の thunk を受ける口 |

## 語彙の学習順序（教材はこの順で導入する）

全部を最初に渡すと面食らう。各語には「誕生の瞬間 = 感じた必要性」があり、教材はその順で導入する:

| ベイビーステップ | 生まれる疑問 | 新用語 |
|---|---|---|
| 0. Hello world / 1. Sprite を出す | —（描きたい物のリストを返す関数、だけ） | **なし** |
| 2. Sprite を動かす | 「位置はどこに置く？どう変える？」 | **World / Step**（対比で Projection） |
| 3. キーで動かす | —（effect 記法に初遭遇するが語彙は増やさない） | なし |
| 4. 敵を10体 | 「10体ぶんの状態は？」 | **Store** |
| 5. Z で巻き戻し | 「履歴を持てば戻れるのでは？」 | **Worldline**（キラー機能と同時に） |
| 6. メニュー | 「再コンパイルせずに直したい」 | **Spec** |
| 7. テスト | 「画面なしで動かして、出力を比べたい」 | **Harness / Trace** |
| 8. 規模拡大 | 「複数モジュールで同じ状態を」「順序の司令塔を」 | **Resource / Driver** |

必要の瞬間なしに導入される語があれば、それは語彙の設計ミス（見直し材料）。

## 語彙の使い方（運用メモ）

- 指示・設計書・レビュー・ドキュメントはこの語彙で書く（コード識別子の一括改名は語彙確定まで保留）
- 当てはまりの悪い場面に出会ったら、それは語彙の見直し材料 — 無理に当てはめず記録する
- パッケージ名の有力案: `engine_world`（昇格時に確定）。アーキテクチャ名: **Worldline**
