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

/// S-A0（Phase B 土台）: `combatView` が読む base 戦闘値（resource 由来・status/ring 補正**前**）。
/// stats（攻/魔攻/防/魔防/技/速/運）+ maxHp を 1 component に束ねた **read-model**。
/// resource 由来ゆえ scene から純粋導出でき、refreshMirror で毎フレーム再 mirror（statusEffects と同型・
/// 構築上常に scene と一致＝emit/DIFF 不要）。B1 で combatView の reader をここへ flip する。
pub type alias BaseStats = {
    attack = Int32, magicAttack = Int32, defense = Int32, magicDefense = Int32,
    skill = Int32, speed = Int32, luck = Int32, maxHp = Int32
}

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
                 // S3: gridPos の read-model mirror。型は Vec2i の structural record（engine_core.Vec2i の演算 API 対象）。
                 // 権威は scene のまま。S4 で Board を fromWorld 化する時の World 側位置ソース候補（mirror）。
                 // A': pos は単一 store（unified-id）。両 faction の split を撤廃。
                 pos = Map[EntityId, {x = Int32, y = Int32}],
                 // S4: 盤面除外（集合・階段退場）中の味方 id。Board.pieces は hidden 味方を除くので fromWorld に必要。
                 playerHidden = Set[EntityId],
                 // F7-spike: 敵の検知フラグ（dormant→chase）。flag→World の最初のプローブ。
                 enemyAlerted = Map[EntityId, Bool],
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
                 // F8-slice1: 攻撃対象 id（攻撃モーション中＝anyAttacking の権威）。None=非攻撃はマップ非在。両 faction。
                 // A': attackTarget は単一 store（unified-id）。両 faction の split を撤廃。
                 attackTarget = Map[EntityId, Int32],
                 // World 拡張: 味方の進行度（level/exp）。combat の撃破→exp→level-up が動かす sim 状態。
                 // 過去に level-up の hp 増分 dual-write が漏れた領域＝検証器で同種漏れを捕える。player-only。
                 playerLevel = Map[EntityId, Int32], playerExp = Map[EntityId, Int32],
                 // S-A0: base 戦闘値 + maxHp の read-model（unified-id・両 faction）。resource 由来ゆえ
                 // refreshMirror で毎フレーム scene から再 mirror（statusEffects と同型）。combatView flip 用。
                 baseStats = Map[EntityId, BaseStats],
                 // S-A0b: 装備武器の戦闘投影 read-model（unified-id・両 faction）。内側 Option=武器なし。
                 // PlayerScene/EnemyScene.equippedWeaponView 由来ゆえ毎フレーム再 mirror。combatView flip 用。
                 weaponView = Map[EntityId, Option[Combat.WeaponView]],
                 // S-A0c: 装備指輪ボーナス read-model（unified-id・両 faction）。未装備は zeroBonuses。
                 // equippedRingBonus 由来ゆえ毎フレーム再 mirror。combatView flip 用。
                 ringBonus = Map[EntityId, Ring.Bonuses],
                 // F8-slice2: 敵ターン driver が読む phase-banner 同期 bool（TopBar が毎フレーム dual-write）。
                 //   enemyTurnBusy      — 敵ターン開始 intro の hold 中（>0）＝敵の行動開始待ち。
                 //   phaseObservedEnemy — 上部バーが「敵ターン」を観測済み（0 体ターンの取りこぼし防止）。
                 // どちらも view-timing 由来だが driver の順序非依存化のため World 経由で読む（生アニメ Data は TopBar 残置）。
                 enemyTurnBusy = Bool, phaseObservedEnemy = Bool })
}

mod World {

    pub def empty(): World =
        World.World({tick = 0, turnPhase = SimPhase.PlayerTurn,
                     playerIds = Set.empty(), enemyIds = Set.empty(),
                     statusEffects = Map.empty(),
                     hp = Map.empty(), team = Map.empty(),
                     pos = Map.empty(),
                     playerHidden = Set.empty(), enemyAlerted = Map.empty(),
                     enemyDying = Set.empty(),
                     enemyBottleUsed = Map.empty(), enemyPrevPos = Map.empty(),
                     followUpUsed = Map.empty(),
                     playerWaited = Map.empty(),
                     attackTarget = Map.empty(),
                     playerLevel = Map.empty(), playerExp = Map.empty(),
                     baseStats = Map.empty(), weaponView = Map.empty(), ringBonus = Map.empty(),
                     enemyTurnBusy = false, phaseObservedEnemy = false})

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
    /// S-A0: resource record（UnitResource / EnemyResource 両対応・row-poly）から base 戦闘値を抽出する。
    /// status/ring 補正は載せない（combatView が読み取り時に加える）。maxHp は resource#hp。
    pub def baseStatsFrom(r: {attack = Int32, magicAttack = Int32, defense = Int32,
                             magicDefense = Int32, skill = Int32, speed = Int32,
                             luck = Int32, hp = Int32 | rest}): BaseStats =
        {attack = r#attack, magicAttack = r#magicAttack, defense = r#defense,
         magicDefense = r#magicDefense, skill = r#skill, speed = r#speed,
         luck = r#luck, maxHp = r#hp}

    def attackTargetMap(uidOf: Int32 -> EntityId, units: List[{id = Int32, attackTargetId = Option[Int32] | r}]): Map[EntityId, Int32] =
        List.foldLeft((m, d) -> match d#attackTargetId {
            case Some(t) => Map.insert(uidOf(d#id), t, m)
            case None    => m
        }, Map.empty(), units)

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
            pos = Map.union(Query.indexBy(d -> d#id, d -> d#gridPos, players),
                            Query.indexBy(d -> enemyUid(d#id), d -> d#gridPos, enemies)),
            playerHidden   = Query.tagOf(d -> d#id, List.filter(d -> d#hidden, players)),
            enemyDying     = Query.tagOf(d -> enemyUid(d#id), List.filter(d -> d#isDying, enemies)),
            enemyAlerted   = Query.indexBy(d -> enemyUid(d#id), d -> d#alerted, enemies),
            enemyBottleUsed = Query.indexBy(d -> enemyUid(d#id), d -> d#bottleUsed, enemies),
            enemyPrevPos   = List.foldLeft((m, d) -> match d#prevPos {
                                 case Some(p) => Map.insert(enemyUid(d#id), p, m)
                                 case None    => m
                             }, Map.empty(), enemies),
            followUpUsed = Map.union(Query.indexBy(d -> d#id, d -> d#followUpUsed, players),
                                     Query.indexBy(d -> enemyUid(d#id), d -> d#followUpUsed, enemies)),
            playerWaited   = Query.indexBy(d -> d#id, d -> d#waited, players),
            playerLevel    = Query.indexBy(d -> d#id, d -> d#level, players),
            playerExp      = Query.indexBy(d -> d#id, d -> d#exp, players),
            baseStats = Map.union(Query.indexBy(d -> d#id, d -> baseStatsFrom(d#resource), players),
                                  Query.indexBy(d -> enemyUid(d#id), d -> baseStatsFrom(d#resource), enemies)),
            weaponView = Map.union(Query.indexBy(d -> d#id, d -> PlayerScene.equippedWeaponView(d), players),
                                   Query.indexBy(d -> enemyUid(d#id), d -> EnemyScene.equippedWeaponView(d), enemies)),
            ringBonus = Map.union(Query.indexBy(d -> d#id, d -> PlayerScene.equippedRingBonus(d), players),
                                  Query.indexBy(d -> enemyUid(d#id), d -> EnemyScene.equippedRingBonus(d), enemies)),
            attackTarget = Map.union(attackTargetMap(id -> id, players),
                                     attackTargetMap(enemyUid, enemies)),
            // F8-slice2: scene に mirror 元がない scalar bool は前 world の値を保持（command 由来）。
            enemyTurnBusy      = w#enemyTurnBusy,
            phaseObservedEnemy = w#phaseObservedEnemy
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
            statusEffects = Map.union(Query.indexBy(d -> d#id, d -> d#statuses, players),
                                      Query.indexBy(d -> enemyUid(d#id), d -> d#statuses, enemies)),
            // F6b: hp も command 由来を保持＋prune（位置と同様）。全 hp 書込が `Cmd.SetHp` を dual-write
            // 済み（`[F6 HP DIFF]` 無音で確認）ゆえ World hp == scene hp で挙動不変。これで **hp は World 権威**。
            hp = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#hp),
            // 位置は command 由来を保持＋scene に居ない id を prune（gridPos からの再構築はしない）。
            pos = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#pos),
            playerHidden   = Query.tagOf(d -> d#id, List.filter(d -> d#hidden, players)),
            // 軸1 仕上げ: isDying も command 由来を保持＋prune（death 完了でノード除去→自動 prune）。
            // A': enemy-only store も unified-id key＝prune は validUids で統一。
            enemyDying     = Set.filter(uid -> Set.memberOf(uid, validUids), w#enemyDying),
            enemyAlerted   = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#enemyAlerted),
            enemyBottleUsed = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#enemyBottleUsed),
            enemyPrevPos   = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#enemyPrevPos),
            followUpUsed = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#followUpUsed),
            playerWaited   = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerWaited),
            // World 拡張: level/exp も command 由来を保持＋prune（hp と同型）。
            playerLevel    = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerLevel),
            playerExp      = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerExp),
            // S-A0: baseStats は resource 由来の read-model ＝ scene から毎フレーム再 mirror（statusEffects と同型・command 由来でない）。
            baseStats = Map.union(Query.indexBy(d -> d#id, d -> baseStatsFrom(d#resource), players),
                                  Query.indexBy(d -> enemyUid(d#id), d -> baseStatsFrom(d#resource), enemies)),
            // S-A0b: weaponView も装備武器由来の read-model ＝ 毎フレーム再 mirror。
            weaponView = Map.union(Query.indexBy(d -> d#id, d -> PlayerScene.equippedWeaponView(d), players),
                                   Query.indexBy(d -> enemyUid(d#id), d -> EnemyScene.equippedWeaponView(d), enemies)),
            // S-A0c: ringBonus も装備指輪由来の read-model ＝ 毎フレーム再 mirror。
            ringBonus = Map.union(Query.indexBy(d -> d#id, d -> PlayerScene.equippedRingBonus(d), players),
                                  Query.indexBy(d -> enemyUid(d#id), d -> EnemyScene.equippedRingBonus(d), enemies)),
            attackTarget = Map.filterWithKey((uid, _) -> Set.memberOf(uid, validUids), w#attackTarget),
            // F8-slice2: scalar bool は command 由来を保持（scene mirror 元なし・TopBar が毎フレーム dual-write）。
            enemyTurnBusy      = w#enemyTurnBusy,
            phaseObservedEnemy = w#phaseObservedEnemy
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
    /// 現状の唯一の System は `tickStatusEffects`（純粋）。これは:
    ///   - pos を触らない（syncTreeFromWorld に無影響）、
    ///   - statuses は read-model で次フレーム `refreshMirror` が scene から上書きする、
    ///   - live な `StatusQuery` reader がゲームに無い、
    /// ため **挙動不変な scaffold**＝「System が段に乗る型/データ流」を実証するだけ（status の正規 tick は
    /// ターン境界に置くので F2 でここへ移す）。identity 段にしないのは、実 System を1つ通して seam を生かすため。
    pub def stepWorld(world: World): World =
        world |> tickStatusEffects

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
        case SetAlerted(EntityRef, Bool)    // F7-spike: 敵検知フラグ write（Player は no-op）
        case SetDying(EntityRef)            // 軸1 仕上げ: 敵を死亡演出中に（Player は no-op・clear は removal+prune）
        case SetBottleUsed(EntityRef, Bool) // F7-slice2: 敵瓶使用フラグ write（Player は no-op）
        case SetPrevPos(EntityRef, {x = Int32, y = Int32})  // F7-slice3: 敵直前位置 write（Player は no-op）
        case SetFollowUpUsed(EntityRef, Bool)  // F7-slice4: followUp 使用済み write（両 faction）
        case SetWaited(EntityRef, Bool)        // F7-slice5: 味方行動済み write（Enemy は no-op）
        case SetAttackTarget(EntityRef, Int32) // F8-slice1: 攻撃対象 id をセット（攻撃開始）
        case ClearAttackTarget(EntityRef)      // F8-slice1: 攻撃対象をクリア（攻撃終了）
        case SetProgress(EntityRef, Int32, Int32) // World 拡張: 味方の (level, exp) write（撃破/レベルアップ/復元で）
        case SetEnemyTurnBusy(Bool)            // F8-slice2: 敵ターン intro hold 中 bool write（TopBar dual-write）
        case SetPhaseObservedEnemy(Bool)       // F8-slice2: バーが敵ターン観測済み bool write（TopBar dual-write）
    }

    /// System が出力する sim-event（F-clock の最小骨組み・F3b 導入）。
    /// System は World→World を即時に解き、「何が起きたか」を SimEvent として返す。
    /// VIEW はこれを再生（Tween/anim）する＝「即時 System ＋ event 再生」型の seam。
    /// 現状は move 1 系統のみ。同 dispatch 内で emit→replay（timing 不変）＝pipeline 段移設（F3c）は別段。
    pub enum SimEvent {
        case Moved(EntityRef, {x = Int32, y = Int32})  // entity が target へ 1 歩進んだ（from は view が現位置で持つ）
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
            case Cmd.SetAlerted(ref, a) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(_)  => world   // F7-spike: 味方に alerted は無い＝no-op
                    case EntityRef.Enemy(id)  => World.World({enemyAlerted = Map.insert(enemyUid(id), a, w#enemyAlerted) | w})
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

    /// F7-spike: 敵の alerted を World から読む（reader flip の供給元・hpOf 同型）。Player は常に None。
    pub def alertedOf(ref: EntityRef, world: World): Option[Bool] =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(_)  => None
            case EntityRef.Enemy(id)  => Map.get(enemyUid(id), w#enemyAlerted)
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
    pub def baseStatsOf(ref: EntityRef, world: World): Option[BaseStats] =
        let World.World(w) = world; Map.get(toUid(ref), w#baseStats)

    /// S-A0b: 装備武器の戦闘投影を World から読む（unified-id・両 faction）。
    /// 外側 Option（entity 未登録）と内側 Option（武器なし）を flatten し、武器なし＝None で返す
    /// （combatView#weapon の型と一致）。B1 で combatView がここを読む。
    pub def weaponViewOf(ref: EntityRef, world: World): Option[Combat.WeaponView] =
        let World.World(w) = world; Map.get(toUid(ref), w#weaponView) |> Option.flatten

    /// S-A0c: 装備指輪ボーナスを World から読む（unified-id・両 faction）。未登録は None。
    /// B1 で combatView がここを読み、base + ring + status を合成する。
    pub def ringBonusOf(ref: EntityRef, world: World): Option[Ring.Bonuses] =
        let World.World(w) = world; Map.get(toUid(ref), w#ringBonus)

    /// B1: `combatView` を **World だけから再構築**する（faction 非依存）。base 戦闘値 + 指輪 + status mods
    /// + hp + 装備武器投影を合成し、`PlayerScene.combatView` / `EnemyScene.combatView` と同一の `Combat.CombatView`
    /// を返す。式は両 scene の combatView と一致（status/ring 補正の載せ方を含む）。baseStats/hp/ringBonus が
    /// 揃わない（未登録）entity は None。これで scene-authority な combatView の reader を World へ flip できる。
    pub def combatViewOf(ref: EntityRef, world: World): Option[Combat.CombatView] =
        match (baseStatsOf(ref, world), hpOf(ref, world), ringBonusOf(ref, world)) {
            case (Some(bs), Some(hp), Some(rb)) =>
                let m = StatusSystem.combatMods(statusEffectsOf(ref, world));
                Some({attack = bs#attack + m#atkBonus + rb#attack,
                      magicAttack = bs#magicAttack,
                      defense = bs#defense + rb#defense + m#defDelta,
                      magicDefense = bs#magicDefense,
                      skill = bs#skill + rb#skill,
                      speed = bs#speed + m#spdDelta + rb#speed,
                      luck = bs#luck + rb#luck,
                      hp = hp, maxHp = bs#maxHp, hitMod = m#hitMod,
                      weapon = weaponViewOf(ref, world)})
            case _ => None
        }

    /// B1 安全網: `combatViewOf`（World 再構築）と scene の `combatView` が食い違う entity を列挙する。
    /// parallel-run DIFF（hp 等と同型）。read-model ゆえ frame-end では常に一致するはずで、
    /// 食い違いは「combatView と combatViewOf の合成式 drift」を意味する（移行中の回帰検出）。
    /// record/enum は Eq 非自動ゆえ全数値 + 武器投影を tuple 射影して比較する。
    pub def combatViewMismatches(world: World, scene: Scene[NodeTag]): List[EntityRef] =
        let wvProj = wv -> (wv#attack, wv#hit, wv#crit, wv#isPhysical, wv#proficient, wv#effectValue);
        let cvProj = cv -> (cv#attack, cv#magicAttack, cv#defense, cv#magicDefense, cv#skill,
                            cv#speed, cv#luck, cv#hp, cv#maxHp, cv#hitMod,
                            Option.map(wvProj, cv#weapon));
        let pms = PlayerScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(cvProj, combatViewOf(EntityRef.Player(d#id), world))
                != Some(cvProj(PlayerScene.combatView(d))))
                Some(EntityRef.Player(d#id)) else None);
        let ems = EnemyScene.getAll(scene) |> List.filterMap(d ->
            if (Option.map(cvProj, combatViewOf(EntityRef.Enemy(d#id), world))
                != Some(cvProj(EnemyScene.combatView(d))))
                Some(EntityRef.Enemy(d#id)) else None);
        List.append(pms, ems)

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

    /// F7-slice5 検証器: 味方 waited の World/scene 不一致。
    pub def waitedMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[Bool], Bool)] =
        PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let ww = waitedOf(EntityRef.Player(d#id), world);
            if (ww != Some(d#waited)) Some((EntityRef.Player(d#id), ww, d#waited)) else None
        })

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

    /// F7-slice2 検証器: 敵 bottleUsed の World/scene 不一致（`alertedMismatches` 同型）。
    pub def bottleUsedMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[Bool], Bool)] =
        EnemyScene.getAll(scene) |> List.filterMap(d -> {
            let wb = bottleUsedOf(EntityRef.Enemy(d#id), world);
            if (wb != Some(d#bottleUsed)) Some((EntityRef.Enemy(d#id), wb, d#bottleUsed)) else None
        })

    /// F7-slice4 検証器: followUpUsed の World/scene 不一致（両 faction）。
    pub def followUpUsedMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[Bool], Bool)] =
        let ps = PlayerScene.getAll(scene) |> List.filterMap(d -> {
            let wf = followUpUsedOf(EntityRef.Player(d#id), world);
            if (wf != Some(d#followUpUsed)) Some((EntityRef.Player(d#id), wf, d#followUpUsed)) else None
        });
        let es = EnemyScene.getAll(scene) |> List.filterMap(d -> {
            let wf = followUpUsedOf(EntityRef.Enemy(d#id), world);
            if (wf != Some(d#followUpUsed)) Some((EntityRef.Enemy(d#id), wf, d#followUpUsed)) else None
        });
        List.append(ps, es)

    /// F7-slice3 検証器: 敵 prevPos の World/scene 不一致。record は ToString 不可ゆえ (x,y) タプルに畳む。
    pub def prevPosMismatches(world: World, scene: Scene[NodeTag]): List[(EntityRef, Option[(Int32, Int32)], Option[(Int32, Int32)])] =
        let toT = op -> Option.map(p -> (p#x, p#y), op);
        EnemyScene.getAll(scene) |> List.filterMap(d -> {
            let wp = toT(prevPosOf(EntityRef.Enemy(d#id), world));
            let sp = toT(d#prevPos);
            if (wp != sp) Some((EntityRef.Enemy(d#id), wp, sp)) else None
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
            case EffectPlan.PlanItem.MaxHpUpAt(id, ally, _) => emitHpAt(id, ally, scene)
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

    /// World（位置の read-model mirror）から Board を組み立てる S4 の経路（World クエリ＝ecs/ 層）。
    /// 地形（map）は静的なので scene から（`BoardSnapshot.mapSnapshotOf` を借用）、駒（pieces）は World から。
    /// flip 時は call-point 単位で `BoardSnapshot.fromScene(scene)` をこれに差し替える。
    pub def toBoard(world: World, scene: Scene[NodeTag]): Board =
        {
            map    = BoardSnapshot.mapSnapshotOf(scene),
            pieces = boardPieces(world)
        }

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

    /// S5（§A 完成へ・World→scene 一方向 sync）: 各ユニットの scene `gridPos` を **World の位置で上書き**する。
    /// `syncStatusesToScene` と同型（`mapPlayer`/`mapEnemy` を再利用・scene 不在 id は no-op）。
    /// S5a（dual-write 継続中）は World==scene ゆえ **no-op＝挙動不変**で seam を確立。S5b で move 関数の
    /// scene gridPos 直書きを撤去し、gridPos を**この sync 由来（World の派生）**に一本化する。
    pub def syncTreeFromWorld(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        // A': 単一 `pos` store を team タグで faction 分けし、original id で mapPlayer/mapEnemy。
        let World.World(w) = world;
        Map.foldLeftWithKey((sc, uid, pos) ->
            match uidToRef(uid) {
                case EntityRef.Player(pid) => PlayerScene.mapPlayer(pid, d -> {gridPos = pos | d}, sc)
                case EntityRef.Enemy(eid)  => EnemyScene.mapEnemy(eid, d -> {gridPos = pos | d}, sc)
            }, scene, w#pos)
}
