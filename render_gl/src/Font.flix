// RenderFont — フォントアトラスベイク (STBTruetype SDF + OpenGL R8 テクスチャ)
//
// 各グリフを stb_truetype の単チャンネル SDF (符号付き距離場) としてベイクし、
// シェルフパッキングで 1 枚のアトラスに敷き詰める。描画側 (Shader.flix) は距離場を
// smoothstep で再構成するため、16px ベイクのアトラスでも任意サイズで輪郭がくっきりする。
//
// 出力フォーマット:
//   - 単一チャンネルアトラス (GL_R8)。辺長は必要面積から 4096/8192 を自動選択。
//   - Swizzle で R=1, G=1, B=1, A=red にして「白色 + 距離場を alpha」テクスチャ化
//   - LINEAR フィルタ (距離場を滑らかに補間 → SDF のエッジが綺麗に出る)

mod RenderFont {
    import org.lwjgl.opengl.GL11
    import org.lwjgl.opengl.GL30
    import org.lwjgl.opengl.GL33
    import org.lwjgl.stb.STBTruetype
    import org.lwjgl.stb.STBTTFontinfo
    import org.lwjgl.BufferUtils
    import org.lwjgl.system.MemoryStack
    import java.io.FileInputStream

    /// SDF ベイク対象のコードポイント列 = **そのフォントが実際にグリフを持つ BMP の全文字**。
    /// U+0020..U+FFFF を cmap で走査し、グリフ index 0（.notdef）の字を除く。
    /// 「使う字を人間が登録する」方式はやめた: フォントに入っている字は全部焼けるので、
    /// 常用漢字リストにも追加登録（旧 extraKanji）にも依存しない。
    /// アトラス辺長は下見の必要面積から自動で選ぶ（chooseAtlasSize）。
    def fontCodepoints(fontInfo: STBTTFontinfo): List[Int32] \ IO =
        List.range(0x20, 0x10000)
            |> List.filter(cp -> STBTruetype.stbtt_FindGlyphIndex(fontInfo, cp) != 0)

    /// アトラス辺長の候補。R8 単チャンネルなので 8192² でも 64MB。
    /// それ以上は CPU 側の直接バッファが巨大になるため候補に入れない。
    /// 最大の候補でも収まらない焼きサイズは fitBakeSize が事前に縮めるので、
    /// 実ベイクの溢れ検査まで届いたら engine 側の詰め方の不具合。
    def atlasSizeCandidates(): List[Int32] = 4096 :: 8192 :: Nil

    def maxAtlasSize(): Int32 = 8192

    /// 焼きサイズの下限。これ以下に縮めても読める字にならないので、
    /// ここで止めて（収まらないまま）実ベイクの検査に委ねる。
    def minBakeSize(): Float64 = 6.0

    /// 収まる最大の焼きサイズを選ぶ。要求どおりで収まるならそのまま返し、
    /// 収まらないときだけ 8192 に入る大きさまで縮める。
    ///
    /// 焼きサイズは「絵の細かさ」だけを決めるつまみで、文字の並びには効かない
    /// （描画時に 出したい大きさ / 焼きサイズ で拡縮するため）。だから勝手に縮めても
    /// レイアウトは 1px も動かない — 少しぼやけるだけで、ゲームは必ず起動する。
    ///
    /// 探し方は二分探索。必要面積の下見（矩形の計算だけ）はラスタライズより桁違いに軽い。
    def fitBakeSize(fontInfo: STBTTFontinfo, requested: Float64, padding: Int32,
                    oversample: Float64, cps: List[Int32]): Float64 \ IO =
        let fitsAt = size -> neededArea(fontInfo, scaleOf(fontInfo, size, oversample), padding, cps)
            <= atlasCapacity();
        // 要求が下限より小さいなら縮める余地は無い（縮めるつまみなので、要求より
        // 大きい値を返してはいけない — 大きく返すと収まらないまま実ベイクへ落ちる）。
        if (requested <= minBakeSize() or fitsAt(requested)) requested
        else narrow(fitsAt, minBakeSize(), requested, 8)

    /// lo（収まる）と hi（収まらない）の間を詰めて、収まる最大を返す。
    def narrow(fitsAt: Float64 -> Bool \ IO, lo: Float64, hi: Float64, steps: Int32): Float64 \ IO =
        if (steps <= 0 or hi - lo < 0.5) lo
        else {
            let mid = (lo + hi) / 2.0;
            if (fitsAt(mid)) narrow(fitsAt, mid, hi, steps - 1)
            else narrow(fitsAt, lo, mid, steps - 1)
        }

    /// 最大アトラスに敷ける面積（シェルフ詰めの取りこぼし余裕を差し引いた実効値）。
    def atlasCapacity(): Int32 =
        let side = maxAtlasSize();
        side * side - (side * side) / 8

    def scaleOf(fontInfo: STBTTFontinfo, bakeSize: Float64, oversample: Float64): Float32 \ IO =
        RenderUtil.f32(
            Float32.toFloat64(STBTruetype.stbtt_ScaleForMappingEmToPixels(
                fontInfo, RenderUtil.f32(bakeSize))) * oversample)

    /// 全グリフの SDF セル（bitmap box + 両側 padding + 詰めの 1px）の合計面積。
    def neededArea(fontInfo: STBTTFontinfo, scale: Float32, padding: Int32,
                   cps: List[Int32]): Int32 \ IO =
        let cellArea = cp -> {
            let stack = MemoryStack.stackPush();
            let x0Buf = stack.mallocInt(1);
            let y0Buf = stack.mallocInt(1);
            let x1Buf = stack.mallocInt(1);
            let y1Buf = stack.mallocInt(1);
            STBTruetype.stbtt_GetCodepointBitmapBox(fontInfo, cp, scale, scale, x0Buf, y0Buf, x1Buf, y1Buf);
            let w = x1Buf.get(0) - x0Buf.get(0) + 2 * padding + 1;
            let h = y1Buf.get(0) - y0Buf.get(0) + 2 * padding + 1;
            discard MemoryStack.stackPop();
            w * h
        };
        List.foldLeft((acc, cp) -> acc + cellArea(cp), 0, cps)

    /// 下見: 各グリフの SDF セル寸法（bitmap box + 両側 padding + 詰めの 1px）を合計し、
    /// シェルフパッキングの取りこぼし余裕 (+約14%) を上乗せして、収まる最小の辺長を選ぶ。
    /// SDF 本体の生成より桁違いに軽い（矩形の計算だけでラスタライズしない）。
    /// どの候補にも収まらない見積もりでも最大候補を返し、実ベイクの溢れ検査に委ねる。
    def chooseAtlasSize(fontInfo: STBTTFontinfo, scale: Float32, padding: Int32, cps: List[Int32]): Int32 \ IO =
        let needed = neededArea(fontInfo, scale, padding, cps);
        let fits = size -> needed + needed / 7 <= size * size;
        match List.find(fits, atlasSizeCandidates()) {
            case Some(size) => size
            case None       => 8192
        }

    /// シェルフパッキングの進行状態。
    ///   glyphs   = 確定したグリフメトリクス (cp → GlyphMetrics)
    ///   cx/cy    = 次に置く左上カーソル (px)
    ///   rowH     = 現在の行の最大グリフ高 (px)
    ///   overflow = アトラスに収まらず空白（advance のみ）になった字数
    type alias PackState = {
        glyphs   = Map[Int32, TextLayout.GlyphMetrics],
        cx       = Int32,
        cy       = Int32,
        rowH     = Int32,
        overflow = Int32
    }

    /// advance のみ持つ（矩形を持たない）グリフメトリクスを作る。スペースや溢れ字用。
    def advanceOnlyGlyph(advance: Float64): TextLayout.GlyphMetrics =
        { xOff = 0.0, yOff = 0.0, glyphW = 0.0, glyphH = 0.0,
          advance = advance, s0 = 0.0, t0 = 0.0, s1 = 0.0, t1 = 0.0 }

    /// 1 つの FontEntry をアトラスにベイクする。
    /// 戻り値: (FontAtlas, TextureInfo) — TextureInfo は registry に登録する用。
    pub def bakeFontAtlas(entry: RenderAsset.FontEntry): (FontAtlas, RenderAsset.TextureInfo) \ IO =
        let f32 = RenderUtil.f32;

        // フォントファイルを ByteBuffer に読み込む
        let fis = new FileInputStream(entry#path);
        let fontBytes = fis.readAllBytes();
        fis.close();
        let fontBuffer = BufferUtils.createByteBuffer(Array.length(fontBytes));
        discard fontBuffer.put(fontBytes);
        discard fontBuffer.flip();

        let fontInfo = STBTTFontinfo.malloc();
        discard STBTruetype.stbtt_InitFont(fontInfo, fontBuffer);

        // SDF パラメータ。padding ぶんの距離場を縁に持たせ、oversample 倍の解像度でラスタ化する
        // （どちらもセルの大きさに効くので、収まるかどうかの下見より先に決める）。
        let oversample = 3.0;
        let invOversample = 1.0 / oversample;
        let padding = 5;
        let onedge = 127i8;
        let pixDist = f32(127.0 / 5.0);

        // このフォントが持つ字を全部数え、要求された焼きサイズが最大アトラスに収まるか下見する。
        // 収まらなければ収まる大きさまで自動で縮める（少しぼやけるだけで、文字の並びは変わらない）。
        let cps = fontCodepoints(fontInfo);
        let bakeSize = fitBakeSize(fontInfo, entry#fontSize, padding, oversample, cps);
        if (bakeSize < entry#fontSize)
            println("[RenderFont] '${entry#name}': ${List.length(cps)} 字は焼きサイズ "
                + "${entry#fontSize} では最大アトラスに入らないので ${bakeSize} に縮めました"
                + "（文字の並びは変わりません。くっきりさせたいなら字数の少ないフォントにするか、"
                + "project.json の fontSize を下げて意図した値を明示してください）")
        else ();

        // em ベースの補正サイズ。SDF/advance のスケールはこの emScale を使う（従来の
        // PackFontRanges が内部で使う ScaleForPixelHeight(bakeSize) と数学的に一致する）。
        let emScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForMappingEmToPixels(fontInfo, f32(bakeSize)));

        // フォントの正式メトリクスを取得
        let metricStack = MemoryStack.stackPush();
        let ascentBuf = metricStack.mallocInt(1);
        let descentBuf = metricStack.mallocInt(1);
        let lineGapBuf = metricStack.mallocInt(1);
        STBTruetype.stbtt_GetFontVMetrics(fontInfo, ascentBuf, descentBuf, lineGapBuf);
        let ascent = Int32.toFloat64(ascentBuf.get(0)) * emScale;
        let descent = -1.0 * Int32.toFloat64(descentBuf.get(0)) * emScale;
        let lineGap = Int32.toFloat64(lineGapBuf.get(0)) * emScale;
        discard MemoryStack.stackPop();

        // onedge=127 を境界 (≈0.5) とし、pixel_dist_scale = onedge/padding で
        // 1px あたりの距離値を正規化する。
        //
        // oversample: SDF ラスタ解像度を焼きサイズの oversample 倍にする。集 のように横線が
        // 密な漢字は等倍 (16px) だと線の隙間が距離場で潰れるため、高解像度でラスタ化して
        // ディテールを保つ。グリフ幾何メトリクス (glyphW/xOff 等) は 1/oversample して論理
        // サイズへ戻すので、レイアウト・表示サイズは不変（UV は実テクセルなので影響なし）。
        let scale = f32(emScale * oversample);

        // 焼きサイズが決まったので、それが収まる最小のアトラス辺長を選ぶ。
        // 日本語フルフォントでも自動で 8192 に広がり、それでも足りなければ上で縮んでいるので、
        // ゲーム側は fontSize を品質だけで選べばよい（容量の心配をしない）。
        let bitmapSize  = chooseAtlasSize(fontInfo, scale, padding, cps);
        let bitmapSizeF = Int32.toFloat64(bitmapSize);
        println("[RenderFont] '${entry#name}': ${List.length(cps)} グリフ → ${bitmapSize}x${bitmapSize} アトラス");

        // 全グリフを SDF 化してアトラスに敷き詰める（シェルフパッキング）。
        // bitmap は破壊的に書き込む。1 グリフ生成→blit→メトリクス確定をクロージャで回す。
        let bitmap = BufferUtils.createByteBuffer(bitmapSize * bitmapSize);
        let bakeGlyph = (st: PackState, cp: Int32) -> {
                let stack = MemoryStack.stackPush();
                let wBuf = stack.mallocInt(1);
                let hBuf = stack.mallocInt(1);
                let xoffBuf = stack.mallocInt(1);
                let yoffBuf = stack.mallocInt(1);
                let advBuf = stack.mallocInt(1);
                let lsbBuf = stack.mallocInt(1);
                STBTruetype.stbtt_GetCodepointHMetrics(fontInfo, cp, advBuf, lsbBuf);
                let advance = Int32.toFloat64(advBuf.get(0)) * emScale;
                let sdf = STBTruetype.stbtt_GetCodepointSDF(fontInfo, scale, cp, padding, onedge,
                                                             pixDist, wBuf, hBuf, xoffBuf, yoffBuf);
                let next =
                    if (Object.isNull(sdf))
                        // グリフ無し（スペース等）。advance だけ記録し矩形は 0。
                        { glyphs = Map.insert(cp, advanceOnlyGlyph(advance), st#glyphs) | st }
                    else {
                        let gw = wBuf.get(0);
                        let gh = hBuf.get(0);
                        // 行に収まらなければ次の行へ折り返す。
                        let (cx0, cy0, rowH0) =
                            if (st#cx + gw > bitmapSize) (0, st#cy + st#rowH + 1, 0)
                            else (st#cx, st#cy, st#rowH);
                        if (cx0 + gw > bitmapSize or cy0 + gh > bitmapSize) {
                            // アトラス溢れ。描けないが advance は活かし、末尾で警告を出す。
                            STBTruetype.stbtt_FreeSDF(sdf);
                            { glyphs = Map.insert(cp, advanceOnlyGlyph(advance), st#glyphs),
                              cx = cx0, cy = cy0, rowH = rowH0, overflow = st#overflow + 1 }
                        } else {
                            // SDF ビットマップ (gw×gh) をアトラスの (cx0,cy0) に書き込む。
                            List.forEach(y -> {
                                let rowSrc = y * gw;
                                let rowDst = (cy0 + y) * bitmapSize + cx0;
                                List.forEach(x ->
                                    discard bitmap.put(rowDst + x, sdf.get(rowSrc + x)),
                                    List.range(0, gw))
                            }, List.range(0, gh));
                            STBTruetype.stbtt_FreeSDF(sdf);
                            let pxF = Int32.toFloat64(cx0);
                            let pyF = Int32.toFloat64(cy0);
                            let gwF = Int32.toFloat64(gw);
                            let ghF = Int32.toFloat64(gh);
                            // 幾何メトリクスは 1/oversample で論理サイズへ戻す。
                            // UV (s0..t1) は実テクセル位置から算出するので oversample 済みのまま。
                            let gm: TextLayout.GlyphMetrics = {
                                xOff = Int32.toFloat64(xoffBuf.get(0)) * invOversample,
                                yOff = Int32.toFloat64(yoffBuf.get(0)) * invOversample,
                                glyphW = gwF * invOversample, glyphH = ghF * invOversample,
                                advance = advance,
                                s0 = pxF / bitmapSizeF, t0 = pyF / bitmapSizeF,
                                s1 = (pxF + gwF) / bitmapSizeF, t1 = (pyF + ghF) / bitmapSizeF
                            };
                            { glyphs = Map.insert(cp, gm, st#glyphs),
                              cx = cx0 + gw + 1, cy = cy0, rowH = Int32.max(rowH0, gh),
                              overflow = st#overflow }
                        }
                    };
                discard MemoryStack.stackPop();
                next
        };
        let initSt: PackState = { glyphs = Map.empty(), cx = 0, cy = 0, rowH = 0, overflow = 0 };
        let finalSt = List.foldLeft(bakeGlyph, initSt, cps);
        // 溢れは起動エラーにする: 空白文字での出荷は「フォントが壊れた」ように見え、
        // 警告 1 行では見逃されるため。焼きサイズは fitBakeSize が収まる大きさまで縮めて
        // あるので、ここへ届くのは詰め方（シェルフパッキング）側の不具合。
        let glyphs =
            if (finalSt#overflow > 0)
                bug!("フォント '${entry#name}' の ${finalSt#overflow} 字が ${bitmapSize}x${bitmapSize} "
                    + "アトラスに収まりません（焼きサイズ ${bakeSize} は下見では収まる見積もりでした "
                    + "— engine の詰め方の不具合）")
            else
                finalSt#glyphs;

        fontInfo.free();

        // GL_RED テクスチャとしてアップロード + swizzle で RGBA 化。
        // SDF は LINEAR で補間してエッジを滑らかに復元する（NEAREST だと距離場が階段状になる）。
        discard bitmap.position(0);
        let texId = GL11.glGenTextures();
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, texId);
        GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL30.GL_R8, bitmapSize, bitmapSize, 0, GL11.GL_RED, GL11.GL_UNSIGNED_BYTE, bitmap);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_LINEAR);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_LINEAR);
        // Swizzle: (ONE, ONE, ONE, RED) → 白色 + 距離場を alpha に載せる
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_R, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_G, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_B, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_A, GL11.GL_RED);

        let texName = "font_${entry#name}";
        let texInfo: RenderAsset.TextureInfo = { id = GpuHandle.wrapTextureId(texId), width = bitmapSizeF, height = bitmapSizeF };
        let atlas: FontAtlas = {
            textureName = texName,
            fontSize = bakeSize,
            textureSize = bitmapSizeF,
            ascent = ascent,
            descent = descent,
            lineGap = lineGap,
            glyphs = glyphs
        };
        (atlas, texInfo)

    /// 全 FontEntry をベイクし、(名前→FontAtlas) と更新済み TextureRegistry を返す
    pub def bakeFontAtlases(manifest: List[RenderAsset.FontEntry],
                            registry: RenderAsset.TextureRegistry): (Map[String, FontAtlas], RenderAsset.TextureRegistry) \ IO =
        List.foldLeft((acc, entry) -> {
            let (atlases, reg) = acc;
            let (atlas, texInfo) = bakeFontAtlas(entry);
            println("  Font '${entry#name}' baked (${atlas#textureName})");
            let newAtlases = Map.insert(entry#name, atlas, atlases);
            let newReg = Map.insert(atlas#textureName, texInfo, reg);
            (newAtlases, newReg)
        }, (Map.empty(), registry), manifest)

}
