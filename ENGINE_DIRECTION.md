# エンジン方向性 / 設計思想の決定

エンジンを本格的に育てるにあたり、現状の設計思想のうち **守るべきもの** と **変えるとさらに良くなるもの** を棚卸しし、以後の全判断の基準（北極星）とするための決定ドキュメント。2 人の批判的レビュアーと壁打ちし、`engine/src` と `examples/fe_rogue`（最大の実例: FE 風タクティカルローグライク。game 50 / scene 47 モジュール）の実コードを根拠に検証した結論。

---

## 確定したアイデンティティ

> **「コードをきっちり書くエンジニア向けの、汎用 FP ゲームエンジン」**

- 多くのゲームを量産できる土台であること（game #2 を additive に作れる）を重視。
- IDE は **土台**として提供し、各プロジェクトが **コードで拡張**する前提。非プログラマ向けの GUI 完結は狙わない。
- **Godot は「語彙」として残し、「制約」としては撤廃する。**

含意: 「IDE は `NodeTag` を表現しきれず構造的に頭打ち」という指摘は、エンジニア向けでは弱点ではない。挙動はコードで書くのが前提で、IDE は骨格（位置・可視・z・レイアウト）を編集できれば十分。よって **FP-native な差別化機能こそ主戦場** になる。

---

## 守る良い思想 — 理由つき

1. **不変シーンツリー（"frame is a value"）**
   `Scene = Map[NodeName, SceneEntry]`、構造共有 + `modifyAt` で部分更新（毎フレーム全再構築ではない）。undo / snapshot / リプレイ / セーブが**ほぼタダ**。`FloorSnapshot` が既に証明。FP エンジンの核。**触らない。**

2. **純粋 `game/` と presentation `scenes/` の分離 + 一方向依存**
   Board / Combat / pathfinding / AI が Scene 非依存で単体テスト可能。`scenes/ → game/` の逆流禁止。最も健全な資産。

3. **代数的エフェクト = 静的に検査される「能力リスト」**
   `\ {PartyQuery, FloorAdvanceRequest}` は Godot のどんな signal より表現力が高い。「この関数は何を読み・何を要求するか」が型に出る。**Godot signal を絶対に入れない**理由でもある。

4. **ハンドラ注入（DI）**
   `EffectRunner` の handler bundle で、同じ Plan を「Scene 変更」にも「テスト用の記録リスト」にも流せる。テスト容易性の源泉。

5. **write-request エフェクト（`GameOverRequest` / `FloorAdvanceRequest` 等）**
   `scene` を明示的に受け取り、継続で新 `scene` を返す。本アーキの**真の宝**。read 系より曖昧さがなく安全。

6. **データ駆動: `scene.json` + Effect DSL**
   ツリー宣言と特殊効果の宣言化（`EffectRule → EffectPlan → EffectRunner`）。コード変更なしでコンテンツ追加できる方向は正しい。

7. **Godot の「語彙」**
   ノード分類・CanvasLayer/カメラ変換分離・y-sort・ready/process ライフサイクル。2D の正しいモデルで FP に綺麗に載る。命名規約・メンタルモデルとして残す（ノード分類を自前で再発明する労を省く）。

8. **描画基盤**
   SDF フォント / GPU インスタンス tilemap / polygon-sprite 描画パリティ。既に堅実。維持。

---

## 変えると良くなる思想 — 理由 + 優先度

### ★ Keystone（最優先）: Godot を「制約」から「語彙」へ

「engine 追加は Godot 対応物に限る / scene.json 宣言可能であること」という**ゲートを撤廃**する。これが他の全修正の許可証。

- 害の実例: 「ターン進行ノード」が Godot に無いため、`EnemyTurn.Queue`（bespoke effect）+ ダミー Marker2D の `EnemyTurnDriver` タグ + `_process` ポーリング + Tween-active 監視、という **偽の逐次処理** を手組みする羽目になっている。
- 残すのは Godot の **データモデル**（tree / resource / scene-instancing）。捨てるのは Godot の **実行モデル**（可変ノードの per-node `_process`）。後者こそ Flix と摩擦している正体。
- ※ engine への独自追加は「事前相談」原則自体は維持してよい。変わるのは「Godot 対応物でなければ却下」という判定基準。

### 方向を決める 3 つ（高レバレッジ）

**1. 中央集権 match dispatch と `checked_ecast` 壁の撤廃**（コード価値最大）

- 現状: `examples/fe_rogue/src/game/Game.flix` は 988 行、`checked_ecast` 58 箇所（全 89 の 65%）。型推論の複雑度上限に当たり dispatch を 4 関数に分割済み（`dispatchEntities/Tickables/Drivers/Menus`）= 既に天井に当たっている。
- 問題の本質: 各 `XxxScene.process` はエフェクト行が異なるのに、単一 `instance Node[NodeTag]` が 1 つの `Aef` に押し込むため、**最も分岐の多い場所で静的エフェクト検査を `checked_ecast` で無効化**している。エンジンの売り（静的エフェクト安全性）が、最もバグを捕まえたい routing 継ぎ目で OFF になっている。
- 方向: 中央 match を廃し、**ノード挙動を `NodeTag` 側に持たせる**（`Behavior` レコード/トレイト `{process, physicsProcess, onInput}` を state と並置）か、各 Scene が自分の handler を**登録**する registry へ。各挙動が自前のエフェクト行を宣言でき、`Game.flix` は登録リストへ縮む。game #2 が surgical → additive に。
- **`checked_ecast` 件数を健全性メトリクスとして監視**（上昇 = 結合の温度計）。

**2. 逐次処理 / スクリプティングを代数的エフェクトの一級市民にする**（最大の戦略ベット）

- `await アニメ` / `wait(dur)` / `parallel` / `sequence` を提供する `Sequence`/`Script` effect。Flix の限定継続はまさにコルーチン。
- 効果: `EnemyTurn` / `StairsExit` / `LevelUpPanel` / `BattlePanel` が **線形で読めるスクリプト** に畳まれ、`EnemyTurnDriver`/`Queue`/`Pacing`/Tween ポーリングの塊が消える。さらに cutscene・dialogue・JRPG 戦闘演出・ビジュアルノベルが解禁。
- 「Godot を不変にしただけ」から「**ゲーム進行が型付きで読めるスクリプトになるエンジン**」へアイデンティティが変わる。Godot/Bevy/Elm が構造的に綺麗にできない領域 = 真の moat。

**3. `game/` のエンティティに安定 ID を与える（ECS にはしない）**

- 症状の根: `ItemKind = Weapon(Int32)` がリスト相対 index を持ち、`PlayerData.flix` に「大きい index から消す」儀式コメント。MoveDraft の revert 3 点修正も同病。
- 修正: `ItemId` newtype を導入し `ItemKind` は slot でなく id を持つ。インベントリを `Map[ItemId, _]` に。**engine 非依存・`game/` ローカルで小さく済み**、ItemKind off-by-one と MoveDraft の痛みの大半が消える。
- **ECS にはしない**: ECS は数千の均質エンティティのキャッシュ局所性問題用。タクティクスの数十ユニットには `Map` で足り、ECS は不変性・エフェクトという差別化と真っ向から喧嘩する。シーンツリー側は `NodeName` パスで既に安定 ID を持つ（問題は `game/` のインベントリ模型だけ）。

### 衛生（方向は変えない / 機を見て対応）

4. **決定論 / リプレイの仕上げ** — `FloorSnapshot`・`SuspendSave`・`RandomUtil` で既に約 60% 出来ている。seed + 入力ログ → 不変 Scene で再生は FP エンジン固有の署名機能。デバッグ基盤兼アピール材料。

5. **`physicsProcess` / RigidBody / gravity の見直し** — グリッドタクティクスでは過剰。fe_rogue は `physicsProcessAll` を「選択ユニットの方向キー読み取り」にしか使っていない。汎用エンジンとしては残してよいが、tactics 系で物理ライフサイクルに入力ポーリングを乗せている事実を認識し、軽量入力フックを別途用意する余地。

6. **query effect は read/write firewall を維持。reads のまとめは慎重に** — `BoardQuery`/`PartyQuery`/`RosterQuery` は最大 3 個程度でまだ危機ではない。**単一 ambient context に潰すとテスト粒度（「この関数は roster を読まない」の型保証）を失う**。やるなら read 系のみ 1 つの `WorldQuery`（party/roster/board アクセサ付きレコード）に束ね、write-request とは分離したまま、が中間解。なお read 系は実装上「フレーム境界 snapshot を Ref から読む = 変装した可変グローバル」。`scene` を明示受け渡す write 系の方が安全 — 「query は安定した横断 read 専用、in-flight write の真実源にしない」を**ハードルール**としてエフェクト定義に明記。

7. **render を単一 fold パスへ**（perf、急がない） — `render()` が `preorderPaths` を 3 回、各ノードで `globalPositionAt`/`effectiveModulateAt`/`effectiveZIndexAt`/`effectiveVisibleAt` が祖先を毎回再走査 = 概ね O(N·depth) を何重も。fe_rogue 規模では不可視。1000+ エンティティで崖。修正は標準的: **継承コンテキスト（累積 transform/modulate/z/visible）を 1 回の preorder で畳み** 全描画コマンドを一括生成。**不変性は無罪**（崖の正体は「素朴な top-down アクセサの反復」）。

8. **EffectBridge 移行のカットオーバー期日を切る** — 旧 enum と DSL の二重保守は移行の臭いであって設計欠陥ではないが、**停滞すると恒久的二重保守になる**。weapons.json/rings.json への効果直接宣言へ移し、旧 enum を廃す期限を決める。

9. **巨大ファイルの分割** — `PlayerScene.flix` 1607 行 / `StaffCastScene` 1303 / `CombatScene` 1018 / `ItemMenuScene` 938 / `ide/MapEditorPanel` 3306。アーキより先に月次の変更速度を落とす。1 Scene が背負いすぎ。

---

## 明示的に「やらないこと」

- **ECS 化しない** — 目的（不変・リプレイ・エフェクト）と喧嘩する。`Map[Id, _]` で十分。
- **FRP / signal バスを入れない** — `_process` + effect の方が「frame is a value」と整合しデバッグ容易。
- **query effect を単一 ambient context に潰さない** — テスト粒度の型保証を失う。
- **IDE を非プログラマ向けに作り込みすぎない** — 対象はエンジニア。IDE は土台 + 各自コード拡張。レベル/レイアウト編集ビューに留め、浮いた工数を sequencing effect と決定論リプレイへ。

---

## ロードマップ（方向 → 検証）

各ステップは独立に着手可能。`make sync-engine` 後に該当 example のテスト（Option.map/flatMap 方式・1 アサート・tagOf 慣習）で回帰確認する。

1. **Keystone を文書化** — CLAUDE.md / engine-guide スキルの「Godot 対応物に限る」判定を「Godot データモデルに準拠、実行は FP-native」へ改訂。これが他修正の許可証。
2. **dispatch リファクタの spike** — 小さな Scene 1 つで「behavior を `NodeTag` 側に持たせる or registry 登録」を試作し、`Game.flix` の `checked_ecast` 件数が減ることで検証。
3. **sequencing effect の spike** — `Sequence` effect（`await`/`wait`/`parallel`）を試作し `EnemyTurn` を線形スクリプトに書き換え。既存テスト（handler 記録方式）で挙動同値を確認。
4. **`ItemId` 化** — `game/` ローカル。既存 `test/TestEffectPlan`・インベントリ系テストが緑のまま off-by-one 懸念が消えることを確認。

### 主要ファイル

| ファイル | 役割 / 論点 |
|----------|------------|
| `examples/fe_rogue/src/game/Game.flix` | 中央 match dispatch / effect 配線 / 偽ターン進行。方向 1・2 の起点 |
| `examples/fe_rogue/src/game/EnemyTurn.flix` | sequencing effect が置き換える bespoke queue |
| `engine/src/scene/Node.flix` | per-node behavior dispatch へ育てる/置換するライフサイクルトレイト |
| `engine/src/scene/Scene.flix` | 不変ツリー（リプレイの強み）と `foldNodes`/`modifyAt`（perf 天井） |
| `examples/fe_rogue/src/game/PlayerData.flix` | `ItemKind` の index 化と shift 回避コメント（方向 3 の起点） |
| `engine/src/GameEngine.flix` | `render()` の三重 preorder と祖先再走査（衛生 7 の対象） |
