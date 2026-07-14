// RenderShader — 描画に使うシェーダのソース・コンパイル・投影行列の設定をまとめる。
// スプライト用とタイルマップ用のシェーダ準備を一箇所に閉じるので、上位は組み上がったものを使うだけでよい。
// 利用例: 起動時にシェーダを用意する / 画面の解像度に合わせて座標変換を設定する。

mod RenderShader {
    import org.lwjgl.opengl.GL11
    import org.lwjgl.opengl.GL20

    // ========================================================================
    // Shader Sources
    // ========================================================================

    pub def vertexShaderSource(): String =
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

    pub def fragmentShaderSource(): String =
        "#version 330 core\n" +
        "in vec2 TexCoords;\n" +
        "out vec4 color;\n" +
        "uniform sampler2D image;\n" +
        "uniform vec3 spriteColor;\n" +
        "uniform float spriteAlpha;\n" +
        "uniform bool useTexture;\n" +
        // SDF テキスト用。useTexture かつ sdfText のとき、テクスチャ .a を距離場として
        // smoothstep で輪郭を再構成する (任意サイズで縁がくっきり)。
        "uniform bool sdfText;\n" +
        // styled (角丸＋枠) 単色矩形用。styleEnabled=false なら従来の単色塗り。
        "uniform bool styleEnabled;\n" +
        "uniform vec2 rectSize;\n" +
        "uniform float cornerRadius;\n" +
        "uniform float borderWidth;\n" +
        "uniform vec3 borderColor;\n" +
        "uniform float borderAlpha;\n" +
        // 塗り領域に重ねる 45° 斜線ハッチ (CSS repeating-linear-gradient 相当)。hatchEnabled=false で従来の塗り。
        "uniform bool hatchEnabled;\n" +
        "uniform vec3 hatchColor;\n" +
        "uniform float hatchAlpha;\n" +
        "uniform float hatchWidth;\n" +
        "uniform float hatchPeriod;\n" +
        // 角丸矩形 SDF (RenderSdf.roundedBox と同式)。p=中心からのオフセット, hsz=半サイズ, r=角半径。
        "float roundedBox(vec2 p, vec2 hsz, float r) {\n" +
        "    vec2 q = abs(p) - hsz + r;\n" +
        "    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;\n" +
        "}\n" +
        "void main() {\n" +
        "    if (useTexture) {\n" +
        "        if (sdfText) {\n" +
        "            float d = texture(image, TexCoords).a;\n" +          // 距離場 (swizzle で R=alpha)
        "            float aa = fwidth(d);\n" +                            // 画面 px 基準の AA 幅
        "            float a = smoothstep(0.5 - aa, 0.5 + aa, d);\n" +
        "            if (a < 0.004) discard;\n" +
        "            color = vec4(spriteColor, spriteAlpha * a);\n" +
        "        } else {\n" +
        "            color = vec4(spriteColor, spriteAlpha) * texture(image, TexCoords);\n" +
        "        }\n" +
        "    } else if (styleEnabled) {\n" +
        "        vec2 hsz = rectSize * 0.5;\n" +
        "        vec2 p = TexCoords * rectSize - hsz;\n" +
        // 角半径は矩形の最小半辺にクランプ（巨大値を入れても形が破綻しないように）
        "        float cr = clamp(cornerRadius, 0.0, min(hsz.x, hsz.y));\n" +
        "        float dOuter = roundedBox(p, hsz, cr);\n" +
        // AA 幅は画面 px 基準 (fwidth)。カメラ zoom で rectSize が小さくなっても角丸が潰れない
        // （固定 1px AA だと縮小時に AA 帯が矩形全体を覆い、角丸が消えて四角に見える）。
        "        float aaO = max(fwidth(dOuter), 0.0001);\n" +
        "        float outerCov = 1.0 - smoothstep(0.0, aaO, dOuter);\n" +   // 矩形内=1 / 外=0
        "        float ri = max(cr - borderWidth, 0.0);\n" +
        "        vec2 hi = max(hsz - vec2(borderWidth), vec2(0.0));\n" +
        "        float dInner = roundedBox(p, hi, ri);\n" +
        "        float aaI = max(fwidth(dInner), 0.0001);\n" +
        "        float fillCov = 1.0 - smoothstep(0.0, aaI, dInner);\n" +    // 塗り領域=1 / 枠+外=0
        // 塗りベース。hatchEnabled なら 45° 斜線を塗りの上に over 合成してから枠と混ぜる。
        "        vec3 fillRgb = spriteColor;\n" +
        "        float fillA = spriteAlpha;\n" +
        "        if (hatchEnabled) {\n" +
        "            float hv = p.x - p.y;\n" +
        "            float m = mod(hv, hatchPeriod);\n" +                    // 縞の位相 (x-y で 45°)
        "            float haa = max(fwidth(hv), 0.0001);\n" +               // 画面 px 基準の縞 AA
        "            float sOn = smoothstep(0.0, haa, m) - smoothstep(hatchWidth, hatchWidth + haa, m);\n" +
        "            float sa = hatchAlpha * clamp(sOn, 0.0, 1.0);\n" +
        "            float outA = sa + fillA * (1.0 - sa);\n" +
        "            fillRgb = (outA > 0.0001) ? (hatchColor * sa + fillRgb * fillA * (1.0 - sa)) / outA : fillRgb;\n" +
        "            fillA = outA;\n" +
        "        }\n" +
        "        vec3 rgb = mix(borderColor, fillRgb, fillCov);\n" +
        "        float a = mix(borderAlpha, fillA, fillCov) * outerCov;\n" +
        "        if (a < 0.004) discard;\n" +
        "        color = vec4(rgb, a);\n" +
        "    } else {\n" +
        "        color = vec4(spriteColor, spriteAlpha);\n" +
        "    }\n" +
        "}\n"

    pub def tileVertexShaderSource(): String =
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

    pub def tileFragmentShaderSource(): String =
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

    /// instanced sprite 用の頂点シェーダ。1 体分の変換・UV・色をすべて
    /// instance 属性 (loc1-5) で受け取るので、uniform の設定なしに
    /// 1 回の draw call で何千体でも描ける。
    /// mat2(inst1.xy, inst1.zw) + inst2 は drawSprite の model 行列
    /// （回転×スケール＋平行移動）と同じ変換。
    pub def spriteInstancedVertexShaderSource(): String =
        "#version 330 core\n" +
        "layout (location = 0) in vec4 vertex;\n" +
        "layout (location = 1) in vec4 inst1;\n" +   // ワールド変換 2x2: (c*sx, s*sx, -s*sy, c*sy)
        "layout (location = 2) in vec2 inst2;\n" +   // 平行移動 (tx, ty)
        "layout (location = 3) in vec4 inst3;\n" +   // uvOffset.xy + uvScale.zw
        "layout (location = 4) in vec4 inst4;\n" +   // color.rgb + alpha
        "layout (location = 5) in vec2 inst5;\n" +   // useTexture, sdfText (0.0/1.0)
        "out vec2 TexCoords;\n" +
        "out vec4 InstColor;\n" +
        "out vec2 InstFlags;\n" +
        "uniform mat4 projection;\n" +
        "void main() {\n" +
        "    vec2 world = mat2(inst1.xy, inst1.zw) * vertex.xy + inst2;\n" +
        "    gl_Position = projection * vec4(world, 0.0, 1.0);\n" +
        "    TexCoords = vertex.zw * inst3.zw + inst3.xy;\n" +
        "    InstColor = inst4;\n" +
        "    InstFlags = inst5;\n" +
        "}\n"

    /// instanced sprite 用のフラグメントシェーダ。
    /// スタイル (角丸・枠・ハッチ) は持たない: style 付き矩形は従来の
    /// sprite シェーダで 1 枚ずつ描く（バッチに積む前に弾かれる）。
    /// 同じバッチ内の全 instance は useTexture/sdfText が揃う
    /// （テクスチャが同じなら font_ 判定も同じ）ので、分岐は実質一様。
    pub def spriteInstancedFragmentShaderSource(): String =
        "#version 330 core\n" +
        "in vec2 TexCoords;\n" +
        "in vec4 InstColor;\n" +
        "in vec2 InstFlags;\n" +
        "out vec4 color;\n" +
        "uniform sampler2D image;\n" +
        "void main() {\n" +
        "    if (InstFlags.x > 0.5) {\n" +
        "        if (InstFlags.y > 0.5) {\n" +
        "            float d = texture(image, TexCoords).a;\n" +          // 距離場 (swizzle で R=alpha)
        "            float aa = fwidth(d);\n" +                            // 画面 px 基準の AA 幅
        "            float a = smoothstep(0.5 - aa, 0.5 + aa, d);\n" +
        "            if (a < 0.004) discard;\n" +
        "            color = vec4(InstColor.rgb, InstColor.a * a);\n" +
        "        } else {\n" +
        "            color = InstColor * texture(image, TexCoords);\n" +
        "        }\n" +
        "    } else {\n" +
        "        color = InstColor;\n" +
        "    }\n" +
        "}\n"

    // ========================================================================
    // Shader Compilation
    // ========================================================================

    pub def compileShader(source: String, shaderType: Int32): Int32 \ IO =
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

    pub def createShaderProgram(vertexSrc: String, fragmentSrc: String): Int32 \ IO =
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
    // Uniform Locations
    // ========================================================================

    /// sprite シェーダの uniform location 一式。
    /// location はリンク後に不変。毎フレーム文字列で問い合わせると描画数×十数回の
    /// JNI 呼び出しになるため、起動時に 1 回だけ引いてレコードに詰めて持ち回る。
    pub type alias SpriteUniforms = {
        model = Int32,
        spriteColor = Int32,
        spriteAlpha = Int32,
        uvOffset = Int32,
        uvScale = Int32,
        useTexture = Int32,
        sdfText = Int32,
        styleEnabled = Int32,
        rectSize = Int32,
        cornerRadius = Int32,
        borderWidth = Int32,
        borderColor = Int32,
        borderAlpha = Int32,
        hatchEnabled = Int32,
        hatchColor = Int32,
        hatchAlpha = Int32,
        hatchWidth = Int32,
        hatchPeriod = Int32
    }

    /// tile シェーダの uniform location 一式。理由は `SpriteUniforms` と同じ。
    pub type alias TileUniforms = {
        layerPos = Int32,
        tileSize = Int32,
        tileScale = Int32,
        layerColor = Int32
    }

    pub def spriteUniformsOf(shader: Int32): SpriteUniforms \ IO =
        {
            model = GL20.glGetUniformLocation(shader, "model"),
            spriteColor = GL20.glGetUniformLocation(shader, "spriteColor"),
            spriteAlpha = GL20.glGetUniformLocation(shader, "spriteAlpha"),
            uvOffset = GL20.glGetUniformLocation(shader, "uvOffset"),
            uvScale = GL20.glGetUniformLocation(shader, "uvScale"),
            useTexture = GL20.glGetUniformLocation(shader, "useTexture"),
            sdfText = GL20.glGetUniformLocation(shader, "sdfText"),
            styleEnabled = GL20.glGetUniformLocation(shader, "styleEnabled"),
            rectSize = GL20.glGetUniformLocation(shader, "rectSize"),
            cornerRadius = GL20.glGetUniformLocation(shader, "cornerRadius"),
            borderWidth = GL20.glGetUniformLocation(shader, "borderWidth"),
            borderColor = GL20.glGetUniformLocation(shader, "borderColor"),
            borderAlpha = GL20.glGetUniformLocation(shader, "borderAlpha"),
            hatchEnabled = GL20.glGetUniformLocation(shader, "hatchEnabled"),
            hatchColor = GL20.glGetUniformLocation(shader, "hatchColor"),
            hatchAlpha = GL20.glGetUniformLocation(shader, "hatchAlpha"),
            hatchWidth = GL20.glGetUniformLocation(shader, "hatchWidth"),
            hatchPeriod = GL20.glGetUniformLocation(shader, "hatchPeriod")
        }

    pub def tileUniformsOf(shader: Int32): TileUniforms \ IO =
        {
            layerPos = GL20.glGetUniformLocation(shader, "layerPos"),
            tileSize = GL20.glGetUniformLocation(shader, "tileSize"),
            tileScale = GL20.glGetUniformLocation(shader, "tileScale"),
            layerColor = GL20.glGetUniformLocation(shader, "layerColor")
        }

    // ========================================================================
    // Projection Matrix
    // ========================================================================

    pub def setProjectionMatrix(shader: Int32, width: Float64, height: Float64): Unit \ IO =
        GL20.glUseProgram(shader);
        let left = 0.0;
        let right = width;
        let bottom = height;
        let top = 0.0;
        let proj = Array#{
            RenderUtil.f32(2.0 / (right - left)), 0.0f32, 0.0f32, 0.0f32,
            0.0f32, RenderUtil.f32(2.0 / (top - bottom)), 0.0f32, 0.0f32,
            0.0f32, 0.0f32, -1.0f32, 0.0f32,
            RenderUtil.f32(-1.0 * (right + left) / (right - left)),
            RenderUtil.f32(-1.0 * (top + bottom) / (top - bottom)),
            0.0f32, 1.0f32
        } @ Static;
        let loc = GL20.glGetUniformLocation(shader, "projection");
        GL20.glUniformMatrix4fv(loc, false, proj)

}
