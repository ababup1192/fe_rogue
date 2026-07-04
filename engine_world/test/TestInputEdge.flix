// InputEdge のテスト。押下の立ち上がりエッジ（up→down の1フレームだけ true）を固定する。

mod TestInputEdge {

    /// 4通りの (prev, cur) 真理値表：
    ///   up→up   = false（押されていない）
    ///   up→down = true （立ち上がり＝この1フレームだけ true）
    ///   down→down = false（押しっぱなし）
    ///   down→up = false（離した）
    @Test
    def testPressedTruthTable(): Unit \ Assert =
        Assert.assertEq(
            expected = (false, true, false, false),
            (InputEdge.pressed(false, false), InputEdge.pressed(false, true),
             InputEdge.pressed(true, true), InputEdge.pressed(true, false)))
}
