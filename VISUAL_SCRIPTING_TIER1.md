<!-- 受領: Tier1 ビジュアルスクリプティング計画 v5（2026-06-29 採用）。
レビュー4lens最終 [grounding 90, completeness 90, scope-honesty 82, user-value 87]。
82/87 は (a) 行アンカー freshness が移行スライスのコミットで陳腐化する構造的要因、(b) golden-family の1誤引用が主因。
**:NNN は cc9e6ad 時点のスナップショット＝二次。一次アンカーは def 名で再 grep すること。**
実装は将来着手。SimEvent 代数=IR ゆえ既存純粋層の薄い orchestration で実現可能（演出の完全巻き戻しは A 完成待ち）。 -->

# Tier 1 ビジュアルスクリプティング基盤 — 実装計画 v5

スコープ: オフラインの **シミュレータ＋デバッガ基盤**。既存の `SimEvent` ストリーム（`CombatSystem` / `StaffSystem`）に対して、(1) headless 実行 (2) SimEvent タイムライン可視化 (3) ステップ実行 (4) 巻き戻し を実現する。engine（`flix.toml` の `flix_game_engine` / `flix_engine_ecs`）は read-only。実装は `examples/fe_rogue` 内に閉じる。

> **アンカー方針**: 本計画は HEAD `cc9e6ad` で全行参照を再アンカーした。World.flix は World 強化 commit 群で ~+10〜+30 行ずれてきた実績がある。**一次アンカーは `def 名`（シグネチャ）とし、`:NNN` は HEAD `cc9e6ad` 時点の二次補助**。冒頭バナーの freshness 主張も同じく `cc9e6ad` のみで有効（HEAD が World/Combat の先へ動いたら def 名で再 grep）。

> **v4 → v5 の主要変更（レビュー 4 巡目・全 lens 反映サマリ）**
> 1. **counter fixture の hp 誤読を全面訂正**（grounding blocking）。旧版が約 6 箇所で「敵 hp200／player200/enemy200／hp200/hp200」と書いていたのは**捏造**。fixture シグネチャは `player(exp, hp, atkTarget, weaponHit)`（TestGoldenTrace.flix:37）と `enemy(id, hp, gridPos, isDying, atkTarget, rule, weaponHit)`（:64）。`player(0,4,Some(1),200)` = exp0/hp4/atkTarget Some(1)/**weaponHit200**、`enemy(1,10,...,200)` = hp10/**weaponHit200**（:937）。末尾 200 は**命中固定＝常時命中**（`fxWeapon hit=200`・常時命中 :102-103）で、**hp ではない**。実 hp は **player=4・enemy=10**。「敵 hp200 が single strike を survive」は誤りで、正しくは **敵 hp10 > strike dmg4（:35 命中ダメージ4）ゆえ survive**、プレイヤーは hp4 に counter を食らって死亡（:931,:934）。結末（敵生存・味方死亡）は正しいが**機構の説明が捏造**だった。
> 2. **decision サイドカーの ring-finisher 寄与の出所を訂正**（completeness blocking）。pub 化した `combatOutcome` の**再呼び出しだけでは ring-finisher の +dmg 寄与は取れない**。返り値 `Outcome = {dmg, newHp, killed, isCrit}`（CombatSystem.flix:58）は分岐を畳み、`isCrit = finisherFired or crit`（:115）が finisher と crit を**混ぜる**うえ、finisher の限界 +dmg を載せるフィールドが**無い**。よってサイドカーは `Ring.finisherTriggers`（catalog/Ring.flix:143）+ `Ring.finisherThreshold`（:138）+ `Combat.applyFinisher`（Combat.flix:112）を `strike#dmg` に対し**別途再評価**し delta を出す＝CombatSystem.flix:104-115 の finisher 分岐の**意図的な小複製**。この 1 セグメントに限り「複製しない／drift しない」断定を撤回。
> 3. **「1 語変更（def→pub def）」会計の訂正**（completeness blocking）。`combatOutcome` の返り型 `Outcome` は**module-private な `type alias`**（CombatSystem.flix:58・`pub` 無し）。private alias を名指す `pub def` が Flix でコンパイルできるか未確認＝**増分 0 のコンパイルゲート**。対処は二択を明記: (a) `Outcome` も `pub` 化（**2 語**になる）か、(b) シグネチャに `{dmg=Int32, newHp=Int32, killed=Bool, isCrit=Bool}` を**インライン展開**する。どちらを採るか §3 で確定。
> 4. **サイドカーの入力再構築依存を補完**（completeness improvement）。`combatOutcome` を再呼び出すには `atk`/`defView` を `World.combatViewOf`（World.flix:980・pub）で、`strike` を `CombatRules.resolveStrike`（:14）で先に再構築する必要がある。finisher 判定には `World.equippedRingOf`（World.flix:948・pub）も要る。これらを §2e/§9 の必須前提に追加（旧版は `resolveStrike` のみ列挙＝不足）。
> 5. **生存ガードの非コンパイル擬似コードを是正**（grounding/scope-honesty improvement）。`SimEvent` は Eq 非派生（enum 閉じ :464・derive 句なし実確認）。捕捉ガードの `ev == SimEvent.Dying(def#ref)` は生 `==` でコンパイルしない。述語ヘルパー `isDyingEvent(ref, ev)`（`eventEntity :734` + タグ判定）を**擬似コード本体に直書き**し、コピペで非コンパイル `==` を書かせない。renderEvent 例の等値比較示唆も同様。
> 6. **MVP に最小 decision 注釈を前倒し＋縮退契約バナー固定**（user-value blocking）。トレース (A) 撃破は `Damaged` 単発なので、その 1 行に限った hit/crit/dmg 内訳注釈を **MVP（増分 1）に前倒し**（pub 化は `combatOutcome` 1 語＝§2e 既定路線・増分小）。最低でも MVP human projector の**先頭ヘッダ行に §1.2 縮退契約バナー**（結果値のみ／命中ロール・必殺・指輪 +dmg 寄与は増分 2.5 まで非表示）を 1 行固定。
> 7. **§0 メンタルモデル補正を MVP 出力先頭行へ焼き込み**（user-value improvement）。doc コメントだけでなく **human projector の string golden 先頭行**（ユーザーが必ず読む出力）に「指輪は死亡の後」「死亡 XOR 反撃」を出すことを増分 1 のチェック項目化。
> 8. **spike 失敗時フォールバックの床を `println` ダンプに固定**（user-value blocking）。`getArgs` が空でも、実証済み `println`（Game.flix:1053 パターン）で `worldAt(t,k)` を stdout へ整形ダンプする 1-shot 関数を**保証下限**として明記。assert 故意失敗に依存しない「回す動詞」の床を確定。
> 9. **decision 注釈の具体行フォーマット例を追加**（user-value improvement）。§2e に 1 サンプル行を載せ 6 段が文字列でどう出るか pin。
> 10. **全 World.flix 行参照を `cc9e6ad` で再アンカー**（既存）。`applyEventToWorld :696`、`eventToCmds :716`、`eventEntity :734`、`cmdKey :779`、`SimEvent` enum :464（derive 無し）、`Lifesteal(EntityRef,{newHp,amt}) :469`、`statusEffectsOf :558`、`alertedOf :820`、`isDyingOf :828`、`posOf :853`、`equippedRingOf :948`、`combatViewOf :980`、`progressOf :1013`、`hpOf :1114`、`boardKey :1300`、`syncTreeFromWorld :1362`、`empty() :123` / `rng = Prng.seed(0i64) :144`。`combatOutcome` は private `def` :101、返り型 private alias `Outcome` :58。

---

## 0. まず無料で出る価値 — メンタルモデル補正（コード前）

実調査だけで、ユーザーの口頭モデルと実装の**3 つのズレ**が判明した。これらはタイムラインを描く前に提示できる第一級の成果物であり、**MVP human projector の string golden 先頭行に焼き込む**（増分 1 チェック項目・§5/§6）。

1. **指輪 lifesteal は「攻撃直後」ではなく「死亡の後」に emit される**。実 emit 順は `fx → Damaged → (撃破なら) Dying → ViewFx(Died) → lifesteal → knockback → exp`（`CombatSystem.flix:200-224`・`coreAll = fx ++ coreEvents ++ lifesteal ++ knock`）。ユーザーの「攻撃→指輪→…」順とここで食い違う。
2. **「死亡」と「反撃」は構造的に相互排他**。敵が死ねば（`Dying` emit）その敵からの反撃 `resolveEnemyAttack` は起きない。逆に敵が生存すれば撃破 exp は出ない。よって 1 本のトレースに「死亡＋反撃」は合成できない（§5 で 2 トレースに分割）。
3. **ユーザー列挙順「攻撃→指輪→比較→反撃→死亡→経験値」は実順と 2 箇所食い違う**: (a) 指輪は死亡の後、(b) 反撃は死亡と排他。さらに「比較（命中/必殺/ダメージ算出）」は SimEvent に出所が無く、そもそもタイムラインの 1 行にならない（§2e）。

---

## 1. 目的と価値

ユーザーは「攻撃の一連」を **scene/render なしで** 視覚確認・ステップ・巻き戻ししたい。既存コードはこの土台をほぼ持っている。

- `CombatSystem.resolveAttack` / `resolveEnemyAttack` は `(World, List[SimEvent]) \ World.RngDraw` を返す純 System（`CombatSystem.flix:181, :261`）。scene/anim/view を一切触らない。
- `StaffSystem.resolveStaffCast(world, caster, effect, dir, hit)` は `(World, List[SimEvent])` を **effect なし**で返す（`StaffSystem.flix:32`）。
- `World.applyEventToWorld(ev, world): World`（`:696`）が `SimEvent → World` の純 reducer。
- `World.eventToCmds(ev): List[Cmd]`（`:716`）＋ `World.cmdKey(c): (String,Int32,Int32,Int32)`（`:779`）が SimEvent を比較可能タプル列へ落とす純関数（**oracle 用**）。
- `World.eventEntity(ev): Option[EntityRef]`（`:734`）が各イベントの主体 entity を返す（**表示の行ラベル用**・ただし entity 無し fx は `None`）。
- `ViewReplay.plan(events): List[ViewAction]`（`src/scenes/ViewReplay.flix:33`、`ViewAction with ToString`）が view 演出列。多くの SimEvent を `Nil` に落とす（view レーン専用）。
- `TestGoldenTrace` が「scene 無しで fixture World に戦闘を走らせ seeded PRNG で決定論結果を凍結する」ハーネスを実証（`test/ecs/TestGoldenTrace.flix`、`driveResolve :107`、合成 counter は `testResolveCounterChainEqualsLegacy :936`）。

つまり Tier 1 は **新メカニズムの発明ではなく、これら純粋層を「捕捉→畳み込み→射影」する薄い orchestration の追加**である（例外: §2e サイドカーのみ src/ System に `pub` 到達が要る）。

### 1.1 入力ソースの誠実な定義（誇大回避）

本計画の capture は **fixture World（`syncFromScene(fixtureScene, World.empty())`）を seed にした既存 System の決定論再走**であり、「ユーザーが実際にプレイした特定セッションの記録」**ではない**。

- `attackTargetId` 等は SCENE で seed される。live World と fixture World が異なれば再走結果は live と乖離しうる。
- 達成するのは「**任意 fixture を seed に攻撃/杖の決定論的結末をタイムラインで観る**」であって「自分の実セッションを後から巻き戻す」ではない。後者は live World snapshot を capture seed に注入する別増分が要る（§8 に名前付き）。

### 1.2 ユーザー事前合意（曖昧放置の解消・指輪二面性込み）

戦闘デバッガの最高価値は「結果」より「**なぜその結果か（算出根拠）**」だが、ユーザー列挙 6 段のうち「比較（命中/必殺/ダメージ算出）」「指輪寄与のダメージ分」は `SimEvent` payload に出所が無く、**SimEvent 射影だけでは原理的に出せない**（§2e で実証）。本計画は次のいずれかで決着させる（曖昧な optional 放置をしない）。

- **既定（推奨）**: decision サイドカー（§2e）を組み込む。**最小注釈（トレース (A) 撃破の単発 `Damaged` 1 行への hit/crit/dmg 内訳）は MVP（増分 1）に前倒し**、フル 6 段は増分 2.5。
- **縮退合意**: サイドカーを採らない場合、「**本デバッガは結果のみ表示し、命中ロール・必殺判定・ダメージ算出・ring finisher のダメージ寄与は表示しない**」をユーザーと事前合意し契約として固定する。この契約文を **MVP human projector のヘッダ先頭行に常時表示**（着手前に限界を飲ませる導線）。

**指輪の二面性（MVP で過大解釈させない）**: lifesteal は独立 `SimEvent.Lifesteal(EntityRef, {newHp, amt})`（World.flix:469）ゆえ human projector に**専用行が出る（見える・`+amt` 表示可）**。一方 **ring finisher の +dmg は `Damaged#dmg` に溶けるため「指輪がダメージへ何点寄与したか」は MVP では見えない**（サイドカーが要る・§2e）。「指輪が見える＝全部見える」ではない点を合意に明記。

**MVP の 6 段カバレッジ（何が見えて何が見えないか）**: 攻撃／結果（命中/ダメージの**値**）／死亡／報酬 の 4 段は SimEvent 射影で出る。「**比較（なぜ当たった/必殺か・算出根拠）**」「**ring finisher 寄与**」の 2 段は SimEvent だけでは出ない。MVP では (A) 撃破トレースの単発 `Damaged` に**最小サイドカー注釈**を前倒しで載せ、フル比較は増分 2.5。

---

## 2. アーキテクチャ

トレースの正準表現（新規 type alias・純粋値）:

```
SimTrace = { initial : World, events : List[World.SimEvent] }
```

`initial` ＋ `events` から全中間状態が決定論的に再導出可能（`World` は不変レコード・plain data・§8 参照）。

### (a) トレース捕捉 — re-run/fold（instrument しない）

instrument（live パスにフック挿入）ではなく **fixture World に既存 System を再走させ返り値の `[SimEvent]` を集める**。根拠:

- System は既に `(World, [SimEvent])` を返すので捕捉に追加配線不要。
- live パスは別経路で scene/Godot を巻き込む。re-run なら純粋層だけで閉じる。
- §1.1 の通り、これは「legacy 公式との等価」を担保するのであって「特定 live セッションの emit との一致」は担保しない。

**捕捉ドライバは 3 形**（実シグネチャが異なるので分ける）。

**1. 単発攻撃 `captureStrike`**（`driveResolve :107` の一般化・**撃破トレースの主役**）:
```
captureStrike(w0, attacker, defender, seed) : SimTrace        // \ なし（region 内で discharge）
  = region rc {
      withSeededRng(rc, seed, () -> resolveAttack(w0, attacker, defender))
    } の (_, evs) から { initial = w0, events = evs }
```
撃破シナリオ（**敵の現在 hp を strike dmg4 未満に下げた fixture**・例 `enemy(1, 3, ...)`、weaponHit=200 で常時命中）はこれ 1 本で「攻撃→死亡→指輪 lifesteal→経験値」が出る。**反撃は出ない**（撃破済み）。

**2. 攻撃→反撃の交換 `captureExchange`**（**生存トレースの主役**・生存ガード必須・単一ソース判定）。`testResolveCounterChainEqualsLegacy`（`:966-972` で実証）の合成を API へ昇格しつつ**撃破時 skip ガード**を加える。ガードは**System が実際に emit した `evs1` の `Dying` 有無**で分岐する（独立再導出しない）。`SimEvent` は Eq 非派生（enum 閉じ :464・derive 句なし）ゆえ生 `==` はコンパイルしない＝**述語ヘルパー `isDyingEvent` を本体に直書き**:
```
// SimEvent は Eq 非派生（World.flix:464）。生 == は不可ゆえ eventEntity+タグで判定。
def isDyingEvent(ref, ev) = match ev {
    case SimEvent.Dying(r) => r == ref      // EntityRef は Eq 可
    case _                 => false
}

captureExchange(w0, atk, def, seed) : SimTrace
  = region rc { withSeededRng(rc, seed, () ->
        let (w1, evs1) = resolveAttack(w0, atk, def);
        // 生存ガード（単一ソース）: System が defender 撃破時に emit する Dying を直接検査。
        // 撃破分岐は Damaged(newHp=0) :: Dying :: ViewFx(Died)（CombatSystem.flix:208-210）。
        // hp==0 の独立再導出は clamp/status-death と二重ソース化するので使わない。
        let killed = List.exists(ev -> isDyingEvent(def#ref, ev), evs1);
        if (killed) (w1, evs1)            // 撃破: 反撃なし＝撃破トレースへ退避
        else
            let (w2, evs2) = resolveEnemyAttack(w1,
                {ref = def#ref, level = 1},   // role 反転: 元 defender が attacker
                {ref = atk#ref, level = 1});  // 元 attacker が defender
            (w2, List.append(evs1, evs2))
      ) }
    から { initial = w0, events = evs }
```
golden の実引数（`TestGoldenTrace.flix:965-968`）では `atk = {ref = EntityRef.Player(0), level = 1}`、`def = {ref = EntityRef.Enemy(1), level = 1}` で開始し、反撃の `resolveEnemyAttack` は `attacker = Enemy(1)`、`defender = Player(0)` と role 反転する。**この反転を取り違えると counter が無音になる**。`evs1 ++ evs2` の連結はログ専用で、生存パスの `w2` は System が `applyAll` で畳んだ最終 World と一致（§4 PRIMARY oracle が `proj(legacyW)` と pin 済み・`:976-979`）。

**counter fixture の実値**: `player(0,4,Some(1),200)` / `enemy(1,10,{x=3,y=2},false,None,ruleJson(""),200)`（`:937`）。末尾 **200 は weaponHit（常時命中）で hp ではない**。実 hp は player=4・enemy=10。**敵 hp10 > strike dmg4 ゆえ single strike を survive**（:35,:931）し **else 側のみ到達**、敵反撃が hp4 のプレイヤーを撃破する（味方死亡・kill exp なし・:934）。**if 側（撃破退避）はこの fixture では非到達**ゆえ §6 に「敵現在 hp を strike dmg4 未満（例 `enemy(1, 3, ...)`）にした専用 fixture」の撃破退避テストを足す。

**3. 杖 `captureStaff`**（effect-free・seed 不要・シグネチャ別形）:
```
captureStaff(w0, caster, effect, dir, hit: RayHit) : SimTrace     // seed なし・RngDraw なし
  = let (_, evs) = resolveStaffCast(w0, caster, effect, dir, hit); { initial = w0, events = evs }
```
`resolveStaffCast(world, caster, effect, dir, hit)` は seed なし・`RayHit` 構築が要る（`StaffSystem.flix:32`）。`captureStrike` とは**シグネチャが異なる**。よって「同 API」ではなく「**同パターン（再走→[SimEvent] 収集）**」。

`w0` はいずれも fixture から `World.syncFromScene(scene, World.empty())`（`:172`）。`World.RngDraw` の discharge は `TestUnitFixtures.withSeededRng(rc, seed, thunk)`（`:432`）を再利用。

### (b) ステップエンジン — `applyEventToWorld` の foldLeft 蓄積

中間 World 列は **`events` を 1 個ずつ `applyEventToWorld` で畳む `foldLeft`** で作る（純粋・RNG 不要）。本コードベースに `scanLeft`/`List.scan` の使用例は無い（`foldLeft` が標準）ので具体形を固定:
```
worldsAfter(t: SimTrace) : List[(World.SimEvent, World)]
  = let (_, accRev) =
        List.foldLeft((acc, ev) ->
            let (w, rows) = acc;
            let w2 = World.applyEventToWorld(ev, w);
            (w2, (ev, w2) :: rows),          // 逆順に push
          (t#initial, Nil), t#events);
    List.reverse(accRev)
```
**捕捉済み `[SimEvent]` の再生に PRNG は要らない**: `SimEvent` は確定値を持つ（`Damaged{newHp,dmg}`、`Lifesteal{newHp,amt}`、`LeveledUp{...}`・`World.flix:464-477`）。`applyEventToWorld` は roll を引かない純 value→value（`ViewFx(_)` は World identity）。ゆえにステップ・巻き戻しは完全決定論・副作用ゼロ。`TestSimEvent` が単段適用を実証済み。

### (c) 巻き戻し — snapshot 列（既定）＋ prefix 再 fold（検証）

1. **snapshot 列（既定）**: (b) の `worldsAfter` が全中間 World を保持。`World` は不変値なので「任意ステップ k へ戻る」＝リスト k 番目の読み出し（`worldAt(t,k)`）。**コスト注記**: Flix の Map/record は persistent で未変更部分木を構造共有するが、各ステップは新 World record ＋変更パス分を必ず割り当てる。正しくは「**フルコピー不要・O(変更分) の追加割当**」。
2. **prefix 再 fold（検証・oracle ではない）**: `initial` から先頭 k 個を `applyEventToWorld` で再 fold しても同じ World に到達（fold は決定論）。長いトレースで全 snapshot を保持したくない場合、`initial` ＋ index だけで再生可能（§7 メモリ上限のフォールバック）。

**PRNG 状態の保存と continuation の限界**: `World.rng : Prng.State`（`Prng.State(Int64)`・`src/ecs/Prng.flix:22`、`rawState :28`）は各 snapshot に同梱される値。**ただし `w0 = syncFromScene(sc, World.empty())` ゆえ各 snapshot の `World.rng` は `World.empty()` 既定の `Prng.seed(0i64)`（`World.flix:144` 実確認）であり、`seedRng(seed)` ですらない**。捕捉時の `World.RngDraw` は `withSeededRng` のハーネス側 `wref`（`TestUnitFixtures.flix:434` `wref = seedRng(seed, World.empty())`）でだけ進み、System に渡す `world` 引数の `rng` には**一切届かない**。帰結:

- **Tier 1 の巻き戻し（捕捉済みトレース内の移動）は純 fold で完結＝PRNG 注入不要＝この問題と無関係**（正しく機能する）。
- 「巻き戻し地点から続きを**再 sim**したい」continuation は、snapshot の `World.rng`（seed すら入らない既定値）を再注入しても roll を replay すらできず continue にならない。正しい continuation には終端 `wref` 状態（ハーネス worldRef の最終 `Prng.State`）の carry が要る＝**Tier 1 外**（§7 で線引き）。

### (d) 表示モデル — 3 レーン（実 emit 順に忠実・人間可読を正準）

#### イベントレーン（正準 = human semantic projector・cmdKey ではない）

`cmdKey` タプル（例 `("SetHp",1000001,0,0)`）は `World.flix:779` のコメント通り「Cmd に Eq が無いための比較通貨」＝**oracle 専用**で、「敵が HP0 で死亡」と読めない。よって表示レーンは**専用 human projector にコミット**:

```
renderEvent(w_before, ev, w_after) : String     // 純関数・既存アクセサのみ・等値比較せず match で分岐
  // Damaged(Enemy(1), {newHp=0, dmg=10}) → "Player(0) → Enemy(1) に 10 ダメージ → Enemy(1) HP 0"
  // Dying(Enemy(1))                      → "Enemy(1) 死亡"
  // Lifesteal(Player(0), {newHp=10, amt=3}) → "Player(0) 指輪 lifesteal +3 → HP 10"   // ★ amt を表示
  // ExpGained({entity=Player(0),...})    → "Player(0) +exp → Lv2 (exp34)"
  // entity 無し fx（eventEntity=None）:
  // ViewFx(Sound(name))     → "[SE] ${name}"            // ViewFxKind から直接射影
  // ViewFx(Explosion(cell)) → "[爆発] (${cell.x},${cell.y})"
```
材料は `eventEntity(ev)`（`:734`・主体／fx は None）、`Damaged#dmg`/`#newHp`、`Lifesteal#newHp`/**`#amt`**（World.flix:469・吸収量を `+amt` で表示＝§2e の寄与表示と整合）、`ExpGained{newLevel,newExp}`、`LeveledUp{...}`、`Afflicted` の status kind、entity 無し fx は `ViewFxKind`（Sound/Explosion/Popup）から直接。**全て `match` 分岐で書く（`SimEvent` は Eq 非派生ゆえ `==` 不可）**。entity 名の人間可読化は `EntityRef`（faction＋id）。cmdKey は §6 PRIMARY oracle に限定し表示レーンから外す。

#### 論理段ラベル（メンタルモデル整合・実順序は保持）

タイムラインは**実 emit 順のまま**提示しつつ、各行にユーザーの口頭モデルに対応する**論理段ラベル**を付与する:

| 論理段 | 該当 SimEvent | 注 |
|---|---|---|
| 攻撃 | `ViewFx(Sound)` + `ViewFx(Explosion)` | fx 先頭・entity None |
| 結果（命中/必殺/ダメージ） | `Damaged{newHp,dmg}` | 算出根拠は §2e サイドカー（MVP は (A) 単発のみ最小注釈／無ければ「結果値のみ」） |
| 結果（死亡） | `Damaged(newHp=0)` → `Dying` → `ViewFx(Died)` | 撃破トレースのみ・指輪より前 |
| 支援（指輪 lifesteal） | `Lifesteal{newHp,amt}` | 死亡の後に emit／吸収量は `+amt`／**finisher +dmg 寄与は溶けて非表示** |
| （ノックバック） | `Moved{着地}` / `ViewFx(Knockback)` | 生存時のみ |
| 報酬 | `ExpGained` / `LeveledUp` | 撃破トレースのみ |
| 反撃 | `resolveEnemyAttack` の別 System | **生存トレースのみ** |

#### view レーン（`ViewReplay.plan`・任意）

`plan(events)`（`ViewReplay.flix:33`）で `ViewAction` 列を得る（`with ToString`＝直接 `toString` 比較可）。`ExpGained/LeveledUp/Afflicted/Released/Alerted/Dying` を `Nil` に落とす（実確認）のは**仕様**。これら欠落イベントは human projector のイベントレーンには出る＝**2 レーンの非対称は意図的**（§7 再掲）。

#### 状態レーン（World diff）

各ステップ前後 World を既存アクセサで比較行に落とす純粋 projector。射影対象 entity は `eventEntity(ev)`（`:734`）で当該ステップが触れた entity を集める（fx は None ゆえ diff 対象なし）。使うアクセサ: `hpOf :1114`, `posOf :853`, `progressOf :1013`, `statusEffectsOf :558`, `alertedOf :820`, `isDyingOf :828`, `boardKey :1300`。これらは `TestGoldenTrace.killProj :288` と同じ「World→Eq 可能タプル射影」確立パターン。diff は隣接段 2 射影の差分。

#### 実 emit 順（コード確認・`CombatSystem.flix:200-224`）

```
fx(命中SE＋魔法爆発)  →  Damaged(敵, newHp)  →  [撃破なら] Dying(敵) → ViewFx(Died 敵)
                                                [非撃破なら] Alerted(敵,true) → Released(敵)
   →  Lifesteal(攻撃側, {newHp,amt})   →  Moved(敵, knockback 着地)   →  ExpGained / LeveledUp
```
（`coreAll = fx ++ coreEvents ++ lifesteal ++ knock`、続いて `exps`・`:219-224`。死亡は指輪 lifesteal より前。反撃は別 System `resolveEnemyAttack :261`。）タイムラインはこの実順序のまま提示し論理段ラベルを併記する。「メンタルモデル順そのまま」とは言わない。

### (e) decision サイドカー — 比較／指輪寄与の注釈（実装 1 経路確定・honesty-over-purity の意図的選択）

ユーザーが最も知りたい「なぜ当たったか/必殺か/ダメージはどう算出されたか」「指輪がどれだけ寄与したか」は、`resolveStrike`/`Combat.isHit`/`combatOutcome`（`CombatSystem.flix:187-198`）が SimEvent を積む**前に内部消費**し、`Damaged` は結果 `{newHp,dmg}` しか持たない。ring finisher の +dmg も畳まれる。**表示モデル（SimEvent 列の射影）では原理的に出せない**。

**access 依存の正直な決着**: 中間値を生む `combatOutcome :101` / `lifestealEvents :120` / `expEvents :144` は**いずれも private `def`**。さらに `combatOutcome` の**返り型 `Outcome` も private `type alias`（:58）**。だが**実体は全て pub なルール関数の合成**:
- `CombatRules.resolveStrike(atk, defView) :14`（pub）→ `{hit, dmg, newHp, killed, crit}`。
- `Combat.isHit(strike#hit, hitRoll) :79`（pub）／`Combat.isCrit(strike#crit, critRoll) :98`（pub）。
- `Combat.applyFinisher(strike#dmg, defView#hp) :112`（pub）／`Combat.applyCrit(...) :103`（pub）／`Combat.heal(...) :133`（pub）／`Combat.battleExp(...) :301`（pub）。
- `Ring.finisherTriggers :143`（pub・catalog/Ring.flix）／`Ring.finisherThreshold :138`（pub）／`Ring.lifestealAmount :127`（pub）。
- `World.combatViewOf :980`（pub）／`World.equippedRingOf :948`（pub）＝サイドカーが `atk`/`defView`/装備指輪を**再構築する入力源**。
- `combatOutcome :104-115` の唯一の private ロジックは「finisher か crit か base か」の**分岐選択**。

実装は**1 経路に確定**（複製も推測もしない・ただし finisher 寄与だけは下記の意図的小複製）:
- **`combatOutcome` を `pub` 化**（src/ の System ファイルに到達）。返り型 `Outcome` が private alias（:58）なので、**増分 0 で「`pub def` が private alias を返せるか」をコンパイル確認**し、不可なら (a) `Outcome` も `pub` 化（2 語）か (b) シグネチャに `{dmg=Int32, newHp=Int32, killed=Bool, isCrit=Bool}` をインライン展開（§3 で確定）。
- **入力再構築**: `World.combatViewOf(atk#ref/def#ref, world)` で `atk`/`defView`、`CombatRules.resolveStrike(atk, defView)` で `strike`、`World.equippedRingOf(atk#ref, world)` で装備指輪を復元する（`combatOutcome` 再呼び出しの前提）。
- **roll の固定捕捉**: `withRecordedRolls(rc, seed, thunk)`（`TestUnitFixtures.flix:444`・戻り値 `(a, List[Int32])`＝draw 順 percent 列）で `resolveAttack` を走らせ、引かれた `(hitRoll, critRoll)` を順序込みで捕捉（draw 順 hit→crit→thief・`CombatSystem.flix:187-198`、thief は `_thiefRoll :198` で World 不変）。記録した `critRoll` を pub 化 `combatOutcome` に、`hitRoll` を `Combat.isHit` に渡し `fin#isCrit`/`fin#dmg`/`fin#newHp`/lifesteal の `+amt` を**再評価**。
- **ring finisher の +dmg 寄与だけは combatOutcome 返り値から取れない**: `Outcome = {dmg,newHp,killed,isCrit}`（:58）は分岐を畳み、`isCrit = finisherFired or crit`（:115）が finisher と crit を混ぜ、finisher の限界 +dmg を載せるフィールドが無い。よってサイドカーは `Ring.finisherTriggers(defView#hp, defView#maxHp, Ring.finisherThreshold(equippedRing))` で発火判定し、発火時 `Combat.applyFinisher(strike#dmg, defView#hp)#dmg − strike#dmg` を delta として算出する＝**CombatSystem.flix:104-115 finisher 分岐の意図的な小複製**（再呼び出しだけでは不可能）。この 1 セグメントに限り「複製しない」断定は撤回する。
- **naive な別 region 再評価は禁止**（別 roll を引き crit/miss が乖離する）。同 seed・同 draw 列を `withRecordedRolls` で固定するのが要点。

**注釈の具体行フォーマット例**（6 段が文字列でどう出るか pin）:
```
[攻撃]   [SE] damage / [爆発] (3,2)
[比較]   hit 72 ≤ 命中85% → HIT  /  crit 40 > 必殺10% → no-crit
[結果]   dmg = 5 base − 1 def (+ ring-fin +6) = 10  → Enemy(1) HP 0
[死亡]   Enemy(1) 死亡
[支援]   Player(0) 指輪 lifesteal +3 → HP ...
[報酬]   Player(0) +exp → Lv2 (exp34)
```
（数値はサンプル。`ring-fin +N` は上記 delta、`lifesteal +M` は `Lifesteal#amt`。）

**選択の性質（honesty-over-purity・inevitability ではない）**: `combatOutcome:104-115` の唯一の private ロジックは既に全 pub な primitive 上の分岐選択にすぎないので、src/ を一切触らず `src/sim` で分岐を再実装する**代替も技術的には可能**。本計画が pub 化を選ぶのは「**最小の API 表面増（pub 1〜2 語・§7 CI で固定）**」を「**src/ ゼロ改変だが分岐ロジック再実装の drift リスク**」より優先する**意図的なトレードオフ**であって、不可避ではない。defer 時は §1.2 縮退合意一択。

---

## 3. どこに住むか（src/ への変更範囲を明示）

**選定: 純粋 orchestration を新規 `src/sim/` モジュール（`SimTrace.flix` / `SimDebugger.flix`）に置き、駆動・検証を `test/`（`TestSimDebugger.flix`）で行う。MVP のユーザー体験は §5 増分 0 の spike 結果で確定（既定は `flix test` golden 読み）。Godot 上の debug Scene（任意増分 5）のみ `src/scenes/` へ。**

**src/ への変更範囲（engine read-only とは別レイヤ・正直に列挙）**:
- 新規: `src/sim/SimTrace.flix`、`src/sim/SimDebugger.flix`（capture/step/rewind/diff/human-projector/decision サイドカー）。
- 既存 src/ への最小改変（**サイドカー採用時のみ**）: `src/ecs/systems/CombatSystem.flix` の `combatOutcome` を `def` → `pub def`。**会計の確定**: 返り型 `Outcome` も private `type alias`（:58）なので、増分 0 のコンパイル確認結果に応じ **(a) `Outcome` も `pub`（合計 2 語）** か **(b) `combatOutcome` シグネチャに `{dmg,newHp,killed,isCrit}` をインライン**のどちらかを採る。「1 語」断定はしない。ロジック追加・変更はなし。サイドカー不採用なら src/ 既存ファイルは無改変。

根拠:

- `src/sim/` は既に非 scene の sim ヘルパー置き場（`EncounterBuilder.flix`, `BoardSnapshot.flix`）。capture/step/rewind/diff/human-projector は全て `World`/`SimEvent` の純関数（capture のみ `World.RngDraw`）で scene/Godot 非依存＝正しい住所。
- 駆動・決定論検証は `flix test` で完結（`TestGoldenTrace` の実績、`withSeededRng` 再利用）。`Main.flix`/`Game.flix` の start/gameLoop を触らない＝Godot ライフサイクル制約と非衝突。
- debug Scene（Godot 上の対話 UI）は MVP 不要。scene を足すと `syncTreeFromWorld :1362` 経由 render・gameLoop 統合・NodeTag 設計が要りスコープが膨らむ。増分 5 に隔離。

却下案: live combat への instrument（§2a の理由）、engine 側追加（read-only ゆえ不可）。

---

## 4. 決定論・RNG の扱い

- 捕捉は固定 seed の `withSeededRng(rc, seed, ...)`（`TestUnitFixtures.flix:432`）で `World.RngDraw` を discharge。`Prng` は splitmix64 純 PRNG（`src/ecs/Prng.flix`）で「同 seed → 同 draw 列」を保証。
- **ステップ・巻き戻しは `applyEventToWorld` の fold のみ＝RNG を一切引かない**（§2b）。既存 golden-trace の決定論等価を壊しようがない（同じ純関数を同順で呼ぶだけ）。
- **PRNG 値 snapshot の限界（再掲・§2c）**: 各 snapshot の `World.rng` は `World.empty()` 既定の `Prng.seed(0i64)`（seed すら入らない）。seed はハーネス `wref` 専用で `SimTrace` に保存されない。**Tier 1 巻き戻し＝純 fold（PRNG 注入不要）／continuation 再 sim＝終端 `Prng.State` carry が必要＝Tier 1 外**。
- **legacy 等価検証（PRIMARY oracle）**: 捕捉トレースの最終 World を `killProj :288` / `boardKey :1300` / 合成 proj（counter は `:976-979`）で射影し、legacy 凍結値（撃破系 `killProj == (Some(0),Some(10),Some((2,34)))`、counter は `proj(legacyW)`）と一致を assert。これが「デバッガが legacy と同じ世界に収束する」回帰固定の主軸。reproducibility は二度引きに倣う。

## 4.5 ユーザー価値を出す最小層（substrate と体験の分離・IO 機構を接地）

増分 1–4 の純粋成果物は `flix test` の golden literal であり、それ単体では「動詞ループ（step/rewind）」をユーザーが回せない。**Godot 外の対話入力（stdin/argv）が本ランタイムで取れるかは未検証**（`readLine`/`stdin`/`getArgs`/`argv`/`Console.` の**入力 IO** は `src/`・`test/` に**ゼロ**＝実確認）。一方 **stdout 出力は実証済み**: `println` が `Game.flix:1053-1119`（F2 debug-diff）と `DungeonGenerator.flix:116` に現存し、`Main.flix:7-9` は `Fs.FileRead/FileWrite.runWithIO`・`Math.Random.runWithIO` を install する（ただし `getArgs`/`stdin` は install しない）。よって誠実に段階化する:

- **MVP 体験の既定（出力のみ・確実）**: human projector（§2d）で「人間可読な 1 行イベント列＋論理段ラベル」を組み、`worldAt(t,k)` の射影を **`flix test` の string golden として人が読む**。step/rewind は「k を変えて golden を読む」形で**テスト内で動詞を体験**できる（巻き戻し＝list index 読み出しがテストに見える）。
- **保証下限の動詞ループ（spike 結果に依存しない床）**: 実証済み `println` で **`worldAt(t,k)` を stdout へ整形ダンプする 1-shot 関数 `dumpAt(t, k)` を `SimDebugger` に必ず置く**（System.IO/stdin 不要・既存 Game.flix:1053 debug-diff と同型）。これにより `getArgs` の可否や assert 故意失敗に**依存せず**、最低限の「回す動詞（k を変えて再実行→ダンプを読む）」が常に成立する。
- **任意増分（要 stdin/argv 検証＝増分 0 で裏取り）**: `dumpAt` を debug サブコマンドで k を**引数駆動**にする。**Godot 埋め込みランタイムで `getArgs` が実値を返すかを増分 0 で先に確定**。返さない場合は「REPL/TUI」表現を撤回し「引数 k を取る 1-shot ダンプを step 毎に再起動」へ弱める、もしくは増分 5（Godot scene のスライダ）まで対話を defer する（ただし上記 `dumpAt` 床は常に有効）。

「純粋層＋標準 IO のみで REPL が回る」という断定は撤回し、入力 IO 入手性を増分 0 の裏取り事項として明記する。

---

## 5. MVP → 増分

各段が前段に乗る最小刻み。**看板シナリオは「死亡 XOR 反撃」の構造的相互排他ゆえ 2 トレースに分割**する（1 本に合成しない）。

**0. IO/ドライブ可能面 spike＋pub-alias コンパイルゲート（ゲーティング・着手前 1 時間）**: (i) Godot 埋め込み runtime で `getArgs` が空 List か実値かを 1 テスト／1 起動で確定。(ii) **`pub def combatOutcome` が private `type alias Outcome`（:58）を返せるかをコンパイル確認**（不可なら §3 の (a) alias も pub / (b) インライン を決定）＝サイドカー全体のコンパイルゲート。同時に **MVP ユーザーを明示再定義**: spike が「実値」なら「k を引数で渡して動かせる開発者デバッガ」、空なら「テスト golden ＋ `println` ダンプを読む開発者」。どちらでユーザー合意を取るかをここで決める。

1. **MVP（テキスト・タイムライン／2 トレース＋最小注釈）**: `src/sim/SimTrace.flix` に `SimTrace` 型・`captureStrike`・`captureExchange`（Dying 単一ソース生存ガード付き）。イベントレーン render = human projector（§2d・**cmdKey ではない**・全 `match` 分岐）。**human projector の先頭ヘッダ行に固定**: (a) §1.2 縮退契約バナー、(b) §0 メンタルモデル補正（「指輪は死亡の後」「死亡 XOR 反撃」）。`test/ecs/TestSimDebugger.flix` が既存 golden fixture を流し行・順序を凍結。看板を **2 本**で達成（**seed/fixture が別物**な点を明記）:
   - **(A) 撃破トレース**（`captureStrike`・**敵の現在 hp を strike dmg4 未満に下げた fixture**・例 `enemy(1, 3, ...)`・weaponHit=200 で常時命中）: 「攻撃→**死亡**→指輪 lifesteal→経験値」を実 emit 順で表示（**反撃なし**）。**この単発 `Damaged` 行に最小 decision 注釈（hit/crit/dmg 内訳）を前倒し**（§2e・pub 化 + roll 記録で 1 行注釈）。
   - **(B) 生存交換トレース**（`captureExchange`・fixture `player(0,4,Some(1),200)`/`enemy(1,10,...,200)`＝**weaponHit=200・実 hp player4/enemy10**・敵が single strike を survive）: 「攻撃→被弾（敵生存）→**反撃**→**味方死亡**」を表示（**kill exp なし**＝プレイヤーは敵未撃破）。
   - **命中確定性の pin（事実・open risk ではない）**: 両 fixture とも `weaponHit=200`（`fxWeapon hit=200`＝常時命中・:102-103）ゆえ **strike は構造的に必中**（seed 任せの miss は起きない）。seed 依存で変わるのは **crit のみ**（hit ではない）。この事実を 1 行 pin し golden 安定性を担保する。
   - golden 凍結は cmdKey タプル直書き（`("Progress",0,2,34) :: ...`・`TestGoldenTrace.flix:243-249` 形式・**`toString` 文字列フォーマット依存を避ける**）で **oracle 比較**し、human projector の出力行は別途 string golden で固定。**tag 文字列は cmdKey の実タグ**（`SetProgress`→`"Progress"`、`SetDying`→`"Dying"`、`SetHp`→`"SetHp"`）、第 2 field は `toUid(ref)`（`Player(0)=0`、`Enemy(1)=1000001`）。
2. **ステップ実行**: `worldsAfter`（§2b の foldLeft 蓄積）。各段 World を `hpOf/posOf/progressOf/statusEffectsOf` 射影でテキスト化。テストで「ステップ i 後 hp」を pin。
   - **2.5 decision サイドカー フル 6 段（§1.2 既定で組み込み）**: §2e の「比較/必殺/ダメージ帰属/指輪寄与」注釈を `withRecordedRolls` で同 seed 記録し、pub 化した `combatOutcome` + `combatViewOf`/`resolveStrike` 再構築で再評価、ring finisher delta は `applyFinisher` の小複製で算出して SimTrace 並走表に持つ。採らない場合は §1.2 縮退合意を契約化。
3. **中間 World diff**: 隣接段射影差分のみを行に出す（変化フィールドだけ）。射影対象 entity は `eventEntity` で当該ステップ分を列挙。human projector ラベルで「何が起きたか」を併記。
4. **巻き戻し**: 任意 k への `worldAt(t,k)`（snapshot 列 index ＝既定／`initial` から prefix 再 fold ＝検証）。杖（`captureStaff`・effect-free・seed なし）も同パターンで捕捉。
   - **4.5 薄い対話層（任意・増分 0 の結果次第）**: §4.5。保証下限の `dumpAt(t,k)` stdout ダンプは常に提供。`getArgs` 入手性の裏取り後に引数駆動 or REPL を決める。
5. **簡易ビジュアル（任意・defer 可）**: `src/scenes/` に read-only debug Scene。各ステップ World を `syncTreeFromWorld(world, scene) :1362` で render に投影しスライダで k 駆動。**§A cutover 後にのみ live と同 render 経路を共有**。Godot/gameLoop 統合が初めて要る＝1〜4 と独立に切り出す。

---

## 6. テスト戦略

- **純粋層中心**: capture/step/rewind/diff/human-projector は全て `World`/`SimEvent` の純関数。`flix test` で `World.RngDraw` を `withSeededRng` で discharge して駆動（`TestGoldenTrace` と同型）。
- **テスト本体でパターンマッチを避ける慣習に準拠**: `killProj :288` 等の射影ヘルパー＋具体値リテラルで assert。
- **比較戦略を型ごとに分離**:
  - `ViewAction` は `with ToString`＝`toString` 比較可。
  - `SimEvent` は `ToString` も `Eq` も無い（enum 閉じ :464・derive 句なし）＝`eventToCmds|>cmdKey` のタプル射影・`eventEntity` でのみ比較（生 `toString`/`==` はコンパイルしない。生存ガードの `Dying` 検査も述語ヘルパー `isDyingEvent` で書く）。
  - `Cmd` は Eq 無し＝`cmdKey :779` が唯一の比較通貨。
- **回帰固定**: (i) MVP のタイムライン cmdKey 行を golden literal（タプル直書き）で凍結＋human projector 出力行を string golden で凍結（**assert 失敗時に整形済みタイムライン全文を表示**）、(ii) 最終 World が `TestGoldenTrace` 既存 legacy 射影（`killProj`/`boardKey`/counter `proj`）と一致＝**PRIMARY oracle**、(iii) `worldAt(t,k)` の snapshot==prefix 再 fold を全 k で assert。
- **生存ガードの撃破分岐 pin（v5）**: counter fixture（実 hp enemy=10）はガードの撃破分岐（if 側）を踏まない＝デッドコード懸念。**敵現在 hp を strike dmg4 未満にした別 fixture（例 `enemy(1, 3, ...)`・weaponHit=200 で必中）で `captureExchange` を走らせ、`Dying` が emit され反撃が走らず（`evs2` 空）撃破トレースと bit-identical に退避する**ことを 1 本 pin。
- **(iii) の性質を正直に**: 両 System は `applyAll(events, world)`（`CombatSystem.flix:61-62, :226`・`StaffSystem.flix:37`）を返し `worldsAfter` も同じ `foldLeft applyEventToWorld`。よって snapshot==再 fold は **foldLeft 決定論／prefix 結合性の確認に過ぎず oracle ではない**。oracle は (ii)。(iii) は内部整合チェック。

---

## 7. リスクと「やらない」線引き

**やらないこと（明示）:**

- **Tier 2 オーサリング**（visual で新ロジック定義・effect DSL ノードエディタ）はスコープ外。本計画は既存 `SimEvent`/System の**観測のみ**。**例外（正直に）**: §2e サイドカー採用時は `CombatSystem.combatOutcome` を `pub` 化する src/ 改変が要る（返り型 alias の扱い次第で 1〜2 語・§3）＝「観測のみ」の境界が緩む。さらに ring-finisher delta は CombatSystem.flix:104-115 finisher 分岐の意図的小複製を持つ（再呼び出しでは取れない・§2e）。サイドカー不採用なら src/ 既存無改変。
- **ライブ実プレイ中のノードハイライト**はスコープ外。`SimEvent` に provenance タグが無い（`enum SimEvent :464`）。タイムラインは各イベントを 0..n の index で参照し、後日 provenance を「index→source 表」または `SimEvent` 拡張として足す素地を残す（§8）。
- **capture は fixture-seeded 再走であって live セッション録画ではない**（§1.1）。live を観たいなら live World snapshot を capture seed に注入する増分が要る（§8 に名前付き）。
- **「死亡」と「反撃」は同一トレースに合成しない**（構造的相互排他・§0/§5）。撃破トレース（死亡あり・反撃なし）と生存交換トレース（反撃あり・敵生存・味方死亡）の 2 本に分ける。
- **「比較」（命中/必殺/ダメージ算出）と「ring finisher 寄与」は SimEvent に出所が無い**（§2e）。§1.2 の決着（サイドカー組み込み or 縮退合意）を着手前にユーザー確認。曖昧な optional 放置はしない。
- **巻き戻し地点からの continuation 再 sim はしない**（終端 `Prng.State` carry が未保存＝§2c/§4）。Tier 1 の巻き戻しは捕捉済みトレース内の純 fold 移動に限る。
- **演出の完全忠実な巻き戻しはしない**。scene/anim/音は副作用（`ViewReplay.execute`）で un-play 不可。割り切り: **World は完全に巻き戻る（純 fold）／演出は再導出（`plan` を任意 k で再評価）or 非再発火**。完全忠実化は §A 完成（`syncTreeFromWorld` 一本化）後に初めて成立。

**リスク:**

- **MVP の体験ギャップ**（user-value）: increment 1–4 の成果物は test golden で、ユーザーが回す動詞面が弱い。**増分 0 spike で `getArgs` 可否を先に確定**し、保証下限 `dumpAt` stdout ダンプ（§4.5・`println` 実証済み）で「回す動詞」の床を確保。test-golden-only に踏み切る場合は MVP ユーザーを「テストを読む開発者」と明示再定義しユーザー合意を取る。
- **capture が legacy と乖離**: `TestGoldenTrace` の `testResolveCombatEqualsLegacy*` 群が安全網。ただし保証は「新 sim System == legacy 公式」であって「debugger 再走 == 特定 live セッション emit」ではない（後者は §1.1 のソース注入が前提）。
- **2 レーン非対称**: `Thief`（未配線・emit されない）に加え、`plan` が `ExpGained/LeveledUp/Afflicted/Released/Alerted/Dying` を落とすため view レーンに出ない。これらは human projector のイベントレーンには出る＝**仕様**。
- **worldsAfter のメモリ上限**: snapshot 列は全中間 World を保持する。現状 1 戦闘の SimEvent 列は短く実害なしだが、長いトレースでは §2c の prefix 再 fold フォールバック（`initial`＋index で再生・全 snapshot 非保持）に切り替える。
- **サイドカー pub 化の波及**: `combatOutcome`（＋必要なら `Outcome` alias）の pub 化は API 表面を増やす。ロジック不変なので回帰リスクは低いが、`flix test` 全体のコンパイル・既存 golden 不変を CI で確認。private alias を返す `pub def` のコンパイル可否は増分 0 ゲートで先に潰す。
- **§4.5 の入力 IO 入手性が未検証**: Godot 埋め込みで stdin/argv が取れない場合、対話 REPL は不成立。MVP 体験を出力のみ（string golden ＋ `println` ダンプ `dumpAt`）に固定し対話を増分 0 の裏取り後へ隔離。
- **engine read-only**: 追加は全て `src/sim/`・`test/`・（サイドカー時のみ `CombatSystem.flix` 1〜2 語）・（任意で）`src/scenes/` に閉じる。

---

## 8. 将来接続

- **live セッション巻き戻しへの道（名前付き将来増分: "live-seed injection"）**: 「自分が見た攻撃を巻き戻す」へ到達する条件は、**live combat 直前の World snapshot を `captureStrike/Exchange` の `w0` に注入**し、かつ live パスが消費した seed/draw 列を carry すること。Tier 1 の `SimTrace = {initial, events}` はこの注入の受け皿（`initial` を live snapshot に差し替えるだけ）で、表示/step/rewind 層は無改修で再利用できる。時期: live パスの seed 露出 API 整備後（Tier 1 外）。
- **S8 セーブとの関係**: World record は **plain data**（Set/Map/Option/`StatusEffects`/`Prng.State` 等のみ・`Scene[NodeTag]` field を**保持しない**＝`World.flix:32-120` で実確認）。`rng` は `rawState`/`seedRng` で値化可能。よって **in-memory の値スナップショットは確実に成立**。on-disk は Map/`Util.Json.Json`/`Prng.State` の serde 可否のみが残課題（S8 の将来課題）。
- **Tier 2（effect DSL ノードエディタ）への足場**: human projector のイベント行・状態レーンの `cmdKey`/`eventToCmds` ラベルは将来ノードが生成する効果と同じ語彙。タイムラインが「ノード発火→SimEvent」対応表の receiver になり得る。decision サイドカーの注釈表も同方向の足場。
- **ライブハイライト（provenance）**: タイムラインの event index がアンカー。後日 `SimEvent` に source タグを足す／並走 index 表を持たせると同じ表示モデルでライブ拡張できる。本計画は event を index 参照で扱い payload を破壊変更しない＝provenance non-breaking を保つ。
- **可視化増分 5**（debug Scene）は `syncTreeFromWorld :1362` 経由で、§A cutover 後に live combat と同 render 経路を共有できる。

---

### Critical Files for Implementation

> **anchors-as-of `cc9e6ad`; `def 名` が authoritative・`:NNN` は二次補助**（World/Combat churn 時は def 名で再 grep）。

- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/ecs/World.flix （`applyEventToWorld` :696 / `eventToCmds` :716 / `eventEntity` :734（ViewFx→None）/ `cmdKey` :779（SetProgress→"Progress"・toUid(ref)）/ `SimEvent` enum :464 = **ToString/Eq 非派生（derive 句なし）**・`Lifesteal(EntityRef,{newHp,amt})` :469 / 射影アクセサ :558,:820,:828,:853,:1013,:1114,:1300 / **サイドカー入力再構築** `equippedRingOf` :948・`combatViewOf` :980（共に pub）/ `syncFromScene` :172 / `empty()` :123・`rng = Prng.seed(0i64)` :144 / record は plain data・Scene 非保持 :32-120）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/ecs/systems/CombatSystem.flix （`resolveAttack` :181（pub）/ `resolveEnemyAttack` :261（pub・role 反転反撃）/ **`combatOutcome` :101 = private `def`**・**返り型 `type alias Outcome` :58 = private**（pub def 化時の alias 可視性ゲート）/ `Outcome = {dmg,newHp,killed,isCrit}` :58・`isCrit = finisherFired or crit` :115＝finisher と crit を混ぜ finisher +dmg フィールドなし / finisher 分岐 :104-115（サイドカーが小複製する範囲）/ `lifestealEvents` :120（`Lifesteal{newHp,amt}` :124-125）・`expEvents` :144 も private / `applyAll` :61 / draw 順 hit→crit→thief :187-198（`isHit(strike#hit,hitRoll)` :191・`combatOutcome(...,critRoll)` :194・`_thiefRoll` :198）/ 撃破 emit `Damaged(newHp=0)::Dying::ViewFx(Died)` :208-210＝Dying が権威 kill 信号 / 実 emit 順 coreAll :219-224）
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/ecs/rules/Combat.flix + CombatRules.flix + /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/src/catalog/Ring.flix （サイドカーが再評価で呼ぶ pub ルール: `CombatRules.resolveStrike` :14＝`{hit,dmg,newHp,killed,crit}` / `Combat.isHit` :79 / `isCrit` :98 / `applyCrit` :103 / `applyFinisher` :112（ring-finisher delta 算出元）/ `heal` :133 / `battleExp` :301 / **Ring**: `lifestealAmount` :127 / `finisherThreshold` :138 / `finisherTriggers` :143（いずれも pub・catalog/Ring.flix））
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/test/ecs/TestGoldenTrace.flix （`driveResolve` :107 / 撃破 golden literal `("SetHp",1000001,0,0)`/`("Dying",1000001,0,0)`/`("Progress",0,2,34)` :243-249 / `killProj` :288 / fixture シグネチャ `player(exp,hp,atkTarget,weaponHit)` :37・`enemy(id,hp,gridPos,isDying,atkTarget,rule,weaponHit)` :64・`fxWeapon hit=200=常時命中` :102-103・命中ダメージ4 :35 / counter 原型 `testResolveCounterChainEqualsLegacy` :936（fixture `player(0,4,Some(1),200)`=**exp0/hp4/atkTarget Some(1)/weaponHit200**・`enemy(1,10,...,200)`=**hp10/weaponHit200** :937・敵 hp10>dmg4 ゆえ survive :931・role 反転 :965-968・反撃が hp4 の味方を撃破 :934・oracle `proj` :976-979））
- /Users/abab/Desktop/flix_game_engine/examples/fe_rogue/test/scenes/TestUnitFixtures.flix （`withSeededRng` :432＝seed はハーネス `wref = seedRng(seed, World.empty())` :434 専用で System `world#rng` に届かない根拠 / `withRecordedRolls` :444＝サイドカーの draw 列順序込み記録の素 / `withTracedWorld` :591）

補助参照: src/ecs/systems/StaffSystem.flix（`resolveStaffCast(world,caster,effect,dir,hit)` :32＝effect-free・seed なし）、src/scenes/ViewReplay.flix（`plan` :33・落とすイベント・`ViewAction with ToString`）、src/Main.flix（`Fs.FileRead/FileWrite.runWithIO`/`Math.Random.runWithIO` install :7-9・`getArgs`/`stdin` 非 install＝§4.5 入力 IO 未接地の根拠）、src/game/Game.flix:1053-1119（`println` debug-diff 現存＝stdout 出力は実証済み・`dumpAt` の床根拠）、src/ecs/Prng.flix（`State(Int64)` :22・`rawState` :28）、src/sim/（新規モジュールの住所）。