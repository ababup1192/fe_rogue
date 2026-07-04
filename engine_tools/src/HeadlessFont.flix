// HeadlessFont — GL を使わずに TTF から FontAtlas を組み立てるヘッドレスなフォント焼き込み。
//
// エンジン実機は STBTruetype + OpenGL で SDF アトラスを GPU テクスチャに焼くが、
// テスト（スナップショット）や将来の IDE ビューポートのように GL コンテキストが無い場所では
// それが使えない。ここでは Java2D（AWT）の FontMetrics だけで
//   1. TTF を読み実測メトリクス（advance / ascent / descent）を得て `FontAtlas` を組む
//   2. 各グリフの仮想アトラス座標（s0/t0/s1/t1）をペン位置から計算する
// を行う。グリフ画像そのものは焼かない — SoftRaster はアトラス PNG をサンプルせず、
// 出力解像度の Font で `drawString` を直接呼ぶ（SoftRaster.flix 参照）ため、実ラスタは不要で
// メトリクスと codepoint↔セル座標の対応表だけが要る。焼き込みサイズ・アトラス寸法・グリフ配置は
// Label2D.toDrawables が期待するメトリクス規約（yOff = -ascent でセル上端が行トップに一致）に
// 合わせてある。
mod HeadlessFont {
    import java.awt.image.BufferedImage
    import java.awt.Graphics2D
    import java.awt.Font
    import java.awt.FontMetrics
    import java.io.File
    import java.io.FileInputStream
    import java.nio.file.Files
    import java.lang.System

    /// AWT をヘッドレスに固定する。macOS では `-XstartOnFirstThread`（GLFW/AppKit がメインスレッドを
    /// 占有）下で非ヘッドレス AWT を初期化するとメインスレッド待ちでデッドロックするため、
    /// 最初の AWT 使用より前に必ず呼ぶ。GraphicsEnvironment 初期化前に設定すれば有効。
    pub def ensureHeadless(): Unit \ IO =
        discard System.setProperty("java.awt.headless", "true")

    /// 焼き込みピクセル高さ。表示は Label2D 側で fontSize/atlas#fontSize 倍に縮小されるので、
    /// 実機の 16px より大きめに焼いて縮小時のディテールを残す。
    def bakeSize(): Float32 = 32.0f32

    /// 仮想アトラスの一辺（正方）。実画像は焼かないが、s0/t0/s1/t1（0..1 正規化 UV）の分母として
    /// Label2D 側の displaySize 計算（texInfo#width == textureSize 前提）と揃える必要がある。
    /// 常用漢字 + かな + ASCII が余裕で収まる大きさ。
    def atlasDim(): Int32 = 2048

    /// ASCII 印字可能文字（0x20..0x7E）。
    def asciiChars(): String =
        " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

    /// ひらがな（0x3041..0x3096）。
    def hiraChars(): String =
        "ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんゔゕゖ"

    /// カタカナ（0x30A1..0x30FA）+ 長音・中黒。
    def kataChars(): String =
        "ァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴヵヶヷヸヹヺ・ー"

    /// UI が使う記号・矢印・約物。BestTen ドット風 UI 文字列に出るものを網羅する。
    def punctChars(): String =
        "、。「」『』（）〔〕？！…‥／％＋－＝×÷℃±→←↑↓◀▶▲▼◆◇■□●○★☆※〜々〆"

    /// アトラス焼き込みの中間状態。次のグリフを置くペン位置と、確定したメトリクス表。
    type alias PackState = {
        penX = Int32,
        penY = Int32,
        glyphs = Map[Int32, TextLayout.GlyphMetrics]
    }

    /// `ttfPath` の TTF から FontAtlas（メトリクス + codepoint↔セル座標の対応表）を組む。
    /// グリフ画像は焼かない（SoftRaster が出力解像度で直接 drawString するため不要 — HeadlessFont
    /// 冒頭コメント参照）。`joyoPath` は 1 行に常用漢字を並べたテキスト（区切りなし）。
    /// 読めなければ漢字なしで続行。返す FontAtlas は Label2D.measure / toDrawables がそのまま
    /// 使えるメトリクスを持つ（textureName = "font_ui"、textureSize = 仮想アトラス一辺）。
    pub def buildUiAtlas(ttfPath: String, joyoPath: String): FontAtlas \ IO =
        ensureHeadless();
        let font = loadFont(ttfPath);
        // メトリクス測定用の 1x1 スクラッチ。
        let probe = new BufferedImage(1i32, 1i32, 2i32);
        let pg: Graphics2D = probe.createGraphics();
        pg.setFont(font);
        let fm: FontMetrics = pg.getFontMetrics();
        let ascent = fm.getAscent();
        let descent = fm.getDescent();
        let leading = fm.getLeading();
        pg.dispose();
        let rowH = ascent + descent + 2i32;
        let dim = atlasDim();
        let dimF = Int32.toFloat64(dim);
        let chars = String.toList(charset(joyoPath));
        let init: PackState = { penX = 0i32, penY = 0i32, glyphs = Map.empty() };
        let baked = List.foldLeft((state, ch) ->
            bakeGlyph(fm, ascent, rowH, dim, dimF, state, ch), init, chars);
        { textureName = "font_ui",
          fontSize = Float32.toFloat64(bakeSize()),
          textureSize = dimF,
          ascent = Int32.toFloat64(ascent),
          descent = Int32.toFloat64(descent),
          lineGap = Int32.toFloat64(leading),
          glyphs = baked#glyphs }

    /// 1 グリフの仮想アトラス上の位置を確定し、メトリクスを記録して次のペン位置を返す
    /// （実描画はしない — 位置とメトリクスの計算のみ）。
    /// advance が 0 以下（制御文字など）はスキップ。行に収まらなければ次の行へ折り返す。
    def bakeGlyph(fm: FontMetrics, ascent: Int32, rowH: Int32, dim: Int32,
                  dimF: Float64, state: PackState, ch: Char): PackState \ IO =
        let cp = TextLayout.charToCodePoint(ch);
        let advance = fm.charWidth(ch);
        if (advance <= 0i32)
            state
        else {
            let cellW = advance;
            let (penX, penY) =
                if (state#penX + cellW > dim) (0i32, state#penY + rowH)
                else (state#penX, state#penY);
            // ベースラインはセル上端から ascent 下（実描画は無いが、drawGlyph 側の逆算規約と揃える）。
            let penXF = Int32.toFloat64(penX);
            let penYF = Int32.toFloat64(penY);
            let cellWF = Int32.toFloat64(cellW);
            let rowHF = Int32.toFloat64(rowH);
            let gm: TextLayout.GlyphMetrics = {
                xOff = 0.0, yOff = -1.0 * Int32.toFloat64(ascent),
                glyphW = cellWF, glyphH = rowHF,
                advance = Int32.toFloat64(advance),
                s0 = penXF / dimF, t0 = penYF / dimF,
                s1 = (penXF + cellWF) / dimF, t1 = (penYF + rowHF) / dimF
            };
            { penX = penX + cellW, penY = penY, glyphs = Map.insert(cp, gm, state#glyphs) }
        }

    /// 焼き込む全文字。ASCII + かな + 記号 + 常用漢字（読めなければ漢字なし）。
    def charset(joyoPath: String): String \ IO =
        "${asciiChars()}${hiraChars()}${kataChars()}${punctChars()}${readJoyo(joyoPath)}"

    /// 常用漢字ファイルを丸ごと読む。存在しなければ空文字（漢字はアトラスに載らない）。
    def readJoyo(joyoPath: String): String \ IO =
        let file = new File(joyoPath);
        if (file.exists()) Files.readString(file.toPath()) else ""

    /// TTF を TRUETYPE_FONT(0) として読み、焼き込みサイズへ deriveFont する。
    def loadFont(ttfPath: String): Font \ IO =
        let fis = new FileInputStream(ttfPath);
        let base = Font.createFont(0i32, fis);
        fis.close();
        base.deriveFont(bakeSize())
}
