// Gallery — Transition 4 種のフィルムストリップ・GIF と、fps オーバレイの見本を焼く。
// World を直接組んで SoftRaster で描くだけなので、実ウィンドウは要らない。

mod Gallery {
    import java.io.File

    // ── 焼き込み設定 ──
    def scale(): Int32 = 2                    // 出力は 640x480
    def frameW(): Int32 = 640
    def frameH(): Int32 = 480
    /// サイトのカード幅は出力画像の実寸と常に一致させる（二重定義にすると片方だけ変えて崩れる）。
    def pxWidth(): Int32 = frameW()
    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def outDir(): String = "gallery"
    def gifDelayMs(): Int32 = 100
    def gifFps(): Int32 = 10

    def bgColor(): Color = { r = 0.101961f32, g = 0.109804f32, b = 0.172549f32 }

    /// Bakery に渡す焼き込み設定（テクスチャなし・単色/文字だけの絵）。
    def config(atlas: FontAtlas): Bakery.BakeConfig =
        { design = View.design(), scale = scale(), background = bgColor(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outDir = outDir(), frameW = frameW(), frameH = frameH(),
          gifDelayMs = gifDelayMs(), gifFps = gifFps() }

    /// World を本番と同じ投影（View.frame）で描画コマンドへ変換する。
    def worldCmds(atlas: FontAtlas, world: World.World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let ctx = { atlas = atlas, visible = { position = Vec2.zero(), size = View.design() } };
        Render.draw(View.frame(ctx, world))

    /// 遷移 1 種を t=0 から t=1 まで動かした frames 列を作る（Replay を使わず自前で刻む。
    /// World が Transition.Progress を直に持つだけなので、これで十分に軽い）。
    /// 各コマは本番と同じ projectUi を通し、ラベルの bind 文言まで焼き込む。
    /// Progress はレコード直組みでなく start/advance で組む（内部の形に依存しない）。
    def timelineOf(ui: UiStore.UiWorld, kind: Transition.Kind, steps: Int32): List[World.World] =
        List.range(0, steps + 1) |> List.map(i -> {
            let t = Int32.toFloat64(i) / Int32.toFloat64(steps);
            let progress = Transition.start(World.duration())
                        |> Transition.advance(t * World.duration());
            GameUi.projectUi({ kind = kind, progress = progress, steps = 0, ui = ui })
        })

    /// 1 種類ぶんの GIF ＋ コマ別 PNG を焼く（8 コマ）。
    def bakeKind(atlas: FontAtlas, ui: UiStore.UiWorld, kind: Transition.Kind, name: String): SnapshotSite.Filmstrip \ IO =
        let frames = timelineOf(ui, kind, 7);
        Bakery.bakeGif(config(atlas), frames, 1, w -> worldCmds(atlas, w), name)

    /// fps オーバレイの見本（debug 表示と同じ絵を 1 枚）。App を起動せずに
    /// Annotate.fpsItems を直接呼んで合成する（App.fpsOverlayOf と同じロジック）。
    def fpsOverlayScene(atlas: FontAtlas, ui: UiStore.UiWorld): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let world = GameUi.projectUi({ kind = Transition.Kind.FadeOut,
                                       progress = Transition.start(World.duration()), steps = 0, ui = ui });
        let ctx = { atlas = atlas, visible = { position = Vec2.zero(), size = View.design() } };
        let sixtyFps = 1.0 / 60.0;
        let anno = List.range(0, 60) |> List.foldLeft((acc, _) -> Annotate.recordDt(sixtyFps, acc), Annotate.initial());
        let overlay = Annotate.fpsItems(atlas, View.design(), Annotate.fpsOf(anno));
        Render.draw(List.append(View.frame(ctx, world), overlay))

    // ── 全部を焼いてサイトを生成する（Bake.all から呼ぶ）──

    pub def bakeAll(): Unit \ IO =
        discard (new File(outDir())).mkdirs();
        let atlas = Harness.atlas();
        let ui = Harness.ui();

        let fadeOutFilm = bakeKind(atlas, ui, Transition.Kind.FadeOut, "fade_out");
        let fadeInFilm  = bakeKind(atlas, ui, Transition.Kind.FadeIn, "fade_in");
        let wipeLeftFilm  = bakeKind(atlas, ui, Transition.Kind.WipeLeft, "wipe_left");
        let wipeRightFilm = bakeKind(atlas, ui, Transition.Kind.WipeRight, "wipe_right");

        let (fpsDrawables, fpsPolys) = fpsOverlayScene(atlas, ui);
        Bakery.renderPng(config(atlas), fpsDrawables, fpsPolys, "fps_overlay");

        run {
            SnapshotSite.generate(
                { outDir = outDir(), title = "feature_lab Gallery", cssScale = 2 },
                catalog({ fadeOut = fadeOutFilm, fadeIn = fadeInFilm,
                          wipeLeft = wipeLeftFilm, wipeRight = wipeRightFilm }))
        } with Fs.FileWrite.runWithIO

    // ── カタログ（ページとカードの宣言）──

    type alias Films = {
        fadeOut = SnapshotSite.Filmstrip, fadeIn = SnapshotSite.Filmstrip,
        wipeLeft = SnapshotSite.Filmstrip, wipeRight = SnapshotSite.Filmstrip
    }

    def catalog(films: Films): List[SnapshotSite.Item] =
        gif("fade_out", "だんだん黒く覆っていく（t=0 素通し → t=1 全面黒）", "Transition", films#fadeOut) ::
        gif("fade_in", "覆いがだんだん晴れる（t=0 全面黒 → t=1 素通し）", "Transition", films#fadeIn) ::
        gif("wipe_left", "黒い帯が右から左へ画面を覆っていく", "Transition", films#wipeLeft) ::
        gif("wipe_right", "黒い帯が左から右へ画面を覆っていく", "Transition", films#wipeRight) ::
        png("fps_overlay", "debug 有効時に画面右上へ出す fps オーバレイの見本（60fps 固定 dt で計測）", "Debug") :: Nil

    def png(name: String, desc: String, scenario: String): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "png",
          pxWidth = pxWidth(), generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def gif(name: String, desc: String, scenario: String, filmstrip: SnapshotSite.Filmstrip): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "gif",
          pxWidth = pxWidth(), generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = Some(filmstrip) }
}
