// World — ハイブリッド ECS 化の足場（S0）＋ statuses store（S1a）
//
// シミュレーション状態を寄せていく不変 World。S0 で id 集合＋tick を scene→World mirror した上に、
// S1a で最初の本物の component store「statuses（時限効果）」を足す。player/enemy は id 空間が別なので
// store も faction 別に持つ（衝突回避＝S0 の playerIds/enemyIds と同じ方針）。
//
// S1a は **非破壊**: statuses も scene から mirror するだけで、既存の読み書き（combatView/tick）は
// scene の Data#statuses のまま。World は描画にもロジックにも影響しない（gameLoop の末尾再帰に thread）。
// S1b で読み書きを 1 箇所ずつ World 由来に切替（parallel-run で一致検証してから）。
// tickStatuses は S1b で使う System（StatusSystem.tick を再利用）。S1a では定義＋テストのみ。
// 道標: ルート ECS_WORKFLOW.md（§D S1）。

pub enum World {
    case World({ tick = Int32,
                 playerIds = Set[EntityId], enemyIds  = Set[EntityId],
                 playerStatuses = Map[EntityId, List[StatusSystem.Status]],
                 enemyStatuses  = Map[EntityId, List[StatusSystem.Status]],
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
                     playerStatuses = Map.empty(), enemyStatuses = Map.empty(),
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
            playerIds      = players |> List.map(d -> d#id) |> List.toSet,
            enemyIds       = enemies |> List.map(d -> d#id) |> List.toSet,
            playerStatuses = players |> List.foldLeft((m, d) -> Map.insert(d#id, d#statuses, m), Map.empty()),
            enemyStatuses  = enemies |> List.foldLeft((m, d) -> Map.insert(d#id, d#statuses, m), Map.empty()),
            playerHp       = players |> List.foldLeft((m, d) -> Map.insert(d#id, d#hp, m), Map.empty()),
            enemyHp        = enemies |> List.foldLeft((m, d) -> Map.insert(d#id, d#hp, m), Map.empty()),
            playerPos      = players |> List.foldLeft((m, d) -> Map.insert(d#id, d#gridPos, m), Map.empty()),
            enemyPos       = enemies |> List.foldLeft((m, d) -> Map.insert(d#id, d#gridPos, m), Map.empty()),
            playerHidden   = players |> List.filter(d -> d#hidden) |> List.map(d -> d#id) |> List.toSet
        })

    /// statuses を 1 ターン進める System（StatusSystem.tick を再利用）。S1b でターン開始フックに繋ぐ。
    pub def tickStatuses(world: World): World =
        let World.World(w) = world;
        World.World({
            playerStatuses = Map.map(StatusSystem.tick, w#playerStatuses),
            enemyStatuses  = Map.map(StatusSystem.tick, w#enemyStatuses)
            | w
        })

    /// World（位置の read-model mirror）から Board を組み立てる S4 の経路（World クエリ＝ecs/ 層）。
    /// 地形（map）は静的なので scene から（`BoardSnapshot.mapSnapshotOf` を借用）、駒（pieces）は World から。
    /// flip 時は call-point 単位で `BoardSnapshot.fromScene(scene)` をこれに差し替える。
    pub def toBoard(world: World, scene: Scene[NodeTag]): Board =
        {
            map    = BoardSnapshot.mapSnapshotOf(scene),
            pieces = boardPieces(world)
        }

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
            PlayerScene.mapPlayer(id, d -> {statuses = statuses | d}, sc), scene, w#playerStatuses);
        Map.foldLeftWithKey((sc, id, statuses) ->
            EnemyScene.mapEnemy(id, d -> {statuses = statuses | d}, sc), withPlayers, w#enemyStatuses)
}
