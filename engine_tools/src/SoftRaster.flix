// SoftRaster — GameEngine.Drawable / PolygonRenderCmd を Java2D で 1 枚の PNG に焼く
// ソフトウェアラスタライザ。GL を使わないので GL コンテキストの無い場所（スナップショット
// テスト、将来の IDE ビューポートのプレビュー）で描画結果を目視確認できる。
//
// 描画規約は render_gl/Frame.drawSprite と一致させてある:
//   - box（texture==""）      : scale がそのまま design px サイズ。角丸＋枠を描く。
//   - textured（texture!=""）  : displaySize = texInfo × scale。centered なら中心原点。
//                               uvOffset/uvScale が元テクスチャの部分矩形を選ぶ。
//   - font_*（テキスト）      : 各グリフ Drawable を PNG 出力解像度の Font で直接 drawString する
//                               （アトラス縮小サンプルではなく実サイズ焼きなので小サイズでもくっきり）。
//   - polygon                 : 頂点を design px として塗りつぶす。
// z 順は (zIndex, 追加順) の安定ソートで Frame と揃える。design を `scale` 倍に拡大して出力する。
mod SoftRaster {
    import java.awt.image.BufferedImage
    import java.awt.image.RescaleOp
    import java.awt.image.ImageObserver
    import java.awt.Graphics2D
    import java.awt.{Color => AwtColor}
    import java.awt.RenderingHints
    import java.awt.BasicStroke
    import java.awt.Font
    import java.awt.Shape
    import java.awt.geom.{RoundRectangle2D$Double => RoundRect}
    import java.awt.geom.{Line2D$Double => Line2D}
    import java.awt.geom.{Rectangle2D$Double => Rect2D}
    import java.io.File
    import java.io.FileInputStream
    import java.lang.{Character => JChar}
    import javax.imageio.ImageIO

    /// ラスタライズ要求。design 解像度の Drawable 群を `scale` 倍に拡大して `outPath` に PNG 出力。
    /// `texturePath` は Drawable#texture 名 → PNG ファイルパス。フォント（`font_` テクスチャ）は
    /// アトラス PNG をサンプルせず、`fontTtf` の TTF を出力解像度サイズへ deriveFont して直接
    /// drawString する。グリフ Drawable から元文字を引くため `fontAtlas`（uvOffset↔codepoint の対応）を使う。
    pub type alias RasterReq = {
        drawables = List[GameEngine.Drawable],
        polygons = List[GameEngine.PolygonRenderCmd],
        design = Vec2.Vec2,
        scale = Int32,
        background = Color,
        texturePath = Map[String, String],
        fontTtf = String,
        fontAtlas = FontAtlas,
        outPath = String
    }

    /// フォントグリフを直接 drawString するための描画コンテキスト。
    /// `baseFont` は素の TTF Font（サイズは deriveFont でグリフ毎に決める）。
    /// `atlas` はメトリクス（ascent/textureSize/bake fontSize）。
    /// `codepointByCell` は `(セル左上 px x, y) → Unicode codepoint`。グリフ Drawable の uvOffset は
    /// アトラスのセル s0/t0 と同一なので、これで元文字へ逆引きできる。
    type alias FontCtx = {
        baseFont = Font,
        atlas = FontAtlas,
        codepointByCell = Map[(Int32, Int32), Int32]
    }

    /// 要求を 1 枚の PNG に焼いて書き出す。
    pub def render(req: RasterReq): Unit \ IO =
        writePng(renderToImage(req), req#outPath)

    /// 要求を 1 枚の BufferedImage に焼いて返す（PNG 書き出しはしない）。
    /// PNG スナップショット（render）と GIF アニメ（GifEncoder が 1 フレームずつ集める）の
    /// 共有ラスタライズ経路。`outPath` は使わない。
    pub def renderToImage(req: RasterReq): BufferedImage \ IO = region rc {
        HeadlessFont.ensureHeadless();
        let sf = Int32.toFloat64(req#scale);
        let w = ri(req#design#x * sf);
        let h = ri(req#design#y * sf);
        let image = new BufferedImage(Int32.max(1i32, w), Int32.max(1i32, h), 2i32);
        let g: Graphics2D = image.createGraphics();
        // box/poly の塗り（fillRoundRect/fillPolygon）は角丸の縁をなめらかにするため AA を効かせる。
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        // スプライト拡大（drawTextured の drawImage）は最近傍固定。実機の GPU 描画はドット絵を
        // 補間せず拡大するため、ここで補間すると実機と見え方がずれる（にじみ・輪郭ボケ）。
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_NEAREST_NEIGHBOR);
        // 出力解像度で小サイズ文字をくっきり焼くためのテキスト品質ヒント（drawString は INTERPOLATION の対象外）。
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON);
        // 背景（clearColor）で塗りつぶす。
        g.setColor(awtColor(req#background, 1.0f32));
        g.fillRect(0i32, 0i32, Int32.max(1i32, w), Int32.max(1i32, h));
        let textures = loadTextures(req#texturePath);
        let fctx = buildFontCtx(req#fontTtf, req#fontAtlas);
        // Drawable(Ok) と Polygon(Err) を 1 列にまとめ、(z, 追加順) で安定ソートする。
        let tagged = List.append(
            List.map(d -> (Result.Ok(d): Result[GameEngine.PolygonRenderCmd, GameEngine.Drawable]), req#drawables),
            List.map(p -> (Result.Err(p): Result[GameEngine.PolygonRenderCmd, GameEngine.Drawable]), req#polygons));
        let sorted = tagged
            |> List.zipWithIndex
            |> List.sortBy(ix -> let (idx, item) = ix; (zOf(item), idx))
            |> List.map(ix -> let (_, item) = ix; item);
        List.forEach(item -> match item {
            case Result.Ok(d)  => drawDrawable(g, sf, textures, fctx, d)
            case Result.Err(p) => drawPolygon(rc, g, sf, p)
        }, sorted);
        g.dispose();
        image
    }

    /// z 値取り出し（Ok=Drawable / Err=Polygon）。
    def zOf(item: Result[GameEngine.PolygonRenderCmd, GameEngine.Drawable]): Int32 =
        match item {
            case Result.Ok(d)  => d#zIndex
            case Result.Err(p) => p#zIndex
        }

    /// texturePath の各エントリを ImageIO で読み込む。読めないものは飛ばす。
    /// indexed / grayscale 等の色モデルは RescaleOp（drawTextured の tint）が扱えないため、
    /// 一律 ARGB へ正規化する。
    def loadTextures(paths: Map[String, String]): Map[String, BufferedImage] \ IO =
        Map.foldLeftWithKey((acc, name, path) -> {
            let file = new File(path);
            if (file.exists()) {
                let img = ImageIO.read(file);
                if (Object.isNull(img)) acc else Map.insert(name, toArgb(img), acc)
            } else acc
        }, (Map.empty(): Map[String, BufferedImage]), paths)

    /// BufferedImage を TYPE_INT_ARGB(2) にコピーする（indexed / grayscale を RescaleOp 可能にする）。
    def toArgb(src: BufferedImage): BufferedImage \ IO =
        let w = Int32.max(1i32, src.getWidth());
        let h = Int32.max(1i32, src.getHeight());
        let dst = new BufferedImage(w, h, 2i32);
        let g: Graphics2D = dst.createGraphics();
        discard g.drawImage(src, 0i32, 0i32, unchecked_cast(null as ImageObserver));
        g.dispose();
        dst

    /// 1 つの Drawable を描く。texture が空なら box、`font_` ならグリフを直接 drawString、
    /// それ以外はテクスチャ画像。
    def drawDrawable(g: Graphics2D, sf: Float64,
                     textures: Map[String, BufferedImage], fctx: FontCtx, d: GameEngine.Drawable): Unit \ IO =
        if (String.isEmpty(d#texture))
            drawBox(g, sf, d)
        else if (String.startsWith({prefix = "font_"}, d#texture))
            drawGlyph(g, sf, fctx, d)
        else
            match Map.get(d#texture, textures) {
                case None      => ()
                case Some(img) => drawTextured(g, sf, img, d)
            }

    // ════════════════════════════════════════════════════════
    // フォント（グリフ Drawable を出力解像度で直接 drawString）
    // ════════════════════════════════════════════════════════

    /// TTF を読み、アトラスの各グリフの s0/t0 からセル左上 px を逆算した codepoint 表を組む。
    def buildFontCtx(ttfPath: String, atlas: FontAtlas): FontCtx \ IO =
        let fis = new FileInputStream(ttfPath);
        let base = Font.createFont(0i32, fis);
        fis.close();
        let ts = atlas#textureSize;
        let table = Map.foldLeftWithKey((acc, cp, gm) ->
            Map.insert((ri(gm#s0 * ts), ri(gm#t0 * ts)), cp, acc),
            (Map.empty(): Map[(Int32, Int32), Int32]), atlas#glyphs);
        { baseFont = base, atlas = atlas, codepointByCell = table }

    /// 1 グリフ Drawable を出力解像度の Font で直接描く。
    /// グリフのセル高さ（drawable#scale#y × textureSize）とアトラスの行高 (ascent+descent+2) の比が
    /// bake スケール = display fontSize / bake fontSize なので、そこから display fontSize を復元する。
    /// ベースラインはセル上端（drawable#position#y）から ascent × bakeScale 下。
    /// uvOffset をセル px へ戻して codepoint を逆引きし、その 1 文字を drawString する。
    def drawGlyph(g: Graphics2D, sf: Float64, fctx: FontCtx, d: GameEngine.Drawable): Unit \ IO =
        let atlas = fctx#atlas;
        let ts = atlas#textureSize;
        let rowH = atlas#ascent + atlas#descent + 2.0;
        let cellH = d#scale#y * ts;
        let bakeScale = if (rowH > 0.0) cellH / rowH else 0.0;
        let displayFontSize = bakeScale * atlas#fontSize;
        let outFontSize = displayFontSize * sf;
        let cellKey = (ri(d#uvOffset#x * ts), ri(d#uvOffset#y * ts));
        match Map.get(cellKey, fctx#codepointByCell) {
            case None     => ()
            case Some(cp) =>
                let str = JChar.toString(cp);
                let baselineX = d#position#x * sf;
                let baselineY = (d#position#y + atlas#ascent * bakeScale) * sf;
                g.setFont(fctx#baseFont.deriveFont(f32(outFontSize)));
                g.setColor(awtColor(d#color, d#alpha));
                g.drawString(str, f32(baselineX), f32(baselineY))
        }

    /// 単色矩形（角丸＋枠）。scale が design px サイズ、position が左上。
    /// 重ねる順は GL シェーダと同じ 塗り → 縞 → 市松 → 枠。
    def drawBox(g: Graphics2D, sf: Float64, d: GameEngine.Drawable): Unit \ IO =
        let x = ri(d#position#x * sf);
        let y = ri(d#position#y * sf);
        let bw = ri(d#scale#x * sf);
        let bh = ri(d#scale#y * sf);
        let (corner, borderW, borderCol, borderA) = match d#style {
            case Some(st) => (st#cornerRadius, st#borderWidth, st#borderColor, st#borderAlpha)
            case None     => (0.0, 0.0, ({r = 1.0f32, g = 1.0f32, b = 1.0f32}: Color), 0.0f32)
        };
        let arc = ri(corner * 2.0 * sf);
        g.setColor(awtColor(d#color, d#alpha));
        g.fillRoundRect(x, y, bw, bh, arc, arc);
        match d#style {
            case Some(st) => drawBoxOverlays(g, sf, d, st)
            case None     => ()
        };
        if (borderW > 0.0 and borderA > 0.0f32) {
            g.setStroke(new BasicStroke(f32(borderW * sf)));
            g.setColor(awtColor(borderCol, borderA));
            g.drawRoundRect(x, y, bw, bh, arc, arc)
        } else ()

    /// 塗りの上に縞と市松を重ねる。box の角丸矩形にクリップして描き、終わったら解除する。
    def drawBoxOverlays(g: Graphics2D, sf: Float64, d: GameEngine.Drawable,
                        st: GameEngine.BoxStyle): Unit \ IO =
        let hasStripe = st#stripeWidth > 0.0 and st#stripeAlpha > 0.0f32 and st#stripePeriod > 0.0;
        let hasChecker = st#checkerCell > 0.0 and st#checkerAlpha > 0.0f32;
        if (hasStripe or hasChecker) {
            // fillRoundRect と同じ丸め済みの値でクリップ形を作り、塗りとぴったり重ねる。
            let x = ri(d#position#x * sf);
            let y = ri(d#position#y * sf);
            let bw = ri(d#scale#x * sf);
            let bh = ri(d#scale#y * sf);
            let arc = ri(st#cornerRadius * 2.0 * sf);
            let clip = new RoundRect(Int32.toFloat64(x), Int32.toFloat64(y),
                                     Int32.toFloat64(bw), Int32.toFloat64(bh),
                                     Int32.toFloat64(arc), Int32.toFloat64(arc));
            g.setClip(clip);
            if (hasStripe) drawStripes(g, sf, d, st) else ();
            if (hasChecker) drawChecker(g, sf, d, st) else ();
            g.setClip(unchecked_cast(null as Shape))
        } else ()

    /// 縞を描く。GL シェーダと同じ box 中心原点のローカル座標 p を使い、
    /// mod(hv, period) が [0, width] に入る帯を線分で塗る（dir 0: p.x−p.y / 1: p.y / 2: p.x）。
    def drawStripes(g: Graphics2D, sf: Float64, d: GameEngine.Drawable,
                    st: GameEngine.BoxStyle): Unit \ IO =
        let bw = d#scale#x * sf;
        let bh = d#scale#y * sf;
        let cx = d#position#x * sf + bw / 2.0;
        let cy = d#position#y * sf + bh / 2.0;
        let period = st#stripePeriod * sf;
        let width = st#stripeWidth * sf;
        g.setColor(awtColor(st#stripeColor, st#stripeAlpha));
        if (st#stripeDir == 1) {
            // 横縞: 帯 [hv-width/2, hv+width/2] を塗り矩形で(AA が掛からずくっきり — 走査線用)。
            forEachStripe(period, bh / 2.0, width, hv ->
                g.fill(new Rect2D(cx - bw, cy + hv - width / 2.0, bw * 2.0, width)))
        } else if (st#stripeDir == 2) {
            // 縦縞: 同じく塗り矩形でくっきり。
            forEachStripe(period, bw / 2.0, width, hv ->
                g.fill(new Rect2D(cx + hv - width / 2.0, cy - bh, width, bh * 2.0)))
        } else {
            // 斜め 45°: hv = p.x − p.y。hv 空間の幅 width は幾何学的には width/√2。
            g.setStroke(new BasicStroke(f32(width / Vec2.sqrt(2.0))));
            let l = bw + bh;
            forEachStripe(period, (bw + bh) / 2.0, width, hv ->
                g.draw(new Line2D(cx + hv - l, cy - l, cx + hv + l, cy + l)))
        }

    /// mod(hv, period) が [0, width] の帯の中心 hv を、[-halfRange, halfRange] に
    /// かかる分だけ列挙して f を呼ぶ（k*period + width/2 の等差列）。
    def forEachStripe(period: Float64, halfRange: Float64, width: Float64,
                      f: Float64 -> Unit \ ef): Unit \ ef =
        let kMin = floorI((-1.0 * halfRange - width) / period);
        let kMax = floorI(halfRange / period);
        List.range(kMin, kMax + 1) |> List.forEach(k ->
            f(Int32.toFloat64(k) * period + width / 2.0))

    /// 市松を描く。GL シェーダと同じ box 中心原点でセルを刻み、
    /// floor(p.x/cell) + floor(p.y/cell) が偶数のセルだけ塗る。
    def drawChecker(g: Graphics2D, sf: Float64, d: GameEngine.Drawable,
                    st: GameEngine.BoxStyle): Unit \ IO =
        let bw = d#scale#x * sf;
        let bh = d#scale#y * sf;
        let cx = d#position#x * sf + bw / 2.0;
        let cy = d#position#y * sf + bh / 2.0;
        let cell = st#checkerCell * sf;
        g.setColor(awtColor(st#checkerColor, st#checkerAlpha));
        let iMin = floorI(-1.0 * bw / 2.0 / cell);
        let iMax = floorI(bw / 2.0 / cell);
        let jMin = floorI(-1.0 * bh / 2.0 / cell);
        let jMax = floorI(bh / 2.0 / cell);
        List.range(iMin, iMax + 1) |> List.forEach(i ->
            List.range(jMin, jMax + 1) |> List.forEach(j ->
                if (Int32.modulo(i + j, 2) == 0)
                    g.fill(new Rect2D(cx + Int32.toFloat64(i) * cell,
                                      cy + Int32.toFloat64(j) * cell, cell, cell))
                else ()))

    /// Float64 の床を Int32 に（縞・市松の格子番号用。負値も床側へ丸める）。
    def floorI(x: Float64): Int32 =
        Float64.tryToInt32(Float64.floor(x)) |> Option.getWithDefault(0i32)

    /// 画像 Drawable。元テクスチャの uv 部分矩形を切り出し、color で tint・alpha を乗算して
    /// design px の表示矩形へ拡大転写する。font_ アトラス（白グリフ）もこの経路で色が付く。
    def drawTextured(g: Graphics2D, sf: Float64, img: BufferedImage, d: GameEngine.Drawable): Unit \ IO =
        let texW = Int32.toFloat64(img.getWidth());
        let texH = Int32.toFloat64(img.getHeight());
        let displayW = texW * d#scale#x;
        let displayH = texH * d#scale#y;
        let posX = if (d#centered) d#position#x - displayW / 2.0 else d#position#x;
        let posY = if (d#centered) d#position#y - displayH / 2.0 else d#position#y;
        // 元テクスチャ内の部分矩形（uv → px）。画像範囲へクランプする。
        let sx = clampI(ri(d#uvOffset#x * texW), 0i32, img.getWidth());
        let sy = clampI(ri(d#uvOffset#y * texH), 0i32, img.getHeight());
        let sw = clampI(ri(d#uvScale#x * texW), 1i32, img.getWidth() - sx);
        let sh = clampI(ri(d#uvScale#y * texH), 1i32, img.getHeight() - sy);
        let sub = img.getSubimage(sx, sy, sw, sh);
        // color tint と alpha を各バンドに乗算（白グリフ×tint=文字色、スプライトは概ね白×1）。
        let scales = Array#{d#color#r, d#color#g, d#color#b, d#alpha} @ Static;
        let offsets = Array#{0.0f32, 0.0f32, 0.0f32, 0.0f32} @ Static;
        let op = new RescaleOp(scales, offsets, unchecked_cast(null as RenderingHints));
        let tinted = op.filter(sub, unchecked_cast(null as BufferedImage));
        let dx1 = ri(posX * sf);
        let dy1 = ri(posY * sf);
        let dx2 = ri((posX + displayW) * sf);
        let dy2 = ri((posY + displayH) * sf);
        discard g.drawImage(tinted, dx1, dy1, dx2, dy2, 0i32, 0i32, sw, sh,
                            unchecked_cast(null as ImageObserver))

    /// 多角形塗り。頂点は design px。
    def drawPolygon(rc: Region[r], g: Graphics2D, sf: Float64, p: GameEngine.PolygonRenderCmd): Unit \ IO + r =
        let xs = List.toArray(rc, List.map(v -> ri(v#x * sf), p#vertices));
        let ys = List.toArray(rc, List.map(v -> ri(v#y * sf), p#vertices));
        let n = List.length(p#vertices);
        g.setColor(awtColor(p#color, p#alpha));
        g.fillPolygon(xs, ys, n)

    /// Flix Color(0..1) + alpha を AWT Color(0..255) へ。
    def awtColor(c: Color, alpha: Float32): AwtColor \ IO =
        new AwtColor(byteOf(c#r), byteOf(c#g), byteOf(c#b), byteOf(alpha))

    /// Float64 → Float32（BasicStroke 用）。
    def f32(x: Float64): Float32 =
        Float64.clampToFloat32(min = -1.0e18f32, max = 1.0e18f32, x)

    /// 0..1 の成分を 0..255 の Int32 へ丸めてクランプ。
    def byteOf(x: Float32): Int32 =
        clampI(ri(Float32.toFloat64(x) * 255.0), 0i32, 255i32)

    /// Float64 を四捨五入して Int32 に（非負前提）。
    def ri(x: Float64): Int32 =
        Float64.tryToInt32(x + 0.5) |> Option.getWithDefault(0i32)

    /// v を [lo, hi] に収める。
    def clampI(v: Int32, lo: Int32, hi: Int32): Int32 =
        Int32.max(lo, Int32.min(hi, v))

    /// BufferedImage を PNG として書く。親ディレクトリが無ければ作る。
    def writePng(image: BufferedImage, path: String): Unit \ IO =
        let file = new File(path);
        let parent = file.getParentFile();
        if (not Object.isNull(parent)) discard parent.mkdirs() else ();
        discard ImageIO.write(image, "png", file)
}
