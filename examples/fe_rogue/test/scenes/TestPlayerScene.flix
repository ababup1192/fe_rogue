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
                        moveStepsTaken    = 0
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

    /// id と gridPos だけを変えた最小限のテスト用 PlayerScene.Data。
    /// 他のフィールドは中庸な値で固定し、隣接判定の挙動に影響しないようにする。
    def buildPartyMember(id: Int32, gridPos: {x = Int32, y = Int32}):
            PlayerScene.Data = {
        id              = id,
        gridPos         = gridPos,
        moveTiles       = 5,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(5, 10),
        weapons         = TestUnitFixtures.testWeapon() :: Nil,
        staves          = Nil,
        selectedItem    = None,
        moveStepsTaken  = 0
    }

    /// 与えた party から「World ノード + 各味方 Marker2D」の scene を組む。
    /// PartyQuery 経由で getAll を呼ぶと、scene 内の Player ノードが id 昇順で返る。
    def sceneWithParty(party: List[PlayerScene.Data]): Scene[NodeTag] =
        let world = Marker2D.make(Vec2.zero());
        let withWorld = Scene.empty()
            |> Scene.addNode(MapScene.worldName(),
                EngineNode.Marker2DWithState(world, NodeTag.NoTag));
        List.foldLeft((acc, data) -> {
            let marker = Marker2D.make(Vec2.zero());
            Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(data#id),
                EngineNode.Marker2DWithState(marker, NodeTag.Player(data)), acc)
        }, withWorld, party)

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
    def testAdjacentAlliesReturnsOnlyOrthogonalNeighbors(): Unit \ Assert =
        let self     = buildPartyMember(0, {x = 5, y = 5});
        let northern = buildPartyMember(1, {x = 5, y = 4});
        let western  = buildPartyMember(2, {x = 4, y = 5});
        let eastern  = buildPartyMember(3, {x = 6, y = 5});
        let southern = buildPartyMember(4, {x = 5, y = 6});
        let diagNW   = buildPartyMember(5, {x = 4, y = 4});
        let diagSE   = buildPartyMember(6, {x = 6, y = 6});
        let scene = sceneWithParty(self :: northern :: western :: eastern ::
                                    southern :: diagNW :: diagSE :: Nil);
        let neighbors = TestUnitFixtures.withMockPartyQuery(scene, () ->
            PlayerScene.adjacentAllies(self));
        let neighborIds = List.map(d -> d#id, neighbors);
        Assert.assertEq(
            expected = 1 :: 2 :: 3 :: 4 :: Nil,
            neighborIds)

    /// 隣接味方が居ない場合は空リストを返す。
    /// 斜めに居る駒は隣接ではない (上のテストと同じ判定だが、空の経路を独立 pin)。
    @Test
    def testAdjacentAlliesReturnsEmptyWhenNoOrthogonalNeighbor(): Unit \ Assert =
        let self   = buildPartyMember(0, {x = 5, y = 5});
        let diagNW = buildPartyMember(1, {x = 4, y = 4});
        let diagSE = buildPartyMember(2, {x = 6, y = 6});
        let scene = sceneWithParty(self :: diagNW :: diagSE :: Nil);
        let neighbors = TestUnitFixtures.withMockPartyQuery(scene, () ->
            PlayerScene.adjacentAllies(self));
        Assert.assertEq(expected = Nil, List.map(d -> d#id, neighbors))

    // ========================================================================
    // swapItem — 2 プレイヤー間でアイテムを交換する
    // ========================================================================

    /// テスト用名前付き武器。`name` で交換結果が区別できるよう作る。
    def namedWeapon(weaponName: String): UnitCatalog.WeaponResource = {
        name       = weaponName,
        attack     = 2,
        durability = 10,
        range      = { min = 1, max = 1 },
        weaponType = UnitCatalog.WeaponType.Physical,
        sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                       offset = {x = 0.0, y = 0.0}}: UnitCatalog.SpriteResource)
    }

    /// テスト用名前付き杖 (耐久 3, Heal 効果)。
    def namedStaff(staffName: String): Staff.StaffResource = {
        name       = staffName,
        effect     = Staff.StaffEffect.Heal,
        durability = 3,
        sprite     = ({texture = "t", hframes = 1, vframes = 1, frame = 0,
                       offset = {x = 0.0, y = 0.0}}: UnitCatalog.SpriteResource)
    }

    /// id / weapons / staves だけ意味を持つ PlayerScene.Data を組む。
    /// gridPos などは固定値 (swap は位置を見ない)。
    def memberWithItems(id: Int32,
                         weapons: List[UnitCatalog.WeaponResource],
                         staves: List[Staff.StaffResource]): PlayerScene.Data = {
        id              = id,
        gridPos         = {x = 0, y = 0},
        moveTiles       = 5,
        hp              = 10,
        waited          = false,
        attackTargetId  = None,
        resource        = TestUnitFixtures.testResource(5, 10),
        weapons         = weapons,
        staves          = staves,
        selectedItem    = None,
        moveStepsTaken  = 0
    }

    /// インベントリ確認用に各プレイヤーの武器名 / 杖名のリストを取り出す。
    /// 順序保存で比較するので、テストは「期待する順序」も含めて pin できる。
    def inventoryNamesOf(id: Int32, scene: Scene[NodeTag]):
            (List[String], List[String]) =
        let weaponNames = PlayerScene.getWeapons(id, scene)
                            |> List.map(w -> w#name);
        let staffNames  = PlayerScene.getStaves(id, scene)
                            |> List.map(s -> s#name);
        (weaponNames, staffNames)

    /// 配置: P0 weapons=[A, B] / P1 weapons=[C]
    /// P0 の Weapon(0)=A と P1 の Weapon(0)=C を交換。
    /// 期待:
    ///   P0: weapons=[B, C] (A 抜けて末尾に C 追加 → リスト順は [B, C])
    ///   P1: weapons=[A]    (C 抜けて末尾に A 追加)
    @Test
    def testSwapItemWeaponToWeaponExchangesBothInventories(): Unit \ Assert =
        let p0 = memberWithItems(0, namedWeapon("A") :: namedWeapon("B") :: Nil, Nil);
        let p1 = memberWithItems(1, namedWeapon("C") :: Nil, Nil);
        let scene = sceneWithParty(p0 :: p1 :: Nil);
        let after = PlayerScene.swapItem(0, PlayerScene.ItemKind.Weapon(0),
                                          1, Some(PlayerScene.ItemKind.Weapon(0)),
                                          scene);
        Assert.assertEq(
            expected = (("B" :: "C" :: Nil, Nil), ("A" :: Nil, Nil)),
            (inventoryNamesOf(0, after), inventoryNamesOf(1, after)))

    /// 配置: P0 staves=[X] / P1 staves=[Y]
    /// P0 の Staff(0)=X と P1 の Staff(0)=Y を交換 (杖同士)。
    /// 期待: P0 staves=[Y] / P1 staves=[X]
    @Test
    def testSwapItemStaffToStaffExchangesBothInventories(): Unit \ Assert =
        let p0 = memberWithItems(0, Nil, namedStaff("X") :: Nil);
        let p1 = memberWithItems(1, Nil, namedStaff("Y") :: Nil);
        let scene = sceneWithParty(p0 :: p1 :: Nil);
        let after = PlayerScene.swapItem(0, PlayerScene.ItemKind.Staff(0),
                                          1, Some(PlayerScene.ItemKind.Staff(0)),
                                          scene);
        Assert.assertEq(
            expected = ((Nil, "Y" :: Nil), (Nil, "X" :: Nil)),
            (inventoryNamesOf(0, after), inventoryNamesOf(1, after)))

    /// 配置: P0 weapons=[A], staves=[] / P1 weapons=[], staves=[X]
    /// P0 の Weapon(0)=A と P1 の Staff(0)=X を交換 (種別跨ぎ)。
    /// 期待:
    ///   P0: weapons=[], staves=[X]   (受け取った杖は staves 側に入る)
    ///   P1: weapons=[A], staves=[]   (受け取った武器は weapons 側に入る)
    @Test
    def testSwapItemWeaponToStaffCrossesInventoryLists(): Unit \ Assert =
        let p0 = memberWithItems(0, namedWeapon("A") :: Nil, Nil);
        let p1 = memberWithItems(1, Nil, namedStaff("X") :: Nil);
        let scene = sceneWithParty(p0 :: p1 :: Nil);
        let after = PlayerScene.swapItem(0, PlayerScene.ItemKind.Weapon(0),
                                          1, Some(PlayerScene.ItemKind.Staff(0)),
                                          scene);
        Assert.assertEq(
            expected = ((Nil, "X" :: Nil), ("A" :: Nil, Nil)),
            (inventoryNamesOf(0, after), inventoryNamesOf(1, after)))

    /// 配置: P0 weapons=[A] / P1 weapons=[]
    /// P0 の Weapon(0)=A を P1 の空スロット (partnerKind = None) に渡す。
    /// 期待:
    ///   P0: weapons=[]     (A が消える、自分のスロットは空になる)
    ///   P1: weapons=[A]    (A を受け取る)
    @Test
    def testSwapItemTransfersToEmptySlot(): Unit \ Assert =
        let p0 = memberWithItems(0, namedWeapon("A") :: Nil, Nil);
        let p1 = memberWithItems(1, Nil, Nil);
        let scene = sceneWithParty(p0 :: p1 :: Nil);
        let after = PlayerScene.swapItem(0, PlayerScene.ItemKind.Weapon(0),
                                          1, None, scene);
        Assert.assertEq(
            expected = ((Nil, Nil), ("A" :: Nil, Nil)),
            (inventoryNamesOf(0, after), inventoryNamesOf(1, after)))
}
