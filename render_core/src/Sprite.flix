// RenderSprite — スプライト / タイルマップの描画関数
//
// LwjglLayer.flix の以下を移植:
//   - initSpriteRenderer (共有 quad VBO/VAO)
//   - drawSprite
//   - buildTileInstanceVBO
//   - buildTileMapVAO
//   - drawTileMapInstanced

mod RenderSprite {
    import org.lwjgl.opengl.GL11
    import org.lwjgl.opengl.GL13
    import org.lwjgl.opengl.GL15
    import org.lwjgl.opengl.GL20
    import org.lwjgl.opengl.GL30
    import org.lwjgl.opengl.GL31
    import org.lwjgl.opengl.GL33

    /// 共有 quad の VAO/VBO を生成する。
    /// vertex layout: (x, y, u, v) の 4 floats。
    /// 戻り値: (vao, vbo)
    pub def initSpriteRenderer(): (Int32, Int32) \ IO =
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

    /// 1 スプライトを描画する。
    /// rotation は center 周りのラジアン回転。useTex = false で純色矩形。
    pub def drawSprite(shader: Int32, texture: Int32, vao: Int32,
                       pos: Vec2.Vec2, size: Vec2.Vec2, color: Color,
                       alpha: Float32,
                       uvOff: Vec2.Vec2, uvSc: Vec2.Vec2, rot: Float64,
                       useTex: Bool): Unit \ IO =
        let f32 = RenderUtil.f32;
        let cosF = RenderUtil.cosF;
        let sinF = RenderUtil.sinF;
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
    // Polygon (Polygon2D) Rendering — sprite シェーダを useTexture=0 で流用
    // ========================================================================

    /// 多角形描画用の VAO と動的 VBO を生成する。
    /// vertex layout は sprite と同じ (x, y, u, v) の 4 floats（u,v は未使用）。
    /// 戻り値: (vao, vbo)
    pub def initPolygonRenderer(): (Int32, Int32) \ IO =
        let vao = GL30.glGenVertexArrays();
        let vbo = GL15.glGenBuffers();
        GL30.glBindVertexArray(vao);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, vbo);
        GL20.glEnableVertexAttribArray(0);
        GL20.glVertexAttribPointer(0, 4, GL11.GL_FLOAT, false, 16, 0i64);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        GL30.glBindVertexArray(0);
        (vao, vbo)

    /// 凸多角形を単色で塗り潰す（GL_TRIANGLE_FAN）。頂点は既にスクリーン px。
    /// sprite シェーダを model=identity / useTexture=0 で流用する。
    pub def drawPolygon(spriteShader: Int32, polyVao: Int32, polyVbo: Int32,
                         verts: List[Vec2.Vec2], color: Color, alpha: Float32): Unit \ IO =
        let f32 = RenderUtil.f32;
        let n = List.length(verts);
        if (n < 3) () else {
            GL20.glUseProgram(spriteShader);
            let model = Array#{
                1.0f32, 0.0f32, 0.0f32, 0.0f32,
                0.0f32, 1.0f32, 0.0f32, 0.0f32,
                0.0f32, 0.0f32, 1.0f32, 0.0f32,
                0.0f32, 0.0f32, 0.0f32, 1.0f32
            } @ Static;
            let modelLoc = GL20.glGetUniformLocation(spriteShader, "model");
            GL20.glUniformMatrix4fv(modelLoc, false, model);
            let colorLoc = GL20.glGetUniformLocation(spriteShader, "spriteColor");
            GL20.glUniform3f(colorLoc, color#r, color#g, color#b);
            let alphaLoc = GL20.glGetUniformLocation(spriteShader, "spriteAlpha");
            GL20.glUniform1f(alphaLoc, alpha);
            let uvOffsetLoc = GL20.glGetUniformLocation(spriteShader, "uvOffset");
            GL20.glUniform2f(uvOffsetLoc, 0.0f32, 0.0f32);
            let uvScaleLoc = GL20.glGetUniformLocation(spriteShader, "uvScale");
            GL20.glUniform2f(uvScaleLoc, 1.0f32, 1.0f32);
            let useTexLoc = GL20.glGetUniformLocation(spriteShader, "useTexture");
            GL20.glUniform1i(useTexLoc, 0);
            let data = Array.empty(Static, n * 4);
            let _ = List.foldLeft((i, v) -> {
                let base = i * 4;
                Array.put(f32(v#x), base + 0, data);
                Array.put(f32(v#y), base + 1, data);
                Array.put(0.0f32,   base + 2, data);
                Array.put(0.0f32,   base + 3, data);
                i + 1
            }, 0, verts);
            GL30.glBindVertexArray(polyVao);
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, polyVbo);
            GL15.glBufferData(GL15.GL_ARRAY_BUFFER, data, GL15.GL_DYNAMIC_DRAW);
            GL11.glDrawArrays(GL11.GL_TRIANGLE_FAN, 0, n);
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
            GL30.glBindVertexArray(0)
        }

    // ========================================================================
    // Tile Map Instanced Rendering
    // ========================================================================

    /// タイルインスタンスデータを GPU VBO にアップロードする (一度だけ呼ぶ)。
    /// 各インスタンスは 7 floats: instPos(2) + instUVO(2) + instUVS(2) + instA(1) = 28 bytes
    pub def buildTileInstanceVBO(instances: List[RenderType.TileInstance]): Int32 \ IO =
        let f32 = RenderUtil.f32;
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
    /// loc 0: 共有 quad VBO (vertex.xy = 局所座標, vertex.zw = UV)
    /// loc 1-4: per-instance VBO (divisor=1)
    pub def buildTileMapVAO(quadVBO: Int32, instanceVBO: Int32): Int32 \ IO =
        let vao = GL30.glGenVertexArrays();
        GL30.glBindVertexArray(vao);
        // 共有 quad VBO (loc 0)
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, quadVBO);
        GL20.glEnableVertexAttribArray(0);
        GL20.glVertexAttribPointer(0, 4, GL11.GL_FLOAT, false, 16, 0i64);
        // インスタンス VBO (loc 1-4, divisor=1)
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
    pub def drawTileMapInstanced(tileShader: Int32, texId: Int32, tileVao: Int32,
                                  layerPos: Vec2.Vec2, tileSize: Float64,
                                  tileScale: Vec2.Vec2,
                                  color: Color, tileCount: Int32): Unit \ IO =
        let f32 = RenderUtil.f32;
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

}
