// RenderFont — フォントアトラスベイク (STBTruetype + OpenGL R8 テクスチャ)
//
// LwjglLayer.flix の以下を移植:
//   - kanjiCodepoints
//   - packedCharMetrics
//   - bakeFontAtlas
//   - bakeFontAtlases
//
// 出力フォーマット:
//   - 2048x2048 の単一チャンネルアトラス (GL_R8)
//   - Swizzle で R=1, G=1, B=1, A=red にして白色テキスト + alpha 用テクスチャ化
//   - NEAREST フィルタ (ドットフォントを保つ)

mod RenderFont {
    import org.lwjgl.opengl.GL11
    import org.lwjgl.opengl.GL30
    import org.lwjgl.opengl.GL33
    import org.lwjgl.stb.STBTruetype
    import org.lwjgl.stb.STBTTPackedchar
    import org.lwjgl.stb.STBTTPackContext
    import org.lwjgl.stb.STBTTPackRange
    import org.lwjgl.stb.STBTTFontinfo
    import org.lwjgl.BufferUtils
    import org.lwjgl.system.MemoryStack
    import org.lwjgl.system.MemoryUtil
    import java.io.FileInputStream

    /// アトラスにベイクする漢字 + UI 記号のコードポイント列。
    /// 常用漢字 2,140 字 + ▼ などの UI 記号を engine_core 同梱の `JoyoKanji.text()` から取得し、
    /// さらに `extraKanji()`（常用漢字外だがゲームで使う字）を足す。
    /// `Char.toBmpCodePoint` は U+8000 以上で負値になるので 0xFFFF でマスクする。
    pub def kanjiCodepoints(): List[Int32] =
        String.toList("${JoyoKanji.text()}${extraKanji()}")
            |> List.map(ch -> Int32.bitwiseAnd(Char.toBmpCodePoint(ch), 0xFFFF))

    /// 常用漢字に含まれないがゲーム UI で使う文字。
    ///   斧（アクス）/ 槍（ランス）。武器タイプ表示などで使う。
    def extraKanji(): String = "斧槍"

    /// stbtt_PackFontRanges でベイクされる単一レンジの記述。
    /// `firstCp = 0` のとき `cps` の個別 cp が使われる (stbtt の仕様)。
    type alias BakeRange = {
        firstCp = Int32,
        count   = Int32,
        cps     = List[Int32]   // firstCp != 0 ならダミー
    }

    /// 1 グリフ分のメトリクスを STBTTPackedchar の address から取り出す
    def packedCharMetrics(addr: Int64, bitmapSizeF: Float64): TextLayout.GlyphMetrics \ IO =
        let x0 = Int32.toFloat64(Int16.toInt32(STBTTPackedchar.nx0(addr)));
        let y0 = Int32.toFloat64(Int16.toInt32(STBTTPackedchar.ny0(addr)));
        let x1 = Int32.toFloat64(Int16.toInt32(STBTTPackedchar.nx1(addr)));
        let y1 = Int32.toFloat64(Int16.toInt32(STBTTPackedchar.ny1(addr)));
        {
            xOff    = Float32.toFloat64(STBTTPackedchar.nxoff(addr)),
            yOff    = Float32.toFloat64(STBTTPackedchar.nyoff(addr)),
            glyphW  = x1 - x0,
            glyphH  = y1 - y0,
            advance = Float32.toFloat64(STBTTPackedchar.nxadvance(addr)),
            s0      = x0 / bitmapSizeF,
            t0      = y0 / bitmapSizeF,
            s1      = x1 / bitmapSizeF,
            t1      = y1 / bitmapSizeF
        }

    /// 1 つの FontEntry をアトラスにベイクする。
    /// 戻り値: (FontAtlas, TextureInfo) — TextureInfo は registry に登録する用。
    pub def bakeFontAtlas(entry: RenderAsset.FontEntry): (FontAtlas, RenderAsset.TextureInfo) \ IO =
        let f32 = RenderUtil.f32;
        // 常用漢字 2,140 字 + ASCII + ひらがな + カタカナ + 全角 ASCII で
        // 約 2,500 グリフ。1024x1024 だと 16px ベイクでもパディング込みで入らないため
        // 2048x2048 に拡張。
        let bitmapSize  = 2048;
        let bitmapSizeF = Int32.toFloat64(bitmapSize);

        // フォントファイルを ByteBuffer に読み込む
        let fis = new FileInputStream(entry#path);
        let fontBytes = fis.readAllBytes();
        fis.close();
        let fontBuffer = BufferUtils.createByteBuffer(Array.length(fontBytes));
        discard fontBuffer.put(fontBytes);
        discard fontBuffer.flip();

        // フォント情報を初期化し、em ベースの補正サイズを算出
        let fontInfo = STBTTFontinfo.malloc();
        discard STBTruetype.stbtt_InitFont(fontInfo, fontBuffer);
        let emScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForMappingEmToPixels(fontInfo, f32(entry#fontSize)));
        let phScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForPixelHeight(fontInfo, f32(entry#fontSize)));
        let bakeSize = entry#fontSize * emScale / phScale;

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
        fontInfo.free();

        // ベイク対象レンジ
        let kanji      = kanjiCodepoints();
        let kanjiCount = List.length(kanji);
        let rangesSpec: List[BakeRange] =
            { firstCp = 0x20,   count = 95,         cps = Nil   } ::    // ASCII
            { firstCp = 0xFF01, count = 94,         cps = Nil   } ::    // 全角 ASCII
            { firstCp = 0x3000, count = 160,        cps = Nil   } ::    // CJK 記号 + ひらがな
            { firstCp = 0x30A0, count = 96,         cps = Nil   } ::    // カタカナ
            { firstCp = 0,      count = kanjiCount, cps = kanji } ::    // 漢字 + UI 記号
            Nil;
        let numRanges = List.length(rangesSpec);

        // 各レンジ用 chardata と漢字 cp の IntBuffer を確保
        let cdataList = List.map(r -> STBTTPackedchar.malloc(r#count), rangesSpec);
        let kanjiBuf  = BufferUtils.createIntBuffer(Int32.max(1, kanjiCount));
        List.forEach(cp -> { discard kanjiBuf.put(cp); () }, kanji);
        discard kanjiBuf.flip();

        // STBTTPackRange を numRanges 個確保し、各レンジを設定
        let ranges = STBTTPackRange.calloc(numRanges);
        let specsWithCdata = List.zip(rangesSpec, cdataList);
        let specsIndexed   = List.zipWithIndex(specsWithCdata);
        List.forEach(entry2 -> {
            let (i, pair) = entry2;
            let (spec, cdata) = pair;
            discard ranges.position(i);
            discard ranges.font_size(f32(bakeSize));
            discard ranges.first_unicode_codepoint_in_range(spec#firstCp);
            discard ranges.num_chars(spec#count);
            discard ranges.chardata_for_range(cdata);
            if (spec#firstCp == 0) {
                discard ranges.array_of_unicode_codepoints(kanjiBuf)
            } else ()
        }, specsIndexed);
        discard ranges.position(0);

        // pack
        discard fontBuffer.position(0);
        let bitmap = BufferUtils.createByteBuffer(bitmapSize * bitmapSize);
        let pc = STBTTPackContext.malloc();
        discard STBTruetype.stbtt_PackBegin(pc, bitmap, bitmapSize, bitmapSize, 0, 1, MemoryUtil.NULL);
        discard STBTruetype.stbtt_PackFontRanges(pc, fontBuffer, 0, ranges);
        STBTruetype.stbtt_PackEnd(pc);
        pc.free();

        // GL_RED テクスチャとしてアップロード + swizzle で RGBA 化
        discard bitmap.position(0);
        let texId = GL11.glGenTextures();
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, texId);
        GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL30.GL_R8, bitmapSize, bitmapSize, 0, GL11.GL_RED, GL11.GL_UNSIGNED_BYTE, bitmap);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
        // Swizzle: (ONE, ONE, ONE, RED) → 白色テキスト + alpha = グレースケール値
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_R, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_G, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_B, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_A, GL11.GL_RED);

        // グリフメトリクスを Map に詰める
        let structSize = 28i64;
        let glyphs = List.foldLeft((acc, pair) -> {
            let (spec, cdata) = pair;
            let baseAddr = cdata.address();
            let count = spec#count;
            let cpAt = if (spec#firstCp == 0)
                          (i -> Option.getWithDefault(0, List.nth(i, spec#cps)))
                      else
                          (i -> spec#firstCp + i);
            List.range(0, count) |> List.foldLeft((acc2, i) -> {
                let addr = baseAddr + Int32.toInt64(i) * structSize;
                let gm = packedCharMetrics(addr, bitmapSizeF);
                Map.insert(cpAt(i), gm, acc2)
            }, acc)
        }, Map.empty(), specsWithCdata);

        // 後始末
        List.forEach(cd -> cd.free(), cdataList);
        ranges.free();

        let texName = "font_${entry#name}";
        let texInfo: RenderAsset.TextureInfo = { id = texId, width = bitmapSizeF, height = bitmapSizeF };
        let atlas: FontAtlas = {
            textureName = texName,
            fontSize = entry#fontSize,
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
