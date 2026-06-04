// PlayerScene のテスト（multi-player 版）
//
// PlayerScene は moveTo(id, target, ...) で gridPos を即更新し、見た目の補間は engine の
// `Tween` モジュールに委ねる。壁判定は Board の責務なので PlayerScene 自身は考えない。
//
// 検証する観点:
//   - moveTo が gridPos を即更新する
//   - moveTo が Tween をスケジュールし、tickAll で target の world 座標に snap する
//   - tween 進行中は isMoving が true、snap 後は false
//
// テスト用 tileSize は 16。`PlayerScene.add` を介さず Marker2D を直接構築する。

mod TestPlayerScene {

    /// テスト用 tileSize
    def testTileSize(): Float64 = 16.0

    /// テスト用ワールド座標換算
    def testGridToWorld(coords: {x = Int32, y = Int32}): Vec2.Vec2 =
        let s = testTileSize();
        let v = Vec2i.toVec2(coords);
        {x = v#x * s + s / 2.0, y = v#y * s + s / 2.0}

    /// テスト用 MapSnapshot — 床のみ・13×13・grid↔world は testGridToWorld
    def testSnapshot(): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2i.zero(), size = ({x = 13, y = 13}: {x = Int32, y = Int32})},
            isWall       = _ -> false,
            isFloor      = _ -> true,
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = _ -> None
        }

    /// テスト用初期グリッド（PlayerScene.add の経由を回避）。
    def initialGrid(): {x = Int32, y = Int32} = {x = 5, y = 5}

    /// id=0 のプレイヤー 1 体だけのシーンを作る（JSON ロードを介さず Marker2D を直接構築）。
    /// PlayerScene.playerPath が World 配下を指すので、ここでも World Marker2D を挟む
    def emptyPlayerScene(): Scene[NodeTag] =
        let initial = initialGrid();
        let pos = testGridToWorld(initial);
        let marker = Marker2D.make(pos);
        let world = Marker2D.make(Vec2.zero())
            |> CanvasItem.setYSortEnabled(true);
        Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0),
                EngineNode.Marker2DWithState(marker,
                    NodeTag.Player({
                        id                = 0,
                        gridPos           = initial,
                        moveTiles         = 5,
                        hp                = 10,
                        waited            = false,
                        attackTargetId    = None,
                        resource          = TestUnitFixtures.testResource(5, 10),
                        weapons           = TestUnitFixtures.testWeapon() :: Nil,
                        staves            = Nil,
                        selectedItem      = None,
                        moveStepsTaken    = 0,
                        facing            = Staff.Direction.Down,
                        hidden            = false,
                        usedStairs            = false,
                        level                     = 1,
                        exp                       = 0,
                        pendingLevelUp            = None
                    })))

    /// プレイヤー id のワールド座標を取り出す
    def playerWorldPos(id: Int32, scene: Scene[NodeTag]): Vec2.Vec2 =
        Scene.globalPositionAt(PlayerScene.playerPath(id), scene)

    /// scene 内 Player(id) の (marker, data) を moveTo に渡し、戻り値で scene を更新する。
    def applyMove(id: Int32, map: MapSnapshot, target: {x = Int32, y = Int32},
                   scene: Scene[NodeTag]): Scene[NodeTag] \ Tween.Scheduler =
        match Scene.getEngineNode(PlayerScene.playerPath(id), scene) {
            case Some(EngineNode.Marker2DWithState(marker, NodeTag.Player(data))) =>
                let (newMarker, newData) =
                    PlayerScene.moveTo(id, map, target, marker, data, scene);
                Scene.setEngineNode(PlayerScene.playerPath(id),
                    EngineNode.Marker2DWithState(newMarker, NodeTag.Player(newData)),
                    scene)
            case _ => bug!("applyMove: expected Player at playerPath(${id})")
        }

    // ========================================================================
    // moveTo — gridPos を即更新、tween は engine に委譲
    // ========================================================================

    /// moveTo 直後: gridPos は target に更新される。world 座標は tween がまだ進んでいないので
    /// 元の位置のまま（noop tween で確認）
    @Test
    def testMoveToUpdatesGridPosImmediately(): Unit \ Assert =
        let target: {x = Int32, y = Int32} = {x = 6, y = 5};
        let initialPos = testGridToWorld(initialGrid());
        let after = TestUnitFixtures.withNoopTween(() ->
            applyMove(0, testSnapshot(), target, emptyPlayerScene()));
        let pos = playerWorldPos(0, after);
        let gridX = PlayerScene.getGridPos(0, after)#x;
        let gridY = PlayerScene.getGridPos(0, after)#y;
        Assert.assertEq(
            expected = (6, 5, initialPos#x, initialPos#y),
            (gridX, gridY, pos#x, pos#y))

    /// moveTo 後の流れを実 Tween で end-to-end 検証する。
    ///   moveTo 直後:        world は initial のまま、isMoving(0) = true
    ///   tickAll(1.0) 後:    world は target に snap、isMoving(0) = false
    @Test
    def testMoveToSchedulesTweenAndSnaps(): Unit \ Assert =
        region rc {
            let target: {x = Int32, y = Int32} = {x = 6, y = 5};
            let initialWorld = testGridToWorld(initialGrid());
            let targetWorld = testGridToWorld(target);
            let result = run {
                let scene1 = applyMove(0, testSnapshot(), target, emptyPlayerScene());
                let posBefore = playerWorldPos(0, scene1);
                let activeBefore = PlayerScene.isMoving(0);
                let scene2 = Tween.tickAll(1.0 |> Duration.seconds, scene1);
                let posAfter = playerWorldPos(0, scene2);
                let activeAfter = PlayerScene.isMoving(0);
                (posBefore#x, posBefore#y, activeBefore,
                 posAfter#x, posAfter#y, activeAfter)
            } with Tween.withScheduler(rc);
            Assert.assertEq(
                expected = (initialWorld#x, initialWorld#y, true,
                             targetWorld#x, targetWorld#y, false),
                result)
        }

    // ========================================================================
    // adjacentAllies — 上下左右 1 マスの他味方だけを返す
    // ========================================================================

    /// 配置 (self = id 0 at (5,5)):
    ///
    ///         (5,4) id=1
    ///   (4,5)        (6,5)
    ///    id=2 (5,5)   id=3
    ///                (self)
    ///         (5,6) id=4
    ///
    ///   (4,4) id=5            (6,6) id=6   ← 斜めなので非隣接
    ///
    /// 期待: 上下左右の id (1,2,3,4) だけが返り、斜め (5,6) と self (0) は除外される。
    /// getAll は id 昇順なので結果も id 昇順で並ぶ前提でリスト比較する。
    @Test
    def testAdjacentAlliesReturnsOnlyOrthogonalNeighbors(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil}: PlayerScene.Spawn);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer(mkSpawn(0, {x = 5, y = 5}))
            |> PlayerScene.addOnePlayer(mkSpawn(1, {x = 5, y = 4}))
            |> PlayerScene.addOnePlayer(mkSpawn(2, {x = 4, y = 5}))
            |> PlayerScene.addOnePlayer(mkSpawn(3, {x = 6, y = 5}))
            |> PlayerScene.addOnePlayer(mkSpawn(4, {x = 5, y = 6}))
            |> PlayerScene.addOnePlayer(mkSpawn(5, {x = 4, y = 4}))
            |> PlayerScene.addOnePlayer(mkSpawn(6, {x = 6, y = 6}));
        let self = match PlayerScene.get(0, scene) {
            case Some(d) => d
            case None    => bug!("player 0 not found")
        };
        let neighbors = TestUnitFixtures.withMockPartyQuery(scene, () ->
            PlayerScene.adjacentAllies(self));
        Assert.assertEq(
            expected = 1 :: 2 :: 3 :: 4 :: Nil,
            List.map(d -> d#id, neighbors))

    /// 隣接味方が居ない場合は空リストを返す。
    /// 斜めに居る駒は隣接ではない (上のテストと同じ判定だが、空の経路を独立 pin)。
    @Test
    def testAdjacentAlliesReturnsEmptyWhenNoOrthogonalNeighbor(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil}: PlayerScene.Spawn);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer(mkSpawn(0, {x = 5, y = 5}))
            |> PlayerScene.addOnePlayer(mkSpawn(1, {x = 4, y = 4}))
            |> PlayerScene.addOnePlayer(mkSpawn(2, {x = 6, y = 6}));
        let self = match PlayerScene.get(0, scene) {
            case Some(d) => d
            case None    => bug!("player 0 not found")
        };
        let neighbors = TestUnitFixtures.withMockPartyQuery(scene, () ->
            PlayerScene.adjacentAllies(self));
        Assert.assertEq(expected = Nil, List.map(d -> d#id, neighbors))

    // ========================================================================
    // swapItem — 2 プレイヤー間でアイテムを交換する
    //
    // 本体経路を使う:
    //   - `UnitCatalog.load` で本番 resources の catalog を読む
    //   - `UnitCatalog.lookupWeapon(id, catalog)` / `Staff.lookup(id, staffCatalog)`
    //     で本物の resource を取得
    //   - `MapScene.addWorldNode` + `PlayerScene.addOnePlayer(spawn, scene)` で scene 構築
    //   - `PlayerScene.swapItem(args, scene)` を record-style 引数で呼ぶ
    //   - インベントリ確認は `PlayerScene.getWeapons` / `getStaves` の戻り値を直接 map
    //
    // 武器: trainingSpear (くんれんやり) / trainingBow (くんれんゆみ) / fire_magic (ファイアー)
    // 杖:   live_staff (かいふくのつえ) / swap_staff (いれかえのつえ)
    // ========================================================================

    /// 共通: 本番の catalog をロードして「最初の player unit」を返す。
    /// 本体 `UnitCatalog.load` + `UnitCatalog.pool("players", _)` の薄い呼び出しなので
    /// テスト固有ロジックは含まない (= helper として最小)。
    def loadTestCatalogs(): {catalog = UnitCatalog.UnitCatalog,
                              staffCatalog = Staff.StaffCatalog,
                              unitSample = UnitCatalog.UnitResource} \ Fs.FileRead =
        let weaponCatalog = WeaponCatalog.load();
        let catalog = UnitCatalog.load("resources/units.json", weaponCatalog);
        let staffCatalog = Staff.load();
        let unitSample = match List.head(UnitCatalog.pool("players", catalog)) {
            case Some(r) => r
            case None    => bug!("no players in catalog")
        };
        {catalog = catalog, staffCatalog = staffCatalog, unitSample = unitSample}

    /// P0 weapons=[槍, ファイアー] / P1 weapons=[弓]
    /// P0 の Weapon(0)=槍 と P1 の Weapon(0)=弓 を交換。
    /// 期待:
    ///   P0: weapons=[ファイアー, 弓]   (槍が抜けて末尾に 弓 追加)
    ///   P1: weapons=[槍]              (弓が抜けて末尾に 槍 追加)
    @Test
    def testSwapItemWeaponToWeaponExchangesBothInventories(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("trainingSpear", fx#catalog);
        let bow   = UnitCatalog.lookupWeapon("trainingBow",   fx#catalog);
        let fire  = UnitCatalog.lookupWeapon("fire_magic",    fx#catalog);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer({id = 0, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = spear :: fire :: Nil, staves = Nil})
            |> PlayerScene.addOnePlayer({id = 1, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = bow :: Nil, staves = Nil});
        let after = PlayerScene.swapItem({
            selfId      = 0,
            selfKind    = PlayerScene.ItemKind.Weapon(0),
            partnerId   = 1,
            partnerKind = Some(PlayerScene.ItemKind.Weapon(0))
        }, scene);
        Assert.assertEq(
            expected = ("ファイアー" :: "くんれんゆみ" :: Nil, "くんれんやり" :: Nil),
            (PlayerScene.getWeapons(0, after) |> List.map(w -> w#name),
             PlayerScene.getWeapons(1, after) |> List.map(w -> w#name)))

    /// P0 staves=[回復] / P1 staves=[入替]
    /// P0 の Staff(0)=回復 と P1 の Staff(0)=入替 を交換 (杖同士)。
    /// 期待: P0 staves=[入替] / P1 staves=[回復]
    @Test
    def testSwapItemStaffToStaffExchangesBothInventories(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let live = Staff.lookup("live_staff", fx#staffCatalog);
        let swap = Staff.lookup("swap_staff", fx#staffCatalog);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer({id = 0, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = Nil, staves = live :: Nil})
            |> PlayerScene.addOnePlayer({id = 1, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = Nil, staves = swap :: Nil});
        let after = PlayerScene.swapItem({
            selfId      = 0,
            selfKind    = PlayerScene.ItemKind.Staff(0),
            partnerId   = 1,
            partnerKind = Some(PlayerScene.ItemKind.Staff(0))
        }, scene);
        Assert.assertEq(
            expected = ("いれかえのつえ" :: Nil, "かいふくのつえ" :: Nil),
            (PlayerScene.getStaves(0, after) |> List.map(s -> s#name),
             PlayerScene.getStaves(1, after) |> List.map(s -> s#name)))

    /// P0 weapons=[槍], staves=[] / P1 weapons=[], staves=[回復]
    /// P0 の Weapon(0)=槍 と P1 の Staff(0)=回復 を交換 (種別跨ぎ)。
    /// 期待:
    ///   P0: weapons=[], staves=[回復]   (受け取った杖は staves 側に入る)
    ///   P1: weapons=[槍], staves=[]     (受け取った武器は weapons 側に入る)
    @Test
    def testSwapItemWeaponToStaffCrossesInventoryLists(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("trainingSpear", fx#catalog);
        let live  = Staff.lookup("live_staff", fx#staffCatalog);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer({id = 0, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = spear :: Nil, staves = Nil})
            |> PlayerScene.addOnePlayer({id = 1, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = Nil, staves = live :: Nil});
        let after = PlayerScene.swapItem({
            selfId      = 0,
            selfKind    = PlayerScene.ItemKind.Weapon(0),
            partnerId   = 1,
            partnerKind = Some(PlayerScene.ItemKind.Staff(0))
        }, scene);
        Assert.assertEq(
            expected = ((Nil, "かいふくのつえ" :: Nil), ("くんれんやり" :: Nil, Nil)),
            ((PlayerScene.getWeapons(0, after) |> List.map(w -> w#name),
              PlayerScene.getStaves(0,  after) |> List.map(s -> s#name)),
             (PlayerScene.getWeapons(1, after) |> List.map(w -> w#name),
              PlayerScene.getStaves(1,  after) |> List.map(s -> s#name))))

    /// P0 weapons=[槍] / P1 weapons=[]
    /// P0 の Weapon(0)=槍 を P1 の空スロット (partnerKind = None) に渡す。
    /// 期待:
    ///   P0: weapons=[]      (槍 が消える、自分のスロットは空になる)
    ///   P1: weapons=[槍]    (槍 を受け取る)
    @Test
    def testSwapItemTransfersToEmptySlot(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("trainingSpear", fx#catalog);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer({id = 0, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = spear :: Nil, staves = Nil})
            |> PlayerScene.addOnePlayer({id = 1, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = Nil, staves = Nil});
        let after = PlayerScene.swapItem({
            selfId      = 0,
            selfKind    = PlayerScene.ItemKind.Weapon(0),
            partnerId   = 1,
            partnerKind = None
        }, scene);
        Assert.assertEq(
            expected = (Nil, "くんれんやり" :: Nil),
            (PlayerScene.getWeapons(0, after) |> List.map(w -> w#name),
             PlayerScene.getWeapons(1, after) |> List.map(w -> w#name)))

    /// TradeMenu 「空スロット picker」シナリオ相当: 自分が空スロット pick、相手の実体を選択
    /// → TradeMenuScene.applyTradeSwap が引数を反転して `swapItem({selfId=partner, ...})`
    /// を呼ぶ経路の確認 (P1 が giver、P0 が receiver)。
    /// 配置: P0 weapons=[] / P1 weapons=[槍]
    /// 期待:
    ///   P0: weapons=[槍]    (相手から槍を受け取る)
    ///   P1: weapons=[]      (槍を渡して空になる)
    @Test
    def testSwapItemPartnerAsGiverTransfersToSelf(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("trainingSpear", fx#catalog);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer({id = 0, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = Nil, staves = Nil})
            |> PlayerScene.addOnePlayer({id = 1, gridPos = {x = 0, y = 0},
                                          resource = fx#unitSample,
                                          weapons = spear :: Nil, staves = Nil});
        let after = PlayerScene.swapItem({
            selfId      = 1,
            selfKind    = PlayerScene.ItemKind.Weapon(0),
            partnerId   = 0,
            partnerKind = None
        }, scene);
        Assert.assertEq(
            expected = ("くんれんやり" :: Nil, Nil),
            (PlayerScene.getWeapons(0, after) |> List.map(w -> w#name),
             PlayerScene.getWeapons(1, after) |> List.map(w -> w#name)))

    // ========================================================================
    // ローグ移動モード — nearestMover(合流順) / pickRespawnCells(解散の再配置)
    // ========================================================================

    /// セル列を assertEq 用の (x, y) タプル列にする。
    def cellsToTuples(cells: List[{x = Int32, y = Int32}]): List[(Int32, Int32)] =
        List.map(c -> (c#x, c#y), cells)

    /// nearestMover テスト用の最小 Data（位置以外はダミー）。
    def pdata(id: Int32, gridPos: {x = Int32, y = Int32}): PlayerScene.Data = {
        id              = id,
        gridPos         = gridPos,
        moveTiles       = 5,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(5, 10),
        weapons         = Nil,
        staves          = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0,
        facing          = Staff.Direction.Down,
        hidden          = false,
        usedStairs          = false,
        level                   = 1,
        exp                     = 0,
        pendingLevelUp          = None
    }

    /// origin 1 マスだけが床で、ほかは壁の MapSnapshot（再配置の不足ケース用）。
    def singleFloorSnapshot(origin: {x = Int32, y = Int32}): MapSnapshot =
        {
            tileSize     = testTileSize(),
            usedRect     = {position = Vec2i.zero(), size = ({x = 13, y = 13}: {x = Int32, y = Int32})},
            isWall       = c -> not (c#x == origin#x and c#y == origin#y),
            isFloor      = c -> c#x == origin#x and c#y == origin#y,
            mapToLocal   = c -> testGridToWorld(c),
            gridToWorld  = c -> testGridToWorld(c),
            moduleOfCell = _ -> None
        }

    /// 合流で次に動かす 1 体は、ロードに最も近い味方。
    /// ロード (5,5)、味方 id1 (8,5) は距離 3、id2 (6,5) は距離 1 → id2 が選ばれる。
    @Test
    def testNearestMoverPicksClosest(): Unit \ Assert =
        let lordPos: {x = Int32, y = Int32} = {x = 5, y = 5};
        let movers = pdata(1, {x = 8, y = 5}) :: pdata(2, {x = 6, y = 5}) :: Nil;
        match PlayerScene.nearestMover(lordPos, movers) {
            case Some(d) => Assert.assertEq(expected = 2, d#id)
            case None    => bug!("nearestMover: expected a mover")
        }

    /// 再配置: ロード周囲が全部空いていれば、近傍を順に n マス選ぶ（origin は含めない）。
    /// origin (5,5)、n=2 → 上下左右の先頭 2 マス [(6,5), (4,5)]。
    @Test
    def testPickRespawnCellsPicksNeighbors(): Unit \ Assert =
        let origin: {x = Int32, y = Int32} = {x = 5, y = 5};
        let board: Board = {map = testSnapshot(), pieces = (Piece.Player(0), origin) :: Nil};
        let cells = PlayerScene.pickRespawnCells(origin, 2, board);
        Assert.assertEq(expected = (6, 5) :: (4, 5) :: Nil, cellsToTuples(cells))

    /// 再配置: 駒が占有しているマスは避ける。
    /// (6,5) に敵が居ると、その次の候補 (4,5), (5,6) が選ばれる。
    @Test
    def testPickRespawnCellsAvoidsOccupied(): Unit \ Assert =
        let origin: {x = Int32, y = Int32} = {x = 5, y = 5};
        let board: Board = {
            map    = testSnapshot(),
            pieces = (Piece.Player(0), origin) :: (Piece.Enemy(0), {x = 6, y = 5}) :: Nil
        };
        let cells = PlayerScene.pickRespawnCells(origin, 2, board);
        Assert.assertEq(expected = (4, 5) :: (5, 6) :: Nil, cellsToTuples(cells))

    /// 再配置: 周囲が壁で空きが足りないときは origin で埋めて長さ n を保つ。
    /// origin だけ床 → 近傍ゼロ → [(5,5), (5,5)]（重なっても次の移動で解ける）。
    @Test
    def testPickRespawnCellsFallsBackToOrigin(): Unit \ Assert =
        let origin: {x = Int32, y = Int32} = {x = 5, y = 5};
        let board: Board = {map = singleFloorSnapshot(origin), pieces = (Piece.Player(0), origin) :: Nil};
        let cells = PlayerScene.pickRespawnCells(origin, 2, board);
        Assert.assertEq(expected = (5, 5) :: (5, 5) :: Nil, cellsToTuples(cells))

    // ========================================================================
    // フロア進行 — 階段退場 (useStairs) / フロア終了判定 / 持ち越し (reconcileWithCarry)
    // ========================================================================

    /// 階段を使った味方は「退場」する: usedStairs / hidden / waited が同時に立つ。
    /// hidden で盤面・カーソルから外れ、waited で行動済み扱いになって動けなくなる。
    @Test
    def testUseStairsExitsUnitFromFloor(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil}: PlayerScene.Spawn);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer(mkSpawn(0, {x = 3, y = 3}));
        let after = PlayerScene.useStairs(0, scene);
        match PlayerScene.get(0, after) {
            case Some(d) =>
                Assert.assertEq(expected = (true, true, true),
                                (d#usedStairs, d#hidden, d#waited))
            case None    => bug!("player 0 not found")
        }

    /// フロア終了は「生存味方が全員」階段を使ったときだけ true。
    /// 味方 2 人のうち 1 人だけ使った段階では false、2 人とも使うと true。
    @Test
    def testAllLivingUsedStairsRequiresEveryone(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let mkSpawn = (id, pos) -> ({id = id, gridPos = pos, resource = fx#unitSample,
                                       weapons = Nil, staves = Nil}: PlayerScene.Spawn);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer(mkSpawn(0, {x = 3, y = 3}))
            |> PlayerScene.addOnePlayer(mkSpawn(1, {x = 4, y = 3}));
        let oneUsed  = PlayerScene.useStairs(0, scene);
        let bothUsed = PlayerScene.useStairs(1, oneUsed);
        Assert.assertEq(
            expected = (false, true),
            (PlayerScene.allLivingUsedStairs(oneUsed),
             PlayerScene.allLivingUsedStairs(bothUsed)))

    /// 次フロアの持ち越し: carry に居る味方は HP / 武器を引き継ぎ、carry に居ない id
    /// （前フロアで戦死）はノードごと除去される。
    /// 配置: 味方 0/1/2 をフル HP で生成 → carry = {0: HP3 + 槍, 1: HP7} のみ。
    /// 期待: 残るのは 0,1 のみ。HP は 3 / 7。0 の武器は くんれんやり。
    @Test
    def testReconcileWithCarryPersistsHpAndDropsDead(): Unit \ {Assert, Fs.FileRead} =
        let fx = loadTestCatalogs();
        let spear = UnitCatalog.lookupWeapon("trainingSpear", fx#catalog);
        let mkSpawn = id -> ({id = id, gridPos = {x = 0, y = 0}, resource = fx#unitSample,
                               weapons = Nil, staves = Nil}: PlayerScene.Spawn);
        let scene = Scene.empty()
            |> MapScene.addWorldNode
            |> PlayerScene.addOnePlayer(mkSpawn(0))
            |> PlayerScene.addOnePlayer(mkSpawn(1))
            |> PlayerScene.addOnePlayer(mkSpawn(2));
        let baseStats = LevelSystem.statsOf(fx#unitSample);
        let carry =
            ({id = 0, hp = 3, weapons = spear :: Nil, staves = Nil,
              level = 1, exp = 0, stats = baseStats}: PlayerScene.CarryData) ::
            ({id = 1, hp = 7, weapons = Nil,          staves = Nil,
              level = 1, exp = 0, stats = baseStats}: PlayerScene.CarryData) :: Nil;
        let after = PlayerScene.reconcileWithCarry(carry, scene);
        Assert.assertEq(
            expected = (0 :: 1 :: Nil, 3, 7, "くんれんやり" :: Nil),
            (PlayerScene.getAll(after) |> List.map(d -> d#id),
             PlayerScene.getHp(0, after),
             PlayerScene.getHp(1, after),
             PlayerScene.getWeapons(0, after) |> List.map(weapon -> weapon#name)))

    // ========================================================================
    // しゅうごう可否: 全員がロード周囲 range マス以内か（チェビシェフ距離）
    // ========================================================================

    /// center (5,5) を中心に、斜めに 3 マス (8,8)=距離3 は範囲内、横に 4 マス (9,5)=距離4 は範囲外。
    /// チェビシェフ距離なので斜めも 1 軸の差で測る（(8,8) は max(3,3)=3）。
    @Test
    def testAllWithinRangeChebyshevBoundary(): Unit \ Assert =
        let center: {x = Int32, y = Int32} = {x = 5, y = 5};
        let inside  = ({x = 8, y = 8}: {x = Int32, y = Int32}) :: {x = 2, y = 5} :: Nil;  // 距離 3 と 3
        let outside = ({x = 9, y = 5}: {x = Int32, y = Int32}) :: Nil;                     // 距離 4
        Assert.assertEq(
            expected = (true, false),
            (PlayerScene.allWithinRange(3, center, inside),
             PlayerScene.allWithinRange(3, center, outside)))

    /// 1 人でも範囲外なら false（全員が条件を満たす必要がある）。空リストは true。
    @Test
    def testAllWithinRangeRequiresEveryone(): Unit \ Assert =
        let center: {x = Int32, y = Int32} = {x = 0, y = 0};
        let mixed = ({x = 1, y = 1}: {x = Int32, y = Int32}) :: {x = 0, y = 5} :: Nil;  // 距離 1 と 5
        Assert.assertEq(
            expected = (false, true),
            (PlayerScene.allWithinRange(3, center, mixed),
             PlayerScene.allWithinRange(3, center, Nil)))
}
