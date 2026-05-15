// RenderFrame — 1 フレーム分の描画パイプライン
//
// LwjglLayer.flix の calcViewport / renderFrameMixed を移植。
// sprites と tileMaps を zIndex で混合描画する (Sprite よりも先に TileMap)。

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

    /// 1 フレーム描画: tileMaps を先に zIndex 順で描き、続いて sprites を zIndex 順で描く。
    /// 黒帯部分は scissor で clear する。
    pub def renderFrameMixed(spriteShader: Int32, tileShader: Int32, vao: Int32,
                              registry: RenderAsset.TextureRegistry,
                              clearColor: Color, designW: Float64, designH: Float64,
                              fbW: Int32, fbH: Int32,
                              sprites: List[RenderType.Drawable],
                              tileMaps: List[RenderType.TileMapRenderCmd]): Unit \ IO =
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
            // 描画順を壊し、特定の Drawable（例: bg ColorRect と同 z の Label2D の最後の文字）が
            // 入れ替わって上書き消失する事故が起きる。
            let sortedTiles = tileMaps
                |> List.zipWithIndex
                |> List.sortBy(idxT -> let (idx, tm) = idxT; (tm#zIndex, idx))
                |> List.map(idxT -> let (_, tm) = idxT; tm);
            List.forEach(tm -> match Map.get(tm#textureName, registry) {
                case Some(texInfo) =>
                    RenderSprite.drawTileMapInstanced(tileShader, texInfo#id, tm#tileVaoId,
                                         tm#position, tm#tileSize, tm#tileScale,
                                         tm#color, tm#tileCount)
                case None => ()
            }, sortedTiles);
            // sprites: zIndex 昇順で描画（同上、stable sort 化）
            let sortedSprites = sprites
                |> List.zipWithIndex
                |> List.sortBy(idxD -> let (idx, d) = idxD; (d#zIndex, idx))
                |> List.map(idxD -> let (_, d) = idxD; d);
            List.forEach(drawable -> {
                if (String.isEmpty(drawable#texture)) {
                    let displaySize: Vec2.Vec2 = drawable#scale;
                    RenderSprite.drawSprite(spriteShader, 0, vao, drawable#position, displaySize,
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
                            RenderSprite.drawSprite(spriteShader, texInfo#id, vao, pos, displaySize,
                                       drawable#color, drawable#alpha, drawable#uvOffset,
                                       drawable#uvScale, drawable#rotation, true)
                        case None => ()
                    }
                }
            }, sortedSprites)
        } else ()

}
