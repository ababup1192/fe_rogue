// RenderFrame — 1 フレームぶんの絵（スプライト・タイル・多角形）を、重なり順に並べて一気に描く。
// 描く順番（zIndex）や画面の縦横比合わせ（黒帯）をこの一箇所に任せられるので、上位は絵の材料を渡すだけでよい。
// 利用例: 毎フレーム、集めた描画物を画面に出す / 手前・奥の重なりを正しく見せる。
// 注意: 同じ zIndex 内は渡された入力順を保つ（安定ソート）。タイルはスプライトより先に描く。

mod RenderFrame {
    import org.lwjgl.opengl.GL11

    /// デザイン解像度のアスペクト比を維持しつつ、フレームバッファに収まる最大矩形を計算。
    /// 戻り値: (vpX, vpY, vpW, vpH)
    pub def calcViewport(fbW: Int32, fbH: Int32, designW: Float64, designH: Float64): (Int32, Int32, Int32, Int32) =
        let floatToInt32 = RenderUtil.floatToInt32;
        let designAspect = designW / designH;
        let windowAspect = Int32.toFloat64(fbW) / Int32.toFloat64(fbH);
        if (windowAspect > designAspect) {
            // ピラーボックス (左右黒帯)
            let vpH = fbH;
            let vpW = floatToInt32(Int32.toFloat64(fbH) * designAspect);
            let vpX = (fbW - vpW) / 2;
            (vpX, 0, vpW, vpH)
        } else {
            // レターボックス (上下黒帯)
            let vpW = fbW;
            let vpH = floatToInt32(Int32.toFloat64(fbW) / designAspect);
            let vpY = (fbH - vpH) / 2;
            (0, vpY, vpW, vpH)
        }

    /// 1 フレーム描画に必要な材料をひとまとめにした名前付き引数。
    /// 同じ Int32（シェーダ・VAO・VBO のハンドル）が何個も並ぶので、位置引数だと
    /// 順番を取り違えても気づけない。名前で渡せば取り違いが起きない。
    /// 利用例: 実行環境（LWJGL 等）のフレームループがこの1件を組んで renderFrameMixed へ渡す。
    pub type alias FrameArgs = {
        spriteShader = Int32,
        tileShader = Int32,
        vao = Int32,
        registry = RenderAsset.TextureRegistry,
        clearColor = Color,
        designW = Float64,
        designH = Float64,
        fbW = Int32,
        fbH = Int32,
        sprites = List[RenderType.Drawable],
        tileMaps = List[RenderType.TileMapRenderCmd],
        polygons = List[RenderType.PolygonCmd],
        polyVao = Int32,
        polyVbo = Int32
    }

    /// 1 フレーム描画: tileMaps を先に zIndex 順で描き、続いて sprites を zIndex 順で描く。
    /// 黒帯部分は scissor で clear する。
    pub def renderFrameMixed(args: FrameArgs): Unit \ IO =
        let spriteShader = args#spriteShader;
        let tileShader   = args#tileShader;
        let vao          = args#vao;
        let registry     = args#registry;
        let clearColor   = args#clearColor;
        let designW      = args#designW;
        let designH      = args#designH;
        let fbW          = args#fbW;
        let fbH          = args#fbH;
        let sprites      = args#sprites;
        let tileMaps     = args#tileMaps;
        let polygons     = args#polygons;
        let polyVao      = args#polyVao;
        let polyVbo      = args#polyVbo;
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
            // tileMaps: zIndex 昇順で 1 draw call ずつ描画。
            // 同一 zIndex 内では入力順を保つため stable sort（zipWithIndex + (zIndex, drawIndex)）。
            // 単純な `List.sortBy(_#zIndex, _)` は unstable で、Scene.toDrawables 側で確立した
            // 描画順を壊し、特定の Drawable（例: bg Rect と同 z の Text の最後の文字）が
            // 入れ替わって上書き消失する事故が起きる。
            let sortedTiles = tileMaps
                |> List.zipWithIndex
                |> List.sortBy(idxT -> let (idx, tm) = idxT; (tm#zIndex, idx))
                |> List.map(idxT -> let (_, tm) = idxT; tm);
            List.forEach(tm -> match Map.get(tm#textureName, registry) {
                case Some(texInfo) =>
                    RenderSprite.drawTileMapInstanced(tileShader, GpuHandle.textureIdInt(texInfo#id), GpuHandle.tileVaoInt(tm#tileVaoId),
                                         tm#position, tm#tileSize, tm#tileScale,
                                         tm#color, tm#tileCount)
                case None => ()
            }, sortedTiles);
            // sprites と polygons を 1 本の zIndex 安定ソート列にマージして描く。
            // sprite だけ z 順にし polygon を最後へまとめて描くと、ワールド配置のポリゴン
            // （武器グリフ等）が手前のポップアップを貫通してしまう。両者を同じ z 空間で
            // 並べることで、重なり順が zIndex の指定どおりになる。
            // 同一 zIndex 内は入力順（sprites → polygons）を保つため stable sort（zipWithIndex）。
            // Ok = Drawable（スプライト/Rect）、Err = PolygonCmd（Polygon/Arc）。
            let merged: List[Result[RenderType.PolygonCmd, RenderType.Drawable]] =
                List.append(
                    sprites  |> List.map(d  -> Result.Ok(d)),
                    polygons |> List.map(pc -> Result.Err(pc)));
            let zOf = item -> match item {
                case Result.Ok(d)   => d#zIndex
                case Result.Err(pc) => pc#zIndex
            };
            let sortedMerged = merged
                |> List.zipWithIndex
                |> List.sortBy(ix -> let (idx, item) = ix; (zOf(item), idx))
                |> List.map(ix -> let (_, item) = ix; item);
            List.forEach(item -> match item {
                case Result.Ok(drawable) =>
                    if (String.isEmpty(drawable#texture)) {
                        let displaySize: Vec2.Vec2 = drawable#scale;
                        RenderSprite.drawSprite(spriteShader, vao, {
                            texture = 0, position = drawable#position, scale = displaySize,
                            color = drawable#color, alpha = drawable#alpha,
                            uvOffset = drawable#uvOffset, uvScale = drawable#uvScale,
                            rotation = drawable#rotation, useTexture = false,
                            style = drawable#style, sdf = false})
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
                                // フォントアトラス (font_*) は SDF テキストとして描く。
                                let isFont = String.startsWith({prefix = "font_"}, drawable#texture);
                                RenderSprite.drawSprite(spriteShader, vao, {
                                    texture = GpuHandle.textureIdInt(texInfo#id), position = pos, scale = displaySize,
                                    color = drawable#color, alpha = drawable#alpha,
                                    uvOffset = drawable#uvOffset, uvScale = drawable#uvScale,
                                    rotation = drawable#rotation, useTexture = true,
                                    style = drawable#style, sdf = isFont})
                            case None => ()
                        }
                    }
                case Result.Err(pc) =>
                    RenderSprite.drawPolygon(spriteShader, polyVao, polyVbo,
                                              pc#vertices, pc#color, pc#alpha)
            }, sortedMerged)
        } else ()

}
