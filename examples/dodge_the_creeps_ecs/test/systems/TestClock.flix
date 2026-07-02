// 共有 lib Clock（反復タイマー tick / カウントダウン countdown）の直接テスト。
// 値は 2 進で厳密な分数（0.25 / 0.125 等）を使い、float 誤差を避ける。

mod TestClock {

    /// interval 未満は fire せず貯める。
    @Test
    def testTickAccumulates(): Unit \ Assert =
        let r = Clock.tick(0.125, 0.125, 0.5);   // 0.25 < 0.5
        Assert.assertEq(expected = true, not r#fired and r#rest == 0.25)

    /// interval 到達で fire し、余りを rest に残す。
    @Test
    def testTickFires(): Unit \ Assert =
        let r = Clock.tick(0.375, 0.25, 0.5);    // 0.625 >= 0.5 → fire, rest = 0.125
        Assert.assertEq(expected = true, r#fired and r#rest == 0.125)

    /// ちょうど interval は fire（< だけ非発火）、余り 0。
    @Test
    def testTickBoundary(): Unit \ Assert =
        let r = Clock.tick(0.25, 0.25, 0.5);     // 0.5 は < 0.5 でない → fire, rest = 0.0
        Assert.assertEq(expected = true, r#fired and r#rest == 0.0)

    /// countdown は dt 減らし、0 で下げ止める（remaining==dt の丁度ゼロ境界も）。
    @Test
    def testCountdown(): Unit \ Assert =
        Assert.assertEq(expected = (1.5, 0.0, 0.0),
            (Clock.countdown(2.0, 0.5),    // 通常
             Clock.countdown(0.25, 1.0),   // 行き過ぎ → 0 clamp
             Clock.countdown(0.5, 0.5)))   // 丁度 0
}
