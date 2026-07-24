// Lifetime — 誕生時刻＋寿命から経過・進行・生存を導く（now の純関数）。
mod TestLifetime {

    def l(): Lifetime.Lifetime = Lifetime.fire(2.0, 4.0)  // 2.0 に始まり 4.0 続く（6.0 で終わり）

    @Test
    def testElapsedIsNowMinusStart(): Unit \ Assert =
        Assert.assertEq(expected = 1.5, Lifetime.elapsedOf(3.5, l()))

    @Test
    def testProgressHalfway(): Unit \ Assert =
        // 経過 2.0 / 寿命 4.0 = 0.5。
        Assert.assertEq(expected = 0.5, Lifetime.progressOf(4.0, l()))

    @Test
    def testProgressClampedTo01(): Unit \ Assert =
        // 発火前は 0、寿命超過は 1 にクランプ。
        Assert.assertEq(expected = (0.0, 1.0),
            (Lifetime.progressOf(0.0, l()), Lifetime.progressOf(99.0, l())))

    @Test
    def testAliveWindow(): Unit \ Assert =
        // 発火前=死・区間内=生・寿命ちょうど=死（0≤経過<寿命）。
        Assert.assertEq(expected = (false, true, false),
            (Lifetime.alive(1.0, l()), Lifetime.alive(4.0, l()), Lifetime.alive(6.0, l())))

    @Test
    def testRemainingNonNegative(): Unit \ Assert =
        Assert.assertEq(expected = (2.5, 0.0),
            (Lifetime.remaining(3.5, l()), Lifetime.remaining(99.0, l())))
}
