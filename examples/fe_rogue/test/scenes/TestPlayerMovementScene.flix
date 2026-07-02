/// PlayerMovementScene.stepPlayerMove（移動 System）の sim 判定を純粋に検証する。
///
/// F3b: 移動は input(view)→System(sim)→SimEvent→replay(view) の seam に分離された。
/// この System 部分を単体で固定する:
///   - 合法な 1 歩 → `Some(Moved(target))` を返し World に `Cmd.Move` を emit する。
///   - 敵駒で占有された先 → `None`・emit なし（位置は書かない）。
///   - MoveRange 述語が false → `None`・emit なし。
/// 位置の権威は World（`Cmd.Move`）にあり、System は scene を一切触らない。
mod TestPlayerMovementScene {

    /// 10×5・壁なしの素の盤面（壁が無いので usedRect 内は全セル床）。
    def tenByFive(): MapSnapshot =
        {tileSize = 26.0, usedRect = {position = {x = 0, y = 0}, size = {x = 10, y = 5}},
         wallCells = (Set#{}: Set[(Int32, Int32)]), mapGlobal = {x = 0.0, y = 0.0},
         placements = RoomLayout.twoRoom(10, 5)}

    /// 合法な 1 歩（右）: target (5,2) を返し、同じ target へ Cmd.Move を 1 回 emit する。
    @Test
    def testStepPlayerMoveLegalEmitsAndReturnsMoved(): Unit \ Assert =
        let board: Board = {map = tenByFive(), pieces = (Piece.Player(0), {x = 4, y = 2}) :: Nil};
        let (evOpt, moves) = TestUnitFixtures.withRecordedMoves(() ->
            PlayerMovementScene.stepPlayerMove(0, {x = 4, y = 2}, Vec2i.right(), board, _ -> true));
        let target  = evOpt |> Option.map(PlayerScene.movedTarget) |> Option.map(t -> (t#x, t#y));
        let emitted = moves |> List.map(t -> (t#x, t#y));
        Assert.assertEq(expected = (Some((5, 2)), (5, 2) :: Nil), (target, emitted))

    /// 進行先が敵駒に占有されている: None を返し emit しない（位置を書かない）。
    @Test
    def testStepPlayerMoveBlockedByEnemyReturnsNoneNoEmit(): Unit \ Assert =
        let board: Board = {map = tenByFive(),
            pieces = (Piece.Player(0), {x = 4, y = 2}) :: (Piece.Enemy(0), {x = 5, y = 2}) :: Nil};
        let (evOpt, moves) = TestUnitFixtures.withRecordedMoves(() ->
            PlayerMovementScene.stepPlayerMove(0, {x = 4, y = 2}, Vec2i.right(), board, _ -> true));
        let target = evOpt |> Option.map(PlayerScene.movedTarget) |> Option.map(t -> (t#x, t#y));
        Assert.assertEq(expected = (None, 0), (target, List.length(moves)))

    /// MoveRange 述語が false（範囲外）: None を返し emit しない。
    @Test
    def testStepPlayerMoveBlockedByRangePredReturnsNoneNoEmit(): Unit \ Assert =
        let board: Board = {map = tenByFive(), pieces = (Piece.Player(0), {x = 4, y = 2}) :: Nil};
        let (evOpt, moves) = TestUnitFixtures.withRecordedMoves(() ->
            PlayerMovementScene.stepPlayerMove(0, {x = 4, y = 2}, Vec2i.right(), board, _ -> false));
        let target = evOpt |> Option.map(PlayerScene.movedTarget) |> Option.map(t -> (t#x, t#y));
        Assert.assertEq(expected = (None, 0), (target, List.length(moves)))

    // ════════════════════════════════════════════════════════
    // physicsStep 統合ハーネス — 実 OOP-callback 経路を 1 フレーム駆動
    //   入力(readHeldDirection) → MoveRange pred gating → stepPlayerMove → Cmd.Move
    //   を physicsStep そのもので通し、単体テストでは届かない結線を固定する。
    //   board/overlay/tween はモック（withMockBoard / MoveRange overlay 直挿し / withNoopTween）。
    // ════════════════════════════════════════════════════════

    /// テスト用の最小プレイヤー Data（gridPos のみ可変）。
    def playerAt(id: Int32, pos: {x = Int32, y = Int32}): PlayerScene.Data = {
        id = id, classId = "test_player", gridPos = pos, moveTiles = 4, hp = 10,
        waited = false, attackTargetId = None, resource = TestUnitFixtures.testResource(4, 10),
        weapons = TestUnitFixtures.testWeapon() :: Nil, staves = Nil, consumables = Nil,
        selectedItem = None, moveStepsTaken = 0, facing = Staff.Direction.Down, hidden = false,
        usedStairs = false, level = 1, exp = 0, pendingLevelUp = None, statuses = Nil,
        rings = Nil, ringEquipped = false, followUpUsed = false
    }

    /// World 配下に Player(0)@(4,2) を挿し、`reachable` セルの MoveRange overlay を直挿しした scene と、
    /// その player ノードを返す（physicsStep の `node` 引数に渡す）。
    def moveScene(reachable: List[{x = Int32, y = Int32}]): (EngineNode[NodeTag], Scene[NodeTag]) =
        let world = Marker2D.make(Vec2.zero()) |> CanvasItem.setYSortEnabled(true);
        let pnode = EngineNode.Marker2DWithState(Marker2D.make(Vec2.zero()),
                        NodeTag.Player(playerAt(0, {x = 4, y = 2})));
        let scene = Scene.empty()
            |> Scene.addNode(MapScene.worldName(), EngineNode.Marker2DWithState(world, NodeTag.NoTag))
            |> Scene.addChildAt(MapScene.worldPath(), PlayerScene.playerName(0), pnode)
            |> RangeOverlay.attachParent("MoveRange", NodeTag.MoveRange({reachable = reachable, drawCells = reachable}));
        (pnode, scene)

    /// physicsStep を 1 フレーム駆動し、emit された Cmd.Move の着地マス列を返す。
    /// `pressed` で押下キーを、`reachable` で MoveRange を作り分ける。board は player@(4,2) で固定。
    def runPhysicsStep(pressed: GameEngine.Key -> Bool,
                        reachable: List[{x = Int32, y = Int32}]): List[(Int32, Int32)] =
        let (pnode, scene) = moveScene(reachable);
        let board = ({map = tenByFive(), pieces = (Piece.Player(0), {x = 4, y = 2}) :: Nil}: Board);
        region rc {
            let (_, moves) = TestUnitFixtures.withRecordedMoves(() ->
                TestUnitFixtures.withMockGameKeys(pressed, () ->
                TestUnitFixtures.withMockBoard(board, () ->
                TestUnitFixtures.withMockGameLogger(() ->
                TestUnitFixtures.withNoopTween(() ->
                TestUnitFixtures.withSelectionRef(rc,
                    ({id = Some(0), drafts = (Nil: List[MoveDraft.DraftAction]), gatherActive = false}: SelectedPlayer.Selection),
                    () ->
                    // S6: physicsStep が waited を World 権威で読むため WorldQuery を discharge。
                    // PlayerMoving は waited を参照しないので World.empty()（scene fallback）で十分。
                    TestUnitFixtures.withWorldQuery(World.empty(), () ->
                    // P4-e: 着地の自動取得が中央ポップアップの State resource を書くため no-op で剥がす。
                    TestUnitFixtures.withNoopPickupPopup(() ->
                    PlayerMovementScene.physicsStep(Duration.zero(), pnode, PlayerScene.playerPath(0), scene)))))))));
            moves |> List.map(c -> (c#x, c#y))
        }

    /// D 押下＋(5,2) が MoveRange 内 → 実 physicsStep 経路で Cmd.Move((5,2)) が 1 回出る。
    @Test
    def testPhysicsStepInRangeEmitsMove(): Unit \ Assert =
        Assert.assertEq(
            expected = (5, 2) :: Nil,
            runPhysicsStep(k -> k == GameEngine.Key.D, {x = 4, y = 2} :: {x = 5, y = 2} :: Nil))

    /// D 押下だが (5,2) が MoveRange 外 → pred gating で移動なし（emit ゼロ）。pred 結線を固定。
    @Test
    def testPhysicsStepOutOfRangeNoMove(): Unit \ Assert =
        Assert.assertEq(
            expected = (Nil: List[(Int32, Int32)]),
            runPhysicsStep(k -> k == GameEngine.Key.D, {x = 4, y = 2} :: Nil))

    /// キー無し → 入力なしで移動なし（emit ゼロ）。readHeldDirection 結線を固定。
    @Test
    def testPhysicsStepNoKeyNoMove(): Unit \ Assert =
        Assert.assertEq(
            expected = (Nil: List[(Int32, Int32)]),
            runPhysicsStep(_ -> false, {x = 4, y = 2} :: {x = 5, y = 2} :: Nil))
}
