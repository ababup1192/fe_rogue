// RenderFont — フォントアトラスベイク (STBTruetype SDF + OpenGL R8 テクスチャ)
//
// 各グリフを stb_truetype の単チャンネル SDF (符号付き距離場) としてベイクし、
// シェルフパッキングで 1 枚のアトラスに敷き詰める。描画側 (Shader.flix) は距離場を
// smoothstep で再構成するため、16px ベイクのアトラスでも任意サイズで輪郭がくっきりする。
//
// 出力フォーマット:
//   - 4096x4096 の単一チャンネルアトラス (GL_R8)。SDF は padding ぶん 1 字が大きいので拡張。
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
    /// 日本語フォント（PixelMplus 等）でも約 7,000〜8,000 字で、fontSize 10〜16 の
    /// ベイクなら 4096x4096 に収まる。収まらなければベイク時に警告を出す（下記 overflow）。
    def fontCodepoints(fontInfo: STBTTFontinfo): List[Int32] \ IO =
        List.range(0x20, 0x10000)
            |> List.filter(cp -> STBTruetype.stbtt_FindGlyphIndex(fontInfo, cp) != 0)

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
        // 約 2,500 グリフ（常用漢字 + ASCII + かな + 全角）を SDF でベイクする。
        // SDF はグリフ周囲に padding 距離場を持つぶん 1 字が大きくなるため 4096x4096 に拡張。
        let bitmapSize  = 4096;
        let bitmapSizeF = Int32.toFloat64(bitmapSize);

        // フォントファイルを ByteBuffer に読み込む
        let fis = new FileInputStream(entry#path);
        let fontBytes = fis.readAllBytes();
        fis.close();
        let fontBuffer = BufferUtils.createByteBuffer(Array.length(fontBytes));
        discard fontBuffer.put(fontBytes);
        discard fontBuffer.flip();

        // フォント情報を初期化し、em ベースの補正サイズを算出。
        // SDF/advance のスケールはこの emScale を使う（従来の PackFontRanges が内部で使う
        // ScaleForPixelHeight(bakeSize) と数学的に一致するため、レイアウトは不変）。
        let fontInfo = STBTTFontinfo.malloc();
        discard STBTruetype.stbtt_InitFont(fontInfo, fontBuffer);
        let emScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForMappingEmToPixels(fontInfo, f32(entry#fontSize)));

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

        // SDF パラメータ。padding ぶんの距離場を縁に持たせ、onedge=127 を境界 (≈0.5) とする。
        // pixel_dist_scale = onedge/padding で 1px あたりの距離値を正規化する。
        //
        // oversample: SDF ラスタ解像度を fontSize の oversample 倍にする。集 のように横線が
        // 密な漢字は等倍 (16px) だと線の隙間が距離場で潰れるため、高解像度でラスタ化して
        // ディテールを保つ。グリフ幾何メトリクス (glyphW/xOff 等) は 1/oversample して論理
        // サイズへ戻すので、レイアウト・表示サイズは不変（UV は実テクセルなので影響なし）。
        let oversample = 3.0;
        let invOversample = 1.0 / oversample;
        let scale = f32(emScale * oversample);
        let padding = 5;
        let onedge = 127i8;
        let pixDist = f32(127.0 / 5.0);

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
        let finalSt = List.foldLeft(bakeGlyph, initSt, fontCodepoints(fontInfo));
        let glyphs = finalSt#glyphs;
        // 溢れは無音にしない: 空白文字化は「フォントが壊れた」ように見えるので、原因と対処を言う。
        if (finalSt#overflow > 0)
            println("[RenderFont] 警告: フォント '${entry#name}' の ${finalSt#overflow} 字が "
                + "4096x4096 アトラスに収まらず空白になります（project.json の fontSize を下げてください）")
        else ();

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
