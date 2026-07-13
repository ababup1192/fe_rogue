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

    def reqOf(cfg: BakeConfig, drawables: List[GameEngine.Drawable],
              polygons: List[GameEngine.PolygonRenderCmd], outPath: String): SoftRaster.RasterReq =
        { drawables = drawables, polygons = polygons,
          design = cfg#design, scale = cfg#scale, background = cfg#background,
          texturePath = cfg#texturePath, fontTtf = cfg#fontTtf, fontAtlas = cfg#fontAtlas,
          outPath = outPath }

    def pngPath(cfg: BakeConfig, name: String): String = "${cfg#outDir}/${name}.png"
    def gifPath(cfg: BakeConfig, name: String): String = "${cfg#outDir}/${name}.gif"

    /// 描画コマンド列を 1 枚の PNG に焼く（World を介さない場面や、投影済みの静止画に使う）。
    pub def renderPng(cfg: BakeConfig, drawables: List[GameEngine.Drawable],
                      polygons: List[GameEngine.PolygonRenderCmd], name: String): Unit \ IO =
        SoftRaster.render(reqOf(cfg, drawables, polygons, pngPath(cfg, name)))

    /// frames を stride 枚ごとに間引き、各コマを toCmds で描いて GIF ＋ コマ別 PNG に焼く。
    /// 返り値は SnapshotSite 用のフィルムストリップ情報（駒送りビューア）。
    pub def bakeGif(cfg: BakeConfig, frames: List[w], stride: Int32,
                    toCmds: w -> (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]),
                    name: String): SnapshotSite.Filmstrip \ IO =
        let sampled = every(stride, frames);
        let images = List.map(w -> {
            let (drawables, polygons) = toCmds(w);
            SoftRaster.renderToImage(reqOf(cfg, drawables, polygons, gifPath(cfg, name)))
        }, sampled);
        GifEncoder.encodeWithFrames(images, cfg#gifDelayMs, gifPath(cfg, name), "${cfg#outDir}/frames/${name}");
        { strip = "frames/${name}/", frameCount = List.length(images),
          frameW = cfg#frameW, frameH = cfg#frameH, fps = cfg#gifFps }

    /// stride 枚ごとに 1 枚を残す（0 番から）。
    pub def every(stride: Int32, xs: List[a]): List[a] =
        List.zipWithIndex(xs)
            |> List.filterMap(pair -> { let (i, x) = pair; if (Int32.modulo(i, stride) == 0) Some(x) else None })

}
