// Depth（見下ろしの前後関係）— 足元の高さが zIndex に写ること、
// 部品どうしの相対的な前後が保たれること。
mod TestDepth {

    def band(): Depth.Band = { back = 20, front = 40, top = 0.0, bottom = 200.0 }

    @Test
    def testFootAtTopMapsToBackOfBand(): Unit \ Assert =
        Assert.assertEq(expected = 20, Depth.zAt(band(), 0.0))

    @Test
    def testFootAtBottomMapsToFrontOfBand(): Unit \ Assert =
        Assert.assertEq(expected = 40, Depth.zAt(band(), 200.0))

    @Test
    def testLowerFootComesInFront(): Unit \ Assert =
        // 下に立っている物ほど大きい zIndex = 手前。
        Assert.assertEq(expected = true, Depth.zAt(band(), 120.0) > Depth.zAt(band(), 80.0))

    @Test
    def testOutsideBandIsClampedToEdges(): Unit \ Assert =
        // 帯の外へ歩き出しても順序が壊れない（端で止まる）。
        Assert.assertEq(expected = (20, 40), (Depth.zAt(band(), -500.0), Depth.zAt(band(), 900.0)))

    @Test
    def testPlaceKeepsRelativeOrderInsideOneBody(): Unit \ Assert =
        // 1 体を 0・1・2 の小さな z で組んでも、帯へ持ち上げたあと差はそのまま。
        let parts = { at = Vec2.zero(), item = Render.box(Vec2.one(), white(), 0) }
            :: { at = Vec2.zero(), item = Render.box(Vec2.one(), white(), 2) } :: Nil;
        let lifted = Depth.place(band(), 100.0, parts) |> List.map(zOf);
        Assert.assertEq(expected = (30, 32), (fstOr(lifted), sndOr(lifted)))

    @Test
    def testForRowsGivesOneStepPerRow(): Unit \ Assert =
        // 10 行の盤なら 10 段ぶんの幅を持ち、1 行下がるごとに 1 段手前になる。
        let b = Depth.forRows({ back = 5, originY = 0.0, rows = 10, tileSize = 20.0 });
        Assert.assertEq(expected = (5, 15, 200.0), (b#back, b#front, b#bottom))

    def white(): Color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }

    def zOf(placed: Render.PlacedItem): Int32 =
        match placed#item {
            case Render.Item.Box(b) => b#zIndex
            case _                  => -1
        }

    def fstOr(xs: List[Int32]): Int32 = List.nth(0, xs) |> Option.getWithDefault(-1)

    def sndOr(xs: List[Int32]): Int32 = List.nth(1, xs) |> Option.getWithDefault(-1)
}
