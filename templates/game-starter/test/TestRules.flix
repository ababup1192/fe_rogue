// ルールだけをテストする（方針どおり）。座標の写経や描画はテストしない。
// 期待値はリテラルでなく Doc の既定値（SampleDoc.defaults）から導く。
mod TestRules {

    def d(): SampleDoc.Doc = SampleDoc.defaults()

    def w0(): World.World =
        World.initial(d(), ThemeDoc.defaults(), PxSpriteDoc.empty())

    @Test
    def testStepMovesBySpeedFromDoc(): Unit \ Assert =
        // 1 秒右に押し続けると Doc の speed ぶんだけ進む（端に届かない範囲で）。
        let dt = 0.1;
        let w = World.step({ x = 1.0, y = 0.0 }, dt, w0());
        Assert.assertEq(expected = World.width() / 2.0 + d()#speed * dt, w#x)

    @Test
    def testHeroClampedInsideScreen(): Unit \ Assert =
        // 端で止まるのはルール。左上へどれだけ押しても主人公全体が画面内に残る。
        let w = World.step({ x = -1.0, y = -1.0 }, 1000.0, w0());
        Assert.assertEq(expected = (World.heroSize() / 2.0, World.heroSize() / 2.0),
            (w#x, w#y))
}
