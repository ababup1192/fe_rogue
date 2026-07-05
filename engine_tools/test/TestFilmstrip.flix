// Filmstrip.bake の単体テスト。平坦色のフレーム列を横連結スプライトシートに焼き、
// 幅 = フレーム数 × frameW・PNG-8（インデックスカラー）で書けたことを固定する。
mod TestFilmstrip {
    import java.awt.image.BufferedImage
    import java.io.File
    import javax.imageio.ImageIO

    /// 指定の RGB で一様に塗った w×h の BufferedImage（TYPE_INT_RGB）。
    /// Graphics2D（createGraphics）は macOS の -XstartOnFirstThread 下でブロックしうるので、
    /// setRGB で 1 画素ずつ塗って AWT の GraphicsEnvironment に触れない。
    def solid(w: Int32, h: Int32, r: Int32, g: Int32, b: Int32): BufferedImage \ IO =
        let img = new BufferedImage(w, h, 1i32);
        let rgb = Int32.bitwiseAnd(r, 255i32) * 65536i32
                  + Int32.bitwiseAnd(g, 255i32) * 256i32 + Int32.bitwiseAnd(b, 255i32);
        List.forEach(y ->
            List.forEach(x -> img.setRGB(x, y, rgb), List.range(0i32, w)),
            List.range(0i32, h));
        img

    /// PNG を読み戻した (幅, 高)。読めなければ (0, 0)。
    def readDims(path: String): (Int32, Int32) \ IO =
        let img = ImageIO.read(new File(path));
        if (Object.isNull(img)) (0i32, 0i32) else (img.getWidth(), img.getHeight())

    /// 一様色フレーム 3 枚（各 8×6）を焼くと、幅 = 3×8 = 24・高 6・PNG-8（indexed=true・3 色）になり、
    /// 書き出した PNG も 24×6 で読み戻せる。
    @Test
    def testBakeIndexedSheet(): Unit \ IO + Assert =
        let frames =
            solid(8i32, 6i32, 200i32, 30i32, 40i32) ::
            solid(8i32, 6i32, 30i32, 200i32, 40i32) ::
            solid(8i32, 6i32, 40i32, 30i32, 200i32) :: Nil;
        let out = "build/test/filmstrip_indexed.png";
        let observed = match Filmstrip.bake(frames, out) {
            case None    => (0i32, 0i32, 0i32, 0i32, 0i32, false, 0i32, (0i32, 0i32))
            case Some(r) => (r#frameCount, r#frameW, r#frameH, r#width, r#height, r#indexed, r#colors, readDims(out))
        };
        Assert.assertEq(expected = (3i32, 8i32, 6i32, 24i32, 6i32, true, 3i32, (24i32, 6i32)), observed)

    /// 空フレーム列は None（ファイルも作らない）。
    @Test
    def testBakeEmptyIsNone(): Unit \ IO + Assert =
        Assert.assertEq(expected = true, Option.isEmpty(Filmstrip.bake(Nil, "build/test/filmstrip_empty.png")))

    /// 256 色を超えるフレーム（各画素を違う色に塗った 20×20 = 400 色）は
    /// フルカラーへフォールバックする（indexed=false）。幅・コマ数は保つ。
    @Test
    def testBakeFallbackFullColor(): Unit \ IO + Assert =
        let img = new BufferedImage(20i32, 20i32, 1i32);
        List.forEach(y ->
            List.forEach(x ->
                img.setRGB(x, y, y * 20i32 + x),   // 0..399 の相異なる RGB
                List.range(0i32, 20i32)),
            List.range(0i32, 20i32));
        let observed = match Filmstrip.bake(img :: Nil, "build/test/filmstrip_fallback.png") {
            case None    => (true, 0i32, 0i32)
            case Some(r) => (r#indexed, r#frameCount, r#width)
        };
        Assert.assertEq(expected = (false, 1i32, 20i32), observed)
}
