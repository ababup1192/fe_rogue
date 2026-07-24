// TimedHopの時間進行だけをテストする。コース通過や接触はTestRulesで確認する。
mod TestTimedHop {

    /// 半分まで進めた時に最高点へ達し、同じ状態は空中として読める。
    @Test
    def testHalfwayReachesMaximumHeight(): Unit \ Assert =
        let duration = 1.0;
        let height = 30.0;
        let jump = TimedHop.grounded()
            |> TimedHop.start(duration)
            |> TimedHop.step(duration / 2.0);
        Assert.assertEq(
            expected = (true, height),
            (TimedHop.isAirborne(jump), TimedHop.height(height, jump)))

    /// 予定時間を使い切ると地上へ戻り、高さも0になる。
    @Test
    def testDurationEndsOnGround(): Unit \ Assert =
        let duration = 1.0;
        let landed = TimedHop.grounded()
            |> TimedHop.start(duration)
            |> TimedHop.step(duration);
        Assert.assertEq(
            expected = (false, 0.0),
            (TimedHop.isAirborne(landed), TimedHop.height(30.0, landed)))
}
