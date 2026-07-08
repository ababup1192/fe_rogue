// World — シミュレーション状態を集約する不変 World。
//
// id 集合＋tick に加え、component store 群を持つ（時限効果 statuses ほか）。
// player/enemy は scene 上の id 空間が別なので、unified-id へ写して単一 store に統合する。
// World は gameLoop の末尾再帰に thread される。
// 道標: ルート ECS_WORKFLOW.md。

/// sim としての「誰のターンか」を表す 3-case の phase。
/// World の権威は 19-case `TurnPhase.Phase`（`turnPhase` field）で持ち、この 3-case は
/// `WorldDriver.simPhaseOf(turnPhaseOf(world))` で**導出**する派生型（敵ターン / GameOver の粗い判定用）。
/// `TurnPhase.Phase` は純 ADT なので World→Phase の型依存は一方向で循環しない。
pub enum SimPhase with Eq, ToString {
    case PlayerTurn   // 味方ターン（カーソル/移動/メニュー/演出待ち = UiState.modalMode と anim-queue で細分）
    case EnemyTurn    // 敵ターン
    case GameOver     // 全滅モーダル
}

/// ゲーム全体の進行状態（「今どの画面か」）。戦闘ターンのサブフェーズ（TurnPhase）とは別レイヤー。
/// World の `screen` field が単一権威で、`GamePhaseState` facade が読み書きし、gameLoop が
/// 前フレームとの差分を見て `applyPhaseChange` で画面を組み替える。
pub enum GamePhase with Eq {
    /// 起動時のタイトル画面（はじめから / 中断から再開）。
    case Title
    /// 起動直後の出撃メンバー / リーダー選択画面。
    case CharacterSelect
    /// ダンジョン本編。
    case Playing
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

/// 魔導書攻撃の炎 3 幕（詠唱→飛翔→着弾）の store エントリ。詠唱者セル中心 `caster` の頭上に
/// 火の玉が生まれ、対象セル中心 `target` へ飛んで炸裂する。elapsed（= total - remaining）から
/// 幕・位置・スケール・プリセットを `FireShotFx` が純関数で導出する（Driver なし・巻き戻し安全）。
/// `remaining` は tickFxMap が dt 減算し 0 以下で cull（PopupFx/ExplosionFx と同 lane）。`seed` は
/// 攻撃ごとの通し番号（撃つたびの表情替え。同じ値なら同じ絵）。
pub type alias FireShot = { remaining = Float64, total = Float64, caster = Vec2.Vec2, target = Vec2.Vec2, seed = Int32 }

/// 体当たり攻撃（lunge）の store エントリ（秒・実時間）。攻撃側が origin → target → origin と
/// 往復する。位置は `lungeRenderPos` が `elapsed` から純関数導出する（FireShot と同じ「値＋導出」lane）。
/// `hitAt`（中点＝target に重なる瞬間）で AttackHit、`total`（終端）で LungeDone を
/// `stepAnimClocks` が signal として発火する。`hitFired` は中点発火の一回性フラグ。
/// クロックは `stepAnimClocks`（入力処理の後・戦闘 signal 解決の前）だけが進める（stepWorld は触らない）。
pub type alias LungeAnim = { origin = Vec2.Vec2, target = Vec2.Vec2, elapsed = Float64,
                             hitAt = Float64, total = Float64, hitFired = Bool }

/// ユニットの再生中アニメ（AnimatedSprite2D の脱ノード化）。frame/frameProgress は保存せず、
/// `elapsed`（再生開始からの実時間秒・stepWorld が加算）から描画時に純関数で導出する
/// （ループ/コマ毎 duration 倍率込み＝engine advanceFrame と同値）。`Cmd.SetAnim` は
/// AnimatedSprite2D.play の意味論（同名=継続/別名=リセット）を再現する。
pub type alias UnitAnim = { name = String, elapsed = Float64 }

/// 1 フレームで移動（Position tween）した entity の補間結果（EntityRef＋補間 pixel）。
/// `stepWorld` が active∪done を返す（テストの補間観測用。描画は renderPos store を
/// `visualPosOf` で直接導出するため、production の読者はいない）。
/// 同型 Vec2 の誤順を防ぐ名前渡し＋faction を EntityRef に閉じ込め（uid は plumbing 内で decode）。
pub type alias MarkerMove = { ref = World.EntityRef, pos = Vec2.Vec2 }

/// GPU タイルレイヤーの軽量描画ハンドル（静的・per-cell TileData 非保持）。scene の TileMapLayer ノード
/// から rebuild 時に bake し、毎フレーム camera 適用して engine `TileMapRenderCmd` に組む。フィールドは engine の
/// `TileMapRenderCmd`/`TileMapLayer` に一致（`tileVaoId`/`tileCount`）。`worldPos` はレイヤーの world 座標（camera parity）。
pub type alias TileLayerHandle = {
    textureName = String, tileSize = Float64, worldPos = Vec2.Vec2,
    color = Color, zIndex = Int32, tileVaoId = Int32, tileCount = Int32
}

/// フロアのマップ生成 Plan と安全スポーン地点（build choke が `Cmd.SetMapLayout` で書く）。
/// `plan` は中断/全滅復元で同一マップを乱数なしに再構築する保存対象（FloorSnapshot が読む）、
/// `spawnGrid` は anchor 部屋内の床が保証されたセルで PlayerScene の初期配置起点。
/// 部屋数は `plan#roomCount`（placements は `mapSnapshot#placements`）から読む。
pub type alias MapLayout = {
    plan = DungeonGenerator.Plan,
    spawnGrid = {x = Int32, y = Int32}
}

pub enum World {
    case World({ tick = Int32,
                 // turn FSM の 19-case phase。World 単一権威（`TurnPhase.State` は facade）。
                 turnPhase = TurnPhase.Phase,
                 // ゲーム全体の進行画面（Title/CharacterSelect/Playing）。World 単一権威（`GamePhaseState` は facade）。
                 screen = GamePhase,
                 // 出撃メンバー（ロード+抽選分・(classId, PlayerResource)）。None=未抽選（次 build で抽選）。
                 // フロア間で維持し、ゲーム開始/全滅/全クリア周回でのみ clear。World 単一権威（`PartySelection` は facade）。
                 party = Option[List[(String, UnitCatalog.PlayerResource)]],
                 // ゲームオーバー復活用の初回 spawn 一覧（初期配置・初期HPで敵味方を復元）。World 単一権威（`InitialSpawns` は facade）。
                 initialSpawns = InitialSpawns.Snapshot,
                 // 中断セーブ / 全滅リスタート用のフロア進入時スナップショット。None=未保存。World 単一権威（`FloorSnapshot` は facade）。
                 floorSnapshot = Option[FloorSnapshot.T],
                 // 現在いるフロア id（floors.json の sub-entry キー、例 "f01"）。""=未 seed（build choke の put が seed）。
                 // World 単一権威（`FloorProgress` は facade）。
                 floorId = String,
                 // 杖/投擲の照準矢印の論理状態（anchor/direction/gridPos）。見た目は view が描く。
                 // World 単一権威（production は `Game.start` の inline facade・test は `ArrowCursorState.withState` Ref）。
                 arrowCursor = ArrowCursorState.Data,
                 // 操作中プレイヤーの選択状態（id / 移動ドラフトの巻き戻しスタック / 集合モード）。
                 // World 単一権威（production は `Game.start` の inline facade・test は各 SelectedPlayer handler）。
                 selection = SelectedPlayer.Selection,
                 playerIds = Set[EntityId], enemyIds  = Set[EntityId],
                 // unified-id → `Faction` enum。faction 判定は id 演算（uid>=base）
                 // でなく **この enum タグ `teamOf` で読む**（Bevy の Team component 相当）。
                 team = Map[EntityId, Faction],
                 // statusEffects も単一 store（unified-id）。
                 statusEffects = Map[EntityId, StatusSystem.StatusEffects],
                 // hp の read-model（query/セーブ/決定論テスト用）。
                 // hp は単一 store（player uid=id / enemy uid=id+base）。
                 hp = Map[EntityId, Int32],
                 // weapons の store（hp 同型・単独権威）。player は weapons(List) をそのまま、
                 // enemy は単数 weapon(Option) を 0/1 要素 List に射影。全 weapon 書込は `Cmd.SetWeapons`
                 // のみ（scene の在庫 twin は spawn 時値の視覚残余）。読み手は weaponsOf / dataFromWorld。
                 weapons = Map[EntityId, List[UnitCatalog.WeaponResource]],
                 // staves/consumables/rings の store（weapons 同型・player-only・単独権威）。
                 // 敵は杖/薬/指輪インベントリを持たない（EnemyData に該当 field なし）ので store も player id keyed。
                 // 書込は `Cmd.SetStaves/SetConsumables/SetRings` のみ・読み手は各 accessor / dataFromWorld。
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
                 // 進行中の体当たり攻撃（lunge）。`Cmd.StartLunge` が seed し、`stepAnimClocks` が
                 // クロックを進めて中点 Hit / 完了 Done を signal 化・完了で除去する。位置は導出（lungeRenderPos）。
                 lunges = Map[EntityId, LungeAnim],
                 // 盤面除外（集合・階段退場）中の味方 id。Board.pieces は hidden 味方を除くので fromWorld に必要。
                 playerHidden = Set[EntityId],
                 // 敵の検知フラグ（dormant→chase）。
                 enemyAlerted = Map[EntityId, Bool],
                 // 敵の行動済みフラグ（ターン flow・view 灰色の権威）。enemy-only。faction-blind tick の前提。
                 enemyActed = Map[EntityId, Bool],
                 // 死亡演出中の敵 id（death_blink 中＝全 LOGIC から除外される sim フラグ）。
                 // present=isDying・非在=非 dying（死亡完了で Cmd.Despawn が除去）。
                 enemyDying = Set[EntityId],
                 // 敵の瓶使用済みフラグ（1ターン1投の sticky）。
                 enemyBottleUsed = Map[EntityId, Bool],
                 // 敵の直前位置（wander の戻り防止）。None=未移動はマップ非在で表現。
                 enemyPrevPos = Map[EntityId, {x = Int32, y = Int32}],
                 // followUp 使用済み（1 攻撃 1 追撃の per-turn transient）。両 faction。
                 // followUpUsed は単一 store（unified-id）。
                 followUpUsed = Map[EntityId, Bool],
                 // 味方の行動済み（ターン flow の権威）。player-only。
                 playerWaited = Map[EntityId, Bool],
                 // 味方の階段退場フラグ（フロア終了条件・tick gating の権威）。player-only。
                 playerUsedStairs = Map[EntityId, Bool],
                 // 攻撃対象 id（攻撃モーション中＝anyAttacking の権威）。None=非攻撃はマップ非在。両 faction。
                 // attackTarget は単一 store（unified-id）。
                 attackTarget = Map[EntityId, Int32],
                 // 味方の進行度（level/exp）。combat の撃破→exp→level-up が動かす sim 状態。
                 // level-up の hp 増分 dual-write が漏れやすい領域＝検証器で同種漏れを捕える。player-only。
                 playerLevel = Map[EntityId, Int32], playerExp = Map[EntityId, Int32],
                 // base 戦闘値 + maxHp の read-model（unified-id・両 faction）。resource 由来の
                 // command-derive（SetBaseStats が dual-write）。combatView flip 用。
                 baseStats = Map[EntityId, Combat.BaseStats],
                 // 装備武器の戦闘投影 read-model（unified-id・両 faction）。内側 Option=武器なし。
                 // PlayerScene/EnemyScene.equippedWeaponView 由来の command-derive（SetWeaponView が dual-write）。combatView flip 用。
                 weaponView = Map[EntityId, Option[Combat.WeaponView]],
                 // 装備指輪ボーナス read-model（unified-id・両 faction）。未装備は zeroBonuses。
                 // equippedRingBonus 由来の command-derive（SetRingBonus が dual-write）。combatView flip 用。
                 ringBonus = Map[EntityId, Ring.Bonuses],
                 // 基礎移動力 moveTiles の store（unified-id・両 faction）。resource 由来で spawn 後不変＝
                 // 実効移動力は effectiveMoveTilesOf が encumbrance を読み時計算（base のみ保持）。
                 moveTiles = Map[EntityId, Int32],
                 // 装備指輪リソース本体の read-model（unified-id・両 faction）。
                 // ringBonus はステ補正だけを持つが、finisher/lifesteal は RingResource（effect/power）を要する。
                 // weaponView と同じ Option-store パターン（内側 Option=未装備）。敵側は SetEnemyRing・player 側は accessor 導出。
                 equippedRing = Map[EntityId, Option[Ring.RingResource]],
                 // level-up 成長に要る resource 由来データ（基準 Stats + 成長率）。
                 // player-only・SetGrowth が書く command-derive。resolveCombat の level-up を World 完結に。
                 growth = Map[EntityId, Growth],
                 // 味方テンプレート（クラス id / UnitResource 本体）。spawn で seed し、resource を
                 // 書き換えるサイト（level-up の成長反映・最大 HP 変化・carry/復元）が SetPlayerResource で
                 // 更新する。`dataFromWorld`（scene 非依存の Data 再構築）と保存 capture が読む。
                 playerClassId = Map[EntityId, String],
                 playerResource = Map[EntityId, UnitCatalog.UnitResource],
                 // ItemMenu の選択中アイテム（非在=未選択）。player-only・SetSelectedItem が書く。
                 playerSelectedItem = Map[EntityId, PlayerData.ItemKind],
                 // 味方の向き（walk アニメの向き・保存 capture が読む）。player-only・SetFacing が書く。
                 playerFacing = Map[EntityId, Dir4.Dir4],
                 // 直近レベルアップ結果（非在=なし）。LevelUpPanel の modal trigger が読み、
                 // 演出消化で SetPendingLevelUp(None) が下ろす。player-only。
                 playerPendingLevelUp = Map[EntityId, LevelSystem.Result],
                 // AutoMove の当ターン進行済みマス数（0..moveTiles）。player-only・SetMoveSteps が書く。
                 playerMoveSteps = Map[EntityId, Int32],
                 // 敵テンプレート（EnemyResource 本体 / catalog id / スポーン部屋 idx）。spawn で seed し、
                 // resource は最大 HP 変化サイトが SetEnemyResource で更新する。`dataFromWorldEnemy` と保存 capture が読む。
                 enemyResource = Map[EntityId, EnemyCatalog.EnemyResource],
                 enemyResourceId = Map[EntityId, String],
                 enemyHomeModule = Map[EntityId, Int32],
                 // 静的地形スナップショット（プレーンな type-alias＝storable）。
                 // ノックバックの着地計算が要する `boardOf` の地形ソース。empty()=None（シーン未確定）。
                 // floor build choke の `Cmd.SetMapSnapshot` が書く（`MapSetup` が compose 結果から組む・boardOf の地形源）。
                 mapSnapshot = Option[MapSnapshot],
                 // マップ生成 Plan＋スポーン起点（None=盤面レス画面）。build choke の `Cmd.SetMapLayout` が書き、
                 // spawn 系（Player 初期配置）と FloorSnapshot 保存（plan）が読む。roomCount も plan から導く。
                 mapLayout = Option[MapLayout],
                 // 階段セル座標の read-model（None=未配置）。`Stairs.getPos(scene)`
                 // 由来を `Cmd.SetStairs` が書く（mapSnapshot と同型）。warp 先計算（`warpCellFor`）が読む。
                 stairsPos = Option[{x = Int32, y = Int32}],
                 // フロア全域の探索記憶（訪問済み module idx 集合）。ミニマップの描画と
                 // カーソル可動域（既訪エリア）判定が読む。`Cmd.AddVisited` が今フレーム分を union、
                 // フロア再構築時は `Cmd.ClearVisited` が一掃する（chests/items と同型・scene 非依存）。
                 visited = Set[Int32],
                 // 宝箱の read/write-model。セル key（`chestCellKey`）→ 宝箱 Data。
                 // spawn（`Cmd.SpawnChest`）/開封（`Cmd.RemoveChest`）が動かす＝存在は component（Map 在/不在）で表現。
                 // 純 command 由来（scene ノードなし）。floor 再構築時は `Cmd.ClearChests` が旧フロア分を一掃する。
                 chests = Map[Int32, Chests.Data],
                 // 床アイテムの read/write-model。セル key（`cellKey`）→ GroundItem Data。
                 // spawn（`Cmd.SpawnItem`）/拾得（`Cmd.RemoveItem`）が動かす＝存在は component（Map 在/不在）で表現。
                 // `elapsed`（点滅位相）は view 専用ゆえ store の値は spawn 時のスナップショット（World reader は読まない）。
                 // chests と同型（floor 再構築時は `Cmd.ClearItems` が一掃）。
                 groundItems = Map[Int32, GroundItems.Data],
                 // fx の寿命 store。spawn は `Cmd.SpawnPopupFx/SpawnExplosionFx`
                 // （applyCmd が nextSeq で採番し +1）、寿命 tick と期限切れ drop は stepWorld（EcsTween と同じ
                 // 「stepWorld が World を直接進める」前例）。scene の子 Label2D/Sprite2D は描画 view で、
                 // gameLoop が `DamagePopupFx.syncView`/`ExplosionFx.syncView` で store から派生する。
                 // 3-builder は command/step 由来ゆえ preserve（scene mirror 元なし・~0.7s 寿命の transient なので
                 // floor 遷移で残っても自然 expire＝prune 不要）。
                 popupFx = Map[Int32, PopupFx], popupFxNextSeq = Int32,
                 explosionFx = Map[Int32, ExplosionFx], explosionFxNextSeq = Int32,
                 // 魔導書攻撃の炎 3 幕 fx。spawn は `Cmd.SpawnFireShot`（applyCmd が nextSeq を seed に採番し +1）、
                 // 老化と cull は stepWorld の tickFxMap（explosionFx と同 lane）。~1.1s の transient ゆえ prune 不要。
                 fireShots = Map[Int32, FireShot], fireShotsNextSeq = Int32,
                 // 背景 map タイルの描画ハンドル（floor+walls 層・静的）。build choke の
                 // `Cmd.SetTileLayers` が seed し、render System が camera 適用して instanced 描画。
                 tileLayers = List[TileLayerHandle],
                 // 敵特殊能力 effectRule の生 Json read-model（unified-id・敵のみ）。
                 // 内側 Option=ルールなし。enemy `#resource#effectRule`（Option[Json]）由来＝weaponView と同じ
                 // Option-store パターン（accessor が flatten）。`Cmd.SetEffectRule` が書く。敵パスの sim 発火判定が読む。
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
        World.World({tick = 0, turnPhase = TurnPhase.Phase.PlayerCursor, screen = GamePhase.Title, party = None,
                     initialSpawns = {enemies = Nil, players = Nil}, floorSnapshot = None, floorId = "",
                     arrowCursor = ArrowCursorState.initial(), selection = SelectedPlayer.cleared(),
                     playerIds = Set.empty(), enemyIds = Set.empty(),
                     statusEffects = Map.empty(),
                     hp = Map.empty(), weapons = Map.empty(), team = Map.empty(),
                     staves = Map.empty(), consumables = Map.empty(), rings = Map.empty(),
                     ringEquipped = Map.empty(),
                     pos = Map.empty(),
                     renderPos = Map.empty(), tweens = Map.empty(),
                     unitAnim = Map.empty(), unitFlipH = Map.empty(),
                     unitModulate = Map.empty(), dyingElapsed = Map.empty(),
                     lunges = Map.empty(),
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
                     playerClassId = Map.empty(), playerResource = Map.empty(),
                     playerSelectedItem = Map.empty(), playerFacing = Map.empty(),
                     playerPendingLevelUp = Map.empty(), playerMoveSteps = Map.empty(),
                     enemyResource = Map.empty(), enemyResourceId = Map.empty(),
                     enemyHomeModule = Map.empty(),
                     mapSnapshot = None,
                     mapLayout = None,
                     stairsPos = None,
                     visited = Set.empty(),
                     chests = Map.empty(),
                     groundItems = Map.empty(),
                     popupFx = Map.empty(), popupFxNextSeq = 0,
                     explosionFx = Map.empty(), explosionFxNextSeq = 0,
                     fireShots = Map.empty(), fireShotsNextSeq = 0,
                     tileLayers = Nil,
                     effectRule = Map.empty(),
                     enemyTurnBusy = false, phaseObservedEnemy = false,
                     rng = Prng.seed(0i64)})

    /// World の turnPhase（19-case・phase の単一権威）を読む（read-model アクセサ）。
    /// 3-case sim-phase が要る所は `WorldDriver.simPhaseOf(turnPhaseOf(world))` で導出する。
    pub def turnPhaseOf(world: World): TurnPhase.Phase =
        let World.World(w) = world; w#turnPhase

    /// World の screen（進行画面・単一権威）を読む（read-model アクセサ）。`GamePhaseState` facade が使う。
    pub def screenOf(world: World): GamePhase =
        let World.World(w) = world; w#screen

    /// World の party（出撃メンバー・単一権威）を読む（read-model アクセサ）。`PartySelection` facade が使う。
    pub def partyOf(world: World): Option[List[(String, UnitCatalog.PlayerResource)]] =
        let World.World(w) = world; w#party

    /// World の initialSpawns（初回 spawn 一覧・単一権威）を読む（read-model アクセサ）。`InitialSpawns` facade が使う。
    pub def initialSpawnsOf(world: World): InitialSpawns.Snapshot =
        let World.World(w) = world; w#initialSpawns

    /// World の floorSnapshot（進入時スナップショット・単一権威）を読む（read-model アクセサ）。`FloorSnapshot` facade が使う。
    pub def floorSnapshotOf(world: World): Option[FloorSnapshot.T] =
        let World.World(w) = world; w#floorSnapshot

    /// World の floorId（現在フロア・単一権威）を読む（read-model アクセサ）。`FloorProgress` facade が使う。
    pub def floorIdOf(world: World): String =
        let World.World(w) = world; w#floorId

    /// World の arrowCursor（照準矢印の論理状態・単一権威）を読む（read-model アクセサ）。`ArrowCursorState` facade が使う。
    pub def arrowCursorOf(world: World): ArrowCursorState.Data =
        let World.World(w) = world; w#arrowCursor

    /// World の selection（操作中プレイヤーの選択状態・単一権威）を読む（read-model アクセサ）。`SelectedPlayer` facade が使う。
    pub def selectionOf(world: World): SelectedPlayer.Selection =
        let World.World(w) = world; w#selection

    /// per-frame の World 更新。**縮退版**: 全 store が command 権威（spawn/despawn/build choke の Cmd が
    /// 唯一の書込・prune は `Cmd.Despawn`/`Cmd.ClearUnits` が担う）なので、scene からの derive/prune は無い。
    /// 残る仕事は frame カウンタを 1 進めるだけ（scene 引数も持たない）。
    /// 初期 seed と床移動/復活/中断再開の reseed は spawn funnel（addOnePlayer/addOneEnemy）の Cmd emit が担う。
    pub def refreshMirror(world: World): World =
        let World.World(w) = world;
        World.World({tick = w#tick + 1 | w})

    /// statuses を 1 ターン進める System（StatusSystem.tick を再利用）。ターン開始フックが使う。
    pub def tickStatusEffects(world: World): World =
        let World.World(w) = world;
        World.World({
            statusEffects = Map.map(StatusSystem.tick, w#statusEffects)
            | w
        })

    /// **System パイプラインの段**。gameLoop の frame-end でここに Systems（`World -> World`）を畳む。
    /// 以後の System（移動 / 敵AI / 戦闘 …）はこの関数に追加していく。
    /// **statusEffects はここで tick しない**: statusEffects は command-authoritative で、ターン境界の
    /// `clearAllWaited`/`clearActedAll` が `StatusSystem.tick`→`Cmd.Seed` で World へ反映する。frame-paced に
    /// ここで tick すると **二重 tick**（remaining が 60/sec で減り status が数フレームで消える・combatViewOf が
    /// buff/debuff を落とす）になるため触らない。（`tickStatusEffects` def は単体テスト用に残置。実 System は
    /// ここへ足すが statusEffects は触らない＝ターン境界の Seed が唯一の権威 tick。）
    pub def stepWorld(world: World, dt: Float64): (World, List[MarkerMove]) =
        let World.World(w) = world;
        let (nextTweens, outs, _done) = EcsTween.step(dt, w#tweens);
        // tweens を更新後、各補間出力をチャンネル別に対象 component へ書く。
        // fx（ダメージ数字/爆発）の寿命もここで tick（remaining -= dt・0 以下で drop）。
        // tween と同じ「stepWorld が World を直接進める」lane＝per-frame Cmd を出さない。
        let stepped = List.foldLeft((acc, pair) -> {
            let ((uid, ch), out) = pair;
            applyTweenOut(uid, ch, out, acc)
        }, World.World({tweens = nextTweens,
                        popupFx = tickFxMap(dt, w#popupFx),
                        explosionFx = tickFxMap(dt, w#explosionFx),
                        fireShots = tickFxMap(dt, w#fireShots),
                        // 床アイテムの点滅位相（elapsed）も World が tick（fx と同じ lane）。
                        groundItems = Map.map(d ->
                            {elapsed = GroundItems.advance(Duration.add(d#elapsed, Duration.seconds(dt))) | d},
                            w#groundItems),
                        // ユニットアニメの再生経過と死亡点滅経過も World が tick
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

    /// fx 寿命 map を dt（秒）ぶん進め、期限切れ（remaining <= 0）を落とす。
    /// PopupFx/ExplosionFx 共用（row-poly・remaining だけ触る）。
    def tickFxMap(dt: Float64, fx: Map[Int32, {remaining = Float64 | r}]):
            Map[Int32, {remaining = Float64 | r}] =
        Map.foldLeftWithKey((acc, seq, d) -> {
            let r = d#remaining - dt;
            if (r <= 0.0) acc else Map.insert(seq, {remaining = r | d}, acc)
        }, Map.empty(), fx)

    /// tween の補間出力をチャンネル別に対象 component へ書く（Position→renderPos）。
    /// 不能組（Position に Scalar 等）は smart constructor 経路ゆえ設計上ありえない＝loud に bug!。
    /// チャンネル増分（Alpha/Scale…）はここに 1 arm 足すだけ。
    def applyTweenOut(uid: EntityId, ch: Channel, out: EcsTween.Out, world: World): World =
        let World.World(w) = world;
        match (ch, out) {
            case (Channel.Position, EcsTween.Out.VecOut(v)) =>
                World.World({renderPos = Map.insert(uid, v, w#renderPos) | w})
            case _ => bug!("EcsTween: impossible (channel, out) combo")
        }

    /// 戦闘演出クロックの発火 signal。`stepAnimClocks` が返し、`CombatDriver.stepEntities` が
    /// 自 entity 宛だけを拾って解決する（AttackHit=ダメージ適用 / LungeDone=反撃・確定 /
    /// DeathBlinkDone=撃破 SE＋ノード除去）。
    pub enum AnimSignal {
        case AttackHit(EntityRef)
        case LungeDone(EntityRef)
        case DeathBlinkDone(EntityRef)
    }

    /// 戦闘演出クロックを 1 フレームぶん進め、発火した signal を返す。
    /// gameLoop が入力処理の後・戦闘 signal 解決（`CombatDriver.stepEntities`）の前に 1 回呼ぶ。
    ///   - lunge: elapsed += dt の後、中点（hitAt <= elapsed・未発火）で AttackHit、
    ///     終端（elapsed/total >= 1.0）で LungeDone を発火し store から除去する。
    ///     入力処理で始まった lunge はそのフレームから進む（開始と同フレームに 1 tick）。
    ///   - 死亡点滅: dyingElapsed（stepWorld が加算・描画 alpha と同じクロック）が全長
    ///     blinkTotal に達した敵に DeathBlinkDone を発火する。consumer（completeDeath）の
    ///     Despawn が dying store を除去するため二重発火しない。
    /// GameOver 中は呼ばない約束（盤面フリーズ＝進行も発火も止まる）。
    pub def stepAnimClocks(dt: Float64, blinkTotal: Float64, world: World): (World, List[AnimSignal]) =
        let World.World(w) = world;
        let (lunges1, lungeSigs) = Map.foldLeftWithKey((acc, uid, l) -> {
            let (m, sigs) = acc;
            let e2 = l#elapsed + dt;
            let hitNow  = (not l#hitFired) and l#hitAt <= e2;
            let doneNow = l#total <= 0.0 or e2 / l#total >= 1.0;
            let sigs1 = if (hitNow)  AnimSignal.AttackHit(uidToRef(uid)) :: sigs  else sigs;
            let sigs2 = if (doneNow) AnimSignal.LungeDone(uidToRef(uid)) :: sigs1 else sigs1;
            let m1 = if (doneNow) m
                     else Map.insert(uid, {elapsed = e2, hitFired = l#hitFired or hitNow | l}, m);
            (m1, sigs2)
        }, (Map.empty(), (Nil: List[AnimSignal])), w#lunges);
        let blinkSigs = Set.foldLeft((sigs, uid) ->
            match Map.get(uid, w#dyingElapsed) {
                case Some(e) => if (e >= blinkTotal) AnimSignal.DeathBlinkDone(uidToRef(uid)) :: sigs else sigs
                case None    => sigs
            }, (Nil: List[AnimSignal]), w#enemyDying);
        (World.World({lunges = lunges1 | w}), List.append(List.reverse(lungeSigs), List.reverse(blinkSigs)))

    /// lunge 中ユニットの描画位置（None=非 lunge）。renderUnits / HP バー / 武器アイコンが
    /// marker 位置の代わりに読む（lunge 中だけ World 導出で上書き）。
    pub def lungePosOf(ref: EntityRef, world: World): Option[Vec2.Vec2] =
        let World.World(w) = world;
        Map.get(toUid(ref), w#lunges) |> Option.map(lungeRenderPos)

    /// LungeAnim の現在位置を elapsed から純関数導出する。進度 t（0..1 クランプ）で
    /// 前半（t<0.5）origin→target、後半 target→origin の線形補間、終端は origin。
    pub def lungeRenderPos(l: LungeAnim): Vec2.Vec2 =
        let t = if (l#total <= 0.0) 1.0 else Float64.min(1.0, l#elapsed / l#total);
        if (t < 0.5) Vec2.lerp(l#origin, l#target, t / 0.5)
        else if (t >= 1.0) l#origin
        else Vec2.lerp(l#target, l#origin, (t - 0.5) / 0.5)

    // ════════════════════════════════════════════════════════════════════
    // statusEffects（時限ステータス効果＝バフ/デバフ）を World 権威にする ECS 層
    // Bevy 正対: Command 書き込み / Query 読み込み。System ロジックは StatusSystem を再利用（再実装ゼロ）。
    //
    // ── entity モデル ──────────────────
    // 単一 unified-id 空間（enemy id は enemyUidBase offset で写す）＋ faction を component に:
    //   `statusEffects: Map[EntityId, StatusEffects]` 1 本 ＋ `team: Map[EntityId, Faction]`。
    //   「敵らしさ」は Faction component で表す（味方型/敵型の継承を作らない）。
    //   scene-tree は PlayerScene/EnemyScene の **2 つの id 名前空間**（味方 id 0 と敵 id 0 が衝突）と
    //   別レコード型（PlayerData/EnemyData）を持つが、World は enemyUid 写像で単一 store に統合している。
    // seam: read = `StatusQuery.statusEffects(EntityRef)`、write の単体操作 = `Cmd.Add/ClearImmobilized/Seed(EntityRef, …)`
    //   はいずれも **EntityRef キーで faction 非依存**。faction 一括操作は `Cmd.TickPlayers/TickEnemies`
    //   （ターン構造上 faction 別が本質）。id 名前空間/セーブ形式の統合は別スコープ（セーブ互換リスクが大きいため defer）。
    // ════════════════════════════════════════════════════════════════════

    /// entity の参照（faction タグ付き）。Board.Piece と同型。statusEffects アクセスのキー抽象＝
    /// 単一 store の unified-id キーを呼び出し側に見せずに触れる seam。
    pub enum EntityRef with Eq, ToString {
        case Player(EntityId)
        case Enemy(EntityId)
    }

    /// faction 別 id 空間を **単一 unified-id 空間**へ決定論写像する固定オフセット。
    /// Player id 0..* はそのまま、Enemy id は `+ENEMY_UID_BASE`。save は scene 由来（faction 別 id）で不変。
    /// これで `hp/pos/...` を **単一 store**に統合でき、applyCmd/accessor の per-store 分岐が `toUid` 1 本に畳まれる。
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

    /// statusEffects への変更命令（Bevy の Commands 相当）。深い scene コードが emit し、
    /// Game.start の handler が worldRef へ即時適用する（純粋 applier 経由）。
    /// 単体操作（Add/ClearImmobilized/Seed）は **EntityRef でキー化＝faction 非依存の write seam**。
    /// Tick は「そのターンの faction を一括」操作
    /// なので faction 別（TickPlayers は非 usedStairs id のみ／TickEnemies は全敵）。
    /// Seed は **replace 意味論**（clear-then-set）＝StatusSystem.add のスキップ型を使わない。
    pub enum Cmd {
        case Add(EntityRef, StatusSystem.Status)
        case ClearImmobilized(EntityRef)
        case Seed(EntityRef, StatusSystem.StatusEffects)  // 再構築/復元の全置換
        case TickPlayers(List[EntityId])    // 味方ターン開始（非 usedStairs の id のみ）
        case TickEnemies                    // 敵ターン開始（全敵）
        case Move(EntityRef, {x = Int32, y = Int32})  // 位置 write（mid-frame currency）
        case SetPhase(TurnPhase.Phase)      // turn phase write（19-case・TurnPhase.State facade が World 権威へ書く）
        case SetScreen(GamePhase)           // 進行画面 write（Title/CharacterSelect/Playing・GamePhaseState facade が書く）
        case SetParty(Option[List[(String, UnitCatalog.PlayerResource)]])  // 出撃メンバー write（PartySelection facade・None=リセット）
        case SetInitialSpawns(InitialSpawns.Snapshot)  // 初回 spawn 一覧 write（InitialSpawns facade・GameOver 復活用）
        case SetFloorSnapshot(Option[FloorSnapshot.T])  // フロア進入時スナップショット write（FloorSnapshot facade・None=未保存）
        case SetFloorId(String)             // 現在フロア id write（FloorProgress facade・階段/全滅/周回で遷移）
        case SetArrowCursor(ArrowCursorState.Data)  // 照準矢印の論理状態 write（ArrowCursorState facade）
        case SetSelection(SelectedPlayer.Selection)  // 操作中プレイヤー選択状態 write（SelectedPlayer facade）
        case SetHp(EntityRef, Int32)        // hp write（dual-write seam。mid-frame で敵ターン System が逐次反映する前提）
        case SetWeapons(EntityRef, List[UnitCatalog.WeaponResource])  // weapons write（dual-write seam。player は List・enemy は 0/1 List 射影）
        case SetBaseStats(EntityRef, Combat.BaseStats)  // base 戦闘値 write（hp/weapons 同型・両 faction・resource 書換ごとに dual-write）
        case SetWeaponView(EntityRef, Option[Combat.WeaponView])  // 装備武器の戦闘投影 write（両 faction・武器なし=None・weapons 書換ごとに dual-write）
        case SetRingBonus(EntityRef, Ring.Bonuses)  // 装備指輪ボーナス write（両 faction・rings/ringEquipped 書換ごとに dual-write）
        case SetMoveTiles(EntityRef, Int32)  // 基礎移動力 write（両 faction・spawn で seed・以後不変）
        case SetStaves(EntityRef, List[Staff.StaffResource])               // staves write（player-only・Enemy no-op）
        case SetConsumables(EntityRef, List[Consumable.ConsumableResource]) // consumables write（player-only）
        case SetRings(EntityRef, List[Ring.RingResource])                  // rings write（player-only）
        case SetRingEquipped(EntityRef, Bool)                              // ringEquipped write（player-only・Bool）
        case SetAlerted(EntityRef, Bool)    // 敵検知フラグ write（Player は no-op）
        case SetActed(EntityRef, Bool)      // 敵行動済みフラグ write（Player は no-op）
        case SetDying(EntityRef)            // 敵を死亡演出中に（Player は no-op・clear は removal+prune）
        case SetBottleUsed(EntityRef, Bool) // 敵瓶使用フラグ write（Player は no-op）
        case SetPrevPos(EntityRef, {x = Int32, y = Int32})  // 敵直前位置 write（Player は no-op）
        case SetFollowUpUsed(EntityRef, Bool)  // followUp 使用済み write（両 faction）
        case SetWaited(EntityRef, Bool)        // 味方行動済み write（Enemy は no-op）
        case SetUsedStairs(EntityRef, Bool)    // 味方階段退場 write（Enemy は no-op）
        case SetRenderPos(EntityRef, Vec2.Vec2)  // 描画位置を直接 set（spawn seed/瞬間移動）
        case StartTween(EntityRef, Channel, EcsTween.Track, Float64, EcsTween.Easing, Bool)  // (entity,channel) tween を dur 秒で開始
        case SetAttackTarget(EntityRef, Int32) // 攻撃対象 id をセット（攻撃開始）
        case ClearAttackTarget(EntityRef)      // 攻撃対象をクリア（攻撃終了）
        case SetProgress(EntityRef, Int32, Int32) // 味方の (level, exp) write（撃破/レベルアップ/復元で）
        case SetEnemyTurnBusy(Bool)            // 敵ターン intro hold 中 bool write（TopBar dual-write）
        case SetPhaseObservedEnemy(Bool)       // バーが敵ターン観測済み bool write（TopBar dual-write）
        case SetStairs(Option[{x = Int32, y = Int32}])  // 階段セル write（配置=Some/未配置=None・floor 単位で 1 回）。stairsPos を World 権威化
        case AddVisited(Set[Int32])        // 探索記憶に今フレームの訪問 module idx を union（Minimap step が emit）
        case ClearVisited                  // フロア再構築時に探索記憶を一掃（ClearChests と同型）
        case SpawnChest(Chests.Data)   // 宝箱を配置（build/復元）。cell key で chests へ挿入（存在=Map 在）
        case ClearChests                   // フロア再構築時に前フロアの宝箱を全消去（build choke が emit）
        case RemoveChest({x = Int32, y = Int32})  // 宝箱を開封して除去（cell key で chests から削除）
        case SpawnItem(GroundItems.Data)     // 床アイテムを配置（build/復元/respawn/drop）。cell key で groundItems へ挿入
        case RemoveItem({x = Int32, y = Int32})   // 床アイテムを拾得して除去（cell key で groundItems から削除）
        case ClearItems                    // フロア再構築時に前フロアの床アイテムを全消去（ClearChests と同型）
        case Spawn(EntityRef)                  // id 集合/team へ登録（spawn funnel 冒頭で emit）
        case Despawn(EntityRef)                // 全 per-entity store から除去
        case ClearUnits                        // 全ユニット store 一掃（build choke の頭で emit・ClearChests と同型）
        case SetHidden(EntityRef, Bool)        // 階段退場フラグ（playerHidden）
        case SetEnemyRing(Int32, Option[Ring.RingResource])   // 敵の装備指輪（spawn/復元/指輪変化で emit）
        case SetGrowth(Int32, Growth)          // 成長 read-model（resource 変化サイト=SetBaseStats と同所で emit）
        case SetClassId(Int32, String)                            // 味方クラス id（spawn で 1 回・以後不変）
        case SetPlayerResource(Int32, UnitCatalog.UnitResource)   // 味方 resource テンプレ（spawn/成長/最大HP変化サイトで emit）
        case SetSelectedItem(Int32, Option[PlayerData.ItemKind])  // ItemMenu 選択（None=解除）
        case SetFacing(Int32, Dir4.Dir4)                          // 味方の向き（移動 view/復元が書く）
        case SetPendingLevelUp(Int32, Option[LevelSystem.Result]) // レベルアップ演出待ち（None=消化済み）
        case SetMoveSteps(Int32, Int32)                           // AutoMove 進行歩数
        case SetEnemyResource(Int32, EnemyCatalog.EnemyResource)  // 敵 resource テンプレ（spawn/最大HP変化サイトで emit）
        case SetEnemyProfile(Int32, {resourceId = String, homeModuleIdx = Int32})  // 敵 catalog id＋出身部屋（spawn で 1 回）
        case SetMapSnapshot(Option[MapSnapshot])               // 地形 read-model（floor build choke で emit・Title は None）
        case SetMapLayout(Option[MapLayout])                   // マップ Plan＋スポーン起点（floor build choke で emit・Title は None）
        case SetTileLayers(List[TileLayerHandle])              // 背景タイルの描画ハンドル（floor build choke で emit・Title は Nil）
        case SetEffectRule(Int32, Option[Util.Json.Json])      // 敵 effectRule（spawn で emit・以後不変）
        case SetAnim(EntityRef, String)        // 再生アニメ切替（play 意味論=同名継続/別名リセット）
        case SetFlipH(EntityRef, Bool)         // 左右反転（移動 view 再生が書く）
        case SetModulate(EntityRef, Color)     // 待機/行動済み暗転色（本体/バー/アイコン共通）
        case SpawnPopupFx({total = Float64, pos = Vec2.Vec2, text = String, color = Color})  // ダメージ数字 fx を spawn（remaining=total で開始・見た目も store 持ち）
        case SpawnExplosionFx({total = Float64, pos = Vec2.Vec2, scale = Float64})            // 爆発 fx を spawn
        case SpawnFireShot({total = Float64, caster = Vec2.Vec2, target = Vec2.Vec2})          // 魔導書の炎 3 幕 fx を spawn（seed=通し番号を採番）
        case StartLunge(EntityRef, {origin = Vec2.Vec2, target = Vec2.Vec2, hitAt = Float64, total = Float64})  // 体当たり攻撃の往復演出を開始（view-lane・golden trace の記録対象外）
    }

    /// System が出力する sim-event。
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
        case FireShot({caster = {x = Int32, y = Int32}, target = {x = Int32, y = Int32}})
        case Knockback(EntityRef, {x = Int32, y = Int32})
        case Thief({x = Int32, y = Int32})
        case Died(EntityRef)
    }

    /// statuses 書き込み effect（Bevy Commands）。handler は Game.start（worldRef へ即時適用）。
    /// emit した Cmd は worldRef に適用され、World 権威として後続フレームに残る。
    pub eff Command {
        def emit(c: Cmd): Unit
    }

    /// statusEffects 読み込み effect（Bevy Query 相当）。**EntityRef で引く＝faction 非依存の read seam**。
    /// handler は Game.start（worldRef を読む）。reader への引数注入の供給元。
    /// 名前は `StatusQuery`（engine_ecs の汎用 `Query` モジュールを mod World 内で使えるよう、衝突回避）。
    pub eff StatusQuery {
        def statusEffects(ref: EntityRef): StatusSystem.StatusEffects
    }

    /// turn phase 読み込み effect。handler は Game.start（worldRef.turnPhase を返す）。
    /// sim-phase（3-case）を読む reader を `TurnPhase.State.get()` からこれに flip する read seam。
    /// メニュー細分（19-case）を要する reader は対象外（UiState.modalMode が要る）。
    pub eff PhaseQuery {
        def phase(): SimPhase
    }

    /// 現フレームの World スナップショットを読む汎用 read seam（worldRef を返す）。handler は Game.start。
    /// フラグ reader（alerted/bottleUsed/…）を scene→World に flip する共通窓口＝フラグごとに effect を増やさない。
    /// 読み手は `World.WorldQuery.get() |> World.alertedOf(ref)` の形で任意の accessor を使う。mid-frame currency
    /// あり（その frame の Cmd が反映済み worldRef を返す）＝同ターン read-after-write が正しい。
    pub eff WorldQuery {
        def get(): World
    }

    /// 全 combat roll の単一 chokepoint。0..99 の一様乱数を 1 つ引く。
    /// live ハンドラ（Game.start）は `Math.Random` に delegate し元の rollPercent と BODY-IDENTITY、
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

    /// statusEffects を引く（既定 Nil＝mid-game spawn は seed 不要）。Query handler から呼ぶ。
    /// 単一 store。player uid=id ゆえ get(id) のまま、enemy は enemyUid(id) へ写す。
    pub def playerStatusEffectsOf(id: EntityId, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(id, Nil, w#statusEffects)
    pub def enemyStatusEffectsOf(id: EntityId, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(enemyUid(id), Nil, w#statusEffects)

    /// faction 非依存の統一アクセサ。単一 store＋toUid。
    pub def statusEffectsOf(ref: EntityRef, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(toUid(ref), Nil, w#statusEffects)

    /// EntityRef の statusEffects に純粋変換 f を適用する。単一 store＋toUid。
    def overEntity(ref: EntityRef, f: StatusSystem.StatusEffects -> StatusSystem.StatusEffects, world: World): World =
        let World.World(w) = world;
        let uid = toUid(ref);
        let cur = Map.getWithDefault(uid, Nil, w#statusEffects);
        World.World({statusEffects = Map.insert(uid, f(cur), w#statusEffects) | w})

    /// 1 命令を World へ適用する純粋 applier（Command handler の本体）。
    /// 1 entity を全 per-entity store から取り除く（`Cmd.Despawn` の実体）。
    /// ノード除去サイト（死亡完了/戦死/引き継ぎ剪定）が emit する。
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
            lunges = Map.remove(uid, w#lunges),
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
            playerClassId = Map.remove(uid, w#playerClassId),
            playerResource = Map.remove(uid, w#playerResource),
            playerSelectedItem = Map.remove(uid, w#playerSelectedItem),
            playerFacing = Map.remove(uid, w#playerFacing),
            playerPendingLevelUp = Map.remove(uid, w#playerPendingLevelUp),
            playerMoveSteps = Map.remove(uid, w#playerMoveSteps),
            enemyResource = Map.remove(uid, w#enemyResource),
            enemyResourceId = Map.remove(uid, w#enemyResourceId),
            enemyHomeModule = Map.remove(uid, w#enemyHomeModule),
            effectRule = Map.remove(uid, w#effectRule),
            attackTarget = Map.remove(uid, w#attackTarget)
            | w})

    pub def applyCmd(cmd: Cmd, world: World): World =
        match cmd {
            case Cmd.Add(ref, s)           => overEntity(ref, xs -> StatusSystem.add(s, xs), world)
            case Cmd.ClearImmobilized(ref) => overEntity(ref, StatusSystem.clearImmobilized, world)
            case Cmd.Seed(ref, xs)         => overEntity(ref, _ -> xs, world)
            case Cmd.TickPlayers(ids) =>
                // 単一 store。player uid=id ゆえ id 集合をそのまま updateTagged（敵 uid は集合外で不変）。
                let World.World(w) = world;
                World.World({statusEffects = Query.updateTagged(List.toSet(ids), StatusSystem.tick, w#statusEffects) | w})
            case Cmd.TickEnemies =>
                // 敵 uid のエントリだけ tick（uidIsEnemy で plumbing 判定）。
                let World.World(w) = world;
                World.World({statusEffects = Map.mapWithKey((uid, s) -> if (uidIsEnemy(uid)) StatusSystem.tick(s) else s, w#statusEffects) | w})
            case Cmd.Move(ref, pos) =>
                // 単一 store＋toUid。
                // 旧位置を prevPos に自動記録（両 faction）＝敵 wander の戻り防止。Cmd 列は不変（新 Cmd を
                // 増やさない）。初回 Move（spawn seed）は旧位置が無いので記録しない。
                let World.World(w) = world;
                let prevs = match Map.get(toUid(ref), w#pos) {
                    case Some(old) => Map.insert(toUid(ref), old, w#enemyPrevPos)
                    case None      => w#enemyPrevPos
                };
                World.World({pos = Map.insert(toUid(ref), pos, w#pos),
                             enemyPrevPos = prevs | w})
            case Cmd.SetPhase(phase) =>
                let World.World(w) = world; World.World({turnPhase = phase | w})
            case Cmd.SetScreen(s) =>
                let World.World(w) = world; World.World({screen = s | w})
            case Cmd.SetParty(sel) =>
                let World.World(w) = world; World.World({party = sel | w})
            case Cmd.SetInitialSpawns(snap) =>
                let World.World(w) = world; World.World({initialSpawns = snap | w})
            case Cmd.SetFloorSnapshot(snap) =>
                let World.World(w) = world; World.World({floorSnapshot = snap | w})
            case Cmd.SetFloorId(id) =>
                let World.World(w) = world; World.World({floorId = id | w})
            case Cmd.SetArrowCursor(a) =>
                let World.World(w) = world; World.World({arrowCursor = a | w})
            case Cmd.SetSelection(s) =>
                let World.World(w) = world; World.World({selection = s | w})
            case Cmd.SetHp(ref, hpVal) =>
                // 単一 store＋toUid。
                let World.World(w) = world;
                World.World({hp = Map.insert(toUid(ref), hpVal, w#hp) | w})
            case Cmd.SetWeapons(ref, ws) =>
                // 単一 store＋toUid（SetHp と同型）。
                let World.World(w) = world;
                World.World({weapons = Map.insert(toUid(ref), ws, w#weapons) | w})
            case Cmd.SetBaseStats(ref, bs) =>
                // 単一 store＋toUid（SetHp/SetWeapons と同型・両 faction）。
                let World.World(w) = world;
                World.World({baseStats = Map.insert(toUid(ref), bs, w#baseStats) | w})
            case Cmd.SetWeaponView(ref, wv) =>
                // 単一 store＋toUid（SetBaseStats と同型・両 faction・内側 Option=武器なし）。
                let World.World(w) = world;
                World.World({weaponView = Map.insert(toUid(ref), wv, w#weaponView) | w})
            case Cmd.SetRingBonus(ref, rb) =>
                // 単一 store＋toUid（SetBaseStats と同型・両 faction）。
                let World.World(w) = world;
                World.World({ringBonus = Map.insert(toUid(ref), rb, w#ringBonus) | w})
            case Cmd.SetMoveTiles(ref, n) =>
                // 単一 store＋toUid（SetBaseStats と同型・両 faction・移動力）。
                let World.World(w) = world;
                World.World({moveTiles = Map.insert(toUid(ref), n, w#moveTiles) | w})
            case Cmd.SetStaves(ref, xs) =>
                // player-only store（SetWaited 流儀・Enemy は no-op）。
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
                    case EntityRef.Player(_)  => world   // 味方に alerted は無い＝no-op
                    case EntityRef.Enemy(id)  => World.World({enemyAlerted = Map.insert(enemyUid(id), a, w#enemyAlerted) | w})
                }
            case Cmd.SetActed(ref, b) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world   // 味方 acted は無い＝no-op
                    case EntityRef.Enemy(id)  => World.World({enemyActed = Map.insert(enemyUid(id), b, w#enemyActed) | w})
                }
            case Cmd.SetDying(ref) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world   // 味方は hp<=0 で即除去＝isDying 無し
                    // 死亡点滅の経過秒も 0 で seed（stepWorld が加算・alpha は描画時に曲線導出）。
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
                // 単一 store＋toUid。
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
                // 描画位置を直接 set（進行中の Position tween は破棄）。spawn seed / 瞬間移動用。
                let World.World(w) = world;
                let uid = toUid(ref);
                World.World({renderPos = Map.insert(uid, p, w#renderPos),
                             tweens = Map.remove((uid, Channel.Position), w#tweens) | w})
            case Cmd.StartTween(ref, ch, track, dur, easing, yoyo) =>
                // (entity, channel) tween を開始。Position は renderPos を即 src にスナップ（補間初期値）。
                let World.World(w) = world;
                let uid = toUid(ref);
                let nextTweens = EcsTween.start((uid, ch), track, dur, easing, yoyo, w#tweens);
                let nextRenderPos = match (ch, track) {
                    case (Channel.Position, EcsTween.Track.Vec(vl)) => Map.insert(uid, vl#start, w#renderPos)
                    case _                                          => w#renderPos
                };
                World.World({tweens = nextTweens, renderPos = nextRenderPos | w})
            case Cmd.SetAttackTarget(ref, t) =>
                // 単一 store＋toUid。
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
            case Cmd.SetStairs(cell) =>
                // 階段セルを World 権威に write（placeAt が emit）。floor 単位で 1 回・未配置は None。
                let World.World(w) = world; World.World({stairsPos = cell | w})
            case Cmd.AddVisited(mods) =>
                // 探索記憶に今フレーム訪問分を union（Minimap step 由来）。記憶＝離脱後も残る。
                let World.World(w) = world; World.World({visited = Set.union(w#visited, mods) | w})
            case Cmd.ClearVisited =>
                // フロア再構築の頭で探索記憶を一掃（ClearChests と同型）。
                let World.World(w) = world; World.World({visited = Set.empty() | w})
            case Cmd.SpawnChest(data) =>
                // 宝箱を cell key で挿入（addOneChest が emit）。存在は Map 在で表現。
                let World.World(w) = world;
                World.World({chests = Map.insert(chestCellKey(data#gridPos), data, w#chests) | w})
            case Cmd.RemoveChest(cell) =>
                // 宝箱を開封して除去（takeAt が emit）。存在の消失は Map 不在で表現。
                let World.World(w) = world;
                World.World({chests = Map.remove(chestCellKey(cell), w#chests) | w})
            case Cmd.ClearChests =>
                // フロア再構築の頭で全消去（宝箱は純 command 由来ゆえ、旧フロア分の掃除は build choke の
                // 明示 Cmd が担う）。
                let World.World(w) = world;
                World.World({chests = Map.empty() | w})
            case Cmd.ClearItems =>
                // ClearChests と同型（床アイテムの掃除）。
                let World.World(w) = world;
                World.World({groundItems = Map.empty() | w})
            case Cmd.SpawnItem(data) =>
                // 床アイテムを cell key で挿入（addOneItem が emit）。存在は Map 在で表現。
                let World.World(w) = world;
                World.World({groundItems = Map.insert(cellKey(data#gridPos), data, w#groundItems) | w})
            case Cmd.RemoveItem(cell) =>
                // 床アイテムを拾得して除去（takeAt が emit）。存在の消失は Map 不在で表現。
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
                             lunges = Map.empty(),
                             playerHidden = Set.empty(), enemyDying = Set.empty(),
                             enemyAlerted = Map.empty(), enemyActed = Map.empty(),
                             enemyBottleUsed = Map.empty(), enemyPrevPos = Map.empty(),
                             followUpUsed = Map.empty(), playerWaited = Map.empty(),
                             playerUsedStairs = Map.empty(), playerLevel = Map.empty(),
                             playerExp = Map.empty(), baseStats = Map.empty(), weaponView = Map.empty(),
                             ringBonus = Map.empty(), moveTiles = Map.empty(), equippedRing = Map.empty(),
                             growth = Map.empty(),
                             playerClassId = Map.empty(), playerResource = Map.empty(),
                             playerSelectedItem = Map.empty(), playerFacing = Map.empty(),
                             playerPendingLevelUp = Map.empty(), playerMoveSteps = Map.empty(),
                             enemyResource = Map.empty(), enemyResourceId = Map.empty(),
                             enemyHomeModule = Map.empty(),
                             effectRule = Map.empty(), attackTarget = Map.empty() | w})
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
            case Cmd.SetClassId(id, c) =>
                let World.World(w) = world;
                World.World({playerClassId = Map.insert(id, c, w#playerClassId) | w})
            case Cmd.SetPlayerResource(id, r) =>
                let World.World(w) = world;
                World.World({playerResource = Map.insert(id, r, w#playerResource) | w})
            case Cmd.SetSelectedItem(id, opt) =>
                // 未選択(None)は Map 非在で表現（attackTarget と同型）。
                let World.World(w) = world;
                let next = match opt {
                    case Some(k) => Map.insert(id, k, w#playerSelectedItem)
                    case None    => Map.remove(id, w#playerSelectedItem)
                };
                World.World({playerSelectedItem = next | w})
            case Cmd.SetFacing(id, dir) =>
                let World.World(w) = world;
                World.World({playerFacing = Map.insert(id, dir, w#playerFacing) | w})
            case Cmd.SetPendingLevelUp(id, opt) =>
                // なし(None)は Map 非在で表現（selectedItem と同型）。
                let World.World(w) = world;
                let next = match opt {
                    case Some(r) => Map.insert(id, r, w#playerPendingLevelUp)
                    case None    => Map.remove(id, w#playerPendingLevelUp)
                };
                World.World({playerPendingLevelUp = next | w})
            case Cmd.SetMoveSteps(id, n) =>
                let World.World(w) = world;
                World.World({playerMoveSteps = Map.insert(id, n, w#playerMoveSteps) | w})
            case Cmd.SetEnemyResource(id, r) =>
                let World.World(w) = world;
                World.World({enemyResource = Map.insert(enemyUid(id), r, w#enemyResource) | w})
            case Cmd.SetEnemyProfile(id, p) =>
                let World.World(w) = world;
                World.World({enemyResourceId = Map.insert(enemyUid(id), p#resourceId, w#enemyResourceId),
                             enemyHomeModule = Map.insert(enemyUid(id), p#homeModuleIdx, w#enemyHomeModule) | w})
            case Cmd.SetMapSnapshot(mOpt) =>
                let World.World(w) = world;
                World.World({mapSnapshot = mOpt | w})
            case Cmd.SetMapLayout(lOpt) =>
                let World.World(w) = world;
                World.World({mapLayout = lOpt | w})
            case Cmd.SetTileLayers(handles) =>
                let World.World(w) = world;
                World.World({tileLayers = handles | w})
            case Cmd.SetEffectRule(id, rule) =>
                let World.World(w) = world;
                World.World({effectRule = Map.insert(enemyUid(id), rule, w#effectRule) | w})
            case Cmd.SetAnim(ref, name) =>
                // AnimatedSprite2D.play 意味論＝同名なら elapsed 継続、別名なら 0 リセット。
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
                // nextSeq で採番して挿入し +1。期限切れ drop は stepWorld（Cmd 不要）。
                let World.World(w) = world;
                let seq = w#popupFxNextSeq;
                World.World({popupFx = Map.insert(seq,
                                 {remaining = d#total, total = d#total, pos = d#pos,
                                  text = d#text, color = d#color}, w#popupFx),
                             popupFxNextSeq = seq + 1 | w})
            case Cmd.SpawnExplosionFx(d) =>
                // popupFx と同型（採番して挿入し +1）。
                let World.World(w) = world;
                let seq = w#explosionFxNextSeq;
                World.World({explosionFx = Map.insert(seq,
                                 {remaining = d#total, total = d#total, pos = d#pos, scale = d#scale},
                                 w#explosionFx),
                             explosionFxNextSeq = seq + 1 | w})
            case Cmd.SpawnFireShot(d) =>
                // ExplosionFx と同型（採番して挿入し +1）。seq をそのまま seed に使う＝撃つたびの
                // 表情替え・巻き戻しでも同じ絵。remaining=total で開始し tickFxMap が老化 / cull する。
                let World.World(w) = world;
                let seq = w#fireShotsNextSeq;
                World.World({fireShots = Map.insert(seq,
                                 {remaining = d#total, total = d#total, caster = d#caster,
                                  target = d#target, seed = seq},
                                 w#fireShots),
                             fireShotsNextSeq = seq + 1 | w})
            case Cmd.StartLunge(ref, d) =>
                // 体当たり往復の開始（同 entity の再スタートは置換＝旧再生の破棄）。
                // クロック（elapsed）は stepAnimClocks が進め、完了時に自分で除去する。
                let World.World(w) = world;
                World.World({lunges = Map.insert(toUid(ref),
                                 {origin = d#origin, target = d#target, elapsed = 0.0,
                                  hitAt = d#hitAt, total = d#total, hitFired = false},
                                 w#lunges) | w})
        }

    // ── SimEvent reducer / adapter / cmdKey ────────────────
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
                case ViewFxKind.FireShot(_)       => None
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
    def turnPhaseToInt(p: TurnPhase.Phase): Int32 = match p {
        case TurnPhase.Phase.PlayerCursor      => 0
        case TurnPhase.Phase.PlayerMoving      => 1
        case TurnPhase.Phase.ActionSelect      => 2
        case TurnPhase.Phase.WeaponSelect      => 3
        case TurnPhase.Phase.ItemSelect        => 4
        case TurnPhase.Phase.ItemActionSelect  => 5
        case TurnPhase.Phase.StaffAim          => 6
        case TurnPhase.Phase.ThrowAim          => 7
        case TurnPhase.Phase.TradeTargetSelect => 8
        case TurnPhase.Phase.TradeInventory    => 9
        case TurnPhase.Phase.AttackForecast    => 10
        case TurnPhase.Phase.PlayerAttack      => 11
        case TurnPhase.Phase.PlayerAttackHold  => 12
        case TurnPhase.Phase.LevelUpView       => 13
        case TurnPhase.Phase.GatherMove        => 14
        case TurnPhase.Phase.StairsExit        => 15
        case TurnPhase.Phase.EnemyTurn         => 16
        case TurnPhase.Phase.GameOver          => 17
        case TurnPhase.Phase.SuspendConfirm    => 18
    }

    /// GamePhase の ordinal（cmdKey の SetScreen 用）。
    def gamePhaseToInt(p: GamePhase): Int32 = match p {
        case GamePhase.Title           => 0
        case GamePhase.CharacterSelect => 1
        case GamePhase.Playing         => 2
    }

    /// Dir4 の ordinal（cmdKey の SetFacing 用）。
    def dirToInt(d: Dir4.Dir4): Int32 = match d {
        case Dir4.Up    => 0
        case Dir4.Down  => 1
        case Dir4.Left  => 2
        case Dir4.Right => 3
    }

    /// ItemKind の (種別 ordinal, index)（cmdKey の SetSelectedItem 用）。None は (-1, -1)。
    def itemKindKey(o: Option[PlayerData.ItemKind]): (Int32, Int32) = match o {
        case None                                  => (-1, -1)
        case Some(PlayerData.ItemKind.Weapon(i))     => (0, i)
        case Some(PlayerData.ItemKind.Staff(i))      => (1, i)
        case Some(PlayerData.ItemKind.Consumable(i)) => (2, i)
        case Some(PlayerData.ItemKind.Ring(i))       => (3, i)
    }

    /// TOTAL な Cmd → 比較キー (tag, uid, a, b)。`Cmd` に Eq が無いため golden-trace/simevent-algebra の
    /// 唯一の比較通貨。全 19 variant 上で網羅（exhaustiveness は `flix check` が強制）。
    /// faction 非依存に `toUid` で uid 化。control/lifecycle と payload-less は tag のみで discriminating。
    pub def cmdKey(c: Cmd): (String, Int32, Int32, Int32) =
        match c {
            case Cmd.SetHp(ref, hp)           => ("SetHp", toUid(ref), hp, 0)
            case Cmd.SetWeapons(ref, ws)      => ("SetWeapons", toUid(ref), List.length(ws), 0)
            // BaseStats は Eq 非自動ゆえ全 8 数値 field の和を digest に、maxHp を 4th に載せて oracle 可視化。
            case Cmd.SetBaseStats(ref, bs)    => ("SetBaseStats", toUid(ref),
                                                  bs#attack + bs#magicAttack + bs#defense + bs#magicDefense
                                                  + bs#skill + bs#speed + bs#luck + bs#maxHp, bs#maxHp)
            // WeaponView は Eq 非自動・Option ゆえ attack を digest に、武器なし(None)=-1 で discriminating。
            case Cmd.SetWeaponView(ref, wv)   => ("SetWeaponView", toUid(ref),
                                                  Option.map(v -> v#attack, wv) |> Option.getWithDefault(-1), 0)
            // Bonuses は Eq 非自動ゆえ 5 数値 field の和を digest に載せて oracle 可視化。
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
            case Cmd.SetPhase(p)              => ("Phase", turnPhaseToInt(p), 0, 0)
            case Cmd.SetScreen(s)            => ("Screen", gamePhaseToInt(s), 0, 0)
            case Cmd.SetParty(sel)           => ("SetParty", if (Option.isEmpty(sel)) 0 else 1, 0, 0)
            case Cmd.SetInitialSpawns(_)     => ("SetInitialSpawns", 0, 0, 0)
            case Cmd.SetFloorSnapshot(snap)  => ("SetFloorSnapshot", if (Option.isEmpty(snap)) 0 else 1, 0, 0)
            case Cmd.SetFloorId(_)           => ("SetFloorId", 0, 0, 0)
            case Cmd.SetArrowCursor(_)       => ("SetArrowCursor", 0, 0, 0)
            case Cmd.SetSelection(_)         => ("SetSelection", 0, 0, 0)
            case Cmd.TickPlayers(_)           => ("TickP", 0, 0, 0)
            case Cmd.TickEnemies              => ("TickE", 0, 0, 0)
            case Cmd.SetEnemyTurnBusy(b)      => ("ETBusy", bool01(b), 0, 0)
            case Cmd.SetPhaseObservedEnemy(b) => ("PhObs", bool01(b), 0, 0)
            case Cmd.SetStairs(cell)          =>
                let (x, y) = Option.map(p -> (p#x, p#y), cell) |> Option.getWithDefault((-1, -1));
                ("SetStairs", x, y, 0)
            case Cmd.AddVisited(mods)         => ("AddVisited", Set.size(mods), 0, 0)
            case Cmd.ClearVisited             => ("ClearVisited", 0, 0, 0)
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
            case Cmd.SetClassId(id, _)        => ("SetClassId", id, 0, 0)
            // resource は Eq 非自動ゆえ hp（最大 HP）を代表 digest に載せる（SetGrowth と同流儀）。
            case Cmd.SetPlayerResource(id, r) => ("SetPlayerResource", id, r#hp, 0)
            case Cmd.SetSelectedItem(id, o)   =>
                let (kind, idx) = itemKindKey(o);
                ("SetSelectedItem", id, kind, idx)
            case Cmd.SetFacing(id, d)         => ("SetFacing", id, dirToInt(d), 0)
            case Cmd.SetPendingLevelUp(id, o) => ("SetPendingLevelUp", id, if (Option.isEmpty(o)) 0 else 1, 0)
            case Cmd.SetMoveSteps(id, n)      => ("SetMoveSteps", id, n, 0)
            case Cmd.SetEnemyResource(id, r)  => ("SetEnemyResource", enemyUid(id), r#hp, 0)
            case Cmd.SetEnemyProfile(id, p)   => ("SetEnemyProfile", enemyUid(id), p#homeModuleIdx, 0)
            case Cmd.SetMapSnapshot(m)        => ("SetMapSnapshot", if (Option.isEmpty(m)) 0 else 1, 0, 0)
            case Cmd.SetMapLayout(l)          => ("SetMapLayout", if (Option.isEmpty(l)) 0 else 1, 0, 0)
            case Cmd.SetTileLayers(hs)        => ("SetTileLayers", List.length(hs), 0, 0)
            case Cmd.SetEffectRule(id, r)     => ("SetEffectRule", enemyUid(id), if (Option.isEmpty(r)) 0 else 1, 0)
            case Cmd.SetAnim(ref, name)       => ("SetAnim(${name})", toUid(ref), 0, 0)
            case Cmd.SetFlipH(ref, b)         => ("SetFlipH", toUid(ref), if (b) 1 else 0, 0)
            case Cmd.SetModulate(ref, col)    => ("SetModulate", toUid(ref),
                                                   Float64.truncateToInt32(Float32.toFloat64(col#r) * 255.0), 0)
            case Cmd.SpawnPopupFx(d)          => ("SpawnPopupFx", Float64.truncateToInt32(d#pos#x), Float64.truncateToInt32(d#pos#y), 0)
            case Cmd.SpawnExplosionFx(d)      => ("SpawnExplosionFx", Float64.truncateToInt32(d#pos#x), Float64.truncateToInt32(d#pos#y), 0)
            case Cmd.SpawnFireShot(d)         => ("SpawnFireShot", Float64.truncateToInt32(d#target#x), Float64.truncateToInt32(d#target#y), 0)
            case Cmd.StartLunge(ref, d)       => ("StartLunge", toUid(ref), Float64.truncateToInt32(d#target#x), Float64.truncateToInt32(d#target#y))
        }

    /// 敵の alerted を World から読む（hpOf 同型）。Player は常に None。
    pub def alertedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyAlerted)
        }

    /// 敵が死亡演出中か。Player は常に false。
    pub def isDyingOf(ref: EntityRef, world: World): Bool =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => false
            case EntityRef.Enemy(id)  => Set.memberOf(enemyUid(id), w#enemyDying)
        }

    /// 敵の bottleUsed を World から読む。Player は常に None。
    pub def bottleUsedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyBottleUsed)
        }

    /// 敵の prevPos を World から読む（None=未移動＝マップ非在）。Player は常に None。
    pub def prevPosOf(ref: EntityRef, world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyPrevPos)
        }

    /// 現在位置を World の pos-store（`Cmd.Move` 権威）から読む（両 faction・unified-id）。
    /// `prevPosOf`（敵直前位置）とは別物＝現在セル。ノックバック着地計算が攻撃側/防御側セルを引くのに要る。
    pub def posOf(ref: EntityRef, world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world; Map.get(toUid(ref), w#pos)

    /// 連続的な描画位置（pixel・tween 込み）。render System が読む。未 seed は None。
    pub def renderPosOf(ref: EntityRef, world: World): Option[{x = Float64, y = Float64}] =
        let World.World(w) = world; Map.get(toUid(ref), w#renderPos)

    /// 駒の描画 pixel 位置の単一導出（World が唯一の権威）。優先順:
    ///   lunge 中 = 往復補間（`lungeRenderPos`）／移動 tween 中・移動済み = renderPos／
    ///   未移動の静止駒 = セル中心（renderPos 未 seed）。未 spawn（pos 不在）は None。
    /// renderUnits / HP バー / 武器アイコンが読む（World store が唯一の読み口）。
    pub def visualPosOf(ref: EntityRef, world: World): Option[Vec2.Vec2] =
        match (lungePosOf(ref, world), renderPosOf(ref, world)) {
            case (Some(p), _)    => Some(p)
            case (None, Some(p)) => Some(p)
            case (None, None)    => posOf(ref, world) |> Option.map(MapSnapshot.cellCenter)
        }

    /// 移動 tween の始点用の描画位置（lunge を含まない）。tween 中は renderPos、静止駒はセル中心。
    /// `moveUnit` の start に渡す（lunge 中に移動が始まっても往復途中の座標を始点にしない）。
    pub def tweenStartPosOf(ref: EntityRef, world: World): Option[Vec2.Vec2] =
        match renderPosOf(ref, world) {
            case Some(p) => Some(p)
            case None    => posOf(ref, world) |> Option.map(MapSnapshot.cellCenter)
        }

    /// 盤上の全味方 id（昇順）。scene を介さない World 単独列挙（render / フォグ入力用）。
    pub def playerIdsOf(world: World): List[Int32] =
        let World.World(w) = world; Set.toList(w#playerIds)

    /// 盤上の全敵 id（昇順）。scene を介さない World 単独列挙（render / フォグ入力用）。
    pub def enemyIdsOf(world: World): List[Int32] =
        let World.World(w) = world; Set.toList(w#enemyIds)

    /// フォグ穴計算の入力（非導出の生値: 味方の live 位置と hidden）。World 単独導出（昇順）。
    /// origin（移動ドラフト）は view 側（`FogScene`）が重ねる。
    pub def fogUnitsOf(world: World): List[{id = Int32, gridPos = {x = Int32, y = Int32}, hidden = Bool}] =
        playerIdsOf(world) |> List.filterMap(id ->
            posOf(EntityRef.Player(id), world) |> Option.map(p ->
                {id = id, gridPos = p, hidden = playerHiddenOf(EntityRef.Player(id), world)}))

    /// 当該 entity が移動（Position）tween 中か（isMoving の World 版・input gate 用）。
    pub def isAnimating(ref: EntityRef, world: World): Bool =
        let World.World(w) = world; EcsTween.isActive((toUid(ref), Channel.Position), w#tweens)

    /// faction-blind な「移動」の唯一の発行口（smart constructor）。Position チャンネルへ span(start→target)
    /// の Vec tween を sec 秒・Linear で開始する Cmd を emit。味方 `PlayerScene.moveTo` と敵
    /// `EnemyScene.replayEnemyMoveView` が**共にこれを呼ぶ**（個別実装を畳む）。同型 Vec2 の誤順を防ぐため
    /// span は `VecLerp`（Track.Vec の payload）で名前渡し。不整合な (Channel, Track) を構築させない seam。
    pub def moveUnit(ref: EntityRef, span: EcsTween.VecLerp, sec: Float64): Unit \ Command =
        Command.emit(Cmd.StartTween(ref, Channel.Position, EcsTween.Track.Vec(span), sec, EcsTween.Easing.Linear, false))

    /// 背景 map タイルの描画ハンドル（render System が読む）。
    pub def tileLayersOf(world: World): List[TileLayerHandle] =
        let World.World(w) = world; w#tileLayers

    /// タイルハンドルを World にセット（`Cmd.SetTileLayers` の適用本体・テスト seed 用）。
    pub def setTileLayers(handles: List[TileLayerHandle], world: World): World =
        let World.World(w) = world; World.World({tileLayers = handles | w})

    /// followUpUsed を World から読む（両 faction）。単一 store＋toUid。
    pub def followUpUsedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world; Map.get(toUid(ref), w#followUpUsed)

    /// 味方 waited を World から読む。Enemy は常に None。
    pub def waitedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerWaited)
            case EntityRef.Enemy(_)   => None
        }

    /// 味方の usedStairs を World から読む。Enemy は常に None。
    pub def usedStairsOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerUsedStairs)
            case EntityRef.Enemy(_)   => None
        }

    /// attackTargetId を World から読む（None=非攻撃）。両 faction・単一 store＋toUid。
    pub def attackTargetOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world; Map.get(toUid(ref), w#attackTarget)

    /// いずれかの味方が攻撃中か。単一 store を uid 復元（plumbing）で faction filter。
    pub def anyPlayerAttacking(world: World): Bool =
        let World.World(w) = world;
        Map.exists((uid, _) -> uidIsPlayer(uid), w#attackTarget)

    /// いずれかの敵が攻撃中か。
    pub def anyEnemyAttacking(world: World): Bool =
        let World.World(w) = world;
        Map.exists((uid, _) -> uidIsEnemy(uid), w#attackTarget)

    /// coord 上の「瀕死でない」敵 id を World から引く（`EnemyScene.findIdAt` の World 版）。
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

    /// base 戦闘値 + maxHp を World から読む（unified-id・両 faction）。未登録は None。
    /// combatView がここを読み、status/ring 補正を加えて CombatView を組む。
    pub def baseStatsOf(ref: EntityRef, world: World): Option[Combat.BaseStats] =
        let World.World(w) = world; Map.get(toUid(ref), w#baseStats)

    // ── canonical comparison keys（proj 集約・drift 防止）──────────────
    // 各検証器の inline 射影を型ごと monomorphic な named key へ集約する。複数 call site が単一 def を
    // 共有すると「片方だけ弱体化」が構造的に不能になり S2.4/S4.4 級 drift を封じる（cmdKey/boardKey 慣習の横展開）。
    // ★E7574 回避: 在庫4種は別 record 型ゆえ共有 `let`-lambda は単相化で衝突する。型ごと top-level def は
    //   generalize されるので安全。将来 `let` 共有へ戻すと value restriction で E7574 を再誘発するため戻すな。
    // ★near-duplicate 2ペアは絶対に統合しない（§1.4）:
    //   weaponViewKey(8) ≠ weaponViewCombatKey(6) / ringKey(name,power) ≠ equippedRingKey(name,effect,power)。

    /// 在庫リストの代表射影: (長さ, 先頭要素の key)。多相 HOF（各 call site で a,b を fresh instantiate）。
    /// row には触れず引数の monomorphic keyFn 内でのみ field access する＝E7574-safe（attackTargetMap 前例）。
    /// 在庫 scene copy の退役で production 消費者は無くなり、テストの射影 seam として残す。
    pub def headKey(xs: List[a], keyFn: a -> b \ ef): (Int32, Option[b]) \ ef =
        (List.length(xs), List.head(xs) |> Option.map(keyFn))

    /// 在庫武器の代表キー (name, durability)。在庫比較テストの正準射影（drift 防止の単一源泉）。
    /// 元 lambda: w -> (w#name, w#durability)
    pub def weaponKey(w: UnitCatalog.WeaponResource): (String, Int32) = (w#name, w#durability)

    /// 杖の代表キー (name, durability)。在庫比較テストの正準射影。
    /// 元 lambda: s -> (s#name, s#durability)
    pub def staffKey(s: Staff.StaffResource): (String, Int32) = (s#name, s#durability)

    /// 消耗品の代表キー (name, durability)。在庫比較テストの正準射影。
    /// 元 lambda: c -> (c#name, c#durability)
    pub def consumableKey(c: Consumable.ConsumableResource): (String, Int32) = (c#name, c#durability)

    /// 在庫指輪の代表キー (name, power)。在庫比較テストの正準射影。
    /// ★equippedRingKey(name,effect,power) とは別物（在庫=power 代表 / 装備=RingEffect 必須）。
    /// 元 lambda: r -> (r#name, r#power)
    pub def ringKey(r: Ring.RingResource): (String, Int32) = (r#name, r#power)

    /// BaseStats の全 8 数値 field キー（baseStatsMismatches）。
    /// 元 lambda: bs -> (bs#attack, bs#magicAttack, bs#defense, bs#magicDefense, bs#skill, bs#speed, bs#luck, bs#maxHp)
    pub def baseStatsKey(bs: Combat.BaseStats): (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) =
        (bs#attack, bs#magicAttack, bs#defense, bs#magicDefense, bs#skill, bs#speed, bs#luck, bs#maxHp)

    /// status list の順序込みキー [(effect, magnitude, remaining)]。statuses 比較テストの正準射影。
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

    /// pendingLevelUp の Option キー (unitName, fromLevel, toLevel, 変化数)。比較テストの正準射影。
    /// 元 lambda: Option.map(r -> (r#unitName, r#fromLevel, r#toLevel, List.length(r#changes)))
    pub def pendingLevelUpKey(o: Option[LevelSystem.Result]): Option[(String, Int32, Int32, Int32)] =
        Option.map(r -> (r#unitName, r#fromLevel, r#toLevel, List.length(r#changes)), o)

    /// ★PlayerData.Data の field キー（playerDataMismatches）。scene が今も併記する field だけを
    /// 比較する（World 単独権威へ移した field は対象外）。sub-key（resourceStatKey）を再利用。
    pub def playerDataKey(d: PlayerData.Data):
            (Int32, String, Int32, Option[Int32],
             (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32),
             Bool) =
        // 注: followUpUsed は含めない。scene copy は退役し World 権威ゆえ DIFF 対象外
        //     （World 権威は dataFromWorld None-gate＋専用テストが保証）。
        // 注: hp / waited / level / exp も含めない。scene twin は退役（ECS 経路は World のみ書く）ゆえ
        //     scene 値は stale が正＝DIFF 対象外。World 権威は overlay（dataFromWorld）と World 直読みの
        //     読み手 ＋ 専用テストが保証。
        // 注: gridPos も含めない（scene twin 退役・読み手は World.posOf/overlay を読む）。
        // 注: selectedItem / moveStepsTaken / facing / usedStairs / pendingLevelUp /
        //     weapons / staves / consumables / rings / ringEquipped / statuses も含めない
        //     （scene twin 退役・World store が単独権威。読み手は accessor/overlay）。
        // 残る比較対象は「scene が今も併記する field」= id / classId / moveTiles(base) /
        // attackTargetId / resource（数値 stat 群で代表）/ hidden。
        (d#id, d#classId, d#moveTiles,
         d#attackTargetId, resourceStatKey(d#resource),
         d#hidden)

    /// ★EnemyData.Data の field キー（enemyDataMismatches）。playerDataKey と同流儀で、
    /// scene が今も併記する field だけを比較する（World 単独権威へ移した field は対象外）。
    pub def enemyDataKey(d: EnemyData.Data):
            (Int32, String, Bool, Int32, Int32, Bool, Option[Int32]) =
        // 注: bottleUsed / followUpUsed / prevPos は含めない。scene copy は退役し World 権威
        //     ゆえ scene 値は stale＝再構築(World)と必然的に食い違う。scene 読み手が World 経由ゆえ DIFF 対象外が正。
        // 注: hp も含めない（ECS 撃破は SetHp(0) のみで scene hp を書かず＝stale が正）。
        //     alerted/isDying は writer が scene 併記（dual-write）ゆえ残す。
        // 注: gridPos も含めない（playerDataKey と同じ理由）。
        // 注: acted / weapon / ring / statuses も含めない（scene twin 退役・World store が単独権威）。
        (d#id, d#resourceId, d#alerted, d#homeModuleIdx,
         d#moveTiles, d#isDying, d#attackTargetId)

    pub def moveTilesOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world; Map.get(toUid(ref), w#moveTiles)

    /// level-up 成長に要る基準 Stats + 成長率を World から読む（player-only。Enemy は常に None）。
    /// resolveCombat の level-up が resource を threading せず World 完結で成長を解くための seam。
    pub def growthOf(ref: EntityRef, world: World): Option[Growth] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#growth)
            case EntityRef.Enemy(_)   => None
        }

    /// 味方クラス id（UnitCatalog の逆引き key・spawn 静的）。Enemy は常に None。
    pub def classIdOf(ref: EntityRef, world: World): Option[String] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerClassId)
            case EntityRef.Enemy(_)   => None
        }

    /// 味方 resource テンプレート本体（スプライト/ステータス源）。Enemy は常に None。
    pub def playerResourceOf(ref: EntityRef, world: World): Option[UnitCatalog.UnitResource] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerResource)
            case EntityRef.Enemy(_)   => None
        }

    /// 敵 resource テンプレート本体。Player は常に None。
    pub def enemyResourceOf(ref: EntityRef, world: World): Option[EnemyCatalog.EnemyResource] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyResource)
        }

    /// 敵 catalog id（spawn 静的）。Player は常に None。
    pub def enemyResourceIdOf(ref: EntityRef, world: World): Option[String] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyResourceId)
        }

    /// 敵のスポーン部屋 idx（検知判定の補助・spawn 静的）。Player は常に None。
    pub def homeModuleIdxOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyHomeModule)
        }

    /// ItemMenu の選択中アイテム（None=未選択）。Enemy は常に None。
    pub def selectedItemOf(ref: EntityRef, world: World): Option[PlayerData.ItemKind] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerSelectedItem)
            case EntityRef.Enemy(_)   => None
        }

    /// 味方の向き。Enemy は常に None（敵は flipH のみで向きを持たない）。
    pub def facingOf(ref: EntityRef, world: World): Option[Dir4.Dir4] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerFacing)
            case EntityRef.Enemy(_)   => None
        }

    /// 直近レベルアップ結果（None=なし）。Enemy は常に None。
    pub def pendingLevelUpOf(ref: EntityRef, world: World): Option[LevelSystem.Result] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerPendingLevelUp)
            case EntityRef.Enemy(_)   => None
        }

    /// レベルアップ表示待ちの味方が 1 人でも居るか（LevelUpPanel の modal-gate が読む）。
    pub def anyPendingLevelUp(world: World): Bool =
        let World.World(w) = world;
        not Map.isEmpty(w#playerPendingLevelUp)

    /// レベルアップ表示待ちの味方 id（最小 id）。演出パネルが順に消化する。
    pub def firstPendingLevelUpId(world: World): Option[Int32] =
        let World.World(w) = world;
        Map.minimumKey(w#playerPendingLevelUp) |> Option.map(fst)

    /// AutoMove の当ターン進行済みマス数。Enemy は常に None。
    pub def moveStepsOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#playerMoveSteps)
            case EntityRef.Enemy(_)   => None
        }

    /// 敵の行動済みフラグを World から読む。Player は常に None。
    pub def actedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyActed)
        }

    /// 対象がローグ職か（盗人の剣の発動条件）。`growthOf#name`（=`resource#description`）を
    /// 読むだけで新 store は足さない。legacy `maybeThiefDrop` の `player#resource#description == "ローグ"` と同判定。
    /// Enemy は growth を持たない（growthOf=None）ため常に false＝ローグは player-only という前提を型で担保。
    pub def isRogueOf(ref: EntityRef, world: World): Bool =
        growthOf(ref, world) |> Option.map(g -> g#name == "ローグ") |> Option.getWithDefault(false)

    /// 装備武器の戦闘投影を World から読む（unified-id・両 faction）。
    /// 外側 Option（entity 未登録）と内側 Option（武器なし）を flatten し、武器なし＝None で返す
    /// （combatView#weapon の型と一致）。combatView がここを読む。
    pub def weaponViewOf(ref: EntityRef, world: World): Option[Combat.WeaponView] =
        let World.World(w) = world; Map.get(toUid(ref), w#weaponView) |> Option.flatten

    /// 装備指輪ボーナスを World から読む（unified-id・両 faction）。未登録は None。
    /// combatView がここを読み、base + ring + status を合成する。
    pub def ringBonusOf(ref: EntityRef, world: World): Option[Ring.Bonuses] =
        let World.World(w) = world; Map.get(toUid(ref), w#ringBonus)

    /// 装備指輪リソース本体を World から読む（unified-id・両 faction）。外側 Option（entity 未登録）と
    /// 内側 Option（未装備）を flatten ＝未装備で None（`weaponViewOf` を逐語踏襲）。finisher/lifesteal が読む。
    pub def equippedRingOf(ref: EntityRef, world: World): Option[Ring.RingResource] =
        // player 側は rings/ringEquipped store から**読み時導出**。
        // 敵側は Cmd.SetEnemyRing が書く equippedRing store。
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) =>
                if (Map.get(id, w#ringEquipped) |> Option.getWithDefault(false))
                    Map.get(id, w#rings) |> Option.flatMap(List.head)
                else None
            case EntityRef.Enemy(_) => Map.get(toUid(ref), w#equippedRing) |> Option.flatten
        }

    /// 敵特殊能力 effectRule（生 Json）を World から読む（敵のみ・unified-id）。外側 Option（未登録）と
    /// 内側 Option（ルールなし）を flatten ＝ルールなしで None（`weaponViewOf` を逐語踏襲）。敵パスの sim 発火判定が読む。
    pub def effectRuleOf(ref: EntityRef, world: World): Option[Util.Json.Json] =
        let World.World(w) = world; Map.get(toUid(ref), w#effectRule) |> Option.flatten

    /// `combatView` を **World だけから再構築**する（faction 非依存）。base 戦闘値 + 指輪 + status mods
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

    /// いずれかの味方が潜伏中か（World の `playerHidden` set 由来）。Enemy は常に false。
    /// scene `unitView` の `hidden = data#hidden` と一致（playerHidden は `d#hidden` の味方を集めた set）。
    pub def playerHiddenOf(ref: EntityRef, world: World): Bool =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Set.memberOf(id, w#playerHidden)
            case EntityRef.Enemy(_)   => false
        }

    /// scene の `PlayerScene.unitView` / `EnemyScene.unitView` と **bit 一致**する `UnitView` を
    /// **World 単独**（scene 非依存）で再構築する。pos/hp/moveTiles/weaponRange/combat/isDying/hidden は
    /// 各 store から、`aiType`（+ player の load 容量に要る constitution/attack）は resource store
    /// （playerResource/enemyResource）から読む。`combatViewOf` が None（base/hp/ring 未登録）なら全体 None。
    /// 味方の `moveTiles` は scene と同じく `Encumbrance.effectiveMoveTiles(base, load)`（load は **World 在庫**の重量合計）、
    /// 敵は base そのまま。`weaponRange` は先頭武器の range（player=weapons 先頭・enemy=0/1 List 射影の先頭）。
    pub def unitViewFromWorld(ref: EntityRef, world: World): Option[UnitView] =
        match (posOf(ref, world), hpOf(ref, world), combatViewOf(ref, world), moveTilesOf(ref, world)) {
            case (Some(pos), Some(hp), Some(combat), Some(base)) =>
                let weaponRange = weaponsOf(ref, world)
                    |> Option.flatMap(List.head) |> Option.map(w -> w#range);
                match ref {
                    case EntityRef.Player(id) =>
                        // 味方の実効移動力: 素の moveTiles に積載ペナルティ（load）を掛けた値。
                        // load の重量合計は World 在庫（weapons/staves/consumables/rings）から、
                        // 容量に要る constitution/attack は playerResource store から。
                        match playerResourceOf(ref, world) {
                            case None    => None
                            case Some(res) =>
                                // 在庫レコードは関数引数位置（カンマ後）に直接書く＝record リテラル明確化（先頭 `let = {` は block 誤認される）。
                                let load = Encumbrance.loadOf(res#constitution, res#attack,
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
                        match enemyResourceOf(ref, world) {
                            case None    => None
                            case Some(res) =>
                                Some({id = id, faction = Faction.Enemy, pos = pos, hp = hp,
                                      moveTiles = base, weaponRange = weaponRange, combat = combat,
                                      isDying = isDyingOf(ref, world), hidden = false,
                                      aiType = res#aiType})
                        }
                }
            case _ => None
        }

    /// `PlayerData.Data` を **World 単独**（scene 非依存）で再構築する。全 23 field が World store 由来:
    ///   gate 対象 16: gridPos=posOf／hp=hpOf／waited=waitedOf／moveTiles=moveTilesOf／weapons=weaponsOf／
    ///     staves=stavesOf／consumables=consumablesOf／rings=ringsOf／ringEquipped=ringEquippedOf／
    ///     followUpUsed=followUpUsedOf／(level,exp)=progressOf／classId=classIdOf／resource=playerResourceOf／
    ///     facing=facingOf／moveStepsTaken=moveStepsOf／usedStairs=usedStairsOf。
    ///   default 供給 5: attackTargetId・selectedItem・pendingLevelUp（Option 直・非在=None）／
    ///     hidden=playerHiddenOf（集合）／statuses=statusEffectsOf（default-Nil）。
    ///   id = 引数。
    /// gate field が一つでも None（未 spawn/despawn 済み）なら全体 None。
    pub def dataFromWorld(id: Int32, world: World): Option[PlayerData.Data] =
        let ref = EntityRef.Player(id);
        forM (
            pos          <- posOf(ref, world);
            hp           <- hpOf(ref, world);
            waited       <- waitedOf(ref, world);
            moveTiles    <- moveTilesOf(ref, world);
            weapons      <- weaponsOf(ref, world);
            staves       <- stavesOf(ref, world);
            consumables  <- consumablesOf(ref, world);
            rings        <- ringsOf(ref, world);
            ringEquipped <- ringEquippedOf(ref, world);
            followUpUsed <- followUpUsedOf(ref, world);
            progress     <- progressOf(ref, world);
            classId      <- classIdOf(ref, world);
            resource     <- playerResourceOf(ref, world);
            facing       <- facingOf(ref, world);
            moveSteps    <- moveStepsOf(ref, world);
            usedStairs   <- usedStairsOf(ref, world)
        ) yield {
            let (level, exp) = progress;
            ({id = id, classId = classId, gridPos = pos, moveTiles = moveTiles, hp = hp,
              waited = waited, attackTargetId = attackTargetOf(ref, world),
              resource = resource, weapons = weapons, staves = staves,
              consumables = consumables, rings = rings, ringEquipped = ringEquipped,
              selectedItem = selectedItemOf(ref, world), moveStepsTaken = moveSteps,
              facing = facing, hidden = playerHiddenOf(ref, world), usedStairs = usedStairs,
              level = level, exp = exp, pendingLevelUp = pendingLevelUpOf(ref, world),
              statuses = statusEffectsOf(ref, world), followUpUsed = followUpUsed}: PlayerData.Data)
        }

    /// scene の `EnemyScene.get` Data と **bit 一致**する `EnemyData.Data` を **World 由来**で再構築する
    /// （dataFromWorld〔player版〕の enemy 版）。`EnemyData.Data` を **World 単独**で再構築する。
    ///   gate 対象 11: gridPos=posOf／alerted=alertedOf／moveTiles=moveTilesOf／hp=hpOf／
    ///     weapon=weaponsOf(0/1 List) の head／followUpUsed=followUpUsedOf／bottleUsed=bottleUsedOf／
    ///     resourceId=enemyResourceIdOf／resource=enemyResourceOf／homeModuleIdx=homeModuleIdxOf／acted=actedOf。
    ///   default 供給: isDying は Bool 直 / attackTargetId・prevPos・ring は Option 直 / statuses は default-Nil。
    ///   id = 引数。
    /// gate field が一つでも None（未 spawn/despawn 済み）なら全体 None（dataFromWorld と同じ gate 流儀）。
    pub def dataFromWorldEnemy(id: Int32, world: World): Option[EnemyData.Data] =
        let ref = EntityRef.Enemy(id);
        forM (
            pos           <- posOf(ref, world);
            alerted       <- alertedOf(ref, world);
            moveTiles     <- moveTilesOf(ref, world);
            hp            <- hpOf(ref, world);
            weapons       <- weaponsOf(ref, world);
            followUpUsed  <- followUpUsedOf(ref, world);
            bottleUsed    <- bottleUsedOf(ref, world);
            resourceId    <- enemyResourceIdOf(ref, world);
            resource      <- enemyResourceOf(ref, world);
            homeModuleIdx <- homeModuleIdxOf(ref, world);
            acted         <- actedOf(ref, world)
        ) yield
            ({id = id, resourceId = resourceId, gridPos = pos, alerted = alerted,
              homeModuleIdx = homeModuleIdx, moveTiles = moveTiles, hp = hp,
              isDying = isDyingOf(ref, world), attackTargetId = attackTargetOf(ref, world),
              resource = resource, weapon = List.head(weapons), acted = acted,
              prevPos = prevPosOf(ref, world), statuses = statusEffectsOf(ref, world),
              ring = equippedRingOf(ref, world), followUpUsed = followUpUsed,
              bottleUsed = bottleUsed}: EnemyData.Data)

    /// 味方の (level, exp) を World から読む。未登録は None。Enemy は常に None。
    pub def progressOf(ref: EntityRef, world: World): Option[(Int32, Int32)] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) =>
                Option.flatMap(lv -> Option.map(xp -> (lv, xp), Map.get(id, w#playerExp)),
                               Map.get(id, w#playerLevel))
            case EntityRef.Enemy(_)   => None
        }

    /// 敵ターン intro hold 中か（`TopBarUi.isBusyOf` の World 版・順序非依存）。
    pub def enemyTurnBusyOf(world: World): Bool =
        let World.World(w) = world; w#enemyTurnBusy

    /// バーが敵ターン観測済みか（`TopBarUi.hasObservedEnemyOf` の World 版・順序非依存）。
    pub def phaseObservedEnemyOf(world: World): Bool =
        let World.World(w) = world; w#phaseObservedEnemy

    /// hp を World から読む（read-model アクセサ）。検証器の供給元。
    /// 単一 store＋toUid。
    pub def hpOf(ref: EntityRef, world: World): Option[Int32] =
        let World.World(w) = world; Map.get(toUid(ref), w#hp)

    /// weapons を World から読む（read-model アクセサ・hpOf 同型）。未登録は None。
    /// 内側 List は player の weapons / enemy の 0/1 List 射影。
    pub def weaponsOf(ref: EntityRef, world: World): Option[List[UnitCatalog.WeaponResource]] =
        let World.World(w) = world; Map.get(toUid(ref), w#weapons)

    /// staves を World から読む（read-model アクセサ・player-only・waitedOf 流儀）。Enemy は常に None。
    pub def stavesOf(ref: EntityRef, world: World): Option[List[Staff.StaffResource]] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#staves)
            case EntityRef.Enemy(_)   => None
        }

    /// consumables を World から読む（player-only）。Enemy は常に None。
    pub def consumablesOf(ref: EntityRef, world: World): Option[List[Consumable.ConsumableResource]] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#consumables)
            case EntityRef.Enemy(_)   => None
        }

    /// rings を World から読む（player-only）。Enemy は常に None。
    pub def ringsOf(ref: EntityRef, world: World): Option[List[Ring.RingResource]] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#rings)
            case EntityRef.Enemy(_)   => None
        }

    /// ringEquipped を World から読む（player-only・Bool）。Enemy は常に None。
    pub def ringEquippedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) => Map.get(id, w#ringEquipped)
            case EntityRef.Enemy(_)   => None
        }

    /// unified-id の faction を **enum タグ component** から読む。
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

    /// hp を変える PlanItem（heal/fullHeal/damage/maxHpUp/revive）について、**runPlan 適用後の World**
    /// から各対象の hp を読み戻して `Cmd.SetHp` を境界で emit する。heal/fullHeal は handler が
    /// 適用時に emit 済みなので、ここは同値の再 emit（冪等）。MaxHpUpAt だけは適用の実体を
    /// ここが担う（handler は no-op）: 現在の resource#hp / hp に +inc して
    /// SetHp / SetBaseStats / SetResource を emit する（read-after-write で連鎖も合成される）。
    /// `emitStatusAdds` と同じ責務分離（handler / 境界 emit）。runPlan の **後**に渡す。
    pub def emitHpSets(items: List[EffectPlan.PlanItem]): Unit \ {Command, WorldQuery} =
        items |> List.forEach(item -> match item {
            case EffectPlan.PlanItem.HealAt(id, ally, _)    => emitHpAt(id, ally)
            case EffectPlan.PlanItem.FullHealAt(id, ally)   => emitHpAt(id, ally)
            case EffectPlan.PlanItem.DamageAt(id, ally, _)  => emitHpAt(id, ally)
            case EffectPlan.PlanItem.MaxHpUpAt(id, ally, n) => emitMaxHpUpAt(id, ally, n)
            case EffectPlan.PlanItem.ReviveAt(id, ally)     => emitHpAt(id, ally)
            case _ => ()
        })

    /// 対象の現 hp を World から読み（居なければ no-op）、`Cmd.SetHp` を emit する内部ヘルパー。
    def emitHpAt(id: EntityId, ally: Bool): Unit \ {Command, WorldQuery} =
        match hpOf(refOf(ally, id), WorldQuery.get()) {
            case Some(hp) => Command.emit(Cmd.SetHp(refOf(ally, id), hp))
            case None     => ()
        }

    /// 最大HP上昇（命の草）の適用本体。現在の resource / hp に +inc して
    /// SetHp → SetBaseStats → SetResource の順で emit する（居なければ no-op）。
    def emitMaxHpUpAt(id: EntityId, ally: Bool, inc: Int32): Unit \ {Command, WorldQuery} =
        let w = WorldQuery.get();
        if (ally)
            match (hpOf(EntityRef.Player(id), w), playerResourceOf(EntityRef.Player(id), w)) {
                case (Some(hp), Some(res)) =>
                    let updated = {hp = res#hp + inc | res};
                    Command.emit(Cmd.SetHp(EntityRef.Player(id), hp + inc));
                    Command.emit(Cmd.SetBaseStats(EntityRef.Player(id), Combat.baseStatsFrom(updated)));
                    Command.emit(Cmd.SetPlayerResource(id, updated))
                case _ => ()
            }
        else
            match (hpOf(EntityRef.Enemy(id), w), enemyResourceOf(EntityRef.Enemy(id), w)) {
                case (Some(hp), Some(res)) =>
                    let updated = {hp = res#hp + inc | res};
                    Command.emit(Cmd.SetHp(EntityRef.Enemy(id), hp + inc));
                    Command.emit(Cmd.SetBaseStats(EntityRef.Enemy(id), Combat.baseStatsFrom(updated)));
                    Command.emit(Cmd.SetEnemyResource(id, updated))
                case _ => ()
            }

    /// World だけから Board を組む（scene 非依存）。地形は store した `mapSnapshot`（未確定なら None）、
    /// 駒は pure-World `boardPieces`（`Cmd.Move` 権威・hidden 除外）。`BoardQuery` handler・
    /// 敵ターンの盤面構築・ノックバックの sim 着地計算が読む唯一の Board 構築口。
    pub def boardOf(world: World): Option[Board] =
        let World.World(w) = world;
        Option.map(m -> ({map = m, pieces = boardPieces(world)}: Board), w#mapSnapshot)

    /// 階段セル座標を World から読む（未配置なら None）。warp 先計算（`warpCellFor`）が読む。
    /// scene の `Stairs.getPos` を mirror した read-model（`boardOf` と同じく scene 非依存 sim を可能にする seam）。
    pub def stairsPosOf(world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world; w#stairsPos

    /// 静的地形（MapSnapshot）を World から読む（None=盤面レス画面）。
    /// 「盤面がある画面でのみ動く」ドライバ / 描画の存在ゲートと placements 読みの共通窓口。
    pub def terrainOf(world: World): Option[MapSnapshot] =
        let World.World(w) = world; w#mapSnapshot

    /// 地形を「必ず在る」前提で読む版（spawn 系 / 範囲計算など盤面のある画面専用）。
    /// 盤面レス画面での呼び出しは配線ミスとして即落とす（fail-open が欲しい読み手は `terrainOf`）。
    pub def terrainOrBug(world: World): MapSnapshot =
        match terrainOf(world) {
            case Some(m) => m
            case None    => bug!("World.terrainOrBug: terrain not seeded (board-less screen)")
        }

    /// 盤面（ダンジョンマップ）が World に seed 済みか。Title / CharacterSelect など盤面レス画面では偽。
    /// カーソル移動・カメラ追従・ミニマップなどの Map 存在ゲートが共通で使う唯一の判定点（`boardOf` と同源）。
    pub def hasBoard(world: World): Bool =
        not Option.isEmpty(terrainOf(world))

    /// マップ生成 Plan＋スポーン起点を World から読む（None=盤面レス画面）。
    pub def mapLayoutOf(world: World): Option[MapLayout] =
        let World.World(w) = world; w#mapLayout

    /// 配置済み全モジュールのワールド bbox（idx 順）。盤面レス画面は Nil。
    /// 敵 / アイテム / 宝箱のスポーン候補列挙・フォグ・ミニマップが読む。
    pub def placementsOf(world: World): List[DungeonComposer.ModulePlacement] =
        terrainOf(world) |> Option.map(m -> m#placements) |> Option.getWithDefault(Nil)

    /// 部屋数。`idx < roomCount` なら部屋、それ以外は通路と判定できる。盤面レス画面は 0。
    pub def roomCountOf(world: World): Int32 =
        mapLayoutOf(world) |> Option.map(l -> l#plan#roomCount) |> Option.getWithDefault(0)

    /// anchor 部屋内の床が保証されたスポーン起点（Player 初期配置）。盤面確定後の build 中にのみ
    /// 読む前提で、未 seed の呼び出しは配線ミスとして即落とす。
    pub def spawnGridOf(world: World): {x = Int32, y = Int32} =
        match mapLayoutOf(world) {
            case Some(l) => l#spawnGrid
            case None    => bug!("World.spawnGridOf: mapLayout not seeded")
        }

    /// このフロアを生成した Plan（FloorSnapshot 保存が読む）。未 seed の呼び出しは配線ミスとして即落とす。
    pub def mapPlanOf(world: World): DungeonGenerator.Plan =
        match mapLayoutOf(world) {
            case Some(l) => l#plan
            case None    => bug!("World.mapPlanOf: mapLayout not seeded")
        }

    /// フロア全域の探索記憶（訪問済み module idx）を World から読む。ミニマップ描画と
    /// カーソル可動域判定が読む read-model。`Cmd.AddVisited` が union・`Cmd.ClearVisited` が一掃。
    pub def visitedModulesOf(world: World): Set[Int32] =
        let World.World(w) = world; w#visited

    /// 配置物 store のセル key（1 セル 1 個ゆえ cell が一意 key＝record の Eq/Order を避け Int32 に符号化）。
    /// グリッドは各軸 1000 未満（ダンジョンセル）ゆえ `x*1000 + y` で衝突しない。chests/groundItems 共通。
    pub def cellKey(cell: {x = Int32, y = Int32}): Int32 = cell#x * 1000 + cell#y

    /// 宝箱 store のセル key（`cellKey` の別名・既存 API 名として保持）。
    pub def chestCellKey(cell: {x = Int32, y = Int32}): Int32 = cellKey(cell)

    /// 宝箱 store を World から読む（cell key → Data）。
    pub def chestsOf(world: World): Map[Int32, Chests.Data] =
        let World.World(w) = world; w#chests

    /// 指定セルの宝箱を World から読む（`Chests.findAt` の World 版）。
    pub def chestAtOf(cell: {x = Int32, y = Int32}, world: World): Option[Chests.Data] =
        let World.World(w) = world; Map.get(cellKey(cell), w#chests)

    /// 床アイテム store を World から読む（cell key → Data）。
    pub def groundItemsOf(world: World): Map[Int32, GroundItems.Data] =
        let World.World(w) = world; w#groundItems

    /// 指定セルの床アイテムを World から読む（`GroundItems.dataAt` の World 版）。
    pub def groundItemAtOf(cell: {x = Int32, y = Int32}, world: World): Option[GroundItems.Data] =
        let World.World(w) = world; Map.get(cellKey(cell), w#groundItems)

    /// ダメージ数字 fx store（seq → 寿命）。syncView が読み scene 子 Label2D を派生する。
    pub def popupFxOf(world: World): Map[Int32, PopupFx] =
        let World.World(w) = world; w#popupFx

    /// 次に spawn する popup fx の連番。emit が子ノード名 `Popup_<seq>` の採番に読む
    /// （Cmd.SpawnPopupFx の applyCmd がこの値で挿入して +1 する＝read-after-write で一致）。
    pub def popupFxNextSeqOf(world: World): Int32 =
        let World.World(w) = world; w#popupFxNextSeq

    /// 爆発 fx store（seq → 寿命）。
    pub def explosionFxOf(world: World): Map[Int32, ExplosionFx] =
        let World.World(w) = world; w#explosionFx

    /// 魔導書の炎 3 幕 fx store（seq → エントリ）。`RenderWorld.renderFireShots` が elapsed を導いて描く。
    pub def fireShotsOf(world: World): Map[Int32, FireShot] =
        let World.World(w) = world; w#fireShots

    /// 再生中アニメ（AnimatedSprite2D 個体のみ登録）。未登録は None。
    pub def unitAnimOf(ref: EntityRef, world: World): Option[UnitAnim] =
        let World.World(w) = world; Map.get(toUid(ref), w#unitAnim)

    /// 左右反転。未登録は false（反転なし）。
    pub def flipHOf(ref: EntityRef, world: World): Bool =
        let World.World(w) = world; Map.get(toUid(ref), w#unitFlipH) |> Option.getWithDefault(false)

    /// 待機/行動済み暗転色（本体/HP バー/武器アイコン共通の単一真実源）。未登録は白。
    pub def modulateOf(ref: EntityRef, world: World): Color =
        let World.World(w) = world;
        Map.get(toUid(ref), w#unitModulate)
            |> Option.getWithDefault({r = 1.0f32, g = 1.0f32, b = 1.0f32})

    /// 死亡点滅の経過秒（SetDying からの実時間）。非 dying は None。
    pub def dyingElapsedOf(ref: EntityRef, world: World): Option[Float64] =
        let World.World(w) = world; Map.get(toUid(ref), w#dyingElapsed)

    /// Board の駒を**順序非依存**で突合する正規形（(faction, id, x, y) 昇順）。
    /// `Board` は型エイリアスで Eq derive 不可・pieces 順が World(id昇順) と fromScene(preorder) で違うため、
    /// 検証器（World 由来盤面 vs scene 由来盤面の mid-frame 突合）はこのキーで比較する。
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
        // 単一 `pos` store を **team タグ**で faction 分けして Piece 化（hidden 味方は除外）。
        let World.World(w) = world;
        Map.toList(w#pos) |> List.filterMap(pair -> {
            let (uid, pos) = pair;
            match uidToRef(uid) {
                case EntityRef.Player(pid) =>
                    if (Set.memberOf(pid, w#playerHidden)) None else Some((Piece.Player(pid), pos))
                case EntityRef.Enemy(eid)  => Some((Piece.Enemy(eid), pos))
            }
        })

}
