// Daylight の「太陽から導く物」— 影の向き・長さ・塗りの光の段階。
mod TestDaylightSun {

    def spec(): Daylight.ShadowSpec = Daylight.shadowDefaults()

    @Test
    def testMorningShadowFallsWest(): Unit \ Assert =
        // 朝は太陽が東（右）なので、影は左へ伸びる。
        let sh = Daylight.shadowAt(spec(), 0.28);
        Assert.assertEq(expected = true, sh#dir#x < 0.0)

    @Test
    def testEveningShadowFallsEast(): Unit \ Assert =
        let sh = Daylight.shadowAt(spec(), 0.72);
        Assert.assertEq(expected = true, sh#dir#x > 0.0)

    @Test
    def testNoonShadowIsShortestAndDarkest(): Unit \ Assert =
        // 正午は太陽が高いので、影は一番短く一番濃い。
        let noon = Daylight.shadowAt(spec(), 0.5);
        let dawn = Daylight.shadowAt(spec(), 0.26);
        Assert.assertEq(expected = true, noon#scale < dawn#scale and noon#alpha > dawn#alpha)

    @Test
    def testShadowAlwaysFallsTowardTheViewer(): Unit \ Assert =
        // 見下ろしの絵では、影は少し手前（下）へ落ちる方が地面に接して見える。
        let sh = Daylight.shadowAt(spec(), 0.4);
        Assert.assertEq(expected = true, sh#dir#y > 0.0)

    @Test
    def testLightStepIsAlwaysFromAbove(): Unit \ Assert =
        // 塗りの光は真上から。横だけが時刻で切り替わる。
        let (_, y) = Daylight.lightStepAt(0.5);
        Assert.assertEq(expected = -1, y)

    @Test
    def testLightComesFromTheSideOppositeTheShadow(): Unit \ Assert =
        // 朝は太陽が東（右）— 光は右から差し（+1）、影は左へ伸びる。
        // 値そのものを釘打つ（「朝と夕で違う」だけでは符号の取り違えを捕まえられない）。
        let (morning, _) = Daylight.lightStepAt(0.28);
        let (evening, _) = Daylight.lightStepAt(0.72);
        let morningShadow = Daylight.shadowAt(spec(), 0.28)#dir#x;
        let eveningShadow = Daylight.shadowAt(spec(), 0.72)#dir#x;
        Assert.assertEq(expected = (1, -1, true, true),
            (morning, evening,
             Int32.toFloat64(morning) * morningShadow < 0.0,
             Int32.toFloat64(evening) * eveningShadow < 0.0))

    @Test
    def testShadowDoesNotJumpAtSunrise(): Unit \ Assert =
        // 日の出をまたぐ 2 点で伸びと濃さが飛ばない（とびとびに切り替えると影がパチンと伸びる）。
        let before = Daylight.shadowAt(spec(), 0.2495);
        let after = Daylight.shadowAt(spec(), 0.2505);
        Assert.assertEq(expected = true,
            Float64.abs(after#scale - before#scale) < 0.1
                and Float64.abs(after#alpha - before#alpha) < 0.02)

    @Test
    def testSunWrapsSmoothlyAtMidnight(): Unit \ Assert =
        let before = Daylight.sunAt(0.999);
        let after = Daylight.sunAt(0.001);
        Assert.assertEq(expected = true,
            Float64.abs(after#height - before#height) < 0.02
                and Float64.abs(after#east - before#east) < 0.02)

    @Test
    def testDarknessFollowsTheAirColour(): Unit \ Assert =
        // 暗さは空気の色の濃さと同じ値（別の曲線を持たない）。
        let keys = Daylight.defaults();
        Assert.assertEq(expected = Daylight.sample(keys, 0.9)#strength,
                        Daylight.darkness(keys, 0.9))

    @Test
    def testLightStepIsOverheadAtNoon(): Unit \ Assert =
        Assert.assertEq(expected = (0, -1), Daylight.lightStepAt(0.5))

    def sideAt(t: Float64): List[Render.PlacedItem] =
        Daylight.sideShadow({ sun = Daylight.shadowAt(spec(), t), at = { x = 100.0, y = 200.0 },
                              radii = { x = 10.0, y = 3.0 }, ink = { r = 0.0, g = 0.0, b = 0.0 },
                              pixelStep = 0.0, z = 4 })

    @Test
    def testSideShadowStaysOnTheGroundLine(): Unit \ Assert =
        // 横視点では影は足元の高さから上下しない（上下に動くと地面から浮く）。
        let ys = sideAt(0.3) |> List.map(p -> p#at#y);
        Assert.assertEq(expected = 200.0 :: 200.0 :: Nil, ys)

    @Test
    def testSideShadowStretchesAwayFromTheSun(): Unit \ Assert =
        // 朝は太陽が東（右）なので、伸びた影の中心は足元より左。夕は右。
        let xOf = items -> items |> List.head |> Option.map(p -> p#at#x) |> Option.getWithDefault(0.0);
        Assert.assertEq(expected = (true, true),
            (xOf(sideAt(0.28)) < 100.0, xOf(sideAt(0.72)) > 100.0))
}
