// Gallery — Transition 4 種のフィルムストリップ・GIF と、fps オーバレイの見本、
// AudioFade の音量カーブ PNG と「同じカーブを焼き込んだ」試聴 WAV を焼く。
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
    /// t=1 のコマも「再生中」として焼く（実機は done で Idle に戻るが、GIF は覆い切った絵で締めたい）。
    def timelineOf(ui: UiStore.UiWorld, kind: Transition.Kind, steps: Int32): List[World.World] =
        List.range(0, steps + 1) |> List.map(i -> {
            let t = Int32.toFloat64(i) / Int32.toFloat64(steps);
            let progress = Transition.start(World.duration())
                        |> Transition.advance(t * World.duration());
            GameUi.projectUi({ kind = kind, playing = Some(progress) | World.initial(ui) })
        })

    /// 1 種類ぶんの GIF ＋ コマ別 PNG を焼く（8 コマ）。
    def bakeKind(atlas: FontAtlas, ui: UiStore.UiWorld, kind: Transition.Kind, name: String): SnapshotSite.Filmstrip \ IO =
        let frames = timelineOf(ui, kind, 7);
        Bakery.bakeGif(config(atlas), frames, 1, w -> worldCmds(atlas, w), name)

    /// fps オーバレイの見本（debug 表示と同じ絵を 1 枚）。App を起動せずに
    /// Annotate.fpsItems を直接呼んで合成する（App.fpsOverlayOf と同じロジック）。
    def fpsOverlayScene(atlas: FontAtlas, ui: UiStore.UiWorld): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let world = GameUi.projectUi(World.initial(ui));
        let ctx = { atlas = atlas, visible = { position = Vec2.zero(), size = View.design() } };
        let sixtyFps = 1.0 / 60.0;
        let anno = List.range(0, 60) |> List.foldLeft((acc, _) -> Annotate.recordDt(sixtyFps, acc), Annotate.initial());
        let overlay = Annotate.fpsItems(atlas, View.design(), Annotate.fpsOf(anno));
        Render.draw(List.append(View.frame(ctx, world), overlay))

    // ── AudioFade: 音量カーブの図 ──

    def risingColor(): Color = { r = 0.360784f32, g = 0.831373f32, b = 0.462745f32 }   // 現れる側（緑）
    def fadingColor(): Color = { r = 0.905882f32, g = 0.415686f32, b = 0.376471f32 }   // 消える側（赤）
    def axisColor(): Color = { r = 0.55f32, g = 0.57f32, b = 0.65f32 }

    /// カーブ図のプロット領域（design 320x240 の内側。左に音量・下に時間の目盛りぶんの余白）。
    def plotLeft(): Float64 = 40.0
    def plotTop(): Float64 = 30.0
    def plotW(): Float64 = 250.0
    def plotH(): Float64 = 180.0

    /// (t, 音量) をプロット領域内の画面座標へ写す（音量 1.0 が上端）。
    def plotPoint(t: Float64, volume: Float64): Vec2.Vec2 =
        { x = plotLeft() + t * plotW(), y = plotTop() + (1.0 - volume) * plotH() }

    /// 音量カーブ 1 本ぶんの折れ線（64 分割）。volumeOf は線形なので今は直線だが、
    /// 呼び側で t を変形（イージング）した時もこの描き方のままで曲線になる。
    def curveItems(fade: AudioFade.Fade, color: Color): List[Render.PlacedItem] =
        let n = 64;
        List.range(0, n) |> List.map(i -> {
            let t0 = Int32.toFloat64(i) / Int32.toFloat64(n);
            let t1 = Int32.toFloat64(i + 1) / Int32.toFloat64(n);
            Render.lineSeg(plotPoint(t0, AudioFade.volumeOf(fade, t0)),
                           plotPoint(t1, AudioFade.volumeOf(fade, t1)), 2.0, color, 10)
        })

    /// 軸と最小限の目盛り（縦=音量 0..1、横=時間 t=0..1）。
    def axisItems(atlas: FontAtlas): List[Render.PlacedItem] =
        let origin = plotPoint(0.0, 0.0);
        let topLeft = plotPoint(0.0, 1.0);
        let bottomRight = plotPoint(1.0, 0.0);
        Render.lineSeg(topLeft, origin, 1.0, axisColor(), 5)
        :: Render.lineSeg(origin, bottomRight, 1.0, axisColor(), 5)
        :: { at = { x = 10.0, y = topLeft#y - 6.0 }, item = Render.text("1.0", atlas, 12.0, 5) }
        :: { at = { x = 10.0, y = origin#y - 6.0 }, item = Render.text("0.0", atlas, 12.0, 5) }
        :: { at = { x = origin#x - 10.0, y = origin#y + 8.0 }, item = Render.text("t=0", atlas, 12.0, 5) }
        :: { at = { x = bottomRight#x - 22.0, y = origin#y + 8.0 }, item = Render.text("t=1", atlas, 12.0, 5) }
        :: Nil

    /// カーブ図 1 枚（複数カーブの重ね描きも同じ口）を PNG に焼く。
    def bakeCurvePng(atlas: FontAtlas, curves: List[(AudioFade.Fade, Color)], name: String): Unit \ IO =
        let bg = { at = Vec2.zero(), item = Render.box(View.design(), bgColor(), 0) };
        let lines = curves |> List.flatMap(pair -> { let (fade, color) = pair; curveItems(fade, color) });
        let (drawables, polygons) = Render.draw(bg :: List.append(axisItems(atlas), lines));
        Bakery.renderPng(config(atlas), drawables, polygons, name)

    // ── AudioFade: 同じカーブを焼き込んだ試聴 WAV ──

    /// 試聴 WAV の合成設定と素材音（440Hz を 1.5 秒。全開の振幅 0.5）。
    def sfxCfg(): SfxSynth.Config = { sampleRate = 22050 }
    def toneSamples(): List[Float64] = SfxSynth.tone(sfxCfg(), 440.0, 0.5, 1500)

    /// AudioFade.volumeOf をサンプル毎に掛ける。実機で毎フレーム setVolume へ流すのと
    /// 同じ純関数なので、この WAV の聞こえ方 = 実機（OpenAL の gain）のカーブの証明になる。
    def applyFade(fade: AudioFade.Fade, samples: List[Float64]): List[Float64] =
        let n = Int32.toFloat64(List.length(samples));
        List.zipWithIndex(samples) |> List.map(pair -> {
            let (i, s) = pair;
            s * AudioFade.volumeOf(fade, Int32.toFloat64(i) / n)
        })

    /// マスター音量は全サンプル一律の乗算（listener gain と同じ掛かり方）。
    def applyMaster(gain: Float64, samples: List[Float64]): List[Float64] =
        List.map(s -> s * gain, samples)

    def bakeWavs(): Unit \ IO =
        SfxSynth.writeBytes("${outDir()}/audio_fade_in.wav",
            SfxSynth.wavBytes(sfxCfg(), applyFade(AudioFade.fadeIn(), toneSamples())));
        SfxSynth.writeBytes("${outDir()}/audio_fade_out.wav",
            SfxSynth.wavBytes(sfxCfg(), applyFade(AudioFade.fadeOut(), toneSamples())));
        SfxSynth.writeBytes("${outDir()}/audio_master_03.wav",
            SfxSynth.wavBytes(sfxCfg(), applyMaster(0.3, toneSamples())))

    // ── AudioFade: 試聴ページ（SnapshotSite は画像専用なので、ここだけ小さな静的 HTML を直書き）──

    def audioHtml(): String =
        "<!doctype html><meta charset=\"utf-8\"><title>feature_lab Audio</title>\n"
        + "<body style=\"background:#1a1c2c;color:#ddd;font-family:sans-serif;padding:24px\">\n"
        + "<h1>AudioFade を耳で確かめる</h1>\n"
        + "<p><a href=\"index.html\">&larr; index</a></p>\n"
        + audioClip("audio_fade_in.wav", "フェードイン: 440Hz 1.5 秒に volumeOf(0&rarr;1) をサンプル毎に適用")
        + audioClip("audio_fade_out.wav", "フェードアウト: 同じ音に volumeOf(1&rarr;0) を適用")
        + audioClip("audio_master_03.wav", "マスター音量 0.3: 全サンプル一律 0.3 倍（listener gain と同じ掛かり方）")

    def audioClip(file: String, desc: String): String =
        "<h2 style=\"font-size:16px\">${file}</h2><p>${desc}</p><audio controls src=\"${file}\"></audio>\n"

    /// 文字列 1 本をファイルへ書く（bake は成果物を作る場なので IO まで剥がして使う）。
    def writeText(path: String, content: String): Unit \ IO =
        run { discard Fs.WriteFile.write({str = content}, path) }
            with Fs.WriteFile.runWithFileWrite
            with Fs.FileWrite.runWithIO

    /// index.html の末尾へ試聴ページへの入口を足す（SnapshotSite 本体は画像専用のまま触らない。
    /// generate が index を毎回書き直すので、この追記は bake のたびに 1 回だけ効く）。
    def linkAudioFromIndex(): Unit \ IO =
        let path = "${outDir()}/index.html";
        let content = run { Fs.ReadFile.read(path) }
            with Fs.ReadFile.runWithFileRead
            with Fs.FileRead.runWithIO;
        let entry = "<h2 class=\"section\">Audio</h2>\n"
            + "<p><a href=\"audio.html\">audio.html — フェードとマスター音量を耳で確かめる</a></p>\n";
        content
            |> Result.map(html -> writeText(path, html + entry))
            |> Result.getWithDefault(())

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

        bakeCurvePng(atlas, (AudioFade.fadeIn(), risingColor()) :: Nil, "audio_fade_in_curve");
        bakeCurvePng(atlas, (AudioFade.fadeOut(), fadingColor()) :: Nil, "audio_fade_out_curve");
        bakeCurvePng(atlas, (AudioFade.fadeOut(), fadingColor()) :: (AudioFade.fadeIn(), risingColor()) :: Nil,
                     "audio_crossfade_curve");
        bakeWavs();

        run {
            SnapshotSite.generate(
                { outDir = outDir(), title = "feature_lab Gallery", cssScale = 2 },
                catalog({ fadeOut = fadeOutFilm, fadeIn = fadeInFilm,
                          wipeLeft = wipeLeftFilm, wipeRight = wipeRightFilm }))
        } with Fs.FileWrite.runWithIO;
        writeText("${outDir()}/audio.html", audioHtml());
        linkAudioFromIndex()

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
        png("fps_overlay", "debug 有効時に画面右上へ出す fps オーバレイの見本（60fps 固定 dt で計測）", "Debug") ::
        png("audio_fade_in_curve", "フェードインの音量カーブ: volumeOf(0→1)。横=時間 t・縦=音量（audio.html で試聴可）", "AudioFade") ::
        png("audio_fade_out_curve", "フェードアウトの音量カーブ: volumeOf(1→0)", "AudioFade") ::
        png("audio_crossfade_curve", "クロスフェード: 消える側（赤）と現れる側（緑）。同じ t の 2 本で、和は常に 1", "AudioFade") :: Nil

    def png(name: String, desc: String, scenario: String): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "png",
          pxWidth = pxWidth(), generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def gif(name: String, desc: String, scenario: String, filmstrip: SnapshotSite.Filmstrip): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "gif",
          pxWidth = pxWidth(), generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = Some(filmstrip) }
}
