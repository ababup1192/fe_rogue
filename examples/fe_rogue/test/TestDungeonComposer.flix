/// DungeonComposer の Door 選択（純粋ロジック）テスト。
///
/// モジュール連結で「どの辺のどのドアを重ねるか」を決める決定的選択。
/// `betterDoorForSide` のタイブレーク（同 x なら min y 等）が 2 マス幅通路の連結の要。
/// `DoorSide` は Eq のみ（ToString 無し）なので、involution は `==`(Bool) で検証する。
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
}
