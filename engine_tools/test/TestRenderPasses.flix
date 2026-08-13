// pass（レンダーターゲット）描き出しの配管を具体値で固定する。
//   renderPassImage: clear Clear = その色で塗ってから / Keep = prev の中身の上に描き足す
//   renderToImageFull: extraImages の絵が普通のスプライトとして描ける（design 寸法 × scale 拡大）
// フォントは描かないが RasterReq の配管上 TTF の実パスが要るため、リポジトリ内の
// 資産を相対参照する（テストの cwd = engine_tools/ 前提）。
mod TestRenderPasses {
    import java.awt.image.BufferedImage
    import java.io.File
    import javax.imageio.ImageIO

    /// 出力の比較は (a, r, g, b) のタプルで行う（負の ARGB int を直接比べると読みにくい）。
    def channels(p: Int32): (Int32, Int32, Int32, Int32) =
        let c = shift -> Int32.bitwiseAnd(Int32.logicalRightShift(dist = shift, p), 255);
        (c(24), c(16), c(8), c(0))

    /// ARGB int の組み立て（テスト入力用）。
    def argb(a: Int32, r: Int32, g: Int32, b: Int32): Int32 =
        Int32.leftShift(a, 24)
            |> Int32.bitwiseOr(Int32.leftShift(r, 16))
            |> Int32.bitwiseOr(Int32.leftShift(g, 8))
            |> Int32.bitwiseOr(b)

    def cfg(scale: Int32): HeadlessRender.RenderConfig =
        { design = { x = 4.0, y = 4.0 }, scale = scale,
          background = { r = 0.0f32, g = 0.0f32, b = 0.0f32 },
          texturePath = Map.empty(),
          fontTtf = "../templates/game-starter/assets/Xolonium-Regular.ttf",
          fontAtlas = { textureName = "font_ui", fontSize = 16.0, textureSize = 256.0,
                        ascent = 12.0, descent = 4.0, lineGap = 0.0, glyphs = Map.empty() },
          outDir = "build/test/renderpasses", frameW = 4, frameH = 4,
          gifDelayMs = 66, gifFps = 15 }

    def emptyPass(op: RenderTarget.LoadOp): HeadlessRender.PassSpec =
        { name = "paper", clear = op, drawables = Nil, polygons = Nil }

    /// 最小の Drawable（テクスチャ名だけ指定。位置・拡大は個々のテストで上書きする）。
    def drawable(texture: String): GameEngine.Drawable =
        { texture = texture, position = { x = 0.0, y = 0.0 }, scale = { x = 1.0, y = 1.0 },
          rotation = 0.0, color = { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, alpha = 1.0f32,
          centered = false, uvOffset = { x = 0.0, y = 0.0 }, uvScale = { x = 1.0, y = 1.0 },
          zIndex = 0, style = None, clip = None, blend = DrawCmd.BlendMode.Normal, mask = Nil }

    // clear Clear は GL の glClear と同じ — ターゲットの全画素がその色（不透明）になる。
    @Test
    def testRenderPassImageClearColorFillsWholeTarget(): Unit \ {Assert, IO} =
        let img: BufferedImage =
            HeadlessRender.renderPassImage(cfg(1),
                emptyPass(RenderTarget.LoadOp.Clear({ r = 1.0f32, g = 0.0f32, b = 0.0f32 })), None);
        Assert.assertEq(expected = (255, 255, 0, 0) :: (255, 255, 0, 0) :: Nil,
            channels(img.getRGB(0i32, 0i32)) :: channels(img.getRGB(3i32, 3i32)) :: Nil)

    // clear Keep は前フレームのターゲットの中身が残ったまま始まる（残像の口）。
    @Test
    def testRenderPassImageNoneKeepsPrevContent(): Unit \ {Assert, IO} =
        let prev: BufferedImage =
            HeadlessRender.renderPassImage(cfg(1),
                emptyPass(RenderTarget.LoadOp.Clear({ r = 0.0f32, g = 0.0f32, b = 1.0f32 })), None);
        let img: BufferedImage =
            HeadlessRender.renderPassImage(cfg(1), emptyPass(RenderTarget.LoadOp.Keep), Some(prev));
        Assert.assertEq(expected = (255, 0, 0, 255), channels(img.getRGB(2i32, 2i32)))

    // clear Keep で prev が無ければ透明から（ターゲットを作った直後の 1 コマ目と同じ）。
    @Test
    def testRenderPassImageNoneWithoutPrevStartsTransparent(): Unit \ {Assert, IO} =
        let img: BufferedImage =
            HeadlessRender.renderPassImage(cfg(1), emptyPass(RenderTarget.LoadOp.Keep), None);
        Assert.assertEq(expected = (0, 0, 0, 0), channels(img.getRGB(0i32, 0i32)))

    // extraImages の絵（2×2）を design (1,1) に置き scale=2 で描き出すと、出力 (2,2) は
    // 元画像 (0,0) の画素になる（表示サイズ = 実寸 × drawable#scale、拡大は最近傍）。
    @Test
    def testRenderToImageFullRendersExtraImageSprite(): Unit \ {Assert, IO} =
        let paper = new BufferedImage(2i32, 2i32, 2i32);
        paper.setRGB(0i32, 0i32, argb(255, 0, 255, 0));
        paper.setRGB(1i32, 1i32, argb(255, 255, 0, 0));
        let c = cfg(2);
        let req: SoftRaster.RasterReq =
            { drawables = { position = { x = 1.0, y = 1.0 } | drawable("paper") } :: Nil,
              polygons = Nil, design = c#design, scale = c#scale, background = c#background,
              texturePath = c#texturePath, fontTtf = c#fontTtf, fontAtlas = c#fontAtlas,
              outPath = "" };
        let img = SoftRaster.renderToImageFull(req, Nil, Map.empty(), Map#{"paper" => paper});
        Assert.assertEq(expected = (255, 0, 255, 0), channels(img.getRGB(2i32, 2i32)))

    // シェーダー面の tex 場が pass の描き出し（extraImages）を読める。
    //   2×2 の pass 画像（左上=緑・右下=赤）を Rgb{Tex×3} で素通しする面を design 4×4 全面に貼る。
    //   出力 (1,1) の画素中心は uv=(0.375,0.375) → texel(0,0)=緑、(3,3) は uv=0.875 → texel(1,1)=赤。
    //   NEAREST の floor 量子化と ARGB のチャンネル取り出しをまとめて釘打ちする。
    @Test
    def testRenderToImageFullSurfaceReadsPassTexture(): Unit \ {Assert, IO} =
        let paper = new BufferedImage(2i32, 2i32, 2i32);
        paper.setRGB(0i32, 0i32, argb(255, 0, 255, 0));
        paper.setRGB(1i32, 1i32, argb(255, 255, 0, 0));
        let c = cfg(1);
        let req: SoftRaster.RasterReq =
            { drawables = Nil, polygons = Nil, design = c#design, scale = c#scale,
              background = c#background, texturePath = c#texturePath, fontTtf = c#fontTtf,
              fontAtlas = c#fontAtlas, outPath = "" };
        let texOf = chan -> ShaderDoc.Field.Tex({ name = "paper", chan = chan });
        let surface: SoftRaster.SurfaceCmd =
            { rect = { position = { x = 0.0, y = 0.0 }, size = { x = 4.0, y = 4.0 } },
              spec = { name = "blit", cycleRate = 0.0, bindings = Nil,
                       out = ShaderDoc.Out.Fill({
                           shade = ShaderDoc.Shade.Rgb({
                               r = texOf(ShaderDoc.TexChan.R), g = texOf(ShaderDoc.TexChan.G),
                               b = texOf(ShaderDoc.TexChan.B) }),
                           alpha = ShaderDoc.Field.Const(1.0) }) },
              time = 0.0, mask = Nil, zIndex = 0, blend = DrawCmd.BlendMode.Normal };
        let img = SoftRaster.renderToImageFull(req, surface :: Nil, Map.empty(),
                                               Map#{"paper" => paper});
        Assert.assertEq(expected = (255, 0, 255, 0) :: (255, 255, 0, 0) :: Nil,
            channels(img.getRGB(1i32, 1i32)) :: channels(img.getRGB(3i32, 3i32)) :: Nil)

    /// PNG を読み戻した 1 画素。読めなければ (−1, −1, −1, −1)。
    def readPixel(path: String, x: Int32, y: Int32): (Int32, Int32, Int32, Int32) \ IO =
        let img = ImageIO.read(new File(path));
        if (Object.isNull(img)) (-1, -1, -1, -1) else channels(img.getRGB(x, y))

    // renderGifWithPasses: コマ番号で色が変わる pass を本編がスプライトとして貼ると、
    // コマ別 PNG に「そのコマの pass の色」が出る — pass がコマごとに描き直されている証拠。
    // GIF の実在と Filmstrip のコマ数も同時に釘打ちする。
    @Test
    def testRenderGifWithPassesRendersPassPerFrame(): Unit \ {Assert, IO} =
        let c = { outDir = "build/test/rendergifpasses" | cfg(1) };
        let toCmds = t -> {
            let p: HeadlessRender.PassSpec =
                { name = "paper",
                  clear = RenderTarget.LoadOp.Clear({ r = t, g = 0.0f32, b = 0.0f32 }),
                  drawables = Nil, polygons = Nil };
            (p :: Nil, drawable("paper") :: Nil,
             (Nil: List[GameEngine.PolygonRenderCmd]), (Nil: List[SoftRaster.SurfaceCmd]))
        };
        let strip = HeadlessRender.renderGifWithPasses(c, 0.0f32 :: 1.0f32 :: Nil, 1, toCmds, "smoke");
        let gifExists = (new File("build/test/rendergifpasses/smoke.gif")).exists();
        Assert.assertEq(
            expected = (2, true, (255, 0, 0, 0), (255, 255, 0, 0)),
            (strip#frameCount, gifExists,
             readPixel("build/test/rendergifpasses/frames/smoke/0.png", 1i32, 1i32),
             readPixel("build/test/rendergifpasses/frames/smoke/1.png", 1i32, 1i32)))

    // 組み込みの放射テクスチャ: Render.lightAt が下ろす Drawable（texture "__radial_light"・
    // centered・Add）を texturePath 空のまま描き出すと、黒背景の中心 (128,128) が白へ加算され、
    // 四隅 (0,0) は黒のまま残る（縁は rgb 0 まで減衰しているので Add は背景を汚さない）。
    // engine_tools は engine_world（lightAt の住処）に依存できないため、Drawable を直接組む。
    @Test
    def testRenderToImageFullRendersBuiltinRadialLight(): Unit \ {Assert, IO} =
        let c = cfg(1);
        let light = { texture = "__radial_light", position = { x = 128.0, y = 128.0 },
                      centered = true, blend = DrawCmd.BlendMode.Add | drawable("") };
        let req: SoftRaster.RasterReq =
            { drawables = light :: Nil,
              polygons = Nil, design = { x = 256.0, y = 256.0 }, scale = c#scale,
              background = c#background, texturePath = c#texturePath, fontTtf = c#fontTtf,
              fontAtlas = c#fontAtlas, outPath = "" };
        let img = SoftRaster.renderToImageFull(req, Nil, Map.empty(), Map.empty());
        Assert.assertEq(expected = (255, 255, 255, 255) :: (255, 0, 0, 0) :: Nil,
            channels(img.getRGB(128i32, 128i32)) :: channels(img.getRGB(0i32, 0i32)) :: Nil)
}
