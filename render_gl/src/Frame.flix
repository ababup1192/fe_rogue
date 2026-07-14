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
        tileUniforms = RenderShader.TileUniforms
    }

    /// instanced sprite 1 体分の値 (16 floats / 64 bytes)。
    /// 並びはシェーダの instance 属性 (loc1-5) と同じ:
    /// 2x2 変換(4) + 平行移動(2) + UV(4) + 色+アルファ(4) + フラグ(2)。
    type alias SpriteInstance = {
        m00 = Float32, m01 = Float32, m10 = Float32, m11 = Float32,
        tx  = Float32, ty  = Float32,
        u0  = Float32, v0  = Float32, uw = Float32, vh = Float32,
        r   = Float32, g   = Float32, b  = Float32, a  = Float32,
        useTex = Float32, sdf = Float32
    }

    /// 溜めた run（同じテクスチャ・style なしの連続スプライト列）を
    /// 1 回の instanced draw で吐き出す。itemsRev は cons で積んだ逆順を
    /// 受け取り、ここで列順に戻して詰める（instance 順 = 列順を守る）。
    def flushSpriteRun(instShader: Int32, instVao: Int32, instVbo: Int32,
                        texId: Int32, itemsRev: List[SpriteInstance]): Unit \ IO =
        let count = List.length(itemsRev);
        if (count == 0) () else {
            let items = List.reverse(itemsRev);
            let data = Array.empty(Static, count * 16);
            let _ = List.foldLeft((i, inst) -> {
                let base = i * 16;
                Array.put(inst#m00,    base + 0,  data);
                Array.put(inst#m01,    base + 1,  data);
                Array.put(inst#m10,    base + 2,  data);
                Array.put(inst#m11,    base + 3,  data);
                Array.put(inst#tx,     base + 4,  data);
                Array.put(inst#ty,     base + 5,  data);
                Array.put(inst#u0,     base + 6,  data);
                Array.put(inst#v0,     base + 7,  data);
                Array.put(inst#uw,     base + 8,  data);
                Array.put(inst#vh,     base + 9,  data);
                Array.put(inst#r,      base + 10, data);
                Array.put(inst#g,      base + 11, data);
                Array.put(inst#b,      base + 12, data);
                Array.put(inst#a,      base + 13, data);
                Array.put(inst#useTex, base + 14, data);
                Array.put(inst#sdf,    base + 15, data);
                i + 1
            }, 0, items);
            RenderSprite.drawSpriteInstanced(instShader, instVao, instVbo, texId, data, count)
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
        let instShader   = args#instShader;
        let instVao      = args#instVao;
        let instVbo      = args#instVbo;
        let spriteUniforms = args#spriteUniforms;
        let tileUniforms = args#tileUniforms;
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
            // 連続する「同じテクスチャ・style なし」のスプライトを 1 回の instanced draw に
            // 畳む（run 収集 → flush）。1 要素 1 draw call だと呼び出しの固定費が積み上がり、
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
            // instance 属性に落とす（絵が per-draw 経路と一致することを式の同一性で保証）。
            let makeInst = (pos: Vec2.Vec2, size: Vec2.Vec2, drawable: RenderType.Drawable,
                             useTex: Bool, sdf: Bool) -> {
                let c = cosF(drawable#rotation);
                let s = sinF(drawable#rotation);
                let sx = size#x;
                let sy = size#y;
                let tx = pos#x + sx / 2.0 - c * sx / 2.0 + s * sy / 2.0;
                let ty = pos#y + sy / 2.0 - s * sx / 2.0 - c * sy / 2.0;
                { m00 = f32(c * sx), m01 = f32(s * sx), m10 = f32(-1.0 * s * sy), m11 = f32(c * sy),
                  tx = f32(tx), ty = f32(ty),
                  u0 = f32(drawable#uvOffset#x), v0 = f32(drawable#uvOffset#y),
                  uw = f32(drawable#uvScale#x), vh = f32(drawable#uvScale#y),
                  r = drawable#color#r, g = drawable#color#g, b = drawable#color#b,
                  a = drawable#alpha,
                  useTex = if (useTex) 1.0f32 else 0.0f32,
                  sdf = if (sdf) 1.0f32 else 0.0f32 }
            };
            // style 付き矩形はスタイル用 uniform を伴う従来経路でしか描けないので、
            // per-draw の drawSprite を残して 1 枚ずつ描く。
            let drawOne = (drawable: RenderType.Drawable) -> {
                if (String.isEmpty(drawable#texture)) {
                    let displaySize: Vec2.Vec2 = drawable#scale;
                    RenderSprite.drawSprite(spriteShader, vao, spriteUniforms, {
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
                            RenderSprite.drawSprite(spriteShader, vao, spriteUniforms, {
                                texture = GpuHandle.textureIdInt(texInfo#id), position = pos, scale = displaySize,
                                color = drawable#color, alpha = drawable#alpha,
                                uvOffset = drawable#uvOffset, uvScale = drawable#uvScale,
                                rotation = drawable#rotation, useTexture = true,
                                style = drawable#style, sdf = isFont})
                        case None => ()
                    }
                }
            };
            // run = (テクスチャ id, 積んだ instance の逆順リスト)。texId=0 は単色矩形の run。
            let emptyRun: (Int32, List[SpriteInstance]) = (0, Nil);
            let flush = (acc: (Int32, List[SpriteInstance])) -> {
                let (accTex, accRev) = acc;
                flushSpriteRun(instShader, instVao, instVbo, accTex, accRev)
            };
            let push = (acc: (Int32, List[SpriteInstance]), texId: Int32, inst: SpriteInstance) -> {
                let (accTex, accRev) = acc;
                if (List.isEmpty(accRev))
                    (texId, inst :: Nil)
                else if (accTex == texId)
                    (accTex, inst :: accRev)
                else {
                    // テクスチャが変わったら現 run を吐いてから新しい run を始める。
                    flush(acc);
                    (texId, inst :: Nil)
                }
            };
            let lastRun = List.foldLeft((acc, item) -> match item {
                case Result.Ok(drawable) =>
                    if (not Option.isEmpty(drawable#style)) {
                        // style 付き矩形が来たら run を吐き、この 1 枚は従来経路で描く。
                        flush(acc);
                        drawOne(drawable);
                        emptyRun
                    } else if (String.isEmpty(drawable#texture)) {
                        push(acc, 0, makeInst(drawable#position, drawable#scale, drawable, false, false))
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
                                push(acc, GpuHandle.textureIdInt(texInfo#id),
                                     makeInst(pos, displaySize, drawable, true, isFont))
                            // texture 未登録は従来どおり描かない。描かないだけなので run は途切れさせない。
                            case None => acc
                        }
                    }
                case Result.Err(pc) =>
                    // polygon が来たら run を吐いてから polygon を描く（列順を守る）。
                    flush(acc);
                    RenderSprite.drawPolygon(spriteShader, polyVao, polyVbo, spriteUniforms,
                                              pc#vertices, pc#color, pc#alpha);
                    emptyRun
            }, emptyRun, sortedMerged);
            flush(lastRun)
        } else ()

}
