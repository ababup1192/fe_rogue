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

> ## ★★ 全体ワークフロー（S0-S10 連番・並列レーン付き・2026-06-29 再採番）★★
> 旧 D0-D15 採番の枝番/ギャップを解消し、**依存順に並べ直した単一スパイン**。新セッションはまずこの地図で現在地（下の状態マーカー）と「同時に走らせてよいレーン」を確認する。
>
> **凡例**: `═` 主クリティカルパス(厳密順) ／ `→` データ依存(後続必須) ／ `∥` 並列レーン(独立・同時可) ／
> `⚠FC` 論理独立だが**同一ファイル編集→マージ衝突**ゆえ worktree 隔離 or 直列 ／ 状態 `✅`完了 `🟡`実行中 `⬜`未着手
>
> ```
> 【主レーン ＝ A 完成までのクリティカルパス】
> S0✅═S1✅═ S2 ═ S3 ═ S4 ═ S5 ═ S6 ═ S7   ★★A完成（§E DoD・「ECS化達成(A)」宣言）★★
>            store status flip  faction menu  bridge
>                        /compose /turn /sync teardown
>
>   ├ S2 ズーム（store 化・⚠FC: 全部 World.flix store 機構を触る → 直列 or worktree 隔離）
>   │   S2.0✅ dead-code/design pin (旧D0/D1)
>   │   S2.1✅ weapons          (旧D3・コミット済)              ┐
>   │   S2.2🟡 inventory staves/consumables/rings/ringEquipped (旧D4) ┤ S2.1/2/3/5 は
>   │   S2.3⬜ stats baseStats  (旧D5)                          ┤ 互いに論理独立(並列可)
>   │   S2.5⬜ moveTiles micro  (旧D6.5)                        ┘ ただし⚠FC
>   │   S2.4⬜ projection currency (旧D6) ──→ (S2.1 & S2.2 に依存=weaponView/ringBonus 投影)
>   │
>   ├ S3⬜ statuses 権威移送(atomic) (旧D12) ← reader-flip の前提ゆえ前倒し(cascade map で確定)
>   │
>   ├ S4 ズーム（reader-flip + compose・データ依存で半順序・全 store(S2+S3) 完了が前提）
>   │   S4.1⬜ unitView World twin (旧D7) ─┬→ S4.2⬜ combatView flip (旧D8) ─┐
>   │                                      └→ S4.3⬜ Encounter flip★hub (旧D9)┴→ S4.4⬜ dataFromWorld compose★最高リスク (旧D10)
>   │                                          (S4.2 ∥ S4.3 同時可)
>   │
>   ├ S5⬜ faction-blind + turn-state (旧D13a-e): acted/usedStairs micro-store・spawn funnel・move/tick 統合・attack policy merge
>   ├ S6⬜ menu/render flip + syncTreeFromWorld teardown (旧D11a-c)
>   └ S7⬜ bridge teardown + DIFF検証器 teardown (旧D14/D15) = EntityScene/EncounterBuilder/refreshMirror read枝/syncTree 物理撤去
>
> 【並列レーン（主レーンと同時に走れる＝本物の並列益）】
>   ∥ R: 調査レーン(read-only・いつでも・編集ゼロ＝競合なし)
>        cascade map✅ → ~/.claude/plans/phase-d9-d10-cascade-map.md
>        B評価✅      → ~/.claude/plans/phase-b-eval-node-tree-removal.md
>        └ S9⬜ B評価ゲート(ActionMenu 1個を試験実装し規模実測) ※A完成前でも資料化は可
>   ∥ SAVE: S8⬜ Save の ECS 化(World 直列化) ── S3 完了後に分岐し S4〜S7 と並列可
>            (reader-flip 非依存＝store さえ揃えば独立。旧「S7 セーブ」)
>
> 【A 完成後・条件分岐】
>   S7(★A) ─→ S10⬜ B 実行(node tree 撤廃・render-from-World・engine 改修要相談) ─→ ★★B完成(純ECS・重複②撲滅)★★
>              ↑ S9(評価OK) が前提
> ```
>
> ### 並列で「本当に得する」ペア（実務指針）
> | 並列ペア | 種別 | 実行方法 |
> |----------|------|----------|
> | **S8(Save) ∥ S4〜S7** | 論理独立（Save は reader-flip 非依存）| store(S2+S3) 完了後にいつでも分岐＝**真の並列益** |
> | **R レーン(調査) ∥ 全工程** | read-only | Explore agent で随時（cascade/B評価は実施済） |
> | **S2.1/2.2/2.3/2.5 同士** | 論理独立だが ⚠FC | worktree 隔離で物理並列可だが World.flix store 節で**衝突ほぼ確実**→**直列が無難**（1つずつ run 検証の discipline とも整合） |
> | **S4.2 ∥ S4.3** | 半順序(S4.1 後) | 同時可 |
>
> ### A / B の位置（要点）
> - **A = S7 終点**: scene-tree は render 層として残すが **sim 権威は完全に World**（重複①消滅）。ここで「ECS 化達成」宣言。
> - **B = S9(評価)＋S10(実行)**: scene tree 自体を撤廃し render-from-World 化（重複②撲滅）。engine 改修 9〜13 週・IDE scene 編集喪失ゆえ **A 完成後にゲート判断**（B評価リサーチ済）。
> - **S8(Save) は A 完成後の独立スライス**だが store 完成後なら前倒し並列も可。
>
> ### 旧→新 採番対応（取りこぼし防止）
> D0/D1→S2.0 ／ D3→S2.1 ／ D4→S2.2 ／ D5→S2.3 ／ D6→S2.4 ／ D6.5→S2.5 ／ **D12→S3(前倒し)** ／ D7/D8/D9→S4.1/4.2/4.3 ／ D10→S4.4 ／ D13a-e→S5 ／ D11a-c→S6 ／ D14/D15→S7 ／ 旧S7(save)→S8 ／ Phase B→S9/S10。
> **主な是正**: ① statuses(旧D12) を reader-flip の**前(S3)**へ（cascade map で「S4 は statuses store が要る」と判明）。② 枝番(6.5/a-c/a-e)を単一ステージへ畳む。
>
> ### 現在地（2026-06-30）
> S0✅ S1✅ S2.0-2.5✅(🎉S2 store) S3✅(statuses) **S4✅実質完了(twin 層 全達成)**: S4.1✅(unitView) S4.4✅(PlayerData) S4.4b✅(EnemyData) +proj refactor✅ run検証batch✅(twin parity 実証)。S4 残は**非ブロッカー**: S4.2=低価値 skip / S4.3a=コード済・敵ターン run 検証待ちのみ / S4.3b=optional(他 unitView 消費者・あれば)。
> **▶ いま: 「reader-flip 仕上げ」レーン（S4→S6/S7 橋渡し・syncTreeFromWorld build-out）** ── ⚠採番注記: これは spine の S6(menu/render flip)とは別物。§A「軸1=sim 状態→World 権威」は dual-write で既達(368行)、その**後半=scene 直書き撤去＋syncTree derive**を field 単位で消化中。前提(S2 store/S3/S4 twin)は揃い済ゆえ S5/S6 本体より先行して良い(半順序)。
>   - 済: gridPos✅ hp✅ isDying✅ alerted✅ waited✅ bottleUsed✅ followUpUsed✅(両 faction) prevPos✅(敵・dead-read だが refreshMirror clobber 防止に syncTree derive 必須)
>   - **attackTargetId = flip 不可と判明・dual-write 据置が end-state（2026-06-30 検証）**: flip 試行→golden 5 本 fail で根本判明。`testResolveCounterChainEqualsLegacy` 等が示す通り **attackTargetId は単なる sim 状態ミラーでなく combat 解決の「作業レジスタ」**＝`startAttack`(set)→`attack:hit`(read)→`onLungeDone`(counter 判定 read) を **synchronous シーケンス内**で scene 経由 thread する（実ゲームは animation で multi-frame だが、解決オラクル/同期テストはフレーム境界・drain・syncTree なしで scene を同期キャリアに使う）。World へ倒しても同期パスは drain 前で None ＝直らない。**残る scene reader 8(CombatScene 6=解決/BattlePanel 2=view) は全て正当なキャリア役**。driver の `anyAttacking` は World 化済(F8-slice1)で**論理的真実源は World・scene は同期作業コピー**。⇒ **attackTargetId は dual-write のまま・`[ATTACKTARGET DIFF]` 維持**。reader-flip レーンの対象外。
>   - **attackTargetId 卒業条件 = Phase C/S7 の純 resolve 一本化**: ECS化(A)は attackTargetId を flip せず成立する（永続 sim 状態でなく combat 解決の transient 作業レジスタ・横断意味の `anyAttacking` は World 権威済・scene は同期作業コピー）。消す代替は (a)純パラメータthreading=❌animation-event 境界を payload で越えられない / (b)reader→World+同期drain=△legacy seam と衝突 / **(c)純 `CombatSystem.resolveAttack`(既存・explicit ref・scene 非読み)+event-replay へ一本化=⭐本命**。今 scene の attackTargetId を消費するのは animation コールバック駆動オーケストレーション(legacy 寄り)のみ。これが「純 resolve→SimEvent→ViewReplay 再生」へ完全移行すると解決が target を scene から引かなくなり attackTargetId は dual-write ごと**自然消滅**。⇒ Phase C/S7 まで dual-write が honest な中間状態。
>   - **🎉 reader-flip レーン収束完了（2026-06-30）**: command-derive/read-model フィールドの「scene 権威→World 権威・scene 派生」化は全消化。残る dual-write は attackTargetId（combat 解決の同期キャリア＝Phase C/S7 で自然消滅）のみで、これは flip 対象外と確定。**次は構造フェーズ S5/S6本体/S7 へ**。
> S5⬜(faction-blind+turn-state) S6⬜(menu/render flip 本体) S7⬜(bridge teardown=★A完成) S8⬜(Save・並列可) S9(調査一部✅) S10⬜。1063緑。
> - **followUpUsed✅（2026-06-30・1063緑・両 faction）**: 追撃二重発動フラグ。reader(CombatScene:267/380)は既に World 優先・EffectFlow は ctx 経由の純関数(scene 非読み)・emit 全6サイト既存。**重要観察: reader は `followUpUsedOf(world) |> getWithDefault(scene)` で World が `Some(false)` を返せば scene マークを無視→ scene 直書きは既に実質 dead**＝安全に撤去。残=直書き4撤去(PlayerScene:931/EnemyScene:448 の combined update から followUpUsed のみ除去〔waited/acted/statuses は維持〕＋CombatScene:235/354 の mark→`scene` 直渡し)＋syncTree derive(統合マップ `w#followUpUsed` を `uidToRef` で両 faction 分配)＋`[FOLLOWUP DIFF]` 撤去。**run 検証待ち**: 追撃が 1 回で止まる(二重追撃しない)・ターン開始でフラグ復帰。
> - **S5 着手: usedStairs World store 化✅（2026-06-30・1063緑・additive）**: 味方階段退場フラグ（フロア終了条件・tick gating の権威）を `playerUsedStairs` store に昇格（playerWaited 同型・player-only Bool）。store 定義/init/refreshMirror re-mirror/prune/`Cmd.SetUsedStairs`/applyCmd/trace/`usedStairsOf`/`usedStairsMismatches`/`[USEDSTAIRS DIFF]`＋useStairs(:1126) に dual-write emit。**reader(PlayerScene:922/974 tick filter・:1132 フロアクリア)は scene 据置＝additive**（flip は後続）。faction-blind tick の前提（TickPlayers が scene usedStairs で filter→World 化で faction-blind 化の道）。**run 検証待ち**: 階段退場→敵ターン跨ぎで退場維持・全員退場でフロアクリア。次の S5 候補=acted store(view-only)・spawn funnel・move/tick 統合。
> - **reader-flip パターン確立（waited→bottleUsed→followUpUsed・S4→S6/S7 橋渡し）**: command-derive/read-model フィールドを「scene 権威→World 権威・scene 派生」へ 1 つずつ flip。手順=① reader を World 優先(`World.xxxOf |> getWithDefault(scene)`)へ ② Cmd emit を全 write サイトに ③ **scene 直書きを撤去**（init record 値は残す）④ **syncTreeFromWorld に derive 追加**（撤去後 scene が World 追従＝re-mirror clobber 防止）⑤ flip 完了で `[XXX DIFF]` 検証器撤去（`xxxMismatches` def は dead code 残置・後でまとめて掃除）。refreshMirror の `Query.indexBy` 行は触らない。
> - **bottleUsed✅（2026-06-30・1063緑）**: 敵瓶使用フラグ。reader(EnemyTurnDriverScene:260)は既に World 優先・emit/store/verifier 全既存ゆえ残=直書き撤去(`:270`)＋syncTree derive(alerted と同型 `w#enemyBottleUsed`)＋`[BOTTLE DIFF]` 撤去の 3 edit のみ＝最クリーン flip。**run 検証待ち**: 敵が瓶/水投擲後に再投擲しない。
> - **S4.3a(hub flip): `EncounterBuilder.fromBoardQuery` を flip**。EnemyAI 入力の units を `PlayerScene/EnemyScene.unitView`(scene) → **`World.unitViewFromWorld`(検証済み twin)** から組む＝**EnemyAI 入力が World 由来に**。effect cascade は **`bumpedDarkRoomEnemy` に `World.WorldQuery` 1 行追加で閉じた**（cascade map の「EnemyAI pure ゆえ浅い」予測どおり・他 caller は既に WorldQuery 保持）。1063緑。
> - **⚠ run 検証ポイント**: twin は frame-end で scene 一致を実証済みだが **EnemyAI は mid-frame に Encounter 使用**。flip 前 units=scene(移動中 gridPos 1 フレーム遅延し得)/board=World、flip 後 **units も World=board と整合**（むしろ整合性↑）。だが mid-frame 挙動は frame-end DIFF 非検証ゆえ、次 run 検証で**敵ターン挙動（移動/追跡/攻撃/かなしばり）を重点確認**。
> - **S4.2(combatView フォールバック除去) は skip 判断**: combatViewOf は既に primary reader・fallback は live 非発火の安全網で正当・残る scene 直読みは combatViewWith(明示武器 forecast)で World 等価無く flip 不可＝低価値。D2 同様 no-op 寄り。
> - **🎉 S2.3〜S4.4b の run 検証 batch 完了（実機）**: store 系 DIFF（BASESTATS/WEAPONVIEW/RINGBONUS/MOVETILES/STATUSEFFECTS/WEAPONS…）は全て無音＝**下層ストア正しい**。
> - **⚠ twin DIFF（UNITVIEW/PLAYERDATA/ENEMYDATA）が当初発火→診断で原因特定→是正**: 一時 field 診断で **`gridPos` 確定**（W=World pos が常に S=scene gridPos の 1 マス先・静止で消える）。**根本原因＝twin DIFF 検査が `syncTreeFromWorld` の*前*に走っていた**（syncTree が scene gridPos を World pos から derive するのは検査の後＝1 フレーム遅延の良性 false-positive。hidden/equippedRing も refreshMirror 前で re-mirror stale）。**twin 自体は正しい**（World pos が権威）。**fix＝3 つの twin DIFF 検査を refreshMirror＋syncTreeFromWorld の後(`world2`/`synced`)へ移動**（World 派生フィールドは一致・dual-write 系〔syncTree 非派生〕は scene が process 値ゆえ coverage 維持）。→ 全 twin DIFF 無音を実機確認。**教訓: World→scene 派生フィールドの twin parity 検査は post-syncTree に置く**。
> - **🎉 twin parity 実証完了＝S4.2/S4.3 の flip に安全に進める**（twin が scene と bit 一致を実機で確認済み）。
> - **S4.4b(EnemyData twin) = additive な World 由来 EnemyData.Data(17 field) compose**。`World.dataFromWorldEnemy(id, world, scene)`＝W12(accessor・enemy weapon=weaponsOf head/ring=equippedRingOf〔P1a both-faction〕)＋R残置3(resource/resourceId/homeModuleIdx)＋S→W未昇格1(acted)。`enemyDataKey` は**proj refactor の正準キー(posKey×2/weaponKey/equippedRingKey/statusListKey)を sub-key 再利用**＝バグ class 再導入なし。`[ENEMYDATA DIFF]`・消費者 flip せず additive・review 93/95/90・1063緑。**⚠ TODO**: enemyDataKey は resource を resourceId で代理(R残置ゆえ今は drift 不能)・S6 で resource が World 派生化したら parity 穴になるので要再訪。
> - **🎉 additive twin 層 完成（unitView/PlayerData/EnemyData 3 twin・両 faction）**＝**scene を World から再構築する材料が全部揃った**（S6 syncTreeFromWorld で両 faction の scene 派生 / S7 bridge 撤去＝A 完成 の土台）。
> - **⚠⚠ ここで additive の安全 runway が尽きた**: 残る S4.2(combatView フォールバック除去)・S4.3(消費者 flip)・S5/S6/S7 は**全て reader を World へ切り替える flip ＝大区切りの run 検証が前提**。**次の自然な節目 = run 検証バッチ**（S2.3〜S4.4b の全 `[... DIFF]` 無音を実機確認）。
> - **検証器 proj 集約 refactor（横断改善・意味保存）**: World.flix の検証器 ~18 個の inline proj 射影を**型ごと monomorphic な正準キー 22 本**(weaponKey/staffKey/.../headKey 高階/posKey/combatViewKey…)に集約。**weaponsMismatches と playerDataKey が同一 weaponKey 共有＝S2.4/S4.4 の「重複射影 drift→弱い方が DIFF 盲目化」バグ class が構造的に再発不能**に。★near-duplicate 対(weaponViewKey 8≠weaponViewCombatKey 6・ringKey≠equippedRingKey)は誤マージせず別 def 共存(テスト pin)。意味保存(既存 mismatch テスト全緑=DIFF byte 不変)・MANDATORY 9 テスト追加・1058緑。review 90/92/92。計画=`~/.claude/plans/proj-refactor-plan.md`。run 検証中立(DIFF 値不変)。
> - **S4.4(dataFromWorld) = additive な World 由来 PlayerData.Data(23 field) compose**。`World.dataFromWorld(id, world, scene): Option[PlayerData.Data]`＝W ストア14(posOf/hpOf/waitedOf/attackTargetOf/progressOf分解/followUpUsedOf/weaponsOf/stavesOf/consumablesOf/ringsOf/ringEquippedOf/moveTilesOf/statusEffectsOf/playerHiddenOf)＋R残置5(classId/resource/selectedItem/facing/pendingLevelUp)＋S→W未昇格2(moveStepsTaken/usedStairs=scene)。`playerDataMismatches`(23 field 射影)＋`[PLAYERDATA DIFF]`。**消費者 flip せず additive**。review 66/90/92。**S6(syncTreeFromWorld で scene を World 派生)/S7(bridge 撤去) の土台**。
> - **⚠ blocking を私が独立検証で修正**: playerDataMismatches の在庫 head 射影が `name` のみで durability/power を落とし sibling 検証器(weaponsMismatches=(name,durability) 等)より弱かった（head 武器 durability drift が [PLAYERDATA DIFF] 沈黙＝S2.4 length+head 取りこぼしの 4 field 版）→ sibling と同じ (name,durability)/(name,power) に揃えた。1049緑。
> - 設計注記(hybrid-A 由来・非bug): R残置7 field は twin が scene 読み＝両辺同一源で恒等一致ゆえ [PLAYERDATA DIFF] の検出価値は実質 **W 由来 ~15 field**。
> - **🎉 S4.1＋S4.4 で World-compose twin が 2 本(unitView/Data)揃った**＝scene を World から再構築する材料が出揃った。**残る S4.2/S4.3 は flip（reader を World 由来へ切替）＝run 検証が前提**（twin が scene と bit 一致を実機 DIFF 無音で確認してから）。
> - **⚠ S4 の flip は run 検証が前提**: S4.2(combatView フォールバック除去)・S4.3(unitView/Encounter 消費者 flip) は twin の bit 一致が前提＝`[UNITVIEW/PLAYERDATA/COMBATVIEW DIFF]` 無音を実機確認してから。**S2.3〜S4.4 が未 run 検証で堆積中＝flip 前に run 検証バッチ推奨**。
> - **S4.1(unitView World twin) = additive な World 由来 unitView**。`World.unitViewFromWorld(ref, world, scene): Option[UnitView]`＝pos/hp/moveTiles/weaponRange/combat/isDying/hidden を World ストア由来、**aiType だけ resource 残置**（player=Aggressive 定数/enemy=resource#aiType・hybrid-A 整合）、player effective-move は base(World)−積載(World 在庫 weaponsOf/stavesOf/consumablesOf/ringsOf から算出)。`unitViewMismatches`(全 10 field 射影)＋`[UNITVIEW DIFF]`。**消費者 flip せず additive**（CursorScene/WeaponSelect/ActionMenu/Combat は今も scene unitView 読み）。review 93/92/92・parity を field 単位で照合。TestWorld に 3 テスト。1046緑。
> - **⚠ S4 の flip は run 検証が前提**: S4.2(combatView フォールバック除去)・S4.3(unitView/Encounter 消費者 flip) は **twin が scene と bit 一致**することが前提＝**`[UNITVIEW/COMBATVIEW DIFF]` 無音を実機確認してから**でないと安全に flip できない。現在 S2.3〜S4.1 が未 run 検証で堆積中。**flip 前に run 検証バッチ推奨**。
> - **S3(statuses) = read-model→command-derive 権威**。`emitStatusesFromScene`(`Cmd.Seed` 全置換・read-after-mutate)を全 ~21 mutation サイト＋**tick 2 核(clearAllWaited:919→926・clearActedAll:448→454)**＋復元 2(placeOneFromSnap・restoreEnemyState)に co-locate。refreshMirror 再mirror→preserve。`combatViewOf` は既に statusEffectsOf を読むので preserve で**自動非 stale**。review 40/38/88。
> - **⚠ CRITICAL 2件を私が独立検証で発見・修正**（review が正しく捕捉・どちらもビルド緑をすり抜けるマルチフレーム実機バグ）: ① **per-frame 二重 tick** — `stepWorld`(World.flix:342)が毎フレーム `tickStatusEffects` を回す。preserve 化前は refreshMirror が scene から上書きして無害だったが、preserve 化で remaining が 60/sec 減り status が数フレームで消失→combatViewOf が buff/debuff 落とし `[STATUSEFFECTS DIFF]` 連続。**修正=stepWorld を identity 化**（ターン境界 Seed が唯一の権威 tick）＋ World.flix/Game.flix の陳腐化コメント是正。② **snapshot 復元の Seed 漏れ** — placeOneFromSnap(:1197)/restoreEnemyState(:702)が `statuses=snap#statuses` を書くが Seed せず、中断再開(in-loop phase change・fresh syncFromScene 無し・preserve)で非空復元 statuses が World に届かない。**修正=両所に emitStatusesFromScene 追加**（statusEffectsOf は空リスト返却ゆえ fresh/Nil spawn・reviveOneAt は safe と確認）。→ 1043緑。
> - **🎉 S3 完了で S4 の全前提が揃った**: combatViewOf の入力（baseStats/weaponView/ringBonus/hp/**statusEffects**）が全て command-derive＝mid-combat 非 stale → **S4.2(combatView reader-flip)に進める**。
> - **S2.5(moveTiles) = base 移動力 micro-store**（両 faction）。moveTiles は resource 由来で **spawn 後不変＝mutation サイトゼロ**（実効移動力は effectiveMoveTilesOf が encumbrance を読み時計算）→ dual-write は spawn seed のみ（player addOnePlayer:331 / enemy addOneEnemy:231）＝F6 級の網羅リスク無し。refreshMirror preserve・`SetMoveTiles`/`moveTilesOf`/`moveTilesMismatches`/`[MOVETILES DIFF]`・TestWorld に 4 テスト（preserve/empty/drift/apply）。**workflow でなく直接実装＋自己検証**（最小スライスゆえ）。
> - **🎉 S2 store フェーズ完了**: scene 権威だった全 combat-relevant field（weapons/staves/consumables/rings/ringEquipped/baseStats/weaponView/ringBonus/moveTiles）が World command-derive store に。combatViewOf の全 projection が command-derive＝**S4.2(combatView flip)の前提が完全に整った**。残 re-mirror read-model は equippedRing/growth/effectRule/mapSnapshot（combatViewOf 非経由 or 静的）。
> - **S2.4(weaponView/ringBonus) = projection read-model→command-derive store**（両 faction）。**既存 emit helper にピギーバック**（SetWeapons の所に SetWeaponView・SetRings/SetRingEquipped の所に SetRingBonus を 1:1 co-locate）でサイト網羅を構造的に保証。refreshMirror 再mirror→preserve(Map.filterWithKey)。review 93/90/72。golden cmd-stream に SetWeaponView 6 箇所追記（SimEvent オラクル不変）。**baseStats(S2.3)＋weaponView/ringBonus(S2.4) で combatViewOf の全 projection が command-derive＝S4.2(combatView flip)の前提が完成**。
> - **⚠ blocking(テスト規律後退)を私が独立検証で修正**: workflow が S2.3 で確立した「preserve 不変条件 pin＋verifier drift テスト」の双子を付け忘れ（World.flix:291/294 を Map.union に戻しても緑で通る穴）。TestWorld に 6 本追加（testRefreshMirrorPreservesCommandWeaponView/RingBonus＋weaponView/ringBonusMismatches の EmptyWhenSynced/DetectsDrift）→ 1039緑。
> - **未了**: equippedRing/growth は再mirror read-model のまま（combatViewOf 非経由ゆえ S2.4 対象外・後続の小スライスで preserve 化候補）。
> - **S2.3(baseStats) = read-model→command-derive store**。核心 = refreshMirror を再mirror(Map.union baseStatsFrom)→preserve(Map.filterWithKey)。これで combatViewOf が mid-combat stale でなくなり **S4.2(combatView flip)の前提が整う**。両 faction(toUid)・`Cmd.SetBaseStats`・`baseStatsMismatches`(BaseStats は Eq 無し→8-tuple 射影)・Game.flix `[BASESTATS DIFF]`・maxHp は emitHpSets/MaxHpUpAt funnel で併置。review 72/88/92。
> - **⚠ blocking 1 件を私が独立検証で発見・修正**: workflow は ECS 経路 level-up(CombatScene:558→561)だけ emit し、**legacy applyLevelUp(CombatScene:1121)が resource 成長後 `SetBaseStats` を emit していなかった**（hp/progress は :1115/:1117 で emit 済みだが baseStats だけ欠落＝F6 と同型の latent drift・useEcsCombat()=false に戻すと level-up で `[BASESTATS DIFF]`）。workflow の自己 audit grep が single-space `resource = ` で multi-space を取り零したのが原因。修正 = applyLevelUp 末尾に `emitBaseStatsFromScene`（:1126・ECS :561 と対称）。これに伴い legacy cmd-stream golden(`TestGoldenTrace.testGoldenLevelUp`)に `("SetBaseStats",0,21,10)` を追記（growthRates=0 で値不変だが emit は無条件＝SetWeapons が miss でも出るのと同型・SimEvent オラクル不変）。1033緑。
> - dual-write 全 6 resource-write サイト被覆確認: PlayerScene reconcileWithCarry/placeOneFromSnap/reviveOneAt・CombatScene ECS+legacy level-up・EnemyScene spawn。snapToPlayerSpawn の resource=lookupUnit は Spawn 構築ゆえ addOnePlayer spawn-seed(:329)で transitively 被覆。
> - **S2.2(D4) = staves/consumables/rings/ringEquipped を World command-derive store 化**（player-only store＝`waited` 流儀・key=player id 直・Enemy arm no-op）。review 93/93/92・dual-write 17 サイト漏れなし（束ね書込 reviveOne hp+consumables / equipRing rings+ringEquipped 含む）。mismatch 検証器は (length, head) 比較ゆえ**非先頭 drift は `[...DIFF]` に出ない**（D3 weapons テンプレ継承・emit は full list ゆえ World は忠実）。
> - **D4 run 検証中の付随修正（元仕様バグ・D4 回帰ではない）**: 「投げた杖が消えない」を発見・修正。`StaffCastScene.consumeThrownItem` の Staff arm を `consumeStaff`(回数-1)→`PlayerScene.dropStaff`(完全除去) に変更＝投げ武器(`dropWeapon`)と対称。投擲は物理的に手放すので残り回数に関わらず消失。通常詠唱(L59 consumeStaff)は耐久-1 のまま据え置き。`dropStaff` が `SetStaves` dual-write ゆえ `[STAVES DIFF]` 無音維持・1029緑・ユーザー spec OK。
> **次の一手**: S2.3/S2.4/S2.5/S3 をまとめて run 検証（戦闘 level-up・復活・拾得・武器/指輪 装備・移動・**状態異常付与/経過/中断再開**で `[BASESTATS/WEAPONVIEW/RINGBONUS/MOVETILES/STATUSEFFECTS DIFF]` 無音。特に S3 は **複数ターン跨ぎで status の remaining が正しく減るか・中断再開で buff/debuff が残るか**を確認＝二重tick回帰の検出）→ コミット → **S4(reader-flip + compose)** へ。combatViewOf の全入力が command-derive 揃い済み＝S4.2(combatView flip) が安全。S4 の刻みは `~/.claude/plans/phase-d9-d10-cascade-map.md`（cascade hub＝EnemyTurnDriver の fromBoardQuery・EnemyAI は pure ゆえ伝播は浅い）。
> - **ビジュアルスクリプティング Tier1 計画**（ユーザー将来相談・v5 採用）: ルート `VISUAL_SCRIPTING_TIER1.md`（別系統・実装は後日）。レビュー4lens 最終 [grounding90/completeness90/scope-honesty82/user-value87]＝90 未達だが実体は完成度高い。82/87 は行アンカー freshness（移行コミットで陳腐化）＋golden 1誤引用が主因＝構造的ゆえ周回打切り。**:NNN は二次・def 名一次**。SimEvent 代数＝IR ゆえ既存純粋層の薄い orchestration で実現可能・演出の完全巻き戻しは A 完成待ち。
>
> ---
>
> ## ★最前線（2026-06-29）= 🎉 **戦闘＋杖の 2 大 orchestration cutover 完了・ECS が既定エンジンに**（1009緑・legacy branch 温存）
>
> プランで「**最重**」と位置づけた CombatScene 戦闘 orchestration とその双子 **StaffCast（杖）** の SimEvent 化＋cutover を
> 同じ型で完遂。OOP `applyAttackHit`/`applyStaffEffect` の実体が **ECS パイプライン**（`useEcsCombat()`/`useEcsStaff()`）に。
> 残る最重は Phase D（終端）。
>
> ### 杖（StaffCast）cutover ✅（dynamic workflow・plan→implement→review 91/91/91・1009緑・run 検証済）
> `StaffSystem.resolveStaffCast`（**純粋・draw 無し**＝rayCast 結果=hit を引数で受ける）が Heal/Blowback/Swap/Bind を
> **既存 SimEvent 代数へ写す**（新変種ゼロ）: Heal→Healed / Blowback→Damaged(+Dying+ViewFx(Died) or +Moved) / Swap→Moved×2 /
> Bind→Afflicted(immobilize5)。golden-trace 10 テストで legacy 等価（seeded RNG 不要＝決定論）。`useEcsStaff()` トグル＋
> `applyStaffEffectLegacy`(pub・oracle)＋`applyEcsStaffSceneEffects`(statuses 反映)＋空振り legacy fallback。Stopgap/effectRule/DSL 杖は
> legacy seam に fallback（deferred）。戦闘の CombatSystem/ViewReplay/applyEcsSceneEffects/golden-trace/`*Legacy` を 2 周目流用。
>
> ### 完成した ECS 戦闘パイプライン
> ```
> applyAttackHit ──useEcsCombat()──► CombatSystem.resolveAttack/resolveEnemyAttack（純 sim・World→(World,[SimEvent])）
> （legacy=applyAttackHitLegacy で温存）  ├ eventToCmds → World（Phase B 権威 field を Cmd 反映）
>                                        ├ syncTreeFromWorld（World→scene 一方向 derive）
>                                        ├ ViewReplay.replay（[SimEvent]→演出: SE/popup/explosion/HPバー/knockback/death）
>                                        └ applyEcsSceneEffects（scene 権威の副作用: statuses/level-up panel+stat成長/武器耐久）
> ```
> - **sim**: `CombatSystem`（`src/ecs/systems/`）= finisher/crit/lifesteal/knockback/thief/effectRule/counter まで legacy 等価。`combatViewOf` を World から読み、`World.RngDraw` で draw、`SimEvent` を産んで `applyEventToWorld` で畳む。
> - **golden-trace 等価**（`TestGoldenTrace`）= legacy `runAttack`（`applyAttackHitLegacy`）の最終 World/cmd-stream を凍結し、ECS `resolveAttack` と直接照合。`ViewFx`(Sound/Popup/Explosion/Died) で log を「完全な view-script」化（World identity＝golden 不変）。
> - **ViewReplay**（`src/scenes/ViewReplay.flix`）= 純粋 `plan: [SimEvent]→[ViewAction]`（テスト固定）＋ effectful `replay`（既存 Scene API へ薄く dispatch）。
> - **Phase B（戦闘が触る field の World 権威化）**: `refreshMirror` が hp/pos/dying/progress/alerted を command 由来 preserve、`syncTreeFromWorld` が scene へ derive（位置 S5b と同型に拡張）。旧 DIFF 検出器（F6 HP/ALERTED/DYING/PROGRESS/COMBATVIEW）撤去（書き漏れは可視バグで現れる＝P3 WRITE-MISS 撤去と同じ）。
> - **statuses は scene 権威のまま**（tick も scene 側）＝ECS 経路は `applyEcsSceneEffects` で scene #statuses に Afflicted/Released を適用（完全 World 権威化＝tick 移行は別スライス・E4 系）。
> - **cutover の test 両立**: `applyAttackHit`(toggle・既定ECS) と `applyAttackHitLegacy`(常に legacy) を分離。golden/equivalence/scene-record テストは `*Legacy` 経由＝**ECS 既定でも legacy oracle 維持・999緑**。equivalence テストは legacy vs ECS を比較し続ける。
> - **run 検証クリア**（ユーザー実機）: 通常戦闘・反撃・撃破・死亡演出・状態異常付与・レベルアップ（パネル＋強化）・武器消耗。「集合で階段」報告は占有のたまたま＝ECS 無関係と切り分け。
> - **deferred（軽微）**: thief view-fx（`ViewFx(Thief)`＝isRogue 未 read-model 化・P2c）・敵 heal effectRule（HealAt/FullHealAt→Healed・P2b）。
>
> ### ロードマップ（A 完成 → B 評価・体感 4〜5 割残）
> **方針決定（2026-06-29・ユーザー）**: まず **A（scene-tree を render 層として残す現 §A 形）を Phase D まで完成** → その後 **B（Node/NodeTree 撤廃 / render-from-World）を別途評価**。
> - ✅ **cutover 完了**: combat（ECS 既定・コミット済）／player staff（ECS）／**enemy Bind 詠唱**（`useEcsEnemyStaff` 既定 false・branch 温存・`StaffSystem` を caster=Enemy 流用・1014緑・golden 5本=直接クロス比較 legacy==ECS 含む・`TestEnemyStaffGolden`・コミット済）。敵 Stopgap/投擲は legacy 温存（defer）。**sim ロジックは概ね ECS 化済み**。
> - 🟡 **Phase D 進行中（終端・= A 完成宣言・25 slice の長丁場）**: 専用プラン = `~/.claude/plans/phase-d-implementation.md`（planning workflow `wwuk0nxil`・review min 80・**スライス順 D0→D15**）。**批准スコープ = hybrid-A**（`resource` は sprite/stat template として scene-backed 残置・baseStats だけ store 投影＝DoD 例外でなく正規形・ユーザー批准 2026-06-29）。discipline = 各 slice「store dual-write→`[XXX DIFF]`無音(実機 run)→reader-flip」・cascade を combatView/unitView の 2 hub に収束・branch 安全。
>   - ✅ **D0**（dead-code `EncounterBuilder.fromScene` 撤去・1014緑）／**D1 核**（PlayerData.flix に field×source 分類＋昇格基準の design pin・後段 gate・1014緑）完了。
>   - ✅ **D2 = 実質完了（no-op・調査で確定）**: メニューは prior work で既に PartyQuery 化済み。残 `PlayerScene.get` は全て正当な除外（`TradeMenu:748`=trade write-adjacent・`Cursor:135`=buildPlayingScene hard 境界）か、flip すると effect cascade（E6216 実証＝ONE render read で PartyQuery 2 段伝播・低価値）か、D11 render（ItemMenu 鮮度依存・cursorTargetDistance crash-risk）。**flippable surface 実質ゼロ＝reader surface は既に実用最小**。プラン D2 は over-scope だった。
>   - **★次の一手 = D3（inventory store: weapons）**: World store 追加＋`Cmd.SetWeapons`＋applyCmd＋全 weapon mutation サイト dual-write（combat 耐久消費/equip/pickup）＋`[WEAPONS DIFF]` 検証器（実機 run 無音確認）。**hp/progress 権威化と同型の実質スライス＝run 検証ペア・marathon-tail でなく fresh session 推奨**。D1 残（`PartyQuery.findIdAt`・menu wrapper・currency fixture）は消費する D5 で fold。以降 D4 → … → D14 bridge 撤去 → D15 DIFF teardown。openQ #2-#8 は各 slice 到達時に判断。
> - **S7 セーブの ECS 化は Phase D の後**（訂正・2026-06-29）: 当初「独立クリーン」と誤判断したが、`FloorSnapshot.PlayerSnap` は **成長後 stats/weapons/staves/consumables/rings/statuses（scene 権威・World 非保持）** も直列化＝World store 直列化は **Phase D まで不完全**。現 scene ベース save は全捕捉で正常動作。∴ Phase D で全部 World/component 化してから World 直列化が自然。
> - **（A 完成後）B 評価**: アーキ判断②の構造重複を撤廃するか。Explore で engine `Render`/`Drawable` 経路の欠落・UI/menu 作り直し規模・IDE scene 編集との競合を資料化してから判断。**今はやらない**。
> - **defer 継続（低 ROI・Plan B 整合）**: statuses 完全 World 権威化（高コスト・byte 同一 churn・reader-flip cascade と判明）／inventory 等 scene 権威（Plan B が明示許容・Phase D の component 分解で吸収）。
>
> ### アーキ判断: Node/NodeTree 再考（ECS との重複・2026-06-29 ユーザー指摘）
> 「ECS 化達成後、Node/NodeTree は OOP 残滓で ECS と機能重複では？」への分析。**重複は部分的・3 層に分解**:
> - **① sim STATE の二重持ち**（hp/pos/status を scene Data record と World が両方）→ **移行が消す**（Phase D で scene Data=World 派生・sim 権威ゼロ。HUD/view 調査で大半が既に pure UI＝World 書込 0・sim 権威 0）。
> - **② entity 同一性＋node-per-entity＋sync 層**（EntityId↔NodePath・Sprite2D node・`syncTreeFromWorld`）→ **A では原理的に残る構造重複**＝ユーザーの違和感の本体。撤廃は B。
> - **③ render 階層(parent-child/y-sort)＋UI/menu(scene node)**→ **重複でなく node の正当な役割**（ECS が native に持たない）。
> - **A vs B**: A=現 §A（scene-tree 残す・World→scene sync）。B=dodge_the_creeps_ecs 流（node tree 捨て World component を render System が即時 `Drawable` 化）。B が②を消すが UI/menu/IDE scene 編集が全部 node 前提＋engine `Render`/`spriteToDrawable` 経路が fe_rogue 描画要件を未吸収（effect 除去 refactor 未了＝engine 改修要相談）ゆえ大工事。**∴ A 完成 → B 評価の二段が現実的**（「ECS 化達成=①解消=A 完成」と「node tree 撤廃=②解消=B」は別レベルの目標）。

> ## ★最前線（2026-06-28）= ✅ OOP→ECS 移行 **Plan B end-state を証跡付きで確定**。**詳細・現在地は `examples/fe_rogue/_plan_oop_to_ecs.md`**（authoritative）
>
> ### ⚠ 過大表現の訂正（重要）
> 「process/physicsProcess/on~~ を全部潰した＝ゴール達成」は**誤り**。実際に System 化したのは**ターン進行 driver 2 つだけ**（EnemyTurnDriver / StairsExitDriver）。`redef process`/`physicsProcess`/`onKeyPressed` は健在で、**戦闘解決・移動・入力・ターンエンド等の LOGIC はまだ callback に残る**。ユーザーは **Plan B**（フル callback 撤去=A はやらず、現状を「driver=System・logic callback=Bevy 流 event/input system」として **end-state 確定**）を選択。下記ゲート＋監査で B を証跡化した。
>
> ### Plan B ゲート（callback が残ってよい条件・明文化）
> (1) **入力 or エンジンイベント駆動 か 順序非依存**（依存なら World 経由で順序非依存化済）。(2) **World 権威の unit sim 状態を書くなら必ず `Cmd.*` で dual-write**。(3) **判定は純関数**。
>
> ### World 権威スコープ（正直な線引き）
> - **in（dual-write 必須・全て被覆済）**: position・current hp・turnPhase(3)・statusEffects(read-model)・hidden(read-model)・alerted・bottleUsed・prevPos・followUpUsed・waited・attackTarget・enemyTurnBusy・phaseObservedEnemy・enemyDying・**level/exp（進行度・World 拡張で合流）**。
> - **out（World 非モデル＝B では callback/scene 権威を**明示許容**・「未達」でなく「移行スコープ外」）**: 成長後 stats・max hp・inventory・weapon 耐久・床アイテム/宝箱・EnemyTurn.Queue・カーソル位置(UI)・演出 timer。将来 World 拡張の候補。
>
> ### World 拡張（Plan B 後）= level/exp を World 権威化（913緑・✅run 検証クリア「大丈夫だった」）
> out-of-scope だった進行度を proven dual-write パターンで合流。`World.playerLevel`/`playerExp: Map[id,Int32]`＋`Cmd.SetProgress(ref, level, exp)`＋applyCmd＋syncFromScene/refreshMirror preserve＋`progressOf`/`progressMismatches`。dual-write 6 サイト全網羅（spawn / applyExpGain(no-levelup) / applyLevelUp / reviveOneAt / placeOneFromSnap / reconcileWithCarry）。gameLoop に `[PROGRESS DIFF]`。TestWorld + level-up リグレッションテストに progress assertion 追加（level-up で (level+1,exp) も dual-write を CI 固定）。run 検証 = 撃破→exp→レベルアップで `[PROGRESS DIFF]` 無音。
>
> ### 後続（2026-06-28・917緑）= OOP→ECS ディレクトリ再編 + S-A0 combatView の World read-model 化
> 計画は `examples/fe_rogue/_split_plan.md`（壁打ち 90+）／`_ecs_taxonomy.md`（役割分類）が authoritative。
> - **ディレクトリ再編（A0/A1/A4/A6/A7）**: **Rule(値→値純ロジック)=`src/ecs/rules/`** と **System(`World→World`)=`src/ecs/systems/`** を分離（ユーザー指摘で確定）。`Combat`/`EnemyAI`/`StatusSystem`/`LevelSystem`/`CounterAttackRules`/`Board`/`Encounter`/`MoveDraft`/`Encumbrance`/`Weapon`/`effects/*` を `ecs/rules/` へ、`UnitView` を `ecs/`、配置 util を `lib/dungeon/RoomLayout`。CombatScene/StaffCast の純 leaf を `ecs/rules/CombatRules`/`StaffRules` へ抽出。`TurnFlow`(11)/`PhaseTransitions`(90) は scene 結合で据置（純粋ラベル誤りを実測訂正）。A7 audit: 6 World-touch scene は全て `Cmd` 書込 0＝View 据置で正。**真の `World→World` System はまだほぼ無く、本命は Phase C の `resolveCombat`**。
> - **S-A0（combatView を World から再構築可能に）**: `Combat.BaseStats`/`assembleView`（組立の単一源泉・式 drift 不能）、World read-model 3 本 `baseStats`/`weaponView`/`ringBonus`（resource/装備由来ゆえ毎フレーム再 mirror＝statusEffects 同型・emit 不要）、`World.combatViewOf(ref): Option[CombatView]`（baseStats+weaponView+ringBonus+statusEffects+hp を合成）。**parity test**（fixture + status-active）+ **`[COMBATVIEW DIFF]` 検証器**（Game.flix・refreshMirror 後・実機全構成で combatViewOf==scene combatView を監視）。✅run 検証 = `[COMBATVIEW DIFF]` 無音「OK だった」。
> - **多引数のレコード名前渡し化**（ユーザー方針 [[feedback_record_named_args]]）: `assembleView` を `ViewParts` レコードに。誤順リスク実在の geometry helper（knockback/push の `KnockbackPos{attacker,defender}`・blowback の `{hit,dir}`・swap の `UnitCell{id,cell}`）を束ね。型混在&Phase C 書換予定の大型 orchestrator（applyHit 等）は据置。
> - **次の一手（Phase B 本体・重・実機 run ペア必須）**: read-model（baseStats/weaponView/ringBonus）を **command-derive 化**（mutation 毎に Cmd emit→mid-combat でも current）→ combatView reader を `combatViewOf` へ **flip** 安全化。現状の再 mirror read-model のままだと **mid-combat で 1 フレーム stale** になり得るため naive flip は不可（frame-end DIFF 無音はそこを保証しない）。
>
> ### 残 logic callback 監査表（全件ゲート pass・912緑）
> | callback | (1)駆動/順序 | (2)in-scope dual-write | (3)純判定 |
> |---|---|---|---|
> | `CombatScene.process` | own-node anim signal=順序非依存 | hp/attackTarget/isDying/alerted/followUpUsed/phase 全 emit 済（hp は level-up 漏れ修正で完了） | Combat.estimate 等 ✓ |
> | `CursorScene.physicsProcess` | 入力駆動・カーソル=UI（World 書込無し） | 該当なし（unit 移動は `Cmd.Move`） | ✓ |
> | `onKeyPressed`(Playing) | engine key event | 確定→combat/move/waited は funnel 経由 emit 済 | ✓ |
> | `TurnEndHoldScene.process` | Shift 入力 | phase は TurnPhase.State handler が `Cmd.SetPhase` 自動 dual-write | ✓ |
> | `ItemScene`(拾得)/`StaffCastScene` | 入力/イベント | inventory=out。hp/status は emitHpSets/emitStatusAdds 境界 tap で被覆 | ✓ |
> | view 群 ~15(HPBar/Camera/Fog/TopBar/Popup…) | render・World 書込無し | 該当なし | ✓ |
>
> **監査結論**: command-authoritative(preserve)な in-scope フラグ全て（hp/pos/alerted/bottleUsed/prevPos/followUpUsed/waited/attackTarget/enemyDying/turnPhase/TopBar bool）の scene 書込が `Cmd.*` emit と paired。**漏れは level-up のみ＝修正済**。∴ 残 callback は全てゲートを満たす＝**「driver=System・logic callback=Bevy 流・World=unit sim 状態の権威」を根拠付きで end-state と宣言**。A（combat/move/input のフル System 化）は optional な将来拡張。
> **🎉 軸1（authoritative sim state→World）完遂**: position・phase(3-case)・hp・alerted/bottleUsed/prevPos/followUpUsed/waited・**attackTarget・TopBar同期bool・isDying** が全て World 権威（dual-write＋refreshMirror preserve＋`[XXX DIFF]` 検証器・各テスト/run 確認）。汎用 read seam `World.WorldQuery { def get(): World }` 確立。**World が sim の唯一の真実源に。** 911緑。`acted` は view-only-read（sprite 灰色のみ・二重行動防止は EnemyTurn.Queue 担保）ゆえ scene 残置で正当。
> **F8-slice1 着地（2026-06-28・909緑）= `attackTargetId` を World 権威化**: 攻撃対象 id（`anyAttacking` の元）を `World.playerAttackTarget`/`enemyAttackTarget: Map[id,target]` に dual-write（`Cmd.SetAttackTarget`/`ClearAttackTarget`＋applyCmd＋refreshMirror preserve＋`attackTargetMismatches` 検証器）。**敵ターン driver の `anyAttacking` reader 6 箇所（EnemyTurnDriverScene×4・StairsExitScene×2）を `World.anyPlayerAttacking/anyEnemyAttacking(WorldQuery.get())` に flip**＝driver の「攻撃モーション中か」判定が scene tree でなく World 由来＝**順序非依存（F8 の ordering ブロッカー＝driver が combat-drain と TopBar に挟まれる問題の本体を解消）**。gameLoop に `[ATTACKTARGET DIFF]` 追加。set 全サイト網羅・clear は funnel 経由・spawn は None=absence で Cmd 不要。**残 run 検証 = `[ATTACKTARGET DIFF]` 無音確認のみ**。
> **F8-slice2 着地（2026-06-28・910緑）= TopBar 同期 bool を World 化（after-ordering 依存を解消）**: driver が読む `TopBarScene.isBusy`(intro hold 中)／`hasObservedEnemy`(バーが敵ターン観測済) の 2 派生 bool を `World.enemyTurnBusy`/`phaseObservedEnemy`(scalar) に dual-write（`Cmd.SetEnemyTurnBusy`/`SetPhaseObservedEnemy`・TopBar.process が確定 scene から毎フレーム emit）。**生アニメ Data（anim/hold/shown/animTarget）は TopBar 残置**（view 状態を World に入れない）。driver の 2 gate（EnemyTurnDriverScene:180/191）を `World.enemyTurnBusyOf`/`phaseObservedEnemyOf(WorldQuery.get())` に flip。gameLoop に `[TOPBAR DIFF]` 検証器。**挙動同一**（旧 scene 読みも今 World 読みも「前フレームの TopBar 状態」＝per-node 順で driver が TopBar より先に走るため）。残 run 検証 = `[TOPBAR DIFF]`+`[ATTACKTARGET DIFF]` 無音。
> **🎉 F8 本体 着地＋run 検証クリア（2026-06-28・910緑）= driver dispatch を OOP callback→frame-paced System へ移設＝軸2（control inversion）達成**: `EnemyTurnDriverScene.process(delta,node,path,scene)` は node/path/delta を使わない pass-through（driver は payload-less stateless）だったので純 `step(scene): Scene` System に昇格。`dispatchDrivers`(per-node redef) から `EnemyTurnDriver` ケースを削除し、gameLoop パイプラインに `|> EnemyTurnDriverScene.step`（`GameEngine.process` の後）を明示段として追加。**敵ターンロジックが Node lifecycle callback でなく gameLoop 駆動の System に。** ≤1 フレームの演出シフトはユーザー実機確認で問題なし＝byte 非同一だが体感不変。**（注: これは敵ターン driver 単体の達成。全 callback 脱却ではない＝上記 Plan B 訂正参照。）**
> **🐛 同時に F6 漏れ修正**: 実機 `[F6 HP DIFF] (Player(0),14,15)` 永続発生→ per-node に戻しても消えず＝F8 無罪確定。原因は `CombatScene.applyLevelUp` の HP 増分が `Cmd.SetHp` 未 emit（scene 直書きのみ）。emit 追加で解消。`[F6 HP DIFF]` 検証器が dual-write 漏れを実機で捕える設計どおり機能。
> **✅ F8 仕上げ: StairsExit も System 化（2026-06-28・910緑・run 検証待ち）**: 階段順次退場 driver（ターン進行 LOGIC・stateful）も `process(node)`→`step(scene)` に昇格。Data(queue/idleRounds) は `Scene.getState(driverPath())` で読み `setState` で同ノードへ書き戻すため node 引数不要。`dispatchDrivers` から外し gameLoop に `|> StairsExitScene.step`（EnemyTurnDriver.step の直後）。**これで全ターン進行 LOGIC driver が frame-paced System。** Fog/Minimap/ArrowCursor は view 描画ゆえ per-node 残置（gate 許容）。run 検証クリア（ユーザー「階段OK」確認・順次歩行/退場/次フロア遷移/取り残しターンエンド正常）。
> **✅ isDying→World dual-write（2026-06-28・911緑・run 検証待ち）= 軸1 最後の sim-authority ギャップを着手**: `isDying`（死亡演出中＝CounterAttackRules の Kill 判定・TurnPhase キュー除外・UnitView 標的選定・ActionMenu/Cursor 攻撃可否 が読む真の sim フラグ）を `World.enemyDying: Set[EntityId]` 化。`Cmd.SetDying`＋applyCmd（Set.insert）＋syncFromScene/refreshMirror で preserve+prune（death 完了でノード除去→自動 prune・absence=非 dying）＋`isDyingOf` 読み＋`dyingMismatches` 検証器。dual-write は `EnemyScene.startDeathAnimation`（hp=0 emit に併置）。gameLoop に `[DYING DIFF]`。**byte 同一・追加のみ**（reader-flip は他フラグ同様 defer）。`acted` は view-only-read（sprite 灰色のみ・二重行動防止は EnemyTurn.Queue が担保）ゆえ scene 残置で OK。run 検証 = 敵撃破（death_blink）で `[DYING DIFF]` 無音。
> **✅ UI callback ゲート点検 完了（2026-06-28）= migration end-state 宣言**: 全 per-node process callback を分類。**ターン進行 LOGIC 駆動（EnemyTurn/StairsExit）は System 化済み＝目標達成。** 残 callback は (a) 純 view 描画（DamagePopup/Explosion/HPBar/UnitInfoPanel/TopBar/ItemPickupPopup/Log/Camera/Minimap/Fog/ArrowCursor）と (b) input/event 反応（CombatScene.process=attack:hit signal で戦闘解決・TurnEndHold=Shift で turn end トリガ・physicsProcess の Player/Cursor 移動・CharacterSelect）のみ。**(b) は Bevy の input-system / event-reader system 相当＝callback が正規形・gap ではない。** 唯一の実質ロジック CombatScene 戦闘解決は event 駆動（attack:hit がアニメ中点発火）で F4 分析（フル反転=実現可能性35）どおり callback 維持が正解。**∴ 当初ゴール「scene を LOGIC 駆動から脱却・ターン進行を World→World System 化」達成。**
> **isDying reader-flip は非推奨（2026-06-28 判断）**: 読み元の `EnemyScene.unitView(data): UnitView` は pure 関数で Encounter join/AI/combat estimate に遍在。World 読みに flip すると pure builder を全域で impure 化＝大 cascade・**しかも dual-write 済で data#isDying は World 忠実＝挙動 byte 同一（ゼロ価値churn）**。scene#isDying 撤去は Data record/snapshot 全面改修が別途必要。よって dual-write+検証器で「権威の土台」は完了とし reader-flip は見送り（軸1 の payoff=serializable/determinism/testable は dual-write で取れている）。
> **任意の残仕事（optional・完全 ECS 化のさらに先）**: 戦闘解決の event-system 化（Bevy 流 EventReader 化・実現可能性低・F4 で defer 済）／scene#isDying 等 view-mirror フィールドの撤去（churn 大・payoff 小）。**いずれも現 end-state で migration ゴールは満たされており必須でない。**
> 以下は旧 ★最前線（P0a 位置移行・2026-06-27・完了済の歴史記録）:
>
> ## ★最前線（2026-06-27）= 位置(Board/Encounter)を World 権威化（write-first）
> **詳細プラン**: `examples/fe_rogue/_plan_position_ecs.md`（v3・レビュー壁打ち 68→84→90 で確定）。statusEffects は下記の通り read-model 確定済み。
>
> ### P0a 完了（**コミット済み(`4f14204`)＋tripwire test 追加・879緑・挙動不変と確定**）
> 位置 write-seam を実装した。要点:
> - `World.Cmd.Move(EntityRef, {x,y})` ＋ `applyCmd`（worldRef を mid-frame 即時更新）。
> - 移動5関数（`PlayerScene.{moveTo,moveToById,snapTo}` / `EnemyScene.{moveTo,snapTo}`）から `World.Command.emit(Cmd.Move)`。
> - **壁を2つ解決（早期の悲観は誤りだった＝スパイク伝播が未完だっただけ）**:
>   ① `FrameAef.T` に `World.Command` を1行追加（physics 経路解禁・E6217 カスケード無し）。
>   ② `StaffCastScene.staffEffectHandlers` の `PlanHandlers` ef 注釈に `World.Command` 追加（custom-op が Command を拾うため）。
> - World.Command を ~20 関数へ compiler 誘導で伝播。test 5件を `TestUnitFixtures.dischargeWorldCommand` で discharge。
> - **検証器**: `Game.flix` の `BoardQuery.board` handler 1箇所で `World.toBoard(worldRef)` vs `BoardSnapshot.fromScene(scene)` を
>   `World.boardKey`（(tag,id,x,y) 順序非依存 tuple 比較）で突合し、差を `println("[P0a BOARD DIFF] ...")`（**real run 専用**＝test は mock handler で通らない）。
> - **tripwire test 追加**: `TestWorld.testMoveReflectsNewPosInBoardMidFrame`（`Cmd.Move`→`boardPieces` が prev→now を mid-frame 反映する currency を pin・879緑）。
>
> ### ★重要な再判断 = **P0a は挙動不変＝実機 run は不要**（2026-06-27 後段）
> 当初 §G は「gather が mid-frame 観測を prev→now に是正するため挙動不変でない＝run 必須」としていたが、**これは誤り**と判明:
> - `BoardQuery.board()` 消費者は7箇所。うち **Cmd.Move より後(mid-frame)に読むのは gather の `followAllies` 1箇所だけ**。
>   他6箇所（StaffCast×3・Cursor・stepFor・TurnPhase context）は全て **move より前(frame-head)** の読みで、そこは World==scene(faithful mirror)＝currency 無関係。
> - 唯一の mid-frame 読みである gather の `Board.followStepsToward` は **主人公の board 位置に非依存**
>   （味方は全プレイヤーセルを通過可・goal は強制 open・lordNewPos は予約）。よって prev でも now でも追従結果は同一。
> - ∴ **P0a が currency を是正しても観測者(gather)が結果を変えないので、ゲーム挙動は不変**。run の残存価値は「write 漏れ監査(DIFF ログ)」のみだが、
>   移動5関数の emit は grep 確認済・applyCmd 機構は tripwire で緑＝**緑のテスト＋静的論証で P0a 完了**。run は cheap insurance（任意）。
> - 検証器 `[P0a BOARD DIFF]` は **P1a/P1b/P3 の flip・mirror 撤去で挙動不変を機械実証する将来資産**として保持。
>
> ### P0b 完了（**spawn/restore funnel の seed emit・880緑・dual-write で挙動不変**・要コミット）
> spawn/restore の funnel `PlayerScene.addOnePlayer`／`EnemyScene.addOneEnemy` から `Cmd.Move`(=位置 seed) を emit。
> - **lifecycle 木への伝播 = ~17 production 関数**（compiler 誘導・計測 envelope 内）: funnel 2 → leaf(add/respawnFromInitial/addFromSnaps/
>   placeOneFromSnap/reviveOneAt/spawnInRoom/maybeSpawnWandererInRoom) → lifecycle ルート(buildPlayingScene/buildCurrentFloor/buildAndRecord/
>   rebuildFloorFromSnapshot/restartFromFloorSnapshot/advanceFloor/resetForGameOver/reviveWithGoddess/maybeSpawnWanderer) → `Game.applyPhaseChange`。
>   上流(gameLoop/dispatch)は P0a move5 伝播で `World.Command` 既保持＝そこで収束。
> - **test discharge**: `TestPlayerScene` は薄ラッパ `addOnePlayerT`(=`dischargeWorldCommand`∘`addOnePlayer`)へ一括置換、`TestMoveRange`/`TestTradeMenu` は scene 構築を `dischargeWorldCommand` で wrap。
> - **tripwire 追加**: `TestWorld.testAddOnePlayerSeedsPositionToWorld`（addOnePlayer の emit を capture→`boardPieces` に id7@(3,4) を確認・emit 行削除で赤）。
> - 毎フレーム `syncFromScene` mirror に上書きされる **dual-write ＝挙動不変**（mirror は P3 まで生存）。run 不要（P0a と同論法）。
>
> ### P1a 完了（frame-head reader flip・挙動不変・run 不要・880緑）
> move 前に board を読む frame-head 経路を `BoardSnapshot.fromScene`→`BoardQuery.board()` に。pure reader(canExit/buildFor/reachability)は対象外（scene gridPos は P3 でも dual-write 継続ゆえ fromScene のまま可）。
> **重要**: P0a+P0b 完了で dual-write が全 move/spawn を被覆＝**World==scene が frame-head/mid-frame とも常時成立**。よって flip は frame timing に依らず挙動不変。
> - **✅ StairsExit group**: `begin`／`advanceFront` を `BoardQuery.board()` に。cascade で `stepOnce`/`process`＋menu trait tier
>   （`MenuHandler.Aef[NodeTag]`＝Game.flix:386・`onItemConfirmed`/`onItemCancelled` は arm が既に `checked_ecast` 済で宣言行に `BoardQuery` 追加のみ）
>   ＋`dispatchMenuKey`/`onItemConfirmed` dispatch＋**`FrameAef.ProcessT` に `BoardQuery` を許可**（旧「process は BoardQuery 不使用」規約を更新）。test は `withMockBoard` を2スタックに追加。
> - **✅ StaffCast player group**: player の blowback 一式（`applyBlowbackMove`/`applyBlowbackToPlayer`/`applyBlowbackToEnemy`）・`warpEnemy`・`applyStopgapToEnemy`・
>   `customStaffEffect`・`applyStaffEffect`/`applyStaffEffectDsl`/`applyStaffEffectLegacy`・throw chain（`applyThrowHit`/`rolledThrow`/`dispatchThrowEffect`）を flip。
>   **`staffEffectHandlers` の `PlanHandlers` ef 注釈に `BoardQuery` 追加**（custom op が BoardQuery を拾う・P0a の World.Command と同型）。fireStaff/fireThrow は :50/:770 で既に `BoardQuery.board()` 保持ゆえ収束。test は `TestStaffCastScene` に `withMockBoard` 追加。
>   - **延期（P1b）**: `warpPlayer`/`applyStopgapToPlayer` は **enemy cast(`enemyCastStaff`)と共有**ゆえ flip すると cascade が敵turn driver(P1b)へ波及する。enemy staff 経路（`enemyCastStaff`/`enemyTryStaff`/`enemyThrowWith` :1033/1072）と一緒に P1b で flip。
> - 各 flip 後 handler assert 差ゼロ（World==scene）。
>
> ### P1b 完了（mid-frame reader flip・挙動不変・run 不要・880緑）
> dual-write で World==scene が mid-frame でも常時成立するので、mid-frame readers も挙動不変で flip 可。
> - **✅ StaffCast enemy cast group**: 延期分 `warpPlayer`/`applyStopgapToPlayer`＋enemy 経路 `enemyCastStaff`/`enemyTryStaff`/`enemyThrowWith`/`enemyTryThrow` を flip。
>   cascade は**敵turn driver全体**（`EnemyTurnDriverScene.process`/`stepOnce`/`applyStep`/`applyStepForEnemy`/`tryThrowOrNormal`）へ伝播し、`Game.process` redef（ProcessT＝BoardQuery 保持）で収束。
> - **✅ Combat knockback group**: `pushEnemyBack`/`pushPlayerBack` を flip。cascade は combat resolution chain 全体
>   （`applyAttackKnockback`/`applyEnemyKnockback`→`resolveAttack`/`resolveEnemyAttack`→`applyDamageTo*`→`applyAttackHit`/`applyEnemyAttackHit`→`onAttackHit`→`drainAndDispatch`→`CombatScene.process`）へ伝播し ProcessT で収束。test は `TestCombatScene` の3スタックに `withMockBoard` 追加。
> - **P2 へ送り**: `EnemyTurnDriverScene` の `EncounterBuilder.fromScene`（:119/:270＝EnemyAI 入力）と `beginTurn` の board 順序付け読み（:143）は **Encounter/EnemyAI の World 化（P2）**で一緒に flip（`beginTurn` 単独 flip は `TurnFlow.commitWaitedAndAdvance` 共有関数への広い cascade を生むため）。
> - **据え置き（pure・恒久 fromScene 可）**: `StairsExit.canExit`(:108)・`RangeScenes`(:149)。`Game.flix:882` は P0a 検証器の参照系ゆえ fromScene 固定。
>
> ### P2 完了（Encounter を World へ・EnemyAI 入力・挙動不変・run 不要・880緑）
> **設計判断**: `UnitView` は pos/hp 以外に combat/weaponRange/moveTiles/aiType（resource/weapon 由来）を持ち World 未保有。§A 採用戦略
> （位置は World 権威・stats は read-model）に沿い、**Encounter は board(位置幾何)=World 由来・units(stats)=scene read-model のハイブリッド**にする。
> - 新 `EncounterBuilder.fromBoardQuery(scene): Encounter \ BoardQuery`（board=`BoardQuery.board()`、units は `fromScene` と同じ scene 由来）。dual-write で board と units の位置一致。
> - flip した effectful EnemyAI 消費者: `applyNormalStep`（敵通常移動 AI＝核）・`bumpedDarkRoomEnemy`（接敵 visibility）。呼び元は P1b で BoardQuery 保持済ゆえ cascade ほぼ無し。
> - **据え置き**: `beginTurn` の step 順序付け board 読み(:143)は flip すると共有 `TurnFlow.commitWaitedAndAdvance`→8 src への wide cascade を生み低価値ゆえ fromScene 維持（後日まとめて検討）。pure(`canExit`/`RangeScenes`)・検証器(`Game.flix:882`)も据え置き。
>
> ### ✅ P3 完了・**実機 run 検証済**（mirror 撤去・§A payoff 達成・883緑）
> **位置の権威を World に一本化**。`syncFromScene` の pos mirror（scene gridPos→World 上書き）を per-frame で停止し、World.pos を **`Cmd.Move` のみ由来**にした。
> - **新 `World.refreshMirror(scene, world)`**: 位置は `world` の値を保持（gridPos 再構築なし）＋scene に居ない id を prune（ghost 防止）。hp/status/hidden/ids は read-model のまま scene から mirror 継続（§A：位置だけ World 権威）。
> - **gameLoop frame-end**: `syncFromScene(next, world)` → `refreshMirror(next, Ref.get(worldRef))`（mid-frame の Cmd.Move 適用済み worldRef を base に）。
> - **seed**: 初期 world は `syncFromScene`（gridPos 読み）を Game.start:817 に残す。床移動/復活/中断再開の reseed は spawn funnel の `Cmd.Move` emit が担う（全て World.Command handler スコープ内）。
> - **単体テスト（`TestWorld`）**: `testRefreshMirrorKeepsCommandPosNotGridPos`（mirror OFF を証明）・`testRefreshMirrorPrunesAbsentIds`・`testRefreshMirrorStillMirrorsHpAndIds`。
> - **実機 run 検証済**: 通常/敵移動・gather・杖・戦闘ノックバック・階段退場・**床移動・全滅復活・中断復帰**を通し、新設 `[P3 WRITE-MISS]`（フレーム末で command World vs scene gridPos を同一時点突合・通常無音）が**一度も発火せず**＝write 漏れゼロを確認（2026-06-27）。
> - **検証器整理**: 役目を終えた mid-frame `[P0a BOARD DIFF]`（移動中に毎フレーム鳴る transient ノイズ）を撤去。サイレントな `[P3 WRITE-MISS]`（フレーム末・real run 専用の恒久 write-miss ガード）だけ残置。
>
> ### 到達点 = **§A payoff 達成**（World が位置の論理的権威・scene は派生ビュー・determinism/save の素地）
>
> ### ✅ S5 完了・**実機 run 検証済**（scene を位置の純粋な派生ビューに＝dual-write 撤去・885緑）
> §A 完成へ。move 関数の scene gridPos 直書きを撤去し、gridPos を **World→scene 一方向 sync（`syncTreeFromWorld`）で derive** する。
> - **新 `World.syncTreeFromWorld(world, scene)`**: 各ユニットの scene gridPos を World 位置で上書き（`mapPlayer`/`mapEnemy` 再利用・`syncStatusesToScene` と同型）。gameLoop の frame-end（render 直前）で実行。
> - **S5a（additive・no-op）**: 上記 sync を配線（dual-write 継続中は World==scene ゆえ no-op）。
> - **S5b（本番）**: `PlayerScene.{moveToById,snapTo}`／`EnemyScene.{moveTo,snapTo}` の `gridPos=target` 直書きを撤去（Tween/anim/facing/prevPos の視覚状態は残す）。
>   唯一の mid-move logic reader `PlayerMovementScene.gatherStep` の `now`（移動後の主人公位置）を scene でなく **World 由来（`BoardQuery.board()`）** から読むよう flip。
>   `PlayerScene.moveTo`(marker版)は呼び出しゼロの dead ゆえ非対象。
> - **検証器整理**: scene gridPos が derive になり「独立 dual-write」前提が消えたため `[P3 WRITE-MISS]` を撤去（write 漏れは「ユニットが動かない」可視バグに変わる）。
> - **test**: 落ちた `TestStaffCastScene.testStaffEffectRuleSwapsPositions`（swap杖の gridPos 入替を scene で検証）は、harness `fireStaffDsl` を gameLoop 同型（worldRef seed→Cmd 蓄積→`syncTreeFromWorld` で gridPos derive）に修正。
> - **run 検証済**: gather（隊列追従）・通常/敵移動・杖各種・戦闘ノックバック・階段集合・床移動・全滅復活・中断復帰を通し挙動正常を確認（2026-06-27・ユーザー run）。
>
> ### ✅ §A 完成 ＋ determinism デモ追加（885緑）
> S7（セーブ封筒の EcsCodec 置換）は **stats が read-model で World 単体シリアライズ不可・セーブ形式 churn の割に実利薄**のため見送り、代わりに **§A payoff（World が位置の決定論的源）を `TestWorld` で実証**:
> - `testCommandLogReplayIsDeterministic`: 位置 = `Cmd.Move` ログの**純粋関数**・独立2回 replay が一致（決定論）。
> - `testWorldPosRoundTripsThroughSerialization`: World 位置が `(id,x,y)` 列へ save/load round-trip（位置 store は単純 component-map ＝EcsCodec 封筒にそのまま載る形）。
> - 新 `World.posOf(EntityRef)` アクセサ追加。
>
> ### 到達点 = **位置 ECS 移行 完了**（P0a→S5 で World が位置の唯一の権威・scene は派生ビュー・determinism 実証済み）
> 任意の発展: stats（hp/weapon/combat）も World 権威化したくなったら S6/Option A（EnemyAI 完全 World 駆動・単一 component-map ストア）へ。現状は §A 採用戦略どおり**位置=World 権威／stats=read-model** で安定。
>
> ### 注意（resumption）
> - **P0a/P0b/P1a/P1b はコード実装済**。P0a は `4f14204`、P0a-tripwire+P0b は `5467cd3`、P1a-StairsExit はユーザーがコミット済。
>   **未コミット（P1a-StaffCast＋P1b）**: `StaffCastScene`/`CombatScene`/`EnemyTurnDriverScene`＋test `TestStaffCastScene`/`TestCombatScene`＋`ECS_WORKFLOW.md`。HEAD+作業ツリーで `flix test` 880緑・`flix check` 緑。
> - **flip パターン（P1a/P1b 共通）**: `BoardSnapshot.fromScene(scene)`→`BoardQuery.board()`＋関数の effect 行に `BoardQuery` 追加。cascade は compiler 誘導で frame tier（`FrameAef.ProcessT`／menu `MenuHandler.Aef`／combat・enemy driver の `process` redef）に収束。trait redef が tier を超える時は **arm を `checked_ecast` 済みにして宣言行に効果追加のみ**（onItemCancelled で実践）。test は該当スタックに `withMockBoard(BoardSnapshot.fromScene(scene))` を1層足す（flip 前と同値）。
> - **WIP は再適用済み**: 旧注記の「`World.Query`→`World.StatusQuery` リネーム＋engine_ecs 汎用 `Query`/`exclude` は HEAD に戻した」は古い。`0d01322 "world強化"` で**再適用＆コミット済み**（engine_ecs `Query`＋`TestQuery`＋fe_rogue の rename）。もう WIP ではない。
> - fpkg は git 管理外。エンジン側変更後/新規 checkout 後は `GITHUB_TOKEN=$(gh auth token) make sync`（無認証は GitHub API レート制限で fpkg 配布が 404/失敗）。
> - perl で effect row へ `World.Command` を撒くのは**多行 sig で誤爆**するので、複数行シグネチャは Edit 推奨。

> **方針転換（2026-06-27）**: read-model 路線では「本物の ECS でない」とのユーザー指摘を受け、**statusEffects を
> 真に World 権威化する Bevy 正対の移行**に舵を切った（plan `gemini-ecs-sunny-curry.md`、複数視点設計＋レビュー）。
> 詳細プランはそちら。以下の §G は **statusEffects 縦断 ECS 化**の進捗（位置/HP の read-model 項目は据え置き）。

**現在ステップ**: **statusEffects は read-model 確定（§A 整合）。emit-flip は E3 まで実装し、E4(権威 flip)は defer**。

> **再判断（2026-06-27 後段）**: emit-flip の reader flip 前段調査で、forecast/AI/盤面ビルダーの reader が **pure**（attackForecast/
> computeView/EncounterBuilder.fromScene 等）と判明。`World.Query` 注入は pure サブグラフへ effect を伝播させ（前回 22点頓挫と同型）、
> 回避には data-threading の中規模配線が要る。さらに reader を scene に残す妥当案（World=snapshot 源）は **§A が「やるな」と明記した
> "挙動ゼロ変化なのにドライバ大改修コストだけ乗る割の合わない flip"** そのもの。よって **statusEffects は §A 通り read-model に確定**し、
> ECS 化の労力は旨味の大きい **位置(Board/Encounter)・EnemyAI・セーブ**(S4〜S7)へ回す。statusEffects の完全 flip は決定論/replay の
> 具体 payoff が出た時に再開する（その時 E1〜E3 の Command/Query seam をそのまま使える）。

**E1〜E3（✅ コミット済・878緑・挙動不変・dual-write）= 将来 flip 用の実証済みインフラとして保持**:
- E1(`e0bf38c`): `clearAllWaited`→`Cmd.TickPlayers`/`clearActedAll`→`Cmd.TickEnemies` emit＋`World.Command` を ~30関数へ伝播。
- E2(`4eadeb5`): add を `EffectRunner.runPlan` の境界で `World.emitStatusAdds(plan)` 発行（handler テーブルは pure のまま＝`checked_ecast` 不要・責務分割）。
- E3(`c22b2d1`): `releaseBind`×2 内部で `Cmd.ClearImmobilized(EntityRef)` emit（scene inline clear は dual-write 維持）。
- これらの emit は毎フレーム `syncFromScene` の mirror に上書きされ **現状は無害な dual-write**（World は scene の faithful mirror）。

**E4 を再開する時の未了点（参考・defer 中）**: ① `syncFromScene`→`refreshMirror`（statusEffects 再計算停止＋prune）② gameLoop base を `Ref.get(worldRef)` に
③ reseed seam（床移動/リスタート/復活/中断再開で `Cmd.Seed`）④ reader flip（pure reader は **data-threading** で `statusEffects` を引数注入、`World.Query` は effect 境界で1回読む）⑤ dual-write 撤去 ⑥ `statuses` フィールド削除。**dual-write gap**（非DSL の直接杖Bind/一時しのぎ/敵詠唱/投擲 directional は境界 emit 未被覆）を塞ぐこと。**実機 `flix run` 必須**。
**次の一手**: ★最前線（§G 冒頭・2026-06-28）参照 — **Phase B 本体**: S-A0 read-model（baseStats/weaponView/ringBonus）を command-derive 化 → combatView reader を `World.combatViewOf` へ flip 安全化（**重・実機 run ペア必須**）。計画 = `examples/fe_rogue/_split_plan.md`。
（旧 S4 Board fromWorld flip②/S5 は Plan B 監査の一部として据置・out-of-scope 整理済み）

### チェックリスト
- [x] S0 足場（最小 World＋sync 骨組み）— `examples/fe_rogue/src/ecs/World.flix`、gameLoop に thread、build＋test 859緑、ゲート88→§G更新で90+
- [x] **S1a** StatusSystem store＋mirror＋System（**非破壊**）— `World.flix` に `playerStatuses`/`enemyStatuses`（faction 別＝id 衝突回避）、`syncFromScene` で mirror、`tickStatuses`（`StatusSystem.tick` 再利用）。build＋test **862緑**（`TestWorld.testSyncMirrorsStatuses`/`testTickStatuses` 追加）。World は依然 render/scene 無影響
- [x] **S1b write-back＋parallel-run 実証**（**非破壊**）— `World.syncStatusesToScene`（逆向き矢印・`PlayerScene.mapPlayer`/`EnemyScene.mapEnemy` 再利用）追加。test **864緑**（`testSyncStatusesToSceneRoundTrip`／**`testTickParallelRunMatchesScenePath`**＝World 経路と scene 経路が同残ターン）
- [x] **S1 完了（read-model 据え置き）** — statuses は scene 権威のまま、World は mirror＋System＋write-back を保持。**tick の権威 flip は不採用**（決定 2026-06-26・§A 採用戦略）
- [x] **S2 Combat HP（read-model mirror・非破壊）** — `World.flix` に `playerHp`/`enemyHp = Map[EntityId, Int32]`、`syncFromScene` で hp mirror。**権威は scene のまま**＝`Combat`/HPBar 無改修。test **866緑**（`testSyncMirrorsHp`／`testHpMirrorEqualsScene`＝World hp == scene hp）
- [x] **S3 位置 store（read-model mirror・非破壊）** — `World.flix` に `playerPos`/`enemyPos = Map[EntityId, {x=Int32,y=Int32}]`（Vec2i structural record）、`syncFromScene` で gridPos mirror。**権威は scene のまま**。test **868緑**（`testSyncMirrorsPos`／`testPosMirrorEqualsScene`＝World pos == scene gridPos・Vec2i.eq）
- [~] **S4 Board fromWorld 化（進行中）** — 射影 `World.toBoard`/`World.boardPieces`（ecs/ 層・World クエリ）と `BoardSnapshot.mapSnapshotOf`（scenes/ に抽出）構築。hidden は `World.playerHidden` に mirror 追加。test **869緑**（`testPiecesFromWorldFiltersHidden`）
  - [x] **flip①: `BoardQuery` handler**（Game.flix:869）→ `World.toBoard(worldRef, sceneRef)`。`worldRef`（sceneRef 対称・毎フレーム頭更新）配線。初回 world は `syncFromScene(scene)`（frame-1 faithful）。**順序リスク静的解消**（全 BoardQuery 消費者は位置キー lookup/集合 membership＝順序非依存。かつ `nextEnemyId=1+max` で敵は昇順 id append＝preorder==Map順）。build＋test 879緑。**挙動不変と確定（run 不要）＝唯一の mid-frame 消費者 gather の followStepsToward が board 位置非依存**（上記★再判断）
  - [ ] flip②: frame-head 直接 call（StaffCast/Combat/Range/Stairs）
  - [ ] flip保留: `EnemyTurnDriver` mid-frame（:118/:141/:268）は mid-frame sync 後
- [x] **statusEffects ECS 層 完成・検証済み（2026-06-27・レビュー91）** — Bevy 正対の `World.Command`/`World.Query` effect、
  `EntityRef` キー抽象（faction 非依存 seam・将来 Option A は World.flix 内部だけで）、`applyCmd`/`overEntity` applier（`StatusSystem`
  再利用）、Game.start handler 配線。`statuses`→`statusEffects` rename＋`StatusEffects` 型 alias。**878緑**（applyCmd 8 ケース＋
  faction ルーティング＋**effect 経由 end-to-end** テスト）。**まだ gameplay から emit せず＝挙動不変**。次は emit-flip（上記「次の一手」）
- [x] **emit-flip E1〜E3（Command 書込 seam・dual-write・878緑）** — gameplay の status 変更を Command emit（tick/add/clear）。**毎フレーム mirror に上書きされる無害な dual-write ＝将来 flip 用インフラ**
- [ ] ~~emit-flip E4（権威 flip）~~ — **defer 確定（§A 整合・read-model 維持）**。reader が pure で Query 注入が伝播／reader を scene に残す案は「割の合わない flip」。決定論/replay の payoff 時に再開
- [ ] ~~S1b-flip~~（read-model 時代の不採用判断・上書き）
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
- **S4（toBoard/boardPieces）**: 地形射影は既存 `BoardSnapshot.fromParts` 内の map 構築を `mapSnapshotOf` に**抽出して共有**（再実装せず
  fromScene/fromParts も同一関数を経由）。`Board`/`Piece` 型・hidden フィルタ規約も既存を踏襲。新規は World→pieces の組み立てのみ。
  **配置**: World だけ読む射影は **ecs/ 層（World.toBoard/boardPieces）**へ。scene 読み取りの `mapSnapshotOf` は scenes/ に残す
  （層を逆にしない＝ecs/→scenes/ の一方向。BoardSnapshot は World を参照しない）。

### ロールバック手順（各ステップで追記）
- 共通: 切替後に parallel-run が割れたら、そのサブシステムを scene 経路へ即戻す（World 並走は残す）。
  S4 は call-point 単位で `fromWorld`→`fromScene` に個別復帰。
