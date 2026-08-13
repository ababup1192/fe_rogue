// Bakery の絵の受け渡し（走行中に作った画素 → PNG と寸法）と、GIF 焼きの配管の煙テスト。
mod TestBakeryImages {
    import java.io.File
    import javax.imageio.ImageIO

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

    /// PNG を読み戻した (幅, 高)。読めなければ (0, 0)。
    def readDims(path: String): (Int32, Int32) \ IO =
        let img = ImageIO.read(new File(path));
        if (Object.isNull(img)) (0i32, 0i32) else (img.getWidth(), img.getHeight())

    /// bakeGifWith の煙テスト: シェーダー面だけの 3 コマを headless で焼くと、
    /// GIF が実在し・コマ別 PNG が design どおりの寸法で読み戻せ・Filmstrip 情報も 3 コマになる。
    @Test
    def testBakeGifWithWritesGifAndFrames(): Unit \ IO + Assert =
        let ttf = "../templates/game-starter/assets/Xolonium-Regular.ttf";
        let atlas = HeadlessFont.buildUiAtlas(ttf, ttf);
        let cfg: Bakery.BakeConfig =
            { design = { x = 16.0, y = 12.0 }, scale = 1,
              background = { r = 0.0f32, g = 0.0f32, b = 0.0f32 },
              texturePath = Map.empty(), fontTtf = ttf, fontAtlas = atlas,
              outDir = "build/test/bakegifwith", frameW = 16, frameH = 12,
              gifDelayMs = 66, gifFps = 15 };
        let spec: ShaderDoc.Spec = { name = "grad", cycleRate = 0.0, bindings = Nil,
            out = ShaderDoc.Out.Fill({
                shade = ShaderDoc.Shade.Solid({ r = 1.0f32, g = 0.5f32, b = 0.2f32 }),
                alpha = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U }) }) };
        let toCmds = t -> {
            let surf: SoftRaster.SurfaceCmd =
                { rect = { position = { x = 0.0, y = 0.0 }, size = { x = 16.0, y = 12.0 } },
                  spec = spec, time = t, mask = Nil, zIndex = 0,
                  blend = DrawCmd.BlendMode.Normal };
            ((Nil: List[GameEngine.Drawable]), (Nil: List[GameEngine.PolygonRenderCmd]),
             surf :: Nil)
        };
        let strip = Bakery.bakeGifWith(cfg, 0.0 :: 0.5 :: 1.0 :: Nil, 1, toCmds, "smoke");
        let gifExists = (new File("build/test/bakegifwith/smoke.gif")).exists();
        Assert.assertEq(expected = (3, true, (16, 12)),
            (strip#frameCount, gifExists, readDims("build/test/bakegifwith/frames/smoke/2.png")))
}
