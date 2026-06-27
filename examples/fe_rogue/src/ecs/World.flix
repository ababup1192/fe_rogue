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

pub enum World {
    case World({ tick = Int32,
                 playerIds = Set[EntityId], enemyIds  = Set[EntityId],
                 playerStatusEffects = Map[EntityId, StatusSystem.StatusEffects],
                 enemyStatusEffects  = Map[EntityId, StatusSystem.StatusEffects],
                 // S2: hp の read-model mirror（権威は scene のまま。query/セーブ/決定論テスト用）。
                 playerHp = Map[EntityId, Int32], enemyHp = Map[EntityId, Int32],
                 // S3: gridPos の read-model mirror。型は Vec2i の structural record（engine_core.Vec2i の演算 API 対象）。
                 // 権威は scene のまま。S4 で Board を fromWorld 化する時の World 側位置ソース候補（mirror）。
                 playerPos = Map[EntityId, {x = Int32, y = Int32}],
                 enemyPos  = Map[EntityId, {x = Int32, y = Int32}],
                 // S4: 盤面除外（集合・階段退場）中の味方 id。Board.pieces は hidden 味方を除くので fromWorld に必要。
                 playerHidden = Set[EntityId] })
}

mod World {

    pub def empty(): World =
        World.World({tick = 0, playerIds = Set.empty(), enemyIds = Set.empty(),
                     playerStatusEffects = Map.empty(), enemyStatusEffects = Map.empty(),
                     playerHp = Map.empty(), enemyHp = Map.empty(),
                     playerPos = Map.empty(), enemyPos = Map.empty(),
                     playerHidden = Set.empty()})

    /// scene→World の一方向 sync（純粋・読み取りのみ）。tick を 1 進め、id 集合と statuses を scene から写す。
    /// PlayerScene.getAll / EnemyScene.getAll（既存・純粋）を再利用（新規走査は書かない）。
    pub def syncFromScene(scene: Scene[NodeTag], world: World): World =
        let World.World(w) = world;
        let players = PlayerScene.getAll(scene);
        let enemies = EnemyScene.getAll(scene);
        World.World({
            tick           = w#tick + 1,
            playerIds      = Query.tagOf(d -> d#id, players),
            enemyIds       = Query.tagOf(d -> d#id, enemies),
            playerStatusEffects = Query.indexBy(d -> d#id, d -> d#statuses, players),
            enemyStatusEffects  = Query.indexBy(d -> d#id, d -> d#statuses, enemies),
            playerHp       = Query.indexBy(d -> d#id, d -> d#hp, players),
            enemyHp        = Query.indexBy(d -> d#id, d -> d#hp, enemies),
            playerPos      = Query.indexBy(d -> d#id, d -> d#gridPos, players),
            enemyPos       = Query.indexBy(d -> d#id, d -> d#gridPos, enemies),
            playerHidden   = Query.tagOf(d -> d#id, List.filter(d -> d#hidden, players))
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
        World.World({
            tick           = w#tick + 1,
            playerIds      = pIds,
            enemyIds       = eIds,
            playerStatusEffects = Query.indexBy(d -> d#id, d -> d#statuses, players),
            enemyStatusEffects  = Query.indexBy(d -> d#id, d -> d#statuses, enemies),
            playerHp       = Query.indexBy(d -> d#id, d -> d#hp, players),
            enemyHp        = Query.indexBy(d -> d#id, d -> d#hp, enemies),
            // 位置は command 由来を保持＋scene に居ない id を prune（gridPos からの再構築はしない）。
            playerPos      = Map.filterWithKey((id, _) -> Set.memberOf(id, pIds), w#playerPos),
            enemyPos       = Map.filterWithKey((id, _) -> Set.memberOf(id, eIds), w#enemyPos),
            playerHidden   = Query.tagOf(d -> d#id, List.filter(d -> d#hidden, players))
        })

    /// statuses を 1 ターン進める System（StatusSystem.tick を再利用）。S1b でターン開始フックに繋ぐ。
    pub def tickStatusEffects(world: World): World =
        let World.World(w) = world;
        World.World({
            playerStatusEffects = Map.map(StatusSystem.tick, w#playerStatusEffects),
            enemyStatusEffects  = Map.map(StatusSystem.tick, w#enemyStatusEffects)
            | w
        })

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
    pub enum EntityRef {
        case Player(EntityId)
        case Enemy(EntityId)
    }

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

    /// statusEffects を引く（既定 Nil＝mid-game spawn は seed 不要）。Query handler から呼ぶ。
    pub def playerStatusEffectsOf(id: EntityId, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(id, Nil, w#playerStatusEffects)
    pub def enemyStatusEffectsOf(id: EntityId, world: World): StatusSystem.StatusEffects =
        let World.World(w) = world; Map.getWithDefault(id, Nil, w#enemyStatusEffects)

    /// faction 非依存の統一アクセサ（前方互換 seam）。`EntityRef` で引くので、内部ストアが split→single へ
    /// 変わっても呼び出し側は不変。Option A 移行時はこの実装だけ差し替える。
    pub def statusEffectsOf(ref: EntityRef, world: World): StatusSystem.StatusEffects =
        match ref {
            case EntityRef.Player(id) => playerStatusEffectsOf(id, world)
            case EntityRef.Enemy(id)  => enemyStatusEffectsOf(id, world)
        }

    /// EntityRef の statusEffects に純粋変換 f を適用する。**内部ストアが faction を知る唯一の点**
    /// （split→single への Option A 移行はここだけ直せばよい）。Seed は `f = _ -> xs`（全置換）。
    def overEntity(ref: EntityRef, f: StatusSystem.StatusEffects -> StatusSystem.StatusEffects, world: World): World =
        let World.World(w) = world;
        match ref {
            case EntityRef.Player(id) =>
                let cur = Map.getWithDefault(id, Nil, w#playerStatusEffects);
                World.World({playerStatusEffects = Map.insert(id, f(cur), w#playerStatusEffects) | w})
            case EntityRef.Enemy(id) =>
                let cur = Map.getWithDefault(id, Nil, w#enemyStatusEffects);
                World.World({enemyStatusEffects = Map.insert(id, f(cur), w#enemyStatusEffects) | w})
        }

    /// 1 命令を World へ適用する純粋 applier（Command handler の本体）。
    pub def applyCmd(cmd: Cmd, world: World): World =
        match cmd {
            case Cmd.Add(ref, s)           => overEntity(ref, xs -> StatusSystem.add(s, xs), world)
            case Cmd.ClearImmobilized(ref) => overEntity(ref, StatusSystem.clearImmobilized, world)
            case Cmd.Seed(ref, xs)         => overEntity(ref, _ -> xs, world)
            case Cmd.TickPlayers(ids) =>
                let World.World(w) = world;
                let next = Query.updateTagged(List.toSet(ids), StatusSystem.tick, w#playerStatusEffects);
                World.World({playerStatusEffects = next | w})
            case Cmd.TickEnemies =>
                let World.World(w) = world;
                World.World({enemyStatusEffects = Map.map(StatusSystem.tick, w#enemyStatusEffects) | w})
            case Cmd.Move(ref, pos) =>
                let World.World(w) = world;
                match ref {
                    case EntityRef.Player(id) => World.World({playerPos = Map.insert(id, pos, w#playerPos) | w})
                    case EntityRef.Enemy(id)  => World.World({enemyPos = Map.insert(id, pos, w#enemyPos) | w})
                }
        }

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
        let World.World(w) = world;
        let playerPieces = Map.toList(w#playerPos)
            |> List.filter(pair -> { let (id, _) = pair; not Set.memberOf(id, w#playerHidden) })
            |> List.map(pair -> { let (id, pos) = pair; (Piece.Player(id), pos) });
        let enemyPieces = Map.toList(w#enemyPos)
            |> List.map(pair -> { let (id, pos) = pair; (Piece.Enemy(id), pos) });
        List.append(playerPieces, enemyPieces)

    /// World→scene の逆向き write-back（S1b）。World が持つ statuses を scene の Data#statuses へ書き戻す。
    /// 既存の純粋 writer `PlayerScene.mapPlayer` / `EnemyScene.mapEnemy` を再利用（走査・書込を再実装しない）。
    /// scene に居ない id は mapPlayer/mapEnemy が no-op で読み飛ばす。combatView/isImmobilized 等の read 側は
    /// 依然 scene の Data#statuses を読むので、この sync が World を唯一の真とする seam になる（flip は S1b 後段）。
    pub def syncStatusesToScene(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        let World.World(w) = world;
        let withPlayers = Map.foldLeftWithKey((sc, id, statuses) ->
            PlayerScene.mapPlayer(id, d -> {statuses = statuses | d}, sc), scene, w#playerStatusEffects);
        Map.foldLeftWithKey((sc, id, statuses) ->
            EnemyScene.mapEnemy(id, d -> {statuses = statuses | d}, sc), withPlayers, w#enemyStatusEffects)

    /// S5（§A 完成へ・World→scene 一方向 sync）: 各ユニットの scene `gridPos` を **World の位置で上書き**する。
    /// `syncStatusesToScene` と同型（`mapPlayer`/`mapEnemy` を再利用・scene 不在 id は no-op）。
    /// S5a（dual-write 継続中）は World==scene ゆえ **no-op＝挙動不変**で seam を確立。S5b で move 関数の
    /// scene gridPos 直書きを撤去し、gridPos を**この sync 由来（World の派生）**に一本化する。
    pub def syncTreeFromWorld(world: World, scene: Scene[NodeTag]): Scene[NodeTag] =
        let World.World(w) = world;
        let withPlayers = Map.foldLeftWithKey((sc, id, pos) ->
            PlayerScene.mapPlayer(id, d -> {gridPos = pos | d}, sc), scene, w#playerPos);
        Map.foldLeftWithKey((sc, id, pos) ->
            EnemyScene.mapEnemy(id, d -> {gridPos = pos | d}, sc), withPlayers, w#enemyPos)
}
