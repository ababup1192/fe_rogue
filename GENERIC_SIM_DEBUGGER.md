<!-- 受領: 汎用 sim デバッガ＋VS フレームワーク計画（2026-06-29）。fe_rogue 偏重 Tier1 を一般化。
VISUAL_SCRIPTING_TIER1.md（fe_rogue 応用例の原典）と対。:NNN は ef92583 スナップショット＝二次・def 名一次。
engine GraphEdit/GraphNode 等は grep で不在確認＝新規=要事前相談。 -->

# 汎用 sim デバッガ＋ビジュアルスクリプティング フレームワーク — 計画 v4

> 位置づけ: 既存 `VISUAL_SCRIPTING_TIER1.md`（fe_rogue 専用の「捕捉→fold→射影」デバッガ）を **engine 側の World 型変数化された汎用ハーネス＋プロジェクトが供給する seam** に一般化し、fe_rogue をその**応用例**へ降格する。汎用コア部は型/関数名で記述し、fe_rogue 固有の `:NNN` 行アンカーは §6 にのみ隔離する。

> **ベースライン（再現可能性）**: 実 HEAD は `ef92583`。「ロジック不変」の検証は doc に依存させず、**既存の実テスト `test/ecs/TestGoldenTrace.flix` を一次の検証基盤**とする。ただし v4 で**検証基盤の正確な切り分け**を行った（§1.1・§6.1・§7-1a）: golden（`testGoldenLevelUp`/`NoLevelUp`）は **legacy 経路の cmdKey 射影列**を凍結し、System 経路（`resolveAttack`）は **`killProj` の final-World 等価のみ**で pin されている。**この 2 基盤は別物で、harness が駆動するのは System 経路ゆえ golden の cmdKey 列を直接再現する保証は無い**（§6.1 blocking）。

> **grep スコープ規律**: 「engine に X が存在しない」は **engine/src/scene 全体＋ trait 宣言全件**を grep してからのみ書く。単一ファイル grep から engine 全体の不在を一般化しない（§5.1 の v2 誤断の構造的修正）。

---

## 1. 目的と「汎用化で何が変わるか」

**before（Tier1）**: `SimTrace = {initial: World, events: List[SimEvent]}` も capture/`worldsAfter`/rewind/timeline も全て fe_rogue の `World`/`SimEvent` に直結。ロジックはゲーム知識ゼロなのに型が固定され他プロジェクトへ移植不能。

**after（本計画）**: capture/step/rewind/timeline を **World 型・Event 型に parametric** な engine ハーネスへ抽出し、ゲーム固有能力を**プロジェクトが供給する seam** として外出しする。fe_rogue は「seam を埋めた 1 インスタンス」になる。

**変わること**:
- `SimTrace`／`worldsAfter`／snapshot rewind／タイムライン射影を型変数 `w`/`ev` に置換して `flix_engine_ecs` の新モジュールへ移す（ロジック不変）。
- fe_rogue に残るのは「seam を埋める薄い record＋driver」＋固有 projector（human-text projector の新規実装・view レーンの既存 `ViewReplay.plan`）だけ。
- Tier1 が列挙した限界（比較サイドカー／演出 rewind／live-seed 注入）は、汎用層では **seam の API 制約**として再表現する。

**変わらないこと（誇大回避）**: 汎用化は「再利用可能な型変数化」であって、Tier1 が出せなかった情報（命中ロール等）を新たに出せるようにはしない。それは各プロジェクトの seam 実装次第（§8）。

### 1.1 「ロジック不変」を実装者が検証できる不変条件（doc 非依存・実コード基盤・v4 で精密化）

**重要な前提（v4 blocking 訂正）**: 既存 golden は **raw `SimEvent` 列を凍結していない**。`SimEvent` は Eq 非派生ゆえ、golden は必ず**射影経由**で比較される。実テストが凍結するのは 2 種:

- **(a) cmdKey タプル列**: `testGoldenLevelUp`（`:235`）/ `testGoldenNoLevelUp`（`:265`）は **legacy 経路 `runAttack`→`applyAttackHitLegacy`**（`:163,173`）を駆動し、その emission を `(String, Int32, Int32, Int32)` の cmdKey タプル列（例 `("SetHp",1000001,0,0)::("Dying",1000001,0,0)::…`・`:242-250`）として凍結。
- **(b) 最終 World 射影**: 同テストが `(hpOf, hpOf, progressOf)` を別 assert で凍結（`:253-257`）。

**System 経路（harness が使うのはこちら）の pin は別物**: `resolveAttack` は `testResolveCombatEqualsLegacy*`（`:298,310,322`）が **`killProj`＝final-World 射影のみ**（`:288`）で legacy と突き合わせる。テスト本体コメント（`:308`）が **「draw 順差は最終 World に効かない範囲で」legacy 等価**と明記＝**System 経路の event 順序列は legacy golden に pin されていない**。

→ 汎用化が既存挙動を保存する、を実装者が pin できる不変条件:

1. **System 経路 final-World 等価（一次・確実）**: harness の `worldsAfter`/`worldAt` fold が `resolveAttack`/`resolveEnemyAttack` 由来 trace を畳んだ終端 World が、`killProj` 射影で legacy 凍結値（`:298,310,322`）と一致。**これは既存 pin がそのまま使える唯一の確実な検証**。
2. **cmdKey 射影の SEQUENCE pin（要新規テスト・成否は未確定）**: もし「順序付き列」を pin したいなら、**System 経路の event 列を cmdKey 相当へ射影して golden cmdKey 列と比較する新規テスト**を §7-1a の合格条件に足す。**ただし legacy（applyAttackHitLegacy）と System（resolveAttack）は draw 順・emit 単位が異なりうる**（legacy は thief/crit を別 draw 順で引く・§6.1）ため、**この新規テストは pass しない可能性があり、その場合は cmdKey SEQUENCE pin を諦め (1) の final-World 等価へ後退する**ことを事前合意する。
3. **refold 一貫性不変（正直化）**: `worldsAfter` の「全 scan」と `worldAt(k)` の「先頭 k refold」は同一 fold の 2 経路で一致＝純性・決定性のクロスチェック。**注意（誇大回避）**: `SimTrace = {initial, events}` は snapshot 列を保持しないので、これは「保存済み snapshot == refold」ではなく「scan 経路 == index 経路」の一致でしかない。真の「live snapshot == refold」が要るなら §3.2 任意 memo フィールドを足して初めて成立。

---

## 2. 汎用インターフェース seam（Flix 表現可能性の裏取り）

プロジェクトが供給する能力。v4 で **5 seam ＋健全性法 L** に拡張:

| seam | シグネチャ（型変数 `w`=World, `ev`=Event） | 純度 |
|---|---|---|
| (a) 純 reducer | `applyEvent: ev -> w -> w`（**純かつ ev 型上で total** であること＝§2.3 契約） | 純 |
| (b) タイムライン射影 | `describe: ev -> TraceRow`（**generic seam に入るのはこれ 1 本のみ**・TraceRow は opaque・§4.2 improvement） | 純 |
| (c) 直列化 | `serialize: w -> Json` / `deserialize: Json -> Option[w]` | 純 |
| (d) RNG/seed seam | System を走らせる effect の決定論 discharge 機構（§6.4・**capture 後 events は post-roll** ＝§2.4） | effectful |
| (e) 純 System（＋driver） | 実体 System は追加引数を取る → driver で `w -> (w, [ev]) \ ef` に絞る（§6.1） | effectful（`ef` 多相） |
| **(L) 健全性法（v4 新規 blocking#1）** | **`fst(driver(w)) == foldLeft(applyEvent, w, snd(driver(w)))`** ＝driver の World 変異と applyEvent 列が一致（events が World 遷移の唯一の権威） | 法（強制不可・CI 検証） |

### 2.1 法 L が generic-soundness の linchpin（v4 blocking#1）

汎用デバッガが「無言で嘘をつかない」中核条件は、**driver が返す World == `foldLeft(applyEvent, initial, events)`**＝events が World 遷移の唯一の権威であること。これは型では強制できない（driver はプロジェクト供給物）ので**明文の seam 法**として課す。

- **fe_rogue はこの法を構造的に満たす（裏取り）**: `resolveAttack` は `(applyAll(events, world), events)`（`CombatSystem.flix:226`）、`resolveStaffCast` は `(applyAll(events, world), events)`（`StaffSystem.flix:37`）で、いずれも **返す World を「返す events を applyEventToWorld で fold して」構築**している。`applyAll` の中身は `applyEventToWorld`（＝seam (a)）の foldLeft ゆえ、`worldsAfter` の fold と**定義的に一致**する。つまり fe_rogue では法 L が機械的に保証される。
- **汎用層での強制**: §7-1b の CounterWorld ゲートに **`assert fst(driver(w0)) == worldsAfter 終端 World`** を CI で課す。これで「events が World 遷移の唯一権威」が fe_rogue を import しない parametric 層で機械検証され、blocking#1 が閉じる。
- **§1.1 不変3 との関係**: 不変3 が「scan 経路 == index 経路」止まりだった真因はこの法 L が未明文だったため。法 L を CI 強制して初めて「capture+worldsAfter+worldAt が driver に忠実」が担保される。

### 2.2 Flix での表現可能性（実 engine の trait で裏取り）

調査した実 trait は **すべて単一型パラメータ**: `Saveable[a]`（`Persistence.flix`）、`Node[s]`（`scene/Node.flix:15`）、`InputHandler[s]`（`scene/InputEvent.flix:22`）。**多パラメータ trait（`Trait[w,ev]`）も associated-value-type trait も engine/engine_ecs 全域に 0 件**（grep 確認）。

**確定設計（唯一の主設計）= record-of-functions（capability record）**。trait 版は任意 stretch（§7 spike 0(i)）。

```
// flix_engine_ecs 新モジュール SimHarness（擬似・型変数 w, ev）
type alias SimSpec[w, ev] = {
    applyEvent  = ev -> w -> w,                       // 純（seam a）
    describe    = ev -> SimHarness.TraceRow,          // 純（seam b）
    serialize   = w -> Util.Json.Json,                // 純（seam c）
    deserialize = Util.Json.Json -> Option[w]         // 純（seam c）
    // (d) RNG seam と (e) System/driver と (L) 法は record に入れない（§2.5）
}
```

**engine イディオムとの関係（v4 engine-honesty 訂正）**: v3 は「engine の既存イディオムに完全準拠」と書いたが過大。**engine_ecs/engine に capability-record（≥2 個の関数フィールドを束ねた type alias）は 0 件**（grep 確認）。引用した `EcsCodec.encodeStore(encodeC: c->Json)`・`Query.indexBy(keyOf, valOf)` は「**closure を引数として 1〜2 個直接渡す**」前例にすぎず、`SimSpec`（4 closure を 1 record に束ねる）には**直接前例が無い**。正直化: **「closure-as-param イディオムの自然な延長。ただし capability-record（複数 closure を束ねた型）自体は engine_ecs 初出」**。ゆえに §7 spike / §8 要相談に「複数 closure を束ねた record の型推論が engine_ecs で初実証」を 1 行明記する。

なお **SimSpec が束ねるのは純 closure のみ**（applyEvent/describe/serialize/deserialize は全て effect-free）。effect 多相 closure（driver）は **意図的に record の外**に置く（§2.5）ので「effect 多相 closure を record 格納」の型推論問題は本設計では発生しない。

**serde seam (c) の trait 再利用**: serde だけは既存 `Saveable[a]` trait を再利用（単一パラメータ＝前例と整合）。fe_rogue は `instance Saveable[World]` を `EcsCodec.encodeStore/decodeStore` で構成。

### 2.3 seam (a) の純度・total 契約（v4 improvement）

汎用層が serde 経由でロードした trace を fold する際の健全性前提を明文化する: **`applyEvent` は純かつ `ev` 型上で total**。`deserialize: Json -> Option[w]` は World を再検証するが、**events 列は再検証されない**＝未検証 Json 由来の `ev` が `applyEvent` に流れうる。よって seam 契約に「`applyEvent` は任意の構築可能な `ev` 値に対して停止し例外を投げない（total）」を課し、untrusted trace を畳む汎用層の健全性を保証する。fe_rogue の `applyEventToWorld` は CLOSED enum 上の網羅 match で total（裏取り: `World.flix` の reducer は `SimEvent` 全変種を match）。

### 2.4 seam (d) RNG の post-roll 不変（v4 improvement・サイドカー限界の seam 由来導出）

seam 契約に **「capture 後の events は post-roll（ロール結果を符号化し roll 値自体は持たない）」** を明記する。これにより §8 のサイドカー限界（命中ロールは `describe` だけでは出せない）が、**各プロジェクトで構造的に必然**であることが seam から導ける: roll 値は capture 時の RNG discharge で消費され events には結果（dmg/killed 等）しか残らないので、`describe: ev -> TraceRow` は原理的に roll 値を復元できない。汎用性の境界がより明瞭になる。

### 2.5 seam (d)(e)(L) を record に入れない理由

driver `w -> (w, List[ev]) \ ef` は effect 多相。record フィールドに effect 多相 closure を格納すると discharge 地点が消えて型が固まらない。よって capture が driver を**直接引数で受け取り `\ ef` で多相化**する（§3.2）。RNG discharge は capture を呼ぶ前に region 内で thunk を包む形でプロジェクト側に残す（§6.4）。法 L は型でなく doc＋CI（§2.1）。

---

## 3. engine 提供ハーネス（capture/step/rewind/timeline・lib 配置）

### 3.1 どの lib に置くか（根拠付き選定）

**選定: 既存 `flix_engine_ecs`（engine_ecs/）に新規モジュール `SimHarness.flix`（＋必要なら `TraceRow.flix`）。新規 lib は作らない。`flix_game_engine`（engine/）には置かない。**

根拠:
- `engine_ecs/flix.toml:2,3`: name=`flix_engine_ecs`, desc=**「Reusable immutable-ECS modules (EntityId, Query combinators, Collision broadphase) for games built on flix_game_engine」**（v4 で実引用に訂正・v3 の「…Codec…」は誤り）。ハーネスは World に parametric・ゲーム知識ゼロ・純粋＝憲章「Reusable immutable-ECS modules」と一致。
- 既存同居モジュールが同型: `Query`（純コンビネータ）、`EcsCodec`（汎用 component-store JSON 往復）。`SimHarness` はこれらの隣に自然に座る。
- serde 再利用: `EcsCodec.encodeStore/decodeStore`（同 lib 内）＋ engine `Saveable` ＝依存追加なし（fe_rogue は両 lib に既に依存）。
- engine（flix_game_engine）を**外す理由**: そこは render_core・scene ノード・GameEngine ランタイム・**Godot 鏡像層**。純 sim ハーネスをここに置くとネイティブランタイム層へ不要結合（altitude 違反）。

### 3.2 汎用ハーネス API（型変数化・capture は薄い adapter と正直化）

```
mod SimHarness {
    type alias SimTrace[w, ev] = { initial = w, events = List[ev] }

    // capture: driver への薄い adapter（v4 improvement で正直化）。
    // 本体ロジックは worldsAfter/worldAt/timeline の fold＋射影であり、capture 自体は
    // 「driver を 1 回走らせ events を取り出す」ラッパにすぎない。harness primitive として
    // 過大表示しないよう、runSeq を driver 構築ヘルパとして併置する。
    pub def capture(initial: w, driver: w -> (w, List[ev]) \ ef): SimTrace[w, ev] \ ef =
        let (_, evs) = driver(initial);                       // ← 1 行 wrapper
        { initial = initial, events = evs }

    // runSeq: 複数の DISTINCT System を 1 つの evolving World に左 fold し ev 列を連結（driver 構築用）。
    // ※用途は「異なる System の連鎖」＝fe_rogue では CounterChain（resolveAttack→resolveEnemyAttack）。
    //   単一 System 内部の派生（撃破→level-up）は runSeq ではなく System 1 呼び出しが emit する（§6.1）。
    pub def runSeq(systems: List[w -> (w, List[ev]) \ ef], w0: w): (w, List[ev]) \ ef = ...

    // step: applyEvent の foldLeft 蓄積（純・全 scan）← 汎用機構の本体①
    pub def worldsAfter(spec: SimSpec[w, ev], t: SimTrace[w, ev]): List[(ev, w)] = ...

    // rewind: 先頭 k 件 refold（純・snapshot 列は保持しない＝§1.1 不変3 の注意）← 本体②
    pub def worldAt(spec: SimSpec[w, ev], t: SimTrace[w, ev], k: Int32): w = ...

    // timeline: describe 射影（generic seam (b) を消費するのはここだけ）← 本体③
    pub def timeline(spec: SimSpec[w, ev], t: SimTrace[w, ev]): List[TraceRow] =
        List.map(spec#describe, t#events)

    // 保証下限: stdout ダンプ（println 床は常に有効）
    pub def dumpAt(spec: SimSpec[w, ev], t: SimTrace[w, ev], k: Int32): Unit \ IO = ...
}
```

**`\ ef` 多相が load-bearing である具体証人**: fe_rogue の System は `resolveAttack`/`resolveEnemyAttack`（`\ World.RngDraw`）と `resolveStaffCast`（**effect-free**＝`StaffSystem.flix:32` は返り `(World, List[SimEvent])` に `\` 無し）の双方を持つ。前者で `ef = RngDraw`、後者で `ef = {}`（純）に縮退し、**同一 `capture`/`runSeq` が両方を通す**。

step/rewind が **RNG を一切引かない純 fold** である点は型変数化後も不変（`applyEvent` 純なら成立・fe_rogue は `applyEventToWorld` 純）。

### 3.3 TraceRow を opaque に確定（v4 improvement）

generic core にゲーム概念が滲む leak を防ぐため、`TraceRow` を engine_ecs 側で**不透明テキスト＋タグ**に確定する:
```
type alias TraceRow = { label = String, tags = List[String], detail = Util.Json.Json }
```
汎用 `describe` 射影は **不透明な label＋tags＋Json detail に限定**し、fe_rogue 固有のレーン/命中/combat 概念を generic core 型に持ち込まない。fe_rogue の human-text projector はこの 3 フィールドに自分の語彙を詰める（例 `label="enemy#1 撃破"`, `tags=["kill","levelup"]`）。

### 3.4 直列化と決定論（汎用層の契約）

- **in-memory rewind は常に成立**: World が plain data（不変値・Scene 非保持）なら純 fold で巻き戻る。seam 契約に「World は plain data であること」を明記。fe_rogue World は満たす。
- **on-disk serde は seam (c) 任せ**: `EcsCodec`＋`Saveable` で実装。
- **決定論 seam (d)**: 「同 seed → 同 draw 列」を保証する純 PRNG をプロジェクトが供給（fe_rogue は `Prng.flix`）。capture 時のみ effect が走り、step/rewind は純。**continuation（rewind 地点から再 sim）は終端 RNG state の carry が要る＝汎用層もスコープ外**（§8）。
- **任意 memo 拡張**: SimTrace に `snapshots = List[w]` を足し capture 時に live World を逐次保存すれば、§1.1 不変3 が「live snapshot == refold」の真のクロスチェックになる（既定 OFF）。

---

## 4. 汎用ノード分類（taxonomy＋ポート登録機構）

Tier2 authoring の語彙確定。§5 の GraphEdit UI（新規・要相談）が載る土台。本章は**設計のみ**。

### 4.1 taxonomy（5 分類・「universal」の射程を §4.2 と整合させる）

| 分類 | 役割 | 汎用グラフ上の表現 | seam との対応 |
|---|---|---|---|
| **Source/Query** | World から値を読む | 出力ポートのみ | `w -> a` accessor を登録 |
| **Compute** | 純変換（rule） | 入力 N→出力 M の純ノード | 純 `rule` 関数を登録 |
| **Control** | **branch / seq のみ** | 制御フロー | describe 分岐・driver の System 列順序 |
| **Sink/Emit** | Event を産む | 入力ポート＋ev 出力 | seam (e) System/driver が emit する `ev` 構築 |
| **Probe** | 観測点（タイムライン行） | 副作用なし tap | seam (b) `describe` ＝ Probe 射影 |

**「universal」主張の射程を正直化（v4 blocking#2）**: §4.1 の taxonomy が universal なのは **Int/Bool/EntityId のスカラ層のみ**。ゲーム固有型（後述 §4.2）が支配的な実プロジェクトでは型安全な汎用グラフは装飾に縮退する。よって見出しは「**universal taxonomy（語彙は普遍・型安全はスカラ層に限る）**」と表現し、§4.2 の縮退定量化とトーンを揃える。

**fold はグラフノードではない**: fold は §3 ハーネス自身（`worldsAfter`/`runSeq`）が供給する暗黙の駆動機構。authoring グラフでユーザーが置くのは branch/seq まで。

### 4.2 ポート登録機構（型安全の縮退を定量化）

```
type alias NodeSpec[w, ev] = {
    kind    = NodeKind,                            // Source|Compute|Control|Sink|Probe
    inputs  = List[PortType],
    outputs = List[PortType],
    eval    = List[PortValue] -> List[PortValue]   // 純（Sink のみ ev を産む）
}
```
`PortType`/`PortValue` は engine 定義の汎用 tagged union（Int/Bool/EntityId/Json…）。engine はゲーム型を知らずグラフを評価でき、プロジェクトは `eval` closure に自分の `World`/rule を閉じ込める。永続化は `EcsCodec` 同様の Json 往復。

**型安全の縮退を定量化（裏取り済み）**: tagged union の固定枝に入らないゲーム固有型は「Json 経由 opaque port」に退避＝**型安全は part-way**:
- **Source/Query 戻り値**: `w -> Combatant`（`CombatSystem.flix:53` の `type alias Combatant`）のような固有 record を返す Source は ほぼ全て opaque-Json 化（tagged union に Combatant 枝は無い）。
- **Sink/Emit の ev payload**: `SimEvent` の構築引数（固有 enum/record）も opaque 化しやすい。
- 逆に Int/Bool/EntityId に閉じる Compute/Probe は型安全を保てる。

→ **「型安全な汎用グラフ」の主張はゲーム固有型が多い射程で大きく劣化する**。UI 着手前に確定すべき設計論点（§8 要相談）。

---

## 5. ビジュアル UI の engine 対応物（GraphEdit 既存調査・入力面の正しい切り分け）

**grep 結果（engine/src・engine_ecs/src・examples/fe_rogue/src・exit=1＝0 件）: `GraphEdit`/`GraphNode`/`VisualScript`/`NodeGraph` は存在しない。** engine の scene ノード在庫は Godot 準拠の 2D/UI ノード群（Sprite2D/Label2D/Camera2D/Control/Panel/Button/ItemList/RichTextLabel/ColorRect/TileMapLayer 等・`SceneLoader.flix:351-371` の dispatch で確認）。**node-graph 編集ノード（Godot の GraphEdit/GraphNode 相当）は無い。**

### 5.1 入力面の正しい切り分け（v2 の blocking 誤認を撤回・実機確認）

**v2 は「node-graph 入力ルーティングは engine に存在せず新規 seam 新設が要る」と書いたが engine 全体では事実誤認（Node.flix 単一ファイル grep の過剰一般化）。** 実機確認:

- **`InputHandler[s]` trait が実在**（`scene/InputEvent.flix:22`）。メソッド: `onKeyPressed:29`/`onKeyReleased:33`/`onMouseButtonPressed:38`（座標付き）/`onMouseButtonReleased:44`（座標付き）/`onMouseMotion:52`/`onMouseEntered:60`/`onMouseExited:65`/`onMouseHover:72`。associated effect `type Aef: Eff`（`:25`）で instance ごとに副作用宣言可。
- **入力ディスパッチ機構も実在**: `handleInput`（`:101`）が前フレーム差分からマウス入出/ホバー/クリックを各ノードへルーティング。
- **ヒットテスト基盤も実在**: `Scene.hoveredPathsAt`（**def 行 `Scene.flix:544`**・`InputEvent.flix:140` で使用）＋ `Scene.globalPositionAt`（def `Scene.flix:476`）＋ `getGlobalRect`（`:529`）。

**結論（正しい切り分け）**: node-graph 編集の**入力ルーティング層は既存**（`InputHandler`＋`Scene.hoveredPathsAt`/`globalPositionAt` を再利用）。真に engine 新規が要るのは:

- **新規 scene ノード `GraphEdit[s]`/`GraphNode[s]`**（接続線ジオメトリの描画とヒットテスト・ポートスナップ判定）。**既存ヒットテストでは不足する根拠（v4 で def＋AABB 行を一次 pin）**: `hoveredPathsAt`（def `Scene.flix:544`）は `EngineNode.getSize` の **AABB 矩形包含**（`Scene.flix:558` で `Rect2 {position=globalPositionAt, size}` を構築し点包含判定）でノードを hit-test する。**接続線は AABB を持たない線分**ゆえ、点-AABB 判定では拾えず**線分-カーソル距離判定が真に新規**。
- **`SceneLoader` 対応**: `SceneLoader.flix:351-371` は `case "Sprite2D" => buildSprite2D(tagParser, map)` 形の**文字列キー dispatch**で、`case "GraphEdit" => buildGraphEdit(...)` を**同型で追加可能**（v4 改善: 拡張可能 dispatch であることを代表行で裏取り）。これにより**scene JSON first**（`[[feedback_scene_json_first]]` 準拠）が UI 着手前に実現可能と確証。

`Node` trait 自体（`scene/Node.flix:15`）が input を持たない（6 メソッド: ready/process/physicsProcess/isTimedOut/clearTimedOut/getProcessMode）のは事実だが、**入力は別 trait `InputHandler` が担当**。GraphEdit ノードは `InputHandler` を instance 実装すればドラッグ/接続を受け取れる。

**規模の正直化**: 接続線描画・線分ヒットテスト・ポート型検証・SceneLoader serde で相応の規模（ただし v2 が水増しした「入力ルーティング新設」は不要＝既存再利用）。**`[[feedback_engine_godot_only]]` 準拠**で「Godot の GraphEdit/GraphNode に対応する汎用ノードを engine に新設する」方向承認をユーザーから取ってから着手。

**UI 不在でも価値が出る経路**: §3 の headless ハーネス（capture/step/rewind/timeline/dumpAt）と §6 の fe_rogue 応用例は GraphEdit 無しで全て成立（既存 `flix test` golden ＋ `println` ダンプ）。UI は最後段に隔離。

---

## 6. fe_rogue 応用例（seam instantiate・Tier1 の再配置）

> 本節にのみ fe_rogue 固有の `:NNN` を置く。一次は `def 名`、`:NNN` は二次補助。HEAD `ef92583` で再 grep 済み。

fe_rogue は §2 の `SimSpec[World, SimEvent]` を以下で埋める 1 インスタンス:

| seam | fe_rogue 実装（def 名＝一次） | :NNN（二次） | generic seam を埋めるか |
|---|---|---|---|
| (a) applyEvent | `World.applyEventToWorld(ev, world): World` | World.flix | **Yes**（uncurry adapter・§6.1） |
| (b) describe | **未実装**＝新規 human-text projector | （未実装ゆえ無し） | **Yes（このレーンのみ generic seam を埋める）** |
| (c) serialize | `instance Saveable[World]` を `EcsCodec.encodeStore/decodeStore` で構成 | EcsCodec.flix | **Yes**（新規 instance・部品は実在） |
| (d) RNG seam | `World.RngDraw`（`pub eff`）の seeded discharge（§6.4） | World.flix | **Yes**（seeded discharge は新規・§6.4） |
| (e) System（driver 経由） | `resolveAttack`/`resolveEnemyAttack`（`\ RngDraw`）・`resolveStaffCast`（純）を driver で絞る | CombatSystem.flix:181,261 / StaffSystem.flix:32 | **Yes**（driver adapter・§6.1） |
| (L) 健全性法 | `resolveAttack`/`resolveStaffCast` が `(applyAll(events,world), events)` ＝**構造的に満たす** | CombatSystem.flix:226 / StaffSystem.flix:37 | **構造的保証**（§2.1） |

**generic seam に入らない fe_rogue ローカルなレーン（SimSpec の外・主に test に同居）**:

| ローカル射影 | def 名 | 用途 |
|---|---|---|
| view レーン | `ViewReplay.plan(events): List[ViewAction]` | Godot 演出（汎用層は知らない） |
| oracle レーン | `eventToCmds(ev) \|> cmdKey` | legacy 一致照合（test） |

**重要**: seam(b) の generic `describe = ev -> TraceRow` を埋めるのは **human-text projector（新規）1 本のみ**。view（`ViewReplay.plan`）と oracle（`eventToCmds|>cmdKey`）は **fe_rogue ローカルで SimSpec の外**（主に test・Godot 側）。`renderEvent` は src/test 全域 0 件＝実在しない（Tier1 doc の擬似コードのみ）。

### 6.1 Tier1「捕捉→fold→射影」をこのインスタンスとして再記述（v4 で実装形状を裏取り訂正）

**seam (a) の uncurry adapter**: seam 契約は `applyEvent: ev -> w -> w`（curried）だが実体 `applyEventToWorld(ev, world): World` は 2 引数 uncurried:
```
applyEvent = ev -> w -> World.applyEventToWorld(ev, w)
```

**seam (e) の driver adapter（v4 blocking#2＝combatant 構築形状を実コードで訂正）**: 実体 System は追加引数を取る:
- `CombatSystem.resolveAttack(world, attacker: Combatant, defender: Combatant): (World, List[SimEvent]) \ World.RngDraw`（`:181`）
- `CombatSystem.resolveEnemyAttack(world, attacker, defender)`（`:261`）
- `StaffSystem.resolveStaffCast(world, caster, effect, dir, hit): (World, List[SimEvent])` effect-free（`:32`）

**v3 の `pickAttack: World -> (Combatant, Combatant)` 純セレクタは repo に実在しない（grep 0 件）**。実テストの実態（`TestGoldenTrace.flix`）:
- combatant は **Scene fixture から構築**: `sceneOf(player(...), enemy(...)::Nil)`（`:146`）で player/enemy を Scene ノードとして挿し、`driveResolve(sc)`（`:107`）が `World.syncFromScene(sc, World.empty())` で World 化したうえで、**combatant ref を `{ref = EntityRef.Player(0), level = 1}` / `{ref = EntityRef.Enemy(1), level = 1}` とリテラル指定**して `resolveAttack` へ渡す（`:111`）。World からの純 accessor 選択**ではない**。

→ **gap の明記（v4）**: capture が driver を組むには「どの combatant ペアで System を呼ぶか」を決める必要があるが、現状その選択は **Scene fixture 構築＋ref リテラル**で行われており、`World -> (Combatant, Combatant)` の純セレクタは自明に導けない。**SimSpec の seam にどう載せるか**（= combatant ペアリングを Scene 非依存の純 `World -> List[(Combatant,Combatant)]` 相当へ抽出する小タスクが要るか、あるいは driver に combatant を明示渡しするか）は §8 要相談 item に格上げ。当面の 1a 実装では **driveResolve と同様に combatant を明示指定する driver** を組む（Scene 非依存化は後続）:
```
// driver の 1 ステップ（System を部分適用して w->(w,[ev]) 化・combatant は明示）。
let attackStep: World -> (World, List[SimEvent]) \ World.RngDraw =
    w -> CombatSystem.resolveAttack(w, {ref = EntityRef.Player(0), level = 1},
                                       {ref = EntityRef.Enemy(1),  level = 1});
SimHarness.capture(w0, attackStep)   // 単一エンカウンタ＝System 1 呼び出し
```

**「撃破→level-up」は runSeq ではない（v4 improvement で emit 単位を訂正）**: level-up（`expEvents`）は **`resolveAttack` の内部**で二相 fold（`CombatSystem.flix:222-224`: `worldMid = applyAll(coreAll, world); exps = expEvents(worldMid, ...)`）として emit され、`SetWeapons/SetWeaponView/Damaged/Dying/…/LeveledUp` が**単一 System 呼び出しの 1 つの event 列**として返る。よって「撃破→level-up SEQUENCE」は **`attackStep::levelUpStep` の runSeq ではなく `attackStep` 単独**が emit する。`runSeq` の正しい用途は **異なる System の連鎖**＝fixture (D) **CounterChain（`resolveAttack`→`resolveEnemyAttack`）**（`TestGoldenTrace.flix:18` のヘッダ記載）であり、これが `runSeq` の `\ ef` 多相と多 System 連結を実際に行使する:
```
let counterDriver = w -> SimHarness.runSeq(attackStep :: enemyCounterStep :: Nil, w);
```
staff シナリオは `resolveStaffCast` を部分適用（`ef = {}` 純に縮退）した driver で capture。

- step ＝ `SimHarness.worldsAfter(feRogueSpec, trace)`。rewind/`worldAt`/`dumpAt` ＝ 汎用版そのまま。
- 3 レーン射影 = human-text projector〔新規・generic seam〕／view `ViewReplay.plan`〔ローカル〕／oracle `eventToCmds|>cmdKey`〔ローカル・test〕。
- **検証の正しい pin（§1.1 と連動）**: harness 経由 trace の終端 World を `killProj`（`:288`）で legacy 凍結値（`:298,310,322`）と突き合わせる **final-World 等価が一次の確実な検証**。cmdKey SEQUENCE 一致は新規テスト＋成否未確定（§7-1a）。

### 6.2 fe_rogue 固有の住所

汎用ハーネスは `flix_engine_ecs`（`engine_ecs/src/SimHarness.flix`）。fe_rogue 側の instance/driver/projector は既存 `examples/fe_rogue/src/sim/`（`EncounterBuilder`/`BoardSnapshot`/`TurnFlow` と同居・実在確認）に新規 `SimSpecFeRogue.flix` 等で置く。サイドカー採用時のみ `CombatSystem.combatOutcome`（`:101`・非 pub）を露出（§6.3）。

### 6.3 gate: `combatOutcome` の pub 化と公開面の波及（v4 で引数型波及を追記）

`combatOutcome` は `def combatOutcome(world, attacker: Combatant, defView: Combat.CombatView, strike, critRoll): Outcome`（`:101`・**非 pub**）で、返り型 `type alias Outcome = {dmg, newHp, killed, isCrit}`（`:58`・**非 pub**）。サイドカー（算出根拠抽出）採用時の pub 化:

- **① `Outcome` も `pub type alias` 化**: 単純だが alias を公開 API に昇格。
- **② シグネチャにフィールドをインライン展開**（既定）: alias を内部実装に保てるが、**フィールド集合を二重管理**（追加時に両所修正）。
- **③ 引数型の波及（v4 追記）**: `combatOutcome` の引数 `defView` は **`Combat.CombatView`**・`attacker` は `Combatant`。pub 化すると **`Combat.CombatView` / `Combatant` も公開 API 面に引きずられる**（これらの可視性も合わせて要確認）。

→ **②を既定**だが、フィールド増の見込みが強ければ①。CombatView/Combatant の公開波及込みで判断する確定方針（spike ではない）。

### 6.4 gate: capture 用 RNG discharge（既存 production handler は決定論でない＝(A) 不可）

既存 production `World.RngDraw` ハンドラ（`Game.flix`）は
```
def nextPercent(k) = k(Prng.unitToPercent(Math.Random.randomFloat64()))   // live・非決定論
```
で、コメントが **「worldRef の seeded PRNG は進めない（PRNG は test/trace 専用）」** と明示。`Prng.flix` も **「この Prng は test / trace ハーネスだけが行使する」** と裏書き。

→ **選択肢 (A)「既存 production handler 再利用」は破棄**: live `Math.Random` ゆえ **golden 非再現＝capture には不適**（同 seed→同列の前提が崩れる）。

→ **(B)「seeded discharge を src/ へ昇格」一択**。ただし `withSeededRng`（`TestUnitFixtures.flix`）は Region-scoped test fixture なので単純移動ではなく、**「PRNG は test/trace 専用」という engine 側の既存設計不変条件を反転する変更**になる（§8 要相談 item5）。capture を test 外（Godot 埋め込み debug Scene 等）で回すには、`World.RngDraw` の seeded discharge（`Prng.seed`/`nextPercent` 駆動）を `src/`（例 `src/sim/`）へ新規に置き、capture 呼び出しの region 内で適用する。

---

## 7. 段階（MVP → 増分）

**0. ゲーティング spike（着手前）**:
- (i) **任意 stretch のみ**: Flix 0.73.0 で単一パラメータ trait＋associated-value-type が compile するか。**compile しなくても計画は進む**（record-of-functions が DEFAULT）。
- (ii) **複数 closure を束ねた `SimSpec` record の型推論が engine_ecs で初実証**（capability-record は engine 初出・§2.2）。純 closure のみ束ねる（effect 多相は driver で外出し）ので推論問題は軽いと見込むが、初出ゆえ最小 spike で確認。
- (iii) Godot 埋め込みで `getArgs`/stdin 入手可否（`dumpAt` stdout 床は常に有効）。**(B) seeded discharge の src/ 配置可否（§6.4・engine 不変条件反転ゆえ要承認）**。
- (iv) **combatant ペアリングの Scene 非依存化が要るか**（§6.1 gap・SimSpec seam への載せ方）。

**1. 汎用ハーネス先行（headless・UI 無し）— fe_rogue ＋ ダミー World を同時 green 条件に**: `engine_ecs/src/SimHarness.flix` に `SimTrace[w,ev]`・`SimSpec[w,ev]`・`capture`/`runSeq`/`worldsAfter`/`worldAt`/`timeline`/`dumpAt`。
  - **1a（合格条件を v4 で実テスト 2 段に精密化）**: fe_rogue を実証ベンチに §6 の `SimSpec[World,SimEvent]` ＋ driver（combatant 明示）を埋める。**合格条件**:
    - **(一次・確実) final-World 等価**: harness 経由 trace の終端 World が `killProj`（`:288`）で legacy 凍結値（`:298,310,322`）と一致＝既存 pin 流用。
    - **(二次・新規・成否未確定) cmdKey SEQUENCE**: System 経路 event 列を cmdKey 相当へ射影し golden cmdKey 列（`:242-250`）と比較する**新規テスト**を足す。**legacy と draw 順/emit 単位が異なりうるため pass しない可能性があり、その場合は (二次) を諦め (一次) へ後退**（§1.1 不変2）。「golden 列を harness が再現」を無条件の合格条件にはしない（v3 の過大主張を撤回）。
  - **1b（MVP 必須ゲート・法 L を CI 強制）**: 最小ダミー World を engine_ecs 内に置き同ハーネスを通す。**具体化**: `CounterWorld = {n = Int32}`、`ev = Inc | Dec`、`applyEvent` は `n` の加減、driver は `Inc::Inc::Dec::Nil` 相当を runSeq。**合格条件**:
    - fe_rogue を一切 import しない同一 `SimHarness` で `capture/worldsAfter/timeline` を通り凍結値に一致（「ゲーム知識ゼロ」を CI で担保）。
    - **法 L の assert（§2.1 blocking#1）**: `assert fst(driver(w0)) == (worldsAfter(spec, capture(w0,driver)) の終端 World)`＝「events が World 遷移の唯一権威」を parametric 層で機械検証。
  - **1a と 1b の両方** が green で step1 完了（1a 単独で止まれない）。

**2.（任意）追加プロジェクト適合性**: 別 example で 3 つ目の `SimSpec`。汎用性の追加証明（1b で最低限担保済み）。

**3. ノード分類の足場（§4・設計＋純評価器）**: `NodeSpec`/`PortType`/`PortValue` と純グラフ評価器（UI 無し・`flix test` で評価結果を pin）。Sink ノードが `ev` を産み `SimHarness` driver に流せることを headless で確認。opaque-Json 退避の境界（§4.2）をここで確定。

**4.（要相談後）GraphEdit UI**: §5。engine 新規ノード `GraphEdit`/`GraphNode`（接続線描画＋線分ヒットテスト＋ポートスナップ）＋ **既存 `InputHandler`/`Scene.hoveredPathsAt`/`globalPositionAt` 再利用**＋SceneLoader 対応（`:351-371` の dispatch に case 追加）＋debug Scene。**方向承認とスコープ合意を取ってから**着手。

---

## 8. リスク・スコープ・engine 要相談・決定論/直列化

**engine 要相談リスト（新規＝要事前承認）**:
1. **`flix_engine_ecs` への `SimHarness` モジュール追加**（純粋・憲章一致だが engine lib 改変ゆえ承認要・複数 closure record は engine_ecs 初出＝§2.2）。
2. **engine への `GraphEdit`/`GraphNode` 新規 scene ノード＋SceneLoader 対応**（§5・最大の新規）。要件＝接続線描画・**線分ヒットテスト**（既存 AABB hit-test `Scene.flix:544,558` では不足）・ポートスナップ・グラフ serde（`SceneLoader.flix:351-371` に case 同型追加）。**入力ルーティングは新設不要**（既存 `InputHandler`＋`Scene.hoveredPathsAt`/`globalPositionAt` 再利用）。**これは「ゲーム実行時ノード」ではなく「オーサリング/ツール用ノード」**である点を明記する。**`[[feedback_consult_not_avoid]]` に照らし、examples/fe_rogue 内に GraphEdit 相当を private 再実装する逃げは取らず、engine 追加前提で相談する**（承認スコープが将来 example 内実装へ滑らないよう宣言）。
3. **`PortType`/`PortValue` 汎用 tagged union の engine 配置**（§4.2・ゲーム固有型を入れない原則と opaque-Json 退避境界・型安全縮退の許容ライン合意）。
4. **fe_rogue: capture 用 seeded RNG discharge を src/ へ新設（§6.4(B)）**。**engine 既存の設計不変条件「PRNG は test/trace 専用」の反転**ゆえ独立承認要。既存 production handler（live `Math.Random`）は非決定論で capture 流用不可。
5. **combatant ペアリングの Scene 非依存化（§6.1 gap）**: 現状 combatant は Scene fixture 構築＋ref リテラルで選ばれる（`pickAttack` 純セレクタは不在）。SimSpec seam にどう載せるか合意。

**v2 から撤回した架空リスク**: 「node-graph 入力ルーティング seam の engine 新設」は **`InputHandler` trait（`InputEvent.flix:22`）と `Scene.hoveredPathsAt`/`globalPositionAt` が実在するため不要**＝撤回。

**既存で足りるもの（新規不要・裏取り済み）**: capture/step/rewind/timeline の全ロジック型（`Query`/`EcsCodec` と同型）、serde（`EcsCodec.encodeStore/decodeStore`＋`Saveable`）、純 PRNG（`Prng.flix`）、**入力ルーティング＆ヒットテスト（`InputHandler`＋`Scene.hoveredPathsAt`/`globalPositionAt`）**、SceneLoader 文字列 dispatch（`:351-371`）、stdout（println 床）。

**Godot-only 制約と SimHarness 配置の境界**: `[[feedback_engine_godot_only]]` は **engine/（`flix_game_engine`・Godot 鏡像層）に効く**。一方 **`engine_ecs/` は project 自前の汎用 lib（`github:ababup1192/flix_engine_ecs`）で Godot API 面ではなく**、憲章「Reusable immutable-ECS modules」（`engine_ecs/flix.toml:3`）が効く。SimHarness（capture/rewind/timeline trace デバッガ）は Godot に対応物が無いが engine_ecs の汎用 lib 憲章で正当化され Godot-only 制約の射程外。GraphEdit/GraphNode のみ Godot 対応物（オーサリングノード）として engine/ に乗り `[[feedback_engine_godot_only]]` の承認対象。

**スコープ外（やらない・正直に）**:
- **Tier2 で新ロジックを visual 定義**は §4 の語彙確定までで、評価器以上は UI 相談後。
- **算出根拠の汎用抽出**: seam (b) describe は「emit 済み Event の射影」しかできず、Event payload に出所が無い中間値（fe_rogue の命中ロール/ring-finisher 寄与）は**どのプロジェクトでも describe だけでは出ない**（§2.4 の post-roll 不変から seam 由来で必然）。各プロジェクトが System 内部へ pub 到達（fe_rogue は `combatOutcome` pub 化＝§6.3・CombatView 波及込み）するか縮退合意するか。
- **continuation 再 sim**（rewind 地点から続行）＝終端 RNG state carry 未保存。汎用契約でもスコープ外。
- **live セッション録画**: capture は fixture-seed 再走。live は `SimTrace#initial` を live snapshot に差し替える将来増分。

**決定論/直列化の扱い**: step/rewind は純 fold＝RNG 非依存（seam (a) 純＋total 契約で保証）。in-memory rewind は World plain-data で常に成立（fe_rogue World は Scene 非保持）。on-disk は seam (c) 任せ。capture のみ seeded discharge（§6.4(B)）が要る。

**「演出の完全 rewind」の正直な線**: World は完全に巻き戻る（純 fold）が、**演出（anim/音/scene 副作用）の完全 rewind は、各プロジェクトの render が World 派生（`syncTreeFromWorld` 一本化相当）になって初めて成立**。それまでは演出は再導出 or 非再発火。汎用層では強制できずプロジェクト責任。

---

### Critical Files for Implementation
- /Users/abab/Desktop/flix_game_engine/engine_ecs/src/EcsCodec.flix （closure-as-param＋serde の既存イディオム・SimHarness の隣人／serde seam 部品。capability-record は engine_ecs 初出＝§2.2）
- /Users/abab/Desktop/flix_game_engine/engine_ecs/src/Query.flix （World-parametric 純コンビネータの前例＝SimHarness 設計テンプレ・配置根拠）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/test/ecs/TestGoldenTrace.flix （**検証基盤の核**: golden=legacy cmdKey 射影列〔runAttack:163 / golden:242-250〕／System 経路=killProj final-World のみ〔driveResolve:107・testResolveCombatEqualsLegacy*:298,310〕／combatant は sceneOf:146 で Scene fixture 構築＋ref リテラル:111＝§1.1・§6.1・§7-1a の一次根拠）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/ecs/systems/CombatSystem.flix （`resolveAttack:181`〔seam e〕・`(applyAll(events,world), events):226`〔法 L 構造的保証〕・二相 fold で level-up が内部 emit:222-224〔runSeq ではない〕・`combatOutcome:101`〔非 pub・defView:Combat.CombatView〕・`Outcome:58`〔非 pub・§6.3〕）
- /Users/abab/Desktop/flix_game_engine/engine/src/scene/Scene.flix （`hoveredPathsAt` def:544・AABB 包含判定:558＝§5 で「線分ヒットテストが真に新規」の一次根拠／`globalPositionAt:476`／`getGlobalRect:529`）

補助（全て絶対パス・HEAD ef92583 実在確認済み）:
- /Users/abab/Desktop/flix_game_engine/engine/src/scene/InputEvent.flix （`trait InputHandler[s]:22`・`type Aef:25`・`onMouseButtonPressed:38`/`onMouseMotion:52`/`onMouseHover:72`・`handleInput:101`・`hoveredPathsAt 使用:140`＝§5 入力ルーティングは新設不要の決定的根拠）
- /Users/abab/Desktop/flix_game_engine/engine/src/SceneLoader.flix （`case "Sprite2D"=>buildSprite2D…:351-371`＝文字列キー dispatch・`GraphEdit` case を同型追加可＝§5/§8 scene-json-first 裏取り）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/ecs/systems/StaffSystem.flix （`resolveStaffCast:32`effect-free＝`\ ef` 多相が純へ縮退する証人・`(applyAll(events,world), events):37`＝法 L 構造的保証）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/ecs/World.flix （`applyEventToWorld`〔seam a 純・CLOSED enum 網羅で total〕・`eventToCmds`/`cmdKey`〔oracle ローカル〕・`pub eff RngDraw`〔seam d〕）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/game/Game.flix （`with handler World.RngDraw`・`nextPercent` live `Math.Random`・コメント「PRNG は test/trace 専用」＝§6.4 で (A) 破棄・(B) 要承認の engine-honesty 裏取り）
- /Users/abab/Desktop/flix_game_engine/engine/src/scene/Node.flix （`trait Node[s]:15` の 6 メソッド・input 非在は事実だが入力は InputHandler が担当）
- /Users/abab/Desktop/flix_game_engine/engine/src/Persistence.flix （`trait Saveable[a]`＝serde seam (c) の単一パラメータ trait 表現）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/scenes/ViewReplay.flix （`plan`＝view レーン射影・SimSpec 外のローカル）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/ecs/Prng.flix （`seed`/`nextPercent`/コメント「test / trace 専用」＝決定論 PRNG・seam d）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/test/scenes/TestUnitFixtures.flix （`withSeededRng`＝Region-scoped test fixture・§6.4(B) で src/ へ昇格要）
- /Users/abab/Desktop/flix_game_engine/engine_ecs/flix.toml （name=flix_engine_ecs:2 / desc「…Collision broadphase…」:3＝SimHarness 配置の一次根拠・Godot-only 射程外の根拠。v4 で実引用に訂正）
- /Users/abab/Desktop/flix_game_engine/VISUAL_SCRIPTING_TIER1.md （root commit 済み・型変数化の出発点）

**grep 実績（HEAD ef92583）**: `GraphEdit`/`GraphNode`/`VisualScript`/`NodeGraph` は engine/src・engine_ecs/src・examples/fe_rogue/src で 0 件＝§5 新規。`pickAttack`/`renderEvent` も 0 件。多パラメータ trait・associated-value-type trait・capability-record（≥2 関数フィールド type alias）は engine/engine_ecs に 0 件。**v3 からの主要訂正**: ①法 L を seam に追加し CounterWorld で CI 強制（generic-soundness linchpin・blocking#1）／②§4.1 universal の射程をスカラ層に正直化（blocking#2）／③golden=legacy cmdKey 射影 vs System=final-World-only を切り分け、harness は System 経路ゆえ golden 列再現を無条件合格条件にしない（completeness blocking#1）／④`pickAttack` 不在・combatant は Scene fixture 構築＝§6.1 gap 明記＋§8 要相談化（completeness blocking#2）／⑤level-up は resolveAttack 内部 emit＝runSeq は CounterChain 用と訂正／⑥capture は薄い adapter と正直化・TraceRow を opaque 確定・seam(a) total 契約・seam(d) post-roll 不変を追加／⑦engine_ecs desc 実引用訂正・capability-record は engine 初出と正直化・hoveredPathsAt def:544＋AABB:558 一次 pin・SceneLoader dispatch:351-371 裏取り・combatOutcome の CombatView 公開波及追記。