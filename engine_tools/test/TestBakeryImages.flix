// Bakery の絵の受け渡し（走行中に作った画素 → PNG と寸法）。
mod TestBakeryImages {

    def images(): List[{ name = String, side = Int32, pixelAt = (Int32, Int32) -> Int32 }] =
        { name = "atlas", side = 8, pixelAt = (_, _) -> 0 }
            :: { name = "empty", side = 0, pixelAt = (_, _) -> 0 } :: Nil

    @Test
    def testTextureInfoReportsTheSide(): Unit \ Assert =
        // UV を解くのに辺長が要る（PNG のパスだけでは足りない）。
        let info = Bakery.imageTextureInfo(images());
        Assert.assertEq(expected = Some((8.0, 8.0)),
            info("atlas") |> Option.map(t -> (t#width, t#height)))

    @Test
    def testUnknownNameHasNoTexture(): Unit \ Assert =
        let info = Bakery.imageTextureInfo(images());
        Assert.assertEq(expected = true, Option.isEmpty(info("nope")))
}
