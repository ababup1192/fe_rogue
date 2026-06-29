# resolveCombat シミュレーション化計画（壁打ち 82・承認済み）

`CombatScene` の戦闘解決ロジックを、World 権威の純粋 sim（`CombatSystem.resolve*`）へ段階移送する計画。
レガシー `CombatScene` はバイト単位で無改変のまま、新しい純粋 read-model アクセサと sim パスのみを追加し、
各スライスをレガシー oracle に対して final-World 等価でピン留めする。

---

## シーケンシング（実施順）

厳密な線形順序で進める。

```
P1a -> P1b -> P1d -> P1c -> P2 -> P2b -> P3
```

- **P1d** は依存フリー（既存の `_thiefRoll`（CombatSystem:90）だけを必要とする）。baseline 以降ならどこにでも差し込めるが、ここでは語りの都合上この位置にグループ化する。
- **P1a** は `equippedRing` という `Option` read-model を追加する（World.flix:76/163/756 の **既存 weaponView パターン** `Map[EntityId,Option[_]]` + `Option.flatten` を踏襲。`ringBonus` の「全ユニットに indexBy する」形ではない）+ finisher の kill-flip。
- **P1b** はその read-model を ring-lifesteal に再利用し、かつ `resolveAttack` を **二相 fold**（coreEvents -> worldMid -> expEvents(worldMid)）に再構成する（expEvents は今日オリジナルの `world` を読む（CombatSystem:95/103）ため、post-lifesteal hp を level-up に流し込むには再構成が真に必要）。weapon の読みは `combatViewOf#weapon : Option[WeaponView]` から取る。
- **P1c** はプレイヤースライスの中で唯一 `mapSnapshot` read-model + `boardOf(world)` + 新規 `posOf` アクセサを必要とするため、最後に隔離して置く。
- **P2** は `resolveEnemyAttack`（別個の draw 構造）を構築し、**ノックバックフリー** なので P1c/`boardOf` に依存しない。`StatusAt`/`ImmobilizeAt`->`Afflicted` と deferred-player-death（`ViewFx(Died)`）を出荷する。
- **P2b** は敵の `HealAt`/`FullHealAt`->`Healed(self)` を追加する。
- **P3** は `resolveAttack` THEN `resolveEnemyAttack` を 1 つの seed thunk の下で合成し、counter シナリオを値非依存性でピン留めする。
- **P2** は P1a（敵の finisher/ring-lifesteal 用の `equippedRingOf`）と P1b（二相 fold + lifesteal ヘルパー）の **両方** に依存する。

各スライスの後に毎回以下を走らせる。決してコミットしない。

```
export GITHUB_TOKEN="$(gh auth token)" && ../../bin/flix test   # baseline 970 green
../../bin/flix check
```

---

## Definition of Done（DoD）

**全スライス共通**: `../../bin/flix test` が green を維持（baseline 970 + 各スライスの新 golden）。`../../bin/flix check` がクリーン。

追加された全 sim パスは、確立されたパターンの下でレガシー oracle に対し final-World 等価でピン留めする。

```
シーン構築 -> legacyW = runAttack/runEnemyAttack(sc)
          -> w0 = World.syncFromScene(sc, World.empty())
          -> CombatSystem.resolve* を withSeededRng(rc, seed()) の下で駆動
          -> sysW と legacyW の World 射影（hpOf/progressOf/alertedOf/statusEffectsOf/posOf）を assertEq
```

ガード:
- 両戦闘者に対する `combatViewOf`-Some の事前ガード + `evCount>0`。
- legacyW にピン留めする（独立 oracle。決して self-derive しない。golden oracle で裏取りした具体的リテラルをピン留めし、同じ純粋関数で再計算しない）。

### スコープの明示的縮小

等価主張は以下に限定する。
- プレイヤー単発攻撃パス（finisher / lifesteal / knockback / thief）
- 敵単発攻撃パス（**ノックバックなし**）
- それらの合成（counter）

**敵ノックバックは明示的な DoD 除外項**。`applyEnemyKnockback`->`pushPlayerBack`->`PlayerScene.snapTo` が `Cmd.Move(player)` を emit する（CombatScene:765）。`boardOf`/`posOf` は P1c で出荷されるものの、P2 は敵の draw 構造を最小に保つためノックバックフリーを維持する。ガード (d) が「P2/P3 の敵 weapon は Knockback effect を持たない」ことを assert し、敵ノックバックパスが unpinned のまま静かに出荷されないようにする。敵ノックバックは将来の named スライス（dependsOn P1c、既に充足可能）。

### 不変条件

**新しい `SimEvent`/`ViewFxKind` 変種は作らない**。CLOSED な集合（World.flix:383-409）+ `applyEventToWorld`/`eventToCmds`/`eventEntity`/`cmdKey`（573-679）はバイト単位で無改変。新しい純粋 read-model アクセサのみを追加する。

### 検証済みペイロード形状（load-bearing・訂正済み）

1. `SimEvent.Lifesteal` と `SimEvent.Healed` は **両方とも** `(EntityRef, {newHp=Int32, amt=Int32})`（World.flix:387-388）。reducer が `amt` を無視しても、全 emit リテラルは `amt` を **必ず** 供給する（`{newHp=...}` 単独リテラルは typecheck FAIL）。
   - Ring-lifesteal: `Lifesteal(ref, {newHp=Combat.heal(curHp,maxHp,amt)#newHp, amt=amt})`
   - Weapon-lifesteal: `Lifesteal(ref, {newHp=Combat.heal(curHp,maxHp,h)#newHp, amt=h})`（h=(dmg*pct)/100）
   - Healed: `Healed(self, {newHp=hv, amt=hv-curHp})`（amt 値は cosmetic）
2. `Combat.heal` は **positional** `heal(currentHp,maxHp,amount):{newHp=Int32}`（Combat.flix:133）。レガシー同様 positional に呼ぶ（record-arg スタイルを上書き）。
3. weapon effect は `combatViewOf(x)#weapon : Option[WeaponView]`（Combat.flix:176-179）から読む（effect/effectValue を運ぶ）。Some(wv)/None、None => lifesteal/knockback/thief event を emit しない。新しい weapon read-model は作らない。
4. `combatViewOf(x)#maxHp == x#resource#hp` は **検証済み不変条件**。heal-cap と predCtx の selfHpPct/targetHpPct/amount#max は `combatViewOf#maxHp` を読んでよい。runtime assert 不要。

### 新 read-model（全て既存 weaponView Option-store パターンを踏襲。`ringBonus` の indexBy-all ではない）

- **`equippedRing : Map[EntityId, Option[Ring.RingResource]]`**（P1a）
  - `empty()` = `Map.empty()`
  - `syncFromScene`/`refreshMirror` = `Map.union(Query.indexBy(d -> d#id, d -> PlayerData.equippedRing(d), players), Query.indexBy(d -> enemyUid(d#id), d -> d#ring, enemies))`。Option を直接 store（`PlayerData.equippedRing` は ringEquipped ゲートを既に内包し Option を返す。敵 `d#ring` は Option）。
  - `pub def equippedRingOf(ref,world): Option[Ring.RingResource]` = `let World.World(w)=world; Map.get(toUid(ref), w#equippedRing) |> Option.flatten`（weaponViewOf at 756-757 を踏襲）+ `equippedRingMismatches` parity verifier。

- **`mapSnapshot : Option[MapSnapshot]`**（P1c。`MapSnapshot` は record/set のプレーンな type-alias（lib/MapSnapshot.flix:9）で storable）
  - `empty()` = `None`
  - `syncFromScene`/`refreshMirror` = `Some(BoardSnapshot.mapSnapshotOf(scene))`（`toBoard` が使うのと同じソース、World.flix:961）
  - `pub def boardOf(world): Option[Board]` = `let World.World(w)=world; Option.map(m -> {map=m, pieces=World.boardPieces(world)}, w#mapSnapshot)`。既存の pure-World `boardPieces(world)`（World.flix:983）を **逐語的に再利用**。`toBoard` は **リファクタしない**（既存 golden `testGoldenFinalBoardParity` に消費されている）。+ `mapSnapshotMismatches` parity verifier。

- **`effectRule : Map[EntityId, Util.Json.Json]`**（P2・敵のみ）
  - `empty()` = `Map.empty()`
  - mirror は enemy `#resource#effectRule`（Option[Json] — enemies 上で `Query.indexBy`、Option を store、accessor が flatten、同じ Option-store パターン）から。
  - `pub def effectRuleOf(ref,world): Option[Json]`（Option.flatten）+ `effectRuleMismatches`。

- **新規 `pub def posOf(ref,world): Option[{x=Int32,y=Int32}]`** = `let World.World(w)=world; Map.get(toUid(ref), w#pos)`（既存 w#pos store 上の純粋。今日存在しない。`prevPosOf` のみ存在）。P1c で **最初に** 追加（P1c/P3 の pos assert にとって DoD-blocking）。

- **新規 pure leaf `hpPct(cur,max)`**（CombatScene.hpPct を踏襲、P2）。

3 つの新 record FIELD（`equippedRing`, `mapSnapshot`, `effectRule`）は **3 つの full-record builder すべて** に配線する。
- `empty()`（~96-111。scene なしの唯一の builder。Option 型フィールドは None/Map.empty にデフォルト）
- `syncFromScene`（~155-168）
- `refreshMirror`（~210-228）

これらが唯一の `World.World({...})` full-record サイト（他は全て `{...|w}`）。フィールド欠落 = コンパイル break。

### 敵パス固有事項

- 敵 hp の Damaged は **RAW** `outcome#newHp`（hard-0 clamp なし。player death は deferred）。
- Player death は `ViewFx(Died(player))` **のみ** でモデル化（`Dying` ではない）。レガシーは player に `SetDying` を emit しない（`SetDying(player)` は World no-op、World.flix:519。`Dying` は phantom cmd になる）。
- `Released` は **無条件** emit（kill AND non-kill、CombatScene:759）。
- player に `Alerted` なし。敵に `expEvents` なし。
- effectRule ctx の amount は **CLOSED な 4-field record** `{max=combatViewOf(defender)#maxHp, dealt=dmg, incoming=0, magic=0}`（2-field リテラルは typecheck FAIL）。
- predCtx は CombatScene:797-801 を `hpPct` leaf で踏襲。
- effectRoll は rule が存在し trigger が発火するときだけ **条件付き** で draw。
- `emitStatusAdds(status)` を `emitHpSets(heal)` の **前** に map -> Afflicted events が Healed events に先行。

### プレイヤーパス不変条件（load-bearing）

`TestCombatSystem.flix:82` は no-ring/no-lifesteal/no-knockback の **KILL パス** で `List.length(events)==3` をピン留めする（Damaged::Dying::ExpGained）。P1b の二相 fold と P1c の knockback append は、このパスで **正確に 3 events** を維持しなければならない（空の lifesteal/knockback list は何も寄与しない。bare kill path に phantom ViewFx を append しない）。coreEvents の bare enemy-death 分岐は `Damaged{newHp=0,dmg=...}`（証明済みの hard-0 clamp）を維持しなければならない。汎用的な `Damaged(enemy,{newHp,dmg})` 表現が clamp を落としてはならない。

### final-World 等価から明示的に除外（関連スライスごとに 1 行）

- weapon durability consume（プレイヤー+敵、scene-only）
- thief floor-item drop（scene-only）
- orchestration 制御 Cmd（AtkTgt/ClrTgt）
- 敵 effectRule の hp-ops `DamageAt`/`MaxHpUpAt`/`ReviveAt`（注: これらの敵ハンドラは no-op `-> sc` で、emitHpSets が runPlan 後の unchanged hp を re-emit = 正味 World no-op。よって発火しても除外は等価-SAFE。ガード (d) は belt-and-suspenders であって load-bearing ではない）
- 敵 KNOCKBACK（P2 ノックバックフリー、ガード (d) がロック）
- 敵 lifesteal+heal STACKING（lifesteal weapon/ring AND heal effectRule の両方を持つ敵の fixture は出荷しない -> runPlan 後の stacking パスは UNPINNED のまま出荷するが明示的に de-scope）

EMITTED な effectRule sim 分岐はすべて golden でピン留めする（StatusAt=P2(a)、ImmobilizeAt=P2(b)、HealAt/FullHealAt=P2b）。unpinned な EMITTED 分岐はマージしない。

### その他

- ブランチは ecs-extension のまま。ユーザがコミットする。
- ViewReplay 配線なし。cutover なし（レガシー CombatScene はバイト無改変）。

---

## スライス

### P1a-finisher — resolveAttack でのプレイヤー finisher（Ring Finisher）kill-flip

**approach**:
World read-model `equippedRing : Map[EntityId, Option[Ring.RingResource]]` を **既存 weaponView Option-store パターン**（World.flix:76/163/224/756。`ringBonus` の indexBy-all 形ではない。後者は全ユニットに値を store する）を踏襲して追加する。`syncFromScene`/`refreshMirror` で `Map.union(Query.indexBy(d -> d#id, d -> PlayerData.equippedRing(d), players), Query.indexBy(d -> enemyUid(d#id), d -> d#ring, enemies))` として構築（両ソースとも既に `Option[Ring.RingResource]` を返す。`PlayerData.equippedRing` は内部に ringEquipped ゲートを持つ。敵 `d#ring` は Option で EnemyScene.flix:752 で使われる）。`empty()` = `Map.empty()`。`pub def equippedRingOf(ref,world): Option[Ring.RingResource]` = `Map.get(toUid(ref), w#equippedRing) |> Option.flatten`（weaponViewOf at 756-757 の逐語的踏襲）+ `equippedRingMismatches` parity verifier（combatViewMismatches を踏襲）を追加。

`CombatSystem.resolveAttack` の hit 分岐で、既存の isCrit 分岐（83-87）の **前** に `finisherFired = Ring.finisherTriggers(defView#hp, defView#maxHp, Ring.finisherThreshold(World.equippedRingOf(attacker#ref, world)))` を計算（PURE・draw なし。Ring fns は `Option[RingResource]` を直接取る）。outcome 優先順位はレガシー CombatScene:520-531 の finisher > crit > base を踏襲。
- finisherFired -> `Combat.applyFinisher(strike#dmg, defView#hp)`（sure-kill）
- else if `isCrit(strike#crit,critRoll)` -> `applyCrit(strike#dmg, defView#hp)`
- else base

critRoll は 76 で依然 draw（draw 2 不変）なので seed order は同一。expEvents は最終 killed flag から battleExp を再計算するので、crit/finisher-kill の exp 再計算は自動再現。defView#maxHp は combatViewOf から。証明済みの kill/non-kill/crit draw・fold order には触れない。

1 行: weapon durability は scene-only、除外。

**newSimEvents**: なし — finisher は Damaged+Dying+ExpGained/LeveledUp を再利用。新 read-model `equippedRing`（Option-store）+ `equippedRingOf` アクセサ（Option.flatten）+ `equippedRingMismatches` parity verifier のみ。

**files**:
- `src/ecs/World.flix`
- `src/ecs/systems/CombatSystem.flix`
- `test/ecs/TestGoldenTrace.flix`

**goldenTest**:
TestGoldenTrace に新規 `testResolveCombatEqualsLegacyFinisher`。ペアの no-ring control 付き（anti-vacuity）。NON-VACUOUS fixture: 敵を `{defense=8, effectRule=None | testEnemyResource(...)}` hp=4/maxHp10（40% <= 50% finisher 閾値）、プレイヤー atk は base strike#dmg が 0 に clamp/killed=false になるよう（base では kill 不可）、プレイヤー weapon crit=0 で stray crit が finisher を mask しないよう設定。
- (A) WITH Ring{effect=Finisher,power=50}（PlayerData.equippedRing 経由でミラー）: `runAttack(sc)->legacyW` vs `withSeededRng(seed())` 下の resolveAttack。assertEq（hpOf(Enemy1)=Some(0)、progressOf(Player0)=KILL-exp）sysW==legacyW、legacyW にピン留め。
- (B) CONTROL 同シーンで ring=None: legacyW と sysW の **両方** で hpOf(Enemy1)=Some(4)（敵 SURVIVES）を assertEq。kill が finisher 駆動であり付随的な base/crit kill でないことを証明。

両方とも viewSome-both + evCount>0 ガード付き。

**risks**:
1. Fixture vacuity — ペアの no-ring control（敵 hp Some(4) survives）は anti-vacuity DoD により MANDATORY。これなしでは kill-flip が ring 起因と証明できない。
2. 敵 defense を上げて base dmg=0 にする（実効プレイヤー atk = atk + weapon attack。選んだプレイヤー atk に対し defense=8 で 0 になることを検証済み）。
3. equippedRing は Option を store し accessor が flatten（weaponView 踏襲）。`ringBonus` の indexBy-all を使わない（全ユニットに insert -> finisher が spurious に発火）。
4. Finisher 分岐は crit に **先行** しなければならない。
5. World フィールド追加は 3 builder すべてに触れる（empty=Map.empty は additive）。builder 漏れ = コンパイル break。

**dependsOn**: なし

---

### P1b-lifesteal — プレイヤー ring-lifesteal（on kill）+ weapon-lifesteal（per-hit）-> プレイヤー hp。二相 fold

**approach**:
`resolveAttack` の hit 分岐を **二相 fold** に再構成する。

```
coreEvents = (killed ? Damaged(enemy,{newHp=0,dmg=...})::Dying(enemy)::Nil
                     : Damaged(enemy,{newHp=strike#newHp,dmg=...})::Alerted(enemy,true)::Released(enemy)::Nil)
             ::: ringLifestealEvents ::: weaponLifestealEvents   // knockback は P1c で append
```

kill 分岐の証明済み hard-0 clamp `newHp=0` を維持。coreEvents を fold -> worldMid。THEN `exps = expEvents(worldMid, attacker, defender, killed)`（CombatSystem:95/103 の arg を `world` から `worldMid` に CHANGE して level-up hp base = post-lifesteal hp とし、lifesteal 更新後シーンを読むレガシー applyExpGain に合わせる）。exps を worldMid に fold -> world1。

- `attackerHp = World.hpOf(attacker#ref, world)`（resolve START 時。プレイヤー hp は自分の攻撃で不変）
- `attackerMaxHp = World.combatViewOf(attacker#ref, world)#maxHp`

Ring-lifesteal（レガシー CombatScene:560-567、kill-only）: `amt = Ring.lifestealAmount(World.equippedRingOf(attacker#ref, world))`。killed and amt>0 なら `Lifesteal(attacker#ref, {newHp=Combat.heal(attackerHp,attackerMaxHp,amt)#newHp, amt=amt})`。

Weapon-lifesteal（レガシー CombatScene:573-585、kill-INDEPENDENT）:
```
match World.combatViewOf(attacker#ref, world)#weapon {
  case None => Nil
  case Some(wv) =>
    let pct = WeaponCatalog.lifestealPercent(wv#effect, wv#effectValue);
    let h = (dmg*pct)/100;
    if pct>0 and dmg>0 then Lifesteal(attacker#ref, {newHp=Combat.heal(attackerHp,attackerMaxHp,h)#newHp, amt=h}) :: Nil else Nil
}
```

`newHp` AND `amt` の両フィールドが Lifesteal リテラルに REQUIRED（World.flix:387）。両方ともオリジナル `attackerHp` から計算。weapon-lifesteal を LAST に emit して SetHp を勝たせる。

既存 7 goldens を検証: no ring + None/NoEffect weapon -> 両 list Nil -> coreEvents==現状、worldMid hp==world hp、expEvents(worldMid)==expEvents(world) -> 射影同一 AND kill path が正確に 3 events（Damaged::Dying::ExpGained）を維持（TestCombatSystem.flix:82）。

**newSimEvents**: なし — 両 lifesteal は `SimEvent.Lifesteal`（-> `Cmd.SetHp`）を REQUIRED な `{newHp,amt}` ペイロードで再利用。P1a の `equippedRing` + `combatViewOf#weapon:Option[WeaponView]` を再利用。

**files**:
- `src/ecs/systems/CombatSystem.flix`
- `test/ecs/TestGoldenTrace.flix`

**goldenTest**:
4 つの新 fixture（全て runAttack legacyW にピン留め）。
- (a) `testResolveCombatEqualsLegacyRingLifesteal`: プレイヤー hp5/maxHp10 exp0、Ring{Lifesteal,power=5}、敵 hp4->kill、heal +5 -> プレイヤー hp10。assertEq（hpOf(Player0)、hpOf(Enemy1)）。
- (b) `testResolveCombatEqualsLegacyWeaponLifesteal`: プレイヤー hp5、blood weapon{Lifesteal,effectValue=50,hit=200,crit=0}、敵 hp20 survives、dmg=4->heal2->hp7。assertEq（hpOf(Player0)、hpOf(Enemy1)、alertedOf(Enemy1)）。
- (c) `testResolveCombatBothLifestealEmitOrder`: プレイヤー hp5/maxHp10、Ring{Lifesteal,power=5} AND blood weapon{Lifesteal,effectValue=50,hit=200}、敵 hp4->kill（ring +5 hp5->10、その後 weapon +2 をオリジナル hp5->7 から）。レガシーは ring-then-weapon last-write-wins -> 最終 = weapon 結果。assertEq hpOf(Player0)（emit order AND 両方オリジナル hp 起点をピン留め）。
- (d) `testResolveCombatRingLifestealLevelUp`: プレイヤー hp5/maxHp10、exp は LEVEL CATALOG LITERAL の LeveledUp 閾値にピン留め（gainExp で再計算しない）、growthRates は post-lifesteal hp が pre-lifesteal と hpOf/progressOf で OBSERVABLY 異なるよう選ぶ、Ring{Lifesteal,power=5}、敵 hp4->kill で hp10 に heal THEN level-up が growth を POST-lifesteal hp に加算。assertEq（hpOf(Player0)、progressOf(Player0)）。worldMid!=world となる唯一の fixture。expEvents が依然 `world` を読むと FAIL する。

全て viewSome-both + evCount>0。

**risks**:
1. 二相 fold は既存 7 goldens で射影同一を維持（no lifesteal -> worldMid==world）AND kill path で正確に 3 events を保持（TestCombatSystem.flix:82）。
2. Lifesteal リテラルは newHp AND amt の両方を含む（World.flix:387）。さもなくば typecheck FAIL。
3. Combat.heal は POSITIONAL。
4. weapon-lifesteal の base hp = オリジナル world hp、worldMid ではない。
5. combatViewOf#weapon は Option。None => weapon-lifesteal なし。
6. emit order ring-then-weapon が load-bearing。fixture (c) がピン留め。
7. kill 分岐の Damaged{newHp=0} hard-0 clamp を維持。
8. fixture (d) の exp 閾値は level catalog からピン留め。growth は post-lifesteal hp を observably に異ならせること。さもなくば回帰時でも (d) が vacuous に pass。

**dependsOn**: P1a-finisher

---

### P1d-thief — thief drop が view-only（World 変更なし）であることを REAL thief weapon + rogue ゲートの下で確認

**approach**:
`maybeThiefDrop`（CombatScene:613-624）が floor-item の副作用（`CustomEffects.ThiefDropRequest`）で World 変更ゼロであることを確認/文書化する。thief roll は既に `_thiefRoll`（CombatSystem:90）として draw-order alignment のため draw されている。rogue ゲート（`player#resource#description=="ローグ"`）は sim が運ばない SCENE-ONLY データで、必要ない（thief effect はいずれにせよ Cmd を emit しないので、resolveAttack は World 等価のためのロジック変更を要さない）。

OPTIONALLY hit 時に `SimEvent.ViewFx(ViewFxKind.Thief({x,y}))` を emit（cosmetic。reducer identity。eventToCmds->Nil なので cmdKey/World 比較の OUTSIDE に留まり、non-thief fixture の 3-event kill-path count を perturb しない）。`_thiefRoll` は hit 時に無条件で draw を維持。

1 行: thief floor-drop は scene-only、除外。

**newSimEvents**: なし — 既存 `ViewFx(ViewFxKind.Thief)` の optional 再利用（view-only、reducer identity、eventToCmds->Nil）。

**files**:
- `src/ecs/systems/CombatSystem.flix`
- `test/ecs/TestGoldenTrace.flix`

**goldenTest**:
新規ガード `testResolveCombatThiefViewOnly` — NON-VACUOUS: プレイヤー resource を `{description="ローグ" | testResource(...)}` で isRogue ゲート（CombatScene:619）を FIRE させ、thief weapon{effect=ThiefDrop,effectValue=100,hit=200,crit=0}。敵 hp20 survives。`runAttack`（harness が withNoopThiefDrop でラップ）-> legacyW vs `withSeededRng(seed())` 下の resolveAttack sysW を駆動。assertEq（hpOf(Enemy1)、hpOf(Player0)、alertedOf(Enemy1)、progressOf(Player0)）sysW==legacyW。REAL に fire した thief weapon は消費した draw 以外 World で何も変えない。posOf は省略（P1d は P1c に先行。thief hit で敵は動かない）。

**risks**:
1. rogue ゲートは scene-only。fixture が description="ローグ" を設定するのは LEGACY パスに thief 分岐を fire させるためだけ（デフォルト "" => vacuous）。
2. ViewFx(Thief) を追加する場合、eventToCmds は Nil に map（既に配線済み）。cmd/World 比較と 3-event 不変条件の外に留める。
3. 最低価値スライス。`_thiefRoll` alignment を回帰ロック。
4. dependsOn=[] — `_thiefRoll` だけを必要とする。

**dependsOn**: なし

---

### P1c-knockback — Knockback（Knockback weapon、敵 survives）-> 敵 pos を Moved 経由。posOf + mapSnapshot(Option) + boardOf(Option) を追加

**approach**:
`pub def posOf(ref,world): Option[{x=Int32,y=Int32}]` = `let World.World(w)=world; Map.get(toUid(ref), w#pos)`（既存 w#pos store 上の純粋。今日 MISSING。最初に追加、DoD-blocking）を追加。

World read-model `mapSnapshot : Option[MapSnapshot]`（プレーンな type-alias、storable）を追加: `empty()`=None。`syncFromScene`/`refreshMirror` = `Some(BoardSnapshot.mapSnapshotOf(scene))`（toBoard が使うのと同じソース、World.flix:961）。

`pub def boardOf(world): Option[Board]` = `let World.World(w)=world; Option.map(m -> {map=m, pieces=World.boardPieces(world)}, w#mapSnapshot)` を追加 — 既存の pure-World `boardPieces(world)`（World.flix:983）を VERBATIM 再利用。`toBoard` は **リファクタしない**（既存 golden `testGoldenFinalBoardParity` に消費されている。触れると回帰リスク）。`mapSnapshotMismatches` parity verifier を追加。

`CombatSystem.resolveAttack` で、coreEvents の weapon-lifesteal の後に、レガシー `applyAttackKnockback`/`pushEnemyBack`（CombatScene:590-609）を踏襲:
```
match World.combatViewOf(attacker#ref, world)#weapon {
  case None => Nil
  case Some(wv) => match WeaponCatalog.knockbackTiles(wv#effect, wv#effectValue) {
    case None => Nil
    case Some(tiles) =>
      if (killed) Nil
      else (match (World.posOf(attacker#ref,world), World.posOf(defender#ref,world), World.boardOf(world)) {
        case (Some(a), Some(d), Some(board)) =>
          let dir = Staff.toVec2i(Staff.deltaToDirection(d#x - a#x, d#y - a#y));
          let cap = if (tiles<=0) None else Some(tiles);
          (match List.last(Board.knockbackPathCapped(d, dir, board, cap)) {
            case Some(landing) => World.SimEvent.Moved(defender#ref, landing) :: Nil
            case None => Nil
          })
        case _ => Nil
      })
  }
}
```

`Staff.deltaToDirection` は 2 つの Int32（dx,dy）を取る。Moved->Cmd.Move は既に配線済み。draw なし。Knockback は defender survives（killed=false）のときだけ。boardOf が Option を返すことで empty()-world（None）は安全に no knockback。

**newSimEvents**: なし — knockback は `SimEvent.Moved` を再利用。新 read-model `mapSnapshot : Option[MapSnapshot]` + `boardOf(world): Option[Board]`（既存 boardPieces を再利用）+ `posOf` アクセサ + `mapSnapshotMismatches`。

**files**:
- `src/ecs/World.flix`
- `src/ecs/systems/CombatSystem.flix`
- `test/ecs/TestGoldenTrace.flix`

**goldenTest**:
新規 `testResolveCombatEqualsLegacyKnockback`: プレイヤー Knockback weapon{effect=Knockback,effectValue=2,hit=200,crit=0}、敵 hp20 survives、壁なし floor。敵 {3,2}、プレイヤー {2,2} -> dir +x、2 タイル押されて {5,2}。`runAttack` -> legacyW（EnemyScene.snapTo:577 が Cmd.Move を emit するので legacyW は moved pos を運ぶ）vs resolveAttack sysW を駆動。assertEq（posOf(Enemy1)、hpOf(Enemy1)）sysW==legacyW、combatViewOf-Some both + evCount>0。

PLUS combined-effects サブ fixture `testResolveCombatCritKnockback`（安価な coreEvents-ordering ピン）: crit-survive weapon（crit=200）WITH Knockback effect、敵 survives -> assertEq（hpOf(Enemy1)、posOf(Enemy1)、alertedOf(Enemy1)）sysW==legacyW、Damaged->Alerted->Released->knockback order を end-to-end でピン。

**risks**:
1. mapSnapshot は Option[MapSnapshot] として store（empty() では None — そこにシーンなし。MapSnapshot に empty ctor がないので非 optional フィールドは unconstructable）。
2. boardOf は Option[Board] を返し boardPieces(world)（既に pure-World、factored）を再利用。toBoard リファクタなし。
3. Board occupancy は resolve-time に w#pos 経由で両戦闘者を含む。
4. posOf は DoD-blocking かつ trivial。最初に追加。
5. Staff.deltaToDirection(dx,dy) は 2 つの Int32。
6. knockbackPathCapped は occupancy-set order-independent。piece order vs fromScene 安全。
7. 3-event kill-path 不変条件を維持（knockback は survive 時のみ append）。

**dependsOn**: P1b-lifesteal

---

### P2-enemy-path — 敵攻撃パス: resolveEnemyAttack（ViewFx(Died) 経由の deferred death、effectRule Status/Immobilize->Afflicted、exp なし、KNOCKBACK-FREE）

**approach**:
World read-model `effectRule : Map[EntityId, Util.Json.Json]`（敵のみ）を enemy `#resource#effectRule`（Option[Json] — enemies 上で Query.indexBy、accessor が flatten）から `empty()`(Map.empty)/`syncFromScene`/`refreshMirror` でミラー + `pub def effectRuleOf(ref,world): Option[Json]`（Option.flatten）+ `effectRuleMismatches` を追加。pure leaf `hpPct(cur,max)`（CombatScene.hpPct 踏襲）を追加。

新規 `pub def resolveEnemyAttack(world, attacker: Combatant, defender: Combatant): (World, List[SimEvent]) \ World.RngDraw` を CombatScene.resolveEnemyAttack:710-770 の draw 構造（プレイヤーと DISTINCT）を踏襲して追加:
- hitRoll(1) draw。miss -> `(world, [ViewFx(Sound("miss"))])`。
- hit -> critRoll(2) draw（crit は hit 時のみ）。finisherFired は `World.equippedRingOf(attacker)`（敵 ring、P1a 由来）経由。outcome = finisher>crit>base を applyFinisher/applyCrit over defView#hp。
- coreEvents = `Damaged(defender#ref, {newHp=outcome#newHp, dmg=outcome#dmg})` — RAW newHp、hard-0 clamp なし（Combat.damage unclamped。レガシー CombatScene:753 は raw を set）`:: (killed ? World.ViewFx(World.ViewFxKind.Died(defender#ref))::Nil : Nil) :: Released(defender#ref)::Nil`（UNCONDITIONAL、CombatScene:759。Alerted なし）`::: enemyRingLifesteal`（kill-only、`Lifesteal(attacker#ref,{newHp,amt})`、P1b ヘルパーを faction-blind に再利用）`::: enemyWeaponLifesteal`（`Lifesteal(attacker#ref,{newHp,amt})` を combatViewOf(attacker)#weapon から）。

PLAYER DEATH は `ViewFx(Died)` のみ emit（`Dying` ではない — SetDying(player) は World no-op、World.flix:519。Dying(player) は phantom cmd になる）。knockback 分岐なし（KNOCKBACK-FREE。boardOf を呼ばない）。

二相 fold coreEvents->worldMid。その後 effectRule tail（applyEnemyEffectRule CombatScene:785-822 を踏襲）:
- `fired = (forM(j <- World.effectRuleOf(attacker), rule <- EffectBridge.fromComposer(j)) yield rule) |> Option.filter(rule -> triggerFiresOnHit(rule#trigger, killed))`
- None -> draw/events なし。
- Some(rule) -> effectRoll(3) draw（CONDITIONAL）。`predCtx = {selfHpPct=hpPct(World.hpOf(attacker#ref,world)|>Option.getWithDefault(0), World.combatViewOf(attacker#ref,world)#maxHp), targetHpPct=hpPct(outcome#newHp, World.combatViewOf(defender#ref,world)#maxHp), targetAlive=outcome#newHp>0, equippedIsRogue=false, adjacent=true}`。
- `EffectPlan.shouldFire(rule,predCtx,roll)` でなければ events なし。else `ctx={selfId=enemyId, attackerId=enemyId, actorIsPlayer=false, rayUnits=[{id=defenderId, ally=true, immobilized=false, alive=outcome#newHp>0}], amount={max=World.combatViewOf(defender#ref,world)#maxHp, dealt=outcome#dmg, incoming=0, magic=0}}`（CLOSED 4-field amount — incoming/magic REQUIRED）。
- `plan = EffectPlan.planActions(rule, ctx)`。StatusAt/ImmobilizeAt items -> `Afflicted(refOf(ally,id), status)`（World.emitStatusAdds の EXACT マッピングを再利用。pure `planItemToAfflicted` leaf に factor）。
- HealAt/FullHealAt -> P2b に DEFERRED。
- DamageAt/MaxHpUpAt/ReviveAt -> EXCLUDED（ハンドラ no-op + emitHpSets が同 hp を re-emit = net no-op、fire しても安全。ガード (d) は belt-and-suspenders）。

expEvents なし。

1 行: 敵 weapon durability は scene-only、除外。

**newSimEvents**: なし — Damaged/Released/Lifesteal/Afflicted + ViewFx(Died/Sound) を再利用。新 read-model `effectRule`（Option-store）+ アクセサ + parity verifier + pure hpPct leaf。SetAlerted/SetDying(player) は no-op 確認済み。Dying(player) は依然回避（phantom cmd）。

**files**:
- `src/ecs/World.flix`
- `src/ecs/systems/CombatSystem.flix`
- `test/ecs/TestGoldenTrace.flix`

**goldenTest**:
3 つの新等価テスト + 1 つのガード。
- (a) `testResolveEnemyCombatEqualsLegacyEffectRule`（StatusAt）: fixture-B シーン再利用（プレイヤー hp10、敵 hp10 weaponHit=200、spdDown onHit rule）。`runEnemyAttack(sc,1)->legacyW` vs `resolveEnemyAttack(w0,{ref=Enemy1,..},{ref=Player0,..})`。assertEq（hpOf(Player0)=Some(6)、statusEffectsOf(Player0) を (effect,magnitude,remaining)=[(SpdDown,3,3)] に射影）sysW==legacyW。クロスチェック `evs|>flatMap(eventToCmds)|>map(cmdKey) == fixture-B golden [SetHp(player,6), ClrImmob(player), Add(player,SpdDown,3)]`（Damaged->Released->Afflicted。ViewFx->Nil）。
- (b) `testResolveEnemyImmobilize`（ImmobilizeAt）: 敵 immobilize-onHit rule、プレイヤー survives。assertEq statusEffectsOf(Player0)（Immobilized present）。
- (c) `testResolveEnemyOverkillsPlayer`（RAW no-clamp）: プレイヤー hp2、敵 weaponHit=200,crit=0 empty rule -> レガシー newHp = 2-dmg(4) = -2（OVERKILL、clamp と区別可能）。assertEq（hpOf(Player0)=Some(-2)、statusEffectsOf(Player0)）。RAW negative hp をピン（hard-0 clamp は Some(0) で FAIL）AND killing blow での ClearImmobilized。
- (d) `testEnemyEffectRuleNoHpOps` ガード: 全 P2/P3 敵 fixture rule の planActions が DamageAt/MaxHpUpAt/ReviveAt を含まない AND HealAt/FullHealAt PlanItem を含まない（heal は P2b に deferred — HealAt を emit する P2 fixture は diverge する）AND P2/P3 敵 weapon が Knockback effect を持たない、ことを assert。

全て viewSome-both + evCount>0。

**risks**:
1. draw 構造がプレイヤーと異なる（crit は hit 時のみ。effectRoll CONDITIONAL）か seed が runEnemyAttack と diverge。
2. Player death = ViewFx(Died) NOT Dying AND hp clamp なし。fixture (c) overkill (-2) がピン（lethal-exact 0 は vacuous）。
3. kill 時も Released。
4. ctx amount は CLOSED 4-field {max,dealt,incoming=0,magic=0}。
5. Lifesteal リテラルは {newHp,amt} を要する。
6. effectRule は EffectBridge.fromComposer で parse。
7. ガード (d) は今や P2-only fixture について HealAt/FullHealAt も除外（heal は P2b に住む）。
8. P2/P2b は CombatScene の effectRule ロジックを複製（private defs、EffectRunner Scene-effecting）。cross-impl parity verifier なし。出荷 fixture でのみピン（accepted risk。将来の CombatScene effectRule 変更が silently diverge しうる — 将来の shared pure leaf 向けに note）。

**dependsOn**: P1a-finisher, P1b-lifesteal

---

### P2b-enemy-heal — 敵 effectRule HealAt/FullHealAt -> Healed(self)、別個にピン留め

**approach**:
resolveEnemyAttack の effectRule tail（P2）を拡張し、HealAt/FullHealAt EffectPlan items も -> `SimEvent.Healed(attacker#ref, {newHp=hv, amt=hv-enemyHp})`（両フィールド required、World.flix:386）に map。`enemyHp = World.hpOf(attacker#ref, world)`（resolve START 時）。`enemyMaxHp = World.combatViewOf(attacker#ref, world)#maxHp`（==resource#hp 不変条件）。

hv は EffectRunner の敵 heal ハンドラを REPLICATE: 実装で検証済み、敵 effectHeal ハンドラは `Combat.heal(enemyHp, enemyMaxHp, amt)#newHp`（heal ハンドラ == Combat.heal、ソース由来）。
- HealAt(amt) => `Combat.heal(enemyHp, enemyMaxHp, amt)#newHp`
- FullHealAt => `enemyMaxHp`

CRITICAL ordering（CombatScene:817-820）: `emitStatusAdds(plan)` が `emitHpSets(plan)` の BEFORE に走る -> tail で Afflicted events を Healed events の BEFORE に emit。この分岐は P2 と SEPARATE に保ち、自身の golden とだけマージ。

EXPLICIT DoD EXCLUSION（de-scoped、未カバー）: 敵 lifesteal+heal STACKING — ring/weapon lifesteal が既に同じ敵をこの strike で heal していたら、レガシー emitHpSets は POST-runPlan シーンを読み prior heal に STACK する。lifesteal weapon/ring AND heal effectRule の両方を持つ敵の fixture は出荷しないので、このパスは UNPINNED のまま出荷し明示的に除外（出荷 P2b golden は敵 lifesteal weapon/ring なしの heal rule を使うので、START 時 enemyHp == runPlan base）。

**newSimEvents**: なし — `SimEvent.Healed`（-> `Cmd.SetHp`）を REQUIRED な {newHp,amt} で再利用。新 read-model なし。

**files**:
- `src/ecs/systems/CombatSystem.flix`
- `test/ecs/TestGoldenTrace.flix`

**goldenTest**:
新規 `testResolveEnemyHealEffectRule`: HealAt/FullHealAt effectRule（lifesteal weapon/ring なし）を持つ敵を reduced enemy hp（hp5/maxHp10）で、survive するプレイヤーへ攻撃。`runEnemyAttack(sc,1)->legacyW` vs resolveEnemyAttack sysW。assertEq hpOf(Enemy1) sysW==legacyW（self-heal newHp を Combat.heal clamp 込みでピン）。combined status+heal rule を使う場合、cmdKey stream order `[Add(status) ... SetHp(enemy,...)]` も assertEq して emitStatusAdds-before-emitHpSets をピン。

**risks**:
1. Self-heal base hp = オリジナル enemy hp（stacking combo は明示的に DE-SCOPED — fixture は exercise しない）。
2. hv は敵 heal ハンドラ == Combat.heal(hp,resource#hp,amt) を replicate（ソースで検証済み、presume ではない）。
3. emit order status-before-heal が cmd-stream parity に load-bearing。
4. Healed リテラルは {newHp,amt} を要する。
5. このスライスなしでは P2 は heal 分岐を emit しない（ガード (d) が P2 fixture に HealAt なしを assert）。このスライスが全 EMITTED 分岐をピン留めし続ける。

**dependsOn**: P2-enemy-path

---

### P3-counter — Counter-chain: resolveAttack(player) THEN resolveEnemyAttack(enemy) が counter final World を再現

**approach**:
新しい CombatSystem/World コードなし — 純粋 COMPOSITION 検証。テストで、1 つの `withSeededRng(seed())` thunk の下:
```
(w1,evs1)=resolveAttack(w0,{ref=Player0,level=1},{ref=Enemy1,level=1});
(w2,evs2)=resolveEnemyAttack(w1,{ref=Enemy1,level=1},{ref=Player0,level=1});
```

w2 を新しい composed legacy oracle と比較（既存 golden D `testGoldenCounterChain` ではない。後者は敵 hp=10 を pre-set しプレイヤー strike を OMIT する）。

PRNG framing: レガシー onLungeDone は sim が決して引かない followUp roll を引くので、2 つの PRNG stream はプレイヤー攻撃後に DIVERGE する。等価は VALUE-INDEPENDENCE で成立: この fixture config では引かれる全 outcome が値非依存（weaponHit=200 always-hit、crit=0 never-crit、effectRule なし、level-up なし）なので、draw 位置の差は World 射影を変えられない。decideView->Counter に SINGLE counter strike で provably 到達する config を使う — non-brave weapon + equal speed で `EffectFlow.followUpDecision(Brave/Pursuit)` を FAIL させる。比較を hp/alerted/status ONLY に射影制限（attackTarget を EXCLUDE — レガシー onLungeDone は sim が emit しない ClrTgt(player)/AtkTgt を emit する。pos も EXCLUDE — どちらの weapon も knockback なしなので pos は invariant。approach/goldenTest の矛盾を除去）。

**newSimEvents**: なし — composition のみ。resolveAttack（P1a/P1b）+ resolveEnemyAttack（P2）を再利用。

**files**:
- `test/ecs/TestGoldenTrace.flix`

**goldenTest**:
新規 `testResolveCounterChainEqualsLegacy`。新しい always-hit config を構築（golden D の weaponHit=80 を引用しない）: プレイヤー(exp=0, hp=4, atkTgt=Some(1), weaponHit=200, crit=0) vs 敵 hp=10 weaponHit=200 crit=0、non-brave weapon + equal speed => Pursuit/Brave fail、single strike。

新しい composed legacy oracle を 1 つの `withTracedWorld(seed())` の下:
```
s1=applyAttackHit(0,sc)              // プレイヤーが敵にダメージ、敵 SURVIVES+alerted
s2=onLungeDone(Player,0,s1)          // decideView->Counter
((_,killed),_,legacyW)=applyEnemyAttackHit(1,s2)  // 敵 counter、プレイヤーを kill
```

Sim: 上記のように w0 上で compose。assertEq（hpOf(Enemy1)、hpOf(Player0)、alertedOf(Enemy1)、statusEffectsOf(Player0)）w2==legacyW、both-views-Some ガード付き。

INTERMEDIATE GUARDS は ORACLE にピン留め（self-guessed リテラルではない）:
- w1 の hpOf(Enemy1) == legacyW の hpOf(Enemy1)（敵が single strike を survive）
- evCount(evs1) が follow-up プレイヤー strike なしを示す（decideView->Counter をロック、brave double-strike ではない）
- progressOf(Player0) が level-up なしを示す（プレイヤー exp sub-threshold）
- プレイヤーが counter で死ぬ -> hpOf(Player0)==legacyW の値（ここでは正確に 0）

**risks**:
1. seed framing は stream alignment ではなく VALUE-INDEPENDENCE。レガシー onLungeDone は followUp roll を引き、brave flag + speed parity 経由で SECOND プレイヤー strike を inject しうる — non-brave/equal-speed で followUpDecision を FAIL させること。enemy-hp-vs-oracle + evCount ガードが stray extra strike を検出。
2. 敵はプレイヤー strike を SURVIVE しなければならない（hp10 vs dmg4）。decideView が Kill でなく Counter を yield するよう。
3. プレイヤーは counter で DIE しなければならない（hp4、敵 dmg4）。deferred-death を end-to-end でピン（ViewFx(Died)、World hp 0）。
4. 両 resolve を SINGLE withSeededRng の下で thread。
5. どちらの weapon も Knockback なし（board なし）NOR heal effectRule なし（P2b dep なし）。
6. 比較集合は attackTarget（orchestration-owned）AND pos（knockback-free、invariant）を EXCLUDE。
7. プレイヤー exp=0/no-level-up が REQUIRED。
8. w1 enemy-hp ガードは legacyW にピン留め、self-guessed Some(6) ではない。

**dependsOn**: P1b-lifesteal, P2-enemy-path
