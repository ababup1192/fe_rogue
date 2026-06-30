// World — ハイブリッド ECS 化の足場（S0）＋ statuses store（S1a）
//
// シミュレーション状態を寄せていく不変 World。S0 で id 集合＋tick を scene→World mirror した上に、
// S1a で最初の本物の component store「statuses（時限効果）」を足す。player/enemy は id 空間が別なので
// store も faction 別に持つ（衝突回避＝S0 の playerIds/enemyIds と同じ方針）。
//
// S1a は **非破壊**: statuses も scene から mirror するだけで、既存の読み書き（combatView/tick）は
// scene の Data#statuses のまま。World は描画にもロジックにも影響しない（gameLoop の末尾再帰に thread）。
// S1b で読み書きを 1 箇所ずつ World 由来に切替（parallel-run で一致検証してから）。
// tickStatusEffects は S1b で使う System（StatusSystem.tick を再利用）。S1a では定義＋テストのみ。
// 道標: ルート ECS_WORKFLOW.md（§D S1）。

/// F2（turn FSM を World へ）: sim としての「誰のターンか」を表す 3-case の phase。
/// 現 19-case `TurnPhase.Phase`（メニュー遷移・演出待ち混在）は **sim-phase(これ) ＋ UiState.modalMode** に分解する。
/// World が TurnPhase.Phase を直接持つと循環依存（TurnPhase→World.Command）になるので、World 側はこの中立な
/// 3-case を持ち、19→3 の写像は境界（Game.flix `simPhaseOf`）で行う。
pub enum SimPhase with Eq, ToString {
    case PlayerTurn   // 味方ターン（カーソル/移動/メニュー/演出待ち = UiState.modalMode と anim-queue で細分）
    case EnemyTurn    // 敵ターン
    case GameOver     // 全滅モーダル
}

// S-A0: combatView の base 戦闘値型 `BaseStats` と組立 `assembleView` は `Combat`（ecs/rules）に集約。
// World はそれを read-model として格納し（`baseStats`）、`combatViewOf` で `Combat.assembleView` を呼ぶ。

/// S-A0d: level-up 成長を World だけで解くための read-model（player-only・resource 由来）。
/// `base` = 現 resource の基準 9 ステータス（`LevelSystem.statsOf`）、`rates` = 成長率、`name` = 表示名
/// （LeveledUp の view パネル Result 用）。spike が「level-up は resource を要する」gap を露出したのを埋める
/// ＝resolveCombat の level-up を World 完結に（resource threading 不要）。
pub type alias Growth = {base = LevelSystem.Stats, rates = UnitCatalog.GrowthRates, name = String}

pub enum World {
    case World({ tick = Int32,
                 // F2a: turn FSM の World mirror（dual・read-model）。権威は当面 TurnPhase.State。
                 turnPhase = SimPhase,
                 playerIds = Set[EntityId], enemyIds  = Set[EntityId],
                 // A'（faction タグ component）: unified-id → `Faction` enum。faction 判定は id 演算（uid>=base）
                 // でなく **この enum タグ `teamOf` で読む**（Bevy の Team component 相当）。
                 team = Map[EntityId, Faction],
                 // A': statusEffects も単一 store（unified-id）。read-model（refreshMirror で scene 再 mirror）。
                 statusEffects = Map[EntityId, StatusSystem.StatusEffects],
                 // S2: hp の read-model mirror（権威は scene のまま。query/セーブ/決定論テスト用）。
                 // A'（store 統合）: hp は単一 store（player uid=id / enemy uid=id+base）。faction 別 split を撤廃。
                 hp = Map[EntityId, Int32],
                 // D3: weapons の command-derive store（hp 同型・preserve+prune）。player は weapons(List)
                 // をそのまま、enemy は単数 weapon(Option) を 0/1 要素 List に射影。reader flip はしない
                 // （combatView/unitView は scene #weapons を読む）＝挙動不変。全 weapon 書込が `Cmd.SetWeapons`
                 // を dual-write し `[WEAPONS DIFF]` で完備性を検証可能にする。
                 weapons = Map[EntityId, List[UnitCatalog.WeaponResource]],
                 // D4: staves/consumables/rings の command-derive store（weapons 同型・player-only・preserve+prune）。
                 // 敵は杖/薬/指輪インベントリを持たない（EnemyData に該当 field なし）ので store も player id keyed。
                 // reader flip はしない（各メニューは scene #staves/#consumables/#rings を読む）＝挙動不変。
                 // 全 staves/consumables/rings 書込が `Cmd.SetStaves/SetConsumables/SetRings` を dual-write し
                 // `[STAVES/CONSUMABLES/RINGS DIFF]` で完備性を検証可能にする。
                 staves = Map[EntityId, List[Staff.StaffResource]],
                 consumables = Map[EntityId, List[Consumable.ConsumableResource]],
                 rings = Map[EntityId, List[Ring.RingResource]],
                 // D4: ringEquipped の command-derive Bool store（waited 同型・player-only）。装備指輪の効果発動フラグ。
                 ringEquipped = Map[EntityId, Bool],
                 // S3: gridPos の read-model mirror。型は Vec2i の structural record（engine_core.Vec2i の演算 API 対象）。
                 // 権威は scene のまま。S4 で Board を fromWorld 化する時の World 側位置ソース候補（mirror）。
                 // A': pos は単一 store（unified-id）。両 faction の split を撤廃。
                 pos = Map[EntityId, {x = Int32, y = Int32}],
                 // B/m2: 連続的な描画位置（pixel・tween 込み）。render System(renderUnits)が読む。command-derive。
                 //   静止時は最後の値（セル pixel）を保持。move で moveAnim が補間更新（stepWorld）。
                 renderPos = Map[EntityId, Vec2.Vec2],
                 // B/m2: 進行中の移動アニメ。stepWorld が毎 tick elapsed++ し renderPos を lerp。完了で除去。
                 moveAnim = Map[EntityId, {srcPos = Vec2.Vec2, dstPos = Vec2.Vec2, elapsed = Int32, duration = Int32}],
                 // S4: 盤面除外（集合・階段退場）中の味方 id。Board.pieces は hidden 味方を除くので fromWorld に必要。
                 playerHidden = Set[EntityId],
                 // F7-spike: 敵の検知フラグ（dormant→chase）。flag→World の最初のプローブ。
                 enemyAlerted = Map[EntityId, Bool],
                 // S5: 敵の行動済みフラグ（ターン flow・view 灰色の権威）。enemy-only。faction-blind tick の前提。
                 enemyActed = Map[EntityId, Bool],
                 // 軸1 仕上げ: 死亡演出中の敵 id（death_blink 中＝全 LOGIC から除外される sim フラグ）。
                 // present=isDying。death 完了でノード除去→refreshMirror が prune（absence=非 dying）。
                 enemyDying = Set[EntityId],
                 // F7-slice2: 敵の瓶使用済みフラグ（1ターン1投の sticky）。
                 enemyBottleUsed = Map[EntityId, Bool],
                 // F7-slice3: 敵の直前位置（wander の戻り防止）。None=未移動はマップ非在で表現。
                 enemyPrevPos = Map[EntityId, {x = Int32, y = Int32}],
                 // F7-slice4: followUp 使用済み（1 攻撃 1 追撃の per-turn transient）。両 faction。
                 // A': followUpUsed は単一 store（unified-id）。両 faction の split を撤廃。
                 followUpUsed = Map[EntityId, Bool],
                 // F7-slice5: 味方の行動済み（ターン flow の権威）。player-only。reader flip は F8 で。
                 playerWaited = Map[EntityId, Bool],
                 // S5: 味方の階段退場フラグ（フロア終了条件・tick gating の権威）。player-only。reader flip は後続。
                 playerUsedStairs = Map[EntityId, Bool],
                 // F8-slice1: 攻撃対象 id（攻撃モーション中＝anyAttacking の権威）。None=非攻撃はマップ非在。両 faction。
                 // A': attackTarget は単一 store（unified-id）。両 faction の split を撤廃。
                 attackTarget = Map[EntityId, Int32],
                 // World 拡張: 味方の進行度（level/exp）。combat の撃破→exp→level-up が動かす sim 状態。
                 // 過去に level-up の hp 増分 dual-write が漏れた領域＝検証器で同種漏れを捕える。player-only。
                 playerLevel = Map[EntityId, Int32], playerExp = Map[EntityId, Int32],
                 // S-A0: base 戦闘値 + maxHp の read-model（unified-id・両 faction）。resource 由来ゆえ
                 // refreshMirror で毎フレーム scene から再 mirror（statusEffects と同型）。combatView flip 用。
                 baseStats = Map[EntityId, Combat.BaseStats],
                 // S-A0b: 装備武器の戦闘投影 read-model（unified-id・両 faction）。内側 Option=武器なし。
                 // PlayerScene/EnemyScene.equippedWeaponView 由来ゆえ毎フレーム再 mirror。combatView flip 用。
                 weaponView = Map[EntityId, Option[Combat.WeaponView]],
                 // S-A0c: 装備指輪ボーナス read-model（unified-id・両 faction）。未装備は zeroBonuses。
                 // equippedRingBonus 由来ゆえ毎フレーム再 mirror。combatView flip 用。
                 ringBonus = Map[EntityId, Ring.Bonuses],
                 // S2.5: 基礎移動力 moveTiles の store（unified-id・両 faction）。resource 由来で spawn 後不変＝
                 // 実効移動力は effectiveMoveTilesOf が encumbrance を読み時計算（base のみ保持）。
                 moveTiles = Map[EntityId, Int32],
                 // P1a（resolveCombat sim）: 装備指輪リソース本体の read-model（unified-id・両 faction）。
                 // ringBonus はステ補正だけを持つが、finisher/lifesteal は RingResource（effect/power）を要する。
                 // weaponView と同じ Option-store パターン（内側 Option=未装備）＝毎フレーム再 mirror。
                 equippedRing = Map[EntityId, Option[Ring.RingResource]],
                 // S-A0d（spike が露出した gap）: level-up 成長に要る resource 由来データ（基準 Stats + 成長率）。
                 // player-only・resource 由来ゆえ毎フレーム再 mirror。resolveCombat の level-up を World 完結に。
                 growth = Map[EntityId, Growth],
                 // P1c（resolveCombat sim）: 静的地形スナップショット（プレーンな type-alias＝storable）。
                 // ノックバックの着地計算が要する `boardOf` の地形ソース。empty()=None（シーン未確定）。
                 // syncFromScene/refreshMirror で `BoardSnapshot.mapSnapshotOf(scene)` を再 mirror（toBoard と同源）。
                 mapSnapshot = Option[MapSnapshot],
                 // P2（resolveCombat sim・敵のみ）: 敵特殊能力 effectRule の生 Json read-model（unified-id）。
                 // 内側 Option=ルールなし。enemy `#resource#effectRule`（Option[Json]）由来＝weaponView と同じ
                 // Option-store パターン（accessor が flatten）＝毎フレーム再 mirror。敵パスの sim 発火判定が読む。
                 effectRule = Map[EntityId, Option[Util.Json.Json]],
                 // F8-slice2: 敵ターン driver が読む phase-banner 同期 bool（TopBar が毎フレーム dual-write）。
                 //   enemyTurnBusy      — 敵ターン開始 intro の hold 中（>0）＝敵の行動開始待ち。
                 //   phaseObservedEnemy — 上部バーが「敵ターン」を観測済み（0 体ターンの取りこぼし防止）。
                 // どちらも view-timing 由来だが driver の順序非依存化のため World 経由で読む（生アニメ Data は TopBar 残置）。
                 enemyTurnBusy = Bool, phaseObservedEnemy = Bool,
                 // slice `rng-world`: 決定論的 PRNG 状態。live パスでは DORMANT（live ハンドラは
                 // Math.Random に delegate し w#rng を進めない）。両 sync パスで verbatim carry し、
                 // seeded PRNG を行使するのは test / trace ハーネスのみ。
                 rng = Prng.State })
}

mod World {

    pub def empty(): World =
        World.World({tick = 0, turnPhase = SimPhase.PlayerTurn,
                     playerIds = Set.empty(), enemyIds = Set.empty(),
                     statusEffects = Map.empty(),
                     hp = Map.empty(), weapons = Map.empty(), team = Map.empty(),
                     staves = Map.empty(), consumables = Map.empty(), rings = Map.empty(),
                     ringEquipped = Map.empty(),
                     pos = Map.empty(),
                     renderPos = Map.empty(), moveAnim = Map.empty(),
                     playerHidden = Set.empty(), enemyAlerted = Map.empty(), enemyActed = Map.empty(),
                     enemyDying = Set.empty(),
                     enemyBottleUsed = Map.empty(), enemyPrevPos = Map.empty(),
                     followUpUsed = Map.empty(),
                     playerWaited = Map.empty(),
                     playerUsedStairs = Map.empty(),
                     attackTarget = Map.empty(),
                     playerLevel = Map.empty(), playerExp = Map.empty(),
                     baseStats = Map.empty(), weaponView = Map.empty(), ringBonus = Map.empty(),
                     moveTiles = Map.empty(),
                     equippedRing = Map.empty(),
                     growth = Map.empty(),
                     mapSnapshot = None,
                     effectRule = Map.empty(),
                     enemyTurnBusy = false, phaseObservedEnemy = false,
                     rng = Prng.seed(0i64)})

    /// F2a: World の turnPhase を読む（read-model アクセサ）。
    pub def turnPhaseOf(world: World): SimPhase =
        let World.World(w) = world; w#turnPhase

    /// F2a: turnPhase を World へ mirror（dual・no-op）。gameLoop が TurnPhase.State → SimPhase 写像後に呼ぶ。
    pub def mirrorTurnPhase(phase: SimPhase, world: World): World =
        let World.World(w) = world; World.World({turnPhase = phase | w})

    /// scene→World の一方向 sync（純粋・読み取りのみ）。tick を 1 進め、id 集合と statuses を scene から写す。
    /// PlayerScene.getAll / EnemyScene.getAll（既存・純粋）を再利用（新規走査は書かない）。
    /// F8-slice1: attackTargetId(Option) を持つ unit list を `Map[id, target]`（None は非在）に畳む。
    /// row-poly で Player/Enemy Data 両対応。
    def attackTargetMap(uidOf: Int32 -> EntityId, units: List[{id = Int32, attackTargetId = Option[Int32] | r}]): Map[EntityId, Int32] =
        List.foldLeft((m, d) -> match d#attackTargetId {
            case Some(t) => Map.insert(uidOf(d#id), t, m)
            case None    => m
        }, Map.empty(), units)

    /// P1c: scene に Map ノードがあれば地形 snapshot を取り、無ければ None（`BoardSnapshot.mapSnapshotOf` /
    /// `MapScene.getMapLayer` は Map 不在で `bug!` する＝map-less な最小 scene でも安全に sync するためのガード）。
    def mapSnapshotOpt(scene: Scene[NodeTag]): Option[MapSnapshot] =
        match Scene.getEngineNode(MapScene.mapPath(), scene) {
            case Some(_) => Some(BoardSnapshot.mapSnapshotOf(scene))
            case None    => None
        }

    pub def syncFromScene(scene: Scene[NodeTag], world: World): World =
        let World.World(w) = world;
        let players = PlayerScene.getAll(scene);
        let enemies = EnemyScene.getAll(scene);
        World.World({
            tick           = w#tick + 1,
            turnPhase      = w#turnPhase,   // F2a: mirror は gameLoop が行う・ここは保持
            playerIds      = Query.tagOf(d -> d#id, players),
            enemyIds       = Query.tagOf(d -> d#id, enemies),
            team           = teamTags(players, enemies),
            statusEffects = Map.union(Query.indexBy(d -> d#id, d -> d#statuses, players),
                                      Query.indexBy(d -> enemyUid(d#id), d -> d#statuses, enemies)),
            hp = Map.union(Query.indexBy(d -> d#id, d -> d#hp, players),
                           Query.indexBy(d -> d#id + enemyUidBase(), d -> d#hp, enemies)),
            // D3: weapons は frame-1 初期 world のみ scene から mirror（以後は command 由来を保持）。
            // player は weapons(List) をそのまま、enemy は単数 weapon(Option) を Option.toList で 0/1 List に射影。
            weapons = Map.union(Query.indexBy(d -> d#id, d -> d#weapons, players),
                                Query.indexBy(d -> enemyUid(d#id), d -> Option.toList(d#weapon), enemies)),
            // D4: staves/consumables/rings/ringEquipped は frame-1 初期 world のみ scene から mirror（player-only）。
            staves      = Query.indexBy(d -> d#id, d -> d#staves, players),
            consumables = Query.indexBy(d -> d#id, d -> d#consumables, players),
            rings       = Query.indexBy(d -> d#id, d -> d#rings, players),
            ringEquipped = Query.indexBy(d -> d#id, d -> d#ringEquipped, players),
            pos = Map.union(Query.indexBy(d -> d#id, d -> d#gridPos, players),
                            Query.indexBy(d -> enemyUid(d#id), d -> d#gridPos, enemies)),
            renderPos = Map.empty(), moveAnim = Map.empty(),  // B/m2: World-native（spawn の SetRenderPos で seed）
            playerHidden   = Query.tagOf(d -> d#id, List.filter(d -> d#hidden, players)),
            enemyDying     = Query.tagOf(d -> enemyUid(d#id), List.filter(d -> d#isDying, enemies)),
            enemyAlerted   = Query.indexBy(d -> enemyUid(d#id), d -> d#alerted, enemies),
            enemyActed     = Query.indexBy(d -> enemyUid(d#id), d -> d#acted, enemies),
            enemyBottleUsed = Query.indexBy(d -> enemyUid(d#id), d -> d#bottleUsed, enemies),
            enemyPrevPos   = List.foldLeft((m, d) -> match d#prevPos {
                                 case Some(p) => Map.insert(enemyUid(d#id), p, m)
                                 case None    => m
                             }, Map.empty(), enemies),
            followUpUsed = Map.union(Query.indexBy(d -> d#id, d -> d#followUpUsed, players),
                                     Query.indexBy(d -> enemyUid(d#id), d -> d#followUpUsed, enemies)),
            playerWaited   = Query.indexBy(d -> d#id, d -> d#waited, players),
            playerUsedStairs = Query.indexBy(d -> d#id, d -> d#usedStairs, players),
            playerLevel    = Query.indexBy(d -> d#id, d -> d#level, players),
            playerExp      = Query.indexBy(d -> d#id, d -> d#exp, players),
            baseStats = Map.union(Query.indexBy(d -> d#id, d -> Combat.baseStatsFrom(d#resource), players),
                                  Query.indexBy(d -> enemyUid(d#id), d -> Combat.baseStatsFrom(d#resource), enemies)),
            weaponView = Map.union(Query.indexBy(d -> d#id, d -> PlayerScene.equippedWeaponView(d), players),
                                   Query.indexBy(d -> enemyUid(d#id), d -> EnemyScene.equippedWeaponView(d), enemies)),
            ringBonus = Map.union(Query.indexBy(d -> d#id, d -> PlayerScene.equippedRingBonus(d), players),
                                  Query.indexBy(d -> enemyUid(d#id), d -> EnemyScene.equippedRingBonus(d), enemies)),
            // S2.5: moveTiles も scene Data から frame-1 seed（base のみ・両 faction）。
            moveTiles = Map.union(Query.indexBy(d -> d#id, d -> d#moveTiles, players),
                                  Query.indexBy(d -> enemyUid(d#id), d -> d#moveTiles, enemies)),
            // P1a: equippedRing も装備指輪由来の read-model（内側 Option=未装備）＝ringBonus と同源で再 mirror。
            equippedRing = Map.union(Query.indexBy(d -> d#id, d -> PlayerData.equippedRing(d), players),
                                     Query.indexBy(d -> enemyUid(d#id), d -> d#ring, enemies)),
            // S-A0d: growth は player-only・resource 由来 read-model（毎フレーム再 mirror）。
            growth = Query.indexBy(d -> d#id,
                        d -> ({base = LevelSystem.statsOf(d#resource), rates = d#resource#growthRates, name = d#resource#description}: Growth), players),
            // P1c: mapSnapshot は scene 静的地形（toBoard が借りるのと同源）を毎フレーム再 mirror。
            mapSnapshot = mapSnapshotOpt(scene),
            // P2: effectRule は敵 resource 由来の read-model（敵のみ・内側 Option=ルールなし）＝毎フレーム再 mirror。
            effectRule = Query.indexBy(d -> enemyUid(d#id), d -> d#resource#effectRule, enemies),
            attackTarget = Map.union(attackTargetMap(id -> id, players),
                                     attackTargetMap(enemyUid, enemies)),
            // F8-slice2: scene に mirror 元がない scalar bool は前 world の値を保持（command 由来）。
            enemyTurnBusy      = w#enemyTurnBusy,
            phaseObservedEnemy = w#phaseObservedEnemy,
            // slice `rng-world`: PRNG 状態は scene mirror 元なし＝前 world を verbatim carry
            // （さもないと毎フレーム seed が silently reset される）。
            rng                = w#rng
        })

    /// P3（mirror 撤去・§A payoff）: per-frame の World 更新。**位置(playerPos/enemyPos)は
    /// `Cmd.Move` のみ由来**＝scene gridPos から再構築せず `world` の値を保持し、scene に居なくなった
    /// id（死亡/階段退場で scene から除去）だけ prune する（ghost piece 防止）。
    /// hp/statusEffects/hidden/ids は read-model のまま scene から毎フレーム mirror（§A 採用戦略：位置だけ World 権威）。
    /// 初期 seed と床移動/復活/中断再開の reseed は spawn funnel（addOnePlayer/addOneEnemy）の `Cmd.Move` emit が担う
    /// （いずれも World.Command handler スコープ内で走るため worldRef が seed される）。
    /// `syncFromScene`（gridPos を読む版）は frame-1 初期 world（Game.start）専用に残す。
    pub def refreshMirror(scene: Scene[NodeTag], world: World): World =
        let World.World(w) = world;
        let players = PlayerScene.getAll(scene);
        let enemies = EnemyScene.getAll(scene);
        let pIds = Query.tagOf(d -> d#id, players);
        let eIds = Query.tagOf(d -> d#id, enemies);
        // A': unified-id 全体の生存集合。store prune は id 演算でなくこの集合で行う（faction 判断不要）。
        let validUids = Set.union(pIds, Set.map(id -> enemyUid(id), eIds));
        World.World({
            tick           = w#tick + 1,
            turnPhase      = w#turnPhase,   // F2a: mirror は gameLoop が行う・ここは保持
            playerIds      = pIds,
            enemyIds       = eIds,
            team           = teamTags(players, enemies),  // A': faction タグを毎フレーム再導出
            // S3: statusEffects も command 由来を保持＋prune（hp/baseStats と同型・再 mirror しない）。全 statuses 書込
            // （add/clearImmobilized/bind/tick）が `Cmd.Seed`（emitStatusesFromScene・全置換）を dual-write 済みゆえ
            // World statusEffects == scene #statuses（[STATUSEFFECTS DIFF] 無音）。これで combatViewOf が読む
            // statusEffectsOf は非 stale（S4.2 の前提）。syncFromScene(frame-1) は seed として残す。
            statusEffects = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#statusEffects),
            // F6b: hp も command 由来を保持＋prune（位置と同様）。全 hp 書込が `Cmd.SetHp` を dual-write
            // 済み（`[F6 HP DIFF]` 無音で確認）ゆえ World hp == scene hp で挙動不変。これで **hp は World 権威**。
            hp = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#hp),
            // D3: weapons も command 由来を保持＋prune（hp と同型・再 mirror しない）。全 weapon 書込が
            // `Cmd.SetWeapons` を dual-write 済みなら World weapons == scene weapons（[WEAPONS DIFF] 無音）。
            weapons = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#weapons),
            // D4: staves/consumables/rings/ringEquipped も command 由来を保持＋prune（player-only ＝ pIds で）。
            staves      = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#staves),
            consumables = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#consumables),
            rings       = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#rings),
            ringEquipped = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#ringEquipped),
            // 位置は command 由来を保持＋scene に居ない id を prune（gridPos からの再構築はしない）。
            pos = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#pos),
            // B/m2: renderPos/moveAnim は command-derive＝preserve＋prune（再 mirror しない）。
            renderPos = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#renderPos),
            moveAnim  = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#moveAnim),
            playerHidden   = Query.tagOf(d -> d#id, List.filter(d -> d#hidden, players)),
            // 軸1 仕上げ: isDying も command 由来を保持＋prune（death 完了でノード除去→自動 prune）。
            // A': enemy-only store も unified-id key＝prune は validUids で統一。
            enemyDying     = Set.filter(uid -> Set.memberOf(uid, validUids), w#enemyDying),
            enemyAlerted   = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#enemyAlerted),
            enemyActed     = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#enemyActed),
            enemyBottleUsed = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#enemyBottleUsed),
            enemyPrevPos   = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#enemyPrevPos),
            followUpUsed = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#followUpUsed),
            playerWaited   = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerWaited),
            playerUsedStairs = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerUsedStairs),
            // World 拡張: level/exp も command 由来を保持＋prune（hp と同型）。
            playerLevel    = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerLevel),
            playerExp      = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerExp),
            // S2.3: baseStats も command 由来を保持＋prune（hp/weapons と同型・再 mirror しない）。全 resource 書込
            // （spawn/復元/carry/level-up/maxHp）が `Cmd.SetBaseStats` を dual-write 済みゆえ World baseStats == scene
            // baseStatsFrom(resource)（[BASESTATS DIFF] 無音）。combatViewOf flip(S4.2) で mid-combat の 1 フレーム stale を解消。
            baseStats = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#baseStats),
            // S2.4: weaponView も command 由来を保持＋prune（baseStats と同型・再 mirror しない）。weapons が変わる全
            // サイト（spawn/carry/復元/装備並べ替え/拾得/耐久消費）が `Cmd.SetWeaponView` を dual-write 済みゆえ World
            // weaponView == scene equippedWeaponView（[WEAPONVIEW DIFF] 無音）。
            weaponView = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#weaponView),
            // S2.4: ringBonus も command 由来を保持＋prune（baseStats と同型）。rings/ringEquipped が変わる全サイトが
            // `Cmd.SetRingBonus` を dual-write 済みゆえ World ringBonus == scene equippedRingBonus（[RINGBONUS DIFF] 無音）。
            ringBonus = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#ringBonus),
            // S2.5: moveTiles も command 由来を保持＋prune（base は spawn 後不変ゆえ stale 化しないが store 規約に合わせ preserve）。
            moveTiles = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#moveTiles),
            // P1a: equippedRing も装備指輪由来の read-model ＝ ringBonus と同源で毎フレーム再 mirror。
            equippedRing = Map.union(Query.indexBy(d -> d#id, d -> PlayerData.equippedRing(d), players),
                                     Query.indexBy(d -> enemyUid(d#id), d -> d#ring, enemies)),
            // S-A0d: growth も player-only・resource 由来 read-model ＝ 毎フレーム再 mirror。
            growth = Query.indexBy(d -> d#id,
                        d -> ({base = LevelSystem.statsOf(d#resource), rates = d#resource#growthRates, name = d#resource#description}: Growth), players),
            // P1c: mapSnapshot も scene 静的地形を毎フレーム再 mirror（toBoard と同源）。
            mapSnapshot = mapSnapshotOpt(scene),
            // P2: effectRule も敵 resource 由来 read-model（敵のみ）＝毎フレーム再 mirror。
            effectRule = Query.indexBy(d -> enemyUid(d#id), d -> d#resource#effectRule, enemies),
            attackTarget = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#attackTarget),
            // F8-slice2: scalar bool は command 由来を保持（scene mirror 元なし・TopBar が毎フレーム dual-write）。
            enemyTurnBusy      = w#enemyTurnBusy,
            phaseObservedEnemy = w#phaseObservedEnemy,
            // slice `rng-world`: PRNG 状態を verbatim carry（refreshMirror も sync パス）。
            rng                = w#rng
        })

    /// statuses を 1 ターン進める System（StatusSystem.tick を再利用）。S1b でターン開始フックに繋ぐ。
    pub def tickStatusEffects(world: World): World =
        let World.World(w) = world;
        World.World({
            statusEffects = Map.map(StatusSystem.tick, w#statusEffects)
            | w
        })

    /// F0（OOP→ECS 移行の足場）: **System パイプラインの段**。gameLoop の frame-end でここに
    /// Systems（`World -> World`）を畳む。以後の System（移動 / 敵AI / 戦闘 …）はこの関数に追加していく。
    /// **S3 以後 identity**: かつてここで `tickStatusEffects` を回していたが、S3 で statusEffects が
    /// command-authoritative になり（ターン境界の `clearAllWaited`/`clearActedAll` が `StatusSystem.tick`→`Cmd.Seed`
    /// で World へ反映）、`refreshMirror` も preserve＝再 mirror しなくなった。frame-paced にここで tick すると
    /// **二重 tick**（remaining が 60/sec で減り status が数フレームで消える・combatViewOf が buff/debuff を落とす）に
    /// なるため本段は identity にする。（`tickStatusEffects` def は単体テスト用に残置。実 System はここへ足すが
    /// statusEffects は触らない＝ターン境界の Seed が唯一の権威 tick。）
    pub def stepWorld(world: World): World =
        stepMoveAnim(world)

    /// B/m2: 進行中の各 moveAnim を 1 tick 進め、renderPos を lerp 更新。完了（elapsed>=duration）で
    /// renderPos=to にスナップして anim を除去。これが「tween を World で回す」System。
    def stepMoveAnim(world: World): World =
        let World.World(w) = world;
        Map.foldLeftWithKey((acc, uid, anim) -> {
            let World.World(wa) = acc;
            let e1 = anim#elapsed + 1;
            if (e1 >= anim#duration)
                World.World({renderPos = Map.insert(uid, anim#dstPos, wa#renderPos),
                             moveAnim = Map.remove(uid, wa#moveAnim) | wa})
            else {
                let t = Int32.toFloat64(e1) / Int32.toFloat64(anim#duration);
                World.World({renderPos = Map.insert(uid, Vec2.lerp(anim#srcPos, anim#dstPos, t), wa#renderPos),
                             moveAnim = Map.insert(uid, {elapsed = e1 | anim}, wa#moveAnim) | wa})
            }
        }, world, w#moveAnim)

    // ════════════════════════════════════════════════════════════════════
    // statusEffects（時限ステータス効果＝バフ/デバフ）を World 権威にする ECS 層
    // Bevy 正対: Command 書き込み / Query 読み込み。System ロジックは StatusSystem を再利用（再実装ゼロ）。
    // 道標: plan gemini-ecs-sunny-curry.md。
    //
    // ── entity モデルの理想と現状（TODO: Option A への seam）──────────────────
    // 【理想（純 ECS / Bevy）】単一の opaque な EntityId 空間 ＋ faction を component に:
    //   `statusEffects: Map[EntityId, StatusEffects]` 1 本 ＋ `faction: Map[EntityId, Faction]`。
    //   「敵らしさ」は AI/Faction component の合成で表す（味方型/敵型の継承を作らない）。
    // 【現状】scene-tree が PlayerScene/EnemyScene の **2 つの id 名前空間**（味方 id 0 と敵 id 0 が衝突）と
    //   別レコード型（PlayerData/EnemyData）を持つため、World も faction 別ストアに割っている（暫定 mirror）。
    // 【seam（配線済み）】read = `StatusQuery.statusEffects(EntityRef)`、write の単体操作 = `Cmd.Add/ClearImmobilized/Seed(EntityRef, …)`
    //   はいずれも **EntityRef キーで faction 非依存**。内部で split ストアに触れるのは `overEntity`（単体）と
    //   `Cmd.TickPlayers/TickEnemies`（faction 一括 = ターン構造上 faction 別が本質）と `syncFromScene` の mirror だけ。
    //   よって将来 Option A（単一 `Map[EntityId,_]` ストア＋Faction component）へ寄せる時は **この World.flix 内部
    //   （overEntity・Tick・syncFromScene・enum フィールド）だけ**を直せばよく、Cmd/Query の呼び出し側は不変。
    //   id 名前空間/セーブ形式の統合は別スコープ（セーブ互換リスクが大きいため defer）。
    // ════════════════════════════════════════════════════════════════════

    /// entity の参照（faction タグ付き）。Board.Piece と同型。statusEffects アクセスのキー抽象＝
    /// 内部ストアが split（現状）でも single（Option A）でも、呼び出し側はこの ref で触れる。
    pub enum EntityRef with ToString {
        case Player(EntityId)
        case Enemy(EntityId)
    }

    /// A'（store 統合）: faction 別 id 空間を **単一 unified-id 空間**へ決定論写像する固定オフセット。
    /// Player id 0..* はそのまま、Enemy id は `+ENEMY_UID_BASE`。World は scene の mirror ゆえ毎フレーム
    /// 再導出され、save は scene 由来（faction 別 id）で不変。これで `hp/pos/...` を **単一 store**に統合でき、
    /// applyCmd/accessor の `match ref` per-store 分岐が `toUid` 1 本に畳まれる（= faction 構造の除去）。
    pub def enemyUidBase(): EntityId = 1000000

    /// enemy original id → unified id（offset 集約・将来の脱却はここ 1 箇所）。
    pub def enemyUid(id: EntityId): EntityId = id + enemyUidBase()

    /// EntityRef → unified EntityId（Player=id, Enemy=enemyUid）。
    pub def toUid(ref: EntityRef): EntityId = match ref {
        case EntityRef.Player(id) => id
        case EntityRef.Enemy(id)  => enemyUid(id)
    }

    /// Faction + id → EntityRef（faction→ref の唯一の構築点・分岐を散らさない）。
    pub def refOfSide(faction: Faction, id: EntityId): EntityRef = match faction {
        case Faction.Player => EntityRef.Player(id)
        case Faction.Enemy  => EntityRef.Enemy(id)
    }

    /// unified EntityId → EntityRef（offset の純粋な逆写像・store↔view plumbing 用）。
    /// **game logic の faction 判断は `teamOf`（enum タグ）を使う**。これは store のキー復元専用 plumbing。
    pub def uidToRef(uid: EntityId): EntityRef =
        if (uid >= enemyUidBase()) EntityRef.Enemy(uid - enemyUidBase()) else EntityRef.Player(uid)

    /// store プラミング用の純粋 faction 述語（uid のキー域から判定）。
    pub def uidIsPlayer(uid: EntityId): Bool = uid < enemyUidBase()
    pub def uidIsEnemy(uid: EntityId): Bool = uid >= enemyUidBase()

    /// A'（faction タグ）: player/enemy の unit list から `Map[uid, Faction]` を組む。
    /// player uid=id→Player, enemy uid=id+base→Enemy。syncFromScene/refreshMirror で毎フレーム再導出。
    def teamTags(players: List[{id = Int32 | p}], enemies: List[{id = Int32 | e}]): Map[EntityId, Faction] =
        let ps = List.foldLeft((m, d) -> Map.insert(d#id, Faction.Player, m), Map.empty(), players);
        List.foldLeft((m, d) -> Map.insert(d#id + enemyUidBase(), Faction.Enemy, m), ps, enemies)

    /// statusEffects への変更命令（Bevy の Commands 相当）。深い scene コードが emit し、
    /// Game.start の handler が worldRef へ即時適用する（純粋 applier 経由）。
    /// 単体操作（Add/ClearImmobilized/Seed）は **EntityRef でキー化＝faction 非依存の write seam**
    /// （内部ストアが split→single へ変わっても命令は不変）。Tick は「そのターンの faction を一括」操作
    /// なので faction 別（TickPlayers は非 usedStairs id のみ／TickEnemies は全敵）。
    /// Seed は **replace 意味論**（clear-then-set）＝StatusSystem.add のスキップ型を使わない。
    pub enum Cmd {
        case Add(EntityRef, StatusSystem.Status)
        case ClearImmobilized(EntityRef)
        case Seed(EntityRef, StatusSystem.StatusEffects)  // 再構築/復元の全置換
        case TickPlayers(List[EntityId])    // 味方ターン開始（非 usedStairs の id のみ）
        case TickEnemies                    // 敵ターン開始（全敵）
        case Move(EntityRef, {x = Int32, y = Int32})  // 位置 write（P0a・mid-frame currency）
        case SetPhase(SimPhase)             // turn phase write（F2b・TurnPhase.State handler が dual-write で emit）
        case SetHp(EntityRef, Int32)        // hp write（F6a・dual-write seam。mid-frame で敵ターン System が逐次反映する前提）
        case SetWeapons(EntityRef, List[UnitCatalog.WeaponResource])  // D3: weapons write（dual-write seam。player は List・enemy は 0/1 List 射影）
        case SetBaseStats(EntityRef, Combat.BaseStats)  // S2.3: base 戦闘値 write（hp/weapons 同型・両 faction・resource 書換ごとに dual-write）
        case SetWeaponView(EntityRef, Option[Combat.WeaponView])  // S2.4: 装備武器の戦闘投影 write（両 faction・武器なし=None・weapons 書換ごとに dual-write）
        case SetRingBonus(EntityRef, Ring.Bonuses)  // S2.4: 装備指輪ボーナス write（両 faction・rings/ringEquipped 書換ごとに dual-write）
        case SetMoveTiles(EntityRef, Int32)  // S2.5: 基礎移動力 write（両 faction・spawn で seed・以後不変）
        case SetStaves(EntityRef, List[Staff.StaffResource])               // D4: staves write（player-only・Enemy no-op）
        case SetConsumables(EntityRef, List[Consumable.ConsumableResource]) // D4: consumables write（player-only）
        case SetRings(EntityRef, List[Ring.RingResource])                  // D4: rings write（player-only）
        case SetRingEquipped(EntityRef, Bool)                              // D4: ringEquipped write（player-only・Bool）
        case SetAlerted(EntityRef, Bool)    // F7-spike: 敵検知フラグ write（Player は no-op）
        case SetActed(EntityRef, Bool)      // S5: 敵行動済みフラグ write（Player は no-op）
        case SetDying(EntityRef)            // 軸1 仕上げ: 敵を死亡演出中に（Player は no-op・clear は removal+prune）
        case SetBottleUsed(EntityRef, Bool) // F7-slice2: 敵瓶使用フラグ write（Player は no-op）
        case SetPrevPos(EntityRef, {x = Int32, y = Int32})  // F7-slice3: 敵直前位置 write（Player は no-op）
        case SetFollowUpUsed(EntityRef, Bool)  // F7-slice4: followUp 使用済み write（両 faction）
        case SetWaited(EntityRef, Bool)        // F7-slice5: 味方行動済み write（Enemy は no-op）
        case SetUsedStairs(EntityRef, Bool)    // S5: 味方階段退場 write（Enemy は no-op）
        case SetRenderPos(EntityRef, Vec2.Vec2)  // B/m2: 描画位置を直接 set（spawn seed/瞬間移動）
        case StartMove(EntityRef, Vec2.Vec2, Vec2.Vec2, Int32)  // B/m2: from→to を duration tick で補間開始
        case SetAttackTarget(EntityRef, Int32) // F8-slice1: 攻撃対象 id をセット（攻撃開始）
        case ClearAttackTarget(EntityRef)      // F8-slice1: 攻撃対象をクリア（攻撃終了）
        case SetProgress(EntityRef, Int32, Int32) // World 拡張: 味方の (level, exp) write（撃破/レベルアップ/復元で）
        case SetEnemyTurnBusy(Bool)            // F8-slice2: 敵ターン intro hold 中 bool write（TopBar dual-write）
        case SetPhaseObservedEnemy(Bool)       // F8-slice2: バーが敵ターン観測済み bool write（TopBar dual-write）
    }

    /// System が出力する sim-event（F-clock の最小骨組み・F3b 導入 → slice `simevent-algebra` で拡張）。
    /// System は World→World を即時に解き、「何が起きたか」を SimEvent として返す。
    /// VIEW はこれを再生（Tween/anim）する＝「即時 System ＋ event 再生」型の seam。
    ///
    /// ── CLOSED / EXPLICITLY-PARTITIONED event set（DESIGN SPIKE。production emitter はまだ無い）──
    /// 【sim-affecting】World 状態を動かす純粋イベント。`applyEventToWorld`（reducer）と
    ///   `eventToCmds`（adapter）が `Cmd` へ写す:
    ///   - `Moved`      → `Cmd.Move`（既出荷の move seam。唯一 production で emit されている）
    ///   - `Damaged`/`Healed`/`Lifesteal` → `Cmd.SetHp(newHp)`（newHp は absolute。差分ではない）
    ///   - `ExpGained`  → `Cmd.SetProgress(newLevel, newExp)` のみ（kill-без-levelup の bare emission 用）
    ///   - `LeveledUp`  → `Cmd.SetHp(newHp)` THEN `Cmd.SetProgress(newLevel, newExp)`
    ///                    （legacy の applyLevelUp が SetHp→SetProgress の順で emit する順序に一致）
    ///   - `Afflicted`  → `Cmd.Add(status)`（状態異常付与。StatusSystem.add 意味論で statusEffects に積む。
    ///                    enemy effectRule の spdDown 等を combat が emit する＝golden-trace fixture B が凍結する Cmd）
    ///   - `Dying`      → `Cmd.SetDying`（撃破された敵を死亡演出中(enemyDying)へ＝**world 状態変化**。
    ///                    view 演出 `ViewFx(Died)` とは別物で、こちらは sim 状態を動かす side ＝閉包に必要）
    ///   - `Released`   → `Cmd.ClearImmobilized`（かなしばり解除＝statusEffects から Immobilized 除去。
    ///                    敵の被弾/反撃で releaseBind が emit する Cmd＝golden-trace fixture B/D が凍結する）
    /// 【view-only】`ViewFx(ViewFxKind)` 1 本に集約。World 不変（reducer は identity）。
    ///   Popup/Sound/Explosion/Knockback/Thief/Died を包む。`Died` はここに居る＝**死亡演出**は VIEW 専用で、
    ///   exp 反映は `ExpGained`/`LeveledUp` の absolute 値が既に持つので double-count しない。
    ///   dying 状態への world 遷移は別途 sim-affecting な `Dying` が担う（演出と状態遷移を分離）。
    /// 【fold の OUT（イベントにしない）】control/lifecycle な Cmd（SetAttackTarget/ClearAttackTarget/
    ///   SetFollowUpUsed/SetAlerted …）は Phase C で resolveCombat が `[SimEvent]` と並べて
    ///   DIRECTLY emit する。reducer のスコープ外。**SetDying / ClearImmobilized は world を動かす**ため
    ///   ここには居ない＝上の sim-affecting（`Dying` / `Released`）に閉じている（event set は combat の
    ///   全 world-mutation を被覆＝CLOSED）。
    ///
    /// 【1 攻撃あたり複数 SetHp の順序（documented）】Damaged(enemy)→Lifesteal(player)→
    ///   WeaponLifesteal(player)。adapter は各イベントを単一 SetHp に写すので、emit 順は
    ///   イベント列の順がそのまま担保する。
    ///
    /// ⚠ これは settled な equivalence contract ではなく DESIGN SPIKE。combat の interleaving 再構成は
    ///   Phase C の仕事で golden-trace の LEGACY Cmd-stream に対して validate される（ここでは証明しない）。
    pub enum SimEvent {
        // sim-affecting
        case Moved(EntityRef, {x = Int32, y = Int32})  // entity が target へ 1 歩進んだ（from は view が現位置で持つ）
        case Damaged(EntityRef, {newHp = Int32, dmg = Int32})    // 被ダメージ後の絶対 hp（dmg は view 用の差分）
        case Healed(EntityRef, {newHp = Int32, amt = Int32})     // 回復後の絶対 hp
        case Lifesteal(EntityRef, {newHp = Int32, amt = Int32})  // 吸収後の絶対 hp（攻撃側）
        case ExpGained({entity = EntityRef, newLevel = Int32, newExp = Int32})  // 撃破のみ（レベルアップ無し）
        case LeveledUp({entity = EntityRef, newLevel = Int32, newExp = Int32,
                        newHp = Int32, grownStats = LevelSystem.Stats, result = LevelSystem.Result})
                                            // grownStats=成長後 9 stat（resource 反映用）・result は view パネル専用
        case Afflicted(EntityRef, StatusSystem.Status)  // 状態異常付与（StatusSystem.add 意味論＝Cmd.Add と同一）
        case Dying(EntityRef)     // 撃破された敵を死亡演出中(enemyDying)へ＝world 状態変化（Cmd.SetDying）。view 演出は ViewFx(Died)
        case Released(EntityRef)  // かなしばり(Immobilized)解除＝statusEffects から除去（Cmd.ClearImmobilized）
        case Alerted(EntityRef, Bool)  // 敵の検知フラグ切替（被弾で起動）＝enemyAlerted（Cmd.SetAlerted）
        // view-only（World 不変）
        case ViewFx(ViewFxKind)
    }

    /// VIEW 専用エフェクトの種類（`SimEvent.ViewFx` の payload）。World 状態を変えない演出のみ。
    /// `Died` も view-only＝撃破演出。exp 反映は `ExpGained`/`LeveledUp` の absolute 値が担う。
    pub enum ViewFxKind {
        case Popup({x = Int32, y = Int32, text = String})
        case Sound(String)
        case Explosion({x = Int32, y = Int32})
        case Knockback(EntityRef, {x = Int32, y = Int32})
        case Thief({x = Int32, y = Int32})
        case Died(EntityRef)
    }

    /// statuses 書き込み effect（Bevy Commands）。handler は Game.start（worldRef へ即時適用）。
    ///
    /// ⚠ write-back seam（emit-flip まで未配線）: handler は **worldRef** を書くが、gameLoop は末尾再帰で
    /// **threaded `world`** を使い `world1 = syncFromScene(next, world)` で statuses を毎フレーム scene から
    /// 上書きし、frame 頭 `Ref.put(world, worldRef)` で worldRef を threaded world で潰す（Game.flix）。
    /// よって現状 emit された Cmd は **同一フレーム内の Query にしか見えず次フレーム頭で消える**。
    /// 今は誰も emit せず reader も scene 由来なので無害。**emit-flip スライスでは reader を Query へ差し替えるだけでは
    /// 不可**で、同時に (a) syncFromScene の statuses 上書きを止める（refreshMirror 化）＋ (b) frame 末の threading 基点を
    /// `Ref.get(worldRef)` にする、の両方が必須（さもないとフレーム境界で statuses が黙って消える）。
    pub eff Command {
        def emit(c: Cmd): Unit
    }

    /// statusEffects 読み込み effect（Bevy Query 相当）。**EntityRef で引く＝faction 非依存の read seam**。
    /// handler は Game.start（worldRef を読む）。reader への引数注入の供給元。
    /// 名前は `StatusQuery`（engine_ecs の汎用 `Query` モジュールを mod World 内で使えるよう、衝突回避）。
    pub eff StatusQuery {
        def statusEffects(ref: EntityRef): StatusSystem.StatusEffects
    }

    /// F2c: turn phase 読み込み effect。handler は Game.start（worldRef.turnPhase を返す）。
    /// sim-phase（3-case）を読む reader を `TurnPhase.State.get()` からこれに flip する read seam。
    /// メニュー細分（19-case）を要する reader は対象外（UiState.modalMode が要る）。
    pub eff PhaseQuery {
        def phase(): SimPhase
    }

    /// F7: 現フレームの World スナップショットを読む汎用 read seam（worldRef を返す）。handler は Game.start。
    /// フラグ reader（alerted/bottleUsed/…）を scene→World に flip する共通窓口＝フラグごとに effect を増やさない。
    /// 読み手は `World.WorldQuery.get() |> World.alertedOf(ref)` の形で任意の accessor を使う。mid-frame currency
    /// あり（その frame の Cmd が反映済み worldRef を返す）＝同ターン read-after-write が正しい。
    pub eff WorldQuery {
        def get(): World
    }

    /// slice `rng-world`: 全 combat roll の単一 chokepoint。0..99 の一様乱数を 1 つ引く。
    /// live ハンドラ（Game.start）は `Math.Random` に delegate し旧 rollPercent と BODY-IDENTITY、
    /// test/trace ハーネスは `World.drawPercent`（worldRef 上の seeded Prng）で discharge する。
    /// CombatScene の `rollPercent` がこの op だけを呼ぶ＝draw 順序は呼び出し位置がそのまま決める。
    pub eff RngDraw {
        def nextPercent(): Int32
    }

    /// world 上の seeded PRNG から 0..99 を 1 つ引き、state を進めた world を返す（test/trace 用）。
    pub def drawPercent(world: World): (Int32, World) =
        let World.World(w) = world;
        let (p, st1) = Prng.nextPercent(w#rng);
        (p, World.World({rng = st1 | w}))

    /// world の PRNG を seed し直す（trace ハーネスが固定 seed で開始するため）。
    pub def seedRng(s: Int64, world: World): World =
        let World.World(w) = world; World.World({rng = Prng.seed(s) | w})

    /// world の現在の PRNG 状態を読む（multi-frame carry テスト用）。
    pub def rngOf(world: World): Prng.State =
        let World.World(w) = world; w#rng

    /// statusEffects を引く（既定 Nil＝mid-game spawn は seed 不要）。Query handler から呼ぶ。
    /// A': 単一 store。player uid=id ゆえ get(id) のまま、enemy は enemyUid(id) へ写す。
    pub def playerStatusEffectsOf(id: EntityId, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(id, Nil, w#statusEffects)
    pub def enemyStatusEffectsOf(id: EntityId, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(enemyUid(id), Nil, w#statusEffects)

    /// faction 非依存の統一アクセサ。A': 単一 store＋toUid（match arm 消失）。
    pub def statusEffectsOf(ref: EntityRef, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(toUid(ref), Nil, w#statusEffects)

    /// EntityRef の statusEffects に純粋変換 f を適用する。A': 単一 store＋toUid＝**faction 別 arm 消失**。
    def overEntity(ref: EntityRef, f: StatusSystem.StatusEffects -> StatusSystem.StatusEffects, world: World): World =
        let World.World(w) = world;
        let uid = toUid(ref);
        let cur = Map.getWithDefault(uid, Nil, w#statusEffects);
        World.World({statusEffects = Map.insert(uid, f(cur), w#statusEffects) | w})

    /// 1 命令を World へ適用する純粋 applier（Command handler の本体）。
    pub def applyCmd(cmd: Cmd, world: World): World =
        match cmd {
            case Cmd.Add(ref, s)           => overEntity(ref, xs -> StatusSystem.add(s, xs), world)
            case Cmd.ClearImmobilized(ref) => overEntity(ref, StatusSystem.clearImmobilized, world)
            case Cmd.Seed(ref, xs)         => overEntity(ref, _ -> xs, world)
            case Cmd.TickPlayers(ids) =>
                // A': 単一 store。player uid=id ゆえ id 集合をそのまま updateTagged（敵 uid は集合外で不変）。
                let World.World(w) = world;
                World.World({statusEffects = Query.updateTagged(List.toSet(ids), StatusSystem.tick, w#statusEffects) | w})
            case Cmd.TickEnemies =>
                // A': 敵 uid のエントリだけ tick（uidIsEnemy で plumbing 判定）。
                let World.World(w) = world;
                World.World({statusEffects = Map.mapWithKey((uid, s) -> if (uidIsEnemy(uid)) StatusSystem.tick(s) else s, w#statusEffects) | w})
            case Cmd.Move(ref, pos) =>
                // A': 単一 store＋toUid（match ref arm 消失）。
                let World.World(w) = world;
                World.World({pos = Map.insert(toUid(ref), pos, w#pos) | w})
            case Cmd.SetPhase(phase) =>
                let World.World(w) = world; World.World({turnPhase = phase | w})
            case Cmd.SetHp(ref, hpVal) =>
                // A': 単一 store＋toUid。faction 別 match arm 消失。
                let World.World(w) = world;
                World.World({hp = Map.insert(toUid(ref), hpVal, w#hp) | w})
            case Cmd.SetWeapons(ref, ws) =>
                // D3: 単一 store＋toUid（SetHp と同型）。
                let World.World(w) = world;
                World.World({weapons = Map.insert(toUid(ref), ws, w#weapons) | w})
            case Cmd.SetBaseStats(ref, bs) =>
                // S2.3: 単一 store＋toUid（SetHp/SetWeapons と同型・両 faction）。
                let World.World(w) = world;
                World.World({baseStats = Map.insert(toUid(ref), bs, w#baseStats) | w})
            case Cmd.SetWeaponView(ref, wv) =>
                // S2.4: 単一 store＋toUid（SetBaseStats と同型・両 faction・内側 Option=武器なし）。
                let World.World(w) = world;
                World.World({weaponView = Map.insert(toUid(ref), wv, w#weaponView) | w})
            case Cmd.SetRingBonus(ref, rb) =>
                // S2.4: 単一 store＋toUid（SetBaseStats と同型・両 faction）。
                let World.World(w) = world;
                World.World({ringBonus = Map.insert(toUid(ref), rb, w#ringBonus) | w})
            case Cmd.SetMoveTiles(ref, n) =>
                // S2.5: 単一 store＋toUid（SetBaseStats と同型・両 faction）。
                let World.World(w) = world;
                World.World({moveTiles = Map.insert(toUid(ref), n, w#moveTiles) | w})
            case Cmd.SetStaves(ref, xs) =>
                // D4: player-only store（SetWaited 流儀・Enemy は no-op）。
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({staves = Map.insert(id, xs, w#staves) | w})
                    case EntityRef.Enemy(_)   => world
                }
            case Cmd.SetConsumables(ref, xs) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({consumables = Map.insert(id, xs, w#consumables) | w})
                    case EntityRef.Enemy(_)   => world
                }
            case Cmd.SetRings(ref, xs) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({rings = Map.insert(id, xs, w#rings) | w})
                    case EntityRef.Enemy(_)   => world
                }
            case Cmd.SetRingEquipped(ref, b) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({ringEquipped = Map.insert(id, b, w#ringEquipped) | w})
                    case EntityRef.Enemy(_)   => world
                }
            case Cmd.SetAlerted(ref, a) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world   // F7-spike: 味方に alerted は無い＝no-op
                    case EntityRef.Enemy(id)  => World.World({enemyAlerted = Map.insert(enemyUid(id), a, w#enemyAlerted) | w})
                }
            case Cmd.SetActed(ref, b) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world   // S5: 味方 acted は無い＝no-op
                    case EntityRef.Enemy(id)  => World.World({enemyActed = Map.insert(enemyUid(id), b, w#enemyActed) | w})
                }
            case Cmd.SetDying(ref) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world   // 味方は hp<=0 で即除去＝isDying 無し
                    case EntityRef.Enemy(id)  => World.World({enemyDying = Set.insert(enemyUid(id), w#enemyDying) | w})
                }
            case Cmd.SetBottleUsed(ref, b) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world
                    case EntityRef.Enemy(id)  => World.World({enemyBottleUsed = Map.insert(enemyUid(id), b, w#enemyBottleUsed) | w})
                }
            case Cmd.SetPrevPos(ref, p) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world
                    case EntityRef.Enemy(id)  => World.World({enemyPrevPos = Map.insert(enemyUid(id), p, w#enemyPrevPos) | w})
                }
            case Cmd.SetFollowUpUsed(ref, f) =>
                // A': 単一 store＋toUid（match ref arm 消失）。
                let World.World(w) = world;
                World.World({followUpUsed = Map.insert(toUid(ref), f, w#followUpUsed) | w})
            case Cmd.SetWaited(ref, wd) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({playerWaited = Map.insert(id, wd, w#playerWaited) | w})
                    case EntityRef.Enemy(_)   => world   // 敵に waited は無い＝no-op
                }
            case Cmd.SetUsedStairs(ref, b) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({playerUsedStairs = Map.insert(id, b, w#playerUsedStairs) | w})
                    case EntityRef.Enemy(_)   => world   // 敵に usedStairs は無い＝no-op
                }
            case Cmd.SetRenderPos(ref, p) =>
                // B/m2: 描画位置を直接 set（進行中アニメは破棄）。spawn seed / 瞬間移動用。
                let World.World(w) = world;
                World.World({renderPos = Map.insert(toUid(ref), p, w#renderPos),
                             moveAnim = Map.remove(toUid(ref), w#moveAnim) | w})
            case Cmd.StartMove(ref, fromP, toP, dur) =>
                // B/m2: src→dst を dur tick で補間開始。renderPos は src から始める。
                let World.World(w) = world;
                let uid = toUid(ref);
                World.World({moveAnim = Map.insert(uid, {srcPos = fromP, dstPos = toP, elapsed = 0, duration = Int32.max(1, dur)}, w#moveAnim),
                             renderPos = Map.insert(uid, fromP, w#renderPos) | w})
            case Cmd.SetAttackTarget(ref, t) =>
                // A': 単一 store＋toUid（match ref arm 消失）。
                let World.World(w) = world;
                World.World({attackTarget = Map.insert(toUid(ref), t, w#attackTarget) | w})
            case Cmd.ClearAttackTarget(ref) =>
                let World.World(w) = world;
                World.World({attackTarget = Map.remove(toUid(ref), w#attackTarget) | w})
            case Cmd.SetProgress(ref, lv, xp) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) =>
                        World.World({playerLevel = Map.insert(id, lv, w#playerLevel),
                                     playerExp   = Map.insert(id, xp, w#playerExp) | w})
                    case EntityRef.Enemy(_)   => world   // 敵は level/exp 無し＝no-op
                }
            case Cmd.SetEnemyTurnBusy(b) =>
                let World.World(w) = world; World.World({enemyTurnBusy = b | w})
            case Cmd.SetPhaseObservedEnemy(b) =>
                let World.World(w) = world; World.World({phaseObservedEnemy = b | w})
        }

    // ── slice `simevent-algebra`: SimEvent reducer / adapter / cmdKey ────────────────
    //
    // PURE な value→value 層。production emitter はまだ無い（DESIGN SPIKE）。
    // `cmdKey` は golden-trace スライスが消費する比較通貨（Cmd に Eq が無いため必須）で、
    // simevent-algebra のテスト自身が `eventToCmds(...).map(cmdKey)` を assert するためここに lives。

    /// SimEvent を World へ適用する純粋 reducer（sim-affecting のみ実効・ViewFx は identity）。
    /// `applyCmd` 経由＝Cmd 適用と bit-identical。LeveledUp は SetHp→SetProgress の順で 2 段適用。
    pub def applyEventToWorld(ev: SimEvent, world: World): World =
        match ev {
            case SimEvent.Moved(ref, t)     => applyCmd(Cmd.Move(ref, t), world)
            case SimEvent.Damaged(ref, r)   => applyCmd(Cmd.SetHp(ref, r#newHp), world)
            case SimEvent.Healed(ref, r)    => applyCmd(Cmd.SetHp(ref, r#newHp), world)
            case SimEvent.Lifesteal(ref, r) => applyCmd(Cmd.SetHp(ref, r#newHp), world)
            case SimEvent.ExpGained(r)      => applyCmd(Cmd.SetProgress(r#entity, r#newLevel, r#newExp), world)
            case SimEvent.LeveledUp(r)      =>
                // legacy applyLevelUp の emit 順（SetHp@997 → SetProgress@999）に一致させる。
                applyCmd(Cmd.SetProgress(r#entity, r#newLevel, r#newExp),
                         applyCmd(Cmd.SetHp(r#entity, r#newHp), world))
            case SimEvent.Afflicted(ref, s) => applyCmd(Cmd.Add(ref, s), world)
            case SimEvent.Dying(ref)        => applyCmd(Cmd.SetDying(ref), world)
            case SimEvent.Released(ref)     => applyCmd(Cmd.ClearImmobilized(ref), world)
            case SimEvent.Alerted(ref, b)   => applyCmd(Cmd.SetAlerted(ref, b), world)
            case SimEvent.ViewFx(_)         => world
        }

    /// SimEvent → emit される Cmd 列（adapter）。`applyEventToWorld` と同じ写像を Cmd 列として返す。
    /// LeveledUp は [SetHp, SetProgress] の順。ViewFx は空。golden-trace の Cmd-stream 比較に使う。
    pub def eventToCmds(ev: SimEvent): List[Cmd] =
        match ev {
            case SimEvent.Moved(ref, t)     => Cmd.Move(ref, t) :: Nil
            case SimEvent.Damaged(ref, r)   => Cmd.SetHp(ref, r#newHp) :: Nil
            case SimEvent.Healed(ref, r)    => Cmd.SetHp(ref, r#newHp) :: Nil
            case SimEvent.Lifesteal(ref, r) => Cmd.SetHp(ref, r#newHp) :: Nil
            case SimEvent.ExpGained(r)      => Cmd.SetProgress(r#entity, r#newLevel, r#newExp) :: Nil
            case SimEvent.LeveledUp(r)      =>
                Cmd.SetHp(r#entity, r#newHp) :: Cmd.SetProgress(r#entity, r#newLevel, r#newExp) :: Nil
            case SimEvent.Afflicted(ref, s) => Cmd.Add(ref, s) :: Nil
            case SimEvent.Dying(ref)        => Cmd.SetDying(ref) :: Nil
            case SimEvent.Released(ref)     => Cmd.ClearImmobilized(ref) :: Nil
            case SimEvent.Alerted(ref, b)   => Cmd.SetAlerted(ref, b) :: Nil
            case SimEvent.ViewFx(_)         => Nil
        }

    /// SimEvent の主体 entity（SYNTACTIC な closure・semantic な Phase-C completeness ではない）。
    /// ViewFx は entity を持つもの（Knockback/Died）だけ Some。
    pub def eventEntity(ev: SimEvent): Option[EntityRef] =
        match ev {
            case SimEvent.Moved(ref, _)     => Some(ref)
            case SimEvent.Damaged(ref, _)   => Some(ref)
            case SimEvent.Healed(ref, _)    => Some(ref)
            case SimEvent.Lifesteal(ref, _) => Some(ref)
            case SimEvent.ExpGained(r)      => Some(r#entity)
            case SimEvent.LeveledUp(r)      => Some(r#entity)
            case SimEvent.Afflicted(ref, _) => Some(ref)
            case SimEvent.Dying(ref)        => Some(ref)
            case SimEvent.Released(ref)     => Some(ref)
            case SimEvent.Alerted(ref, _)   => Some(ref)
            case SimEvent.ViewFx(vk)        => match vk {
                case ViewFxKind.Knockback(ref, _) => Some(ref)
                case ViewFxKind.Died(ref)         => Some(ref)
                case ViewFxKind.Popup(_)          => None
                case ViewFxKind.Sound(_)          => None
                case ViewFxKind.Explosion(_)      => None
                case ViewFxKind.Thief(_)          => None
            }
        }

    /// Bool → 0/1（cmdKey の payload 正規化）。
    def bool01(b: Bool): Int32 = if (b) 1 else 0

    /// StatusEffect の IDENTITY ordinal（cmdKey が Add を効果種別で区別するため）。magnitude/remaining は無視。
    def statusKindToInt(e: StatusSystem.StatusEffect): Int32 = match e {
        case StatusSystem.StatusEffect.HitDown     => 0
        case StatusSystem.StatusEffect.SpdDown     => 1
        case StatusSystem.StatusEffect.AtkUp       => 2
        case StatusSystem.StatusEffect.SpdUp       => 3
        case StatusSystem.StatusEffect.DefDown     => 4
        case StatusSystem.StatusEffect.Immobilized => 5
    }

    /// SimPhase の ordinal（cmdKey の SetPhase 用）。
    def phaseToInt(p: SimPhase): Int32 = match p {
        case SimPhase.PlayerTurn => 0
        case SimPhase.EnemyTurn  => 1
        case SimPhase.GameOver   => 2
    }

    /// TOTAL な Cmd → 比較キー (tag, uid, a, b)。`Cmd` に Eq が無いため golden-trace/simevent-algebra の
    /// 唯一の比較通貨。全 19 variant 上で網羅（exhaustiveness は `flix check` が強制）。
    /// faction 非依存に `toUid` で uid 化。control/lifecycle と payload-less は tag のみで discriminating。
    pub def cmdKey(c: Cmd): (String, Int32, Int32, Int32) =
        match c {
            case Cmd.SetHp(ref, hp)           => ("SetHp", toUid(ref), hp, 0)
            case Cmd.SetWeapons(ref, ws)      => ("SetWeapons", toUid(ref), List.length(ws), 0)
            // S2.3: BaseStats は Eq 非自動ゆえ全 8 数値 field の和を digest に、maxHp を 4th に載せて oracle 可視化。
            case Cmd.SetBaseStats(ref, bs)    => ("SetBaseStats", toUid(ref),
                                                  bs#attack + bs#magicAttack + bs#defense + bs#magicDefense
                                                  + bs#skill + bs#speed + bs#luck + bs#maxHp, bs#maxHp)
            // S2.4: WeaponView は Eq 非自動・Option ゆえ attack を digest に、武器なし(None)=-1 で discriminating。
            case Cmd.SetWeaponView(ref, wv)   => ("SetWeaponView", toUid(ref),
                                                  Option.map(v -> v#attack, wv) |> Option.getWithDefault(-1), 0)
            // S2.4: Bonuses は Eq 非自動ゆえ 5 数値 field の和を digest に載せて oracle 可視化。
            case Cmd.SetRingBonus(ref, rb)    => ("SetRingBonus", toUid(ref),
                                                  rb#attack + rb#speed + rb#defense + rb#skill + rb#luck, 0)
            case Cmd.SetMoveTiles(ref, n)     => ("SetMoveTiles", toUid(ref), n, 0)
            case Cmd.SetStaves(ref, xs)       => ("SetStaves", toUid(ref), List.length(xs), 0)
            case Cmd.SetConsumables(ref, xs)  => ("SetConsumables", toUid(ref), List.length(xs), 0)
            case Cmd.SetRings(ref, xs)        => ("SetRings", toUid(ref), List.length(xs), 0)
            case Cmd.SetRingEquipped(ref, b)  => ("SetRingEquipped", toUid(ref), bool01(b), 0)
            case Cmd.Move(ref, p)             => ("Move", toUid(ref), p#x, p#y)
            case Cmd.SetProgress(ref, lv, xp) => ("Progress", toUid(ref), lv, xp)
            case Cmd.SetAttackTarget(ref, t)  => ("AtkTgt", toUid(ref), t, 0)
            case Cmd.ClearAttackTarget(ref)   => ("ClrTgt", toUid(ref), 0, 0)
            case Cmd.SetFollowUpUsed(ref, b)  => ("FollowUp", toUid(ref), bool01(b), 0)
            case Cmd.SetAlerted(ref, b)       => ("Alerted", toUid(ref), bool01(b), 0)
            case Cmd.SetActed(ref, b)         => ("Acted", toUid(ref), bool01(b), 0)
            case Cmd.SetDying(ref)            => ("Dying", toUid(ref), 0, 0)
            case Cmd.SetBottleUsed(ref, b)    => ("Bottle", toUid(ref), bool01(b), 0)
            case Cmd.SetWaited(ref, b)        => ("Waited", toUid(ref), bool01(b), 0)
            case Cmd.SetUsedStairs(ref, b)    => ("UsedStairs", toUid(ref), bool01(b), 0)
            case Cmd.SetRenderPos(ref, _)     => ("RenderPos", toUid(ref), 0, 0)
            case Cmd.StartMove(ref, _, _, dur) => ("StartMove", toUid(ref), dur, 0)
            case Cmd.SetPrevPos(ref, p)       => ("PrevPos", toUid(ref), p#x, p#y)
            case Cmd.ClearImmobilized(ref)    => ("ClrImmob", toUid(ref), 0, 0)
            // magnitude を 4th slot に載せて oracle に可視化する（kind だけだと量違いを golden が見逃す）。
            // remaining はここに載らないが golden-trace の最終 World 射影が turn-count を捕捉する。
            case Cmd.Add(ref, s)              => ("Add", toUid(ref), statusKindToInt(s#effect), s#magnitude)
            case Cmd.Seed(ref, _)             => ("Seed", toUid(ref), 0, 0)
            case Cmd.SetPhase(p)              => ("Phase", phaseToInt(p), 0, 0)
            case Cmd.TickPlayers(_)           => ("TickP", 0, 0, 0)
            case Cmd.TickEnemies              => ("TickE", 0, 0, 0)
            case Cmd.SetEnemyTurnBusy(b)      => ("ETBusy", bool01(b), 0, 0)
            case Cmd.SetPhaseObservedEnemy(b) => ("PhObs", bool01(b), 0, 0)
        }

    /// F7-spike: 敵の alerted を World から読む（reader flip の供給元・hpOf 同型）。Player は常に None。
    pub def alertedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyAlerted)
        }

    /// S5: 敵の acted を World から読む。Player は常に None。
    pub def actedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyActed)
        }

    /// 軸1 仕上げ: 敵が死亡演出中か（reader flip の供給元）。Player は常に false。
    pub def isDyingOf(ref: EntityRef, world: World): Bool =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => false
            case EntityRef.Enemy(id)  => Set.memberOf(enemyUid(id), w#enemyDying)
        }

    /// F7-slice2: 敵の bottleUsed を World から読む。Player は常に None。
    pub def bottleUsedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyBottleUsed)
        }

    /// F7-slice3: 敵の prevPos を World から読む（None=未移動＝マップ非在）。Player は常に None。
    pub def prevPosOf(ref: EntityRef, world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyPrevPos)
        }

    /// P1c: 現在位置を World の pos-store（`Cmd.Move` 権威）から読む（両 faction・unified-id）。
    /// `prevPosOf`（敵直前位置）とは別物＝現在セル。ノックバック着地計算が攻撃側/防御側セルを引くのに要る。
    pub def posOf(ref: EntityRef, world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world; Map.get(toUid(ref), w#pos)

    /// B/m2: 連続的な描画位置（pixel・tween 込み）。render System が読む。未 seed は None。
    pub def renderPosOf(ref: EntityRef, world: World): Option[{x = Float64, y = Float64}] =
        let World.World(w) = world; Map.get(toUid(ref), w#renderPos)

    /// B/m2: 当該 entity が移動アニメ中か（isMoving の World 版・input gate 用）。
    pub def isAnimating(ref: EntityRef, world: World): Bool =
        let World.World(w) = world; Map.memberOf(toUid(ref), w#moveAnim)

    /// F7-slice4: followUpUsed を World から読む（両 faction）。A': 単一 store＋toUid。
    pub def followUpUsedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world; Map.get(toUid(ref), w#followUpUsed)

    /// F7-slice5: 味方 waited を World から読む（reader flip は F8）。Enemy は常に None。
    pub def waitedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerWaited)
            case EntityRef.Enemy(_)   => None
        }

    /// S5: 味方の usedStairs を World から読む。Enemy は常に None。
    pub def usedStairsOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerUsedStairs)
            case EntityRef.Enemy(_)   => None
        }

    /// F8-slice1: attackTargetId を World から読む（None=非攻撃）。両 faction。A': 単一 store＋toUid。
    pub def attackTargetOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world; Map.get(toUid(ref), w#attackTarget)

    /// F8-slice1: いずれかの味方が攻撃中か。A': 単一 store を uid 復元（plumbing）で faction filter。
    pub def anyPlayerAttacking(world: World): Bool =
        let World.World(w) = world;
        Map.exists((uid, _) -> uidIsPlayer(uid), w#attackTarget)

    /// F8-slice1: いずれかの敵が攻撃中か。
    pub def anyEnemyAttacking(world: World): Bool =
        let World.World(w) = world;
        Map.exists((uid, _) -> uidIsEnemy(uid), w#attackTarget)

    /// S-A0: base 戦闘値 + maxHp を World から読む（unified-id・両 faction）。未登録は None。
    /// B1 で combatView がここを読み、status/ring 補正を加えて CombatView を組む（reader flip）。
    pub def baseStatsOf(ref: EntityRef, world: World): Option[Combat.BaseStats] =
        let World.World(w) = world; Map.get(toUid(ref), w#baseStats)

    // ── slice: canonical comparison keys（proj 集約・drift 防止）──────────────
    // 各検証器の inline 射影を型ごと monomorphic な named key へ集約する。複数 call site が単一 def を
    // 共有すると「片方だけ弱体化」が構造的に不能になり S2.4/S4.4 級 drift を封じる（cmdKey/boardKey 慣習の横展開）。
    // ★E7574 回避: 在庫4種は別 record 型ゆえ共有 `let`-lambda は単相化で衝突する。型ごと top-level def は
    //   generalize されるので安全。将来 `let` 共有へ戻すと value restriction で E7574 を再誘発するため戻すな。
    // ★near-duplicate 2ペアは絶対に統合しない（§1.4）:
    //   weaponViewKey(8) ≠ weaponViewCombatKey(6) / ringKey(name,power) ≠ equippedRingKey(name,effect,power)。

    /// 在庫リストの代表射影: (長さ, 先頭要素の key)。多相 HOF（各 call site で a,b を fresh instantiate）。
    /// row には触れず引数の monomorphic keyFn 内でのみ field access する＝E7574-safe（attackTargetMap 前例）。
    /// fst が常に length＝weaponsMismatches 等の (ref, worldLen, sceneLen) 診断 payload の load-bearing 要素。
    pub def headKey(xs: List[a], keyFn: a -> b \ ef): (Int32, Option[b]) \ ef =
        (List.length(xs), List.head(xs) |> Option.map(keyFn))

    /// 在庫武器の代表キー (name, durability)。weaponsMismatches / playerDataKey で共有＝drift 不能。
    /// 元 lambda: w -> (w#name, w#durability)
    pub def weaponKey(w: UnitCatalog.WeaponResource): (String, Int32) = (w#name, w#durability)

    /// 杖の代表キー (name, durability)。stavesMismatches / playerDataKey で共有。
    /// 元 lambda: s -> (s#name, s#durability)
    pub def staffKey(s: Staff.StaffResource): (String, Int32) = (s#name, s#durability)

    /// 消耗品の代表キー (name, durability)。consumablesMismatches / playerDataKey で共有。
    /// 元 lambda: c -> (c#name, c#durability)
    pub def consumableKey(c: Consumable.ConsumableResource): (String, Int32) = (c#name, c#durability)

    /// 在庫指輪の代表キー (name, power)。ringsMismatches / playerDataKey で共有。
    /// ★equippedRingKey(name,effect,power) とは別物（在庫=power 代表 / 装備=RingEffect 必須）。
    /// 元 lambda: r -> (r#name, r#power)
    pub def ringKey(r: Ring.RingResource): (String, Int32) = (r#name, r#power)

    /// BaseStats の全 8 数値 field キー（baseStatsMismatches）。
    /// 元 lambda: bs -> (bs#attack, bs#magicAttack, bs#defense, bs#magicDefense, bs#skill, bs#speed, bs#luck, bs#maxHp)
    pub def baseStatsKey(bs: Combat.BaseStats): (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) =
        (bs#attack, bs#magicAttack, bs#defense, bs#magicDefense, bs#skill, bs#speed, bs#luck, bs#maxHp)

    /// status list の順序込みキー [(effect, magnitude, remaining)]（statusEffectsMismatches / playerDataKey 共有）。
    /// 元 lambda: xs -> List.map(s -> (s#effect, s#magnitude, s#remaining), xs)
    pub def statusListKey(xs: List[StatusSystem.Status]): List[(StatusSystem.StatusEffect, Int32, Int32)] =
        List.map(s -> (s#effect, s#magnitude, s#remaining), xs)

    /// Ring.Bonuses の 5 数値 field キー（ringBonusMismatches）。
    /// 元 lambda: rb -> (rb#attack, rb#speed, rb#defense, rb#skill, rb#luck)
    pub def ringBonusKey(rb: Ring.Bonuses): (Int32, Int32, Int32, Int32, Int32) =
        (rb#attack, rb#speed, rb#defense, rb#skill, rb#luck)

    /// ★武器ミラー全体検証用 WeaponView 8 field キー（weaponViewMismatches・weaponType/effect 込み）。
    /// ★weaponViewCombatKey(6) とは別物。統合すると combatView/unitView DIFF が weaponType/effect で新たに鳴る＝意味変化。
    /// 元 lambda: v -> (v#weaponType, v#attack, v#hit, v#crit, v#isPhysical, v#proficient, v#effect, v#effectValue)
    pub def weaponViewKey(v: Combat.WeaponView):
            (WeaponCatalog.WeaponType, Int32, Int32, Int32, Bool, Bool, WeaponCatalog.WeaponEffect, Int32) =
        (v#weaponType, v#attack, v#hit, v#crit, v#isPhysical, v#proficient, v#effect, v#effectValue)

    /// ★CombatView 内蔵 weapon の戦闘 6 field キー（combatViewKey 内包・combatView/unitView 共有）。
    /// ★weaponViewKey(8) とは別物（weaponType/effect は含めない）。
    /// 元 lambda: wv -> (wv#attack, wv#hit, wv#crit, wv#isPhysical, wv#proficient, wv#effectValue)
    pub def weaponViewCombatKey(wv: Combat.WeaponView): (Int32, Int32, Int32, Bool, Bool, Int32) =
        (wv#attack, wv#hit, wv#crit, wv#isPhysical, wv#proficient, wv#effectValue)

    /// CombatView の全数値 + 内蔵 weapon 射影キー（combatViewMismatches / unitViewKey 共有）。
    /// 内蔵 weapon は weaponViewCombatKey を再利用（second source of truth を作らない）。
    /// 元 lambda: cv -> (cv#attack, cv#magicAttack, cv#defense, cv#magicDefense, cv#skill,
    ///                   cv#speed, cv#luck, cv#hp, cv#maxHp, cv#hitMod, Option.map(wvProj, cv#weapon))
    pub def combatViewKey(cv: Combat.CombatView):
            (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32,
             Option[(Int32, Int32, Int32, Bool, Bool, Int32)]) =
        (cv#attack, cv#magicAttack, cv#defense, cv#magicDefense, cv#skill,
         cv#speed, cv#luck, cv#hp, cv#maxHp, cv#hitMod,
         Option.map(weaponViewCombatKey, cv#weapon))

    /// ★装備指輪キー (name, RingEffect, power)（equippedRingMismatches）。
    /// ★ringKey(name,power) とは別物（装備指輪は finisher/lifesteal が effect を読むため effect 必須）。
    /// 元 lambda: r -> (r#name, r#effect, r#power)
    pub def equippedRingKey(r: Ring.RingResource): (String, Ring.RingEffect, Int32) =
        (r#name, r#effect, r#power)

    /// 敵 effectRule（生 Json）の ToString キー（effectRuleMismatches）。
    /// 元 lambda: j -> "${j}"
    pub def effectRuleKey(j: Util.Json.Json): String = "${j}"

    /// 位置 {x,y} のキー (x, y)。unitViewKey / playerDataKey 等の source 共有
    /// （3 source とも closed row {x=Int32,y=Int32} ゆえ monomorphic 安全・§1.2）。
    /// 元 lambda: p -> (p#x, p#y)
    pub def posKey(p: {x = Int32, y = Int32}): (Int32, Int32) = (p#x, p#y)

    /// 武器射程 {min,max} のキー (min, max)（unitViewKey）。
    /// 元 lambda: r -> (r#min, r#max)
    pub def weaponRangeKey(r: {min = Int32, max = Int32}): (Int32, Int32) = (r#min, r#max)

    /// UnitView の全 10 field キー（unitViewMismatches）。pos/weaponRange/combat は sub-key を再利用。
    /// 元 proj: uv -> (uv#id, uv#faction, (uv#pos#x, uv#pos#y), uv#hp, uv#moveTiles,
    ///                 Option.map(r -> (r#min, r#max), uv#weaponRange),
    ///                 cvProj(uv#combat), uv#isDying, uv#hidden, uv#aiType)
    pub def unitViewKey(uv: UnitView):
            (Int32, Faction, (Int32, Int32), Int32, Int32, Option[(Int32, Int32)],
             (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32,
              Option[(Int32, Int32, Int32, Bool, Bool, Int32)]),
             Bool, Bool, EnemyAI.AiType) =
        (uv#id, uv#faction, posKey(uv#pos), uv#hp, uv#moveTiles,
         Option.map(weaponRangeKey, uv#weaponRange),
         combatViewKey(uv#combat), uv#isDying, uv#hidden, uv#aiType)

    /// resource 由来 stat 11 field キー（playerDataKey 内包・resProj）。
    /// 元 lambda: r -> (r#moveTiles, r#level, r#hp, r#attack, r#defense, r#magicAttack,
    ///                  r#magicDefense, r#speed, r#skill, r#luck, r#constitution)
    pub def resourceStatKey(r: UnitCatalog.UnitResource):
            (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) =
        (r#moveTiles, r#level, r#hp, r#attack, r#defense, r#magicAttack,
         r#magicDefense, r#speed, r#skill, r#luck, r#constitution)

    /// pendingLevelUp の Option キー (unitName, fromLevel, toLevel, 変化数)（playerDataKey 内包・pluProj）。
    /// 元 lambda: Option.map(r -> (r#unitName, r#fromLevel, r#toLevel, List.length(r#changes)))
    pub def pendingLevelUpKey(o: Option[LevelSystem.Result]): Option[(String, Int32, Int32, Int32)] =
        Option.map(r -> (r#unitName, r#fromLevel, r#toLevel, List.length(r#changes)), o)

    /// ★PlayerData.Data の全 23 field キー（playerDataMismatches）。flat でなく 2段ネスト ((13),(10))
    /// （tuple arity/Eq 上限回避・§1.3）。sub-key（posKey/resourceStatKey/headKey/statusListKey/
    /// pendingLevelUpKey）を再利用＝leaf drift 不能を継承。13/10 のネスト境界は逐語複製。
    pub def playerDataKey(d: PlayerData.Data):
            ((Int32, String, (Int32, Int32), Int32, Int32, Bool, Option[Int32],
              (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32),
              (Int32, Option[(String, Int32)]),
              (Int32, Option[(String, Int32)]),
              (Int32, Option[(String, Int32)]),
              (Int32, Option[(String, Int32)]),
              Bool),
             (Option[PlayerData.ItemKind], Int32, Staff.Direction, Bool, Bool,
              Int32, Int32, Option[(String, Int32, Int32, Int32)],
              List[(StatusSystem.StatusEffect, Int32, Int32)], Bool)) =
        ((d#id, d#classId, posKey(d#gridPos), d#moveTiles, d#hp, d#waited,
          d#attackTargetId, resourceStatKey(d#resource),
          headKey(d#weapons, weaponKey),
          headKey(d#staves, staffKey),
          headKey(d#consumables, consumableKey),
          headKey(d#rings, ringKey),
          d#ringEquipped),
         (d#selectedItem, d#moveStepsTaken, d#facing, d#hidden, d#usedStairs,
          d#level, d#exp, pendingLevelUpKey(d#pendingLevelUp),
          statusListKey(d#statuses), d#followUpUsed))

    /// ★EnemyData.Data の全 17 field キー（enemyDataMismatches）。playerDataKey と同流儀の 2段ネスト
    /// ((9),(8))（tuple arity/Eq 上限回避・§1.3）。sub-key（posKey/weaponKey/equippedRingKey/statusListKey）を
    /// 既存正準キーから再利用＝leaf drift 不能を継承（S2.4/S4.4 級の重複射影 drift バグを再導入しない）。
    /// resource(R 残置)は両辺 scene 由来＝恒等一致ゆえ resourceId(String) を代表値とする。
    pub def enemyDataKey(d: EnemyData.Data):
            ((Int32, String, (Int32, Int32), Bool, Int32, Int32, Int32, Bool, Option[Int32]),
             (String, Option[(String, Int32)], Bool, Option[(Int32, Int32)],
              List[(StatusSystem.StatusEffect, Int32, Int32)],
              Option[(String, Ring.RingEffect, Int32)], Bool, Bool)) =
        ((d#id, d#resourceId, posKey(d#gridPos), d#alerted, d#homeModuleIdx,
          d#moveTiles, d#hp, d#isDying, d#attackTargetId),
         (d#resourceId, Option.map(weaponKey, d#weapon), d#acted,
          Option.map(posKey, d#prevPos), statusListKey(d#statuses),
          Option.map(equippedRingKey, d#ring), d#followUpUsed, d#bottleUsed))

    /// 地形 snapshot キー (tileSize, wallCells)（mapSnapshotMatchesScene）。
    /// 元 lambda: m -> (m#tileSize, m#wallCells)
    pub def mapSnapshotKey(m: MapSnapshot): (Float64, Set[(Int32, Int32)]) =
        (m#tileSize, m#wallCells)

    /// S2.3 安全網: World baseStats（command 由来）と scene resource 由来 baseStats が食い違う entity を列挙する（両 faction）。
    /// BaseStats は Eq 非自動ゆえ全 8 数値 field を tuple へ射影して比較（combatViewMismatches 同型）。
    /// preserve 化後 frame-end では常に一致するはずで、食い違いは dual-write の漏れ（[BASESTATS DIFF]）を意味する。
    pub def baseStatsMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(baseStatsKey, baseStatsOf(EntityRef.Player(d#id), world)) != Some(baseStatsKey(Combat.baseStatsFrom(d#resource))))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(baseStatsKey, baseStatsOf(EntityRef.Enemy(d#id), world)) != Some(baseStatsKey(Combat.baseStatsFrom(d#resource))))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    /// S3 安全網: World statusEffects（command 由来）と scene の `#statuses` が食い違う entity を列挙する（両 faction）。
    /// Status は record（StatusEffect は Eq 持ち）だが順序込みの安定比較のため (effect, magnitude, remaining) tuple list へ
    /// 射影して比較（baseStatsMismatches 同型）。preserve 化後 frame-end では常に一致するはずで、食い違いは
    /// emitStatusesFromScene(Seed) の dual-write 漏れ（[STATUSEFFECTS DIFF]）を意味する。
    pub def statusEffectsMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (statusListKey(statusEffectsOf(EntityRef.Player(d#id), world)) != statusListKey(d#statuses))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (statusListKey(statusEffectsOf(EntityRef.Enemy(d#id), world)) != statusListKey(d#statuses))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    pub def moveTilesOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world; Map.get(toUid(ref), w#moveTiles)

    /// S2.5 安全網: World moveTiles（command 由来）と scene Data の base moveTiles が食い違う entity を列挙する（両 faction）。
    /// Int32 は Eq 自動ゆえ直接比較。spawn 後不変だが dual-write 漏れ（[MOVETILES DIFF]）を検出する。
    pub def moveTilesMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (moveTilesOf(EntityRef.Player(d#id), world) != Some(d#moveTiles))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (moveTilesOf(EntityRef.Enemy(d#id), world) != Some(d#moveTiles))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    /// S2.4 安全網: World weaponView（command 由来）と scene の装備武器投影が食い違う entity を列挙する（両 faction）。
    /// WeaponView は Eq 非自動・Option ゆえ全 8 field tuple を Option へ射影して比較（equippedRingMismatches 同型）。
    /// preserve 化後 frame-end では常に一致するはずで、食い違いは dual-write の漏れ（[WEAPONVIEW DIFF]）を意味する。
    pub def weaponViewMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(weaponViewKey, weaponViewOf(EntityRef.Player(d#id), world)) != Option.map(weaponViewKey, PlayerScene.equippedWeaponView(d)))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(weaponViewKey, weaponViewOf(EntityRef.Enemy(d#id), world)) != Option.map(weaponViewKey, EnemyScene.equippedWeaponView(d)))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    /// S2.4 安全網: World ringBonus（command 由来）と scene の装備指輪ボーナスが食い違う entity を列挙する（両 faction）。
    /// Bonuses は Eq 非自動ゆえ 5 数値 field tuple へ射影して比較（baseStatsMismatches 同型）。
    /// 食い違いは dual-write の漏れ（[RINGBONUS DIFF]）を意味する。
    pub def ringBonusMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(ringBonusKey, ringBonusOf(EntityRef.Player(d#id), world)) != Some(ringBonusKey(PlayerScene.equippedRingBonus(d))))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(ringBonusKey, ringBonusOf(EntityRef.Enemy(d#id), world)) != Some(ringBonusKey(EnemyScene.equippedRingBonus(d))))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    /// S-A0d: level-up 成長に要る基準 Stats + 成長率を World から読む（player-only。Enemy は常に None）。
    /// resolveCombat の level-up が resource を threading せず World 完結で成長を解くための seam。
    pub def growthOf(ref: EntityRef, world: World): Option[Growth] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#growth)
            case EntityRef.Enemy(_)   => None
        }

    /// S-A0b: 装備武器の戦闘投影を World から読む（unified-id・両 faction）。
    /// 外側 Option（entity 未登録）と内側 Option（武器なし）を flatten し、武器なし＝None で返す
    /// （combatView#weapon の型と一致）。B1 で combatView がここを読む。
    pub def weaponViewOf(ref: EntityRef, world: World): Option[Combat.WeaponView] =
        let World.World(w) = world; Map.get(toUid(ref), w#weaponView) |> Option.flatten

    /// S-A0c: 装備指輪ボーナスを World から読む（unified-id・両 faction）。未登録は None。
    /// B1 で combatView がここを読み、base + ring + status を合成する。
    pub def ringBonusOf(ref: EntityRef, world: World): Option[Ring.Bonuses] =
        let World.World(w) = world; Map.get(toUid(ref), w#ringBonus)

    /// P1a: 装備指輪リソース本体を World から読む（unified-id・両 faction）。外側 Option（entity 未登録）と
    /// 内側 Option（未装備）を flatten ＝未装備で None（`weaponViewOf` を逐語踏襲）。finisher/lifesteal が読む。
    pub def equippedRingOf(ref: EntityRef, world: World): Option[Ring.RingResource] =
        let World.World(w) = world; Map.get(toUid(ref), w#equippedRing) |> Option.flatten

    /// P1a 安全網: World の equippedRing（read-model）と scene の装備指輪が食い違う entity を列挙する。
    /// RingResource は Eq 非自動ゆえ (name, effect, power) タプルへ射影して比較（combatViewMismatches 同型）。
    pub def equippedRingMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(equippedRingKey, equippedRingOf(EntityRef.Player(d#id), world)) != Option.map(equippedRingKey, PlayerData.equippedRing(d)))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(equippedRingKey, equippedRingOf(EntityRef.Enemy(d#id), world)) != Option.map(equippedRingKey, d#ring))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    /// P2: 敵特殊能力 effectRule（生 Json）を World から読む（敵のみ・unified-id）。外側 Option（未登録）と
    /// 内側 Option（ルールなし）を flatten ＝ルールなしで None（`weaponViewOf` を逐語踏襲）。敵パスの sim 発火判定が読む。
    pub def effectRuleOf(ref: EntityRef, world: World): Option[Util.Json.Json] =
        let World.World(w) = world; Map.get(toUid(ref), w#effectRule) |> Option.flatten

    /// P2 安全網: World の effectRule（read-model）と scene の敵 effectRule が食い違う敵を列挙する。
    /// Json は Eq 非自動ゆえ ToString へ射影して比較（equippedRingMismatches 同型）。
    pub def effectRuleMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(effectRuleKey, effectRuleOf(EntityRef.Enemy(d#id), world)) != Option.map(effectRuleKey, d#resource#effectRule))
                Some(EntityRef.Enemy(d#id)) else None)

    /// B1: `combatView` を **World だけから再構築**する（faction 非依存）。base 戦闘値 + 指輪 + status mods
    /// + hp + 装備武器投影を合成し、`PlayerScene.combatView` / `EnemyScene.combatView` と同一の `Combat.CombatView`
    /// を返す。式は両 scene の combatView と一致（status/ring 補正の載せ方を含む）。baseStats/hp/ringBonus が
    /// 揃わない（未登録）entity は None。これで scene-authority な combatView の reader を World へ flip できる。
    pub def combatViewOf(ref: EntityRef, world: World): Option[Combat.CombatView] =
        match (baseStatsOf(ref, world), hpOf(ref, world), ringBonusOf(ref, world)) {
            case (Some(bs), Some(hp), Some(rb)) =>
                // scene combatView と同一の組立（`Combat.assembleView` 単一源泉）を使う＝formula drift 不能。
                Some(Combat.assembleView({
                    base   = bs,
                    mods   = StatusSystem.combatMods(statusEffectsOf(ref, world)),
                    ring   = rb,
                    hp     = hp,
                    weapon = weaponViewOf(ref, world)}))
            case _ => None
        }

    /// B1 安全網: `combatViewOf`（World 再構築）と scene の `combatView` が食い違う entity を列挙する。
    /// parallel-run DIFF（hp 等と同型）。read-model ゆえ frame-end では常に一致するはずで、
    /// 食い違いは「combatView と combatViewOf の合成式 drift」を意味する（移行中の回帰検出）。
    /// record/enum は Eq 非自動ゆえ全数値 + 武器投影を tuple 射影して比較する。
    pub def combatViewMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(combatViewKey, combatViewOf(EntityRef.Player(d#id), world))
                != Some(combatViewKey(PlayerScene.combatView(d))))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(combatViewKey, combatViewOf(EntityRef.Enemy(d#id), world))
                != Some(combatViewKey(EnemyScene.combatView(d))))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    /// S4.1: いずれかの味方が潜伏中か（World の `playerHidden` set 由来）。Enemy は常に false。
    /// scene `unitView` の `hidden = data#hidden` と一致（playerHidden は `d#hidden` の味方を集めた set）。
    pub def playerHiddenOf(ref: EntityRef, world: World): Bool =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Set.memberOf(id, w#playerHidden)
            case EntityRef.Enemy(_)   => false
        }

    /// S4.1: scene の `PlayerScene.unitView` / `EnemyScene.unitView` と **bit 一致**する `UnitView` を
    /// **World 由来**で再構築する（消費者 flip の土台）。pos/hp/moveTiles/weaponRange/combat/isDying/hidden は
    /// World store から、`aiType`（+ player の load 容量に要る constitution/attack）だけ resource 由来ゆえ
    /// scene Data から読む（hybrid-A 批准の resource 残置）。`combatViewOf` が None（base/hp/ring 未登録）なら全体 None。
    /// 味方の `moveTiles` は scene と同じく `Encumbrance.effectiveMoveTiles(base, load)`（load は **World 在庫**の重量合計）、
    /// 敵は base そのまま。`weaponRange` は先頭武器の range（player=weapons 先頭・enemy=0/1 List 射影の先頭）。
    pub def unitViewFromWorld(ref: EntityRef, world: World, scene: Scene[NodeTag]): Option[UnitView] =
        match (posOf(ref, world), hpOf(ref, world), combatViewOf(ref, world), moveTilesOf(ref, world)) {
            case (Some(pos), Some(hp), Some(combat), Some(base)) =>
                let weaponRange = weaponsOf(ref, world)
                    |> Option.flatMap(List.head) |> Option.map(w -> w#range);
                match ref {
                    case EntityRef.Player(id) =>
                        // 味方の実効移動力: 素の moveTiles に積載ペナルティ（load）を掛けた値。
                        // load の重量合計は World 在庫（weapons/staves/consumables/rings）から、
                        // 容量に要る constitution/attack は resource 由来ゆえ scene Data から（aiType と同じ残置）。
                        match PlayerScene.get(id, scene) {
                            case None    => None
                            case Some(d) =>
                                // 在庫レコードは関数引数位置（カンマ後）に直接書く＝record リテラル明確化（先頭 `let = {` は block 誤認される）。
                                let load = Encumbrance.loadOf(d#resource#constitution, d#resource#attack,
                                    {weapons     = Option.getWithDefault(Nil, weaponsOf(ref, world)),
                                     staves      = Option.getWithDefault(Nil, stavesOf(ref, world)),
                                     consumables = Option.getWithDefault(Nil, consumablesOf(ref, world)),
                                     rings       = Option.getWithDefault(Nil, ringsOf(ref, world))});
                                Some({id = id, faction = Faction.Player, pos = pos, hp = hp,
                                      moveTiles = Encumbrance.effectiveMoveTiles(base, load),
                                      weaponRange = weaponRange, combat = combat,
                                      isDying = false, hidden = playerHiddenOf(ref, world),
                                      aiType = EnemyAI.AiType.Aggressive})
                        }
                    case EntityRef.Enemy(id) =>
                        match EnemyScene.get(id, scene) {
                            case None    => None
                            case Some(d) =>
                                Some({id = id, faction = Faction.Enemy, pos = pos, hp = hp,
                                      moveTiles = base, weaponRange = weaponRange, combat = combat,
                                      isDying = isDyingOf(ref, world), hidden = false,
                                      aiType = d#resource#aiType})
                        }
                }
            case _ => None
        }

    /// S4.1 安全網: World 由来 `unitViewFromWorld` と scene `unitView` が食い違う entity を列挙する（両 faction）。
    /// UnitView は Eq 非自動ゆえ全 10 field を tuple へ射影（pos/weaponRange/combat は更にネスト射影）して比較する。
    /// parity（消費者 flip の前提＝挙動不変の担保）が命で、食い違いは load 式 / head 規約 / combat 合成の drift を意味する（[UNITVIEW DIFF]）。
    pub def unitViewMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(unitViewKey, unitViewFromWorld(EntityRef.Player(d#id), world, scene))
                != Some(unitViewKey(PlayerScene.unitView(d))))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(unitViewKey, unitViewFromWorld(EntityRef.Enemy(d#id), world, scene))
                != Some(unitViewKey(EnemyScene.unitView(d))))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

    /// S4.4: scene の `PlayerScene.get` Data と **bit 一致**する `PlayerData.Data` を **World 由来**で再構築する
    /// （S6 で scene を World から派生する／S7 で bridge 撤去する土台。additive twin ＝消費者 flip はまだしない）。
    /// 23 field の供給源（PlayerData.flix:80-89 の分類）:
    ///   W ストア由来 14 accessor（15 field）: gridPos=posOf／hp=hpOf／waited=waitedOf／moveTiles=moveTilesOf／
    ///     attackTargetId=attackTargetOf／weapons=weaponsOf／staves=stavesOf／consumables=consumablesOf／rings=ringsOf／
    ///     ringEquipped=ringEquippedOf／followUpUsed=followUpUsedOf／(level,exp)=progressOf（タプル分解）／
    ///     hidden=playerHiddenOf／statuses=statusEffectsOf。
    ///   R 残置 5（scene Data から）: classId／resource／selectedItem／facing／pendingLevelUp（hybrid-A resource 系残置）。
    ///   S→W 未昇格 2（scene Data から・S5/D13a で将来昇格）: moveStepsTaken／usedStairs（World にまだ store 無し）。
    ///   id = 引数。
    /// core な W field（posOf/hpOf/moveTiles/在庫/progress 等）が一つでも None なら全体 None（unitViewFromWorld と同じ gate 流儀）。
    pub def dataFromWorld(id: Int32, world: World, scene: Scene[NodeTag]): Option[PlayerData.Data] =
        let ref = EntityRef.Player(id);
        match (posOf(ref, world), hpOf(ref, world), waitedOf(ref, world), moveTilesOf(ref, world),
               weaponsOf(ref, world), stavesOf(ref, world), consumablesOf(ref, world), ringsOf(ref, world),
               ringEquippedOf(ref, world), followUpUsedOf(ref, world), progressOf(ref, world),
               PlayerScene.get(id, scene)) {
            case (Some(pos), Some(hp), Some(waited), Some(moveTiles),
                  Some(weapons), Some(staves), Some(consumables), Some(rings),
                  Some(ringEquipped), Some(followUpUsed), Some((level, exp)),
                  Some(d)) =>
                // record リテラルは `Some(` 直後（`(` の後）に置く＝block/named-tuple 誤パース回避（S4.1 gotcha）。
                Some({id = id, classId = d#classId, gridPos = pos, moveTiles = moveTiles, hp = hp,
                      waited = waited, attackTargetId = attackTargetOf(ref, world),
                      resource = d#resource, weapons = weapons, staves = staves,
                      consumables = consumables, rings = rings, ringEquipped = ringEquipped,
                      selectedItem = d#selectedItem, moveStepsTaken = d#moveStepsTaken,
                      facing = d#facing, hidden = playerHiddenOf(ref, world), usedStairs = d#usedStairs,
                      level = level, exp = exp, pendingLevelUp = d#pendingLevelUp,
                      statuses = statusEffectsOf(ref, world), followUpUsed = followUpUsed})
            case _ => None
        }

    /// S4.4 安全網: World 由来 `dataFromWorld` と scene `PlayerScene.get` Data が食い違う味方を列挙する（[PLAYERDATA DIFF]）。
    /// Data は Eq 非自動ゆえ **全 23 field を tuple へ射影**して比較する。射影が 1 field でも漏れると、その field が
    /// ズレても DIFF が鳴らず「parity 成立」と誤認する（S2.4 の length+head 見逃しの拡大版）ため **全 field 完備が命**。
    /// ネスト射影: gridPos={x,y}／weapons/staves/consumables/rings は (長さ, 先頭の name)／resource は数値 stat 群で代表／
    /// statuses は (effect,magnitude,remaining) list／selectedItem(ItemKind Eq)／facing(Direction Eq)／
    /// pendingLevelUp は Option を (unitName,fromLevel,toLevel,変化数) へ射影／他スカラはそのまま。
    pub def playerDataMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        // 全 23 field の射影は playerDataKey へ集約（2段ネスト ((13),(10))・在庫は weaponsMismatches 等と
        // 同一 weaponKey/staffKey/consumableKey/ringKey を共有＝S4.4 級 drift 不能）。
        PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(playerDataKey, dataFromWorld(d#id, world, scene)) != Some(playerDataKey(d)))
                Some(EntityRef.Player(d#id)) else None)

    /// S4.4b: scene の `EnemyScene.get` Data と **bit 一致**する `EnemyData.Data` を **World 由来**で再構築する
    /// （S4.4 の dataFromWorld〔player版〕の enemy 版。S6 で両 faction scene を World 派生／S7 で bridge 撤去する土台。
    /// additive twin ＝消費者 flip はまだしない）。17 field の供給源（EnemyData.flix:21-49 の分類）:
    ///   W ストア由来 12 accessor: gridPos=posOf／alerted=alertedOf／moveTiles=moveTilesOf／hp=hpOf／
    ///     isDying=isDyingOf／attackTargetId=attackTargetOf／weapon=weaponsOf(Enemy id) の head／prevPos=prevPosOf／
    ///     statuses=statusEffectsOf／ring=equippedRingOf（敵 ring は P1a の equippedRing store・both faction）／
    ///     followUpUsed=followUpUsedOf／bottleUsed=bottleUsedOf。
    ///   R 残置 3（scene Data から）: resourceId／resource／homeModuleIdx。
    ///   S→W 未昇格 1（scene Data から・D13a で将来昇格）: acted。
    ///   id = 引数。
    /// core な W field（posOf/hpOf/moveTiles/alerted/weapons/followUpUsed/bottleUsed）が一つでも None なら全体 None
    /// （dataFromWorld と同じ gate 流儀）。isDying は Bool 直 / attackTargetId・prevPos・ring は Option 直 / statuses は default-Nil。
    pub def dataFromWorldEnemy(id: Int32, world: World, scene: Scene[NodeTag]): Option[EnemyData.Data] =
        let ref = EntityRef.Enemy(id);
        match (posOf(ref, world), alertedOf(ref, world), moveTilesOf(ref, world), hpOf(ref, world),
               weaponsOf(ref, world), followUpUsedOf(ref, world), bottleUsedOf(ref, world),
               EnemyScene.get(id, scene)) {
            case (Some(pos), Some(alerted), Some(moveTiles), Some(hp),
                  Some(weapons), Some(followUpUsed), Some(bottleUsed),
                  Some(d)) =>
                // record リテラルは `Some(` 直後（`(` の後）に置く＝block/named-tuple 誤パース回避（S4.1 gotcha）。
                Some({id = id, resourceId = d#resourceId, gridPos = pos, alerted = alerted,
                      homeModuleIdx = d#homeModuleIdx, moveTiles = moveTiles, hp = hp,
                      isDying = isDyingOf(ref, world), attackTargetId = attackTargetOf(ref, world),
                      resource = d#resource, weapon = List.head(weapons), acted = d#acted,
                      prevPos = prevPosOf(ref, world), statuses = statusEffectsOf(ref, world),
                      ring = equippedRingOf(ref, world), followUpUsed = followUpUsed,
                      bottleUsed = bottleUsed})
            case _ => None
        }

    /// S4.4b 安全網: World 由来 `dataFromWorldEnemy` と scene `EnemyScene.get` Data が食い違う敵を列挙する（[ENEMYDATA DIFF]）。
    /// 全 17 field の射影は enemyDataKey へ集約（2段ネスト ((9),(8))・weapon/ring/statuses/pos は weaponKey/
    /// equippedRingKey/statusListKey/posKey を共有＝S4.4 級 drift 不能）。1 field でも漏れると検出穴になるため全 field 完備が命。
    pub def enemyDataMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(enemyDataKey, dataFromWorldEnemy(d#id, world, scene)) != Some(enemyDataKey(d)))
                Some(EntityRef.Enemy(d#id)) else None)

    /// World 拡張: 味方の (level, exp) を World から読む。未登録は None。Enemy は常に None。
    pub def progressOf(ref: EntityRef, world: World): Option[(Int32, Int32)] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) =>
                Option.flatMap(lv -> Option.map(xp -> (lv, xp), Map.get(id, w#playerExp)),
                               Map.get(id, w#playerLevel))
            case EntityRef.Enemy(_)   => None
        }

    /// World 拡張 検証器: 味方 (level, exp) の World/scene 不一致。
    pub def progressMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[(Int32, Int32)], (Int32, Int32))] =
        PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let wp = progressOf(EntityRef.Player(d#id), world);
            let sp = (d#level, d#exp);
            if (wp != Some(sp)) Some((EntityRef.Player(d#id), wp, sp)) else None
        })

    /// F8-slice2: 敵ターン intro hold 中か（`TopBarScene.isBusy` の World 版・順序非依存）。
    pub def enemyTurnBusyOf(world: World): Bool =
        let World.World(w) = world; w#enemyTurnBusy

    /// F8-slice2: バーが敵ターン観測済みか（`TopBarScene.hasObservedEnemy` の World 版・順序非依存）。
    pub def phaseObservedEnemyOf(world: World): Bool =
        let World.World(w) = world; w#phaseObservedEnemy

    /// F8-slice1 検証器: attackTargetId の World/scene 不一致（両 faction）。
    pub def attackTargetMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[Int32], Option[Int32])] =
        let ps = PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let wt = attackTargetOf(EntityRef.Player(d#id), world);
            if (wt != d#attackTargetId) Some((EntityRef.Player(d#id), wt, d#attackTargetId)) else None
        });
        let es = EnemyScene.getAll(scene) |> List.filterMap(d -> {
            let wt = attackTargetOf(EntityRef.Enemy(d#id), world);
            if (wt != d#attackTargetId) Some((EntityRef.Enemy(d#id), wt, d#attackTargetId)) else None
        });
        List.append(ps, es)

    /// 軸1 仕上げ 検証器: 敵の World isDying（command 由来）と scene isDying の不一致を返す。
    pub def dyingMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Bool, Bool)] =
        EnemyScene.getAll(scene) |> List.filterMap(d -> {
            let wd = isDyingOf(EntityRef.Enemy(d#id), world);
            if (wd != d#isDying) Some((EntityRef.Enemy(d#id), wd, d#isDying)) else None
        })

    /// F7-spike 検証器: 敵の World alerted（command 由来）と scene alerted の不一致を返す（`hpMismatches` 同型）。
    pub def alertedMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[Bool], Bool)] =
        EnemyScene.getAll(scene) |> List.filterMap(d -> {
            let wa = alertedOf(EntityRef.Enemy(d#id), world);
            if (wa != Some(d#alerted)) Some((EntityRef.Enemy(d#id), wa, d#alerted)) else None
        })

    /// F6b 検証器: scene の各ユニットについて **World hp（command 由来）と scene hp の不一致**を返す。
    /// gameLoop が refreshMirror（hp re-mirror）の **前**に呼ぶ＝全 hp 書込が `Cmd.SetHp` を dual-write して
    /// いれば空。書き漏れがあると `(ref, worldHp, sceneHp)` が出る（`[F6 HP DIFF]`）。spawn 直後など World 未登録は
    /// transient（次フレーム refreshMirror で解消）。preserve 化（refreshMirror が hp を保持）の前提を pin する。
    pub def hpMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[Int32], Int32)] =
        let mism = (ref, sceneHp) -> {
            let wHp = hpOf(ref, world);
            if (wHp != Some(sceneHp)) Some((ref, wHp, sceneHp)) else None
        };
        let ps = PlayerScene.getAll(scene) |> List.filterMap(d -> mism(EntityRef.Player(d#id), d#hp));
        let es = EnemyScene.getAll(scene)  |> List.filterMap(d -> mism(EntityRef.Enemy(d#id), d#hp));
        List.append(ps, es)

    /// hp を World から読む（read-model アクセサ）。F6 の reader flip / 検証器の供給元。
    /// A': 単一 store＋toUid（faction 別 match arm 消失）。
    pub def hpOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world; Map.get(toUid(ref), w#hp)

    /// D3: weapons を World から読む（read-model アクセサ・hpOf 同型）。未登録は None。
    /// 内側 List は player の weapons / enemy の 0/1 List 射影。reader flip はまだしない（供給元のみ）。
    pub def weaponsOf(ref: EntityRef, world: World): Option[List[UnitCatalog.WeaponResource]] =
        let World.World(w) = world; Map.get(toUid(ref), w#weapons)

    /// D3 検証器（hpMismatches 同型）: World weapons（command 由来）と scene #weapons の不一致を返す。
    /// WeaponResource は Eq 非自動ゆえ **長さ＋先頭武器の (name, durability)** へ射影して比較する
    /// （[WEAPONS DIFF]）。enemy は単数 #weapon を Option.toList で 0/1 List 化して突合。
    /// gameLoop が refreshMirror（weapons preserve+prune）の **前**に呼ぶ＝全 weapon 書込が
    /// `Cmd.SetWeapons` を dual-write していれば空。書き漏れがあると `(ref, worldLen, sceneLen)` が出る。
    pub def weaponsMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Int32, Int32)] =
        let mism = (ref, sceneWs) -> {
            let wWs = weaponsOf(ref, world) |> Option.map(ws -> headKey(ws, weaponKey));
            if (wWs != Some(headKey(sceneWs, weaponKey)))
                Some((ref, Option.getWithDefault(-1, Option.map(p -> fst(p), wWs)), List.length(sceneWs)))
            else None
        };
        let ps = PlayerScene.getAll(scene) |> List.filterMap(d -> mism(EntityRef.Player(d#id), d#weapons));
        let es = EnemyScene.getAll(scene)  |> List.filterMap(d -> mism(EntityRef.Enemy(d#id), Option.toList(d#weapon)));
        List.append(ps, es)

    /// D4: staves を World から読む（read-model アクセサ・player-only・waitedOf 流儀）。Enemy は常に None。
    pub def stavesOf(ref: EntityRef, world: World): Option[List[Staff.StaffResource]] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#staves)
            case EntityRef.Enemy(_)   => None
        }

    /// D4: consumables を World から読む（player-only）。Enemy は常に None。
    pub def consumablesOf(ref: EntityRef, world: World): Option[List[Consumable.ConsumableResource]] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#consumables)
            case EntityRef.Enemy(_)   => None
        }

    /// D4: rings を World から読む（player-only）。Enemy は常に None。
    pub def ringsOf(ref: EntityRef, world: World): Option[List[Ring.RingResource]] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#rings)
            case EntityRef.Enemy(_)   => None
        }

    /// D4: ringEquipped を World から読む（player-only・Bool）。Enemy は常に None。
    pub def ringEquippedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#ringEquipped)
            case EntityRef.Enemy(_)   => None
        }

    /// D4 検証器（weaponsMismatches 同型・players のみ）: World staves と scene #staves の不一致。
    /// StaffResource は Eq 非自動ゆえ **長さ＋先頭 (name, durability)** へ射影して比較する（[STAVES DIFF]）。
    pub def stavesMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Int32, Int32)] =
        PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let ww = stavesOf(EntityRef.Player(d#id), world) |> Option.map(xs -> headKey(xs, staffKey));
            if (ww != Some(headKey(d#staves, staffKey)))
                Some((EntityRef.Player(d#id), Option.getWithDefault(-1, Option.map(p -> fst(p), ww)), List.length(d#staves)))
            else None
        })

    /// D4 検証器: World consumables と scene #consumables の不一致（先頭 (name, durability) 射影）。
    pub def consumablesMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Int32, Int32)] =
        PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let ww = consumablesOf(EntityRef.Player(d#id), world) |> Option.map(xs -> headKey(xs, consumableKey));
            if (ww != Some(headKey(d#consumables, consumableKey)))
                Some((EntityRef.Player(d#id), Option.getWithDefault(-1, Option.map(p -> fst(p), ww)), List.length(d#consumables)))
            else None
        })

    /// D4 検証器: World rings と scene #rings の不一致。RingResource に durability が無いので先頭 (name, power) 射影。
    pub def ringsMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Int32, Int32)] =
        PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let ww = ringsOf(EntityRef.Player(d#id), world) |> Option.map(xs -> headKey(xs, ringKey));
            if (ww != Some(headKey(d#rings, ringKey)))
                Some((EntityRef.Player(d#id), Option.getWithDefault(-1, Option.map(p -> fst(p), ww)), List.length(d#rings)))
            else None
        })

    /// D4 検証器: World ringEquipped と scene #ringEquipped の不一致（Bool 直接比較・alertedMismatches 同型）。
    pub def ringEquippedMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[Bool], Bool)] =
        PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let ww = ringEquippedOf(EntityRef.Player(d#id), world);
            if (ww != Some(d#ringEquipped)) Some((EntityRef.Player(d#id), ww, d#ringEquipped)) else None
        })

    /// A'（faction タグ）: unified-id の faction を **enum タグ component** から読む。
    /// 「player/enemy を id で判断」せず、この明示タグで faction を得る（Bevy Team component 相当）。
    pub def teamOf(uid: EntityId, world: World): Option[Faction] =
        let World.World(w) = world; Map.get(uid, w#team)

    /// faction タグの便宜述語。
    pub def isPlayerUid(uid: EntityId, world: World): Bool = teamOf(uid, world) == Some(Faction.Player)
    pub def isEnemyUid(uid: EntityId, world: World): Bool = teamOf(uid, world) == Some(Faction.Enemy)

    /// ally フラグ＋id から EntityRef を作る（境界 emit / call-site の共通化）。
    pub def refOf(ally: Bool, id: EntityId): EntityRef =
        if (ally) EntityRef.Player(id) else EntityRef.Enemy(id)

    /// EffectPlan の status/immobilize 項目を **runPlan の境界で** World.Command として emit する。
    /// これにより handler テーブルは pure のまま（`checked_ecast` 不要）＝「scene 効果適用(pure handler)」と
    /// 「World command 発行(境界)」を責務分離。各 `EffectRunner.runPlan` 呼出点で plan を渡して呼ぶ。
    pub def emitStatusAdds(items: List[EffectPlan.PlanItem]): Unit \ Command =
        items |> List.forEach(item -> match item {
            case EffectPlan.PlanItem.StatusAt(id, ally, se, m, t) =>
                Command.emit(Cmd.Add(refOf(ally, id), {effect = se, magnitude = m, remaining = t}))
            case EffectPlan.PlanItem.ImmobilizeAt(id, ally, turns) =>
                Command.emit(Cmd.Add(refOf(ally, id), StatusSystem.immobilizeFor(turns)))
            case _ => ()
        })

    /// F6a: hp を変える PlanItem（heal/fullHeal/damage/maxHpUp/revive）について、**runPlan 適用後の scene**
    /// から各対象の hp を読み戻して `Cmd.SetHp` を境界で emit する。これで effect-runner 経由の hp も
    /// World に dual-write されつつ、PlanHandlers は **pure のまま**（pure-handler-widen 不可の壁を回避）。
    /// `emitStatusAdds` と同じ責務分離（pure handler / 境界 emit）。runPlan の **後**に渡す（適用後 hp を読むため）。
    pub def emitHpSets(items: List[EffectPlan.PlanItem], scene: Scene[NodeTag]): Unit \ Command =
        items |> List.forEach(item -> match item {
            case EffectPlan.PlanItem.HealAt(id, ally, _)    => emitHpAt(id, ally, scene)
            case EffectPlan.PlanItem.FullHealAt(id, ally)   => emitHpAt(id, ally, scene)
            case EffectPlan.PlanItem.DamageAt(id, ally, _)  => emitHpAt(id, ally, scene)
            case EffectPlan.PlanItem.MaxHpUpAt(id, ally, _) =>
                emitHpAt(id, ally, scene);
                // S2.3: 命の草で resource#hp（=baseStats#maxHp）が変わる＝唯一 baseStats を動かす effect-plan。
                // hp と同 funnel で SetBaseStats を境界 dual-write（StaffCast の maxHpUpUnit/applyMaxHpUp の World 側）。
                emitBaseStatsAt(id, ally, scene)
            case EffectPlan.PlanItem.ReviveAt(id, ally)     => emitHpAt(id, ally, scene)
            case _ => ()
        })

    /// 対象の現 hp を scene から読み（居なければ no-op）、`Cmd.SetHp` を emit する内部ヘルパー。
    def emitHpAt(id: EntityId, ally: Bool, scene: Scene[NodeTag]): Unit \ Command =
        let hpOpt = if (ally) PlayerScene.get(id, scene) |> Option.map(d -> d#hp)
                    else EnemyScene.get(id, scene) |> Option.map(d -> d#hp);
        match hpOpt {
            case Some(hp) => Command.emit(Cmd.SetHp(refOf(ally, id), hp))
            case None     => ()
        }

    /// S2.3: 対象の現 resource から baseStats を導いて `Cmd.SetBaseStats` を emit する内部ヘルパー（emitHpAt 同型）。
    /// maxHp 変更 effect で baseStats#maxHp が動くため runPlan 後の scene を読んで境界 dual-write する。
    def emitBaseStatsAt(id: EntityId, ally: Bool, scene: Scene[NodeTag]): Unit \ Command =
        let bsOpt = if (ally) PlayerScene.get(id, scene) |> Option.map(d -> Combat.baseStatsFrom(d#resource))
                    else EnemyScene.get(id, scene) |> Option.map(d -> Combat.baseStatsFrom(d#resource));
        match bsOpt {
            case Some(bs) => Command.emit(Cmd.SetBaseStats(refOf(ally, id), bs))
            case None     => ()
        }

    /// World（位置の read-model mirror）から Board を組み立てる S4 の経路（World クエリ＝ecs/ 層）。
    /// pieces は World の pos-store（`Cmd.Move` 権威・hidden 味方除外）、map は scene の静的地形
    /// （`BoardSnapshot.mapSnapshotOf` を借用）。すなわち「駒は World・地形は scene」の合成。
    /// 通常フレームでは dual-write により `BoardSnapshot.fromScene` と `boardKey` 上で一致する
    /// （`boardMatchesScene` が Phase C の凍結契約としてこれを pin する）。
    /// flip 時は call-point 単位で `BoardSnapshot.fromScene(scene)` をこれに差し替える。
    pub def toBoard(world: World, scene: Scene[NodeTag]): Board =
        {
            map    = BoardSnapshot.mapSnapshotOf(scene),
            pieces = boardPieces(world)
        }

    /// P1c: World だけから Board を組む（scene 非依存）。地形は store した `mapSnapshot`（未確定なら None）、
    /// 駒は既存の pure-World `boardPieces`（`Cmd.Move` 権威・hidden 除外）を VERBATIM 再利用＝`toBoard` の
    /// scene 地形を World store に差し替えた版。ノックバックの sim 着地計算が読む。
    pub def boardOf(world: World): Option[Board] =
        let World.World(w) = world;
        Option.map(m -> ({map = m, pieces = boardPieces(world)}: Board), w#mapSnapshot)

    /// P1c 安全網: store した mapSnapshot（地形）が scene 由来と食い違うか（boardKey は駒のみ見るため別建て）。
    /// MapSnapshot は Eq 非自動ゆえ (tileSize, wallCells) へ射影して比較（壁レイアウトの drift 検出）。
    pub def mapSnapshotMatchesScene(world: World, scene: Scene[NodeTag]): Bool =
        let World.World(w) = world;
        Option.map(mapSnapshotKey, w#mapSnapshot) == Some(mapSnapshotKey(BoardSnapshot.mapSnapshotOf(scene)))

    /// Board の駒を**順序非依存**で突合する正規形（(faction, id, x, y) 昇順）。
    /// `Board` は型エイリアスで Eq derive 不可・pieces 順が World(id昇順) と fromScene(preorder) で違うため、
    /// P0a 検証器（World 由来盤面 vs scene 由来盤面の mid-frame 突合）はこのキーで比較する。
    pub def boardKey(board: Board): List[(Int32, Int32, Int32, Int32)] =
        board#pieces
            |> List.map(pair -> {
                let (piece, pos) = pair;
                match piece {
                    case Piece.Player(i) => (0, i, pos#x, pos#y)
                    case Piece.Enemy(i)  => (1, i, pos#x, pos#y)
                }
            })
            |> List.sort

    /// World の位置 store から駒一覧を組む（map 非依存・純粋）。順序は id 昇順（Map.toList）で決定的。
    /// hidden 味方（集合・階段退場）は除外＝`BoardSnapshot.fromScene` の hidden フィルタと同義。
    /// 順序が fromScene（敵 preorder）と食い違っても、occupancy/セル集合/距離場の多源 BFS・AI（id タイブレーク
    /// 再ソート）は順序非依存で、各 piece が id を自己同定するため安全。
    pub def boardPieces(world: World): List[(Piece, {x = Int32, y = Int32})] =
        // A': 単一 `pos` store を **team タグ**で faction 分けして Piece 化（hidden 味方は除外）。
        let World.World(w) = world;
        Map.toList(w#pos) |> List.filterMap(pair -> {
            let (uid, pos) = pair;
            match uidToRef(uid) {
                case EntityRef.Player(pid) =>
                    if (Set.memberOf(pid, w#playerHidden)) None else Some((Piece.Player(pid), pos))
                case EntityRef.Enemy(eid)  => Some((Piece.Enemy(eid), pos))
            }
        })

    /// board-lock（Phase C 契約）: 「World 由来の盤面 == scene 由来の盤面」を **順序非依存キー**で突合する。
    /// `toBoard`（pieces=World pos-store・Cmd.Move 権威・hidden 除外／map=scene 静的）と
    /// `BoardSnapshot.fromScene`（pieces=scene gridPos・hidden 除外）を同じ `boardKey` 正規形で比較。
    /// dual-write が整合する通常フレームでは true。これが、将来の `resolveCombat` の board 入力が
    /// 満たすべき凍結契約（World-derived board が legacy scene-derived board と一致する）。
    /// 非対称ガード: `boardKey` が各 source を独立に walk する＝id 集合の **和** 上で symmetric ゆえ、
    /// 片側にしか居ない可視 entity（prune/pre-sync ずれ）も mismatch として検出する。
    pub def boardMatchesScene(world: World, scene: Scene[NodeTag]): Bool =
        boardKey(toBoard(world, scene)) == boardKey(BoardSnapshot.fromScene(scene))

    /// `boardMatchesScene` の diff 版。一致なら None、不一致なら正規化済みの 2 キー
    /// `(World 由来, scene 由来)` を返す（[BOARD DIFF] 検証器・デバッグ出力の供給元）。
    pub def boardKeyMismatch(world: World, scene: Scene[NodeTag]):
            Option[(List[(Int32, Int32, Int32, Int32)], List[(Int32, Int32, Int32, Int32)])] =
        let wk = boardKey(toBoard(world, scene));
        let sk = boardKey(BoardSnapshot.fromScene(scene));
        if (wk == sk) None else Some((wk, sk))

    /// World→scene の逆向き write-back（S1b）。World が持つ statuses を scene の Data#statuses へ書き戻す。
    /// 既存の純粋 writer `PlayerScene.mapPlayer` / `EnemyScene.mapEnemy` を再利用（走査・書込を再実装しない）。
    /// scene に居ない id は mapPlayer/mapEnemy が no-op で読み飛ばす。combatView/isImmobilized 等の read 側は
    /// 依然 scene の Data#statuses を読むので、この sync が World を唯一の真とする seam になる（flip は S1b 後段）。
    pub def syncStatusesToScene(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        let World.World(w) = world;
        // A': 単一 statusEffects を uidToRef で faction 分けし、original id で mapPlayer/mapEnemy。
        Map.foldLeftWithKey((sc, uid, statuses) ->
            match uidToRef(uid) {
                case EntityRef.Player(pid) => PlayerScene.mapPlayer(pid, d -> {statuses = statuses | d}, sc)
                case EntityRef.Enemy(eid)  => EnemyScene.mapEnemy(eid, d -> {statuses = statuses | d}, sc)
            }, scene, w#statusEffects)

    /// S5（§A 完成へ・World→scene 一方向 sync）: 各ユニットの scene `gridPos` を **World の位置で上書き**する。
    /// `syncStatusesToScene` と同型（`mapPlayer`/`mapEnemy` を再利用・scene 不在 id は no-op）。
    /// S5a（dual-write 継続中）は World==scene ゆえ **no-op＝挙動不変**で seam を確立。S5b で move 関数の
    /// scene gridPos 直書きを撤去し、gridPos を**この sync 由来（World の派生）**に一本化する。
    pub def syncTreeFromWorld(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        // A': 単一 `pos` store を team タグで faction 分けし、original id で mapPlayer/mapEnemy。
        let World.World(w) = world;
        // 位置（S5b・既存）。store に居る entity だけ derive＝spawn-transient（store 未登録）は scene を保持。
        let withPos = Map.foldLeftWithKey((sc, uid, pos) ->
            match uidToRef(uid) {
                case EntityRef.Player(pid) => PlayerScene.mapPlayer(pid, d -> {gridPos = pos | d}, sc)
                case EntityRef.Enemy(eid)  => EnemyScene.mapEnemy(eid, d -> {gridPos = pos | d}, sc)
            }, scene, w#pos);
        // Phase B（hp/dying/progress も World 権威・scene 派生化）: refreshMirror が command 由来をすでに preserve
        // しているこれらを scene へ一方向 derive する。legacy（dual-write 済み）では idempotent＝scene==World で
        // 挙動不変。ECS 経路（World のみ書く cutover）では scene の stale を解消する。write 漏れは「hp が動かない /
        // 敵が死なない / exp が増えない」可視バグとして現れる（位置と同じ＝独立 DIFF 検出器に依存しない）。
        let withHp = Map.foldLeftWithKey((sc, uid, hp) ->
            match uidToRef(uid) {
                case EntityRef.Player(pid) => PlayerScene.mapPlayer(pid, d -> {hp = hp | d}, sc)
                case EntityRef.Enemy(eid)  => EnemyScene.mapEnemy(eid, d -> {hp = hp | d}, sc)
            }, withPos, w#hp);
        // S6（waited も World 権威・scene 派生化）: setWaited/setActive/useStairs は scene 直書きを撤去し
        // Cmd.SetWaited のみ emit する。ここで playerWaited store から scene へ一方向 derive する（player のみ）。
        let withWaited = Map.foldLeftWithKey((sc, pid, wd) ->
            PlayerScene.mapPlayer(pid, d -> {waited = wd | d}, sc), withHp, w#playerWaited);
        // isDying は enemyDying(Set) の membership で全敵に derive（true/false 両方・敵のみ）。
        let withDying = List.foldLeft((sc, d) ->
            EnemyScene.mapEnemy(d#id, e -> {isDying = Set.memberOf(enemyUid(d#id), w#enemyDying) | e}, sc),
            withWaited, EnemyScene.getAll(scene));
        // alerted も World(enemyAlerted) 由来に derive（敵のみ）。
        let withAlerted = Map.foldLeftWithKey((sc, uid, b) ->
            match uidToRef(uid) {
                case EntityRef.Enemy(eid) => EnemyScene.mapEnemy(eid, e -> {alerted = b | e}, sc)
                case EntityRef.Player(_)  => sc
            }, withDying, w#enemyAlerted);
        // S6: bottleUsed も World(enemyBottleUsed) 由来に derive（敵のみ・alerted と同型）。
        let withBottle = Map.foldLeftWithKey((sc, uid, b) ->
            match uidToRef(uid) {
                case EntityRef.Enemy(eid) => EnemyScene.mapEnemy(eid, e -> {bottleUsed = b | e}, sc)
                case EntityRef.Player(_)  => sc
            }, withAlerted, w#enemyBottleUsed);
        // S6: followUpUsed も World(followUpUsed・両 faction 統合マップ)由来に derive。uid を uidToRef で分配。
        let withFollowUp = Map.foldLeftWithKey((sc, uid, f) ->
            match uidToRef(uid) {
                case EntityRef.Player(pid) => PlayerScene.mapPlayer(pid, d -> {followUpUsed = f | d}, sc)
                case EntityRef.Enemy(eid)  => EnemyScene.mapEnemy(eid, e -> {followUpUsed = f | e}, sc)
            }, withBottle, w#followUpUsed);
        // S6: prevPos も World(enemyPrevPos)由来に derive（敵のみ・sparse Option）。scene 読み手はゼロ(dead-read)だが
        // refreshMirror が scene #prevPos から re-mirror するため derive 必須（撤去後 None → World clobber 防止）。
        let withPrevPos = List.foldLeft((sc, d) ->
            EnemyScene.mapEnemy(d#id, e -> {prevPos = prevPosOf(EntityRef.Enemy(d#id), world) | e}, sc),
            withFollowUp, EnemyScene.getAll(scene));
        // 注: attackTargetId は syncTree で derive しない。combat 解決の同期キャリア（startAttack→attack:hit を
        // scene 経由で同期 thread）ゆえ dual-write 据置が正当。driver の anyAttacking は World 化済(F8-slice1)。
        // progress（level/exp）は player のみ。store key は player id。
        let withLevel = Map.foldLeftWithKey((sc, pid, lvl) ->
            PlayerScene.mapPlayer(pid, d -> {level = lvl | d}, sc), withPrevPos, w#playerLevel);
        Map.foldLeftWithKey((sc, pid, xp) ->
            PlayerScene.mapPlayer(pid, d -> {exp = xp | d}, sc), withLevel, w#playerExp)
}
