// Depth（見下ろしの前後関係）— 足元の高さが zIndex に写ること、
// 部品どうしの相対的な前後が保たれること。
mod TestDepth {

    def zRange(): Depth.ZRange = { back = 20, front = 40, top = 0.0, bottom = 200.0 }

    @Test
    def testFootAtTopMapsToBackOfRange(): Unit \ Assert =
        Assert.assertEq(expected = 20, Depth.zAt(zRange(), 0.0))

    @Test
    def testFootAtBottomMapsToFrontOfRange(): Unit \ Assert =
        Assert.assertEq(expected = 40, Depth.zAt(zRange(), 200.0))

    @Test
    def testLowerFootComesInFront(): Unit \ Assert =
        // 下に立っている物ほど大きい zIndex = 手前。
        Assert.assertEq(expected = true, Depth.zAt(zRange(), 120.0) > Depth.zAt(zRange(), 80.0))

    @Test
    def testOutsideRangeIsClampedToEdges(): Unit \ Assert =
        // 範囲の外へ歩き出しても順序が壊れない（端で止まる）。
        Assert.assertEq(expected = (20, 40), (Depth.zAt(zRange(), -500.0), Depth.zAt(zRange(), 900.0)))

    @Test
    def testPlaceKeepsRelativeOrderInsideOneBody(): Unit \ Assert =
        // 1 体を 0・1・2 の小さな z で組んでも、範囲へ持ち上げたあと差はそのまま。
        let parts = { at = Vec2.zero(), item = RawDraw.box(Vec2.one(), white(), 0) }
            :: { at = Vec2.zero(), item = RawDraw.box(Vec2.one(), white(), 2) } :: Nil;
        let lifted = Depth.place(zRange(), 100.0, parts) |> List.map(zOf);
        Assert.assertEq(expected = (30, 32), (fstOr(lifted), sndOr(lifted)))

    @Test
    def testForRowsGivesOneStepPerRow(): Unit \ Assert =
        // 10 行の盤なら 10 個ぶんの幅を持ち、1 行下がるごとに 1 つ手前になる。
        let b = Depth.forRows({ back = 5, originY = 0.0, rows = 10, tileSize = 20.0 });
        Assert.assertEq(expected = (5, 15, 200.0), (b#back, b#front, b#bottom))

    def sevenBands(): Depth.Bands =
        Depth.bands({ base = 100, stride = 50 },
            "back" :: "far" :: "ground" :: "shadow" :: "mid" :: "near" :: "front" :: Nil)

    @Test
    def testBandsAreOrderedBackToFront(): Unit \ Assert =
        // 並べた順がそのまま奥→手前。1 本足しても以降を手で書き直さずに済む。
        Assert.assertEq(expected = (100, 200, 400),
            (Depth.bandZ(sevenBands(), "back"), Depth.bandZ(sevenBands(), "ground"),
             Depth.bandZ(sevenBands(), "front")))

    @Test
    def testUnknownBandFallsToBackmost(): Unit \ Assert =
        // 綴り違いは一番奥へ回る（見えるので気づける）。
        Assert.assertEq(expected = 100, Depth.bandZ(sevenBands(), "grnd"))

    @Test
    def testBandRangeStaysInsideItsOwnBand(): Unit \ Assert =
        // 帯の中で足元順に並べても、隣の帯（次は 250）へはみ出さない。
        let r = Depth.bandRange(sevenBands(), "shadow", { stride = 50, top = 0.0, bottom = 100.0 });
        Assert.assertEq(expected = (250, 299, 299), (r#back, r#front, Depth.zAt(r, 100.0)))

    def white(): Color = { r = 1.0, g = 1.0, b = 1.0 }

    def zOf(placed: Render.PlacedItem): Int32 =
        match placed#item {
            case Render.Item.Box(b) => b#zIndex
            case _                  => -1
        }

    def fstOr(xs: List[Int32]): Int32 = List.nth(0, xs) |> Option.getWithDefault(-1)

    def sndOr(xs: List[Int32]): Int32 = List.nth(1, xs) |> Option.getWithDefault(-1)
}
