// RenderFrame — 1 フレームぶんの絵（スプライト・タイル・多角形）を、重なり順に並べて一気に描く。
// 描く順番（zIndex）や画面の縦横比合わせ（黒帯）をこの一箇所に任せられるので、上位は絵の材料を渡すだけでよい。
// 利用例: 毎フレーム、集めた描画物を画面に出す / 手前・奥の重なりを正しく見せる。
// 注意: 同じ zIndex 内は渡された入力順を保つ（安定ソート）。タイル層も動的な描画物と
// 同じ z 空間で並ぶ（同 z なら列に先に積むタイル層が奥 — 手前に出すには大きい zIndex を与える）。

mod RenderFrame {
    import java.nio.FloatBuffer
    import org.lwjgl.opengl.GL11

    /// z 安定ソート列に混ぜる 5 種の描画物。MTile=タイルマップ 1 層（1 draw call）、
    /// MSprite=スプライト/箱、MPoly=動的多角形、MStatic=永続 VBO のレンジ（頂点は運ばず
    /// 範囲だけ）、MSurface=宣言シェーダー面。種類が切り替わる瞬間に
    /// 溜めた run を吐くことで、列順（＝重なり順）を厳密に守る。
    pub enum Merged {
        case MTile(RenderType.TileMapRenderCmd)
        case MSprite(RenderType.Drawable)
        case MPoly(RenderType.PolygonCmd)
        case MStatic(RenderStatic.Range)
        case MSurface(ShaderEffect.ShaderRenderCmd)
    }

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

    /// 鍵の昇順・同鍵内は入力順のまま、に並べ替える（鍵は Order を持つ任意の型）。
    /// 比較ソートにしないのは、1 比較ごとにキー関数の呼び出しと多相比較が走り、
    /// 物量シーン（数千件）でフレーム時間の大半を占めるため（スレッドダンプ実測）。
    /// 鍵ごとのバケツへ 1 パスで振り分けてキー昇順に繋ぎ直せば、比較は鍵の
    /// 種類数ぶんの Map 操作だけで済み、同鍵内の順序も構造的に崩れない。
    /// 同 z の入れ替わりは実害がある（bg Rect と同 z のテキスト最後の文字が
    /// 上書き消失した事故が過去にある）ため、安定性はこの関数の必須条件。
    /// zIndex は小さな整数がひとかたまりに並ぶので、鍵の幅ぶんの席を 1 本用意して
    /// 振り分ける。木の Map だと 1 個ごとに挿入と枝の組み替えが走り、数千個の画面では
    /// その組み替えだけがフレーム時間に現れる（スレッドダンプ実測）。
    /// 席は先頭挿入で溜める（= 逆順）。席の大きい側から前置し直すので、
    /// 全体は z 昇順・席内は入力順に戻る。
    /// 5 種の描画物を、zIndex 昇順・同 z 内は
    /// tiles → sprites → polygons → static → surfaces の順に並べた 1 本の列にする。
    /// 5 本を 1 本に繋いでから並べ替えないのは、繋ぐだけで列 1 本ぶんの写しが増え、
    /// 鍵と中身の組も 1 個ずつ作ることになるため（数千個の画面ではその作り直しが
    /// フレーム時間に出る）。幅と個数は席を作る前に一度だけ数え、
    /// 数える場所は組でなく席 3 つに置く（組は 1 個ごとに作り直しになる）。
    pub def mergedByZ(tiles: List[RenderType.TileMapRenderCmd],
                      sprites: List[RenderType.Drawable],
                      polygons: List[RenderType.PolygonCmd],
                      statics: List[RenderStatic.Range],
                      surfaces: List[ShaderEffect.ShaderRenderCmd]): List[Merged] =
        region rc {
            // 0 = 一番小さい z / 1 = 一番大きい z / 2 = 個数
            let tally: Array[Int32, rc] = Array#{2147483647, -2147483648, 0} @ rc;
            let scan = (z: Int32) -> {
                if (z < Array.get(0, tally)) Array.put(z, 0, tally) else ();
                if (z > Array.get(1, tally)) Array.put(z, 1, tally) else ();
                Array.put(Array.get(2, tally) + 1, 2, tally)
            };
            List.forEach(x -> scan(x#zIndex), tiles);
            List.forEach(x -> scan(x#zIndex), sprites);
            List.forEach(x -> scan(x#zIndex), polygons);
            List.forEach(x -> scan(x#zIndex), statics);
            List.forEach(x -> scan(x#zIndex), surfaces);
            let lo = Array.get(0, tally);
            let hi = Array.get(1, tally);
            let count = Array.get(2, tally);
            if (count == 0) Nil
            // 鍵がまばらに散っていると席の数が描く物の数を大きく超える。
            // そのときだけ木で並べ替える（席を数百万本用意して埋めないより速い）。
            else if (hi - lo > seatLimit(count)) stableByZTree(zOfMerged, chain(tiles, sprites, polygons, statics, surfaces))
            else {
                let n = hi - lo + 1;
                let seats: Array[List[Merged], rc] = Array.repeat(rc, n, Nil);
                let seat = (z: Int32, m: Merged) -> {
                    let i = z - lo;
                    Array.put(m :: Array.get(i, seats), i, seats)
                };
                List.forEach(x -> seat(x#zIndex, Merged.MTile(x)), tiles);
                List.forEach(x -> seat(x#zIndex, Merged.MSprite(x)), sprites);
                List.forEach(x -> seat(x#zIndex, Merged.MPoly(x)), polygons);
                List.forEach(x -> seat(x#zIndex, Merged.MStatic(x)), statics);
                List.forEach(x -> seat(x#zIndex, Merged.MSurface(x)), surfaces);
                List.range(0, n) |> List.foldLeft((acc, i) ->
                    List.foldLeft((rest, x) -> x :: rest, acc,
                                  Array.get(n - 1 - i, seats)), Nil)
            }
        }

    /// 鍵がまばらなときだけ使う、5 本を入力順どおりに繋いだ 1 本。
    def chain(tiles: List[RenderType.TileMapRenderCmd], sprites: List[RenderType.Drawable],
              polygons: List[RenderType.PolygonCmd], statics: List[RenderStatic.Range],
              surfaces: List[ShaderEffect.ShaderRenderCmd]): List[Merged] =
        List.append(
            tiles |> List.map(x -> Merged.MTile(x)),
            List.append(
                List.append(
                    List.append(
                        sprites  |> List.map(x -> Merged.MSprite(x)),
                        polygons |> List.map(x -> Merged.MPoly(x))),
                    statics |> List.map(x -> Merged.MStatic(x))),
                surfaces |> List.map(x -> Merged.MSurface(x))))

    /// 並べ替え鍵 = zIndex（全 run 種で共有の 1 つの z 空間）。
    def zOfMerged(item: Merged): Int32 =
        match item {
            case Merged.MTile(tm)   => tm#zIndex
            case Merged.MSprite(d)  => d#zIndex
            case Merged.MPoly(pc)   => pc#zIndex
            case Merged.MStatic(r)  => r#zIndex
            case Merged.MSurface(s) => s#zIndex
        }

    /// 席方式に倒す鍵の幅の上限。描く物の数に比例させるのは、席が疎らでも
    /// 「埋める手間 ≒ 描く物の数」に収まる範囲なら席のほうが速いため。
    def seatLimit(count: Int32): Int32 = 4096 + 4 * count

    /// 鍵がまばらなときの受け皿（席方式と同じ順序を返す）。
    def stableByZTree(zOf: a -> Int32, items: List[a]): List[a] =
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
        // 1 度だけ GPU に焼いて使い回す静的多角形のレンジ列（無ければ Nil）。動的 polygons と
        // 同じ z 安定ソート列に混ぜて描くので重なり順は壊れない。camera（viewOffset/viewScale）
        // は各レンジが持ち、halfDesign は design/2 をここで計算して当てる。
        staticRanges = List[RenderStatic.Range],
        // 同 blend / 切り抜き窓の連続多角形を 1 draw call に畳むバッチ描画用。
        polyBatchShader = Int32,
        polyBatchVao = Int32,
        polyBatchVbo = Int32,
        polyBatchUniforms = RenderShader.PolyBatchUniforms,
        instShader = Int32,
        instVao = Int32,
        instVbo = Int32,
        // 1 フレームぶんの instance / 頂点を直に書き溜める使い回しの入れ物
        // （バックエンドが起動時に 1 つずつ作って毎フレーム貸す）。
        instBuf = RenderBuf.Buf,
        polyBuf = RenderBuf.Buf,
        spriteUniforms = RenderShader.SpriteUniforms,
        tileUniforms = RenderShader.TileUniforms,
        // instanced シェーダの premultiply スイッチ（Multiply ブレンド用）の uniform location。
        instMultiplyBlend = Int32,
        // 宣言シェーダー面の描画依頼列。sprites/polygons/静的レンジと同じ z 安定ソート列に
        // 第 4 の run 種として混ぜ、各面の zIndex の位置で描く（水を床の上・壁の下に置ける）。
        surfaces = List[ShaderEffect.ShaderRenderCmd],
        // シェーダー面 1 枚を実際に GL へ描くクロージャ（program の uniform location を知る
        // バックエンド側が提供する）。renderFrameMixed は z の合流だけを受け持つ。
        drawSurface = ShaderEffect.ShaderRenderCmd -> Unit \ IO
    }

    /// drawSprite が uniform に詰める model 行列と同じ式を CPU 側で計算して、
    /// instance 属性 (38 floats・シェーダ loc1-10 と同並び) を入れ物の slot 番目へ直に書く
    /// （絵が per-draw 経路と一致することを式の同一性で保証）。
    /// style も per-instance 属性に載せる: 単色矩形は常に style 付きで届く
    /// (Render.box が solidStyle を持たせる) ため、style をバッチ分割条件に
    /// すると矩形が全部 1 枚ずつ描かれて一括化が骨抜きになる（実測で発覚）。
    /// 38 本の書き込みを短い名前でまとめず並べるのは、まとめ役の小さな関数を挟むと
    /// 1 体につき 38 回その呼び出しが走り、書き込み本体より高くつくため（実測）。
    def writeInstAt(data: FloatBuffer, slot: Int32, pos: Vec2.Vec2, size: Vec2.Vec2,
                    drawable: RenderType.Drawable, useTex: Bool, sdf: Bool): Unit \ IO =
        let f32 = RenderUtil.f32;
        let c = RenderUtil.cosF(drawable#rotation);
        let s = RenderUtil.sinF(drawable#rotation);
        let sx = size#x;
        let sy = size#y;
        let tx = pos#x + sx / 2.0 - c * sx / 2.0 + s * sy / 2.0;
        let ty = pos#y + sy / 2.0 - s * sx / 2.0 - c * sy / 2.0;
        let color = drawable#color;
        let uvo = drawable#uvOffset;
        let uvs = drawable#uvScale;
        let base = slot * 38;
        discard data.put(base + 0, f32(c * sx));
        discard data.put(base + 1, f32(s * sx));
        discard data.put(base + 2, f32(-1.0 * s * sy));
        discard data.put(base + 3, f32(c * sy));
        discard data.put(base + 4, f32(tx));
        discard data.put(base + 5, f32(ty));
        discard data.put(base + 6, f32(uvo#x));
        discard data.put(base + 7, f32(uvo#y));
        discard data.put(base + 8, f32(uvs#x));
        discard data.put(base + 9, f32(uvs#y));
        discard data.put(base + 10, color#r);
        discard data.put(base + 11, color#g);
        discard data.put(base + 12, color#b);
        discard data.put(base + 13, drawable#alpha);
        discard data.put(base + 14, if (useTex) 1.0f32 else 0.0f32);
        discard data.put(base + 15, if (sdf) 1.0f32 else 0.0f32);
        discard data.put(base + 18, f32(sx));
        discard data.put(base + 19, f32(sy));
        match drawable#style {
            case None =>
                discard data.put(base + 16, 0.0f32);
                discard data.put(base + 17, 0.0f32);
                discard data.put(base + 20, 0.0f32);
                discard data.put(base + 21, 0.0f32);
                discard data.put(base + 22, 0.0f32);
                discard data.put(base + 23, 0.0f32);
                discard data.put(base + 24, 0.0f32);
                discard data.put(base + 25, 0.0f32);
                discard data.put(base + 26, 0.0f32);
                discard data.put(base + 27, 0.0f32);
                discard data.put(base + 28, 0.0f32);
                discard data.put(base + 29, 0.0f32);
                discard data.put(base + 30, 0.0f32);
                discard data.put(base + 31, 0.0f32);
                discard data.put(base + 32, 0.0f32);
                discard data.put(base + 33, 0.0f32);
                discard data.put(base + 34, 0.0f32);
                discard data.put(base + 35, 0.0f32);
                discard data.put(base + 36, 0.0f32);
                discard data.put(base + 37, 0.0f32)
            case Some(st) =>
                // hatch の有効判定は drawSprite の hatchOn と同式(period<=0 は GLSL の mod が未定義なので無効扱い)。
                let hatch = if (st#stripeWidth > 0.0 and st#stripeAlpha > 0.0f32 and st#stripePeriod > 0.0) 1.0f32 else 0.0f32;
                let bc = st#borderColor;
                let hc = st#stripeColor;
                let cc = st#checkerColor;
                discard data.put(base + 16, 1.0f32);
                discard data.put(base + 17, hatch);
                discard data.put(base + 20, f32(st#cornerRadius));
                discard data.put(base + 21, f32(st#borderWidth));
                discard data.put(base + 22, bc#r);
                discard data.put(base + 23, bc#g);
                discard data.put(base + 24, bc#b);
                discard data.put(base + 25, st#borderAlpha);
                discard data.put(base + 26, hc#r);
                discard data.put(base + 27, hc#g);
                discard data.put(base + 28, hc#b);
                discard data.put(base + 29, st#stripeAlpha);
                discard data.put(base + 30, f32(st#stripeWidth));
                discard data.put(base + 31, f32(st#stripePeriod));
                discard data.put(base + 32, Int32.toFloat32(st#stripeDir));
                discard data.put(base + 33, f32(st#checkerCell));
                discard data.put(base + 34, cc#r);
                discard data.put(base + 35, cc#g);
                discard data.put(base + 36, cc#b);
                discard data.put(base + 37, st#checkerAlpha)
        }

    /// 多角形を三角形へほどいたときの頂点数の上限（1 個 n 頂点なら 3(n-2) 以下）。
    /// 入れ物をこの数で先に広げておけば、溜めている途中で取り直す
    /// （＝書きかけを捨てる）ことが起きない。
    def polyVertCap(polygons: List[RenderType.PolygonCmd]): Int32 =
        3 * List.foldLeft((acc, pc) -> acc + List.length(pc#vertices), 0, polygons)

    /// 1 フレーム描画: タイル層・sprites・polygons・静的レンジ・シェーダー面を
    /// 1 本の安定ソート列に混ぜ、共有の zIndex どおりの重なり順で描く。
    /// 黒帯部分は scissor で clear する。
    pub def renderFrameMixed(args: FrameArgs): Unit \ IO =
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
        let staticRanges = args#staticRanges;
        let polyBatchShader = args#polyBatchShader;
        let polyBatchVao = args#polyBatchVao;
        let polyBatchVbo = args#polyBatchVbo;
        let polyBatchUniforms = args#polyBatchUniforms;
        let instShader   = args#instShader;
        let instVao      = args#instVao;
        let instVbo      = args#instVbo;
        let instBuf      = args#instBuf;
        let polyBuf      = args#polyBuf;
        let tileUniforms = args#tileUniforms;
        let instMultiplyBlend = args#instMultiplyBlend;
        let surfaces     = args#surfaces;
        let drawSurface  = args#drawSurface;
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
            // タイル層・sprites・polygons・静的レンジ・シェーダー面を 1 本の安定ソート列に
            // マージして描く。sprite だけ z 順にし polygon を最後へまとめて描くと、ワールド
            // 配置のポリゴン（武器グリフ等）が手前のポップアップを貫通してしまう。全種を
            // 同じ列で並べることで、重なり順が並べ替え鍵の指定どおりになる。静的レンジは
            // 「頂点は既に GPU にある永続 VBO の範囲」を軽い値で表す run 種で、同鍵の
            // 動的アイテムとの前後も入力順で保たれる（洞窟の壁 z=2 が粒 z=2 を正しく隠す等）。
            // 同一鍵内は入力順（tiles → sprites → polygons → static → surfaces）を保つ
            // （stableByZ が構造的に保証）。シェーダー面は zIndex の位置で両 run を吐いてから
            // 1 枚描くので、水を床(z=0)の上・壁(z=2)の下に置ける（clear 直後の一括描画だと
            // zIndex を無視して最下になり、不透明な背景に覆われて消える）。
            // 同 z 内は入力順 = tiles → sprites → polygons → static → surfaces なので、
            // 「同 z ならタイル層が奥」が安定ソートの規約としてそのまま立つ
            // （タイル層を手前に出すには大きい zIndex）。
            let sortedMerged = mergedByZ(tileMaps, sprites, polygons, staticRanges, surfaces);
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
            // 書き溜める先は 1 フレーム 1 本の使い回し。溜まった run を吐くたびに
            // 先頭へ戻すので、要る大きさは「一番大きい run」ぶんで足りる。
            RenderBuf.ensure(instBuf, Int32.max(1, List.length(sprites)) * 38);
            RenderBuf.ensure(polyBuf, Int32.max(3, polyVertCap(polygons)) * 6);
            let instData = RenderBuf.buffer(instBuf);
            let polyData = RenderBuf.buffer(polyBuf);
            let writeInst = (slot: Int32, pos: Vec2.Vec2, size: Vec2.Vec2,
                             drawable: RenderType.Drawable, useTex: Bool, sdf: Bool) ->
                writeInstAt(instData, slot, pos, size, drawable, useTex, sdf);
            // run = (テクスチャ id, scissor キー, blend, 体数)。中身は入れ物の先頭から
            // 詰まっているので、run そのものは体数だけ覚えていればよい。
            // texId=0 は単色矩形の run。scissor キーか blend が変わるところでも run を切る
            // （blend は GL のグローバル状態なので、混ぜると run 全体が同じ重ね方になってしまう）。
            let emptyRun: (Int32, Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32) =
                (0, None, DrawCmd.BlendMode.Normal, 0);
            // 空 run では scissor / blend を触らない — GL 状態を無駄に往復させない。
            let flush = (acc: (Int32, Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32)) -> {
                let (accTex, accClip, accBlend, accCount) = acc;
                if (accCount == 0) () else {
                    setScissor(accClip);
                    RenderSprite.drawSpriteInstancedBuf(instShader, instVao, instVbo, accTex,
                                                        instMultiplyBlend, accBlend, instData, accCount)
                }
            };
            // 積むときにその場で入れ物へ書く。テクスチャ・窓・重ね方が変わるところでは
            // **先に**溜めた run を吐く — 吐くと書き込み位置が先頭へ戻るため、
            // 書いてから吐くと新しい 1 体が前の run に混ざって出てしまう。
            let push = (acc: (Int32, Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32),
                        texId: Int32, clipK: Option[(Int32, Int32, Int32, Int32)],
                        blend: DrawCmd.BlendMode,
                        pos: Vec2.Vec2, size: Vec2.Vec2, drawable: RenderType.Drawable,
                        useTex: Bool, sdf: Bool) -> {
                let (accTex, accClip, accBlend, accCount) = acc;
                if (accCount == 0) {
                    writeInst(0, pos, size, drawable, useTex, sdf);
                    (texId, clipK, blend, 1)
                } else if (accTex == texId and accClip == clipK and accBlend == blend) {
                    writeInst(accCount, pos, size, drawable, useTex, sdf);
                    (accTex, accClip, accBlend, accCount + 1)
                } else {
                    flush(acc);
                    writeInst(0, pos, size, drawable, useTex, sdf);
                    (texId, clipK, blend, 1)
                }
            };
            // 多角形 run = (scissor キー, blend, 積んだ頂点数, 三角形頂点配列の逆順リスト)。
            // 切り抜き窓か blend が変わるところで run を切る（スプライト run と同じ理由:
            // scissor と blend は GL のグローバル状態なので 1 バッチ内で均一でないといけない）。
            // 1 バッチにまとめても頂点は入力順のまま連結する。GL は 1 draw call 内の三角形を
            // 提出順に処理するので、重なった多角形どうしのアルファ合成も 1 枚ずつ描いたときと同じ結果になる。
            let emptyPolyRun: (Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32) =
                (None, DrawCmd.BlendMode.Normal, 0);
            let flushPoly = (acc: (Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32)) -> {
                let (accClip, accBlend, accCount) = acc;
                if (accCount == 0) () else {
                    setScissor(accClip);
                    RenderSprite.drawPolygonBatchBuf(polyBatchShader, polyBatchVao, polyBatchVbo,
                                                     polyBatchUniforms, accBlend, polyData, accCount)
                }
            };
            // 静的レンジ 1 本を描く: 溜まっている両 run は呼び側で吐き終えている前提。
            // scissor をレンジの clip に合わせ、永続 VBO の範囲を 1 draw call で塗る
            // （アップロードも三角形化もしない）。
            let drawStatic = (r: RenderStatic.Range) -> {
                setScissor(clipKeyOf(r#clip));
                RenderSprite.drawStaticRange(polyBatchShader, r#vao, polyBatchUniforms, r#blend,
                                             r#viewOffset, r#viewScale, r#halfDesign, r#first, r#count)
            };
            // 1 多角形を三角形化し、各頂点を 6 floats (x, y, r, g, b, a) にして入れ物へ直に書く。
            // 色×alpha は頂点属性に畳み込む（drawPolygon が uniform で渡していた spriteColor /
            // spriteAlpha と同じ値を頂点ごとに持たせるだけなので絵は変わらない）。
            // 展開（単色の耳切り / grad の扇割り＋頂点色）は RenderSprite.writePolyVerts に共通化。
            // 窓か重ね方が変わるところでは先に吐く — 吐くと書き込み位置が先頭へ戻るため。
            let pushPoly = (acc: (Option[(Int32, Int32, Int32, Int32)], DrawCmd.BlendMode, Int32),
                            clipK: Option[(Int32, Int32, Int32, Int32)], blend: DrawCmd.BlendMode,
                            pc: RenderType.PolygonCmd) -> {
                let (accClip, accBlend, accCount) = acc;
                if (accCount == 0) {
                    let n = RenderSprite.writePolyVerts(polyData, 0, pc);
                    // 頂点数が 3 未満（退化）なら何も積まない（drawPolygon の n<3 と同じ扱い）。
                    if (n < 3) acc else (clipK, blend, n)
                } else if (accClip == clipK and accBlend == blend) {
                    let n = RenderSprite.writePolyVerts(polyData, accCount, pc);
                    if (n < 3) acc else (accClip, accBlend, accCount + n)
                } else {
                    flushPoly(acc);
                    let n = RenderSprite.writePolyVerts(polyData, 0, pc);
                    if (n < 3) emptyPolyRun else (clipK, blend, n)
                }
            };
            // スプライト run と多角形 run を並行して溜める。種類が切り替わる瞬間に
            // もう一方を吐き出すことで、sortedMerged の列順（＝重なり順）を厳密に守る。
            // 同一時点で両 run が非空になることはない（切替時に必ず flush する）。
            let (lastRun, lastPolyRun) = List.foldLeft((acc, item) -> {
                let (sRun, pRun) = acc;
                match item {
                    case Merged.MTile(tm) =>
                        // タイル層が来たら両 run を吐いてから 1 draw call で描く（列順を守る）。
                        // 層は画面全体に敷くので scissor は viewport 全体へ戻し、blend は
                        // TileMapRenderCmd が blend を持たない（常に Normal）ため明示的に戻す
                        // （前 run の Add/Multiply を持ち越さない）。
                        flush(sRun);
                        flushPoly(pRun);
                        setScissor(None);
                        RenderSprite.applyBlend(DrawCmd.BlendMode.Normal);
                        match Map.get(tm#textureName, registry) {
                            case Some(texInfo) =>
                                RenderSprite.drawTileMapInstanced(tileShader, GpuHandle.textureIdInt(texInfo#id), GpuHandle.tileVaoInt(tm#tileVaoId),
                                                     tileUniforms,
                                                     tm#position, tm#tileSize, tm#tileScale,
                                                     tm#color, tm#tileCount)
                            // texture 未登録は従来どおり描かない（穴も開けない）。
                            case None => ()
                        };
                        (emptyRun, emptyPolyRun)
                    case Merged.MSprite(drawable) =>
                        // スプライトが来たら溜まっている多角形 run を先に吐く（列順を守る）。
                        flushPoly(pRun);
                        let sRun2 = if (String.isEmpty(drawable#texture)) {
                            push(sRun, 0, clipKeyOf(drawable#clip), drawable#blend,
                                 drawable#position, drawable#scale, drawable, false, false)
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
                                    push(sRun, GpuHandle.textureIdInt(texInfo#id), clipKeyOf(drawable#clip),
                                         drawable#blend,
                                         pos, displaySize, drawable, true, isFont)
                                // texture 未登録は従来どおり描かない。描かないだけなので run は途切れさせない。
                                case None => sRun
                            }
                        };
                        (sRun2, emptyPolyRun)
                    case Merged.MPoly(pc) =>
                        // 多角形が来たら溜まっているスプライト run を先に吐く（列順を守る）。
                        flush(sRun);
                        (emptyRun, pushPoly(pRun, clipKeyOf(pc#clip), pc#blend, pc))
                    case Merged.MStatic(r) =>
                        // 静的レンジが来たら両 run を吐いてから 1 draw call で描く（列順を守る）。
                        flush(sRun);
                        flushPoly(pRun);
                        drawStatic(r);
                        (emptyRun, emptyPolyRun)
                    case Merged.MSurface(s) =>
                        // シェーダー面が来たら両 run を吐いてから 1 枚描く（列順＝重なり順を守る）。
                        // 面は矩形全体を塗るので scissor は viewport 全体に戻す（前 run の clip 窓を持ち越さない）。
                        flush(sRun);
                        flushPoly(pRun);
                        setScissor(None);
                        drawSurface(s);
                        (emptyRun, emptyPolyRun)
                }
            }, (emptyRun, emptyPolyRun), sortedMerged);
            // どちらか片方だけが非空（切替時に相手を吐いているため）。空 flush は no-op。
            flush(lastRun);
            flushPoly(lastPolyRun);
            // フレーム末尾で必ず scissor を解除する — 有効なまま持ち越すと、次フレームの
            // 全画面 clear や F8 注釈のスクリーンショット再描画が小矩形に切られる。
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            // blend も Normal に戻す — Add/Multiply のまま持ち越すと、次フレーム冒頭の
            // タイルマップや F8 注釈の再描画が違う重ね方で合成される。
            RenderSprite.applyBlend(DrawCmd.BlendMode.Normal)
        } else ()

}
