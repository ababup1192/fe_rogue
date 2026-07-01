// World（S0 足場）のテスト — scene→World 一方向 sync が id 集合と tick を正しく写すか。
// 最小 scene は TestCombatScene.battleScene と同じ「World ノード＋直接 addChildAt」パターン。

mod TestWorld {

    def playerData(id: Int32): PlayerScene.Data = playerDataS(id, Nil)

    def playerDataS(id: Int32, statuses: List[StatusSystem.Status]): PlayerScene.Data = {
        id                = id,
        statuses          = statuses,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = None,
        resource          = TestUnitFixtures.testResource(4, 10),
        weapons           = TestUnitFixtures.testWeapon() :: Nil,
        staves            = Nil,
        consumables       = Nil,
        selectedItem      = None,
        moveStepsTaken    = 0,
        facing            = Staff.Direction.Down,
        hidden            = false,
        usedStairs        = false,
        level             = 1,
        exp               = 0,
        pendingLevelUp    = None,
        rings             = Nil,
        ringEquipped      = false,
        followUpUsed      = false
    }

    def enemyData(id: Int32): EnemyScene.Data = {
        id             = id,
        resourceId     = "test_enemy",
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = Some(TestUnitFixtures.testWeapon()),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// World 配下に player 2 体（id 0,1）＋ enemy 1 体（id 5）を直接挿した最小 scene。
    def sampleScene(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let mk = () -> Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(0))))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(1),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(1))))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(5),
                EngineNode.Marker2DWithState(mk(), NodeTag.Enemy(enemyData(5))))

    /// syncFromScene が player/enemy の id 集合を写し、tick を 1 進める。
    @Test
    def testSyncFromScene(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(
            expected = (2, 1, 1),
            (Set.size(w#playerIds), Set.size(w#enemyIds), w#tick))

    /// id の実値も検証（player/enemy の取り違えを直接捕捉）。
    @Test
    def testSyncFromSceneIds(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(expected = (Set#{0, 1}, Set#{5}), (w#playerIds, w#enemyIds))

    /// 空 scene なら id 集合は空、tick は進む。
    @Test
    def testSyncFromEmptyScene(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(Scene.empty(), World.empty());
        Assert.assertEq(
            expected = (0, 0, 1),
            (Set.size(w#playerIds), Set.size(w#enemyIds), w#tick))

    // ── S1a: statuses store ──

    /// player 0 に immobilize(残3) を持たせた scene を World に mirror する。
    def sceneWithStatus(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                    NodeTag.Player(playerDataS(0, StatusSystem.immobilizeFor(3) :: Nil))))

    def firstRemaining(m: Map[EntityId, List[StatusSystem.Status]], id: EntityId): Int32 =
        Map.get(id, m) |> Option.flatMap(List.head) |> Option.map(s -> s#remaining) |> Option.getWithDefault(-1)

    /// syncFromScene が statuses を player store に写す（残3 がそのまま）。
    @Test
    def testSyncMirrorsStatuses(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sceneWithStatus(), World.empty());
        Assert.assertEq(expected = 3, firstRemaining(w#statusEffects, 0))

    /// tickStatusEffects（StatusSystem.tick 再利用）で残ターンが 1 減る（残3→2）。
    @Test
    def testTickStatuses(): Unit \ Assert =
        let synced = World.syncFromScene(sceneWithStatus(), World.empty());
        let World.World(w) = World.tickStatusEffects(synced);
        Assert.assertEq(expected = 2, firstRemaining(w#statusEffects, 0))

    // ── S1b: World→scene write-back（逆向き矢印）と parallel-run 同値実証 ──

    /// scene の player 0 の Data#statuses を読む（write-back の検証用）。
    def sceneFirstRemaining(scene: Scene[NodeTag], id: Int32): Int32 =
        PlayerScene.getAll(scene)
            |> List.find(d -> d#id == id)
            |> Option.flatMap(d -> List.head(d#statuses))
            |> Option.map(s -> s#remaining)
            |> Option.getWithDefault(-1)

    /// syncStatusesToScene が World の statuses を scene の Data#statuses へ書き戻す（残3 が往復で保たれる）。
    @Test
    def testSyncStatusesToSceneRoundTrip(): Unit \ Assert =
        let scene  = sceneWithStatus();
        let synced = World.syncFromScene(scene, World.empty());
        let back   = World.syncStatusesToScene(synced, scene);
        Assert.assertEq(expected = 3, sceneFirstRemaining(back, 0))

    /// parallel-run 同値実証: 「World 経路（tickStatusEffects→write-back で scene を更新）」と
    /// 「現行 scene 経路（StatusSystem.tick を直接 Data#statuses に畳む）」が同じ残ターンを与える。
    /// これが一致する限り、turn 開始 tick を World へ flip しても挙動は不変（S1b 後段の前提）。
    @Test
    def testTickParallelRunMatchesScenePath(): Unit \ Assert =
        let scene = sceneWithStatus();
        // World 経路: sync → tickStatusEffects → scene へ write-back → scene から読む。
        let worldPath =
            World.syncStatusesToScene(World.tickStatusEffects(World.syncFromScene(scene, World.empty())), scene)
                |> (s -> sceneFirstRemaining(s, 0));
        // scene 経路: 既存と同じく Data#statuses に StatusSystem.tick を直接畳む。
        let scenePath =
            PlayerScene.mapPlayer(0, d -> {statuses = StatusSystem.tick(d#statuses) | d}, scene)
                |> (s -> sceneFirstRemaining(s, 0));
        Assert.assertEq(expected = scenePath, worldPath)

    // ── S2: hp の read-model mirror ──

    /// syncFromScene が hp を World store へ mirror する（player 0,1／enemy 5 とも scene の hp と一致）。
    /// 権威は scene のまま＝この mirror は query/セーブ用の read-model。
    @Test
    def testSyncMirrorsHp(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        // sampleScene の fixture は player/enemy とも hp=10。
        Assert.assertEq(
            expected = (Some(10), Some(10), Some(10)),
            (Map.get(0, w#hp), Map.get(1, w#hp), Map.get(5 + World.enemyUidBase(), w#hp)))

    /// A'（faction タグ）: `team` enum component が unified-id ごとに Player/Enemy を返す。
    /// faction は id 演算でなくこの enum タグで読む。sampleScene = player 0,1 / enemy 5。
    @Test
    def testTeamTagComponent(): Unit \ Assert =
        let w = World.syncFromScene(sampleScene(), World.empty());
        Assert.assertEq(
            expected = (Some(Faction.Player), Some(Faction.Player),
                        Some(Faction.Enemy), true, true, None),
            (World.teamOf(0, w), World.teamOf(1, w),
             World.teamOf(5 + World.enemyUidBase(), w),
             World.isPlayerUid(0, w), World.isEnemyUid(5 + World.enemyUidBase(), w),
             World.teamOf(999, w)))

    /// hp mirror が scene の各 Data#hp と完全一致する（parallel-run 同値：World hp == scene hp）。
    @Test
    def testHpMirrorEqualsScene(): Unit \ Assert =
        let scene = sampleScene();
        let World.World(w) = World.syncFromScene(scene, World.empty());
        let scenePlayerHp = PlayerScene.getAll(scene)
            |> List.foldLeft((m, d) -> Map.insert(d#id, d#hp, m), Map.empty());
        // A': hp は単一 store。player 部分（uid < base）を取り出して比較。
        Assert.assertEq(expected = scenePlayerHp,
            Map.filterWithKey((uid, _) -> uid < World.enemyUidBase(), w#hp))

    // ── S3: gridPos の read-model mirror ──

    /// syncFromScene が gridPos を World store へ mirror する（fixture: player {2,2}／enemy {3,2}）。
    /// record の == は使えないので x/y スカラに展開して比較。
    @Test
    def testSyncMirrorsPos(): Unit \ Assert =
        let World.World(w) = World.syncFromScene(sampleScene(), World.empty());
        let xy = (id, m) -> Map.get(id, m) |> Option.map(v -> (v#x, v#y));
        Assert.assertEq(
            expected = (Some((2, 2)), Some((2, 2)), Some((3, 2))),
            (xy(0, w#pos), xy(1, w#pos), xy(5 + World.enemyUidBase(), w#pos)))

    /// pos mirror が scene の各 Data#gridPos と一致（parallel-run 同値：World pos == scene gridPos・Vec2i.eq）。
    @Test
    def testPosMirrorEqualsScene(): Unit \ Assert =
        let scene = sampleScene();
        let World.World(w) = World.syncFromScene(scene, World.empty());
        let allMatch = PlayerScene.getAll(scene)
            |> List.forAll(d ->
                Map.get(d#id, w#pos)
                    |> Option.map(v -> Vec2i.eq(v, d#gridPos))
                    |> Option.getWithDefault(false));
        Assert.assertEq(expected = true, allMatch)

    // ── S4: BoardSnapshot.piecesFromWorld（位置 read-model から Board.pieces を組む）──

    /// World 配下に player 0（可視・{2,2}）／player 3（hidden）／enemy 5（{3,2}）を挿した scene。
    def sceneWithHidden(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let mk = () -> Marker2D.make(Vec2.zero());
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(playerData(0))))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(3),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player({hidden = true | playerData(3)})))
            |> Scene.addChildAt(MapScene.worldPath(), EnemyScene.enemyName(5),
                EngineNode.Marker2DWithState(mk(), NodeTag.Enemy(enemyData(5))))

    /// pieces を faction 別に id→(x,y) の Map へ畳む（record の == 不可のため tuple 化、順序非依存比較）。
    def playerPosMapOf(pieces: List[(Piece, {x = Int32, y = Int32})]): Map[Int32, (Int32, Int32)] =
        List.foldLeft((m, pair) -> { let (pc, p) = pair; match pc {
            case Piece.Player(id) => Map.insert(id, (p#x, p#y), m)
            case _                => m
        }}, Map.empty(), pieces)

    def enemyPosMapOf(pieces: List[(Piece, {x = Int32, y = Int32})]): Map[Int32, (Int32, Int32)] =
        List.foldLeft((m, pair) -> { let (pc, p) = pair; match pc {
            case Piece.Enemy(id) => Map.insert(id, (p#x, p#y), m)
            case _               => m
        }}, Map.empty(), pieces)

    /// piecesFromWorld が World 位置から正しい駒を組む：hidden 味方 3 を除外、player 0／enemy 5 が残る。
    /// fromScene の hidden フィルタ・(Piece,pos) 生成と同義であることを id→pos 同値で検証（順序非依存）。
    @Test
    def testPiecesFromWorldFiltersHidden(): Unit \ Assert =
        let world  = World.syncFromScene(sceneWithHidden(), World.empty());
        let pieces = World.boardPieces(world);
        Assert.assertEq(
            expected = (Map#{0 => (2, 2)}, Map#{5 => (3, 2)}),
            (playerPosMapOf(pieces), enemyPosMapOf(pieces)))

    // ── board-lock: boardMatchesScene（Phase C 盤面契約の pin）──

    // `toBoard`/`BoardSnapshot.fromScene` は `mapSnapshotOf` 経由で TileMapLayer を要求するため、
    // board-lock テストの scene には Map ノードが要る（boardPieces だけの上の S4 テストと違う点）。
    // 壁なし 13×13 床マップ（駒位置 {2,2}/{3,2}/{9,9} を全て内包）。boardKey は pieces のみ使うので
    // map は両 source で同一＝差分に効かない。TestMoveRangeScene の floorMap パターンを踏襲。
    def floorMapLayer(): TileMapLayer =
        let atlas: TileSetAtlasSource = {
            textureName = "test", texWidth = 0.0, texHeight = 0.0,
            tileSize = 16.0, marginX = 0.0, marginY = 0.0, spacingX = 0.0, spacingY = 0.0
        };
        TileMapLayer.make({
            tileSet        = TileSet.make(atlas),
            tiles          = Nil,
            collisionCells = Nil,
            gridSize       = ({x = 13, y = 13}: {x = Int32, y = Int32})
        })

    def floorMapData(): MapScene.Data = {
        anchorOffset = {x = 0, y = 0},
        spawnGrid    = {x = 5, y = 5},
        placements   = RoomLayout.singleRoom(13, 13),
        roomCount    = 1,
        plan         = ({modulePaths = Nil, sideConnections = Nil, roomCount = 1}: DungeonGenerator.Plan)
    }

    /// 既存 scene に "DungeonLevel0" の Map ノードを足す（mapSnapshotOf の bug! を回避）。
    def addMap(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.addNode("DungeonLevel0",
            EngineNode.TileMapLayerWithState(floorMapLayer(), NodeTag.Map(floorMapData())), scene)

    /// World 配下に player 0 のみ（可視・{2,2}）を挿した最小 scene。one-sided guard 用に
    /// 「scene に居る可視 entity が World pos に居ない」状態を作るための片肺 World を syncFromScene する元。
    def sceneOnlyPlayer0(): Scene[NodeTag] =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(), EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()), NodeTag.Player(playerData(0))))

    /// (1) positive: syncFromScene 直後は World 由来盤面 == scene 由来盤面。hidden 味方 3 は両側で除外され、
    /// boardMatchesScene true かつ boardKey(toBoard) == boardKey(fromScene)（順序非依存・明示等価）。
    @Test
    def testToBoardEqualsFromScene(): Unit \ Assert =
        let scene = addMap(sceneWithHidden());
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(
            expected = (true, true),
            (World.boardMatchesScene(world, scene),
             World.boardKey(World.toBoard(world, scene)) == World.boardKey(BoardSnapshot.fromScene(scene))))

    /// (2) negative（World 権威）: World のみに Cmd.Move を適用し scene を stale に保つと、その mid-frame で
    /// World 由来盤面が先行し boardMatchesScene false。boardKeyMismatch も Some（2 キーが食い違う）。
    @Test
    def testBoardMismatchWhenWorldMovesAhead(): Unit \ Assert =
        let scene = addMap(sceneWithHidden());
        let world = World.syncFromScene(scene, World.empty());
        let moved = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 9, y = 9}), world);
        Assert.assertEq(
            expected = (false, true),
            (World.boardMatchesScene(moved, scene),
             Option.isEmpty(World.boardKeyMismatch(moved, scene)) == false))

    /// (3) one-sided guard（非 vacuous・id 和上で symmetric）: scene に **可視** entity（player 1・enemy 5）が
    /// 居るのに World pos に居ない（prune/pre-sync を模擬＝player 0 だけ sync した片肺 World）→ false。
    /// hidden ではなく可視を使うのが要点（hidden は両側で除外されガードを誤って pass させるため）。
    @Test
    def testBoardMismatchWhenSceneEntityMissingFromWorld(): Unit \ Assert =
        let scene = addMap(sampleScene());                                  // 可視 player 0,1 + enemy 5
        let world = World.syncFromScene(sceneOnlyPlayer0(), World.empty());  // World pos は player 0 のみ
        Assert.assertEq(expected = false, World.boardMatchesScene(world, scene))

    // ── S1: World.Cmd applier（statuses 権威化の System/command。StatusSystem 再利用）──

    def spdUp(mag: Int32, rem: Int32): StatusSystem.Status =
        {effect = StatusSystem.StatusEffect.SpdUp, magnitude = mag, remaining = rem}

    /// List[Status] 先頭の残ターン（無ければ -1）。
    def firstRem(xs: List[StatusSystem.Status]): Int32 =
        List.head(xs) |> Option.map(s -> s#remaining) |> Option.getWithDefault(-1)

    /// AddPlayer は付与する。同 effect 種別の再付与は増えず、**元の値が据え置かれる**（skip であって置換でない）。
    @Test
    def testApplyAddPlayerDedup(): Unit \ Assert =
        let w1 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 3)), World.empty());
        let w2 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(9, 9)), w1);  // 同 effect 再付与（skip される）
        let xs = World.playerStatusEffectsOf(0, w2);
        let mag = List.head(xs) |> Option.map(s -> s#magnitude) |> Option.getWithDefault(-1);
        Assert.assertEq(expected = (1, 2), (List.length(xs), mag))  // 1 件・残ったのは元の magnitude=2

    /// TickPlayers(ids) はリスト内 id のみ remaining を減らし、リスト外 id（usedStairs 相当）は不変。
    @Test
    def testApplyTickPlayersFilters(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(1), spdUp(2, 5)),
                   World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 5)), World.empty()));
        let w1 = World.applyCmd(World.Cmd.TickPlayers(0 :: Nil), w0);
        Assert.assertEq(
            expected = (4, 5),  // id0 は tick(5→4)、id1 はリスト外で不変(5)
            (firstRem(World.playerStatusEffectsOf(0, w1)), firstRem(World.playerStatusEffectsOf(1, w1))))

    /// TickEnemies は全敵を tick する（残4→3）。
    @Test
    def testApplyTickEnemies(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Enemy(5), spdUp(2, 4)), World.empty());
        let w1 = World.applyCmd(World.Cmd.TickEnemies, w0);
        Assert.assertEq(expected = 3, firstRem(World.enemyStatusEffectsOf(5, w1)))

    /// SeedPlayer は既存を完全置換する（replace 意味論）。immobilize を捨て spdUp だけになる。
    @Test
    def testApplySeedPlayerReplaces(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), StatusSystem.immobilizeFor(3)), World.empty());
        let w1 = World.applyCmd(World.Cmd.Seed(World.EntityRef.Player(0), spdUp(2, 7) :: Nil), w0);
        Assert.assertEq(
            expected = (1, false),  // 1 件・immobilize は消えている
            (List.length(World.playerStatusEffectsOf(0, w1)),
             StatusSystem.isImmobilized(World.playerStatusEffectsOf(0, w1))))

    /// ClearEnemyImmobilized は完全停止だけ解除する（clearImmobilized 再利用）。
    @Test
    def testApplyClearEnemyImmobilized(): Unit \ Assert =
        let w0 = World.applyCmd(World.Cmd.Add(World.EntityRef.Enemy(5), StatusSystem.immobilizeFor(3)), World.empty());
        let w1 = World.applyCmd(World.Cmd.ClearImmobilized(World.EntityRef.Enemy(5)), w0);
        Assert.assertEq(expected = false, StatusSystem.isImmobilized(World.enemyStatusEffectsOf(5, w1)))

    /// faction 隔離: AddPlayer は enemyStatuses を変えない。
    @Test
    def testApplyFactionIsolation(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 3)), World.empty());
        Assert.assertEq(
            expected = (1, 0),
            (List.length(World.playerStatusEffectsOf(0, w)), List.length(World.enemyStatusEffectsOf(0, w))))

    /// アクセサ既定は Nil（未登録 id＝mid-game spawn は seed 不要の根拠）。
    @Test
    def testStatusesOfDefaultNil(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true),
            (List.isEmpty(World.playerStatusEffectsOf(99, World.empty())),
             List.isEmpty(World.enemyStatusEffectsOf(99, World.empty()))))

    /// 統一アクセサ `statusEffectsOf(EntityRef)` が faction を判別する＝**味方 id0 と敵 id0 が衝突しない**
    /// （read seam が live＝Query handler が呼ぶ実体）。
    @Test
    def testStatusEffectsOfRoutesByFaction(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 3)), World.empty());
        // Player(0) には付与済み、同 id でも Enemy(0) は別エンティティで空。
        Assert.assertEq(
            expected = (1, 0),
            (List.length(World.statusEffectsOf(World.EntityRef.Player(0), w)),
             List.length(World.statusEffectsOf(World.EntityRef.Enemy(0), w))))

    /// Command/Query を **effect 経由で** end-to-end 検証（Game.start と同じ handler 配線）。
    /// emit した Cmd が worldRef へ即時適用され、Query で読み戻せる＝live な seam を守るテスト。
    @Test
    def testCommandQueryHandlersRoundTrip(): Unit \ Assert =
        let len = region rc {
            let worldRef = Ref.fresh(rc, World.empty());
            run {
                World.Command.emit(World.Cmd.Add(World.EntityRef.Player(0), spdUp(2, 4)));
                List.length(World.StatusQuery.statusEffects(World.EntityRef.Player(0)))
            } with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(worldRef)), worldRef); k() }
            } with handler World.StatusQuery {
                def statusEffects(ref, k) = k(World.statusEffectsOf(ref, Ref.get(worldRef)))
            }
        };
        Assert.assertEq(expected = 1, len)

    // ── P0a: Cmd.Move の mid-frame currency（位置権威化・gather 是正の前提）──

    /// P0a tripwire: 主人公が **mid-frame に prev→now と動いた**直後、`Cmd.Move` を適用すると
    /// BoardQuery が返す盤面（= `World.toBoard` → `boardPieces`）は **now を反映**し、stale な prev を返さない。
    ///
    /// これは検証器 `[P0a BOARD DIFF]`（Game.flix）が gather で「主人公位置を prev→now に是正する」根拠そのもの。
    /// `Cmd.Move` を `applyCmd`／`playerPos` ストアに配線し損ねる（または `boardPieces` が別ストアを読む）と、
    /// `before==after==prev` になりこのテストが赤くなる＝手動 run 前に回帰を機械検出できる。
    ///
    /// 補足: gather の追従計算 `Board.followStepsToward` 自体は board の主人公セル位置に**非依存**
    /// （味方は全プレイヤーセルを通過可・goal は強制 open・lordNewPos は予約）。よって tripwire は
    /// followStepsToward でなく、P0a が実際に変える「World 盤面の currency」を対象に置く。
    @Test
    def testMoveReflectsNewPosInBoardMidFrame(): Unit \ Assert =
        let now = ({x = 5, y = 5}: {x = Int32, y = Int32});
        // frame-head: scene を mirror（sampleScene の player 0 は {2,2}）。
        let w0 = World.syncFromScene(sampleScene(), World.empty());
        // mid-frame: 主人公(player 0)が now へ移動 → Cmd.Move を World に即時適用。
        let w1 = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), now), w0);
        let posOf0 = w -> Map.get(0, playerPosMapOf(World.boardPieces(w)));
        // before は frame-head の prev {2,2}、after は now {5,5}（prev のままなら配線漏れ）。
        Assert.assertEq(expected = (Some((2, 2)), Some((5, 5))), (posOf0(w0), posOf0(w1)))

    // ── P0b: spawn/restore funnel が新規ユニットの位置を World へ seed ──

    /// P0b tripwire: `addOnePlayer`（spawn/restore の funnel）が新規ユニットの初期位置を
    /// World へ seed する（`Cmd.Move` を emit）。emit を applyCmd で worldRef に積み、
    /// `boardPieces` に id 7 @ (3,4) が現れることを確認する。funnel の emit 行を消す回帰で赤になる。
    @Test
    def testAddOnePlayerSeedsPositionToWorld(): Unit \ Assert =
        let sp = ({id = 7, classId = "test_player", gridPos = {x = 3, y = 4},
                    resource = TestUnitFixtures.testResource(4, 10),
                    weapons = Nil, staves = Nil, consumables = Nil, rings = Nil}: PlayerScene.Spawn);
        let world = region rc {
            let ref = Ref.fresh(rc, World.empty());
            run {
                discard PlayerScene.addOnePlayer(sp, MapScene.addWorldNode(Scene.empty())); ()
            } with handler World.Command {
                def emit(c, k) = { Ref.put(World.applyCmd(c, Ref.get(ref)), ref); k() }
            };
            Ref.get(ref)
        };
        Assert.assertEq(expected = Some((3, 4)), Map.get(7, playerPosMapOf(World.boardPieces(world))))

    // ── P3: refreshMirror（位置 mirror 撤去・World が位置権威）──

    /// P3 の要: `refreshMirror` は **scene gridPos を読まず** command 由来の位置を保持する。
    /// command で player 0 を {5,5} に置き、gridPos が {2,2} の scene を渡しても pos は {5,5} のまま。
    /// もし refreshMirror が gridPos を再構築（＝mirror 復活）すると {2,2} になり赤くなる回帰ガード。
    @Test
    def testRefreshMirrorKeepsCommandPosNotGridPos(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty());
        // sampleScene の player 0 の gridPos は {2,2}。refreshMirror は command の {5,5} を保持する。
        let refreshed = World.refreshMirror(sampleScene(), seeded);
        let World.World(w) = refreshed;
        Assert.assertEq(expected = Some((5, 5)), Map.get(0, w#pos) |> Option.map(p -> (p#x, p#y)))

    /// P3: scene に居なくなった id（死亡/退場で scene から除去）は pos から prune される（ghost piece 防止）。
    /// command で enemy 99 を置くが sampleScene に 99 は居ない → prune される。scene に居る player 0 は残る。
    @Test
    def testRefreshMirrorPrunesAbsentIds(): Unit \ Assert =
        let s1 = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(99), {x = 9, y = 9}),
                 World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty()));
        let World.World(w) = World.refreshMirror(sampleScene(), s1);
        Assert.assertEq(
            expected = (Some((5, 5)), None),
            (Map.get(0, w#pos) |> Option.map(p -> (p#x, p#y)),
             Map.get(99 + World.enemyUidBase(), w#pos) |> Option.map(p -> (p#x, p#y))))

    /// F6b: hp は **command 由来で保持**（scene から re-mirror しない＝hp 権威は World）。`Cmd.SetHp` で
    /// player 0 を 3 に下げ、refreshMirror 後も scene の 10 でなく command の 3 が残ることを pin。
    /// status/ids は引き続き scene 由来。位置と同じく prune（scene に居ない id は落ちる）。
    @Test
    def testRefreshMirrorPreservesCommandHp(): Unit \ Assert =
        let seeded  = World.syncFromScene(sampleScene(), World.empty());      // hp 0/1 = 10
        let damaged = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 3), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), damaged);
        // player 0 は command の 3（scene の 10 で上書きされない）、player 1 は 10 のまま、ids は scene 由来。
        Assert.assertEq(
            expected = (Some(3), Some(10), Set#{0, 1}),
            (Map.get(0, w#hp), Map.get(1, w#hp), w#playerIds))

    // ── §A payoff デモ: 位置の決定論（World は Cmd.Move ログの純粋関数）──
    // P0a→S5 で World が位置の権威・scene はその派生になった。位置の唯一の source は `Cmd.Move` のログ。
    // ゆえに「同じログ → 同じ位置」が成り立ち、save/replay の素地（World さえ持てば位置を再構築できる）になる。

    /// 共通のサンプル command ログ（移動の履歴）。
    def sampleMoveLog(): List[World.Cmd] =
        World.Cmd.Move(World.EntityRef.Player(0), {x = 1, y = 1})
            :: World.Cmd.Move(World.EntityRef.Enemy(5), {x = 3, y = 3})
            :: World.Cmd.Move(World.EntityRef.Player(0), {x = 2, y = 2}) :: Nil

    /// ログを空 World に畳んで replay する。
    def replayLog(log: List[World.Cmd]): World =
        List.foldLeft((w, c) -> World.applyCmd(c, w), World.empty(), log)

    /// テスト用: World から EntityRef の位置を引く（単体 pos アクセサは prod では使わない＝BoardQuery 経由
    /// で読むため、ここに test-local で置く）。
    def worldPosOf(ref: World.EntityRef, world: World): Option[{x = Int32, y = Int32}] =
        let World.World(w) = world; Map.get(World.toUid(ref), w#pos)

    /// determinism: World 位置は `Cmd.Move` ログの**純粋関数**。最終位置は「最後の Move 勝ち」
    /// （player 0 は {1,1}→{2,2}）。**同じログを独立に2回 replay すると同一**＝決定論リプレイの素地。
    @Test
    def testCommandLogReplayIsDeterministic(): Unit \ Assert =
        let log = sampleMoveLog();
        let tup = (ref, w) -> worldPosOf(ref, w) |> Option.map(p -> (p#x, p#y));
        let w1 = replayLog(log);
        let w2 = replayLog(log);
        Assert.assertEq(
            expected = (Some((2, 2)), Some((3, 3)), Some((2, 2)), Some((3, 3))),
            (tup(World.EntityRef.Player(0), w1), tup(World.EntityRef.Enemy(5), w1),
             tup(World.EntityRef.Player(0), w2), tup(World.EntityRef.Enemy(5), w2)))

    /// save/load の素地: ログから replay した World 位置を **`(id, x, y)` 列にシリアライズ→復元**しても
    /// 位置が round-trip する（World.pos は単純な component-map ＝そのまま保存可能）。
    /// EcsCodec の store 封筒（Map[EntityId, c]）にそのまま載る形であることをデモする。
    @Test
    def testWorldPosRoundTripsThroughSerialization(): Unit \ Assert =
        let World.World(w) = replayLog(sampleMoveLog());
        // "save": pos（単一 store）を (id, x, y) のフラット列へ。
        let saved = Map.foldRightWithKey((id, c, acc) -> (id, c#x, c#y) :: acc, Nil, w#pos);
        // "load": 列から pos を復元。
        let loaded = List.foldLeft((m, t) -> { let (id, x, y) = t;
            Map.insert(id, ({x = x, y = y}: {x = Int32, y = Int32}), m) }, Map.empty(), saved);
        let toTuples = m -> Map.foldRightWithKey((id, c, acc) -> (id, c#x, c#y) :: acc, Nil, m);
        Assert.assertEq(expected = toTuples(w#pos), toTuples(loaded))

    // ── F0: System パイプライン段 stepWorld（OOP→ECS 移行の足場）──

    /// F0 不変条件: `stepWorld`（現状 inert な `tickStatusEffects` のみ）は **位置を変えない**。
    /// gameLoop は `syncTreeFromWorld(stepWorld(world1))` で scene gridPos を derive するので、
    /// stepWorld が pos を保つ限り render は不変＝F0 は挙動不変。System を足して pos を壊す回帰で赤になる。
    @Test
    def testStepWorldPreservesPositions(): Unit \ Assert =
        let seeded = World.applyCmd(World.Cmd.Move(World.EntityRef.Enemy(5), {x = 3, y = 3}),
                     World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 5, y = 5}), World.empty()));
        let stepped = World.stepWorld(seeded, 0.0);
        let tup = ref -> worldPosOf(ref, stepped) |> Option.map(p -> (p#x, p#y));
        Assert.assertEq(
            expected = (Some((5, 5)), Some((3, 3))),
            (tup(World.EntityRef.Player(0)), tup(World.EntityRef.Enemy(5))))

    // ── B/tiles: 背景タイルの World 権威化（bake ハンドル preserve と gen bump）──

    /// setTileLayers した描画ハンドルが stepWorld（identity）を経ても残る（rebuild イベント間 World 権威で保持）。
    @Test
    def testTileLayersPreservedThroughStep(): Unit \ Assert =
        let handle = ({textureName = "atlas", tileSize = 26.0, worldPos = {x = 0.0, y = 0.0},
                       color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}, zIndex = -1,
                       tileVaoId = 7, tileCount = 42}: TileLayerHandle);
        let stepped = World.stepWorld(World.setTileLayers(handle :: Nil, World.empty()), 0.0);
        match World.tileLayersOf(stepped) {
            case h :: Nil => Assert.assertEq(expected = (7, 42), (h#tileVaoId, h#tileCount))
            case _        => bug!("expected exactly 1 tile layer preserved")
        }

    /// `Cmd.BumpTileGen` がマップ再構築の世代を 1 ずつ増やす（gameLoop の tile bake トリガの根拠）。
    @Test
    def testBumpTileGenIncrements(): Unit \ Assert =
        let w1 = World.applyCmd(World.Cmd.BumpTileGen, World.empty());
        let w2 = World.applyCmd(World.Cmd.BumpTileGen, w1);
        Assert.assertEq(expected = (1, 2), (World.tileGenOf(w1), World.tileGenOf(w2)))

    /// F3 基盤: `syncTreeFromWorld` が World の位置を scene の `gridPos` に **derive** する。
    /// F3 の sim/view 分離（位置の権威は World・scene はその派生／`replayMoveView` は見た目のみ）の前提。
    /// `Cmd.Move` で World 位置を動かし、syncTreeFromWorld 後に scene Player gridPos が World 由来に
    /// なる（元 scene は不変）ことを pin。既存テストは World 側（`worldPosOf`）のみで、この
    /// World→scene 書き戻しは未カバーだった＝F3 の土台を直接固定する。
    @Test
    def testSyncTreeFromWorldDerivesScenePos(): Unit \ Assert =
        let scene  = sampleScene();                       // player 0 @ (2,2)
        let seeded = World.syncFromScene(scene, World.empty());
        let moved  = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 7, y = 1}), seeded);
        let before = PlayerScene.getGridPos(0, scene);    // 元 scene は派生前ゆえ不変（2,2）
        let after  = PlayerScene.getGridPos(0, World.syncTreeFromWorld(moved, scene));
        Assert.assertEq(
            expected = ((2, 2), (7, 1)),
            ((before#x, before#y), (after#x, after#y)))

    // ── F2a: turn FSM の World mirror（SimPhase）──

    /// F2a: 既定は PlayerTurn・`mirrorTurnPhase`/`turnPhaseOf` が round-trip する。
    @Test
    def testTurnPhaseMirrorRoundTrips(): Unit \ Assert =
        let after = World.mirrorTurnPhase(SimPhase.EnemyTurn, World.empty());
        Assert.assertEq(
            expected = (SimPhase.PlayerTurn, SimPhase.EnemyTurn),
            (World.turnPhaseOf(World.empty()), World.turnPhaseOf(after)))

    /// F2a 不変条件: `refreshMirror`（毎フレーム）は turnPhase を**保持**する（書き手は gameLoop の mirror だけ）。
    /// status/pos と違い turnPhase は scene 由来でないので、refreshMirror が勝手に上書きしないことを pin。
    @Test
    def testRefreshMirrorPreservesTurnPhase(): Unit \ Assert =
        let seeded = World.mirrorTurnPhase(SimPhase.EnemyTurn, World.empty());
        let refreshed = World.refreshMirror(sampleScene(), seeded);
        Assert.assertEq(expected = SimPhase.EnemyTurn, World.turnPhaseOf(refreshed))

    /// F2b: `Cmd.SetPhase` が World.turnPhase を command で更新する（TurnPhase.State handler が put 時に emit）。
    @Test
    def testSetPhaseCommandUpdatesTurnPhase(): Unit \ Assert =
        let after = World.applyCmd(World.Cmd.SetPhase(SimPhase.EnemyTurn), World.empty());
        Assert.assertEq(expected = SimPhase.EnemyTurn, World.turnPhaseOf(after))

    /// F7-spike: `Cmd.SetAlerted` が World の enemyAlerted を更新し `alertedOf` で読める（flag→World の土台）。
    @Test
    def testSetAlertedCommandUpdatesWorld(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetAlerted(World.EntityRef.Enemy(5), true), World.empty());
        Assert.assertEq(expected = Some(true), World.alertedOf(World.EntityRef.Enemy(5), w))

    /// F7-slice5: `Cmd.SetWaited` が World を更新し `waitedOf` で読める＋preserve（command が scene 上書きされない）。
    @Test
    def testSetWaitedCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());   // player 0 waited=false
        let acted  = World.applyCmd(World.Cmd.SetWaited(World.EntityRef.Player(0), true), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), acted);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (World.waitedOf(World.EntityRef.Player(0), acted), Map.get(0, w#playerWaited)))

    /// F8-slice1: `Cmd.SetAttackTarget`/`ClearAttackTarget` が World を更新し `attackTargetOf` で読める＋preserve。
    /// `anyPlayerAttacking`/`anyEnemyAttacking`（driver の順序非依存判定の本体）も同時に検証。
    @Test
    def testSetAttackTargetCommandAndPreserve(): Unit \ Assert =
        let seeded  = World.syncFromScene(sampleScene(), World.empty());     // 誰も攻撃中でない
        let set     = seeded
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Player(0), 5))
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Enemy(5), 0));
        let World.World(w) = World.refreshMirror(sampleScene(), set);        // scene は None だが command 由来は保持
        Assert.assertEq(
            expected = (Some(5), Some(0), true, true),
            (World.attackTargetOf(World.EntityRef.Player(0), set),
             Map.get(5 + World.enemyUidBase(), w#attackTarget),
             World.anyPlayerAttacking(set),
             World.anyEnemyAttacking(set)))

    /// F8-slice1: `ClearAttackTarget` で対象が消え、`anyXAttacking` が false に戻る。
    @Test
    def testClearAttackTargetRemovesAndPredicateFalse(): Unit \ Assert =
        let cleared = World.empty()
            |> World.applyCmd(World.Cmd.SetAttackTarget(World.EntityRef.Player(0), 5))
            |> World.applyCmd(World.Cmd.ClearAttackTarget(World.EntityRef.Player(0)));
        Assert.assertEq(
            expected = (None, false),
            (World.attackTargetOf(World.EntityRef.Player(0), cleared),
             World.anyPlayerAttacking(cleared)))

    /// World 拡張: `Cmd.SetProgress` が味方の (level, exp) を更新し `progressOf` で読める＋preserve。
    /// Enemy は no-op（常に None）。
    @Test
    def testSetProgressCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());
        let leveled = seeded
            |> World.applyCmd(World.Cmd.SetProgress(World.EntityRef.Player(0), 3, 40))
            |> World.applyCmd(World.Cmd.SetProgress(World.EntityRef.Enemy(5), 9, 99));  // no-op
        let kept = World.refreshMirror(sampleScene(), leveled);
        Assert.assertEq(
            expected = (Some((3, 40)), None, Some((3, 40))),
            (World.progressOf(World.EntityRef.Player(0), leveled),
             World.progressOf(World.EntityRef.Enemy(5), leveled),
             World.progressOf(World.EntityRef.Player(0), kept)))

    /// 軸1 仕上げ: `Cmd.SetDying` が敵を World の dying set に入れ `isDyingOf` で読める＋preserve。
    /// Player は no-op（常に false）。
    @Test
    def testSetDyingCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());   // enemy 5 isDying=false
        let dying  = seeded
            |> World.applyCmd(World.Cmd.SetDying(World.EntityRef.Enemy(5)))
            |> World.applyCmd(World.Cmd.SetDying(World.EntityRef.Player(0)));  // no-op
        let kept = World.refreshMirror(sampleScene(), dying);
        Assert.assertEq(
            expected = (true, false, true),
            (World.isDyingOf(World.EntityRef.Enemy(5), dying),
             World.isDyingOf(World.EntityRef.Player(0), dying),
             World.isDyingOf(World.EntityRef.Enemy(5), kept)))

    /// F8-slice2: `Cmd.SetEnemyTurnBusy`/`SetPhaseObservedEnemy` が scalar bool を更新し読める＋
    /// refreshMirror で保持（scene mirror 元なし＝command 由来を持ち越す）。
    @Test
    def testSetTopBarBoolsCommandAndPreserve(): Unit \ Assert =
        let set = World.empty()
            |> World.applyCmd(World.Cmd.SetEnemyTurnBusy(true))
            |> World.applyCmd(World.Cmd.SetPhaseObservedEnemy(true));
        let kept = World.refreshMirror(sampleScene(), set);   // scene に mirror 元なし＝保持されるはず
        Assert.assertEq(
            expected = (true, true, true, true),
            (World.enemyTurnBusyOf(set), World.phaseObservedEnemyOf(set),
             World.enemyTurnBusyOf(kept), World.phaseObservedEnemyOf(kept)))

    /// F7-slice4: `Cmd.SetFollowUpUsed` が両 faction を更新し `followUpUsedOf` で読める＋preserve。
    @Test
    def testSetFollowUpUsedCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());
        let used   = seeded
            |> World.applyCmd(World.Cmd.SetFollowUpUsed(World.EntityRef.Player(0), true))
            |> World.applyCmd(World.Cmd.SetFollowUpUsed(World.EntityRef.Enemy(5), true));
        let World.World(w) = World.refreshMirror(sampleScene(), used);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (Map.get(0, w#followUpUsed), Map.get(5 + World.enemyUidBase(), w#followUpUsed)))

    /// F7-slice3: `Cmd.SetPrevPos` が World を更新し `prevPosOf` で読める＋preserve（command が scene 上書きされない）。
    @Test
    def testSetPrevPosCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());
        let moved  = World.applyCmd(World.Cmd.SetPrevPos(World.EntityRef.Enemy(5), {x = 7, y = 1}), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), moved);
        let toT = op -> Option.map(p -> (p#x, p#y), op);
        Assert.assertEq(
            expected = (Some((7, 1)), Some((7, 1))),
            (toT(World.prevPosOf(World.EntityRef.Enemy(5), moved)), toT(Map.get(5 + World.enemyUidBase(), w#enemyPrevPos))))

    /// F7-slice2: `Cmd.SetBottleUsed` が World を更新し `bottleUsedOf` で読める＋preserve。
    @Test
    def testSetBottleUsedCommandAndPreserve(): Unit \ Assert =
        let seeded = World.syncFromScene(sampleScene(), World.empty());   // enemy 5 bottleUsed=false
        let used   = World.applyCmd(World.Cmd.SetBottleUsed(World.EntityRef.Enemy(5), true), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), used);
        Assert.assertEq(
            expected = (Some(true), Some(true)),
            (World.bottleUsedOf(World.EntityRef.Enemy(5), used), Map.get(5 + World.enemyUidBase(), w#enemyBottleUsed)))

    /// F7-spike: alerted は command 由来で **保持**（scene から re-mirror しない）。`Cmd.SetAlerted(5,true)` 後、
    /// refreshMirror しても scene fixture（enemy 5 alerted=false）でなく command の true が残る＝flag も World 権威化可。
    @Test
    def testRefreshMirrorPreservesCommandAlerted(): Unit \ Assert =
        let seeded  = World.syncFromScene(sampleScene(), World.empty());
        let alerted = World.applyCmd(World.Cmd.SetAlerted(World.EntityRef.Enemy(5), true), seeded);
        let World.World(w) = World.refreshMirror(sampleScene(), alerted);
        Assert.assertEq(expected = Some(true), Map.get(5 + World.enemyUidBase(), w#enemyAlerted))

    /// F6a: `Cmd.SetHp` が World の hp store を faction 別に更新し、`hpOf` で読める（hp→World 権威化の土台）。
    /// 後段（F6b）で reader を World へ flip・refreshMirror を preserve 化する前提のコマンドシーム。
    @Test
    def testSetHpCommandUpdatesWorldHp(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 7),
                World.applyCmd(World.Cmd.SetHp(World.EntityRef.Enemy(5), 3), World.empty()));
        Assert.assertEq(
            expected = (Some(7), Some(3)),
            (World.hpOf(World.EntityRef.Player(0), w), World.hpOf(World.EntityRef.Enemy(5), w)))

    // ── S-A0: baseStats（stats + maxHp）の read-model mirror ──

    /// syncFromScene が baseStats（resource 由来の base 戦闘値 + maxHp）を World へ mirror する。
    /// status/ring 補正前の生値で、scene の resource から `baseStatsFrom` で導いた値と一致する
    /// （player 0 / enemy 5）。fixture 値に依存せず parallel-derivation で同値を確認する。
    @Test
    def testBaseStatsMirrorsResource(): Unit \ Assert =
        let scene = sampleScene();
        let w = World.syncFromScene(scene, World.empty());
        // record は Eq を持たないので 8-tuple に射影して比較する（Int32 tuple は Eq）。
        let toTup = bs -> (bs#attack, bs#magicAttack, bs#defense, bs#magicDefense,
                           bs#skill, bs#speed, bs#luck, bs#maxHp);
        let p0 = Option.map(d -> toTup(Combat.baseStatsFrom(d#resource)), PlayerScene.get(0, scene));
        let e5 = Option.map(d -> toTup(Combat.baseStatsFrom(d#resource)), EnemyScene.get(5, scene));
        Assert.assertEq(
            expected = (p0, e5),
            (Option.map(toTup, World.baseStatsOf(World.EntityRef.Player(0), w)),
             Option.map(toTup, World.baseStatsOf(World.EntityRef.Enemy(5), w))))

    /// S2.3: refreshMirror は baseStats を **command 由来で保持**（preserve）＝再 mirror しない。
    /// syncFromScene が seed した baseStats が refreshMirror 後も残り、maxHp = resource#hp が player 0 で読める。
    @Test
    def testRefreshMirrorPreservesBaseStats(): Unit \ Assert =
        let scene = sampleScene();
        let w = World.refreshMirror(scene, World.syncFromScene(scene, World.empty()));
        let expectedMaxHp = Option.map(d -> d#resource#hp, PlayerScene.get(0, scene));
        Assert.assertEq(
            expected = expectedMaxHp,
            Option.map(bs -> bs#maxHp, World.baseStatsOf(World.EntityRef.Player(0), w)))

    /// S2.3: refreshMirror は command-derived baseStats を上書きしない（preserve）。SetBaseStats で
    /// player 0 の maxHp を scene resource と無関係な値（999）へ書いても refreshMirror 後も残る
    /// （再 mirror なら scene の resource#hp で上書きされるはず＝preserve であることの証明）。
    @Test
    def testRefreshMirrorPreservesCommandBaseStats(): Unit \ Assert =
        let scene  = sampleScene();
        let seeded = World.syncFromScene(scene, World.empty());
        let custom = ({attack = 1, magicAttack = 2, defense = 3, magicDefense = 4,
                       skill = 5, speed = 6, luck = 7, maxHp = 999}: Combat.BaseStats);
        let withCmd = World.applyCmd(World.Cmd.SetBaseStats(World.EntityRef.Player(0), custom), seeded);
        let refreshed = World.refreshMirror(scene, withCmd);
        Assert.assertEq(
            expected = Some(999),
            Option.map(bs -> bs#maxHp, World.baseStatsOf(World.EntityRef.Player(0), refreshed)))

    // ── S-A0b: weaponView（装備武器の戦闘投影）の read-model mirror ──

    /// syncFromScene が weaponView を World へ mirror する。scene 由来の equippedWeaponView と一致する
    /// （player 0 / enemy 5）。record/enum は Eq 非自動ゆえスカラ tuple に射影して比較する。
    @Test
    def testWeaponViewMirrorsEquipped(): Unit \ Assert =
        let scene = sampleScene();
        let w = World.syncFromScene(scene, World.empty());
        let proj = ov -> Option.map(wv -> (wv#attack, wv#hit, wv#crit, wv#isPhysical,
                                            wv#proficient, wv#effectValue), ov);
        let expP0 = PlayerScene.get(0, scene)
            |> Option.map(d -> proj(PlayerScene.equippedWeaponView(d))) |> Option.getWithDefault(None);
        let expE5 = EnemyScene.get(5, scene)
            |> Option.map(d -> proj(EnemyScene.equippedWeaponView(d))) |> Option.getWithDefault(None);
        Assert.assertEq(
            expected = (expP0, expE5),
            (proj(World.weaponViewOf(World.EntityRef.Player(0), w)),
             proj(World.weaponViewOf(World.EntityRef.Enemy(5), w))))

    // ── D3: weapons store（command-derive・preserve+prune）──

    /// applyCmd(SetWeapons) が weapons store を更新する。weaponsOf で読み戻し、record Eq 非自動ゆえ
    /// (長さ, 先頭耐久) に射影して比較する（具体値 pin・test 本体に match を書かない）。
    @Test
    def testApplySetWeaponsUpdatesStore(): Unit \ Assert =
        let ws = TestUnitFixtures.testWeaponFull(2, 5) :: TestUnitFixtures.testWeaponFull(3, 9) :: Nil;
        let w  = World.applyCmd(World.Cmd.SetWeapons(World.EntityRef.Player(0), ws), World.empty());
        let proj = World.weaponsOf(World.EntityRef.Player(0), w)
            |> Option.map(xs -> (List.length(xs), List.head(xs) |> Option.map(x -> x#durability)));
        Assert.assertEq(expected = Some((2, Some(5))), proj)

    /// syncFromScene 直後は World weapons == scene #weapons ＝ weaponsMismatches 空（dual-write 整合の基準）。
    /// sampleScene は player 0 が weapons=[testWeapon] / enemy 5 が weapon=Some(testWeapon)。
    @Test
    def testWeaponsMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.weaponsMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ player0 weapons を空に drift させると weaponsMismatches が検出する
    /// （dual-write 漏れ＝[WEAPONS DIFF] が鳴るべき状況を pin）。
    @Test
    def testWeaponsMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetWeapons(World.EntityRef.Player(0), Nil), world);
        Assert.assertEq(expected = false, List.isEmpty(World.weaponsMismatches(drifted, scene)))

    /// 代表 mutation の dual-write 整合: scene の player0 武器耐久を 1 本目だけ削り、同じ新 list を
    /// SetWeapons で World へ併置すると weaponsMismatches は空のまま（consumeEquippedWeapon の縮図）。
    @Test
    def testWeaponsMismatchesEmptyAfterConsumeStyleDualWrite(): Unit \ Assert =
        let scene    = sampleScene();
        let world    = World.syncFromScene(scene, World.empty());
        let newWs    = TestUnitFixtures.testWeaponFull(2, 9) :: Nil;  // 耐久 10→9 に消費した先頭差し替え
        let scene2   = PlayerScene.mapPlayer(0, d -> {weapons = newWs | d}, scene);
        let world2   = World.applyCmd(World.Cmd.SetWeapons(World.EntityRef.Player(0), newWs), world);
        Assert.assertEq(expected = true, List.isEmpty(World.weaponsMismatches(world2, scene2)))

    // ── S2.3: baseStats store（command-derive・両 faction・preserve+prune）──

    /// applyCmd(SetBaseStats) が baseStats store を更新する（両 faction）。baseStatsOf で読み戻し、
    /// record Eq 非自動ゆえ 8-tuple に射影して比較する。
    @Test
    def testApplySetBaseStatsUpdatesStore(): Unit \ Assert =
        let bs = ({attack = 1, magicAttack = 2, defense = 3, magicDefense = 4,
                   skill = 5, speed = 6, luck = 7, maxHp = 99}: Combat.BaseStats);
        let toTup = b -> (b#attack, b#magicAttack, b#defense, b#magicDefense, b#skill, b#speed, b#luck, b#maxHp);
        let wP = World.applyCmd(World.Cmd.SetBaseStats(World.EntityRef.Player(0), bs), World.empty());
        let wE = World.applyCmd(World.Cmd.SetBaseStats(World.EntityRef.Enemy(5), bs), World.empty());
        Assert.assertEq(
            expected = (Some((1, 2, 3, 4, 5, 6, 7, 99)), Some((1, 2, 3, 4, 5, 6, 7, 99))),
            (Option.map(toTup, World.baseStatsOf(World.EntityRef.Player(0), wP)),
             Option.map(toTup, World.baseStatsOf(World.EntityRef.Enemy(5), wE))))

    /// syncFromScene 直後は World baseStats == scene resource 由来 ＝ baseStatsMismatches 空（dual-write 整合の基準）。
    @Test
    def testBaseStatsMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.baseStatsMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ player0 baseStats を別値へ drift させると baseStatsMismatches が検出する
    /// （dual-write 漏れ＝[BASESTATS DIFF] が鳴るべき状況を pin）。
    @Test
    def testBaseStatsMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drift   = ({attack = 999, magicAttack = 0, defense = 0, magicDefense = 0,
                        skill = 0, speed = 0, luck = 0, maxHp = 0}: Combat.BaseStats);
        let drifted = World.applyCmd(World.Cmd.SetBaseStats(World.EntityRef.Player(0), drift), world);
        Assert.assertEq(expected = false, List.isEmpty(World.baseStatsMismatches(drifted, scene)))

    // ── S2.4: weaponView / ringBonus store（command-derive・両 faction・preserve+prune）──

    /// S2.4: refreshMirror は command-derived weaponView を上書きしない（preserve）。sampleScene の
    /// player 0 は武器装備＝synced weaponView は Some。SetWeaponView で None を書いても refreshMirror 後も
    /// None のまま（再 mirror なら装備武器で Some に戻るはず＝preserve の証明）。
    @Test
    def testRefreshMirrorPreservesCommandWeaponView(): Unit \ Assert =
        let scene     = sampleScene();
        let seeded    = World.syncFromScene(scene, World.empty());
        let cleared   = World.applyCmd(World.Cmd.SetWeaponView(World.EntityRef.Player(0), None), seeded);
        let refreshed = World.refreshMirror(scene, cleared);
        Assert.assertEq(
            expected = None,
            Option.map(wv -> wv#attack, World.weaponViewOf(World.EntityRef.Player(0), refreshed)))

    /// S2.4: refreshMirror は command-derived ringBonus を上書きしない（preserve）。SetRingBonus で
    /// player 0 へ scene 無関係な attack 補正(77)を書いても refreshMirror 後も残る（再 mirror なら
    /// 装備指輪由来＝未装備で 0 に戻るはず＝preserve の証明）。
    @Test
    def testRefreshMirrorPreservesCommandRingBonus(): Unit \ Assert =
        let scene     = sampleScene();
        let seeded    = World.syncFromScene(scene, World.empty());
        let custom    = ({attack = 77 | Ring.zeroBonuses()}: Ring.Bonuses);
        let withCmd   = World.applyCmd(World.Cmd.SetRingBonus(World.EntityRef.Player(0), custom), seeded);
        let refreshed = World.refreshMirror(scene, withCmd);
        Assert.assertEq(
            expected = Some(77),
            Option.map(rb -> rb#attack, World.ringBonusOf(World.EntityRef.Player(0), refreshed)))

    /// syncFromScene 直後は World weaponView == scene 装備武器投影 ＝ weaponViewMismatches 空（dual-write 整合の基準）。
    @Test
    def testWeaponViewMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.weaponViewMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ player0 weaponView を None に drift させると weaponViewMismatches が検出する
    /// （dual-write 漏れ＝[WEAPONVIEW DIFF] が鳴るべき状況を pin。player0 は装備武器ありゆえ scene は Some）。
    @Test
    def testWeaponViewMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetWeaponView(World.EntityRef.Player(0), None), world);
        Assert.assertEq(expected = false, List.isEmpty(World.weaponViewMismatches(drifted, scene)))

    /// syncFromScene 直後は World ringBonus == scene 装備指輪投影 ＝ ringBonusMismatches 空（dual-write 整合の基準）。
    @Test
    def testRingBonusMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.ringBonusMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ player0 ringBonus を別値へ drift させると ringBonusMismatches が検出する
    /// （dual-write 漏れ＝[RINGBONUS DIFF] が鳴るべき状況を pin）。
    @Test
    def testRingBonusMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drift   = ({attack = 999 | Ring.zeroBonuses()}: Ring.Bonuses);
        let drifted = World.applyCmd(World.Cmd.SetRingBonus(World.EntityRef.Player(0), drift), world);
        Assert.assertEq(expected = false, List.isEmpty(World.ringBonusMismatches(drifted, scene)))

    // ── S2.5: moveTiles store（command-derive・両 faction・spawn 後不変・preserve+prune）──

    /// applyCmd(SetMoveTiles) が moveTiles store を更新する（Int32 ゆえ直接比較）。
    @Test
    def testApplySetMoveTilesUpdatesStore(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetMoveTiles(World.EntityRef.Player(0), 7), World.empty());
        Assert.assertEq(expected = Some(7), World.moveTilesOf(World.EntityRef.Player(0), w))

    /// S2.5: refreshMirror は command-derived moveTiles を上書きしない（preserve）。SetMoveTiles で
    /// player 0 へ scene base と無関係な値(99)を書いても refreshMirror 後も残る（再 mirror なら
    /// scene の d#moveTiles に戻るはず＝preserve の証明）。
    @Test
    def testRefreshMirrorPreservesCommandMoveTiles(): Unit \ Assert =
        let scene     = sampleScene();
        let seeded    = World.syncFromScene(scene, World.empty());
        let withCmd   = World.applyCmd(World.Cmd.SetMoveTiles(World.EntityRef.Player(0), 99), seeded);
        let refreshed = World.refreshMirror(scene, withCmd);
        Assert.assertEq(expected = Some(99), World.moveTilesOf(World.EntityRef.Player(0), refreshed))

    /// syncFromScene 直後は World moveTiles == scene base moveTiles ＝ moveTilesMismatches 空（dual-write 整合の基準）。
    @Test
    def testMoveTilesMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.moveTilesMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ player0 moveTiles を別値(99)へ drift させると moveTilesMismatches が検出する
    /// （dual-write 漏れ＝[MOVETILES DIFF] が鳴るべき状況を pin）。
    @Test
    def testMoveTilesMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetMoveTiles(World.EntityRef.Player(0), 99), world);
        Assert.assertEq(expected = false, List.isEmpty(World.moveTilesMismatches(drifted, scene)))

    // ── D4: staves/consumables/rings/ringEquipped store（command-derive・player-only・preserve+prune）──

    def d4Staff(): Staff.StaffResource = {
        name       = "テスト杖", effect = Staff.StaffEffect.Heal, durability = 3, weight = 0.75,
        sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0},
                        scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
        description = "", effectRule = None
    }
    def d4Consumable(): Consumable.ConsumableResource = {
        name = "きずぐすり", effect = Consumable.ConsumableEffect.Heal, magnitude = 10, duration = 0,
        healAmount = 10, durability = 5, weight = 0.5,
        sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0},
                    scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
        description = "", effectRule = None
    }
    def d4Ring(): Ring.RingResource = {
        name = "ちからの指輪", effect = Ring.RingEffect.Power, power = 3, weight = 0.4,
        sprite = ({texture = "t", hframes = 1, vframes = 1, frame = 0, offset = {x = 0.0, y = 0.0},
                    scale = {x = 1.0, y = 1.0}, flipForFacing = false}: Sprite.SpriteResource),
        description = "", effectRule = None
    }

    /// applyCmd(SetStaves) が staves store を更新する。stavesOf で読み戻し、(長さ, 先頭耐久) に射影。
    @Test
    def testApplySetStavesUpdatesStore(): Unit \ Assert =
        let xs = d4Staff() :: d4Staff() :: Nil;
        let w  = World.applyCmd(World.Cmd.SetStaves(World.EntityRef.Player(0), xs), World.empty());
        let proj = World.stavesOf(World.EntityRef.Player(0), w)
            |> Option.map(ys -> (List.length(ys), List.head(ys) |> Option.map(x -> x#durability)));
        Assert.assertEq(expected = Some((2, Some(3))), proj)

    /// SetStaves は player-only（Enemy は no-op）＝stavesOf(Enemy) は None。
    @Test
    def testStavesEnemyIsNone(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetStaves(World.EntityRef.Enemy(5), d4Staff() :: Nil), World.empty());
        Assert.assertEq(expected = None, World.stavesOf(World.EntityRef.Enemy(5), w) |> Option.map(List.length))

    /// synced 直後は World staves == scene #staves（共に Nil）＝stavesMismatches 空。
    @Test
    def testStavesMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.stavesMismatches(world, scene)))

    /// 非 vacuous: World 側だけ player0 staves を増やすと stavesMismatches が検出する（[STAVES DIFF]）。
    @Test
    def testStavesMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetStaves(World.EntityRef.Player(0), d4Staff() :: Nil), world);
        Assert.assertEq(expected = false, List.isEmpty(World.stavesMismatches(drifted, scene)))

    /// applyCmd(SetConsumables) が consumables store を更新する。
    @Test
    def testApplySetConsumablesUpdatesStore(): Unit \ Assert =
        let xs = d4Consumable() :: Nil;
        let w  = World.applyCmd(World.Cmd.SetConsumables(World.EntityRef.Player(0), xs), World.empty());
        let proj = World.consumablesOf(World.EntityRef.Player(0), w)
            |> Option.map(ys -> (List.length(ys), List.head(ys) |> Option.map(x -> x#durability)));
        Assert.assertEq(expected = Some((1, Some(5))), proj)

    /// 非 vacuous: World 側だけ consumables drift で consumablesMismatches 検出（[CONSUMABLES DIFF]）。
    @Test
    def testConsumablesMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetConsumables(World.EntityRef.Player(0), d4Consumable() :: Nil), world);
        Assert.assertEq(expected = false, List.isEmpty(World.consumablesMismatches(drifted, scene)))

    /// applyCmd(SetRings) が rings store を更新する。(長さ, 先頭 power) 射影で pin。
    @Test
    def testApplySetRingsUpdatesStore(): Unit \ Assert =
        let xs = d4Ring() :: Nil;
        let w  = World.applyCmd(World.Cmd.SetRings(World.EntityRef.Player(0), xs), World.empty());
        let proj = World.ringsOf(World.EntityRef.Player(0), w)
            |> Option.map(ys -> (List.length(ys), List.head(ys) |> Option.map(x -> x#power)));
        Assert.assertEq(expected = Some((1, Some(3))), proj)

    /// 非 vacuous: World 側だけ rings drift で ringsMismatches 検出（[RINGS DIFF]）。
    @Test
    def testRingsMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetRings(World.EntityRef.Player(0), d4Ring() :: Nil), world);
        Assert.assertEq(expected = false, List.isEmpty(World.ringsMismatches(drifted, scene)))

    /// applyCmd(SetRingEquipped) が ringEquipped store を更新する（Bool・player-only）。
    @Test
    def testApplySetRingEquippedUpdatesStore(): Unit \ Assert =
        let w = World.applyCmd(World.Cmd.SetRingEquipped(World.EntityRef.Player(0), true), World.empty());
        Assert.assertEq(expected = Some(true), World.ringEquippedOf(World.EntityRef.Player(0), w))

    /// 非 vacuous: synced(false) から World 側だけ true に drift で ringEquippedMismatches 検出。
    @Test
    def testRingEquippedMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetRingEquipped(World.EntityRef.Player(0), true), world);
        Assert.assertEq(expected = false, List.isEmpty(World.ringEquippedMismatches(drifted, scene)))

    /// refreshMirror が command 由来の inventory store を preserve しつつ scene 不在 id を prune する。
    /// player0 に SetStaves で 1 本積み、refreshMirror 後も保持される（再 mirror で消えない）。
    @Test
    def testRefreshMirrorPreservesCommandStaves(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        let withStaff = World.applyCmd(World.Cmd.SetStaves(World.EntityRef.Player(0), d4Staff() :: Nil), world);
        let refreshed = World.refreshMirror(scene, withStaff);
        Assert.assertEq(
            expected = Some(1),
            World.stavesOf(World.EntityRef.Player(0), refreshed) |> Option.map(List.length))

    // ── S-A0c: ringBonus（装備指輪ボーナス）の read-model mirror ──

    /// syncFromScene が ringBonus を World へ mirror する。scene 由来の equippedRingBonus と一致する
    /// （player 0 / enemy 5）。record は Eq 非自動ゆえ 5-tuple に射影して比較する。
    @Test
    def testRingBonusMirrorsEquipped(): Unit \ Assert =
        let scene = sampleScene();
        let w = World.syncFromScene(scene, World.empty());
        let proj = b -> (b#attack, b#speed, b#defense, b#skill, b#luck);
        let expP0 = Option.map(d -> proj(PlayerScene.equippedRingBonus(d)), PlayerScene.get(0, scene));
        let expE5 = Option.map(d -> proj(EnemyScene.equippedRingBonus(d)), EnemyScene.get(5, scene));
        Assert.assertEq(
            expected = (expP0, expE5),
            (Option.map(proj, World.ringBonusOf(World.EntityRef.Player(0), w)),
             Option.map(proj, World.ringBonusOf(World.EntityRef.Enemy(5), w))))

    // ── B1: combatViewOf が scene combatView を World だけから完全再構築する（parity） ──

    /// `World.combatViewOf(ref)` が `PlayerScene.combatView` / `EnemyScene.combatView` と同一の
    /// CombatView を返すことを固定 fixture で証明する（S-A0 の end-to-end 検証）。record/enum は Eq
    /// 非自動ゆえ全数値 + 武器投影を tuple に射影して比較する。これが緑なら reader を World へ flip できる。
    @Test
    def testCombatViewOfReconstructsSceneView(): Unit \ Assert =
        let scene = sampleScene();
        let w = World.syncFromScene(scene, World.empty());
        let wvProj = wv -> (wv#attack, wv#hit, wv#crit, wv#isPhysical, wv#proficient, wv#effectValue);
        let cvProj = cv -> (cv#attack, cv#magicAttack, cv#defense, cv#magicDefense, cv#skill,
                            cv#speed, cv#luck, cv#hp, cv#maxHp, cv#hitMod,
                            Option.map(wvProj, cv#weapon));
        let expP0 = Option.map(d -> cvProj(PlayerScene.combatView(d)), PlayerScene.get(0, scene));
        let expE5 = Option.map(d -> cvProj(EnemyScene.combatView(d)), EnemyScene.get(5, scene));
        Assert.assertEq(
            expected = (expP0, expE5),
            (Option.map(cvProj, World.combatViewOf(World.EntityRef.Player(0), w)),
             Option.map(cvProj, World.combatViewOf(World.EntityRef.Enemy(5), w))))

    /// B1 安全網: synced な World では combatViewMismatches が空（read-model ＝ scene と一致）。
    /// 実機 [COMBATVIEW DIFF] が無音であることの単体版。
    @Test
    def testCombatViewMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let w = World.refreshMirror(scene, World.syncFromScene(scene, World.empty()));
        Assert.assertEq(expected = true, List.isEmpty(World.combatViewMismatches(w, scene)))

    /// B1 強化 parity: **状態異常 active** な player でも combatViewOf == combatView（status mods 経路）。
    /// 既定 fixture は statuses=Nil・ring 未装備で `m`/`rb` がゼロのため、SpdDown を 1 件付けて
    /// `StatusSystem.combatMods` の spdDelta が両 combatView 実装で同一に載ることを確認する。
    @Test
    def testCombatViewOfParityWithStatus(): Unit \ Assert =
        let worldM = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let mk = () -> Marker2D.make(Vec2.zero());
        let status = ({effect = StatusSystem.StatusEffect.SpdDown, magnitude = 2,
                       remaining = 3}: StatusSystem.Status);
        let pdata = playerDataS(0, status :: Nil);
        let scene = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(worldM, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(mk(), NodeTag.Player(pdata)));
        let w = World.syncFromScene(scene, World.empty());
        let wvProj = wv -> (wv#attack, wv#hit, wv#crit, wv#isPhysical, wv#proficient, wv#effectValue);
        let cvProj = cv -> (cv#attack, cv#magicAttack, cv#defense, cv#magicDefense, cv#skill,
                            cv#speed, cv#luck, cv#hp, cv#maxHp, cv#hitMod,
                            Option.map(wvProj, cv#weapon));
        Assert.assertEq(
            expected = Some(cvProj(PlayerScene.combatView(pdata))),
            Option.map(cvProj, World.combatViewOf(World.EntityRef.Player(0), w)))

    // ── S-A0d: growth（level-up 用 base Stats + 成長率 + 名前）の read-model（player-only） ──

    /// growth は player の resource から base#hp/rates#hp/name を mirror し、enemy は None（player-only）。
    /// これで resolveCombat の level-up を resource threading 無しで World 完結に解ける（spike の gap close）。
    @Test
    def testGrowthMirrorsResourcePlayerOnly(): Unit \ Assert =
        let scene = sampleScene();
        let w = World.syncFromScene(scene, World.empty());
        let p0 = PlayerScene.get(0, scene)
            |> Option.map(d -> (LevelSystem.statsOf(d#resource)#hp, d#resource#growthRates#hp, d#resource#description));
        Assert.assertEq(
            expected = (p0, true),
            (World.growthOf(World.EntityRef.Player(0), w) |> Option.map(g -> (g#base#hp, g#rates#hp, g#name)),
             Option.isEmpty(World.growthOf(World.EntityRef.Enemy(5), w))))

    // ── S4.1: World 由来 unitView twin（scene unitView と bit 一致・additive parity）──

    /// syncFromScene 直後は World 由来 `unitViewFromWorld` == scene `unitView` ＝ unitViewMismatches 空（parity の基準）。
    /// sampleScene は player 0,1（base move 4・weapons=[testWeapon]）／enemy 5（base move 3・weapon=Some）。
    @Test
    def testUnitViewMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.unitViewMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ player0 の位置を drift させると unitViewMismatches が検出する
    /// （twin の pos が scene unitView と乖離＝[UNITVIEW DIFF] が鳴るべき状況を pin）。
    @Test
    def testUnitViewMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.Move(World.EntityRef.Player(0), {x = 9, y = 9}), world);
        Assert.assertEq(expected = false, List.isEmpty(World.unitViewMismatches(drifted, scene)))

    /// フィールド単位 pin: effective-move / weaponRange / combat / aiType / isDying / hidden が
    /// faction 別に scene unitView と一致し、かつ twin が Some（None 同士の vacuous でない）ことを併せて検証する。
    @Test
    def testUnitViewFromWorldFieldsMatchScene(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        let cvProj = cv -> (cv#attack, cv#magicAttack, cv#defense, cv#magicDefense, cv#skill,
                            cv#speed, cv#luck, cv#hp, cv#maxHp);
        let field = uv -> (uv#moveTiles, Option.map(r -> (r#min, r#max), uv#weaponRange),
                           cvProj(uv#combat), uv#aiType, uv#isDying, uv#hidden);
        let worldP = World.unitViewFromWorld(World.EntityRef.Player(0), world, scene) |> Option.map(field);
        let sceneP = PlayerScene.get(0, scene) |> Option.map(d -> field(PlayerScene.unitView(d)));
        let worldE = World.unitViewFromWorld(World.EntityRef.Enemy(5), world, scene) |> Option.map(field);
        let sceneE = EnemyScene.get(5, scene) |> Option.map(d -> field(EnemyScene.unitView(d)));
        Assert.assertEq(
            expected = (sceneP, sceneE, false, false),
            (worldP, worldE, Option.isEmpty(worldP), Option.isEmpty(worldE)))

    // ── S4.4: dataFromWorld（World 由来 PlayerData twin）/ playerDataMismatches（全 23 field parity）──

    /// syncFromScene 直後は World 由来 dataFromWorld == scene PlayerScene.get Data ＝ playerDataMismatches 空
    /// （全 23 field の parity 基準。W14 accessor + R残置5 + S→W未昇格2 の stitch が scene と bit 一致）。
    @Test
    def testPlayerDataMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.playerDataMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ player0 hp を drift させると playerDataMismatches が検出する
    /// （[PLAYERDATA DIFF] が鳴るべき状況を pin。射影に hp が含まれていることの実証も兼ねる）。
    @Test
    def testPlayerDataMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Player(0), 99), world);
        Assert.assertEq(expected = false, List.isEmpty(World.playerDataMismatches(drifted, scene)))

    /// フィールド単位 pin: dataFromWorld(0) の代表 field（gridPos/hp/moveTiles/level/classId）が
    /// sampleScene fixture 値と一致し、かつ twin が Some（None 同士の vacuous でない）ことを併せて検証する。
    @Test
    def testDataFromWorldRepresentativeFields(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        let field = d -> ((d#gridPos#x, d#gridPos#y), d#hp, d#moveTiles, d#level, d#classId);
        let twin  = World.dataFromWorld(0, world, scene) |> Option.map(field);
        Assert.assertEq(
            expected = (Some(((2, 2), 10, 4, 1, "test_player")), false),
            (twin, Option.isEmpty(twin)))

    // ── 正準キー集約 refactor: near-duplicate 分離維持 & composite field-coverage pin ──
    // 軸B（call-site key selection・誤 sibling 配線）の唯一の防壁。コンパイラも mismatch テストも
    // 捕えられない「強→弱」（field 落ち・誤 key）を、各キーが正しい field を見ていることで pin する。

    /// 戦闘 8 field を埋めた代表 WeaponView。record 部分上書きで 1 field だけ違える基点。
    def wvSample(): Combat.WeaponView =
        {weaponType = WeaponCatalog.WeaponType.Sword, attack = 5, hit = 80, crit = 0,
         isPhysical = true, proficient = true,
         effect = WeaponCatalog.WeaponEffect.NoEffect, effectValue = 0}

    /// ★MANDATORY (§5.2): weaponViewKey(8) ≠ weaponViewCombatKey(6)。weaponType だけ違える 2 値で
    /// 8-key は検出（!=）・6-key は検出しない（==・weaponType を含めない設計の pin）。誤統合の防壁。
    @Test
    def testWeaponViewKeysSeparateOnWeaponType(): Unit \ Assert =
        let a = wvSample();
        let b = {weaponType = WeaponCatalog.WeaponType.Axe | wvSample()};
        Assert.assertEq(
            expected = (true, true),
            (World.weaponViewKey(a) != World.weaponViewKey(b),
             World.weaponViewCombatKey(a) == World.weaponViewCombatKey(b)))

    /// ★MANDATORY (§5.2): weaponViewKey は effect も見る／weaponViewCombatKey は見ない。effect だけ
    /// 違える 2 値で 8-key 検出・6-key 非検出を pin（weaponType と並ぶ single-site silent field）。
    @Test
    def testWeaponViewKeysSeparateOnEffect(): Unit \ Assert =
        let a = wvSample();
        let c = {effect = WeaponCatalog.WeaponEffect.Lifesteal | wvSample()};
        Assert.assertEq(
            expected = (true, true),
            (World.weaponViewKey(a) != World.weaponViewKey(c),
             World.weaponViewCombatKey(a) == World.weaponViewCombatKey(c)))

    /// ★MANDATORY (§5.2): equippedRingKey(name,effect,power) ≠ ringKey(name,power)。effect だけ違える
    /// 指輪で 3-key は検出・2-key は検出しない（装備=effect 必須 / 在庫=power 代表）。誤統合の防壁。
    @Test
    def testRingKeysSeparateOnEffect(): Unit \ Assert =
        let r1 = d4Ring();                                     // effect = Power
        let r2 = {effect = Ring.RingEffect.Guard | d4Ring()};  // name+power 同一・effect のみ Guard
        Assert.assertEq(
            expected = (true, true),
            (World.equippedRingKey(r1) != World.equippedRingKey(r2),
             World.ringKey(r1) == World.ringKey(r2)))

    /// ★MANDATORY (§5.3): baseStatsKey が 8 field を漏れなく見る pin（各 1 field drift で検出）。
    @Test
    def testBaseStatsKeyCoversAllFields(): Unit \ Assert =
        let b = ({attack = 1, magicAttack = 2, defense = 3, magicDefense = 4,
                  skill = 5, speed = 6, luck = 7, maxHp = 8}: Combat.BaseStats);
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true),
            (World.baseStatsKey({attack = 99 | b})       != World.baseStatsKey(b),
             World.baseStatsKey({magicAttack = 99 | b})  != World.baseStatsKey(b),
             World.baseStatsKey({defense = 99 | b})      != World.baseStatsKey(b),
             World.baseStatsKey({magicDefense = 99 | b}) != World.baseStatsKey(b),
             World.baseStatsKey({skill = 99 | b})        != World.baseStatsKey(b),
             World.baseStatsKey({speed = 99 | b})        != World.baseStatsKey(b),
             World.baseStatsKey({luck = 99 | b})         != World.baseStatsKey(b),
             World.baseStatsKey({maxHp = 99 | b})        != World.baseStatsKey(b)))

    /// ★MANDATORY (§5.3): resourceStatKey が 11 stat field を漏れなく見る pin。
    @Test
    def testResourceStatKeyCoversAllFields(): Unit \ Assert =
        let r = TestUnitFixtures.testResource(4, 10);
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true, true),
            (World.resourceStatKey({moveTiles = 99 | r})    != World.resourceStatKey(r),
             World.resourceStatKey({level = 99 | r})        != World.resourceStatKey(r),
             World.resourceStatKey({hp = 99 | r})           != World.resourceStatKey(r),
             World.resourceStatKey({attack = 99 | r})       != World.resourceStatKey(r),
             World.resourceStatKey({defense = 99 | r})      != World.resourceStatKey(r),
             World.resourceStatKey({magicAttack = 99 | r})  != World.resourceStatKey(r),
             World.resourceStatKey({magicDefense = 99 | r}) != World.resourceStatKey(r),
             World.resourceStatKey({speed = 99 | r})        != World.resourceStatKey(r),
             World.resourceStatKey({skill = 99 | r})        != World.resourceStatKey(r),
             World.resourceStatKey({luck = 99 | r})         != World.resourceStatKey(r),
             World.resourceStatKey({constitution = 99 | r}) != World.resourceStatKey(r)))

    /// ★MANDATORY (§5.3): combatViewKey が 10 数値 field + 内蔵 weapon を見る pin。最後の項は
    /// 戦闘 field を違える weapon を載せると検出する＝weaponViewCombatKey 配線の pin（combat sub-key 落ち防止）。
    @Test
    def testCombatViewKeyCoversAllFields(): Unit \ Assert =
        let cv = ({attack = 1, magicAttack = 2, defense = 3, magicDefense = 4, skill = 5,
                   speed = 6, luck = 7, hp = 8, maxHp = 9, hitMod = 10, weapon = None}: Combat.CombatView);
        let cvW1 = {weapon = Some(wvSample()) | cv};
        let cvW2 = {weapon = Some({attack = 999 | wvSample()}) | cv};
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true, true),
            (World.combatViewKey({attack = 99 | cv})       != World.combatViewKey(cv),
             World.combatViewKey({magicAttack = 99 | cv})  != World.combatViewKey(cv),
             World.combatViewKey({defense = 99 | cv})      != World.combatViewKey(cv),
             World.combatViewKey({magicDefense = 99 | cv}) != World.combatViewKey(cv),
             World.combatViewKey({skill = 99 | cv})        != World.combatViewKey(cv),
             World.combatViewKey({speed = 99 | cv})        != World.combatViewKey(cv),
             World.combatViewKey({luck = 99 | cv})         != World.combatViewKey(cv),
             World.combatViewKey({hp = 99 | cv})           != World.combatViewKey(cv),
             World.combatViewKey({maxHp = 99 | cv})        != World.combatViewKey(cv),
             World.combatViewKey({hitMod = 99 | cv})       != World.combatViewKey(cv),
             World.combatViewKey(cvW1)                      != World.combatViewKey(cvW2)))

    /// ★MANDATORY (§5.3・§1.1): unitViewKey が 10 field を見る pin。pos（posKey）・weaponRange
    /// （weaponRangeKey の (min,max) ネスト）・combat（combatViewKey 内包）の sub-key 落ちまで検出する。
    @Test
    def testUnitViewKeyCoversAllFields(): Unit \ Assert =
        let uv = PlayerScene.unitView(playerData(0));
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true),
            (World.unitViewKey({id = 99 | uv})                             != World.unitViewKey(uv),
             World.unitViewKey({faction = Faction.Enemy | uv})             != World.unitViewKey(uv),
             World.unitViewKey({pos = {x = 99, y = 99} | uv})              != World.unitViewKey(uv),
             World.unitViewKey({hp = 99 | uv})                             != World.unitViewKey(uv),
             World.unitViewKey({moveTiles = 99 | uv})                      != World.unitViewKey(uv),
             World.unitViewKey({weaponRange = Some({min = 99, max = 99}) | uv}) != World.unitViewKey(uv),
             World.unitViewKey({combat = {attack = 999 | uv#combat} | uv}) != World.unitViewKey(uv),
             World.unitViewKey({isDying = true | uv})                      != World.unitViewKey(uv),
             World.unitViewKey({hidden = true | uv})                       != World.unitViewKey(uv),
             World.unitViewKey({aiType = EnemyAI.AiType.Wanderer | uv})    != World.unitViewKey(uv)))

    /// ★MANDATORY (§5.3・§1.3): playerDataKey 第1 group（13 field）を漏れなく見る pin。在庫4種の
    /// headKey・posKey・resourceStatKey の sub-key 落ち（S4.4 再発）まで検出する。
    @Test
    def testPlayerDataKeyCoversGroup1Fields(): Unit \ Assert =
        let d = playerData(0);
        let k = World.playerDataKey;
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true, true, true, true),
            (k({id = 99 | d})                              != k(d),
             k({classId = "other" | d})                    != k(d),
             k({gridPos = {x = 99, y = 99} | d})           != k(d),
             k({moveTiles = 99 | d})                       != k(d),
             k({hp = 99 | d})                              != k(d),
             k({waited = true | d})                        != k(d),
             k({attackTargetId = Some(7) | d})             != k(d),
             k({resource = TestUnitFixtures.testResource(99, 10) | d}) != k(d),
             k({weapons = Nil | d})                        != k(d),
             k({staves = d4Staff() :: Nil | d})            != k(d),
             k({consumables = d4Consumable() :: Nil | d})  != k(d),
             k({rings = d4Ring() :: Nil | d})              != k(d),
             k({ringEquipped = true | d})                  != k(d)))

    /// ★MANDATORY (§5.3・§1.3): playerDataKey 第2 group（10 field）を漏れなく見る pin。
    /// pendingLevelUpKey・statusListKey の内包まで検出する。
    @Test
    def testPlayerDataKeyCoversGroup2Fields(): Unit \ Assert =
        let d = playerData(0);
        let k = World.playerDataKey;
        let plu = ({unitName = "x", fromLevel = 1, toLevel = 2, changes = Nil}: LevelSystem.Result);
        let st  = ({effect = StatusSystem.StatusEffect.AtkUp, magnitude = 1, remaining = 1}: StatusSystem.Status);
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true, true),
            (k({selectedItem = Some(PlayerData.ItemKind.Weapon(0)) | d}) != k(d),
             k({moveStepsTaken = 99 | d})                  != k(d),
             k({facing = Staff.Direction.Up | d})          != k(d),
             k({hidden = true | d})                        != k(d),
             k({usedStairs = true | d})                    != k(d),
             k({level = 99 | d})                           != k(d),
             k({exp = 99 | d})                             != k(d),
             k({pendingLevelUp = Some(plu) | d})           != k(d),
             k({statuses = st :: Nil | d})                 != k(d),
             k({followUpUsed = true | d})                  != k(d)))

    // ── S4.4b: dataFromWorldEnemy（World 由来 EnemyData twin）/ enemyDataMismatches（全 17 field parity）──

    /// syncFromScene 直後は World 由来 dataFromWorldEnemy == scene EnemyScene.get Data ＝ enemyDataMismatches 空
    /// （全 17 field の parity 基準。W12 accessor + R残置3 + S→W未昇格1 の stitch が scene と bit 一致）。
    @Test
    def testEnemyDataMismatchesEmptyWhenSynced(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        Assert.assertEq(expected = true, List.isEmpty(World.enemyDataMismatches(world, scene)))

    /// 非 vacuous ガード: World 側だけ enemy5 hp を drift させると enemyDataMismatches が検出する
    /// （[ENEMYDATA DIFF] が鳴るべき状況を pin。射影に hp が含まれていることの実証も兼ねる）。
    @Test
    def testEnemyDataMismatchesDetectsDrift(): Unit \ Assert =
        let scene   = sampleScene();
        let world   = World.syncFromScene(scene, World.empty());
        let drifted = World.applyCmd(World.Cmd.SetHp(World.EntityRef.Enemy(5), 99), world);
        Assert.assertEq(expected = false, List.isEmpty(World.enemyDataMismatches(drifted, scene)))

    /// フィールド単位 pin: dataFromWorldEnemy(5) の代表 field（gridPos/hp/moveTiles/alerted/resourceId）が
    /// sampleScene fixture 値と一致し、かつ twin が Some（None 同士の vacuous でない）ことを併せて検証する。
    @Test
    def testDataFromWorldEnemyRepresentativeFields(): Unit \ Assert =
        let scene = sampleScene();
        let world = World.syncFromScene(scene, World.empty());
        let field = d -> ((d#gridPos#x, d#gridPos#y), d#hp, d#moveTiles, d#alerted, d#resourceId);
        let twin  = World.dataFromWorldEnemy(5, world, scene) |> Option.map(field);
        Assert.assertEq(
            expected = (Some(((3, 2), 10, 3, false, "test_enemy")), false),
            (twin, Option.isEmpty(twin)))

    /// ★MANDATORY (§5.3・§1.3): enemyDataKey 第1 group（9 field）を漏れなく見る pin。posKey の sub-key
    /// 落ちまで検出する。
    @Test
    def testEnemyDataKeyCoversGroup1Fields(): Unit \ Assert =
        let d = enemyData(5);
        let k = World.enemyDataKey;
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true, true, true),
            (k({id = 99 | d})                     != k(d),
             k({resourceId = "other" | d})        != k(d),
             k({gridPos = {x = 99, y = 99} | d})  != k(d),
             k({alerted = true | d})              != k(d),
             k({homeModuleIdx = 99 | d})          != k(d),
             k({moveTiles = 99 | d})              != k(d),
             k({hp = 99 | d})                     != k(d),
             k({isDying = true | d})              != k(d),
             k({attackTargetId = Some(7) | d})    != k(d)))

    /// ★MANDATORY (§5.3・§1.3): enemyDataKey 第2 group（8 field）を漏れなく見る pin。weaponKey/
    /// equippedRingKey/statusListKey/posKey の sub-key 落ちまで検出する。resource(R 残置)は resourceId
    /// 代表ゆえ group1 の resourceId pin が兼ねる（両辺 scene 由来＝drift 不能）。
    @Test
    def testEnemyDataKeyCoversGroup2Fields(): Unit \ Assert =
        let d = enemyData(5);
        let k = World.enemyDataKey;
        let st = ({effect = StatusSystem.StatusEffect.AtkUp, magnitude = 1, remaining = 1}: StatusSystem.Status);
        Assert.assertEq(
            expected = (true, true, true, true, true, true, true),
            (k({weapon = None | d})                       != k(d),
             k({acted = true | d})                        != k(d),
             k({prevPos = Some({x = 1, y = 1}) | d})      != k(d),
             k({statuses = st :: Nil | d})                != k(d),
             k({ring = Some(d4Ring()) | d})               != k(d),
             k({followUpUsed = true | d})                 != k(d),
             k({bottleUsed = true | d})                   != k(d)))
}
