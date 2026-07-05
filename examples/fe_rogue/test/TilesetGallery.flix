// TilesetGallery — TilesetGen（純粋生成器）をヘッドレスに PNG へ焼き、目視承認用の比較 1 枚を作る。
// RobotGallery と同型（GL なし・flix test がファイルを生成）。SoftRaster は背景不透明前提のため使わず、
// TilesetGen.pixelArgb の packed ARGB を BufferedImage.setRGB で直接置く（透明セルをそのまま透過させる）。
//
//   gallery/tileset_fire.png   / tileset_forest.png / tileset_ruins.png — 312×234・座標互換（原本と同格子）
//   gallery/tileset_compare.png — 原本 green + 3 テーマを縦に並べた比較（各シート 2 倍・左にラベル）
mod TilesetGallery {
    import java.io.File
    import java.awt.image.BufferedImage
    import java.awt.image.ImageObserver
    import java.awt.Graphics2D
    import java.awt.{Color => AwtColor}
    import java.awt.Font
    import java.awt.RenderingHints
    import javax.imageio.ImageIO

    def outDir(): String = "gallery"
    def originalPath(): String = "assets/sprites/tileset_dungeon_green.png"

    // ════════════════════════════════════════════════════════
    // テーマ 1 枚を 312×234 の ARGB BufferedImage へ焼く
    // ════════════════════════════════════════════════════════

    /// TilesetGen.pixelArgb を全ピクセルに適用して 1 枚のアトラス画像を組む（透明は alpha=0 のまま）。
    def renderTheme(theme: TilesetGen.Theme): BufferedImage \ IO =
        let w = TilesetGen.atlasW();
        let h = TilesetGen.atlasH();
        let c = TilesetGen.cell();
        let img = new BufferedImage(w, h, 2i32);  // TYPE_INT_ARGB
        List.forEach(y ->
            List.forEach(x -> {
                let argb = TilesetGen.pixelArgb(theme, x / c, y / c, Int32.modulo(x, c), Int32.modulo(y, c));
                img.setRGB(x, y, argb)
            }, List.range(0, w)),
            List.range(0, h));
        img

    /// テーマ画像を gallery/tileset_<name>.png へ書き出し、非透明ピクセル数を返す（sanity 用）。
    def writeTheme(theme: TilesetGen.Theme): Int32 \ IO =
        let img = renderTheme(theme);
        discard (new File(outDir())).mkdirs();
        discard ImageIO.write(img, "png", new File("${outDir()}/tileset_${theme#name}.png"));
        countOpaque(img)

    /// 非透明（ARGB≠0）のピクセル数。TilesetGen は透明を厳密に 0 で返すため単純比較でよい。
    def countOpaque(img: BufferedImage): Int32 \ IO =
        let w = img.getWidth();
        let h = img.getHeight();
        region rc {
            let n = Ref.fresh(rc, 0);
            List.forEach(y ->
                List.forEach(x ->
                    if (img.getRGB(x, y) != 0) Ref.put(Ref.get(n) + 1, n) else (),
                    List.range(0, w)),
                List.range(0, h));
            Ref.get(n)
        }

    // ════════════════════════════════════════════════════════
    // 比較画像（原本 + 3 テーマを縦積み・2 倍・左ラベル）
    // ════════════════════════════════════════════════════════

    def scale(): Int32 = 2
    def labelW(): Int32 = 104
    def gap(): Int32 = 14
    def margin(): Int32 = 14

    def bg(): AwtColor \ IO = new AwtColor(24i32, 26i32, 24i32, 255i32)
    def fg(): AwtColor \ IO = new AwtColor(224i32, 228i32, 224i32, 255i32)

    /// (label, atlas) の縦積みを 1 枚に描く。各 atlas は scale 倍・最近傍で拡大。
    def buildCompare(rowsIn: List[(String, BufferedImage)]): BufferedImage \ IO =
        let sw = TilesetGen.atlasW() * scale();
        let sh = TilesetGen.atlasH() * scale();
        let n = List.length(rowsIn);
        let w = labelW() + sw + margin() * 2;
        let h = margin() * 2 + n * sh + (n - 1) * gap();
        let img = new BufferedImage(w, h, 2i32);
        let g: Graphics2D = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_NEAREST_NEIGHBOR);
        g.setColor(bg());
        g.fillRect(0i32, 0i32, w, h);
        g.setFont(new Font("SansSerif", 1i32, 22i32));
        List.forEach(pair -> {
            let (i, row) = pair;
            let (label, atlas) = row;
            let rowY = margin() + i * (sh + gap());
            g.setColor(fg());
            g.drawString(label, 12i32, rowY + sh / 2i32);
            discard g.drawImage(atlas, labelW(), rowY, labelW() + sw, rowY + sh,
                                0i32, 0i32, TilesetGen.atlasW(), TilesetGen.atlasH(),
                                unchecked_cast(null as ImageObserver))
        }, List.zip(List.range(0, n), rowsIn));
        g.dispose();
        img

    // ════════════════════════════════════════════════════════
    // テストエントリ: PNG を焼いて存在と非空を assert する
    // ════════════════════════════════════════════════════════

    @Test
    def testTilesetGallery(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        discard (new File(outDir())).mkdirs();
        // 3 テーマを焼き出し、非透明ピクセル数を集める。
        let themes = TilesetGen.themes();
        let counts = List.map(writeTheme, themes);
        // 比較画像: 原本 + 3 テーマ。
        let original = ImageIO.read(new File(originalPath()));
        let themeImgs = List.map(renderTheme, themes);
        let labeled = ("green", original) ::
            List.zip(List.map(t -> t#name, themes), themeImgs);
        let compare = buildCompare(labeled);
        discard ImageIO.write(compare, "png", new File("${outDir()}/tileset_compare.png"));
        // sanity: 各テーマは相当数の非透明ピクセルを持つ（役割セルが塗れている）。
        // 参照 47 セル + 床/水/壁の連続領域 ≒ 60 セル × ~600px ≒ 3 万 px 以上。
        let minCount = List.foldLeft((m, x) -> Int32.min(m, x), 999999, counts);
        Assert.assertEq(expected = true,
            minCount > 25000
                and (new File("${outDir()}/tileset_fire.png")).exists()
                and (new File("${outDir()}/tileset_forest.png")).exists()
                and (new File("${outDir()}/tileset_ruins.png")).exists()
                and (new File("${outDir()}/tileset_compare.png")).exists())
}
