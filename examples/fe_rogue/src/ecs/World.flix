// World — シミュレーション状態を集約する不変 World。
//
// id 集合＋tick に加え、component store 群を持つ（時限効果 statuses ほか）。
// player/enemy は scene 上の id 空間が別なので、unified-id へ写して単一 store に統合する。
// World は gameLoop の末尾再帰に thread される。
// 道標: ルート ECS_WORKFLOW.md。

/// sim としての「誰のターンか」を表す 3-case の phase。
/// 現 19-case `TurnPhase.Phase`（メニュー遷移・演出待ち混在）は **sim-phase(これ) ＋ UiState.modalMode** に分解する。
/// World が TurnPhase.Phase を直接持つと循環依存（TurnPhase→World.Command）になるので、World 側はこの中立な
/// 3-case を持ち、19→3 の写像は境界（Game.flix `simPhaseOf`）で行う。
pub enum SimPhase with Eq, ToString {
    case PlayerTurn   // 味方ターン（カーソル/移動/メニュー/演出待ち = UiState.modalMode と anim-queue で細分）
    case EnemyTurn    // 敵ターン
    case GameOver     // 全滅モーダル
}

// combatView の base 戦闘値型 `BaseStats` と組立 `assembleView` は `Combat`（ecs/rules）に集約。
// World はそれを read-model として格納し（`baseStats`）、`combatViewOf` で `Combat.assembleView` を呼ぶ。

/// level-up 成長を World だけで解くための read-model（player-only・resource 由来）。
/// `base` = 現 resource の基準 9 ステータス（`LevelSystem.statsOf`）、`rates` = 成長率、`name` = 表示名
/// （LeveledUp の view パネル Result 用）。resolveCombat の level-up を World 完結にする（resource threading 不要）。
pub type alias Growth = {base = LevelSystem.Stats, rates = UnitCatalog.GrowthRates, name = String}

/// tween のチャンネル＝「何を」動かすかの**意味**（lib EcsTween は値の補間だけ知り、意味はここが持つ。
/// Bevy Lens の no-reflection 版）。複合キー `(EntityId, Channel)` で 1 entity が複数チャンネル同時可。
/// 増分（Alpha/Scale…）はこの enum と applyTweenOut の match を 1 arm 足すだけ（局所）。
pub enum Channel with Eq, Order {
    case Position   // renderPos（連続描画位置＝移動）
}

/// ダメージ数字ポップアップ fx の store エントリ（秒・実時間）。
/// `remaining` は stepWorld が毎フレーム dt 減算し 0 以下で drop。text/色/位置も store が
/// 持ち（view ノード全廃）、描画は `RenderWorld.renderPopups` が経過比率から上方向 float を導出する。
pub type alias PopupFx = { remaining = Float64, total = Float64, pos = Vec2.Vec2, text = String, color = Color }

/// 爆発 fx の store エントリ。位置/scale も store が持ち、経過比率からコマ番号を
/// `RenderWorld.renderExplosions` が導出する。
pub type alias ExplosionFx = { remaining = Float64, total = Float64, pos = Vec2.Vec2, scale = Float64 }

/// ユニットの再生中アニメ（AnimatedSprite2D の脱ノード化）。frame/frameProgress は保存せず、
/// `elapsed`（再生開始からの実時間秒・stepWorld が加算）から描画時に純関数で導出する
/// （ループ/コマ毎 duration 倍率込み＝engine advanceFrame と同値）。`Cmd.SetAnim` は
/// AnimatedSprite2D.play の意味論（同名=継続/別名=リセット）を再現する。
pub type alias UnitAnim = { name = String, elapsed = Float64 }

/// 1 フレームで移動（Position tween）した entity の marker 駆動情報（EntityRef＋補間 pixel）。
/// `stepWorld` が active∪done を返し、`RenderWorld.syncMarkers` が実 scene の marker を pos へ置く。
/// 同型 Vec2 の誤順を防ぐ名前渡し＋faction を EntityRef に閉じ込め（uid は plumbing 内で decode）。
pub type alias MarkerMove = { ref = World.EntityRef, pos = Vec2.Vec2 }

/// GPU タイルレイヤーの軽量描画ハンドル（静的・per-cell TileData 非保持）。scene の TileMapLayer ノード
/// から rebuild 時に bake し、毎フレーム camera 適用して engine `TileMapRenderCmd` に組む。フィールドは engine の
/// `TileMapRenderCmd`/`TileMapLayer` に一致（`tileVaoId`/`tileCount`）。`worldPos` は globalPositionAt（camera parity）。
pub type alias TileLayerHandle = {
    textureName = String, tileSize = Float64, worldPos = Vec2.Vec2,
    color = Color, zIndex = Int32, tileVaoId = Int32, tileCount = Int32
}

pub enum World {
    case World({ tick = Int32,
                 // turn FSM の World mirror（dual・read-model）。権威は当面 TurnPhase.State。
                 turnPhase = SimPhase,
                 playerIds = Set[EntityId], enemyIds  = Set[EntityId],
                 // unified-id → `Faction` enum。faction 判定は id 演算（uid>=base）
                 // でなく **この enum タグ `teamOf` で読む**（Bevy の Team component 相当）。
                 team = Map[EntityId, Faction],
                 // statusEffects も単一 store（unified-id）。
                 statusEffects = Map[EntityId, StatusSystem.StatusEffects],
                 // hp の read-model（query/セーブ/決定論テスト用）。
                 // hp は単一 store（player uid=id / enemy uid=id+base）。
                 hp = Map[EntityId, Int32],
                 // weapons の command-derive store（hp 同型・preserve+prune）。player は weapons(List)
                 // をそのまま、enemy は単数 weapon(Option) を 0/1 要素 List に射影。reader flip はしない
                 // （combatView/unitView は scene #weapons を読む）＝挙動不変。全 weapon 書込が `Cmd.SetWeapons`
                 // を dual-write し `[WEAPONS DIFF]` で完備性を検証可能にする。
                 weapons = Map[EntityId, List[UnitCatalog.WeaponResource]],
                 // staves/consumables/rings の command-derive store（weapons 同型・player-only・preserve+prune）。
                 // 敵は杖/薬/指輪インベントリを持たない（EnemyData に該当 field なし）ので store も player id keyed。
                 // reader flip はしない（各メニューは scene #staves/#consumables/#rings を読む）＝挙動不変。
                 // 全 staves/consumables/rings 書込が `Cmd.SetStaves/SetConsumables/SetRings` を dual-write し
                 // `[STAVES/CONSUMABLES/RINGS DIFF]` で完備性を検証可能にする。
                 staves = Map[EntityId, List[Staff.StaffResource]],
                 consumables = Map[EntityId, List[Consumable.ConsumableResource]],
                 rings = Map[EntityId, List[Ring.RingResource]],
                 // ringEquipped の command-derive Bool store（waited 同型・player-only）。装備指輪の効果発動フラグ。
                 ringEquipped = Map[EntityId, Bool],
                 // 位置 store。型は Vec2i の structural record（engine_core.Vec2i の演算 API 対象）。
                 // pos は単一 store（unified-id・`Cmd.Move` 権威）。
                 pos = Map[EntityId, {x = Int32, y = Int32}],
                 // 連続的な描画位置（pixel・tween 込み）。render System(renderUnits)が読む。command-derive。
                 //   静止時は最後の値（セル pixel）を保持。move で moveAnim が補間更新（stepWorld）。
                 renderPos = Map[EntityId, Vec2.Vec2],
                 // 進行中の tween（複合キー (EntityId, Channel)）。stepWorld が毎フレ実時間 dt(秒) 進め、
                 //   出力を対象 component（Position→renderPos）へ書く。完了で除去。**実時間ベース**（engine tween と
                 //   同じ dt で進む＝lockstep 同期・fps 非依存）。1 entity が複数チャンネルを同時に持てる。
                 tweens = EcsTween.Tweens[EntityId, Channel],
                 // 描画 view 状態の store（全て command/step 由来・
                 // preserve＋validUids prune）。unitAnim=再生アニメ（player の AnimatedSprite2D 個体のみ・
                 // elapsed は stepWorld が加算）、unitFlipH=左右反転（移動 view 再生が書く）、
                 // unitModulate=待機/行動済み暗転（本体/HP バー/武器アイコンの 3 読者の単一真実源）、
                 // dyingElapsed=死亡点滅の経過秒（SetDying で 0 seed・alpha は描画時に曲線導出）。
                 unitAnim = Map[EntityId, UnitAnim],
                 unitFlipH = Map[EntityId, Bool],
                 unitModulate = Map[EntityId, Color],
                 dyingElapsed = Map[EntityId, Float64],
                 // 盤面除外（集合・階段退場）中の味方 id。Board.pieces は hidden 味方を除くので fromWorld に必要。
                 playerHidden = Set[EntityId],
                 // 敵の検知フラグ（dormant→chase）。
                 enemyAlerted = Map[EntityId, Bool],
                 // 敵の行動済みフラグ（ターン flow・view 灰色の権威）。enemy-only。faction-blind tick の前提。
                 enemyActed = Map[EntityId, Bool],
                 // 死亡演出中の敵 id（death_blink 中＝全 LOGIC から除外される sim フラグ）。
                 // present=isDying。death 完了でノード除去→refreshMirror が prune（absence=非 dying）。
                 enemyDying = Set[EntityId],
                 // 敵の瓶使用済みフラグ（1ターン1投の sticky）。
                 enemyBottleUsed = Map[EntityId, Bool],
                 // 敵の直前位置（wander の戻り防止）。None=未移動はマップ非在で表現。
                 enemyPrevPos = Map[EntityId, {x = Int32, y = Int32}],
                 // followUp 使用済み（1 攻撃 1 追撃の per-turn transient）。両 faction。
                 // followUpUsed は単一 store（unified-id・両 faction）。
                 followUpUsed = Map[EntityId, Bool],
                 // 味方の行動済み（ターン flow の権威）。player-only。
                 playerWaited = Map[EntityId, Bool],
                 // 味方の階段退場フラグ（フロア終了条件・tick gating の権威）。player-only。
                 playerUsedStairs = Map[EntityId, Bool],
                 // 攻撃対象 id（攻撃モーション中＝anyAttacking の権威）。None=非攻撃はマップ非在。両 faction。
                 // attackTarget は単一 store（unified-id・両 faction）。
                 attackTarget = Map[EntityId, Int32],
                 // 味方の進行度（level/exp）。combat の撃破→exp→level-up が動かす sim 状態。
                 // dual-write の漏れは検証器で捕える。player-only。
                 playerLevel = Map[EntityId, Int32], playerExp = Map[EntityId, Int32],
                 // base 戦闘値 + maxHp の read-model（unified-id・両 faction）。resource 由来ゆえ
                 // refreshMirror で毎フレーム scene から再 mirror（statusEffects と同型）。combatView flip 用。
                 baseStats = Map[EntityId, Combat.BaseStats],
                 // 装備武器の戦闘投影 read-model（unified-id・両 faction）。内側 Option=武器なし。
                 // PlayerScene/EnemyScene.equippedWeaponView 由来ゆえ毎フレーム再 mirror。combatView flip 用。
                 weaponView = Map[EntityId, Option[Combat.WeaponView]],
                 // 装備指輪ボーナス read-model（unified-id・両 faction）。未装備は zeroBonuses。
                 // equippedRingBonus 由来ゆえ毎フレーム再 mirror。combatView flip 用。
                 ringBonus = Map[EntityId, Ring.Bonuses],
                 // 基礎移動力 moveTiles の store（unified-id・両 faction）。resource 由来で spawn 後不変＝
                 // 実効移動力は effectiveMoveTilesOf が encumbrance を読み時計算（base のみ保持）。
                 moveTiles = Map[EntityId, Int32],
                 // 装備指輪リソース本体の read-model（unified-id・両 faction）。
                 // ringBonus はステ補正だけを持つが、finisher/lifesteal は RingResource（effect/power）を要する。
                 // weaponView と同じ Option-store パターン（内側 Option=未装備）＝毎フレーム再 mirror。
                 equippedRing = Map[EntityId, Option[Ring.RingResource]],
                 // level-up 成長に要る resource 由来データ（基準 Stats + 成長率）。
                 // player-only・resource 由来ゆえ毎フレーム再 mirror。resolveCombat の level-up を World 完結に。
                 growth = Map[EntityId, Growth],
                 // 静的地形スナップショット（プレーンな type-alias＝storable）。
                 // ノックバックの着地計算が要する `boardOf` の地形ソース。empty()=None（シーン未確定）。
                 // syncFromScene/refreshMirror で `BoardSnapshot.mapSnapshotOf(scene)` を再 mirror（toBoard と同源）。
                 mapSnapshot = Option[MapSnapshot],
                 // 階段セル座標の read-model（None=未配置）。`Stairs.getPos(scene)`
                 // 由来＝mapSnapshot と同じ scene-derive 毎フレーム再 mirror。Stopgap の warp 先計算（`warpCellFor`）が読む。
                 stairsPos = Option[{x = Int32, y = Int32}],
                 // 宝箱の read/write-model。セル key（`chestCellKey`）→ 宝箱 Data。
                 // spawn（`Cmd.SpawnChest`）/開封（`Cmd.RemoveChest`）が動かす＝存在は component（Map 在/不在）で表現。
                 // syncFromScene で frame-1 seed（Chests.getAll）、refreshMirror は command 由来を preserve＋
                 // scene 在セルで prune（unit の pos と同型・floor 遷移で旧フロア分が自動 prune される）。
                 chests = Map[Int32, Chests.Data],
                 // 床アイテムの read/write-model。セル key（`cellKey`）→ GroundItem Data。
                 // spawn（`Cmd.SpawnItem`）/拾得（`Cmd.RemoveItem`）が動かす＝存在は component（Map 在/不在）で表現。
                 // `elapsed`（点滅位相）は view 専用ゆえ store の値は spawn 時のスナップショット（World reader は読まない）。
                 // 3-builder は chests と同型（seed=itemsFromScene／preserve＋scene 在セルで prune）。
                 groundItems = Map[Int32, GroundItems.Data],
                 // fx の寿命 store。spawn は `Cmd.SpawnPopupFx/SpawnExplosionFx`
                 // （applyCmd が nextSeq で採番し +1）、寿命 tick と期限切れ drop は stepWorld（EcsTween と同じ
                 // 「stepWorld が World を直接進める」前例）。scene の子 Label2D/Sprite2D は描画 view で、
                 // gameLoop が `DamagePopupFx.syncView`/`ExplosionFx.syncView` で store から派生する。
                 // 3-builder は command/step 由来ゆえ preserve（scene mirror 元なし・~0.7s 寿命の transient なので
                 // floor 遷移で残っても自然 expire＝prune 不要）。
                 popupFx = Map[Int32, PopupFx], popupFxNextSeq = Int32,
                 explosionFx = Map[Int32, ExplosionFx], explosionFxNextSeq = Int32,
                 // 背景 map タイルの描画ハンドル（floor+walls 層・静的）。rebuild イベント（tileGen 変化）で
                 // bake し、render System が camera 適用して instanced 描画。scene TileMapLayer ノードは衝突用に存続。
                 tileLayers = List[TileLayerHandle],
                 // マップ再構築の世代カウンタ。build choke（buildPlayingScene/rebuildFloorFromSnapshot）が
                 // `Cmd.BumpTileGen` で +1。gameLoop は world1 と incoming world の gen を比べ、変化時のみ tileLayers を bake。
                 tileGen = Int32,
                 // 敵特殊能力 effectRule の生 Json read-model（unified-id）。
                 // 内側 Option=ルールなし。enemy `#resource#effectRule`（Option[Json]）由来＝weaponView と同じ
                 // Option-store パターン（accessor が flatten）＝毎フレーム再 mirror。敵パスの sim 発火判定が読む。
                 effectRule = Map[EntityId, Option[Util.Json.Json]],
                 // 敵ターン driver が読む phase-banner 同期 bool（TopBar が毎フレーム dual-write）。
                 //   enemyTurnBusy      — 敵ターン開始 intro の hold 中（>0）＝敵の行動開始待ち。
                 //   phaseObservedEnemy — 上部バーが「敵ターン」を観測済み（0 体ターンの取りこぼし防止）。
                 // どちらも view-timing 由来だが driver の順序非依存化のため World 経由で読む（生アニメ Data は TopBar 残置）。
                 enemyTurnBusy = Bool, phaseObservedEnemy = Bool,
                 // 決定論的 PRNG 状態。live パスでは DORMANT（live ハンドラは
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
                     renderPos = Map.empty(), tweens = Map.empty(),
                     unitAnim = Map.empty(), unitFlipH = Map.empty(),
                     unitModulate = Map.empty(), dyingElapsed = Map.empty(),
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
                     stairsPos = None,
                     chests = Map.empty(),
                     groundItems = Map.empty(),
                     popupFx = Map.empty(), popupFxNextSeq = 0,
                     explosionFx = Map.empty(), explosionFxNextSeq = 0,
                     tileLayers = Nil, tileGen = 0,
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
            renderPos = Map.empty(), tweens = Map.empty(),  // B/m2: World-native（spawn の SetRenderPos で seed）
            // P6-1h: 描画 view store は command/step 由来＝preserve（spawn emit が seed）。
            unitAnim = w#unitAnim, unitFlipH = w#unitFlipH,
            unitModulate = w#unitModulate, dyingElapsed = w#dyingElapsed,
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
            // P3-a: stairsPos は frame-1 seed だけ scene の Stairs ノードから読む（hp と同型）。以後は
            // refreshMirror が placeAt の `Cmd.SetStairs` を preserve＝World 権威。
            stairsPos = Stairs.getPos(scene),
            // P6-1d: chests は scene ノード撤去に伴い純 command 由来（SpawnChest/RemoveChest/ClearChests）＝
            // sync パスでも preserve（seed は build choke の Spawn emit が担う）。
            chests = w#chests,
            // P6-1e: production はノードを積まないため常に空＝実質 preserve と同義。手組み
            // GroundItem ノードで World を seed するテスト seam（stairs の getPos seed と同型）として残置。
            groundItems = itemsFromScene(scene),
            // P5-b: fx は command/step 由来＝preserve（scene mirror 元なし・transient）。
            popupFx = w#popupFx, popupFxNextSeq = w#popupFxNextSeq,
            explosionFx = w#explosionFx, explosionFxNextSeq = w#explosionFxNextSeq,
            // B/tiles: tileLayers/tileGen は command-derive（BumpTileGen/setTileLayers）＝preserve（frame-1 は空/0 を carry）。
            tileLayers = w#tileLayers, tileGen = w#tileGen,
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
    /// P6-2c: **縮退版**。全 store が command 権威（spawn/despawn/build choke の Cmd が唯一の書込・
    /// prune は Despawn/ClearUnits が代替）になり、scene からの derive/prune は消滅した。
    /// 残る仕事は frame カウンタだけ（scene 引数も撤去）。旧 derive 7 系の行き先:
    ///   ids/team=Cmd.Spawn ／ hidden=Cmd.SetHidden ／ 敵 ring=Cmd.SetEnemyRing ／ growth=Cmd.SetGrowth
    ///   ／ mapSnapshot=Cmd.SetMapSnapshot ／ effectRule=Cmd.SetEffectRule ／ player 側 equippedRing=accessor 導出。
    pub def refreshMirror(world: World): World =
        let World.World(w) = world;
        World.World({tick = w#tick + 1 | w})

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
    pub def stepWorld(world: World, dt: Float64): (World, List[MarkerMove]) =
        let World.World(w) = world;
        let (nextTweens, outs, _done) = EcsTween.step(dt, w#tweens);
        // tweens を更新後、各補間出力をチャンネル別に対象 component へ書く。
        // P5-b: fx（ダメージ数字/爆発）の寿命もここで tick（remaining -= dt・0 以下で drop）。
        // tween と同じ「stepWorld が World を直接進める」lane＝per-frame Cmd を出さない。
        let stepped = List.foldLeft((acc, pair) -> {
            let ((uid, ch), out) = pair;
            applyTweenOut(uid, ch, out, acc)
        }, World.World({tweens = nextTweens,
                        popupFx = tickFxMap(dt, w#popupFx),
                        explosionFx = tickFxMap(dt, w#explosionFx),
                        // P6-1e: 床アイテムの点滅位相（elapsed）も World が tick（fx と同じ lane・
                        // 旧 GroundItems.step の per-node 更新を置換）。
                        groundItems = Map.map(d ->
                            {elapsed = GroundItems.advance(Duration.add(d#elapsed, Duration.seconds(dt))) | d},
                            w#groundItems),
                        // P6-1h: ユニットアニメの再生経過と死亡点滅経過も World が tick
                        // （frame/alpha は描画時に elapsed から純関数で導出）。
                        unitAnim = Map.map(a -> {elapsed = a#elapsed + dt | a}, w#unitAnim),
                        dyingElapsed = Map.map(e -> e + dt, w#dyingElapsed) | w}), outs);
        // marker 駆動用に Position チャンネルの補間結果を EntityRef＋pixel で外へ出す。
        // outs は active に加え**完了フレームの target（t=1.0 スナップ）も含む**（EcsTween.step）＝
        // 完了の取りこぼしなく marker を target に確定できる（isAnimating 単独では落とす）。
        let moved = outs |> List.filterMap(pair -> {
            let ((uid, ch), out) = pair;
            match (ch, out) {
                case (Channel.Position, EcsTween.Out.VecOut(v)) => Some({ref = uidToRef(uid), pos = v})
                case _ => None
            }
        });
        (stepped, moved)

    /// P5-b: fx 寿命 map を dt（秒）ぶん進め、期限切れ（remaining <= 0）を落とす。
    /// PopupFx/ExplosionFx 共用（row-poly・remaining だけ触る）。
    def tickFxMap(dt: Float64, fx: Map[Int32, {remaining = Float64 | r}]):
            Map[Int32, {remaining = Float64 | r}] =
        Map.foldLeftWithKey((acc, seq, d) -> {
            let r = d#remaining - dt;
            if (r <= 0.0) acc else Map.insert(seq, {remaining = r | d}, acc)
        }, Map.empty(), fx)

    /// B/m2: tween の補間出力をチャンネル別に対象 component へ書く（Position→renderPos）。
    /// 不能組（Position に Scalar 等）は smart constructor 経路ゆえ設計上ありえない＝loud に bug!。
    /// チャンネル増分（Alpha/Scale…）はここに 1 arm 足すだけ。
    def applyTweenOut(uid: EntityId, ch: Channel, out: EcsTween.Out, world: World): World =
        let World.World(w) = world;
        match (ch, out) {
            case (Channel.Position, EcsTween.Out.VecOut(v)) =>
                World.World({renderPos = Map.insert(uid, v, w#renderPos) | w})
            case _ => bug!("EcsTween: impossible (channel, out) combo")
        }

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
        case StartTween(EntityRef, Channel, EcsTween.Track, Float64, EcsTween.Easing, Bool)  // B/m2: (entity,channel) tween を dur 秒で開始
        case SetAttackTarget(EntityRef, Int32) // F8-slice1: 攻撃対象 id をセット（攻撃開始）
        case ClearAttackTarget(EntityRef)      // F8-slice1: 攻撃対象をクリア（攻撃終了）
        case SetProgress(EntityRef, Int32, Int32) // World 拡張: 味方の (level, exp) write（撃破/レベルアップ/復元で）
        case SetEnemyTurnBusy(Bool)            // F8-slice2: 敵ターン intro hold 中 bool write（TopBar dual-write）
        case SetPhaseObservedEnemy(Bool)       // F8-slice2: バーが敵ターン観測済み bool write（TopBar dual-write）
        case BumpTileGen                       // B/tiles: マップ再構築の世代 +1（build choke が emit・gameLoop の tile bake トリガ）
        case SetStairs(Option[{x = Int32, y = Int32}])  // P3-a: 階段セル write（配置=Some/未配置=None・floor 単位で 1 回）。stairsPos を World 権威化
        case SpawnChest(Chests.Data)   // P3-b: 宝箱を配置（build/復元）。cell key で chests へ挿入（存在=Map 在）
        case ClearChests                   // P6-1d: フロア再構築時に前フロアの宝箱を全消去（build choke が emit。旧: scene 再構築による prune）
        case RemoveChest({x = Int32, y = Int32})  // P3-b: 宝箱を開封して除去（cell key で chests から削除）
        case SpawnItem(GroundItems.Data)     // P3-c: 床アイテムを配置（build/復元/respawn/drop）。cell key で groundItems へ挿入
        case RemoveItem({x = Int32, y = Int32})   // P3-c: 床アイテムを拾得して除去（cell key で groundItems から削除）
        case ClearItems                    // P6-1e: フロア再構築時に前フロアの床アイテムを全消去（ClearChests と同型）
        case Spawn(EntityRef)                  // P6-2c: id 集合/team へ登録（spawn funnel 冒頭で emit）
        case Despawn(EntityRef)                // P6-2c: 全 per-entity store から除去（旧 refreshMirror prune の代替）
        case ClearUnits                        // P6-2c: 全ユニット store 一掃（build choke の頭で emit・ClearChests と同型）
        case SetHidden(EntityRef, Bool)        // P6-2c: 階段退場フラグ（playerHidden・旧 scene derive の代替）
        case SetEnemyRing(Int32, Option[Ring.RingResource])   // P6-2c: 敵の装備指輪（spawn/復元/指輪変化で emit）
        case SetGrowth(Int32, Growth)          // P6-2c: 成長 read-model（resource 変化サイト=SetBaseStats と同所で emit）
        case SetMapSnapshot(Option[MapSnapshot])               // P6-2c: 地形 read-model（floor build choke で emit・Title は None）
        case SetEffectRule(Int32, Option[Util.Json.Json])      // P6-2c: 敵 effectRule（spawn で emit・以後不変）
        case SetAnim(EntityRef, String)        // P6-1h: 再生アニメ切替（play 意味論=同名継続/別名リセット）
        case SetFlipH(EntityRef, Bool)         // P6-1h: 左右反転（移動 view 再生が書く）
        case SetModulate(EntityRef, Color)     // P6-1h: 待機/行動済み暗転色（本体/バー/アイコン共通）
        case SpawnPopupFx({total = Float64, pos = Vec2.Vec2, text = String, color = Color})  // P5-b/P6-1f: ダメージ数字 fx を spawn（remaining=total で開始・見た目も store 持ち）
        case SpawnExplosionFx({total = Float64, pos = Vec2.Vec2, scale = Float64})            // P5-b/P6-1f: 爆発 fx を spawn
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
    /// CombatDriver の `rollPercent` がこの op だけを呼ぶ＝draw 順序は呼び出し位置がそのまま決める。
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
    /// P6-2c: 1 entity を全 per-entity store から取り除く（`Cmd.Despawn` の実体＝旧 refreshMirror prune の
    /// 個別版）。ノード除去サイト（死亡完了/戦死/引き継ぎ剪定）が emit する。
    def despawnUid(ref: EntityRef, world: World): World =
        let World.World(w) = world;
        let uid = toUid(ref);
        let (pIds, eIds) = match ref {
            case EntityRef.Player(id) => (Set.remove(id, w#playerIds), w#enemyIds)
            case EntityRef.Enemy(id)  => (w#playerIds, Set.remove(id, w#enemyIds))
        };
        World.World({
            playerIds = pIds, enemyIds = eIds,
            team = Map.remove(uid, w#team),
            statusEffects = Map.remove(uid, w#statusEffects),
            hp = Map.remove(uid, w#hp),
            weapons = Map.remove(uid, w#weapons),
            staves = Map.remove(uid, w#staves),
            consumables = Map.remove(uid, w#consumables),
            rings = Map.remove(uid, w#rings),
            ringEquipped = Map.remove(uid, w#ringEquipped),
            pos = Map.remove(uid, w#pos),
            renderPos = Map.remove(uid, w#renderPos),
            tweens = Map.filterWithKey((key, _) -> fst(key) != uid, w#tweens),
            unitAnim = Map.remove(uid, w#unitAnim),
            unitFlipH = Map.remove(uid, w#unitFlipH),
            unitModulate = Map.remove(uid, w#unitModulate),
            dyingElapsed = Map.remove(uid, w#dyingElapsed),
            playerHidden = Set.remove(uid, w#playerHidden),
            enemyDying = Set.remove(uid, w#enemyDying),
            enemyAlerted = Map.remove(uid, w#enemyAlerted),
            enemyActed = Map.remove(uid, w#enemyActed),
            enemyBottleUsed = Map.remove(uid, w#enemyBottleUsed),
            enemyPrevPos = Map.remove(uid, w#enemyPrevPos),
            followUpUsed = Map.remove(uid, w#followUpUsed),
            playerWaited = Map.remove(uid, w#playerWaited),
            playerUsedStairs = Map.remove(uid, w#playerUsedStairs),
            playerLevel = Map.remove(uid, w#playerLevel),
            playerExp = Map.remove(uid, w#playerExp),
            baseStats = Map.remove(uid, w#baseStats),
            weaponView = Map.remove(uid, w#weaponView),
            ringBonus = Map.remove(uid, w#ringBonus),
            moveTiles = Map.remove(uid, w#moveTiles),
            equippedRing = Map.remove(uid, w#equippedRing),
            growth = Map.remove(uid, w#growth),
            effectRule = Map.remove(uid, w#effectRule),
            attackTarget = Map.remove(uid, w#attackTarget)
            | w})

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
                // P6-2b: 旧位置を prevPos に自動記録（両 faction）。従来は敵の view 再生が move 後に
                // scene の pre-move gridPos を読んで SetPrevPos していたが、gridPos twin 退役に伴い
                // sim 側（ここ）で完結させる。Cmd 列は不変（新 Cmd を増やさない）。初回 Move（spawn seed）は
                // 旧位置が無いので記録しない（従来も spawn では SetPrevPos されない）。
                let World.World(w) = world;
                let prevs = match Map.get(toUid(ref), w#pos) {
                    case Some(old) => Map.insert(toUid(ref), old, w#enemyPrevPos)
                    case None      => w#enemyPrevPos
                };
                World.World({pos = Map.insert(toUid(ref), pos, w#pos),
                             enemyPrevPos = prevs | w})
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
                    // P6-1h: 死亡点滅の経過秒も 0 で seed（stepWorld が加算・alpha は描画時に曲線導出）。
                    case EntityRef.Enemy(id)  => World.World({enemyDying = Set.insert(enemyUid(id), w#enemyDying),
                                                              dyingElapsed = Map.insert(enemyUid(id), 0.0, w#dyingElapsed) | w})
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
                // B/m2: 描画位置を直接 set（進行中の Position tween は破棄）。spawn seed / 瞬間移動用。
                let World.World(w) = world;
                let uid = toUid(ref);
                World.World({renderPos = Map.insert(uid, p, w#renderPos),
                             tweens = Map.remove((uid, Channel.Position), w#tweens) | w})
            case Cmd.StartTween(ref, ch, track, dur, easing, yoyo) =>
                // B/m2: (entity, channel) tween を開始。Position は renderPos を即 src にスナップ（補間初期値）。
                let World.World(w) = world;
                let uid = toUid(ref);
                let nextTweens = EcsTween.start((uid, ch), track, dur, easing, yoyo, w#tweens);
                let nextRenderPos = match (ch, track) {
                    case (Channel.Position, EcsTween.Track.Vec(vl)) => Map.insert(uid, vl#start, w#renderPos)
                    case _                                          => w#renderPos
                };
                World.World({tweens = nextTweens, renderPos = nextRenderPos | w})
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
            case Cmd.BumpTileGen =>
                // B/tiles: マップ再構築の世代 +1。build choke（buildPlayingScene/rebuildFloorFromSnapshot）が emit し、
                // gameLoop が world1 と incoming world の gen 差でタイル bake を判定する。
                let World.World(w) = world; World.World({tileGen = w#tileGen + 1 | w})
            case Cmd.SetStairs(cell) =>
                // P3-a: 階段セルを World 権威に write（placeAt が emit）。floor 単位で 1 回・未配置は None。
                let World.World(w) = world; World.World({stairsPos = cell | w})
            case Cmd.SpawnChest(data) =>
                // P3-b: 宝箱を cell key で挿入（addOneChest が emit）。存在は Map 在で表現。
                let World.World(w) = world;
                World.World({chests = Map.insert(chestCellKey(data#gridPos), data, w#chests) | w})
            case Cmd.RemoveChest(cell) =>
                // P3-b: 宝箱を開封して除去（takeAt が emit）。存在の消失は Map 不在で表現。
                let World.World(w) = world;
                World.World({chests = Map.remove(chestCellKey(cell), w#chests) | w})
            case Cmd.ClearChests =>
                // P6-1d: フロア再構築の頭で全消去（scene ノード撤去に伴い refreshMirror の prune が消えたため、
                // 旧フロア分の掃除は build choke の明示 Cmd が担う）。
                let World.World(w) = world;
                World.World({chests = Map.empty() | w})
            case Cmd.ClearItems =>
                // P6-1e: ClearChests と同型（床アイテムの掃除）。
                let World.World(w) = world;
                World.World({groundItems = Map.empty() | w})
            case Cmd.SpawnItem(data) =>
                // P3-c: 床アイテムを cell key で挿入（addOneItem が emit）。存在は Map 在で表現。
                let World.World(w) = world;
                World.World({groundItems = Map.insert(cellKey(data#gridPos), data, w#groundItems) | w})
            case Cmd.RemoveItem(cell) =>
                // P3-c: 床アイテムを拾得して除去（takeAt が emit）。存在の消失は Map 不在で表現。
                let World.World(w) = world;
                World.World({groundItems = Map.remove(cellKey(cell), w#groundItems) | w})
            case Cmd.Spawn(ref) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({playerIds = Set.insert(id, w#playerIds),
                                                              team = Map.insert(id, Faction.Player, w#team) | w})
                    case EntityRef.Enemy(id)  => World.World({enemyIds = Set.insert(id, w#enemyIds),
                                                              team = Map.insert(enemyUid(id), Faction.Enemy, w#team) | w})
                }
            case Cmd.Despawn(ref) =>
                despawnUid(ref, world)
            case Cmd.ClearUnits =>
                // 全ユニット store を空へ（非ユニット store〔stairs/chests/items/fx/tiles/map/rng/phase 等〕は保持）。
                let World.World(w) = world;
                World.World({playerIds = Set.empty(), enemyIds = Set.empty(), team = Map.empty(),
                             statusEffects = Map.empty(), hp = Map.empty(), weapons = Map.empty(),
                             staves = Map.empty(), consumables = Map.empty(), rings = Map.empty(),
                             ringEquipped = Map.empty(), pos = Map.empty(), renderPos = Map.empty(),
                             tweens = Map.empty(), unitAnim = Map.empty(), unitFlipH = Map.empty(),
                             unitModulate = Map.empty(), dyingElapsed = Map.empty(),
                             playerHidden = Set.empty(), enemyDying = Set.empty(),
                             enemyAlerted = Map.empty(), enemyActed = Map.empty(),
                             enemyBottleUsed = Map.empty(), enemyPrevPos = Map.empty(),
                             followUpUsed = Map.empty(), playerWaited = Map.empty(),
                             playerUsedStairs = Map.empty(), playerLevel = Map.empty(),
                             playerExp = Map.empty(), baseStats = Map.empty(), weaponView = Map.empty(),
                             ringBonus = Map.empty(), moveTiles = Map.empty(), equippedRing = Map.empty(),
                             growth = Map.empty(), effectRule = Map.empty(), attackTarget = Map.empty() | w})
            case Cmd.SetHidden(ref, b) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) =>
                        let next = if (b) Set.insert(id, w#playerHidden) else Set.remove(id, w#playerHidden);
                        World.World({playerHidden = next | w})
                    case EntityRef.Enemy(_) => world   // 敵に hidden は無い（防御 no-op）
                }
            case Cmd.SetEnemyRing(id, ring) =>
                let World.World(w) = world;
                World.World({equippedRing = Map.insert(enemyUid(id), ring, w#equippedRing) | w})
            case Cmd.SetGrowth(id, g) =>
                let World.World(w) = world;
                World.World({growth = Map.insert(id, g, w#growth) | w})
            case Cmd.SetMapSnapshot(mOpt) =>
                let World.World(w) = world;
                World.World({mapSnapshot = mOpt | w})
            case Cmd.SetEffectRule(id, rule) =>
                let World.World(w) = world;
                World.World({effectRule = Map.insert(enemyUid(id), rule, w#effectRule) | w})
            case Cmd.SetAnim(ref, name) =>
                // P6-1h: AnimatedSprite2D.play 意味論＝同名なら elapsed 継続、別名なら 0 リセット。
                let World.World(w) = world;
                let uid = toUid(ref);
                let next = match Map.get(uid, w#unitAnim) {
                    case Some(e) => if (e#name == name) e else {name = name, elapsed = 0.0}
                    case None    => {name = name, elapsed = 0.0}
                };
                World.World({unitAnim = Map.insert(uid, next, w#unitAnim) | w})
            case Cmd.SetFlipH(ref, b) =>
                let World.World(w) = world;
                World.World({unitFlipH = Map.insert(toUid(ref), b, w#unitFlipH) | w})
            case Cmd.SetModulate(ref, c) =>
                let World.World(w) = world;
                World.World({unitModulate = Map.insert(toUid(ref), c, w#unitModulate) | w})
            case Cmd.SpawnPopupFx(d) =>
                // P5-b: nextSeq で採番して挿入し +1。期限切れ drop は stepWorld（Cmd 不要）。
                let World.World(w) = world;
                let seq = w#popupFxNextSeq;
                World.World({popupFx = Map.insert(seq,
                                 {remaining = d#total, total = d#total, pos = d#pos,
                                  text = d#text, color = d#color}, w#popupFx),
                             popupFxNextSeq = seq + 1 | w})
            case Cmd.SpawnExplosionFx(d) =>
                // P5-b: popupFx と同型（採番して挿入し +1）。
                let World.World(w) = world;
                let seq = w#explosionFxNextSeq;
                World.World({explosionFx = Map.insert(seq,
                                 {remaining = d#total, total = d#total, pos = d#pos, scale = d#scale},
                                 w#explosionFx),
                             explosionFxNextSeq = seq + 1 | w})
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
            case Cmd.StartTween(ref, _, _, _, _, _) => ("StartTween", toUid(ref), 0, 0)
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
            case Cmd.BumpTileGen              => ("BumpTileGen", 0, 0, 0)
            case Cmd.SetStairs(cell)          =>
                let (x, y) = Option.map(p -> (p#x, p#y), cell) |> Option.getWithDefault((-1, -1));
                ("SetStairs", x, y, 0)
            case Cmd.SpawnChest(data)         => ("SpawnChest", data#gridPos#x, data#gridPos#y, 0)
            case Cmd.RemoveChest(cell)        => ("RemoveChest", cell#x, cell#y, 0)
            case Cmd.ClearChests              => ("ClearChests", 0, 0, 0)
            case Cmd.ClearItems               => ("ClearItems", 0, 0, 0)
            case Cmd.SpawnItem(data)          => ("SpawnItem", data#gridPos#x, data#gridPos#y, 0)
            case Cmd.RemoveItem(cell)         => ("RemoveItem", cell#x, cell#y, 0)
            case Cmd.Spawn(ref)               => ("Spawn", toUid(ref), 0, 0)
            case Cmd.Despawn(ref)             => ("Despawn", toUid(ref), 0, 0)
            case Cmd.ClearUnits               => ("ClearUnits", 0, 0, 0)
            case Cmd.SetHidden(ref, b)        => ("SetHidden", toUid(ref), if (b) 1 else 0, 0)
            case Cmd.SetEnemyRing(id, r)      => ("SetEnemyRing", enemyUid(id), if (Option.isEmpty(r)) 0 else 1, 0)
            case Cmd.SetGrowth(id, g)         => ("SetGrowth", id, g#base#hp, 0)
            case Cmd.SetMapSnapshot(m)        => ("SetMapSnapshot", if (Option.isEmpty(m)) 0 else 1, 0, 0)
            case Cmd.SetEffectRule(id, r)     => ("SetEffectRule", enemyUid(id), if (Option.isEmpty(r)) 0 else 1, 0)
            case Cmd.SetAnim(ref, name)       => ("SetAnim(${name})", toUid(ref), 0, 0)
            case Cmd.SetFlipH(ref, b)         => ("SetFlipH", toUid(ref), if (b) 1 else 0, 0)
            case Cmd.SetModulate(ref, col)    => ("SetModulate", toUid(ref),
                                                   Float64.truncateToInt32(Float32.toFloat64(col#r) * 255.0), 0)
            case Cmd.SpawnPopupFx(d)          => ("SpawnPopupFx", Float64.truncateToInt32(d#pos#x), Float64.truncateToInt32(d#pos#y), 0)
            case Cmd.SpawnExplosionFx(d)      => ("SpawnExplosionFx", Float64.truncateToInt32(d#pos#x), Float64.truncateToInt32(d#pos#y), 0)
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

    /// B/m2: 当該 entity が移動（Position）tween 中か（isMoving の World 版・input gate 用）。
    pub def isAnimating(ref: EntityRef, world: World): Bool =
        let World.World(w) = world; EcsTween.isActive((toUid(ref), Channel.Position), w#tweens)

    /// B/m2: faction-blind な「移動」の唯一の発行口（smart constructor）。Position チャンネルへ span(start→target)
    /// の Vec tween を sec 秒・Linear で開始する Cmd を emit。味方 `PlayerScene.moveTo` と敵
    /// `EnemyScene.replayEnemyMoveView` が**共にこれを呼ぶ**（個別実装を畳む）。同型 Vec2 の誤順を防ぐため
    /// span は `VecLerp`（Track.Vec の payload）で名前渡し。不整合な (Channel, Track) を構築させない seam。
    /// Phase 2 で engine `Tween.tweenPosition` を退役しこれ 1 本に統一。
    pub def moveUnit(ref: EntityRef, span: EcsTween.VecLerp, sec: Float64): Unit \ Command =
        Command.emit(Cmd.StartTween(ref, Channel.Position, EcsTween.Track.Vec(span), sec, EcsTween.Easing.Linear, false))

    /// B/tiles: マップ再構築の世代（gameLoop の tile bake トリガ比較用）。
    pub def tileGenOf(world: World): Int32 =
        let World.World(w) = world; w#tileGen

    /// B/tiles: 背景 map タイルの描画ハンドル（render System が読む）。
    pub def tileLayersOf(world: World): List[TileLayerHandle] =
        let World.World(w) = world; w#tileLayers

    /// B/tiles: bake したタイルハンドルを World にセット（rebuild〔tileGen 変化〕時に gameLoop が呼ぶ）。
    pub def setTileLayers(handles: List[TileLayerHandle], world: World): World =
        let World.World(w) = world; World.World({tileLayers = handles | w})

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

    /// P2-S2: coord 上の「瀕死でない」敵 id を World から引く（`EnemyScene.findIdAt` の World 版）。
    /// pos（uid キー・位置権威＝World）を昇順 uid で走査し最初の一致を返す。dying は `enemyDying` set で
    /// 除外（scene の `not isDying` と等価）。★順序不変条件: scene 版は `getAll`（Scene preorder＝id 昇順ではない）
    /// + findMap、本関数は uid 昇順走査＝両者の走査順は違うが、**1 セル 1 敵の不変条件**（敵は排他マス占有）
    /// ゆえ coord 一致は高々 1 体＝tiebreak が発生せず結果は同一。複数敵同居が生じる改変時のみ差が出る。
    pub def enemyIdAt(coord: {x = Int32, y = Int32}, world: World): Option[Int32] =
        let World.World(w) = world;
        Map.toList(w#pos) |> List.findMap(pair -> {
            let (uid, p) = pair;
            if (uidIsEnemy(uid) and p#x == coord#x and p#y == coord#y and not Set.memberOf(uid, w#enemyDying))
                Some(uid - enemyUidBase())   // uidIsEnemy 済ゆえ uid-base = 元の敵 id（uidToRef の enemy 分岐と同値）
            else None
        })

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

    /// ★PlayerData.Data の field キー（playerDataMismatches）。flat でなく 2段ネスト ((11),(8))
    /// （tuple arity/Eq 上限回避・§1.3）。sub-key（posKey/resourceStatKey/headKey/statusListKey/
    /// pendingLevelUpKey）を再利用＝leaf drift 不能を継承。ネスト境界は逐語複製。
    pub def playerDataKey(d: PlayerData.Data):
            ((Int32, String, Int32, Option[Int32],
              (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32),
              (Int32, Option[(String, Int32)]),
              (Int32, Option[(String, Int32)]),
              (Int32, Option[(String, Int32)]),
              (Int32, Option[(String, Int32)]),
              Bool),
             (Option[PlayerData.ItemKind], Int32, Staff.Direction, Bool, Bool,
              Option[(String, Int32, Int32, Int32)],
              List[(StatusSystem.StatusEffect, Int32, Int32)])) =
        // 注: followUpUsed は含めない。P2 で scene copy 退役（syncTree 派生撤去・World 権威）ゆえ DIFF 対象外
        //     （World 権威は dataFromWorld None-gate＋専用テストが保証）。
        // 注: hp / waited / level / exp も P6-2a で外した。scene twin 退役（syncTree 派生撤去・
        //     ECS 経路は World のみ書く）ゆえ scene 値は stale が正＝DIFF 対象外。World 権威は
        //     overlay（dataFromWorld）と World 直読みの読み手 flip ＋ 専用テストが保証。
        // 注: gridPos も P6-2b で外した（scene twin 退役＝syncTree 撤去・読み手は World.posOf/overlay へ flip 済み）。
        ((d#id, d#classId, d#moveTiles,
          d#attackTargetId, resourceStatKey(d#resource),
          headKey(d#weapons, weaponKey),
          headKey(d#staves, staffKey),
          headKey(d#consumables, consumableKey),
          headKey(d#rings, ringKey),
          d#ringEquipped),
         (d#selectedItem, d#moveStepsTaken, d#facing, d#hidden, d#usedStairs,
          pendingLevelUpKey(d#pendingLevelUp),
          statusListKey(d#statuses)))

    /// ★EnemyData.Data の field キー（enemyDataMismatches）。playerDataKey と同流儀の 2段ネスト
    /// ((8),(8))（tuple arity/Eq 上限回避・§1.3）。sub-key（posKey/weaponKey/equippedRingKey/statusListKey）を
    /// 既存正準キーから再利用＝leaf drift 不能を継承（S2.4/S4.4 級の重複射影 drift バグを再導入しない）。
    /// resource(R 残置)は両辺 scene 由来＝恒等一致ゆえ resourceId(String) を代表値とする。
    pub def enemyDataKey(d: EnemyData.Data):
            ((Int32, String, Bool, Int32, Int32, Bool, Option[Int32]),
             (String, Option[(String, Int32)], Bool,
              List[(StatusSystem.StatusEffect, Int32, Int32)],
              Option[(String, Ring.RingEffect, Int32)])) =
        // 注: bottleUsed / followUpUsed / prevPos は含めない。P2 で scene copy 退役（syncTree 派生撤去・World 権威）
        //     ゆえ scene 値は stale＝再構築(World)と必然的に食い違う。scene 読み手が World 経由ゆえ DIFF 対象外が正。
        // 注: hp も P6-2a で外した（ECS 撃破は SetHp(0) のみで scene hp を書かず、syncTree 派生も撤去＝stale が正）。
        //     alerted/isDying は writer が scene 併記（dual-write）ゆえ残す。
        // 注: gridPos も P6-2b で外した（playerDataKey と同じ理由）。
        ((d#id, d#resourceId, d#alerted, d#homeModuleIdx,
          d#moveTiles, d#isDying, d#attackTargetId),
         (d#resourceId, Option.map(weaponKey, d#weapon), d#acted,
          statusListKey(d#statuses), Option.map(equippedRingKey, d#ring)))

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

    /// P1-b（thief drop ECS）: 対象がローグ職か（盗人の剣の発動条件）。`growthOf#name`（=`resource#description`）を
    /// 読むだけで新 store は足さない。legacy `maybeThiefDrop` の `player#resource#description == "ローグ"` と同判定。
    /// Enemy は growth を持たない（growthOf=None）ため常に false＝ローグは player-only という前提を型で担保。
    pub def isRogueOf(ref: EntityRef, world: World): Bool =
        growthOf(ref, world) |> Option.map(g -> g#name == "ローグ") |> Option.getWithDefault(false)

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
        // P6-2c: player 側は rings/ringEquipped store から**読み時導出**（旧 refreshMirror の毎フレーム
        // 再 mirror を置換）。敵側は Cmd.SetEnemyRing が書く equippedRing store。
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) =>
                if (Map.get(id, w#ringEquipped) |> Option.getWithDefault(false))
                    Map.get(id, w#rings) |> Option.flatMap(List.head)
                else None
            case EntityRef.Enemy(_) => Map.get(toUid(ref), w#equippedRing) |> Option.flatten
        }

    /// P2: 敵特殊能力 effectRule（生 Json）を World から読む（敵のみ・unified-id）。外側 Option（未登録）と
    /// 内側 Option（ルールなし）を flatten ＝ルールなしで None（`weaponViewOf` を逐語踏襲）。敵パスの sim 発火判定が読む。
    pub def effectRuleOf(ref: EntityRef, world: World): Option[Util.Json.Json] =
        let World.World(w) = world; Map.get(toUid(ref), w#effectRule) |> Option.flatten

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
    /// P6-2a 調査用: mismatch した entity について「どの field が違うか」を人間可読で返す。
    /// [UNITVIEW DIFF] のログ強化（恒久ではなくデバッグ支援・比較は unitViewKey と同じ粒度）。
    pub def unitViewFieldDiff(ref: EntityRef, world: World, scene: Scene[NodeTag]): String =
        let svOpt = match ref {
            case EntityRef.Player(id) => PlayerScene.get(id, scene) |> Option.map(PlayerScene.unitView)
            case EntityRef.Enemy(id)  => EnemyScene.get(id, scene) |> Option.map(EnemyScene.unitView)
        };
        match (unitViewFromWorld(ref, world, scene), svOpt) {
            case (None, _)    => "worldView=None"
            case (_, None)    => "sceneView=None"
            case (Some(wv), Some(sv)) =>
                let tag = (name, eq) -> if (eq) "" else " ${name}";
                let ds =
                    tag("pos", (wv#pos#x, wv#pos#y) == (sv#pos#x, sv#pos#y))
                    + tag("hp(w=${wv#hp},s=${sv#hp})", wv#hp == sv#hp)
                    + tag("moveTiles(w=${wv#moveTiles},s=${sv#moveTiles})", wv#moveTiles == sv#moveTiles)
                    + tag("weaponRange", Option.map(r -> (r#min, r#max), wv#weaponRange) == Option.map(r -> (r#min, r#max), sv#weaponRange))
                    + tag("combat", combatViewKey(wv#combat) == combatViewKey(sv#combat))
                    + tag("isDying", wv#isDying == sv#isDying)
                    + tag("hidden", wv#hidden == sv#hidden)
                    + tag("aiType", wv#aiType == sv#aiType);
                if (ds == "") "(key-equal?)" else ds
        }

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

    /// P1-a: 階段セル座標を World から読む（未配置なら None）。Stopgap 杖の warp 先計算（`warpCellFor`）が読む。
    /// scene の `Stairs.getPos` を mirror した read-model（`boardOf` と同じく scene 非依存 sim を可能にする seam）。
    pub def stairsPosOf(world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world; w#stairsPos

    /// P3-b/c: 配置物 store のセル key（1 セル 1 個ゆえ cell が一意 key＝record の Eq/Order を避け Int32 に符号化）。
    /// グリッドは各軸 1000 未満（ダンジョンセル）ゆえ `x*1000 + y` で衝突しない。chests/groundItems 共通。
    pub def cellKey(cell: {x = Int32, y = Int32}): Int32 = cell#x * 1000 + cell#y

    /// P3-b: 宝箱 store のセル key（`cellKey` の別名・既存 API 名として保持）。
    pub def chestCellKey(cell: {x = Int32, y = Int32}): Int32 = cellKey(cell)

    /// P3-b: 宝箱 store を World から読む（cell key → Data）。
    pub def chestsOf(world: World): Map[Int32, Chests.Data] =
        let World.World(w) = world; w#chests

    /// P3-b: 指定セルの宝箱を World から読む（`Chests.findAt` の World 版）。
    pub def chestAtOf(cell: {x = Int32, y = Int32}, world: World): Option[Chests.Data] =
        let World.World(w) = world; Map.get(cellKey(cell), w#chests)

    /// P6-1e: 手組み GroundItem ノード（テスト fixture）を cell key → Data の Map に射影する seed seam。
    /// production はノードを積まないので常に空。
    def itemsFromScene(scene: Scene[NodeTag]): Map[Int32, GroundItems.Data] =
        Scene.getChildrenAt(MapScene.worldName() :: "Items" :: Nil, scene)
            |> List.filterMap(name ->
                match Scene.getState(MapScene.worldName() :: "Items" :: name :: Nil, scene) {
                    case Some(NodeTag.GroundItem(d)) => Some(d)
                    case _                            => None
                })
            |> List.foldLeft((m, d) -> Map.insert(cellKey(d#gridPos), d, m), Map.empty())

    /// P3-c: 床アイテム store を World から読む（cell key → Data）。
    pub def groundItemsOf(world: World): Map[Int32, GroundItems.Data] =
        let World.World(w) = world; w#groundItems

    /// P3-c: 指定セルの床アイテムを World から読む（`GroundItems.dataAt` の World 版）。
    pub def groundItemAtOf(cell: {x = Int32, y = Int32}, world: World): Option[GroundItems.Data] =
        let World.World(w) = world; Map.get(cellKey(cell), w#groundItems)

    /// P5-b: ダメージ数字 fx store（seq → 寿命）。syncView が読み scene 子 Label2D を派生する。
    pub def popupFxOf(world: World): Map[Int32, PopupFx] =
        let World.World(w) = world; w#popupFx

    /// P5-b: 次に spawn する popup fx の連番。emit が子ノード名 `Popup_<seq>` の採番に読む
    /// （Cmd.SpawnPopupFx の applyCmd がこの値で挿入して +1 する＝read-after-write で一致）。
    pub def popupFxNextSeqOf(world: World): Int32 =
        let World.World(w) = world; w#popupFxNextSeq

    /// P5-b: 爆発 fx store（seq → 寿命）。
    pub def explosionFxOf(world: World): Map[Int32, ExplosionFx] =
        let World.World(w) = world; w#explosionFx

    /// P5-b: 次に spawn する爆発 fx の連番（popupFxNextSeqOf と同型）。
    pub def explosionFxNextSeqOf(world: World): Int32 =
        let World.World(w) = world; w#explosionFxNextSeq

    /// P6-1h: 再生中アニメ（AnimatedSprite2D 個体のみ登録）。未登録は None。
    pub def unitAnimOf(ref: EntityRef, world: World): Option[UnitAnim] =
        let World.World(w) = world; Map.get(toUid(ref), w#unitAnim)

    /// P6-1h: 左右反転。未登録は false（反転なし）。
    pub def flipHOf(ref: EntityRef, world: World): Bool =
        let World.World(w) = world; Map.get(toUid(ref), w#unitFlipH) |> Option.getWithDefault(false)

    /// P6-1h: 待機/行動済み暗転色（本体/HP バー/武器アイコン共通の単一真実源）。未登録は白。
    pub def modulateOf(ref: EntityRef, world: World): Color =
        let World.World(w) = world;
        Map.get(toUid(ref), w#unitModulate)
            |> Option.getWithDefault({r = 1.0f32, g = 1.0f32, b = 1.0f32})

    /// P6-1h: 死亡点滅の経過秒（SetDying からの実時間）。非 dying は None。
    pub def dyingElapsedOf(ref: EntityRef, world: World): Option[Float64] =
        let World.World(w) = world; Map.get(toUid(ref), w#dyingElapsed)

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

    /// P6-2b: **本番からは退役（テスト seam）**。gameLoop はもう呼ばない（gridPos の読み手は
    /// World.posOf / overlay / getXxxWithWorldPos へ全 flip 済み）。golden/DSL テストが「World の位置を
    /// scene Data へ投影して比較する」用途にのみ残す。
    pub def syncTreeFromWorld(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        // A': 単一 `pos` store を team タグで faction 分けし、original id で mapPlayer/mapEnemy。
        let World.World(w) = world;
        // 位置（S5b・既存）。store に居る entity だけ derive＝spawn-transient（store 未登録）は scene を保持。
        // P6-2a: hp/waited/isDying/alerted/level/exp の derive を撤去。
        //   - waited/hp/level/exp: scene twin 退役（live 読み手は overlay か World 直読みへ flip 済み。
        //     waited は scene 直書きも撤去済＝S6、hp/level/exp は ECS 経路が World のみ書く）。
        //     playerDataKey/enemyDataKey（DIFF）からも外した＝scene 値は stale で正。
        //   - isDying/alerted: writer が scene へも併記（startDeathAnimation/driver/restore の dual-write）
        //     ゆえ derive は冗長＝撤去（scene は writer 由来で fresh のまま・DIFF キーに残す）。
        // 残るは gridPos のみ（P6-2b で読み手 flip 後に撤去 → syncTree 全体を退役）。
        Map.foldLeftWithKey((sc, uid, pos) ->
            match uidToRef(uid) {
                case EntityRef.Player(pid) => PlayerScene.mapPlayer(pid, d -> {gridPos = pos | d}, sc)
                case EntityRef.Enemy(eid)  => EnemyScene.mapEnemy(eid, d -> {gridPos = pos | d}, sc)
            }, scene, w#pos)
}
