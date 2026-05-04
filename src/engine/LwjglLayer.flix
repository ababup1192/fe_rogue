// LWJGL rendering backend — handles GameEngine.Game effect with OpenGL (minimal)

mod LwjglLayer {
    import org.lwjgl.glfw.GLFW
    import org.lwjgl.glfw.Callbacks
    import org.lwjgl.glfw.GLFWFramebufferSizeCallbackI
    import org.lwjgl.opengl.GL
    import org.lwjgl.opengl.GL11
    import org.lwjgl.opengl.GL13
    import org.lwjgl.opengl.GL15
    import org.lwjgl.opengl.GL20
    import org.lwjgl.opengl.GL30
    import org.lwjgl.opengl.GL33
    import org.lwjgl.stb.STBImage
    import org.lwjgl.stb.STBTruetype
    import org.lwjgl.stb.STBTTBakedChar
    import org.lwjgl.stb.STBTTFontinfo
    import org.lwjgl.stb.STBVorbis
    import org.lwjgl.openal.AL
    import org.lwjgl.openal.AL10
    import org.lwjgl.openal.ALC
    import org.lwjgl.openal.ALC10
    import org.lwjgl.BufferUtils
    import org.lwjgl.system.MemoryStack
    import org.lwjgl.system.MemoryUtil
    import java.lang.System
    import java.io.FileInputStream
    import java.nio.ByteBuffer
    import java.nio.ByteOrder
    import java.nio.file.Files
    import java.nio.file.Paths

    import java.lang.Math

    // ========================================================================
    // 数値変換ヘルパー
    // ========================================================================

    /// Float64 → Float32（GL uniform 用）
    def f32(v: Float64): Float32 =
        Float64.truncateToFloat32(v)

    /// Float64 → Int32（四捨五入）
    def floatToInt32(v: Float64): Int32 =
        Int64.truncateToInt32(unchecked_cast(Math.round(v) as _ \ {}))

    def sinF(x: Float64): Float64 =
        unchecked_cast(Math.sin(x) as _ \ {})

    def cosF(x: Float64): Float64 =
        unchecked_cast(Math.cos(x) as _ \ {})

    // ========================================================================
    // Shader Sources
    // ========================================================================

    def vertexShaderSource(): String =
        "#version 330 core\n" +
        "layout (location = 0) in vec4 vertex;\n" +
        "out vec2 TexCoords;\n" +
        "uniform mat4 model;\n" +
        "uniform mat4 projection;\n" +
        "uniform vec2 uvOffset;\n" +
        "uniform vec2 uvScale;\n" +
        "void main() {\n" +
        "    TexCoords = vertex.zw * uvScale + uvOffset;\n" +
        "    gl_Position = projection * model * vec4(vertex.xy, 0.0, 1.0);\n" +
        "}\n"

    def fragmentShaderSource(): String =
        "#version 330 core\n" +
        "in vec2 TexCoords;\n" +
        "out vec4 color;\n" +
        "uniform sampler2D image;\n" +
        "uniform vec3 spriteColor;\n" +
        "uniform float spriteAlpha;\n" +
        "uniform bool useTexture;\n" +
        "void main() {\n" +
        "    if (useTexture) {\n" +
        "        color = vec4(spriteColor, spriteAlpha) * texture(image, TexCoords);\n" +
        "    } else {\n" +
        "        color = vec4(spriteColor, spriteAlpha);\n" +
        "    }\n" +
        "}\n"

    // ========================================================================
    // Shader Compilation
    // ========================================================================

    def compileShader(source: String, shaderType: Int32): Int32 \ IO =
        let shader = GL20.glCreateShader(shaderType);
        GL20.glShaderSource(shader, source);
        GL20.glCompileShader(shader);
        let success = GL20.glGetShaderi(shader, GL20.GL_COMPILE_STATUS);
        if (success == GL11.GL_FALSE) {
            let log = GL20.glGetShaderInfoLog(shader, 1024);
            println("Shader compilation error: ${log}");
            bug!("Shader failed")
        } else ();
        shader

    def createShaderProgram(vertexSrc: String, fragmentSrc: String): Int32 \ IO =
        let vs = compileShader(vertexSrc, GL20.GL_VERTEX_SHADER);
        let fs = compileShader(fragmentSrc, GL20.GL_FRAGMENT_SHADER);
        let program = GL20.glCreateProgram();
        GL20.glAttachShader(program, vs);
        GL20.glAttachShader(program, fs);
        GL20.glLinkProgram(program);
        let success = GL20.glGetProgrami(program, GL20.GL_LINK_STATUS);
        if (success == GL11.GL_FALSE) {
            let log = GL20.glGetProgramInfoLog(program, 1024);
            println("Shader linking error: ${log}");
            bug!("Linking failed")
        } else ();
        GL20.glDeleteShader(vs);
        GL20.glDeleteShader(fs);
        program

    // ========================================================================
    // Texture Loading
    // ========================================================================

    def loadTexture(path: String, alpha: Bool): GameEngine.TextureInfo \ IO =
        let stack = MemoryStack.stackPush();
        let w = stack.mallocInt(1);
        let h = stack.mallocInt(1);
        let c = stack.mallocInt(1);
        STBImage.stbi_set_flip_vertically_on_load(false);
        let channels = if (alpha) 4 else 3;
        let data = STBImage.stbi_load(path, w, h, c, channels);
        if (Object.isNull(data)) {
            discard MemoryStack.stackPop();
            bug!("Failed to load texture: ${path}")
        } else {
            let texWidth = w.get(0);
            let texHeight = h.get(0);
            let textureID = GL11.glGenTextures();
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, textureID);
            let format = if (alpha) GL11.GL_RGBA else GL11.GL_RGB;
            GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, format, texWidth, texHeight, 0, format, GL11.GL_UNSIGNED_BYTE, data);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL11.GL_REPEAT);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL11.GL_REPEAT);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
            STBImage.stbi_image_free(data);
            discard MemoryStack.stackPop();
            { id = textureID, width = Int32.toFloat64(texWidth), height = Int32.toFloat64(texHeight) }
        }

    def loadTextureRegistry(manifest: List[GameEngine.TextureEntry]): GameEngine.TextureRegistry \ IO =
        List.foldLeft((registry, entry) -> {
            let texInfo = loadTexture(entry#path, entry#hasAlpha);
            println("  ${entry#path} loaded (${texInfo#width}x${texInfo#height})");
            Map.insert(entry#name, texInfo, registry)
        }, Map.empty(), manifest)

    // ========================================================================
    // Key Mapping (GameEngine.Key → GLFW key code)
    // ========================================================================

    def keyToGlfw(key: GameEngine.Key): Int32 = match key {
        case GameEngine.Key.W         => 87
        case GameEngine.Key.A         => 65
        case GameEngine.Key.S         => 83
        case GameEngine.Key.D         => 68
        case GameEngine.Key.Z         => 90
        case GameEngine.Key.Up        => 265
        case GameEngine.Key.Down      => 264
        case GameEngine.Key.Left      => 263
        case GameEngine.Key.Right     => 262
        case GameEngine.Key.Enter     => 257
        case GameEngine.Key.Space     => 32
        case GameEngine.Key.Escape    => 256
        case GameEngine.Key.F1        => 290
        case GameEngine.Key.LeftShift => 340
        case GameEngine.Key.LeftCtrl  => 341
        case GameEngine.Key.LeftSuper => 343
    }

    // ========================================================================
    // Mouse Button Mapping (GameEngine.MouseButton → GLFW mouse button code)
    // ========================================================================

    def mouseButtonToGlfw(button: GameEngine.MouseButton): Int32 = match button {
        case GameEngine.MouseButton.Left   => 0
        case GameEngine.MouseButton.Right  => 1
        case GameEngine.MouseButton.Middle => 2
    }

    // ========================================================================
    // Cursor Mapping (GameEngine.Cursor → GLFW standard cursor shape code)
    // ========================================================================
    //
    // GLFW 3.3 系では NWSE / NESW の対角リサイズカーソルが提供されないため、
    // 4 隅ハンドル用の AllResize には十字カーソル（CROSSHAIR_CURSOR）で代用する

    def cursorShapeToGlfw(cursor: GameEngine.Cursor): Int32 = match cursor {
        case GameEngine.Cursor.Default   => 0x36001  // GLFW_ARROW_CURSOR
        case GameEngine.Cursor.HResize   => 0x36005  // GLFW_HRESIZE_CURSOR
        case GameEngine.Cursor.VResize   => 0x36006  // GLFW_VRESIZE_CURSOR
        case GameEngine.Cursor.AllResize => 0x36003  // GLFW_CROSSHAIR_CURSOR
    }

    // ========================================================================
    // Sprite Renderer
    // ========================================================================

    def initSpriteRenderer(): (Int32, Int32) \ IO =
        let vao = GL30.glGenVertexArrays();
        let vbo = GL15.glGenBuffers();
        let vertices = Array#{
            0.0f32, 1.0f32, 0.0f32, 1.0f32,
            1.0f32, 0.0f32, 1.0f32, 0.0f32,
            0.0f32, 0.0f32, 0.0f32, 0.0f32,
            0.0f32, 1.0f32, 0.0f32, 1.0f32,
            1.0f32, 1.0f32, 1.0f32, 1.0f32,
            1.0f32, 0.0f32, 1.0f32, 0.0f32
        } @ Static;
        GL30.glBindVertexArray(vao);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, vbo);
        GL15.glBufferData(GL15.GL_ARRAY_BUFFER, vertices, GL15.GL_STATIC_DRAW);
        GL20.glEnableVertexAttribArray(0);
        GL20.glVertexAttribPointer(0, 4, GL11.GL_FLOAT, false, 16, 0i64);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        GL30.glBindVertexArray(0);
        (vao, vbo)

    def setProjectionMatrix(shader: Int32, width: Float64, height: Float64): Unit \ IO =
        GL20.glUseProgram(shader);
        let left = 0.0;
        let right = width;
        let bottom = height;
        let top = 0.0;
        let proj = Array#{
            f32(2.0 / (right - left)), 0.0f32, 0.0f32, 0.0f32,
            0.0f32, f32(2.0 / (top - bottom)), 0.0f32, 0.0f32,
            0.0f32, 0.0f32, -1.0f32, 0.0f32,
            f32(-1.0 * (right + left) / (right - left)), f32(-1.0 * (top + bottom) / (top - bottom)), 0.0f32, 1.0f32
        } @ Static;
        let loc = GL20.glGetUniformLocation(shader, "projection");
        GL20.glUniformMatrix4fv(loc, false, proj)

    def drawSprite(shader: Int32, texture: Int32, vao: Int32,
                   pos: Vec2.Vec2, size: Vec2.Vec2, color: Color,
                   alpha: Float32,
                   uvOff: Vec2.Vec2, uvSc: Vec2.Vec2, rot: Float64,
                   useTex: Bool): Unit \ IO =
        GL20.glUseProgram(shader);
        let c = cosF(rot);
        let s = sinF(rot);
        let sx = size#x;
        let sy = size#y;
        let tx = pos#x + sx / 2.0 - c * sx / 2.0 + s * sy / 2.0;
        let ty = pos#y + sy / 2.0 - s * sx / 2.0 - c * sy / 2.0;
        let model = Array#{
            f32(c * sx), f32(s * sx), 0.0f32, 0.0f32,
            f32(-1.0 * s * sy), f32(c * sy), 0.0f32, 0.0f32,
            0.0f32, 0.0f32, 1.0f32, 0.0f32,
            f32(tx), f32(ty), 0.0f32, 1.0f32
        } @ Static;
        let modelLoc = GL20.glGetUniformLocation(shader, "model");
        GL20.glUniformMatrix4fv(modelLoc, false, model);
        let colorLoc = GL20.glGetUniformLocation(shader, "spriteColor");
        GL20.glUniform3f(colorLoc, color#r, color#g, color#b);
        let alphaLoc = GL20.glGetUniformLocation(shader, "spriteAlpha");
        GL20.glUniform1f(alphaLoc, alpha);
        let uvOffsetLoc = GL20.glGetUniformLocation(shader, "uvOffset");
        GL20.glUniform2f(uvOffsetLoc, f32(uvOff#x), f32(uvOff#y));
        let uvScaleLoc = GL20.glGetUniformLocation(shader, "uvScale");
        GL20.glUniform2f(uvScaleLoc, f32(uvSc#x), f32(uvSc#y));
        let useTexLoc = GL20.glGetUniformLocation(shader, "useTexture");
        GL20.glUniform1i(useTexLoc, if (useTex) 1 else 0);
        if (useTex) {
            GL13.glActiveTexture(GL13.GL_TEXTURE0);
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, texture)
        } else ();
        GL30.glBindVertexArray(vao);
        GL11.glDrawArrays(GL11.GL_TRIANGLES, 0, 6);
        GL30.glBindVertexArray(0)

    // ========================================================================
    // Viewport Calculation (Stretch Mode)
    // ========================================================================

    /// デザイン解像度のアスペクト比を維持しつつ、フレームバッファに収まる最大矩形を計算する。
    /// 戻り値: (vpX, vpY, vpW, vpH)
    def calcViewport(fbW: Int32, fbH: Int32, designW: Float64, designH: Float64): (Int32, Int32, Int32, Int32) =
        let designAspect = designW / designH;
        let windowAspect = Int32.toFloat64(fbW) / Int32.toFloat64(fbH);
        if (windowAspect > designAspect) {
            // ピラーボックス（左右黒帯）
            let vpH = fbH;
            let vpW = floatToInt32(Int32.toFloat64(fbH) * designAspect);
            let vpX = (fbW - vpW) / 2;
            (vpX, 0, vpW, vpH)
        } else {
            // レターボックス（上下黒帯）
            let vpW = fbW;
            let vpH = floatToInt32(Int32.toFloat64(fbW) / designAspect);
            let vpY = (fbH - vpH) / 2;
            (0, vpY, vpW, vpH)
        }

    /// ビューポート計算・レターボックス処理を含むフレーム描画処理。
    /// render ハンドラとリサイズコールバックの両方から呼ばれる。
    def renderFrame(shader: Int32, vao: Int32, registry: GameEngine.TextureRegistry,
                    clearColor: Color, designW: Float64, designH: Float64,
                    fbW: Int32, fbH: Int32, drawables: List[GameEngine.Drawable]): Unit \ IO =
        if (fbW > 0 and fbH > 0) {
            let (vpX, vpY, vpW, vpH) = calcViewport(fbW, fbH, designW, designH);
            // フレームバッファ全体を黒でクリア（レターボックス/ピラーボックス領域）
            GL11.glViewport(0, 0, fbW, fbH);
            GL11.glClearColor(0.0f32, 0.0f32, 0.0f32, 1.0f32);
            GL11.glClear(GL11.GL_COLOR_BUFFER_BIT);
            // ゲーム領域にビューポートを設定
            GL11.glViewport(vpX, vpY, vpW, vpH);
            GL11.glEnable(GL11.GL_SCISSOR_TEST);
            GL11.glScissor(vpX, vpY, vpW, vpH);
            GL11.glClearColor(clearColor#r, clearColor#g, clearColor#b, 1.0f32);
            GL11.glClear(GL11.GL_COLOR_BUFFER_BIT);
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            List.forEach(drawable -> {
                if (String.isEmpty(drawable#texture)) {
                    // テクスチャなし（ColorRect）: scale をそのままピクセルサイズとして使う
                    let displaySize: Vec2.Vec2 = drawable#scale;
                    drawSprite(shader, 0, vao, drawable#position, displaySize, drawable#color, drawable#alpha, drawable#uvOffset, drawable#uvScale, drawable#rotation, false)
                } else {
                    match Map.get(drawable#texture, registry) {
                        case Some(texInfo) =>
                            let displayW = texInfo#width * drawable#scale#x;
                            let displayH = texInfo#height * drawable#scale#y;
                            let displaySize: Vec2.Vec2 = {x = displayW, y = displayH};
                            let pos: Vec2.Vec2 = if (drawable#centered)
                                {x = drawable#position#x - displayW / 2.0, y = drawable#position#y - displayH / 2.0}
                            else
                                drawable#position;
                            drawSprite(shader, texInfo#id, vao, pos, displaySize, drawable#color, drawable#alpha, drawable#uvOffset, drawable#uvScale, drawable#rotation, true)
                        case None => ()
                    }
                }
            }, drawables)
        } else ()

    // ========================================================================
    // Font Atlas Baking (STBTruetype)
    // ========================================================================

    def bakeFontAtlas(entry: GameEngine.FontEntry): (FontAtlas, GameEngine.TextureInfo) \ IO =
        let bitmapSize = 512;
        let charCount = 96;   // ASCII 32-127
        let firstChar = 32;

        // フォントファイルを ByteBuffer に読み込む
        let fis = new FileInputStream(entry#path);
        let fontBytes = fis.readAllBytes();
        fis.close();
        let fontBuffer = BufferUtils.createByteBuffer(Array.length(fontBytes));
        discard fontBuffer.put(fontBytes);
        discard fontBuffer.flip();

        // フォント情報を初期化し、em ベースの補正サイズを算出
        // STBTruetype: ScaleForPixelHeight → ascent-descent = fontSize
        // Godot/FreeType: em ベース → 1em = fontSize
        // フォントの ascent-descent > unitsPerEm の場合、STBTruetype は小さくなるため補正が必要
        let fontInfo = STBTTFontinfo.malloc();
        discard STBTruetype.stbtt_InitFont(fontInfo, fontBuffer);
        let emScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForMappingEmToPixels(fontInfo, f32(entry#fontSize)));
        let phScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForPixelHeight(fontInfo, f32(entry#fontSize)));
        let bakeSize = entry#fontSize * emScale / phScale;

        // フォントの正式メトリクスを取得（hhea テーブル: ascent/descent/lineGap）
        // em スケールで算出（Godot/FreeType 互換）
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

        // em 補正済みサイズでフォントを焼き込む
        discard fontBuffer.position(0);
        let cdata = STBTTBakedChar.malloc(charCount);
        let bitmap = BufferUtils.createByteBuffer(bitmapSize * bitmapSize);
        discard STBTruetype.stbtt_BakeFontBitmap(fontBuffer, f32(bakeSize), bitmap, bitmapSize, bitmapSize, firstChar, cdata);

        // GL_RED テクスチャとしてアップロード + swizzle で RGBA 化
        discard bitmap.position(0);
        let texId = GL11.glGenTextures();
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, texId);
        GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL30.GL_R8, bitmapSize, bitmapSize, 0, GL11.GL_RED, GL11.GL_UNSIGNED_BYTE, bitmap);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_LINEAR);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_LINEAR);
        // Swizzle: (ONE, ONE, ONE, RED) → 白色テキスト + alpha = グレースケール値
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_R, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_G, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_B, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_A, GL11.GL_RED);

        // グリフメトリクスを構築（静的アクセサで各フィールドを取得）
        // グリフは bakeSize で焼かれているが、atlas#fontSize = entry#fontSize (em ベース)
        // → Label2D の scale = 1.0 でそのまま em ベースの表示サイズになる
        let bitmapSizeF = Int32.toFloat64(bitmapSize);
        let baseAddr = cdata.address();
        let structSize = 20i64;   // STBTTBakedChar: 4 shorts (8B) + 3 floats (12B) = 20B
        let glyphs = List.range(0, charCount) |> List.foldLeft((acc, i) -> {
            let cp = firstChar + i;
            let addr = baseAddr + Int32.toInt64(i) * structSize;
            let x0 = Int32.toFloat64(Int16.toInt32(STBTTBakedChar.nx0(addr)));
            let y0 = Int32.toFloat64(Int16.toInt32(STBTTBakedChar.ny0(addr)));
            let x1 = Int32.toFloat64(Int16.toInt32(STBTTBakedChar.nx1(addr)));
            let y1 = Int32.toFloat64(Int16.toInt32(STBTTBakedChar.ny1(addr)));
            let gm: TextLayout.GlyphMetrics = {
                xOff = Float32.toFloat64(STBTTBakedChar.nxoff(addr)),
                yOff = Float32.toFloat64(STBTTBakedChar.nyoff(addr)),
                glyphW = x1 - x0,
                glyphH = y1 - y0,
                advance = Float32.toFloat64(STBTTBakedChar.nxadvance(addr)),
                s0 = x0 / bitmapSizeF,
                t0 = y0 / bitmapSizeF,
                s1 = x1 / bitmapSizeF,
                t1 = y1 / bitmapSizeF
            };
            Map.insert(cp, gm, acc)
        }, Map.empty());

        cdata.free();

        let texName = "font_${entry#name}";
        let texInfo: GameEngine.TextureInfo = { id = texId, width = bitmapSizeF, height = bitmapSizeF };
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

    def bakeFontAtlases(manifest: List[GameEngine.FontEntry],
                        registry: GameEngine.TextureRegistry): (Map[String, FontAtlas], GameEngine.TextureRegistry) \ IO =
        List.foldLeft((acc, entry) -> {
            let (atlases, reg) = acc;
            let (atlas, texInfo) = bakeFontAtlas(entry);
            println("  Font '${entry#name}' baked (${atlas#textureName})");
            let newAtlases = Map.insert(entry#name, atlas, atlases);
            let newReg = Map.insert(atlas#textureName, texInfo, reg);
            (newAtlases, newReg)
        }, (Map.empty(), registry), manifest)

    // ========================================================================
    // Audio Loading
    // ========================================================================

    /// OGG ファイルを STBVorbis でデコードし、OpenAL バッファにアップロードする
    def loadOggToALBuffer(path: String): Int32 \ IO =
        let stack = MemoryStack.stackPush();
        let channelsBuf = stack.mallocInt(1);
        let sampleRateBuf = stack.mallocInt(1);
        let pcm = STBVorbis.stb_vorbis_decode_filename(path, channelsBuf, sampleRateBuf);
        if (Object.isNull(pcm)) {
            discard MemoryStack.stackPop();
            bug!("Failed to decode OGG: ${path}")
        } else {
            let channels = channelsBuf.get(0);
            let sampleRate = sampleRateBuf.get(0);
            discard MemoryStack.stackPop();
            let format = if (channels == 1) AL10.AL_FORMAT_MONO16 else AL10.AL_FORMAT_STEREO16;
            let buffer = AL10.alGenBuffers();
            AL10.alBufferData(buffer, format, pcm, sampleRate);
            MemoryUtil.memFree(pcm);
            buffer
        }

    /// WAV ファイルをパースし、OpenAL バッファにアップロードする
    def loadWavToALBuffer(path: String): Int32 \ IO =
        let wavBytes = Files.readAllBytes(Paths.get(path));
        let hdr = ByteBuffer.wrap(wavBytes);
        discard hdr.order(ByteOrder.LITTLE_ENDIAN);
        let channels = Int16.toInt32(hdr.getShort(22));
        let sampleRate = hdr.getInt(24);
        let bitsPerSample = Int16.toInt32(hdr.getShort(34));
        let dataOffset = match AudioUtil.findDataChunkOffset(i -> hdr.get(i), i -> hdr.getInt(i), hdr.limit(), 12) {
            case Some(off) => off
            case None      => bug!("WAV data chunk not found: ${path}")
        };
        let dataSize = hdr.getInt(dataOffset + 4);
        let pcmStart = dataOffset + 8;
        let pcmBuf = MemoryUtil.memAlloc(dataSize);
        discard pcmBuf.put(wavBytes, pcmStart, dataSize);
        discard pcmBuf.flip();
        let format = AudioUtil.alFormat(channels, bitsPerSample);
        let buffer = AL10.alGenBuffers();
        AL10.alBufferData(buffer, format, pcmBuf, sampleRate);
        MemoryUtil.memFree(pcmBuf);
        buffer

    /// サウンドマニフェストから全音声を読み込み、AudioRegistry（名前 → OpenAL ソース ID）を返す
    def loadAudioRegistry(manifest: List[GameEngine.AudioEntry]): GameEngine.AudioRegistry \ IO =
        List.foldLeft((registry, entry) -> {
            let buffer = if (String.endsWith({suffix = ".ogg"}, entry#path))
                loadOggToALBuffer(entry#path)
            else
                loadWavToALBuffer(entry#path);
            let source = AL10.alGenSources();
            AL10.alSourcei(source, AL10.AL_BUFFER, buffer);
            AL10.alSourcei(source, AL10.AL_LOOPING, if (entry#looping) AL10.AL_TRUE else AL10.AL_FALSE);
            println("  ${entry#path} loaded");
            Map.insert(entry#name, source, registry)
        }, Map.empty(), manifest)

    // ========================================================================
    // LWJGL Handler for GameEngine.Game effect
    // ========================================================================

    pub def withLwjgl(config: GameEngine.EngineConfig, f: Unit -> a \ ef): a \ ef - GameEngine.Game - GameEngine.Audio + IO =
        if (not GLFW.glfwInit()) {
            println("GLFW init failed");
            bug!("GLFW failed")
        } else ();

        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MAJOR, 3);
        GLFW.glfwWindowHint(GLFW.GLFW_CONTEXT_VERSION_MINOR, 3);
        GLFW.glfwWindowHint(GLFW.GLFW_OPENGL_PROFILE, GLFW.GLFW_OPENGL_CORE_PROFILE);
        GLFW.glfwWindowHint(GLFW.GLFW_OPENGL_FORWARD_COMPAT, GL11.GL_TRUE);
        GLFW.glfwWindowHint(GLFW.GLFW_RESIZABLE, GL11.GL_TRUE);

        let window = GLFW.glfwCreateWindow(config#screenWidth, config#screenHeight, config#title, MemoryUtil.NULL, MemoryUtil.NULL);
        GLFW.glfwMakeContextCurrent(window);
        GLFW.glfwSwapInterval(1);
        discard GL.createCapabilities();

        let fbStack = MemoryStack.stackPush();
        let fbWidthBuf = fbStack.mallocInt(1);
        let fbHeightBuf = fbStack.mallocInt(1);
        GLFW.glfwGetFramebufferSize(window, fbWidthBuf, fbHeightBuf);
        let fbWidth = fbWidthBuf.get(0);
        let fbHeight = fbHeightBuf.get(0);
        discard MemoryStack.stackPop();
        println("Framebuffer size: ${fbWidth}x${fbHeight}");

        GL11.glEnable(GL11.GL_BLEND);
        GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);

        let screenW = Int32.toFloat64(config#screenWidth);
        let screenH = Int32.toFloat64(config#screenHeight);

        let shader = createShaderProgram(vertexShaderSource(), fragmentShaderSource());
        setProjectionMatrix(shader, screenW, screenH);

        let (vao, _vbo) = initSpriteRenderer();

        println("Loading textures...");
        let registry0 = loadTextureRegistry(config#textureManifest);

        println("Baking font atlases...");
        let (fontAtlases, registry) = bakeFontAtlases(config#fontManifest, registry0);

        // ===== OpenAL audio init =====
        println("Initializing audio...");
        let alDevice = ALC10.nalcOpenDevice(MemoryUtil.NULL);
        if (alDevice == 0i64) {
            println("Failed to open OpenAL device");
            bug!("Failed to open OpenAL device")
        } else ();
        let alcCaps = ALC.createCapabilities(alDevice);
        let alContext = ALC10.nalcCreateContext(alDevice, MemoryUtil.NULL);
        if (alContext == 0i64) {
            println("Failed to create OpenAL context");
            bug!("Failed to create OpenAL context")
        } else ();
        if (not ALC10.alcMakeContextCurrent(alContext)) {
            println("Failed to make OpenAL context current");
            bug!("Failed to make OpenAL context current")
        } else ();
        discard AL.createCapabilities(alcCaps);

        println("  Loading sounds...");
        let audioRegistry = loadAudioRegistry(config#soundManifest);
        println("  Audio ready");

        let timeHolder = Array#{System.nanoTime()} @ Static;

        // リサイズ中の再描画用に最後のフレームの描画リストを保持する
        let drawablesHolder = Array#{(Nil: List[GameEngine.Drawable])} @ Static;

        // 4 種のスタンダードカーソルを起動時に作成して再利用する。
        // setCursor 呼び出しの度に都度作成 / 破棄すると重く、リーク源にもなる
        let arrowCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.Default));
        let hResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.HResize));
        let vResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.VResize));
        let allResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.AllResize));
        // 同じ Cursor を毎フレーム渡されたときに glfwSetCursor を抑制するためのキャッシュ
        let lastCursorHolder = Array#{(GameEngine.Cursor.Default: GameEngine.Cursor)} @ Static;
        let cursorOf = cursor -> match cursor {
            case GameEngine.Cursor.Default   => arrowCursor
            case GameEngine.Cursor.HResize   => hResizeCursor
            case GameEngine.Cursor.VResize   => vResizeCursor
            case GameEngine.Cursor.AllResize => allResizeCursor
        };

        // macOS ではリサイズ中に glfwPollEvents がブロックされるため、
        // フレームバッファサイズ変更コールバックで再描画を行う
        discard GLFW.glfwSetFramebufferSizeCallback(window, new GLFWFramebufferSizeCallbackI {
            def invoke(_this: GLFWFramebufferSizeCallbackI, cbWindow: Int64, width: Int32, height: Int32): Unit \ IO = {
                renderFrame(shader, vao, registry, config#clearColor, screenW, screenH,
                            width, height, Array.get(0, drawablesHolder));
                GLFW.glfwSwapBuffers(cbWindow)
            }
        });

        let result = run {
            f()
        } with handler GameEngine.Audio {
            def playAudio(name, k) = {
                match Map.get(name, audioRegistry) {
                    case Some(src) => AL10.alSourceStop(src); AL10.alSourcePlay(src)
                    case None      => ()
                };
                k(())
            }
            def stopAudio(name, k) = {
                match Map.get(name, audioRegistry) {
                    case Some(src) => AL10.alSourceStop(src)
                    case None      => ()
                };
                k(())
            }
        } with handler GameEngine.Game {
            def render(drawables, k) = {
                Array.put(drawables, 0, drawablesHolder);
                let stack = MemoryStack.stackPush();
                let wBuf = stack.mallocInt(1);
                let hBuf = stack.mallocInt(1);
                GLFW.glfwGetFramebufferSize(window, wBuf, hBuf);
                let fbW = wBuf.get(0);
                let fbH = hBuf.get(0);
                discard MemoryStack.stackPop();
                renderFrame(shader, vao, registry, config#clearColor, screenW, screenH, fbW, fbH, drawables);
                GLFW.glfwSwapBuffers(window);
                k(())
            }
            def shouldClose(k) = {
                GLFW.glfwPollEvents();
                k(GLFW.glfwWindowShouldClose(window))
            }
            def getDeltaTime(k) = {
                let currentTime = System.nanoTime();
                let prev = Array.get(0, timeHolder);
                Array.put(currentTime, 0, timeHolder);
                let dtNanos = currentTime - prev;
                let dtf = Int64.toFloat64(dtNanos) / 1000000000.0;
                k(Float64.min(dtf, config#maxDeltaTime))
            }
            def isKeyPressed(key, k) = {
                let code = keyToGlfw(key);
                k(GLFW.glfwGetKey(window, code) == 1)
            }
            def getMousePosition(k) = {
                let mStack = MemoryStack.stackPush();
                let xBuf = mStack.mallocDouble(1);
                let yBuf = mStack.mallocDouble(1);
                GLFW.glfwGetCursorPos(window, xBuf, yBuf);
                let cursorX = xBuf.get(0);
                let cursorY = yBuf.get(0);
                discard MemoryStack.stackPop();
                // ウィンドウサイズからデザイン座標に変換
                let wStack = MemoryStack.stackPush();
                let winW = wStack.mallocInt(1);
                let winH = wStack.mallocInt(1);
                GLFW.glfwGetWindowSize(window, winW, winH);
                let windowW = Int32.toFloat64(winW.get(0));
                let windowH = Int32.toFloat64(winH.get(0));
                discard MemoryStack.stackPop();
                let designX = cursorX / windowW * screenW;
                let designY = cursorY / windowH * screenH;
                k({x = designX, y = designY})
            }
            def isMouseButtonPressed(button, k) = {
                let code = mouseButtonToGlfw(button);
                k(GLFW.glfwGetMouseButton(window, code) == 1)
            }
            def getFontAtlas(name, k) = {
                match Map.get(name, fontAtlases) {
                    case Some(atlas) => k(atlas)
                    case None => bug!("Font atlas not found: ${name}")
                }
            }
            def getViewportRect(k) = {
                k({position = Vec2.zero(), size = {x = screenW, y = screenH}})
            }
            def getTextureInfo(name, k) = {
                k(Map.get(name, registry))
            }
            def setCursor(cursor, k) = {
                let prev = Array.get(0, lastCursorHolder);
                if (prev != cursor) {
                    GLFW.glfwSetCursor(window, cursorOf(cursor));
                    Array.put(cursor, 0, lastCursorHolder)
                } else ();
                k(())
            }
        };

        // セッション終了時にカーソルハンドルを開放
        GLFW.glfwDestroyCursor(arrowCursor);
        GLFW.glfwDestroyCursor(hResizeCursor);
        GLFW.glfwDestroyCursor(vResizeCursor);
        GLFW.glfwDestroyCursor(allResizeCursor);

        // OpenAL cleanup
        Map.forEach((_, src) -> AL10.alDeleteSources(src), audioRegistry);
        ALC10.alcDestroyContext(alContext);
        discard ALC10.alcCloseDevice(alDevice);

        Callbacks.glfwFreeCallbacks(window);
        GLFW.glfwDestroyWindow(window);
        GLFW.glfwTerminate();
        result
}
