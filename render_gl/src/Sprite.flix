// RenderSprite — スプライト1枚やタイルマップ1面を、実際に画面へ描く低レベルの描画関数。
// GL の頂点バッファ準備や描画命令をこの一箇所に閉じるので、上位はこれを呼ぶだけで絵を出せる。
// 利用例: キャラや弾の画像を描く / 敷き詰めた地形タイルをまとめて描く。

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

    /// blend に応じて GL のブレンド因子を切り替える。呼んだ後の描画から効く。
    /// Multiply は因子だけでは alpha 付きの正しい式にならないため、シェーダ側の
    /// premultiply（multiplyBlend uniform）とペアで dst×(1−a×(1−src)) を作る。
    pub def applyBlend(blend: DrawCmd.BlendMode): Unit \ IO =
        match blend {
            case DrawCmd.BlendMode.Normal   =>
                GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA)
            case DrawCmd.BlendMode.Add      =>
                GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE)
            case DrawCmd.BlendMode.Multiply =>
                GL11.glBlendFunc(GL11.GL_DST_COLOR, GL11.GL_ONE_MINUS_SRC_ALPHA)
        }

    /// multiplyBlend uniform に渡す値（Multiply のときだけ premultiply を有効化）。
    pub def multiplyFlag(blend: DrawCmd.BlendMode): Int32 =
        if (blend == DrawCmd.BlendMode.Multiply) 1 else 0

    /// 1 スプライトを描画する。
    /// rotation は center 周りのラジアン回転。useTex = false で純色矩形。
    /// uniforms は起動時に 1 回だけ引いた location 一式（RenderShader.spriteUniformsOf）。
    pub def drawSprite(shader: Int32, vao: Int32, uniforms: RenderShader.SpriteUniforms,
                        params: RenderType.DrawSpriteParams): Unit \ IO =
        // 1 レコードからローカルへ束ね直す（以降の描画ロジックは従来どおり）。
        let texture = params#texture;
        let pos     = params#position;
        let size    = params#scale;
        let color   = params#color;
        let alpha   = params#alpha;
        let uvOff   = params#uvOffset;
        let uvSc    = params#uvScale;
        let rot     = params#rotation;
        let useTex  = params#useTexture;
        let style   = params#style;
        let sdf     = params#sdf;
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
        GL20.glUniformMatrix4fv(uniforms#model, false, model);
        GL20.glUniform3f(uniforms#spriteColor, color#r, color#g, color#b);
        GL20.glUniform1f(uniforms#spriteAlpha, alpha);
        GL20.glUniform2f(uniforms#uvOffset, f32(uvOff#x), f32(uvOff#y));
        GL20.glUniform2f(uniforms#uvScale, f32(uvSc#x), f32(uvSc#y));
        GL20.glUniform1i(uniforms#useTexture, if (useTex) 1 else 0);
        // SDF テキスト uniform。テキスト以外は 0 にして GL state 持ち越しを防ぐ。
        GL20.glUniform1i(uniforms#sdfText, if (sdf) 1 else 0);
        // drawPolygon と同じシェーダを共有するため、premultiply スイッチも明示 0 にして持ち越しを防ぐ。
        GL20.glUniform1i(uniforms#multiplyBlend, 0);
        // 角丸＋枠スタイル uniform。Some のとき styleEnabled=1（単色矩形のみシェーダ側で適用）。
        match style {
            case Some(st) =>
                GL20.glUniform1i(uniforms#styleEnabled, 1);
                GL20.glUniform2f(uniforms#rectSize, f32(size#x), f32(size#y));
                GL20.glUniform1f(uniforms#cornerRadius, f32(st#cornerRadius));
                GL20.glUniform1f(uniforms#borderWidth, f32(st#borderWidth));
                GL20.glUniform3f(uniforms#borderColor, st#borderColor#r, st#borderColor#g, st#borderColor#b);
                GL20.glUniform1f(uniforms#borderAlpha, st#borderAlpha);
                // 斜線ハッチ uniform。幅・濃さ・周期がすべて正のときのみ有効化(SoftRaster と同じ判定)。
                let hatchOn = st#stripeWidth > 0.0 and st#stripeAlpha > 0.0f32 and st#stripePeriod > 0.0;
                GL20.glUniform1i(uniforms#hatchEnabled, if (hatchOn) 1 else 0);
                GL20.glUniform3f(uniforms#hatchColor, st#stripeColor#r, st#stripeColor#g, st#stripeColor#b);
                GL20.glUniform1f(uniforms#hatchAlpha, st#stripeAlpha);
                GL20.glUniform1f(uniforms#hatchWidth, f32(st#stripeWidth));
                GL20.glUniform1f(uniforms#hatchPeriod, f32(st#stripePeriod));
                GL20.glUniform1i(uniforms#hatchDir, st#stripeDir);
                // 市松 uniform。有効判定 (cell>0 かつ alpha>0) はシェーダ側で行う。
                GL20.glUniform3f(uniforms#checkerColor, st#checkerColor#r, st#checkerColor#g, st#checkerColor#b);
                GL20.glUniform1f(uniforms#checkerAlpha, st#checkerAlpha);
                GL20.glUniform1f(uniforms#checkerCell, f32(st#checkerCell))
            case None =>
                GL20.glUniform1i(uniforms#styleEnabled, 0);
                GL20.glUniform1i(uniforms#hatchEnabled, 0);
                GL20.glUniform1f(uniforms#checkerCell, 0.0f32)
        };
        if (useTex) {
            GL13.glActiveTexture(GL13.GL_TEXTURE0);
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, texture)
        } else ();
        GL30.glBindVertexArray(vao);
        GL11.glDrawArrays(GL11.GL_TRIANGLES, 0, 6);
        GL30.glBindVertexArray(0)

    // ========================================================================
    // Polygon (Polygon) Rendering — sprite シェーダを useTexture=0 で流用
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

    /// 単純多角形（凹あり可）を単色で塗り潰す。頂点は既にスクリーン px。
    /// 耳切り（Triangulate.triangles）で三角形化して GL_TRIANGLES で描くので、星のような
    /// 凹多角形も SoftRaster（スキャンライン塗り）と同じ絵になる。凸は従来と同じ見た目。
    /// sprite シェーダを model=identity / useTexture=0 で流用する。
    /// uniforms は起動時に 1 回だけ引いた location 一式（RenderShader.spriteUniformsOf）。
    pub def drawPolygon(spriteShader: Int32, polyVao: Int32, polyVbo: Int32,
                         uniforms: RenderShader.SpriteUniforms,
                         verts: List[Vec2.Vec2], color: Color, alpha: Float32,
                         blend: DrawCmd.BlendMode): Unit \ IO =
        let f32 = RenderUtil.f32;
        let flat = Triangulate.triangles(verts)
            |> List.flatMap(tri -> { let (a, b, c) = tri; a :: b :: c :: Nil });
        let n = List.length(flat);
        if (n < 3) () else {
            GL20.glUseProgram(spriteShader);
            applyBlend(blend);
            GL20.glUniform1i(uniforms#multiplyBlend, multiplyFlag(blend));
            let model = Array#{
                1.0f32, 0.0f32, 0.0f32, 0.0f32,
                0.0f32, 1.0f32, 0.0f32, 0.0f32,
                0.0f32, 0.0f32, 1.0f32, 0.0f32,
                0.0f32, 0.0f32, 0.0f32, 1.0f32
            } @ Static;
            GL20.glUniformMatrix4fv(uniforms#model, false, model);
            GL20.glUniform3f(uniforms#spriteColor, color#r, color#g, color#b);
            GL20.glUniform1f(uniforms#spriteAlpha, alpha);
            GL20.glUniform2f(uniforms#uvOffset, 0.0f32, 0.0f32);
            GL20.glUniform2f(uniforms#uvScale, 1.0f32, 1.0f32);
            GL20.glUniform1i(uniforms#useTexture, 0);
            // sprite シェーダ共有のため styleEnabled / hatchEnabled / checkerCell を明示 0 にして GL state 持ち越しを防ぐ。
            GL20.glUniform1i(uniforms#styleEnabled, 0);
            GL20.glUniform1i(uniforms#hatchEnabled, 0);
            GL20.glUniform1f(uniforms#checkerCell, 0.0f32);
            GL20.glUniform1i(uniforms#sdfText, 0);
            let data = Array.empty(Static, n * 4);
            let _ = List.foldLeft((i, v) -> {
                let base = i * 4;
                Array.put(f32(v#x), base + 0, data);
                Array.put(f32(v#y), base + 1, data);
                Array.put(0.0f32,   base + 2, data);
                Array.put(0.0f32,   base + 3, data);
                i + 1
            }, 0, flat);
            GL30.glBindVertexArray(polyVao);
            GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, polyVbo);
            GL15.glBufferData(GL15.GL_ARRAY_BUFFER, data, GL15.GL_DYNAMIC_DRAW);
            GL11.glDrawArrays(GL11.GL_TRIANGLES, 0, n);
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

    /// TileLayer 専用 VAO を構築する。
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

    /// 1 draw call で TileLayer のすべてのタイルを描画する。
    /// uniforms は起動時に 1 回だけ引いた location 一式（RenderShader.tileUniformsOf）。
    pub def drawTileMapInstanced(tileShader: Int32, texId: Int32, tileVao: Int32,
                                  uniforms: RenderShader.TileUniforms,
                                  layerPos: Vec2.Vec2, tileSize: Float64,
                                  tileScale: Vec2.Vec2,
                                  color: Color, tileCount: Int32): Unit \ IO =
        let f32 = RenderUtil.f32;
        GL20.glUseProgram(tileShader);
        GL20.glUniform2f(uniforms#layerPos, f32(layerPos#x), f32(layerPos#y));
        GL20.glUniform1f(uniforms#tileSize, f32(tileSize));
        GL20.glUniform2f(uniforms#tileScale, f32(tileScale#x), f32(tileScale#y));
        GL20.glUniform3f(uniforms#layerColor, color#r, color#g, color#b);
        GL13.glActiveTexture(GL13.GL_TEXTURE0);
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, texId);
        GL30.glBindVertexArray(tileVao);
        GL31.glDrawArraysInstanced(GL11.GL_TRIANGLES, 0, 6, tileCount);
        GL30.glBindVertexArray(0)

    // ========================================================================
    // Sprite Instanced Rendering — 連続する同テクスチャのスプライトを 1 draw call で
    // ========================================================================

    /// instanced sprite 用の VAO と instance VBO を構築する（起動時に 1 回）。
    /// loc 0: 共有 quad VBO (vertex.xy = 局所座標, vertex.zw = UV)
    /// loc 1-10: per-instance VBO (divisor=1)。1 instance = 38 floats / 152 bytes:
    ///   loc1 vec4 = ワールド変換 2x2 / loc2 vec2 = 平行移動 /
    ///   loc3 vec4 = uvOffset+uvScale / loc4 vec4 = color+alpha /
    ///   loc5 vec4 = フラグ (useTexture, sdf, styleEnabled, hatchEnabled) /
    ///   loc6 vec4 = rectSize+cornerRadius+borderWidth / loc7 vec4 = 枠色+枠alpha /
    ///   loc8 vec4 = ハッチ色+alpha / loc9 vec4 = ハッチ幅+周期+向き+市松セル /
    ///   loc10 vec4 = 市松色+alpha
    /// 戻り値: (vao, instanceVbo)
    pub def initSpriteInstancedRenderer(quadVBO: Int32): (Int32, Int32) \ IO =
        let vao = GL30.glGenVertexArrays();
        let instanceVbo = GL15.glGenBuffers();
        GL30.glBindVertexArray(vao);
        // 共有 quad VBO (loc 0)
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, quadVBO);
        GL20.glEnableVertexAttribArray(0);
        GL20.glVertexAttribPointer(0, 4, GL11.GL_FLOAT, false, 16, 0i64);
        // インスタンス VBO (loc 1-10, divisor=1, stride 152 bytes)
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, instanceVbo);
        GL20.glEnableVertexAttribArray(1);
        GL20.glVertexAttribPointer(1, 4, GL11.GL_FLOAT, false, 152, 0i64);
        GL33.glVertexAttribDivisor(1, 1);
        GL20.glEnableVertexAttribArray(2);
        GL20.glVertexAttribPointer(2, 2, GL11.GL_FLOAT, false, 152, 16i64);
        GL33.glVertexAttribDivisor(2, 1);
        GL20.glEnableVertexAttribArray(3);
        GL20.glVertexAttribPointer(3, 4, GL11.GL_FLOAT, false, 152, 24i64);
        GL33.glVertexAttribDivisor(3, 1);
        GL20.glEnableVertexAttribArray(4);
        GL20.glVertexAttribPointer(4, 4, GL11.GL_FLOAT, false, 152, 40i64);
        GL33.glVertexAttribDivisor(4, 1);
        GL20.glEnableVertexAttribArray(5);
        GL20.glVertexAttribPointer(5, 4, GL11.GL_FLOAT, false, 152, 56i64);
        GL33.glVertexAttribDivisor(5, 1);
        GL20.glEnableVertexAttribArray(6);
        GL20.glVertexAttribPointer(6, 4, GL11.GL_FLOAT, false, 152, 72i64);
        GL33.glVertexAttribDivisor(6, 1);
        GL20.glEnableVertexAttribArray(7);
        GL20.glVertexAttribPointer(7, 4, GL11.GL_FLOAT, false, 152, 88i64);
        GL33.glVertexAttribDivisor(7, 1);
        GL20.glEnableVertexAttribArray(8);
        GL20.glVertexAttribPointer(8, 4, GL11.GL_FLOAT, false, 152, 104i64);
        GL33.glVertexAttribDivisor(8, 1);
        GL20.glEnableVertexAttribArray(9);
        GL20.glVertexAttribPointer(9, 4, GL11.GL_FLOAT, false, 152, 120i64);
        GL33.glVertexAttribDivisor(9, 1);
        GL20.glEnableVertexAttribArray(10);
        GL20.glVertexAttribPointer(10, 4, GL11.GL_FLOAT, false, 152, 136i64);
        GL33.glVertexAttribDivisor(10, 1);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        GL30.glBindVertexArray(0);
        (vao, instanceVbo)

    /// 同じテクスチャのスプライト count 体を 1 回の instanced draw で描画する。
    /// data は 1 体 38 floats を列順に並べた instance データ（RenderFrame が組む）。
    /// 毎フレーム glBufferData で丸ごと差し替える（orphaning。drawPolygon と同方式）。
    /// texId = 0 は単色矩形の run で、シェーダはテクスチャを読まないので bind しない。
    /// blend は run 内で均一（RenderFrame が blend 変化で run を切る）。multiplyBlendLoc は
    /// instanced シェーダの premultiply スイッチの location（起動時に 1 回引いたもの）。
    pub def drawSpriteInstanced(shader: Int32, vao: Int32, instanceVbo: Int32, texId: Int32,
                                 multiplyBlendLoc: Int32, blend: DrawCmd.BlendMode,
                                 data: Array[Float32, Static], count: Int32): Unit \ IO =
        GL20.glUseProgram(shader);
        applyBlend(blend);
        GL20.glUniform1i(multiplyBlendLoc, multiplyFlag(blend));
        if (texId != 0) {
            GL13.glActiveTexture(GL13.GL_TEXTURE0);
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, texId)
        } else ();
        GL30.glBindVertexArray(vao);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, instanceVbo);
        GL15.glBufferData(GL15.GL_ARRAY_BUFFER, data, GL15.GL_DYNAMIC_DRAW);
        GL15.glBindBuffer(GL15.GL_ARRAY_BUFFER, 0);
        GL31.glDrawArraysInstanced(GL11.GL_TRIANGLES, 0, 6, count);
        GL30.glBindVertexArray(0)

}
