// Bakery — ギャラリー生成の共通配管。描画コマンド列を PNG に、フレーム列を GIF＋コマ別 PNG に
// 生成し、SnapshotSite 用のフィルムストリップ情報を返す。
//
// 各ゲームは「1回だけ宣言する設定（BakeConfig）」と「World → 描画コマンドへの投影」だけ用意すれば、
// RasterReq 組み立て・SoftRaster 呼び出し・GIF エンコード・コマ別 PNG 書き出し・間引きは Bakery に任せられる。
// GL 不要なので画面の無い場所（テスト・CI）で走る。
//
// Replay はここに含めない（engine_world に住むため）。ゲーム側で Replay.timeline した frames: List[w] を
// 渡す。投影も engine 型 (GameEngine.Drawable / PolygonRenderCmd) で受け取り、engine_world に依存しない。

mod Bakery {
    import java.awt.image.BufferedImage
    import java.io.File

    /// ゲームごとに 1 回宣言する生成設定。design を `scale` 倍に拡大して出力する。
    /// texturePath は Drawable#texture 名 → PNG パス。fontAtlas はメトリクス、fontTtf は実サイズ生成用 TTF。
    pub type alias BakeConfig = {
        design      = Vec2.Vec2,
        scale       = Int32,
        background  = Color,
        texturePath = Map[String, String],
        fontTtf     = String,
        fontAtlas   = FontAtlas,
        outDir      = String,
        frameW      = Int32,
        frameH      = Int32,
        gifDelayMs  = Int32,
        gifFps      = Int32
    }

    /// 走行中に作った正方形の絵（ドット絵アトラスなど）を PNG に落とし、
    /// 「名前 → PNG パス」の表を返す。BakeConfig#texturePath にそのまま入れられる。
    ///
    /// 実機は画素をそのまま GPU へ上げられるが、生成（SoftRaster）はファイルからしか
    /// 絵を読めない。この差をゲームごとに埋めていると、生成し忘れた絵だけが gallery で
    /// 消えてスナップショットが実機を守れなくなる — だから配管はここが持つ。
    pub def imagePngs(outDir: String,
                      images: List[{ name = String, side = Int32,
                                     pixelAt = (Int32, Int32) -> Int32 }]): Map[String, String] \ IO =
        discard (new File(outDir)).mkdirs();
        images |> List.foldLeft((acc, img) -> {
            if (img#side <= 0) acc
            else {
                let path = "${outDir}/${img#name}.png";
                SoftRaster.writeRadialPng(img#side, img#pixelAt, path);
                Map.insert(img#name, path, acc)
            }
        }, Map.empty())

    /// 同じ絵の一覧から「名前 → テクスチャの寸法」を引く関数を作る（Render.drawWith に渡す）。
    /// UV を解くのに辺長が要るので、PNG のパスだけでは足りない。
    pub def imageTextureInfo(images: List[{ name = String, side = Int32 | r }]):
            String -> Option[{ id = GpuHandle.TextureId, width = Float64, height = Float64 }] =
        let sides = images |> List.foldLeft((acc, img) ->
            Map.insert(img#name, img#side, acc), Map.empty());
        name -> Map.get(name, sides) |> Option.map(side ->
            { id = GpuHandle.wrapTextureId(0), width = Int32.toFloat64(side),
              height = Int32.toFloat64(side) })

    def reqOf(cfg: BakeConfig, drawables: List[GameEngine.Drawable],
              polygons: List[GameEngine.PolygonRenderCmd], outPath: String): SoftRaster.RasterReq =
        { drawables = drawables, polygons = polygons,
          design = cfg#design, scale = cfg#scale, background = cfg#background,
          texturePath = cfg#texturePath, fontTtf = cfg#fontTtf, fontAtlas = cfg#fontAtlas,
          outPath = outPath }

    def pngPath(cfg: BakeConfig, name: String): String = "${cfg#outDir}/${name}.png"
    def gifPath(cfg: BakeConfig, name: String): String = "${cfg#outDir}/${name}.gif"

    /// 生成する前に「この経路では絵に出ない指定」を知らせる。黙って落とすと、実機と違う絵が
    /// スナップショットに固定されてしまう（bake で証明する流儀そのものが嘘をつく）。
    def warnDropped(drawables: List[GameEngine.Drawable], name: String): Unit \ IO =
        SoftRaster.dropped(drawables)
            |> List.forEach(x -> println("${SoftRaster.droppedLine(x)}（${name}）"))

    /// 描画コマンド列を 1 枚の PNG に生成する（World を介さない場面や、投影済みの静止画に使う）。
    pub def renderPng(cfg: BakeConfig, drawables: List[GameEngine.Drawable],
                      polygons: List[GameEngine.PolygonRenderCmd], name: String): Unit \ IO =
        warnDropped(drawables, name);
        SoftRaster.render(reqOf(cfg, drawables, polygons, pngPath(cfg, name)))

    /// 複数フォントで生成する renderPng。`extraFonts` はテクスチャ名（実機の project.json の
    /// fonts[].name に "font_" を付けた物。HeadlessFont.buildAtlas が付ける名前と同じ）→ その本。
    /// 既定フォント（cfg#fontTtf / cfg#fontAtlas）はそのまま効くので、混ぜたい本だけ渡す。
    /// 名前が実機と食い違うと、その字は既定フォントで描かれる（消えはしない）。
    pub def renderPngFonts(cfg: BakeConfig, extraFonts: Map[String, SoftRaster.FontEntry],
                           drawables: List[GameEngine.Drawable],
                           polygons: List[GameEngine.PolygonRenderCmd], name: String): Unit \ IO =
        warnDropped(drawables, name);
        SoftRaster.renderFonts(reqOf(cfg, drawables, polygons, pngPath(cfg, name)), extraFonts)

    /// 宣言シェーダー面つきの renderPng。surfaces（Render.shaderSurfaces の出力と同形の
    /// 構造レコード）は ShaderEval の画素評価で生成され、z 順で他の描き物と合流する。
    /// 面の tex 場（Field.Tex）が読めるのはゲームのテクスチャだけ — pass の名前も読むなら
    /// renderPngWithPasses / renderPngWithImages を使う。
    /// 渡す側は draw の代表色ベタ塗りと二重にならないよう、items を Render.withoutShaders で
    /// 外してから draw すること。
    pub def renderPngWith(cfg: BakeConfig, drawables: List[GameEngine.Drawable],
                          polygons: List[GameEngine.PolygonRenderCmd],
                          surfaces: List[SoftRaster.SurfaceCmd], name: String): Unit \ IO =
        warnDropped(drawables, name);
        SoftRaster.renderWithSurfaces(reqOf(cfg, drawables, polygons, pngPath(cfg, name)), surfaces)

    // ════════════════════════════════════════════════════════
    // シルエット生成 — 造形（形が物として読めるか）を目視するための材料づくり
    // ════════════════════════════════════════════════════════

    /// シルエット生成の絞り方。既定に使うのは WorldBand — 全アイテムを黒にすると画面が
    /// 1 つの塊に融けて個々の形が見えないため、まず主役の z-index の範囲（world の範囲）だけに絞る。
    /// All（全アイテム黒）の用途は画面全体の重心確認に限る（docs/drawing-floor.md）。
    pub enum SilhouetteScope {
        case WorldBand
        case All
    }

    /// scope が z を対象に含むか。world の範囲の上端は UI 層の底（CanvasLayer.layerStride）。
    def silhouetteKeeps(scope: SilhouetteScope, z: Int32): Bool =
        match scope {
            case SilhouetteScope.WorldBand => z < CanvasLayer.layerStride()
            case SilhouetteScope.All       => true
        }

    /// 描画コマンド列を「対象は真っ黒・それ以外は落とす」に写す純関数。背景を白にして
    /// 生成すれば、シルエットだけで何か分かるか（絵の下限の 5 つ目の性質）を目で確かめられる。
    /// 形の良し悪しの判定はしない — 機械は見やすい材料を出すまで。
    pub def silhouette(scope: SilhouetteScope,
                       drawables: List[GameEngine.Drawable],
                       polygons: List[GameEngine.PolygonRenderCmd]):
                       (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        (drawables |> List.filter(d -> silhouetteKeeps(scope, d#zIndex)) |> List.map(blackenDrawable),
         polygons  |> List.filter(p -> silhouetteKeeps(scope, p#zIndex)) |> List.map(blackenPolygon))

    def silhouetteInk(): Color = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }

    /// Drawable を真っ黒の不透明に写す。texture は消さない — 絵の抜き（形）はテクスチャの
    /// α が持っていて、色は黒 tint の乗算で消えるため。blend は Normal に倒す（Add は黒を
    /// 足しても何も描かず、形ごと消える）。alpha を 1 に上げるのは、半透明の濃淡は塗りの
    /// 情報で、形の検査には雑音だから。
    def blackenDrawable(d: GameEngine.Drawable): GameEngine.Drawable =
        { color = silhouetteInk(), alpha = 1.0f32, blend = DrawCmd.BlendMode.Normal,
          style = d#style |> Option.map(st ->
              { borderColor = silhouetteInk(), stripeColor = silhouetteInk(),
                checkerColor = silhouetteInk() | st }) | d }

    /// 多角形を真っ黒の不透明に写す。grad は外す — 頂点ごとの色は面の情報で、
    /// 残すと補間の縁が灰色に出てシルエットの縁が濁る。
    def blackenPolygon(p: GameEngine.PolygonRenderCmd): GameEngine.PolygonRenderCmd =
        { color = silhouetteInk(), alpha = 1.0f32, blend = DrawCmd.BlendMode.Normal,
          grad = None | p }

    /// シルエット PNG を生成する（renderPng の変形版）。対象を黒・背景を白で <name>.png に書く。
    /// 背景白を cfg でなくここで固定するのは、シルエットの読み取りが黒 / 白の 2 値で
    /// 成り立つ検査で、ゲームごとの背景色が混ざると意味が変わるため。
    pub def silhouettePng(cfg: BakeConfig, scope: SilhouetteScope,
                          drawables: List[GameEngine.Drawable],
                          polygons: List[GameEngine.PolygonRenderCmd], name: String): Unit \ IO =
        let (blackDrawables, blackPolygons) = silhouette(scope, drawables, polygons);
        renderPng({ background = { r = 1.0f32, g = 1.0f32, b = 1.0f32 } | cfg },
                  blackDrawables, blackPolygons, name)

    // ════════════════════════════════════════════════════════
    // pass（レンダーターゲット）— 本編より先に別画像へ描き、名前で本編から貼る
    // ════════════════════════════════════════════════════════

    /// pass 1 枚ぶんの宣言（Render.Pass のコマンド列版）。name はそのままテクスチャ名になり、
    /// 本編の drawables から普通のスプライトとして参照できる。本編のシェーダー面の tex 場
    ///（Field.Tex）も同じ name で生成した絵を読める。
    /// drawables へ下ろすときは items を Render.withoutShaders で外してから Render.draw する
    /// こと — GL はターゲットの中の Shader 面を描かないので、代表色ベタ塗りが混ざると実機とズレる。
    pub type alias PassSpec = {
        name = String,
        clear = RenderTarget.LoadOp,
        drawables = List[GameEngine.Drawable],
        polygons = List[GameEngine.PolygonRenderCmd]
    }

    /// pass 1 枚を design 解像度（scale = 1）の画像に生成する。GL のターゲットが design ×1 の
    /// テクスチャなので、ここで cfg#scale を掛けると本編に貼るときの拡大と二重になる。
    /// clear が Clear ならその色（不透明）で塗ってから — prev は見ない（GL の glClear と
    /// 同じで、塗った時点で前の中身は消えるため）。ClearTransparent も prev を見ずに透明から。
    /// Keep なら prev のコピーの上に描き足し（残像・軌跡を GIF やプレロールで再現する口）、
    /// prev が無ければ透明から。
    pub def bakePassImage(cfg: BakeConfig, p: PassSpec,
                          prev: Option[BufferedImage]): BufferedImage \ IO =
        bakePassImageWith(cfg, Map.empty(), p, prev)

    /// bakePassImage の「先に生成したターゲットも参照できる」版。`images` は既に生成した pass の
    /// 名前 → 画像（GL が宣言順に描くのと同じで、後の pass は前の pass を貼れる）。
    pub def bakePassImageWith(cfg: BakeConfig, images: Map[String, BufferedImage],
                              p: PassSpec, prev: Option[BufferedImage]): BufferedImage \ IO =
        let req = { scale = 1 | reqOf(cfg, p#drawables, p#polygons, "") };
        match p#clear {
            case RenderTarget.LoadOp.Clear(c)         => SoftRaster.renderToImageFull({ background = c | req }, Nil, Map.empty(), images)
            case RenderTarget.LoadOp.Keep             => SoftRaster.renderPassImage(req, prev, images)
            case RenderTarget.LoadOp.ClearTransparent => SoftRaster.renderPassImage(req, None, images)
        }

    /// 追加の生成済み画像（pass のレンダーターゲットなど）を textures に混ぜて本編を PNG に生成する。
    pub def renderPngWithImages(cfg: BakeConfig, images: Map[String, BufferedImage],
                                drawables: List[GameEngine.Drawable],
                                polygons: List[GameEngine.PolygonRenderCmd],
                                surfaces: List[SoftRaster.SurfaceCmd], name: String): Unit \ IO =
        warnDropped(drawables, name);
        SoftRaster.renderFull(reqOf(cfg, drawables, polygons, pngPath(cfg, name)),
            surfaces, Map.empty(), images)

    /// passes を宣言順に生成してから本編を PNG に生成する（GL の renderFrame と同じ順序 —
    /// 後の pass の drawables は先に生成した pass の名前を貼れる）。
    /// 本編の drawables 同様、pass の items も Render.withoutShaders → Render.draw で
    /// 下ろすこと（PassSpec の doc の約束）。
    pub def renderPngWithPasses(cfg: BakeConfig, passes: List[PassSpec],
                                drawables: List[GameEngine.Drawable],
                                polygons: List[GameEngine.PolygonRenderCmd],
                                surfaces: List[SoftRaster.SurfaceCmd], name: String): Unit \ IO =
        // pass の中の生成できない指定も本編と同じに知らせる（本編ぶんは renderPngWithImages が出す）。
        passes |> List.forEach(p -> warnDropped(p#drawables, "${name}:pass ${p#name}"));
        let images = passes |> List.foldLeft((acc, p) -> {
            Map.insert(p#name, bakePassImageWith(cfg, acc, p, None), acc)
        }, (Map.empty(): Map[String, BufferedImage]));
        renderPngWithImages(cfg, images, drawables, polygons, surfaces, name)

    /// frames を stride 枚ごとに間引き、各コマを toCmds で描いて GIF ＋ コマ別 PNG に生成する。
    /// 返り値は SnapshotSite 用のフィルムストリップ情報（駒送りビューア）。
    pub def bakeGif(cfg: BakeConfig, frames: List[w], stride: Int32,
                    toCmds: w -> (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]),
                    name: String): SnapshotSite.Filmstrip \ IO =
        bakeGifFonts(cfg, Map.empty(), frames, stride, toCmds, name)

    /// 複数フォントで生成する bakeGif。`extraFonts` はテクスチャ名（実機の project.json の
    /// fonts[].name に "font_" を付けた物。HeadlessFont.buildAtlas が付ける名前と同じ）→ その本。
    /// 既定フォント（cfg#fontTtf / cfg#fontAtlas）はそのまま効くので、混ぜたい本だけ渡す。
    /// 名前が実機と食い違うと、その字は既定フォントで描かれる（消えはしない）。
    pub def bakeGifFonts(cfg: BakeConfig, extraFonts: Map[String, SoftRaster.FontEntry],
                         frames: List[w], stride: Int32,
                         toCmds: w -> (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]),
                         name: String): SnapshotSite.Filmstrip \ IO =
        let sampled = every(stride, frames);
        // コマ列は同じ作りの絵が続くので、報告は先頭コマぶんだけ出す（同じ警告が何十行も並ばない）。
        List.head(sampled) |> Option.forEach(w -> warnDropped(fst(toCmds(w)), name));
        // コマ別 PNG は「描くたびに 1 枚ずつ」書く（最後に一括ではなく）— 長い生成の最中でも
        // Studio が frames/ をポーリングして、出来上がりつつあるコマを流し見できる。
        // 命名・画素は Filmstrip.bakeFrames と同じ経路（bakeFrame）なのでバイト列も変わらない。
        let images = List.zipWithIndex(sampled) |> List.map(pair -> {
            let (i, w) = pair;
            let (drawables, polygons) = toCmds(w);
            let img = SoftRaster.renderToImageFonts(reqOf(cfg, drawables, polygons, gifPath(cfg, name)), Nil, extraFonts);
            Filmstrip.bakeFrame(img, "${cfg#outDir}/frames/${name}/${i}.png");
            img
        });
        GifEncoder.encode(images, cfg#gifDelayMs, gifPath(cfg, name));
        { strip = "frames/${name}/", frameCount = List.length(images),
          frameW = cfg#frameW, frameH = cfg#frameH, fps = cfg#gifFps }

    /// シェーダー面つきの bakeGif（renderPngWith の GIF 版）。toCmds が各コマの
    /// (描き物, 多角形, シェーダー面) を返し、面は ShaderEval の画素評価で z 順に合流する。
    /// 渡す側は draw の代表色ベタ塗りと二重にならないよう、items を Render.withoutShaders で
    /// 外してから draw すること（renderPngWith と同じ約束）。
    /// 既存 bakeGif に surfaces 引数を足さないのは、面チャンネルの無い呼び元のシグネチャを
    /// 割らないため。
    pub def bakeGifWith(cfg: BakeConfig, frames: List[w], stride: Int32,
                        toCmds: w -> (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd],
                                      List[SoftRaster.SurfaceCmd]),
                        name: String): SnapshotSite.Filmstrip \ IO =
        let sampled = every(stride, frames);
        // コマ列は同じ作りの絵が続くので、報告は先頭コマぶんだけ出す（bakeGifFonts と同じ）。
        List.head(sampled) |> Option.forEach(w -> {
            let (drawables, _, _) = toCmds(w);
            warnDropped(drawables, name)
        });
        // 欠け名の知らせもコマ列で 1 本の控えを共有する（同じ警告がコマ数ぶん並ばない）。
        let warnLog = SoftRaster.freshTexWarnLog();
        let images = List.zipWithIndex(sampled) |> List.map(pair -> {
            let (i, w) = pair;
            let (drawables, polygons, surfaces) = toCmds(w);
            let img = SoftRaster.renderToImageLogged(reqOf(cfg, drawables, polygons, gifPath(cfg, name)),
                                                     surfaces, Map.empty(), Map.empty(), warnLog);
            Filmstrip.bakeFrame(img, "${cfg#outDir}/frames/${name}/${i}.png");
            img
        });
        GifEncoder.encode(images, cfg#gifDelayMs, gifPath(cfg, name));
        { strip = "frames/${name}/", frameCount = List.length(images),
          frameW = cfg#frameW, frameH = cfg#frameH, fps = cfg#gifFps }

    /// pass つきの bakeGif（renderPngWithPasses の GIF 版）。toCmds が各コマの
    /// (pass 列, 描き物, 多角形, シェーダー面) を返し、コマごとに pass を宣言順に生成してから
    /// 本編と合成する — 実機の App.withPasses と同じ順序で、後の pass は先に生成した pass の
    /// 名前を貼れる。items は本編・pass とも Render.withoutShaders → Render.draw で下ろす
    /// こと（renderPngWithPasses と同じ約束。pass は Render.passSpecOf が外してくれる）。
    /// pass の Keep はコマをまたいで持ち越さない — 実機の Keep は前フレームの画面を
    /// 引き継ぐが、GIF は途中のコマからも見られるので、頭出しの位置で絵が変わる生成物は
    /// スナップショットに固定できない。毎コマ透明から始める（静止画の renderPngWithPasses と同じ）。
    pub def bakeGifWithPasses(cfg: BakeConfig, frames: List[w], stride: Int32,
                              toCmds: w -> (List[PassSpec], List[GameEngine.Drawable],
                                            List[GameEngine.PolygonRenderCmd],
                                            List[SoftRaster.SurfaceCmd]),
                              name: String): SnapshotSite.Filmstrip \ IO =
        let sampled = every(stride, frames);
        // コマ列は同じ作りの絵が続くので、報告は先頭コマぶんだけ出す（bakeGifWith と同じ）。
        List.head(sampled) |> Option.forEach(w -> {
            let (passes, drawables, _, _) = toCmds(w);
            passes |> List.forEach(p -> warnDropped(p#drawables, "${name}:pass ${p#name}"));
            warnDropped(drawables, name)
        });
        // 欠け名の知らせもコマ列で 1 本の控えを共有する（同じ警告がコマ数ぶん並ばない）。
        let warnLog = SoftRaster.freshTexWarnLog();
        let images = List.zipWithIndex(sampled) |> List.map(pair -> {
            let (i, w) = pair;
            let (passes, drawables, polygons, surfaces) = toCmds(w);
            let passImages = passes |> List.foldLeft((acc, p) -> {
                Map.insert(p#name, bakePassImageWith(cfg, acc, p, None), acc)
            }, (Map.empty(): Map[String, BufferedImage]));
            let img = SoftRaster.renderToImageLogged(reqOf(cfg, drawables, polygons, gifPath(cfg, name)),
                                                     surfaces, Map.empty(), passImages, warnLog);
            Filmstrip.bakeFrame(img, "${cfg#outDir}/frames/${name}/${i}.png");
            img
        });
        GifEncoder.encode(images, cfg#gifDelayMs, gifPath(cfg, name));
        { strip = "frames/${name}/", frameCount = List.length(images),
          frameW = cfg#frameW, frameH = cfg#frameH, fps = cfg#gifFps }

    /// stride 枚ごとに 1 枚を残す（0 番から）。
    pub def every(stride: Int32, xs: List[a]): List[a] =
        List.zipWithIndex(xs)
            |> List.filterMap(pair -> { let (i, x) = pair; if (Int32.modulo(i, stride) == 0) Some(x) else None })

}
