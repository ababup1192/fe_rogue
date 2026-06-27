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
         placements = MapScene.twoRoom(10, 5)}

    /// `World.Command` を記録するディスチャージャ。emit された `Cmd.Move` の着地マスを集める。
    /// 戻り値は (thunk の結果, emit された Move target のリスト)。
    def recordMoves(thunk: Unit -> a \ ef):
            (a, List[{x = Int32, y = Int32}]) \ (ef - World.Command) =
        region rc {
            let rec = Ref.fresh(rc, (Nil: List[{x = Int32, y = Int32}]));
            let out = run { thunk() } with handler World.Command {
                def emit(c, k) = {
                    match c {
                        case World.Cmd.Move(_, t) => Ref.put(t :: Ref.get(rec), rec)
                        case _                    => ()
                    };
                    k()
                }
            };
            (out, Ref.get(rec))
        }

    /// 合法な 1 歩（右）: target (5,2) を返し、同じ target へ Cmd.Move を 1 回 emit する。
    @Test
    def testStepPlayerMoveLegalEmitsAndReturnsMoved(): Unit \ Assert =
        let board: Board = {map = tenByFive(), pieces = (Piece.Player(0), {x = 4, y = 2}) :: Nil};
        let (evOpt, moves) = recordMoves(() ->
            PlayerMovementScene.stepPlayerMove(0, {x = 4, y = 2}, Vec2i.right(), board, _ -> true));
        let target  = evOpt |> Option.map(PlayerScene.movedTarget) |> Option.map(t -> (t#x, t#y));
        let emitted = moves |> List.map(t -> (t#x, t#y));
        Assert.assertEq(expected = (Some((5, 2)), (5, 2) :: Nil), (target, emitted))

    /// 進行先が敵駒に占有されている: None を返し emit しない（位置を書かない）。
    @Test
    def testStepPlayerMoveBlockedByEnemyReturnsNoneNoEmit(): Unit \ Assert =
        let board: Board = {map = tenByFive(),
            pieces = (Piece.Player(0), {x = 4, y = 2}) :: (Piece.Enemy(0), {x = 5, y = 2}) :: Nil};
        let (evOpt, moves) = recordMoves(() ->
            PlayerMovementScene.stepPlayerMove(0, {x = 4, y = 2}, Vec2i.right(), board, _ -> true));
        let target = evOpt |> Option.map(PlayerScene.movedTarget) |> Option.map(t -> (t#x, t#y));
        Assert.assertEq(expected = (None, 0), (target, List.length(moves)))

    /// MoveRange 述語が false（範囲外）: None を返し emit しない。
    @Test
    def testStepPlayerMoveBlockedByRangePredReturnsNoneNoEmit(): Unit \ Assert =
        let board: Board = {map = tenByFive(), pieces = (Piece.Player(0), {x = 4, y = 2}) :: Nil};
        let (evOpt, moves) = recordMoves(() ->
            PlayerMovementScene.stepPlayerMove(0, {x = 4, y = 2}, Vec2i.right(), board, _ -> false));
        let target = evOpt |> Option.map(PlayerScene.movedTarget) |> Option.map(t -> (t#x, t#y));
        Assert.assertEq(expected = (None, 0), (target, List.length(moves)))
}
