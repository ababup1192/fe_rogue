// LWJGL rendering backend — handles GameEngine.Game effect with OpenGL (minimal)

mod LwjglLayer {
    import org.lwjgl.glfw.GLFW
    import org.lwjgl.glfw.Callbacks
    import org.lwjgl.glfw.GLFWFramebufferSizeCallbackI
    import org.lwjgl.glfw.GLFWMouseButtonCallbackI
    import org.lwjgl.glfw.GLFWScrollCallbackI
    import org.lwjgl.opengl.GL
    import org.lwjgl.opengl.GL11
    import org.lwjgl.opengl.GL13
    import org.lwjgl.opengl.GL15
    import org.lwjgl.opengl.GL20
    import org.lwjgl.opengl.GL30
    import org.lwjgl.opengl.GL33
    import org.lwjgl.opengl.GL31
    import org.lwjgl.stb.STBImage
    import org.lwjgl.stb.STBTruetype
    import org.lwjgl.stb.STBTTBakedChar
    import org.lwjgl.stb.STBTTPackedchar
    import org.lwjgl.stb.STBTTPackContext
    import org.lwjgl.stb.STBTTPackRange
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

    def tileVertexShaderSource(): String =
        "#version 330 core\n" +
        "layout (location = 0) in vec4 vertex;\n" +
        "layout (location = 1) in vec2 instPos;\n" +
        "layout (location = 2) in vec2 instUVO;\n" +
        "layout (location = 3) in vec2 instUVS;\n" +
        "layout (location = 4) in float instA;\n" +
        "out vec2 TexCoords;\n" +
        "out float FragAlpha;\n" +
        "uniform mat4 projection;\n" +
        "uniform vec2 layerPos;\n" +
        "uniform float tileSize;\n" +
        "uniform vec2 tileScale;\n" +
        "void main() {\n" +
        "    vec2 screenPos = layerPos + (instPos + vertex.xy * tileSize) * tileScale;\n" +
        "    gl_Position = projection * vec4(screenPos, 0.0, 1.0);\n" +
        "    TexCoords = instUVO + vertex.zw * instUVS;\n" +
        "    FragAlpha = instA;\n" +
        "}\n"

    def tileFragmentShaderSource(): String =
        "#version 330 core\n" +
        "in vec2 TexCoords;\n" +
        "in float FragAlpha;\n" +
        "out vec4 color;\n" +
        "uniform sampler2D image;\n" +
        "uniform vec3 layerColor;\n" +
        "void main() {\n" +
        "    vec4 t = texture(image, TexCoords);\n" +
        "    color = vec4(layerColor * t.rgb, t.a * FragAlpha);\n" +
        "    if (color.a < 0.01) discard;\n" +
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
        case GameEngine.Key.X         => 88
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
    // GLFW 3.4（LWJGL 3.3.4 に同梱）の cursor shape を使用する。
    // NWSE / NESW の対角リサイズと ResizeAll は 3.4 で追加された

    def cursorShapeToGlfw(cursor: GameEngine.Cursor): Int32 = match cursor {
        case GameEngine.Cursor.Default    => 0x36001  // GLFW_ARROW_CURSOR
        case GameEngine.Cursor.HResize    => 0x36005  // GLFW_HRESIZE_CURSOR
        case GameEngine.Cursor.VResize    => 0x36006  // GLFW_VRESIZE_CURSOR
        case GameEngine.Cursor.AllResize  => 0x36009  // GLFW_RESIZE_ALL_CURSOR
        case GameEngine.Cursor.NWSEResize => 0x36007  // GLFW_RESIZE_NWSE_CURSOR
        case GameEngine.Cursor.NESWResize => 0x36008  // GLFW_RESIZE_NESW_CURSOR
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
    // Tile Map Instanced Rendering
    // ========================================================================

    /// タイルインスタンスデータを GPU VBO にアップロードする（一度だけ呼ぶ）。
    /// 各インスタンスは 7 floats: instPos(2) + instUVO(2) + instUVS(2) + instA(1) = 28 bytes
    def buildTileInstanceVBO(instances: List[GameEngine.TileInstance]): Int32 \ IO =
        let count = List.length(instances);
        let data = Array.empty(Static, count * 7);
        let _ = List.foldLeft((i, inst) -> {
            let base = i * 7;
            let px = inst#px;
            Array.put(f32(px#x),       base + 0, data);
            Array.put(f32(px#y),       base + 1, data);
            let uvOff = inst#uvOff;
            Array.put(f32(uvOff#x),    base + 2, data);
            Array.put(f32(uvOff#y),    base + 3, data);
            let uvSc = inst#uvSc;
            Array.put(f32(uvSc#x),     base + 4, data);
            Array.put(f32(uvSc#y),     base + 5, data);
            Array.put(inst#alpha,      base + 6, data);
            i + 1
        }, 0, instances);
        let vbo = GL15.glGenBuffers();
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, vbo);
        GL15.glBufferData(GL15.GL_ARRAY_BUFFER, data, GL15.GL_STATIC_DRAW);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        vbo

    /// TileMapLayer 専用 VAO を構築する。
    /// loc 0: 共有 quad VBO（vertex.xy = 局所座標, vertex.zw = UV）
    /// loc 1-4: per-instance VBO（divisor=1）
    def buildTileMapVAO(quadVBO: Int32, instanceVBO: Int32): Int32 \ IO =
        let vao = GL30.glGenVertexArrays();
        GL30.glBindVertexArray(vao);
        // 共有 quad VBO（loc 0）
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, quadVBO);
        GL20.glEnableVertexAttribArray(0);
        GL20.glVertexAttribPointer(0, 4, GL11.GL_FLOAT, false, 16, 0i64);
        // インスタンス VBO（loc 1-4, divisor=1）
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, instanceVBO);
        GL20.glEnableVertexAttribArray(1);
        GL20.glVertexAttribPointer(1, 2, GL11.GL_FLOAT, false, 28, 0i64);
        GL33.glVertexAttribDivisor(1, 1);
        GL20.glEnableVertexAttribArray(2);
        GL20.glVertexAttribPointer(2, 2, GL11.GL_FLOAT, false, 28, 8i64);
        GL33.glVertexAttribDivisor(2, 1);
        GL20.glEnableVertexAttribArray(3);
        GL20.glVertexAttribPointer(3, 2, GL11.GL_FLOAT, false, 28, 16i64);
        GL33.glVertexAttribDivisor(3, 1);
        GL20.glEnableVertexAttribArray(4);
        GL20.glVertexAttribPointer(4, 1, GL11.GL_FLOAT, false, 28, 24i64);
        GL33.glVertexAttribDivisor(4, 1);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        GL30.glBindVertexArray(0);
        vao

    /// 1 draw call で TileMapLayer のすべてのタイルを描画する。
    def drawTileMapInstanced(tileShader: Int32, texId: Int32, tileVao: Int32,
                              layerPos: Vec2.Vec2, tileSize: Float64,
                              tileScale: Vec2.Vec2,
                              color: Color, tileCount: Int32): Unit \ IO =
        GL20.glUseProgram(tileShader);
        let layerPosLoc = GL20.glGetUniformLocation(tileShader, "layerPos");
        GL20.glUniform2f(layerPosLoc, f32(layerPos#x), f32(layerPos#y));
        let tileSizeLoc = GL20.glGetUniformLocation(tileShader, "tileSize");
        GL20.glUniform1f(tileSizeLoc, f32(tileSize));
        let tileScaleLoc = GL20.glGetUniformLocation(tileShader, "tileScale");
        GL20.glUniform2f(tileScaleLoc, f32(tileScale#x), f32(tileScale#y));
        let colorLoc = GL20.glGetUniformLocation(tileShader, "layerColor");
        GL20.glUniform3f(colorLoc, color#r, color#g, color#b);
        GL13.glActiveTexture(GL13.GL_TEXTURE0);
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, texId);
        GL30.glBindVertexArray(tileVao);
        GL31.glDrawArraysInstanced(GL11.GL_TRIANGLES, 0, 6, tileCount);
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

    /// renderFrameMixed: sprites + tileMaps 混合版。tileMaps は zIndex 順で sprites の前に描画する。
    /// 通常の dungeon ユースケースでは TileMapLayer は背景（zIndex=0）として配置されるため、
    /// 単純化として TileMapLayer 群を先に、Sprite 群を後に描く。
    def renderFrameMixed(spriteShader: Int32, tileShader: Int32, vao: Int32,
                          registry: GameEngine.TextureRegistry,
                          clearColor: Color, designW: Float64, designH: Float64,
                          fbW: Int32, fbH: Int32,
                          sprites: List[GameEngine.Drawable],
                          tileMaps: List[GameEngine.TileMapRenderCmd]): Unit \ IO =
        if (fbW > 0 and fbH > 0) {
            let (vpX, vpY, vpW, vpH) = calcViewport(fbW, fbH, designW, designH);
            GL11.glViewport(0, 0, fbW, fbH);
            GL11.glClearColor(0.0f32, 0.0f32, 0.0f32, 1.0f32);
            GL11.glClear(GL11.GL_COLOR_BUFFER_BIT);
            GL11.glViewport(vpX, vpY, vpW, vpH);
            GL11.glEnable(GL11.GL_SCISSOR_TEST);
            GL11.glScissor(vpX, vpY, vpW, vpH);
            GL11.glClearColor(clearColor#r, clearColor#g, clearColor#b, 1.0f32);
            GL11.glClear(GL11.GL_COLOR_BUFFER_BIT);
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            // tileMaps: zIndex 昇順で 1 draw call ずつ描画
            let sortedTiles = List.sortBy(tm -> tm#zIndex, tileMaps);
            List.forEach(tm -> match Map.get(tm#textureName, registry) {
                case Some(texInfo) =>
                    drawTileMapInstanced(tileShader, texInfo#id, tm#tileVaoId,
                                         tm#position, tm#tileSize, tm#tileScale,
                                         tm#color, tm#tileCount)
                case None => ()
            }, sortedTiles);
            // sprites: zIndex 昇順で描画
            let sortedSprites = List.sortBy(d -> d#zIndex, sprites);
            List.forEach(drawable -> {
                if (String.isEmpty(drawable#texture)) {
                    let displaySize: Vec2.Vec2 = drawable#scale;
                    drawSprite(spriteShader, 0, vao, drawable#position, displaySize,
                               drawable#color, drawable#alpha, drawable#uvOffset,
                               drawable#uvScale, drawable#rotation, false)
                } else {
                    match Map.get(drawable#texture, registry) {
                        case Some(texInfo) =>
                            let displayW = texInfo#width * drawable#scale#x;
                            let displayH = texInfo#height * drawable#scale#y;
                            let displaySize: Vec2.Vec2 = {x = displayW, y = displayH};
                            let pos: Vec2.Vec2 = if (drawable#centered)
                                {x = drawable#position#x - displayW / 2.0,
                                 y = drawable#position#y - displayH / 2.0}
                            else drawable#position;
                            drawSprite(spriteShader, texInfo#id, vao, pos, displaySize,
                                       drawable#color, drawable#alpha, drawable#uvOffset,
                                       drawable#uvScale, drawable#rotation, true)
                        case None => ()
                    }
                }
            }, sortedSprites)
        } else ()

    // ========================================================================
    // Font Atlas Baking (STBTruetype)
    // ========================================================================

    /// アトラスにベイクする漢字 + UI 記号のコードポイント列を `fonts/joyo_kanji.txt`
    /// から読み込む。常用漢字 2,140 字 + ▼ などの UI 記号を 1 行にまとめたテキストで
    /// 管理し、Flix コードからは外している（ハードコードを避けて編集しやすくする）。
    /// `Char.toBmpCodePoint` は U+8000 以上で負値になるので 0xFFFF でマスクする。
    def kanjiCodepoints(): List[Int32] \ IO =
        let text = Files.readString(Paths.get("fonts/joyo_kanji.txt"));
        String.toList(text)
            |> List.map(ch -> Int32.bitwiseAnd(Char.toBmpCodePoint(ch), 0xFFFF))

    /// stbtt_PackFontRanges でベイクされる単一レンジの記述。
    /// `firstCp = 0` のとき `array` の個別 cp が使われる（stbtt の仕様）。
    type alias BakeRange = {
        firstCp = Int32,
        count   = Int32,
        cps     = List[Int32]   // firstCp != 0 ならダミー（連続範囲扱い）
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

    def bakeFontAtlas(entry: GameEngine.FontEntry): (FontAtlas, GameEngine.TextureInfo) \ IO =
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
        // STBTruetype: ScaleForPixelHeight → ascent-descent = fontSize
        // Godot/FreeType: em ベース → 1em = fontSize
        let fontInfo = STBTTFontinfo.malloc();
        discard STBTruetype.stbtt_InitFont(fontInfo, fontBuffer);
        let emScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForMappingEmToPixels(fontInfo, f32(entry#fontSize)));
        let phScale = Float32.toFloat64(
            STBTruetype.stbtt_ScaleForPixelHeight(fontInfo, f32(entry#fontSize)));
        let bakeSize = entry#fontSize * emScale / phScale;

        // フォントの正式メトリクスを取得（hhea: ascent/descent/lineGap, em スケール）
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

        // ベイク対象レンジ: ASCII (95) + 全角 ASCII (94) + CJK 記号 + ひらがな (160) + カタカナ (96) + 個別漢字
        let kanji      = kanjiCodepoints();
        let kanjiCount = List.length(kanji);
        let rangesSpec: List[BakeRange] =
            { firstCp = 0x20,   count = 95,         cps = Nil   } ::    // ASCII 0x20-0x7E
            { firstCp = 0xFF01, count = 94,         cps = Nil   } ::    // 全角 ASCII（Ａ-Ｚ ａ-ｚ ！？等）U+FF01-U+FF5E
            { firstCp = 0x3000, count = 160,        cps = Nil   } ::    // CJK 記号 (、。「」『』〜 等) + ひらがな U+3000-U+309F
            { firstCp = 0x30A0, count = 96,         cps = Nil   } ::    // カタカナ
            { firstCp = 0,      count = kanjiCount, cps = kanji } ::    // 漢字 + UI 記号（… ▼ 等の個別 cp）
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
            // firstCp = 0 の場合は array_of_unicode_codepoints を使う
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
        // ピクセルアートのドットフォント (BestTen-DOT 等) を双線形補間でぼかさない
        // ように NEAREST を採用。アンチエイリアスはフォント側のベイクに任せる。
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
        // Swizzle: (ONE, ONE, ONE, RED) → 白色テキスト + alpha = グレースケール値
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_R, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_G, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_B, GL11.GL_ONE);
        GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL33.GL_TEXTURE_SWIZZLE_A, GL11.GL_RED);

        // グリフメトリクスを Map に詰める。STBTTPackedchar は 28 byte (4 shorts + 5 floats)
        let structSize = 28i64;
        let glyphs = List.foldLeft((acc, pair) -> {
            let (spec, cdata) = pair;
            let baseAddr = cdata.address();
            let count = spec#count;
            // 連続レンジか配列レンジかで cp の取り出し方が変わる
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

        let window = GLFW.glfwCreateWindow(config#windowWidth, config#windowHeight, config#title, MemoryUtil.NULL, MemoryUtil.NULL);
        GLFW.glfwMakeContextCurrent(window);
        GLFW.glfwSwapInterval(1);
        // Sticky mouse buttons: 1 フレーム未満の press→release（macOS の
        // トラックパッド「タップでクリック」など）が polling で取りこぼされる
        // のを防ぐ。次回 `glfwGetMouseButton` 呼び出し時に PRESS を 1 度返してから
        // RELEASE に落ちる。これがないと Mac ユーザは "押してるつもりなのに
        // 反応しない" 体感になる。
        GLFW.glfwSetInputMode(window, GLFW.GLFW_STICKY_MOUSE_BUTTONS, GL11.GL_TRUE);
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

        let screenW = Int32.toFloat64(config#designWidth);
        let screenH = Int32.toFloat64(config#designHeight);

        let spriteShader = createShaderProgram(vertexShaderSource(), fragmentShaderSource());
        setProjectionMatrix(spriteShader, screenW, screenH);

        let tileShader = createShaderProgram(tileVertexShaderSource(), tileFragmentShaderSource());
        setProjectionMatrix(tileShader, screenW, screenH);

        let (vao, quadVBO) = initSpriteRenderer();

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

        // リサイズ中の再描画用に最後のフレームの描画コマンドを保持する（sprites + tileMaps）
        let renderStateHolder = Array#{((Nil: List[GameEngine.Drawable]),
                                         (Nil: List[GameEngine.TileMapRenderCmd]))} @ Static;

        // 6 種のスタンダードカーソルを起動時に作成して再利用する。
        // setCursor 呼び出しの度に都度作成 / 破棄すると重く、リーク源にもなる
        let arrowCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.Default));
        let hResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.HResize));
        let vResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.VResize));
        let allResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.AllResize));
        let nwseResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.NWSEResize));
        let neswResizeCursor = GLFW.glfwCreateStandardCursor(cursorShapeToGlfw(GameEngine.Cursor.NESWResize));
        // 同じ Cursor を毎フレーム渡されたときに glfwSetCursor を抑制するためのキャッシュ
        let lastCursorHolder = Array#{(GameEngine.Cursor.Default: GameEngine.Cursor)} @ Static;
        let cursorOf = cursor -> match cursor {
            case GameEngine.Cursor.Default    => arrowCursor
            case GameEngine.Cursor.HResize    => hResizeCursor
            case GameEngine.Cursor.VResize    => vResizeCursor
            case GameEngine.Cursor.AllResize  => allResizeCursor
            case GameEngine.Cursor.NWSEResize => nwseResizeCursor
            case GameEngine.Cursor.NESWResize => neswResizeCursor
        };

        // マウスホイールの y 方向 delta を 1 フレームぶん蓄積する。
        // consumeScrollDelta ハンドラが値を読み出して 0 に戻す。
        let scrollDeltaHolder = Array#{0.0} @ Static;
        discard GLFW.glfwSetScrollCallback(window, new GLFWScrollCallbackI {
            def invoke(_this: GLFWScrollCallbackI, _w: Int64, _xoffset: Float64, yoffset: Float64): Unit \ IO = {
                let prev = Array.get(0, scrollDeltaHolder);
                Array.put(prev + yoffset, 0, scrollDeltaHolder)
            }
        });

        // マウスボタンの「PRESS が来た」フラグを 1 フレームぶん保持する。
        // [0]=Left, [1]=Right, [2]=Middle. `shouldClose` が glfwPollEvents の **直前**
        // にリセットし、polling 中に来た callback が立てる。`isMouseButtonPressed` は
        // 物理状態 (`glfwGetMouseButton`) と OR を取って返す。
        // これが無いと、macOS トラックパッドの「タップでクリック」のように 1 フレーム
        // 未満で press→release が完結する入力を polling だけでは取りこぼす。
        let mouseButtonPressedHolder = Array#{false, false, false} @ Static;
        discard GLFW.glfwSetMouseButtonCallback(window, new GLFWMouseButtonCallbackI {
            def invoke(_this: GLFWMouseButtonCallbackI, _w: Int64,
                        button: Int32, action: Int32, _mods: Int32): Unit \ IO = {
                // GLFW_PRESS = 1。0..2 範囲外 (将来 GLFW が追加するボタン) は無視。
                if (action == 1 and button >= 0 and button <= 2)
                    Array.put(true, button, mouseButtonPressedHolder)
                else ()
            }
        });

        // macOS ではリサイズ中に glfwPollEvents がブロックされるため、
        // フレームバッファサイズ変更コールバックで再描画を行う
        discard GLFW.glfwSetFramebufferSizeCallback(window, new GLFWFramebufferSizeCallbackI {
            def invoke(_this: GLFWFramebufferSizeCallbackI, cbWindow: Int64, width: Int32, height: Int32): Unit \ IO = {
                let (sprites, tileMaps) = Array.get(0, renderStateHolder);
                renderFrameMixed(spriteShader, tileShader, vao, registry,
                                 config#clearColor, screenW, screenH,
                                 width, height, sprites, tileMaps);
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
            def setVolume(name, volume, k) = {
                match Map.get(name, audioRegistry) {
                    case Some(src) => AL10.alSourcef(src, AL10.AL_GAIN, volume)
                    case None      => ()
                };
                k(())
            }
        } with handler GameEngine.Game {
            def renderCommands(sprites, tileMaps, k) = {
                Array.put((sprites, tileMaps), 0, renderStateHolder);
                let stack = MemoryStack.stackPush();
                let wBuf = stack.mallocInt(1);
                let hBuf = stack.mallocInt(1);
                GLFW.glfwGetFramebufferSize(window, wBuf, hBuf);
                let fbW = wBuf.get(0);
                let fbH = hBuf.get(0);
                discard MemoryStack.stackPop();
                renderFrameMixed(spriteShader, tileShader, vao, registry,
                                 config#clearColor, screenW, screenH, fbW, fbH,
                                 sprites, tileMaps);
                GLFW.glfwSwapBuffers(window);
                k(())
            }
            def initTileBuffer(instances, k) = {
                let instanceVBO = buildTileInstanceVBO(instances);
                let tileVao = buildTileMapVAO(quadVBO, instanceVBO);
                k((tileVao, List.length(instances)))
            }
            def shouldClose(k) = {
                // glfwPollEvents の **直前** に PRESS フラグをリセット。
                // poll 中に発火した callback が立てたフラグが、その後の
                // `isMouseButtonPressed` 経路で 1 フレーム間だけ true として読まれ、
                // 次フレーム冒頭でクリアされる。
                Array.put(false, 0, mouseButtonPressedHolder);
                Array.put(false, 1, mouseButtonPressedHolder);
                Array.put(false, 2, mouseButtonPressedHolder);
                GLFW.glfwPollEvents();
                k(GLFW.glfwWindowShouldClose(window))
            }
            def getDeltaTime(k) = {
                let currentTime = System.nanoTime();
                let prev = Array.get(0, timeHolder);
                Array.put(currentTime, 0, timeHolder);
                let dtNanos = currentTime - prev;
                let dtSec = Int64.toFloat64(dtNanos) / 1000000000.0;
                let clamped = Float64.min(dtSec, config#maxDeltaTime);
                k(clamped |> Duration.seconds)
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
                // 物理状態 OR 当フレーム内に callback が観測した PRESS。
                // 後者は macOS トラックパッドのタップなど、polling 間隔より速い
                // press→release を取りこぼさないためのフォールバック。
                let polled = GLFW.glfwGetMouseButton(window, code) == 1;
                let buffered = Array.get(code, mouseButtonPressedHolder);
                k(polled or buffered)
            }
            def consumeScrollDelta(k) = {
                let v = Array.get(0, scrollDeltaHolder);
                Array.put(0.0, 0, scrollDeltaHolder);
                k(v)
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
        GLFW.glfwDestroyCursor(nwseResizeCursor);
        GLFW.glfwDestroyCursor(neswResizeCursor);

        // OpenAL cleanup
        Map.forEach((_, src) -> AL10.alDeleteSources(src), audioRegistry);
        ALC10.alcDestroyContext(alContext);
        discard ALC10.alcCloseDevice(alDevice);

        Callbacks.glfwFreeCallbacks(window);
        GLFW.glfwDestroyWindow(window);
        GLFW.glfwTerminate();
        result
}
