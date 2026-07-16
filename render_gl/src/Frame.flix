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

    /// zIndex 昇順・同 z 内は入力順のまま、に並べ替える。
    /// 比較ソートにしないのは、1 比較ごとにキー関数の呼び出しと多相比較が走り、
    /// 物量シーン（数千件）でフレーム時間の大半を占めるため（スレッドダンプ実測）。
    /// z ごとのバケツへ 1 パスで振り分けてキー昇順に繋ぎ直せば、比較は z の
    /// 種類数ぶんの Map 操作だけで済み、同 z 内の順序も構造的に崩れない。
    /// 同 z の入れ替わりは実害がある（bg Rect と同 z のテキスト最後の文字が
    /// 上書き消失した事故が過去にある）ため、安定性はこの関数の必須条件。
    def stableByZ(zOf: a -> Int32, items: List[a]): List[a] =
        // バケツは先頭挿入で溜める（= 逆順）。foldRight が z の大きい側から
        // 前置し直すので、全体は z 昇順・バケツ内は入力順に戻る。
        let buckets = List.foldLeft((m, x) -> {
            let z = zOf(x);
            let bucket = Map.get(z, m) |> Option.getWithDefault(Nil);
            Map.insert(z, x :: bucket, m)
        }, Map.empty(), items);
        Map.foldRight((bucket, acc) ->
            List.foldLeft((rest, x) -> x :: rest, acc, bucket), Nil, buckets)

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
        polyVbo = Int32,
        instShader = Int32,
        instVao = Int32,
        instVbo = Int32,
        spriteUniforms = RenderShader.SpriteUniforms,
        tileUniforms = RenderShader.TileUniforms,
        // instanced シェーダの premultiply スイッチ（Multiply ブレンド用）の uniform location。
        instMultiplyBlend = Int32
    }

    /// 溜めた run（同じテクスチャの連続スプライト列）を 1 回の instanced draw で
    /// 吐き出す。1 体 = 38 floats の Float32 配列で受け取る。record にしないのは、
    /// record の `#` 読みが実行時のフィールド探索で、数千体の詰め直しでは
    /// その探索だけでフレーム時間に現れるため（スレッドダンプ実測）。
    /// itemsRev は cons で積んだ逆順。末尾位置から前へ詰め戻すことで
    /// List.reverse なしに instance 順 = 列順を守る。
    def flushSpriteRun(instShader: Int32, instVao: Int32, instVbo: Int32,
                        texId: Int32, multiplyBlendLoc: Int32, blend: DrawCmd.BlendMode,
                        count: Int32,
                        itemsRev: List[Array[Float32, Static]]): Unit \ IO =
        if (count == 0) () else {
            let data = Array.empty(Static, count * 38);
            let _ = List.foldLeft((endIdx, inst) -> {
                let base = (endIdx - 1) * 38;
                Array.forEachWithIndex((j, v) -> Array.put(v, base + j, data), inst);
                endIdx - 1
            }, count, itemsRev);
            RenderSprite.drawSpriteInstanced(instShader, instVao, instVbo, texId,
                                             multiplyBlendLoc, blend, data, count)
        }

    /// 1 フレーム描画: tileMaps を先に zIndex 順で描き、続いて sprites を zIndex 順で描く。
    /// 黒帯部分は scissor で clear する。
    pub def renderFrameMixed(args: FrameArgs): Unit \ IO =
        let spriteShader = args#spriteShader;
        let tileShader   = args#tileShader;
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
        let instShader   = args#instShader;
        let instVao      = args#instVao;
        let instVbo      = args#instVbo;
        let spriteUniforms = args#spriteUniforms;
        let tileUniforms = args#tileUniforms;
        let instMultiplyBlend = args#instMultiplyBlend;
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
            // tileMaps: zIndex 昇順で 1 draw call ずつ描画。並べ替えは stableByZ（下記）。
            let sortedTiles = stableByZ(tm -> tm#zIndex, tileMaps);
            List.forEach(tm -> match Map.get(tm#textureName, registry) {
                case Some(texInfo) =>
                    RenderSprite.drawTileMapInstanced(tileShader, GpuHandle.textureIdInt(texInfo#id), GpuHandle.tileVaoInt(tm#tileVaoId),
                                         tileUniforms,
                                         tm#position, tm#tileSize, tm#tileScale,
                                         tm#color, tm#tileCount)
                case None => ()
            }, sortedTiles);
            // sprites と polygons を 1 本の zIndex 安定ソート列にマージして描く。
            // sprite だけ z 順にし polygon を最後へまとめて描くと、ワールド配置のポリゴン
            // （武器グリフ等）が手前のポップアップを貫通してしまう。両者を同じ z 空間で
            // 並べることで、重なり順が zIndex の指定どおりになる。
            // 同一 zIndex 内は入力順（sprites → polygons）を保つ（stableByZ が構造的に保証）。
            // Ok = Drawable（スプライト/Rect）、Err = PolygonCmd（Polygon/Arc）。
            let merged: List[Result[RenderType.PolygonCmd, RenderType.Drawable]] =
                List.append(
                    sprites  |> List.map(d  -> Result.Ok(d)),
                    polygons |> List.map(pc -> Result.Err(pc)));
            let zOf = item -> match item {
                case Result.Ok(d)   => d#zIndex
                case Result.Err(pc) => pc#zIndex
            };
            let sortedMerged = stableByZ(zOf, merged);
            // clip 窓 → framebuffer 座標の整数 scissor 矩形 (x0, y0, x1, y1)（top-left 原点）。
            // record に Eq が無いので、run の分断キーはこの int 組で比較する（fb 画素への
            // 量子化を兼ね、1px 未満の差で run を無駄に割らない）。
            let scaleX = Int32.toFloat64(vpW) / designW;
            let scaleY = Int32.toFloat64(vpH) / designH;
            let clipKeyOf = clip -> match clip {
                case None    => (None: Option[(Int32, Int32, Int32, Int32)])
                case Some(r) => Some(DrawCmd.clipPixels({ scaleX = scaleX, scaleY = scaleY }, r))
            };
            // scissor を張り替える。y は GL の左下原点へ反転し、viewport と交差する
            // （clip が画面外へ食み出しても letterbox の黒帯を侵さない）。
            // 幅か高さが 0 以下の矩形は glScissor(…, 0, 0) になり、その run は何も描かない。
            let setScissor = clipK -> match clipK {
                case None => GL11.glDisable(GL11.GL_SCISSOR_TEST)
                case Some((x0, y0, x1, y1)) => {
                    let cx0 = Int32.max(0, x0);
                    let cx1 = Int32.min(vpW, x1);
                    let cy0 = Int32.max(0, y0);
                    let cy1 = Int32.min(vpH, y1);
                    GL11.glEnable(GL11.GL_SCISSOR_TEST);
                    GL11.glScissor(vpX + cx0, vpY + vpH - cy1,
                                   Int32.max(0, cx1 - cx0), Int32.max(0, cy1 - cy0))
                }
            };
            // 連続する「同じテクスチャ・同じ scissor」のスプライトを 1 回の instanced draw に
            // 畳む（run 収集 → flush）。run を切るのはテクスチャ変化・scissor 変化と polygon だけ。
            // 1 要素 1 draw call だと呼び出しの固定費が積み上がり、
            // 数千体で描画時間のほとんどを占めてしまうため。
            //
            // 【順序の不変条件・変更禁止】sortedMerged の列順は一切入れ替えない。
            // 畳んでよいのは「先頭から連続する同状態の部分列」だけで、バッチ内の
            // instance 順 = 列順。run をまたいでテクスチャごとに再グループ化するのは禁止:
            // アルファブレンドは描画順に依存するので、同 zIndex の bg 矩形とテキスト最後の
            // 文字が入れ替わって文字が消える実バグが過去に起きた。
            let f32 = RenderUtil.f32;
            let cosF = RenderUtil.cosF;
            let sinF = RenderUtil.sinF;
            // drawSprite が uniform に詰める model 行列と同じ式を CPU 側で計算して
            // instance 属性 (38 floats・シェーダ loc1-10 と同並び) に落とす
            // （絵が per-draw 経路と一致することを式の同一性で保証）。
            // style も per-instance 属性に載せる: 単色矩形は常に style 付きで届く
            // (Render.box が solidStyle を持たせる) ため、style をバッチ分割条件に
            // すると矩形が全部 1 枚ずつ描かれて一括化が骨抜きになる（実測で発覚）。
            let makeInst = (pos: Vec2.Vec2, size: Vec2.Vec2, drawable: RenderType.Drawable,
                             useTex: Bool, sdf: Bool) -> {
                let c = cosF(drawable#rotation);
                let s = sinF(drawable#rotation);
                let sx = size#x;
                let sy = size#y;
                let tx = pos#x + sx / 2.0 - c * sx / 2.0 + s * sy / 2.0;
                let ty = pos#y + sy / 2.0 - s * sx / 2.0 - c * sy / 2.0;
                let color = drawable#color;
                let uvo = drawable#uvOffset;
                let uvs = drawable#uvScale;
                let (styleOn, hatchOn, cr, bw, bc, ba, hc, ha, hw, hp, hd, cc, ca, cl) = match drawable#style {
                    case None =>
                        let zero: Color = { r = 0.0f32, g = 0.0f32, b = 0.0f32 };
                        (0.0f32, 0.0f32, 0.0f32, 0.0f32, zero, 0.0f32,
                         zero, 0.0f32, 0.0f32, 0.0f32, 0.0f32, zero, 0.0f32, 0.0f32)
                    case Some(st) =>
                        // hatch の有効判定は drawSprite の hatchOn と同式(period<=0 は GLSL の mod が未定義なので無効扱い)。
                        let hatch = if (st#stripeWidth > 0.0 and st#stripeAlpha > 0.0f32 and st#stripePeriod > 0.0) 1.0f32 else 0.0f32;
                        (1.0f32, hatch, f32(st#cornerRadius), f32(st#borderWidth),
                         st#borderColor, st#borderAlpha,
                         st#stripeColor, st#stripeAlpha, f32(st#stripeWidth), f32(st#stripePeriod),
                         Int32.toFloat32(st#stripeDir),
                         st#checkerColor, st#checkerAlpha, f32(st#checkerCell))
                };
                Array#{
                    f32(c * sx), f32(s * sx), f32(-1.0 * s * sy), f32(c * sy),
                    f32(tx), f32(ty),
                    f32(uvo#x), f32(uvo#y), f32(uvs#x), f32(uvs#y),
                    color#r, color#g, color#b, drawable#alpha,
                    (if (useTex) 1.0f32 else 0.0f32), (if (sdf) 1.0f32 else 0.0f32), styleOn, hatchOn,
                    f32(sx), f32(sy), cr, bw,
                    bc#r, bc#g, bc#b, ba,
                    hc#r, hc#g, hc#b, ha,
                    hw, hp, hd, cl,
                    cc#r, cc#g, cc#b, ca
                } @ Static
            };
            // run = (テクスチャ id, scissor キー, blend, 体数, 積んだ instance の逆順リスト)。
            // texId=0 は単色矩形の run。scissor キーか blend が変わるところでも run を切る
            // （blend は GL のグローバル状態なので、混ぜると run 全体が同じ重ね方になってしまう）。
            let emptyRun: (Int32, Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32, List[Array[Float32, Static]]) =
                (0, None, DrawCmd.BlendMode.Normal, 0, Nil);
            // 空 run では scissor / blend を触らない — GL 状態を無駄に往復させない。
            let flush = (acc: (Int32, Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32, List[Array[Float32, Static]])) -> {
                let (accTex, accClip, accBlend, accCount, accRev) = acc;
                if (accCount == 0) () else {
                    setScissor(accClip);
                    flushSpriteRun(instShader, instVao, instVbo, accTex,
                                   instMultiplyBlend, accBlend, accCount, accRev)
                }
            };
            let push = (acc: (Int32, Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32, List[Array[Float32, Static]]),
                        texId: Int32, clipK: Option[(Int32, Int32, Int32, Int32)],
                        blend: DrawCmd.BlendMode,
                        inst: Array[Float32, Static]) -> {
                let (accTex, accClip, accBlend, accCount, accRev) = acc;
                if (accCount == 0)
                    (texId, clipK, blend, 1, inst :: Nil)
                else if (accTex == texId and accClip == clipK and accBlend == blend)
                    (accTex, accClip, accBlend, accCount + 1, inst :: accRev)
                else {
                    // テクスチャ・scissor・blend のどれかが変わったら現 run を吐いてから新しい run を始める。
                    flush(acc);
                    (texId, clipK, blend, 1, inst :: Nil)
                }
            };
            let lastRun = List.foldLeft((acc, item) -> match item {
                case Result.Ok(drawable) =>
                    if (String.isEmpty(drawable#texture)) {
                        push(acc, 0, clipKeyOf(drawable#clip), drawable#blend,
                             makeInst(drawable#position, drawable#scale, drawable, false, false))
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
                                push(acc, GpuHandle.textureIdInt(texInfo#id), clipKeyOf(drawable#clip),
                                     drawable#blend,
                                     makeInst(pos, displaySize, drawable, true, isFont))
                            // texture 未登録は従来どおり描かない。描かないだけなので run は途切れさせない。
                            case None => acc
                        }
                    }
                case Result.Err(pc) =>
                    // polygon が来たら run を吐いてから polygon を描く（列順を守る）。
                    flush(acc);
                    setScissor(clipKeyOf(pc#clip));
                    RenderSprite.drawPolygon(spriteShader, polyVao, polyVbo, spriteUniforms,
                                              pc#vertices, pc#color, pc#alpha, pc#blend);
                    emptyRun
            }, emptyRun, sortedMerged);
            flush(lastRun);
            // フレーム末尾で必ず scissor を解除する — 有効なまま持ち越すと、次フレームの
            // 全画面 clear や F8 注釈のスクリーンショット再描画が小矩形に切られる。
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            // blend も Normal に戻す — Add/Multiply のまま持ち越すと、次フレーム冒頭の
            // タイルマップや F8 注釈の再描画が違う重ね方で合成される。
            RenderSprite.applyBlend(DrawCmd.BlendMode.Normal)
        } else ()

}
