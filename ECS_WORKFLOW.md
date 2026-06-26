# ECS ハイブリッド移行ワークフロー（道標）

このドキュメントは、既存のゲーム（まず `examples/fe_rogue`）を **壊さず・動かしながら** 段階的に
ECS 化し、最終的に **UI 層（scene-tree）と ECS 層（World）が調和した一つのまとまったコード** へ
到達するための **方法論＋ロードマップ＋進捗** を載せた living document（生きた道標）です。

> **新しいセッションの開始手順**: ① この doc を上から読む → ② 末尾「§G 進捗」で現在ステップを確認 →
> ③ そのステップの「次の一手」を実行 → ④ 各ステップ完了時にゲートを通し §G を更新する。

関連: 共有 lib は `engine_ecs/`（package `flix_engine_ecs`）。リファレンス実装は `examples/dodge_the_creeps_ecs`。

---

## §A. 目標アーキテクチャ（調和した最終形）

```
            入力(UI コマンド・確定時のみ)
                     │  逆方向（command）
                     ▼
   ┌──────────────  World（不変・シミュレーションの唯一の正）──────────────┐
   │  positions / hp / statuses / … を component ごとの Map[EntityId, _] で  │
   │     System（World -> World、純粋 or narrow effect）で前進               │
   └───────────────────────────┬──────────────────────────────────────────┘
                               │ 一方向 sync（World → scene-tree）
                               ▼
   ┌────────── scene-tree（描画＋UI 専用・正の sim 状態は持たない）──────────┐
   │  Sprite2D/Label2D/… のノード＝表示。メニュー(Item/Trade/Action)もここ   │
   │  engine の既存 GameEngine.render(scene) で描画                          │
   └─────────────────────────────────────────────────────────────────────┘
```

- **World = 頭脳**（全シミュレーション状態と論理）、**scene-tree = 身体**（描画・UI）、**sync = 神経**（World→node を一方向に流す）。
- 状態の二重持ちをやめ **World に一本化**。scene-tree は World の派生ビュー。
- UI 入力は **コマンド**として World に返す（確定時だけ・逆方向）。連続同期は World→scene の一方向のみ。
- **dodge との違い**: dodge は scene-tree を捨て即時 Drawable で描画（`Render`）。fe_rogue は **scene-tree 描画を残す**ので、`Render` は使わず **World→scene-tree の sync 層**でつなぐ。

### fe_rogue の採用戦略：**read-model 先行**（決定 2026-06-26）

上の §A は理想の最終形。fe_rogue は **いきなり「World を唯一の正」にせず、read-model 先行**で進める:

- **World は scene から mirror した派生 read-model**（`syncFromScene` で scene→World・毎フレーム）。**query / セーブ / 決定論テスト**に使う。
- **権威 flip は ECS の旨味が出るサブシステムだけ**に限定し、サブシステム単位で都度判断する。旨味が大きいのは
  **位置（Board/Encounter）・EnemyAI・セーブ**（S3〜S7）。**statuses / hp のように scene 側の純粋ロジックで既に綺麗な物は
  flip しない**（read-model として mirror するだけ）。
- 理由: statuses tick の検証で判明 — 既に綺麗な subsystem の権威 flip は **挙動ゼロ変化なのにドライバ大改修コストだけ乗る**割の
  合わないスライス（`syncFromScene` の毎フレーム再 mirror で World は翌フレーム上書きされ、権威は見かけだけになる）。
- read-model でも `World.tickStatuses` / `syncStatusesToScene`（逆向き write-back）は **保持**（セーブ復元・将来の flip 余地）。

---

## §B0. 最重要原則：既存ロジックは再実装せず「昇華」して再利用する

**過去の資産を必ず生かす。一から書き直さない。** 機能が必要になったら、まず既存実装を探し、見つかったら
**再利用または昇華**する。新規実装は「既存に無い」と確認できた時だけ。

**探す順**: (1) `examples/fe_rogue` の純粋層（`Board`/`Encounter`/`EnemyAI`/`Combat`/`StatusSystem`）→
(2) engine の純粋関数（ノードに埋まっていても可）→ (3) lib `flix_engine_ecs` → 無ければ新規。

**昇華（elevate）の型**:
- fe_rogue の純関数 → **アダプタ経由で System として再利用**（ロジックは書き換えない）。
- engine の **ノード由来ロジック** → ノードから切り離して再利用。障壁は2種:
  - **(a) 既に pub＋純粋** ＝ 呼ぶだけ（engine 改修ゼロ）。
    実例: lib `Collision` ← engine `CollisionShape2D.checkOverlap`、lib `Render` ← `Label2D.toDrawables`。
  - **(b) pub だが effect 依存**（ノード/registry 結合）＝ **effect を引数注入で外す純粋化 refactor（engine 改修＝要相談）**。
    実例: `EngineNode.spriteToDrawable` は既に pub だが `\ GameEngine.Game`（texture registry で UV/atlas サイズを引く）。
    `texSize` を引数注入して純粋化すれば lib が再利用でき、現状 `Render` が `bug!` で落として再実装している
    region 描画を吸収できる。← **(b) の昇華が未了ゆえ再実装が起きている実例**。
- 汎用なら **lib に昇華**（実証後）、ゲーム固有なら **System／ゲーム内**へ。

**engine 改修を伴う昇華**（(b) の effect 除去 refactor 等）は **事前相談**。ただし“ゼロから書き直し”ではなく
“既存ロジックの公開／抽出／effect 除去”であることを明示する。

**再利用ノート（各ステップ必須の成果物）**: 「どこを探したか／ヒット・不発／再利用・昇華・新規のどれをなぜ選んだか」
を1段落で §G に記録する。**ゲートはこのノートの有無と妥当性を確認**（自己申告でなく証跡で車輪の再発明を防ぐ）。

---

## §B. 移行プレイブック（strangler-fig＝壊さず差し替え）

**原則: 走っているゲームを一度も壊さない。** World を scene-tree と **並走導入** し、サブシステム単位で
正を移し、**parallel-run で一致検証してから切替**。

**ステップ・テンプレート（繰り返し単位）**
1. 次のサブシステムを選ぶ（ECS 価値 × 低リスクで順序付け）。
2. **再利用調査（§B0 必須）**: 該当ロジックが fe_rogue 純粋層 / engine（ノード由来含む）/ lib に既にあるか探し、
   再利用・昇華の計画を立てる（書き直し禁止）。→ 再利用ノートに記録。
3. その component store を World に足す（初回は World を新設）。
4. サブシステムを System（`World -> World`）化（既存純関数をアダプタ経由で再利用。engine ノード由来は §B0 で昇華）。
5. **parallel-run**: 毎フレーム「World 派生の結果」と「現行 scene 派生の結果」を両方計算して**一致を assert/log**。
   ゲームは従来 scene 経路のまま＝挙動不変で同値を実証。
6. **正を切替**: そのサブシステムを World 読み書きに。表示は World→scene sync。scene 派生経路（と足場 mirror）を削除。
7. **ゲート**（全部緑で次へ）:
   - `./bin/flix build` / `./bin/flix test` 緑、**実機 `./bin/flix run` でプレイ可**。
   - parallel-run クリーン（一致）／決定論テスト追加。
   - **再利用ノート確認**（既存を再利用したか・再実装していないか）。
   - レビュー役 **90 点以上**。
8. §G 進捗を更新（チェック／次の一手／決定ログ／再利用ノート／**ロールバック手順**）。

**parallel-run の決定論規約**
- **乱数を消費しうる全 System**（`Combat` の hit/crit、`EnemyAI` の tie-break 等）は、両系を独立計算すると
  roll を二重に引いて不一致になる。→ **roll 非依存の決定的部分で一致を見る**（例: S2 は実ダメージでなく
  `Combat.estimate`/`willKill`、S6 は roll 前の決定的選択）か、**同一 roll を両系に手渡す**。
- **roll の単一供給点**: 同一 roll を共有する場合、供給元は既存の `Math.Random` ハンドラ（`Game.start` の Ref）。
  新しい RNG を作らない。
- **snapshot タイミング**: `Encounter` には frame-head（`sceneRef`）と mid-frame（driver が mutation 済み）の
  2 読み口がある（`EnemyTurnDriverScene` は敵 step 内で board 再構築）。→ **呼び出し点ごとにいつ snapshot を取るか
  を区別して比較**（偽陽性/偽陰性回避）。
- **サブシステム別の比較対象**: §D の各ステップ参照。

---

## §C. 再利用ツールキット（lib `flix_engine_ecs`）と sync 層

| lib モジュール | fe_rogue での扱い | 理由 |
|---|---|---|
| `EntityId` | **即** | `type alias = Int32`。PlayerData/EnemyData の id と無摩擦 |
| `Query`（with2/updateWith2） | **World store 成立後（S1+）** | `Map[EntityId,_]` 前提なので「即」ではない |
| `EcsCodec`（encodeStore 等） | **store 化後（S7）に封筒分だけ** | 一般化は store エンベロープ＋id set/option のみ。FloorSnapshot のネスト codec（Stats/Plan/Status/idDur）は手書き継続。「ほぼタダ」ではない |
| `Motion` | 不使用 | グリッド・速度積分なし |
| `Render` | 不使用 | scene-tree 描画ゆえ sync 層で代替 |
| `Collision` | 不使用 | 占有判定は `Board.isOccupied` で足りる（broadphase 過剰） |
| `Clock` / `Viewport` | 不使用 | ターン制ゆえ dt アキュム・画面外判定が盤面に不要 |

- **グリッド座標は新規不要**: `engine_core.Vec2i`（add/sub/eq/zero/up/down/left/right/toVec2/fromVec2Floor）が既存で、
  fe_rogue が既に 13 ファイルで使用中。**既存 Vec2i を再利用**（`GridCoord` 新規は作らない）。
- **survey 済みで排除した昇華候補（再 derive 防止のため記録）**: engine `RayCast2D` の private セグメント幾何
  （`segmentIntersectsShape`/`segmentIntersectsAABB`）はノード由来の純粋幾何だが、射程/視線は `Board` で足りるため不要。
  `PhysicsStep`（Scene 結合＋連続物理）も不要。
- **新規汎用候補（fe_rogue 内 spike → 実証後 lib 抽出）**: `TurnQueue`（actor 順序、現状 `EnemyTurn.Queue` 手書き）、
  `Query.withFaction`（faction フィルタ join、現状 `Encounter.enemiesOf/alliesOf`）。早すぎる抽象化を避け、まず fe_rogue 内に置く。

**sync 層の形**: `syncTreeFromWorld(world, scene)`（World→node 位置/HP 等を書く）＋ Tween/Anim を effect facade 化。
既存の `PartyQuery`/`RosterQuery`/`BoardQuery` は **既に effect facade**で、handler が scene 実体に委譲している
（例: `Game.flix` `def board(k) = k(BoardSnapshot.fromScene(...))`）。**handler を scene→World に差し替えるだけで
呼び出し側は不変**＝強い seam。

---

## §D. fe_rogue ロードマップ（順序・seam に基づく）

> **順序の肝**: `Board` ＝ map ＋ **駒位置** なので、**gridPos が World に入る前に Board を fromWorld 化できない**。
> よって「位置 store を World に足す（S3）→ Board を fromWorld 化（S4）→ 位置の正を切替＆ノード sync 化（S5）」と
> **役割を分離**する。S3 の間は scene→World の **一時 mirror（足場・S5 で撤去）** で World gridPos を scene と一致させる。

- **S0 足場**: 最小 World＋World↔scene sync の骨組み（自明な1フィールドを並走 sync）。ゲーム不変。seam を確立。
- **S1 StatusSystem（✅ read-model で完了）**: statuses を World store に mirror、`tick` を System 化（`tickStatuses`）、
  逆向き write-back（`syncStatusesToScene`）まで。**権威は scene のまま（read-model 据え置き決定）**。flip はしない。
- **S2 Combat HP（read-model mirror）**: hp を World store に mirror（statuses と同型）。**権威は scene のまま**＝
  scene の `Combat`/HPBar 経路は無改修。World hp は query/セーブ/決定論テスト用。比較=World hp == scene hp。位置非依存・最低リスク。
- **S3 位置 store を World に追加（ノードは依然 writer）**: gridPos を World store に持ち **scene→World mirror** で同期。
  **mirror は frame-head＋各 mid-frame mutation 直後にも発火**（EnemyTurnDriver が敵 step 内で位置を mutate するため。
  さもないと S4 の fromWorld が stale を読み割れる）。比較=World gridPos == scene gridPos。挙動不変。
- **S4 Board/Encounter を fromWorld 化**: `fromScene`→`fromWorld`。**約15 呼び出し点を1点ずつ切替**
  （BoardSnapshot.fromScene 13＋EncounterBuilder.fromScene 2 = StaffCast×5・StairsExit×3・Combat×2・Range×1・
  EnemyTurnDriver×3(Board1+Encounter2)・`BoardQuery` handler×1）。各点で frame-head/mid-frame の snapshot タイミングを保つ。
  **ロールバックは call-point 単位**（割れた点だけ `fromWorld`→`fromScene` に個別復帰）。比較=`Board.pieces`(順序込み)・`distanceField`。
- **S5 位置の正を World に切替**: ノードを sync 派生に。**移行阻害の本丸＝`Tween.tweenPosition(targetPath: NodePath, …)`
  の NodePath 結合**を effect facade で切る（`moveUnit(id, from, to, dur)` の eff を介して World が Tween を駆動）。
  **数フレーム並走で World-writer と scene-writer の node 位置一致を検証してから** S3 の足場 mirror を撤去。
- **S6 EnemyAI**: `decideAction` を World 駆動キューに（`TurnQueue` spike）。比較=同 Encounter・同一 roll での Action 値。
- **S7 セーブ**: store を component-map 化し EcsCodec の封筒を利用（ネスト codec は手書き継続）。FloorSnapshot を簡素化。
- **メニュー（Item/Trade/Action）は全工程で tree のまま**（移行しない＝ECS が弱い領域）。

---

## §E. 完成の定義（このプロジェクトが「調和した形」と言える条件）

- シミュレーション状態の正が World に一本化され、scene-tree はその派生ビュー（描画＋UI）になっている。
- ゲームロジックが System（`World -> World`）で表され、fe_rogue の既存純関数がアダプタ経由で再利用されている。
- セーブ＝World のシリアライズ（決定論リプレイ・スナップショットが容易）。
- メニュー UI は scene-tree で、World とは「表示は sync・操作はコマンド」で疎結合。
- 既存ロジックの再実装がゼロ（再利用ノートで証跡）。
- **どの新規プロジェクトもこの形（World＋System＋sync＋tree-UI）を初手から採れる**ことが、dodge と fe_rogue の2例で示されている。

---

## §F. 既知の落とし穴（Flix / engine 固有）

- 予約語をフィールド/変数名に使わない: `region`/`spawn`/`select`/`eff`/`project`（パースエラー）。
- レコード丸ごとの `assertEq` は ToString 不在で不可 → スカラフィールドで assert。
- engine/src 編集後は `make sync-engine` 等で fpkg を再ビルド＆symlink（examples は fpkg 経由）。lib 編集は `make sync-engine-ecs`。
- `def` パラメータに無名レコード型注釈を使うとパースが不安定 → フラットな個別引数にする。
- fe_rogue の full build は肥大テストで `MethodTooLargeException` になりうる → 型/effect 検証は `./bin/flix check`。

---

## §G. 進捗（living・各ステップ完了で更新）

**現在ステップ**: **S4 Board/Encounter fromWorld 化の検討**（S1・S2・S3 は read-model mirror で完了・非破壊）
**次の一手**: **S4 はまず判断から**。位置は S3 で World に mirror 済み。ここで初めて「読み込み経路（`BoardSnapshot.fromScene`→
`fromWorld`）を World 由来に切替える」＝ECS の旨味（query/決定論/巻き戻し）が出る**最初の権威 flip 候補**。ただし read-model 戦略では
**旨味とコストを call-point 単位で都度判断**する。**肝**（§D）: 位置は `EnemyTurnDriver` が敵 step 内で mid-frame mutate するので、
fromWorld 化するなら **mirror の発火を frame-head だけでなく mid-frame mutation 直後にも**入れて stale を防ぐ（さもないと割れる）。
**着手前にユーザーと旨味/リスクを確認**（read-model のまま query だけ World で享受する手もある）。

### チェックリスト
- [x] S0 足場（最小 World＋sync 骨組み）— `examples/fe_rogue/src/ecs/World.flix`、gameLoop に thread、build＋test 859緑、ゲート88→§G更新で90+
- [x] **S1a** StatusSystem store＋mirror＋System（**非破壊**）— `World.flix` に `playerStatuses`/`enemyStatuses`（faction 別＝id 衝突回避）、`syncFromScene` で mirror、`tickStatuses`（`StatusSystem.tick` 再利用）。build＋test **862緑**（`TestWorld.testSyncMirrorsStatuses`/`testTickStatuses` 追加）。World は依然 render/scene 無影響
- [x] **S1b write-back＋parallel-run 実証**（**非破壊**）— `World.syncStatusesToScene`（逆向き矢印・`PlayerScene.mapPlayer`/`EnemyScene.mapEnemy` 再利用）追加。test **864緑**（`testSyncStatusesToSceneRoundTrip`／**`testTickParallelRunMatchesScenePath`**＝World 経路と scene 経路が同残ターン）
- [x] **S1 完了（read-model 据え置き）** — statuses は scene 権威のまま、World は mirror＋System＋write-back を保持。**tick の権威 flip は不採用**（決定 2026-06-26・§A 採用戦略）
- [x] **S2 Combat HP（read-model mirror・非破壊）** — `World.flix` に `playerHp`/`enemyHp = Map[EntityId, Int32]`、`syncFromScene` で hp mirror。**権威は scene のまま**＝`Combat`/HPBar 無改修。test **866緑**（`testSyncMirrorsHp`／`testHpMirrorEqualsScene`＝World hp == scene hp）
- [x] **S3 位置 store（read-model mirror・非破壊）** — `World.flix` に `playerPos`/`enemyPos = Map[EntityId, {x=Int32,y=Int32}]`（Vec2i structural record）、`syncFromScene` で gridPos mirror。**権威は scene のまま**。test **868緑**（`testSyncMirrorsPos`／`testPosMirrorEqualsScene`＝World pos == scene gridPos・Vec2i.eq）
- [ ] **S4 Board/Encounter fromWorld 化**（位置を World 由来に。初の権威 flip 候補・約15 call-point。読み込みは此処で初めて旨味が出る）
- [ ] ~~S1b-flip~~（不採用）
- [ ] S2 Combat HP
- [ ] S3 位置 store 追加（mirror）
- [ ] S4 Board/Encounter fromWorld 化（15 点）
- [ ] S5 位置の正を World に切替（mirror 撤去）
- [ ] S6 EnemyAI World 駆動
- [ ] S7 セーブ（store 化＋EcsCodec 封筒）

### TODO（道標の整備）
- [x] `CLAUDE.md` に本 doc（`ECS_WORKFLOW.md`）への参照を追加済み（「ECS ハイブリッド移行」節）。

### 決定ログ
- **S1 read-model 据え置き（2026-06-26）**: statuses の権威を World に flip しない。理由＝tick 発火点が
  `EnemyTurnDriverScene`（Tween/AnimationPlayer/TurnPhase effect 内）深部で World 不在→flip は driver 大改修が必要なのに、
  `syncFromScene` の毎フレーム再 mirror で挙動ゼロ変化（権威は見かけだけ）。**read-model 先行**戦略に変更（§A 参照）。
  以後 statuses/hp 等の「scene 側が既に綺麗」な subsystem は mirror のみ、flip は位置/AI/セーブ（旨味大）だけ都度判断。
- **S0**: World は gameLoop に**値引数で thread**（dodge と同型。fe_rogue 既存の Ref 群とは別に）。sync は
  描画される `next`（phase 遷移後のリビルド済みシーン）から取る（`updated` でなく `next`＝遷移フレームも追従）。
  World→scene の **write 方向は入れない**（S0 は read-only mirror、World は無権限）。write は S1（hp/status）から。

### 再利用ノート（各ステップで追記）
- **S0**: `EntityId`（lib `flix_engine_ecs` の `type alias = Int32`）を再利用＝新規 id 型を作らない。
  scene 走査は `PlayerScene.getAll`/`EnemyScene.getAll`（既存・純粋）に委譲＝新規走査を再実装しない。
  新規ロジックはゼロ（World 型と sync 配線のみ）。fe_rogue に lib 依存追加（flix.toml＋`make sync-engine-ecs`）。
- **S1a**: 時限効果ロジックは `StatusSystem.tick`（`src/game/StatusSystem.flix:56`・純粋）を `Map.map` で
  store 全体に適用＝**再実装ゼロ**。Status 型も `StatusSystem.Status`（既存 type alias）をそのまま store の値型に。
  combatMods/isImmobilized も S1b で既存関数をそのまま呼ぶ前提（再実装しない）。新規は store の器と mirror 配線のみ。
- **S1b（write-back）**: World→scene の書き戻しは既存純粋 writer `PlayerScene.mapPlayer`（:585）/`EnemyScene.mapEnemy`（:360）を
  `Map.foldLeftWithKey` で畳むだけ＝**走査も書込も再実装ゼロ**。scene 不在 id は mapPlayer/mapEnemy が no-op で読み飛ばす。
  読み側（combatMods/isImmobilized 計 7 site）は scene Data#statuses を読むまま＝write-back が faithful mirror である限り**無改修**。
- **S2（hp mirror）**: `getAll`（既存・純粋）の `Data#hp`（PlayerData:84/EnemyData:30・既存 Int32 フィールド）を `Map.insert` で
  畳むだけ＝**新規走査・新規 hp ロジックなし**。damage 計算は scene の `Combat`（既存）が引き続き担い、World は読むだけ。再実装ゼロ。
- **S3（pos mirror）**: `Data#gridPos`（既存 `{x=Int32,y=Int32}` structural record）を mirror。新規座標型は作らず、比較は
  既存 `Vec2i.eq`（engine_core）を再利用（record の == 不可のため）。新規走査・新規位置ロジックなし＝再実装ゼロ。

### ロールバック手順（各ステップで追記）
- 共通: 切替後に parallel-run が割れたら、そのサブシステムを scene 経路へ即戻す（World 並走は残す）。
  S4 は call-point 単位で `fromWorld`→`fromScene` に個別復帰。
