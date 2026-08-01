// Bakery — ギャラリー焼きの共通配管。描画コマンド列を PNG に、フレーム列を GIF＋コマ別 PNG に
// 焼き、SnapshotSite 用のフィルムストリップ情報を返す。
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

    /// ゲームごとに 1 回宣言する焼き込み設定。design を `scale` 倍に拡大して出力する。
    /// texturePath は Drawable#texture 名 → PNG パス。fontAtlas はメトリクス、fontTtf は実サイズ焼き用 TTF。
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
    /// 実機は画素をそのまま GPU へ上げられるが、焼き（SoftRaster）はファイルからしか
    /// 絵を読めない。この差をゲームごとに埋めていると、焼き忘れた絵だけが gallery で
    /// 消えて golden が実機を守れなくなる — だから配管はここが持つ。
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

    /// 焼く前に「この経路では絵に出ない指定」を知らせる。黙って落とすと、実機と違う絵が
    /// golden に固定されてしまう（bake で証明する流儀そのものが嘘をつく）。
    def warnDropped(drawables: List[GameEngine.Drawable], name: String): Unit \ IO =
        SoftRaster.dropped(drawables)
            |> List.forEach(x -> println("${SoftRaster.droppedLine(x)}（${name}）"))

    /// 描画コマンド列を 1 枚の PNG に焼く（World を介さない場面や、投影済みの静止画に使う）。
    pub def renderPng(cfg: BakeConfig, drawables: List[GameEngine.Drawable],
                      polygons: List[GameEngine.PolygonRenderCmd], name: String): Unit \ IO =
        warnDropped(drawables, name);
        SoftRaster.render(reqOf(cfg, drawables, polygons, pngPath(cfg, name)))

    /// 複数フォントで焼く renderPng。`extraFonts` はテクスチャ名（実機の project.json の
    /// fonts[].name に "font_" を付けた物。HeadlessFont.buildAtlas が付ける名前と同じ）→ その本。
    /// 既定フォント（cfg#fontTtf / cfg#fontAtlas）はそのまま効くので、混ぜたい本だけ渡す。
    /// 名前が実機と食い違うと、その字は既定フォントで描かれる（消えはしない）。
    pub def renderPngFonts(cfg: BakeConfig, extraFonts: Map[String, SoftRaster.FontEntry],
                           drawables: List[GameEngine.Drawable],
                           polygons: List[GameEngine.PolygonRenderCmd], name: String): Unit \ IO =
        warnDropped(drawables, name);
        SoftRaster.renderFonts(reqOf(cfg, drawables, polygons, pngPath(cfg, name)), extraFonts)

    /// 宣言シェーダー面つきの renderPng。surfaces（Render.shaderSurfaces の出力と同形の
    /// 構造レコード）は ShaderEval の画素評価で焼かれ、z 順で他の描き物と合流する。
    /// 渡す側は draw の代表色ベタ塗りと二重にならないよう、items を Render.withoutShaders で
    /// 外してから draw すること。
    pub def renderPngWith(cfg: BakeConfig, drawables: List[GameEngine.Drawable],
                          polygons: List[GameEngine.PolygonRenderCmd],
                          surfaces: List[SoftRaster.SurfaceCmd], name: String): Unit \ IO =
        warnDropped(drawables, name);
        SoftRaster.renderWithSurfaces(reqOf(cfg, drawables, polygons, pngPath(cfg, name)), surfaces)

    /// frames を stride 枚ごとに間引き、各コマを toCmds で描いて GIF ＋ コマ別 PNG に焼く。
    /// 返り値は SnapshotSite 用のフィルムストリップ情報（駒送りビューア）。
    pub def bakeGif(cfg: BakeConfig, frames: List[w], stride: Int32,
                    toCmds: w -> (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]),
                    name: String): SnapshotSite.Filmstrip \ IO =
        bakeGifFonts(cfg, Map.empty(), frames, stride, toCmds, name)

    /// 複数フォントで焼く bakeGif。`extraFonts` はテクスチャ名（実機の project.json の
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
        // コマ別 PNG は「描くたびに 1 枚ずつ」書く（最後に一括ではなく）— 長い焼きの最中でも
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
        let images = List.zipWithIndex(sampled) |> List.map(pair -> {
            let (i, w) = pair;
            let (drawables, polygons, surfaces) = toCmds(w);
            let img = SoftRaster.renderToImageWith(reqOf(cfg, drawables, polygons, gifPath(cfg, name)), surfaces);
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
