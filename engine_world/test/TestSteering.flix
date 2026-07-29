// Steering の 1 歩選びを小さな盤で pin する。乱数を持たない決定性（同着は固定順、
// wander はハッシュ）がここでの検査対象 — 経路全体ではなく「いまの 1 歩」だけを見る。

mod TestSteering {

    // 5x5 の開けた盤。壁なし — 入れるかどうかは盤の外かどうかだけ。
    def open5(cell: (Int32, Int32)): Bool =
        let (x, y) = cell;
        x >= 0 and x < 5 and y >= 0 and y < 5

    // 横 1 列の廊下 (0,1)〜(4,1)。逃げ道が 1 方向しかない盤。
    def corridor(cell: (Int32, Int32)): Bool =
        let (x, y) = cell;
        y == 1 and x >= 0 and x < 5

    /// chase は target へ最短で近づく隣を選ぶ。同着（(1,1)→(0,0) は上と左が同距離）は
    /// 上→下→左→右 の固定順で先に現れる「上」が勝つ — 毎回同じ 1 歩（golden が効く根拠）。
    @Test
    def testChasePicksShortestInFixedOrder(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some((2, 1)), Some((1, 0))),
            (Steering.chase(open5, (2, 2), (2, 0), 25),
             Steering.chase(open5, (1, 1), (0, 0), 25)))

    /// flee は threat から遠ざかる隣を選ぶ。廊下では反対側へ 1 歩。
    /// 袋小路（廊下の端で threat が隣）では遠くなる隣が無く None。
    @Test
    def testFleeMovesAwayOrGivesUp(): Unit \ Assert =
        Assert.assertEq(
            expected = (Some((3, 1)), None),
            (Steering.flee(corridor, (2, 1), (0, 1), 25),
             Steering.flee(corridor, (4, 1), (3, 1), 25)))

    /// wander は引いた向きへ入れなければ None（呼び側が「今回は留まる」に倒す）。
    @Test
    def testWanderBlockedIsNone(): Unit \ Assert =
        Assert.assertEq(
            expected = None,
            Steering.wander(_ -> false, (2, 2), 0, 0))
}
