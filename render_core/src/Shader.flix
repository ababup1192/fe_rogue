// RenderShader — シェーダソース・コンパイル・projection 行列設定
//
// LwjglLayer.flix の以下を移植:
//   - vertexShaderSource / fragmentShaderSource (sprite 用)
//   - tileVertexShaderSource / tileFragmentShaderSource (tilemap instanced 用)
//   - compileShader / createShaderProgram
//   - setProjectionMatrix

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
        // styled (角丸＋枠) 単色矩形用。styleEnabled=false なら従来の単色塗り。
        "uniform bool styleEnabled;\n" +
        "uniform vec2 rectSize;\n" +
        "uniform float cornerRadius;\n" +
        "uniform float borderWidth;\n" +
        "uniform vec3 borderColor;\n" +
        "uniform float borderAlpha;\n" +
        // 角丸矩形 SDF (RenderSdf.roundedBox と同式)。p=中心からのオフセット, hsz=半サイズ, r=角半径。
        "float roundedBox(vec2 p, vec2 hsz, float r) {\n" +
        "    vec2 q = abs(p) - hsz + r;\n" +
        "    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;\n" +
        "}\n" +
        "void main() {\n" +
        "    if (useTexture) {\n" +
        "        color = vec4(spriteColor, spriteAlpha) * texture(image, TexCoords);\n" +
        "    } else if (styleEnabled) {\n" +
        "        vec2 hsz = rectSize * 0.5;\n" +
        "        vec2 p = TexCoords * rectSize - hsz;\n" +
        "        float aa = 1.0;\n" +                       // デザイン解像度の 1px AA
        // 角半径は矩形の最小半辺にクランプ (Godot StyleBoxFlat と同様、巨大値での破綻防止)
        "        float cr = clamp(cornerRadius, 0.0, min(hsz.x, hsz.y));\n" +
        "        float dOuter = roundedBox(p, hsz, cr);\n" +
        "        float outerCov = 1.0 - smoothstep(0.0, aa, dOuter);\n" +   // 矩形内=1 / 外=0
        "        float ri = max(cr - borderWidth, 0.0);\n" +
        "        vec2 hi = max(hsz - vec2(borderWidth), vec2(0.0));\n" +
        "        float dInner = roundedBox(p, hi, ri);\n" +
        "        float fillCov = 1.0 - smoothstep(0.0, aa, dInner);\n" +    // 塗り領域=1 / 枠+外=0
        "        vec3 rgb = mix(borderColor, spriteColor, fillCov);\n" +
        "        float a = mix(borderAlpha, spriteAlpha, fillCov) * outerCov;\n" +
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
