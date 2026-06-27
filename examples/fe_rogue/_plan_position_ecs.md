# 位置(Board/Encounter)を World 権威化する移行計画（feasibility-first / **v3** = 2巡レビュー反映）

## 目的とゴール
Board の読みを全て World 由来にし、World を「位置の**論理的**権威」にする（§A 高旨味: Board/Encounter/EnemyAI/セーブ）。
scene-tree は gridPos を**描画位置**として保持し続ける（render view・dual-write 恒久）。最終的に save/determinism が World から成立する素地を作る。

## 最優先＝実現可能性
各ステップが (a) `flix test`（full build）緑 (b) **挙動差を handler の mid-frame board assert で機械検出** (c) 伝播が有限・compiler 誘導・**計測 envelope 内** (d) 罠（pure reader伝播 / mid-frame staleness）を構造的に回避。

---

## 中核の検証器: handler 1 箇所の mid-frame board assert（v3 で確定）
- **設置場所は `Game.flix:876` の `BoardQuery.board` handler ただ1箇所**。理由: `worldRef` と `sceneRef` が同時に可視なのはここだけ（scene 層の呼出点は worldRef を持てない）。board() を flip した消費者は全員ここを通るので**per-call-site 改修ゼロで全4経路を自動網羅**。
- 実装: handler 内で `World.toBoard(Ref.get(worldRef), Ref.get(sceneRef))` と `BoardSnapshot.fromScene(Ref.get(sceneRef))` を突合。
- **比較は順序非依存のタプル集合**: `Board` は型エイリアス record で **Eq derive 不可**（`Board.flix` 明記）。さらに pieces 順が違う（World=`Map.toList` id 昇順、fromScene=preorder）。よって両者を `(tag, id, x, y)` のリストへ写し `List.sort` して比較（または Set 化）。差分のみ debug log。
- 役割: P0 以降「World 由来盤面 == scene 由来盤面」を**毎フレーム・全 board() 経路で実証**。gather の prev→now 是正だけは P0 で意図的に差が出る（run 確認）。以降の flip/mirror 撤去はこの assert が差ゼロを継続することが**挙動不変の機械的証明**。
- **ゲート判定は「即時差ゼロ」でなく「差は次フレーム頭までに解消（transient OK）」**。`Cmd.Move` は pos のみ即時化するため、以下は**正当な transient**（次フレーム頭の `syncFromScene` mirror で解消・log-only ゆえ build は赤くならない）として carve-out し、中止条件にカウントしない:
  - **hidden 遷移**（gather/階段退場で ally が mid-frame に hidden 化）: scene は即除外、World の `playerHidden` は mirror 遅延 → 当該 ally を1フレームだけ含む差。※ hidden も mid-frame 化したいなら `Cmd.SetHidden` を足す（P0 範囲外・任意）。
  - **P0b 着手前の spawn フレーム**: scene 先行・World mirror 遅延。P0b 完了で解消。
- 「想定外の差」＝**次フレーム頭でも解消しない差**のみを中止条件とする。

## 写し漏れ検出（補助・別 assert）
各 `Cmd.Move` 経路で「emit した pos == scene に書いた pos」を `Ref.get(worldRef)` と end-state 比較（写し忘れ検出。挙動不変の証明ではない）。

---

## 検証済み前提（grep + スパイク実測）
- **write 完全性（レビュー裏取り済 TRUE）**: ユニット位置 write は移動5関数（`PlayerScene.{moveTo:380, moveToById:401, snapTo:422}`, `EnemyScene.{moveTo:500, snapTo:525}`）＋ spawn3（`PlayerScene:212`, `EnemyScene:185/316`）＋ restore2（`PlayerScene:1115`, `EnemyScene:611`）。他は World 対象外。
- **P0a 伝播スパイク実測**: 移動5関数の emit → ~20関数・**構造的壁ゼロ**（FrameAef.T/checked_ecast/E2518/E6217 出ず）。新種は `applyBlowbackMove` の高階 `moveFn` param のみ。
- **spawn/restore は別系統の木**（GameLifecycle: `buildPlayingScene`/`rebuildFloorFromSnapshot`/`maybeSpawnWanderer`/`advanceFloor`/`restartFromFloorSnapshot`）で現状 `World.Command` row を持たない → **P0a と別に伝播計測してから着手**（P0b）。
- **テスト絶縁の確認**: `gatherStep`/`followAllies` を呼ぶ自動テストは無く、test の `BoardQuery` stub（`TestUnitFixtures.withMockBoard`）は worldRef 非依存の固定 board。**ゆえに P0 はどのテストも赤にしない（緑は堅い）が、gather 是正の唯一のゲートが手動 run になる**→ tripwire test を足す（P0a-4）。

---

## フェーズ（各々 緑・handler assert で検証・**確認の上**コミット）

### P0a: 移動 write-seam＋mid-frame currency（move 次元）＋検証器
1. `World.Cmd.Move(EntityRef, {x,y})`＋`applyCmd`。
2. 移動5関数から `Cmd.Move` emit（dual-write 維持）。伝播 ~20（実測）を compiler 誘導で付与・test fixture wrap。
3. **handler mid-frame board assert を実装**（上記・`Game.flix:876`・タプル集合比較）。
4. **gather tripwire 単体テスト**を追加: worldRef-backed な BoardQuery stub を lord@prev / lord@now で seed し、`followAllies` が選ぶ ally target を assert（prev→now 是正に赤/緑を付け、手動 run 依存を冗長化）。
- **完了ゲート**: full build 緑 ＋ handler assert が gather 以外で差ゼロ ＋ tripwire 緑 ＋ **実機 run 目視**（集合追従・敵移動・杖いれかえ/ワープ・階段集合退場）。
- ⚠ gather は prev→now に**意図的に変わる**（flip① の staleness 是正）。run で正挙動を確認。flip① の prev 観測に依存する意図があれば着手前に要相談。

### P0b: spawn/restore write-seam（lifecycle 木・別計測）
- spawn3/restore2 から `Cmd.Move`(=Seed) emit。**着手前に GameLifecycle 木の `World.Command` 伝播本数をスパイク計測**（move5 と別 envelope）。
- mirror が P2 まで生きるので staleness の実害は P3 直前まで出ないが、**P1b（mid-frame の新規ユニット読み）の前提**なので P1b より前に置く。
- dual-write 継続＝挙動不変。完了ゲート: 緑＋handler assert 差ゼロ。

### P1a: frame-head reader flip（挙動不変・run 不要）
move 前に board を読む frame-head 経路を `BoardSnapshot.fromScene` → `BoardQuery.board()`。
- 対象: StairsExit(begin/advanceFront), StaffCast **player** warp/blowback。
- pure reader（canExit/buildFor/reachability）は**対象外**（scene gridPos 据え置き）。各 flip 後 handler assert 差ゼロ。1群ごと緑→確認→コミット。

### P1b: mid-frame reader flip（P0a+P0b の currency 前提・要 run）
- 対象: EnemyTurnDriver applyNormalStep, Combat knockback, StaffCast **enemy** cast。
- これらは `EncounterBuilder.fromScene` 直読み点もあり board() を通らない → **flip して初めて handler/該当 assert で currency を自己検証**（P0 が事前証明はしない）。
- 各 flip 後 assert 差ゼロ＋敵ターン実機 run。1群ごと緑→確認→コミット。

### P2: Encounter を World へ（EnemyAI 入力＝旨味の核）
- `EncounterBuilder.fromScene` の **effectful** 消費者（EnemyAI 駆動）を World 由来に。assert＋run。pure 利用は据え置き。

### P3: mirror 撤去（§A payoff・要 run）
- `syncFromScene` の pos mirror 停止（World.pos は command のみ由来）。scene gridPos は描画位置として dual-write 継続。spawn/restore は P0b で emit 済み。
- handler assert が**全経路 差ゼロを継続実証**していれば、撤去は写し漏れ無き限り挙動不変。実機 run（床移動/集合/敵移動/杖/中断再開）で最終確認。

---

## リスクと対策（v3）
| リスク | 対策 |
|---|---|
| **mid-frame 観測差**（flip②頓挫の本質）| **handler 1 箇所の board assert**（タプル集合比較）で全 board() 経路を機械検出 |
| Board が Eq 不可・順序差 | `(tag,id,x,y)` へ写し sort/Set 比較 |
| write 完全性 | grep 裏取り済＋写し漏れ assert |
| spawn staleness | P0b で別計測の上 seam（P1b 前）。mirror 生存中は実害遅延 |
| lifecycle 木の未計測伝播 | P0b 着手前にスパイク計測（move5 envelope と分離）|
| pure/effectful reader の mid-frame 不整合 | pure は scene 据え置き＋effectful は P0 後 World==scene（pos 次元）。hidden 次元は 1 フレーム transient（carve-out 済）|
| pure reader 伝播爆発（statusEffects頓挫）| pure reader を flip しない |
| gather 是正がCIで無検出 | tripwire 単体テスト（P0a-4）|

## 中止条件
handler assert が**次フレーム頭でも解消しない差**を出す（transient carve-out 後）／伝播が計測 envelope を大きく超える／pure 経路へ侵入したら手前で停止して再計画（既コミット分は緑・assert 緑のまま無害＝安全に中断可）。

## 各フェーズ「完了の定義」
- **P0a**: full build 緑＋handler assert gather 以外差ゼロ＋tripwire 緑＋targeted run 合格。
- **P0b**: 緑＋assert 差ゼロ（伝播本数を事前計測）。
- **P1a**: 緑＋assert 差ゼロ（run 不要）。
- **P1b/P2**: 緑＋assert 差ゼロ＋該当 run。
- **P3**: 緑＋assert 全経路差ゼロ継続＋実機 run チェックリスト合格。

## 付録: flip① の扱い
flip①（committed・未 run 検証）は gather で主人公位置を `prev`(古) に見せている可能性。P0a が `now`(正) に是正。P0a の run でこの是正が正挙動と確認する（依存意図があれば要相談）。
