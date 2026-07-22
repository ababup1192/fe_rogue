// PxSprite の「box 列」(既定)と「アトラス 1 クアッド」(opt-in)が同じ絵になることの pin。
// NEAREST・整数 scale・整数座標なら両モードはバイト一致するはず(設計書 R2b の検証)。
// SoftRaster で両方を焼き、全画素を比較する。フォントは使わないが RasterReq が TTF を
// 必須にするので monorepo 内の実フォントを借りる(PreviewFx と同じ工面)。
mod TestPxSpriteRaster {
    import java.awt.image.BufferedImage

    def ttf(): String = "../examples/platformer/assets/Xolonium-Regular.ttf"

    def doc(): PxSpriteDoc.Doc =
        PxSpriteDoc.fromJson(String.unlines(
            "{" ::
            "  \"legend\": { \"a\": \"body\", \"b\": \"hair\", \"c\": \"skin\" }," ::
            "  \"sprites\": {" ::
            "    \"guy\": {" ::
            "      \"anchor\": { \"x\": 2.0, \"y\": 3.0 }," ::
            "      \"frames\": {" ::
            "        \"f0\": [ \".bb..\", \"bccb.\", \"aaaa.\", \".a.a.\" ]" ::
            "      }" ::
            "    }" ::
            "  }" ::
            "}" :: Nil))
            |> Option.getWithDefault(PxSpriteDoc.empty())

    def resolver(key: String): Color =
        match key {
            case "body" => { r = 0.86f32, g = 0.30f32, b = 0.29f32 }
            case "hair" => { r = 0.18f32, g = 0.14f32, b = 0.12f32 }
            case _      => { r = 0.91f32, g = 0.76f32, b = 0.63f32 }
        }

    def design(): Vec2.Vec2 = { x = 48.0, y = 36.0 }

    def bg(): Color = { r = 0.05f32, g = 0.075f32, b = 0.055f32 }

    /// items → BufferedImage(regionRect は textureInfoOf = アトラス寸法で解決)。
    def raster(sideF: Float64, texPath: Map[String, String],
               items: List[Render.PlacedItem]): BufferedImage \ IO =
        let atlas = HeadlessFont.buildUiAtlas(ttf(), ttf());
        let info: GameEngine.TextureInfo =
            { id = GpuHandle.wrapTextureId(0), width = sideF, height = sideF };
        let (drawables, polygons) = Render.drawWith(_ -> Some(info), items);
        SoftRaster.renderToImage({
            drawables = drawables, polygons = polygons,
            design = design(), scale = 2, background = bg(),
            texturePath = texPath, fontTtf = ttf(), fontAtlas = atlas, outPath = "" })

    /// 2 枚の画像の (不一致画素数, 背景以外の画素数[1 枚目]) を数える。
    def diffCount(a: BufferedImage, b: BufferedImage): (Int32, Int32) \ IO =
        let w = a.getWidth();
        let h = a.getHeight();
        let bgArgb = a.getRGB(0, 0);
        let counts = List.range(0, w * h) |> List.foldLeft((acc, i) -> {
            let (diff, painted) = acc;
            let x = Int32.remainder(i, w);
            let y = i / w;
            let pa = a.getRGB(x, y);
            let pb = b.getRGB(x, y);
            ((if (pa != pb) diff + 1 else diff),
             (if (pa != bgArgb) painted + 1 else painted))
        }, (0, 0));
        counts

    def compareModes(flip: Bool): (Int32, Int32) \ IO =
        let d = doc();
        let baked = PxSpriteAtlas.bake(d, resolver);
        let pngPath = "build/test/px_atlas.png";
        SoftRaster.writeRadialPng(baked#side, (x, y) -> PxSpriteAtlas.pixelAt(baked, x, y), pngPath);
        let at: Vec2.Vec2 = { x = 24.0, y = 18.0 };
        let boxItems = PxSprite.draw(d, "guy", "f0", at, flip, 3, resolver, 5);
        let quadItems = PxSprite.drawQuad(d, baked, "px", "guy", "f0", at, flip, 3, 5);
        let boxImg = raster(Int32.toFloat64(baked#side), Map.empty(), boxItems);
        let quadImg = raster(Int32.toFloat64(baked#side), Map#{"px" => pngPath}, quadItems);
        diffCount(boxImg, quadImg)

    /// 非反転: 全画素一致・かつ絵が実際に描かれている(空同士の偽陽性でない)。
    @Test
    def testBoxAndQuadPixelsMatch(): Unit \ IO + Assert =
        let (diff, painted) = compareModes(false);
        Assert.assertEq(expected = (0, true), (diff, painted > 100))

    /// flipX: 鏡映の置き場所規約(anchor の写像)込みで全画素一致。
    @Test
    def testBoxAndQuadPixelsMatchFlipped(): Unit \ IO + Assert =
        let (diff, painted) = compareModes(true);
        Assert.assertEq(expected = (0, true), (diff, painted > 100))
}
