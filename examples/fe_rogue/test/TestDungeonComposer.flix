/// DungeonComposer の Door 選択（純粋ロジック）テスト。
///
/// モジュール連結で「どの辺のどのドアを重ねるか」を決める決定的選択。
/// `betterDoorForSide` のタイブレーク（同 x なら min y 等）が 2 マス幅通路の連結の要。
/// `DoorSide` は Eq のみ（derive ToString 無し）なので、involution は `==`(Bool) で検証する。
/// JSON セーブ用の `doorSideToString` / `parseDoorSide` は round-trip を `==`(Bool) で検証する。
mod TestDungeonComposer {

    use DungeonComposer.DoorSide

    /// Right 辺は最大 x のドアを選び、同 x なら最小 y で決定的に一意化する。
    /// doors=[(1,0),(3,1),(3,0)] → (3,0)。先頭ドアの一貫選択が 2 マス幅連結を成立させる。
    @Test
    def testDoorBySideRightPicksMaxX(): Unit \ Assert =
        let doors = {x = 1, y = 0} :: {x = 3, y = 1} :: {x = 3, y = 0} :: Nil;
        Assert.assertEq(
            expected = Some((3, 0)),
            DungeonComposer.doorBySide(DoorSide.Right, doors)
                |> Option.map(d -> (d#x, d#y)))

    /// ドアが空なら None（境界）。
    @Test
    def testDoorBySideEmptyIsNone(): Unit \ Assert =
        Assert.assertEq(
            expected = (None: Option[(Int32, Int32)]),
            DungeonComposer.doorBySide(DoorSide.Right, Nil)
                |> Option.map(d -> (d#x, d#y)))

    /// 反対側の反対側は元に戻る（involution の不変条件・全 4 辺）。
    @Test
    def testOppositeSideInvolution(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, true, true),
            (DungeonComposer.oppositeSide(DungeonComposer.oppositeSide(DoorSide.Left))   == DoorSide.Left,
             DungeonComposer.oppositeSide(DungeonComposer.oppositeSide(DoorSide.Right))  == DoorSide.Right,
             DungeonComposer.oppositeSide(DungeonComposer.oppositeSide(DoorSide.Top))    == DoorSide.Top,
             DungeonComposer.oppositeSide(DungeonComposer.oppositeSide(DoorSide.Bottom)) == DoorSide.Bottom))

    /// 左右辺=横（横通路）、上下辺=縦（縦通路）。通路向きの選択に使う。
    @Test
    def testHorizontalSideClassification(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, false, false),
            (DungeonComposer.isHorizontalSide(DoorSide.Left),
             DungeonComposer.isHorizontalSide(DoorSide.Right),
             DungeonComposer.isHorizontalSide(DoorSide.Top),
             DungeonComposer.isHorizontalSide(DoorSide.Bottom)))

    /// `doorSideToString` → `parseDoorSide` で元の辺に戻る（全 4 辺 round-trip）。
    /// JSON セーブの `Plan#sideConnections` 復元がこの往復に依存する。
    @Test
    def testDoorSideStringRoundTrip(): Unit \ Assert =
        Assert.assertEq(
            expected = (true, true, true, true),
            (DungeonComposer.parseDoorSide(DungeonComposer.doorSideToString(DoorSide.Left))   == Ok(DoorSide.Left),
             DungeonComposer.parseDoorSide(DungeonComposer.doorSideToString(DoorSide.Right))  == Ok(DoorSide.Right),
             DungeonComposer.parseDoorSide(DungeonComposer.doorSideToString(DoorSide.Top))    == Ok(DoorSide.Top),
             DungeonComposer.parseDoorSide(DungeonComposer.doorSideToString(DoorSide.Bottom)) == Ok(DoorSide.Bottom)))

    /// 未知文字列は `Err`（JSON 直編集 typo を検出する境界）。
    /// `DoorSide` は ToString を持たないため `Result.isErr`（Bool）に射影して検証する。
    @Test
    def testParseDoorSideUnknownIsErr(): Unit \ Assert =
        Assert.assertEq(
            expected = true,
            Result.isErr(DungeonComposer.parseDoorSide("Diagonal")))

    // ── bfsOffsets: 接続 → 各モジュールの世界座標 offset 解決 ──

    /// アンカー（module 0）は常に (0,0)、相手は door 重ね合わせ式で配置される。
    /// 接続 a=(0, grid(2,0)) ↔ b=(1, grid(0,0)) を「同じ世界座標で重ねる」と
    ///   offsets[1] = offsets[0] + gridA − gridB = (0,0)+(2,0)−(0,0) = (2,0)。
    @Test
    def testBfsAnchorAndDoorAlignment(): Unit \ Assert =
        let conns =
            ({a = ({moduleIndex = 0, grid = {x = 2, y = 0}}: DungeonComposer.DoorRef),
              b = ({moduleIndex = 1, grid = {x = 0, y = 0}}: DungeonComposer.DoorRef)}
             : DungeonComposer.Connection) :: Nil;
        let offs = DungeonComposer.bfsOffsets(conns);
        Assert.assertEq(
            expected = (Some((0, 0)), Some((2, 0))),
            (Map.get(0, offs) |> Option.map(o -> (o#x, o#y)),
             Map.get(1, offs) |> Option.map(o -> (o#x, o#y))))

    /// 正規化: computeMinOffset で全 offset の最小を求め、その符号反転で shift すると
    /// 配置後の最小は (0,0) に揃う（負座標のはみ出しを防ぐ不変条件）。
    @Test
    def testNormalizeMinToZero(): Unit \ Assert =
        let offs = Map.empty()
            |> Map.insert(0, ({x = 0, y = 0}: {x = Int32, y = Int32}))
            |> Map.insert(1, ({x = -2, y = -3}: {x = Int32, y = Int32}));
        let minOff  = DungeonComposer.computeMinOffset(offs);
        let shift   = ({x = 0 - minOff#x, y = 0 - minOff#y}: {x = Int32, y = Int32});
        let shifted = DungeonComposer.shiftOffsets(offs, shift);
        let newMin  = DungeonComposer.computeMinOffset(shifted);
        Assert.assertEq(expected = (0, 0), (newMin#x, newMin#y))
}
