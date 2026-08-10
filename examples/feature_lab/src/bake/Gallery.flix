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

    /// カンテラ探索デモが使うテクスチャ名 → project.json の実ファイルパス。
    /// glow_halo/glow_mask は project.json 登録と揃える（実ファイルは bakeGlowTextures が焼く）。
    def texturePath(): Map[String, String] =
        Map#{ "glow_halo" => "assets/glow_halo.png", "glow_mask" => "assets/glow_mask.png" }

    /// Bakery に渡す焼き込み設定。texturePath はカンテラ探索デモのテクスチャ付き。
    def config(atlas: FontAtlas): Bakery.BakeConfig =
        { design = View.design(), scale = scale(), background = bgColor(),
          texturePath = texturePath(), fontTtf = ttfPath(), fontAtlas = atlas,
          outDir = outDir(), frameW = frameW(), frameH = frameH(),
          gifDelayMs = gifDelayMs(), gifFps = gifFps() }

    /// World を本番と同じ投影（View.frame）で描画コマンドへ変換する。
    def worldCmds(atlas: FontAtlas, world: World.World): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let ctx = App.viewCtxOf(atlas, View.design());
        Render.draw(View.frame(ctx, world))

    /// 遷移 1 種を t=0 から t=1 まで動かした frames 列を作る（Replay を使わず自前で刻む。
    /// World が Transition.Progress を直に持つだけなので、これで十分に軽い）。
    /// 各コマは本番と同じ projectUi を通し、ラベルの bind 文言まで焼き込む。
    /// Progress はレコード直組みでなく start/advance で組む（内部の形に依存しない）。
    /// t=1 のコマも「再生中」として焼く（実機は done で Idle に戻るが、GIF は覆い切った絵で締めたい）。
    def timelineOf(ui: UiStore.UiWorld, lightDoc: LightDoc.Spec, kind: Transition.Kind, steps: Int32): List[World.World] =
        List.range(0, steps + 1) |> List.map(i -> {
            let t = Int32.toFloat64(i) / Int32.toFloat64(steps);
            let progress = Transition.start(World.duration())
                        |> Transition.advance(t * World.duration());
            GameUi.projectUi({ kind = kind, playing = Some(progress) | World.initial(ui, lightDoc, false, ShaderDoc.waterVeins()) })
        })

    /// 1 種類ぶんの GIF ＋ コマ別 PNG を焼く（8 コマ）。
    def bakeKind(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec, kind: Transition.Kind, name: String): SnapshotSite.Filmstrip \ IO =
        let frames = timelineOf(ui, lightDoc, kind, 7);
        Bakery.bakeGif(config(atlas), frames, 1, w -> worldCmds(atlas, w), name)

    /// fps オーバレイの見本（帯の見た目を 1 枚）。App を起動せずに
    /// Annotate.fpsItems を直接呼んで合成する。実機の fps 表示は組み込みフォントの
    /// 等倍で出るので、字体と大きさはここと同じにはならない（見るのは帯の形）。
    def fpsOverlayScene(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let world = GameUi.projectUi(World.initial(ui, lightDoc, false, ShaderDoc.waterVeins()));
        let ctx = App.viewCtxOf(atlas, View.design());
        let sixtyFps = 1.0 / 60.0;
        let anno = List.range(0, 60) |> List.foldLeft((acc, _) -> Annotate.recordDt(sixtyFps, acc), Annotate.initial());
        let overlay = Annotate.fpsItems(atlas, Annotate.defaultBadgeFontSize(), View.design(), Annotate.fpsOf(anno));
        Render.draw(List.append(View.frame(ctx, world), overlay))

    // ── blend 比較（RGB 3 円 × Normal/Add/Multiply）──

    /// blend デモを表示した世界を本番と同じ投影（View.frame）で焼く。
    /// 3 モードを同じ構図で並べると、Add は重なりが白へ光り・Multiply は黒へ沈むのが一目で分かる。
    def bakeBlendPng(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec, mode: DrawCmd.BlendMode, name: String): Unit \ IO =
        let world = GameUi.projectUi({ blend = Some(mode) | World.initial(ui, lightDoc, false, ShaderDoc.waterVeins()) });
        let (drawables, polygons) = worldCmds(atlas, world);
        Bakery.renderPng(config(atlas), drawables, polygons, name)

    // ── Light: カンテラ探索デモ（放射グロー＋穴あき暗幕）──

    /// haloTexture/maskTexture の実ファイルを assets/ に焼く。project.json の texturePath が
    /// 指すファイルはここでしか生成されないので、実行前に必ず bake を通す必要がある。
    /// maskTexture は maskCurveWithHole で平坦な穴を持たせる（View.maskHoleFrac と揃える —
    /// 揃っていないと Light.items のスケール計算が前提とする「穴の実寸半径」がずれる）。
    def bakeGlowTextures(): Unit \ IO =
        let maskSize = RenderUtil.floatToInt32(View.maskSourceSize());
        let haloSize = RenderUtil.floatToInt32(View.haloSourceSize());
        let maskCurve = t -> RadialGlow.maskCurveWithHole(View.maskHoleFrac(), RadialGlow.smoothstepCurve, t);
        SoftRaster.writeRadialPng(maskSize,
            (x, y) -> RadialGlow.maskPixel(maskCurve, RadialGlow.normalizedRadius(maskSize, x, y)),
            "assets/glow_mask.png");
        SoftRaster.writeRadialPng(haloSize,
            (x, y) -> RadialGlow.haloPixel(RadialGlow.smoothstepCurve, RadialGlow.normalizedRadius(haloSize, x, y)),
            "assets/glow_halo.png")

    /// カンテラ探索の比較 3 枚が使う共通のプレイヤー位置（目印の間、画面中央よりやや上）。
    def lanternDemoAt(): Vec2.Vec2 = { x = 160.0, y = 100.0 }

    /// 比較 PNG 1 枚ぶんの世界を組んで焼く。
    def bakeLanternPng(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec, lantern: Option[World.Lantern], name: String): Unit \ IO =
        let world = GameUi.projectUi({ lantern = lantern | World.initial(ui, lightDoc, false, ShaderDoc.waterVeins()) });
        let (drawables, polygons) = worldCmds(atlas, world);
        Bakery.renderPng(config(atlas), drawables, polygons, name)

    /// 「明（Bright。部屋+目印がフル輝度）」「暗闇のみ（Dark。光源なしの全面暗幕で
    /// 目印がシルエット程度に残る）」「暗闇+カンテラ（DarkWithLight。穴あき+ハロ）」の3枚を焼く。
    def bakeLanternComparisonPngs(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec): Unit \ IO =
        bakeLanternPng(atlas, ui, lightDoc, Some({ at = lanternDemoAt(), mode = World.LanternMode.Bright, walls = false }), "lantern_bright");
        bakeLanternPng(atlas, ui, lightDoc, Some({ at = lanternDemoAt(), mode = World.LanternMode.Dark, walls = false }), "lantern_dark_no_light");
        bakeLanternPng(atlas, ui, lightDoc, Some({ at = lanternDemoAt(), mode = World.LanternMode.DarkWithLight, walls = false }), "lantern_dark_with_light")

    /// カンテラが目印の間を歩き回る経路（往復する巡回点列。t を周期的に進めて線形補間する）。
    def lanternPatrolPoints(): List[Vec2.Vec2] =
        { x = 60.0, y = 60.0 } :: { x = 260.0, y = 60.0 } :: { x = 260.0, y = 180.0 } ::
        { x = 60.0, y = 180.0 } :: { x = 60.0, y = 60.0 } :: Nil

    /// 巡回点列を frames コマぶん等分してなめらかに歩く World 列を作る（DarkWithLight 固定。
    /// walls は影デモの GIF だけ true にする — 既存の lantern_patrol の絵を変えないため）。
    def patrolTimeline(ui: UiStore.UiWorld, lightDoc: LightDoc.Spec, points: List[Vec2.Vec2], walls: Bool, frames: Int32): List[World.World] =
        let segments = List.length(points) - 1;
        List.range(0, frames + 1) |> List.map(i -> {
            let t = Int32.toFloat64(i) / Int32.toFloat64(frames) * Int32.toFloat64(segments);
            let seg = Int32.min(segments - 1, Float64.tryToInt32(Float64.floor(t)) |> Option.getWithDefault(0));
            let localT = t - Int32.toFloat64(seg);
            let segStart = List.nth(seg, points) |> Option.getWithDefault(lanternDemoAt());
            let segEnd = List.nth(seg + 1, points) |> Option.getWithDefault(lanternDemoAt());
            let at = Vec2.add(segStart, Vec2.mul(Vec2.sub(segEnd, segStart), localT));
            GameUi.projectUi({ lantern = Some({ at = at, mode = World.LanternMode.DarkWithLight, walls = walls }) | World.initial(ui, lightDoc, false, ShaderDoc.waterVeins()) })
        })

    /// カンテラが目印の間を歩き回る GIF（8 コマ）。
    def bakeLanternGif(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec): SnapshotSite.Filmstrip \ IO =
        let frames = patrolTimeline(ui, lightDoc, lanternPatrolPoints(), false, 7);
        Bakery.bakeGif(config(atlas), frames, 1, w -> worldCmds(atlas, w), "lantern_patrol")

    // ── Shadow: 壁と影（View の壁定義 + Shadow.itemsFor の手本）──

    /// 影比較 2 枚の光の位置。front は壁の手前（白丸目印と反対側）、behind は
    /// 壁の向こう側（目印と同じ側）。目印は光の届く範囲（穴 48+落ち際）に入れる —
    /// 遠すぎると影の有無にかかわらず真っ黒で、影の証明にならない。
    /// 画面端からも離す（縁取りマーカーが落ち際で照らされて紛らわしいため）。
    def shadowFrontAt(): Vec2.Vec2 = { x = 160.0, y = 120.0 }
    def shadowBehindAt(): Vec2.Vec2 = { x = 262.0, y = 120.0 }

    /// 影の比較 3 枚（DarkWithLight 固定）。front/behind は walls=true。
    /// walls_off は front と同じ光位置で walls=false にした対照カット —
    /// front の暗さが「壁の影」であって「光源からの距離減衰」でないことの証明になる
    /// （walls=false でも目印まわりが front と同じ明るさなら、影は壁 occluder だけの効果）。
    def bakeShadowPngs(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec): Unit \ IO =
        bakeLanternPng(atlas, ui, lightDoc,
            Some({ at = shadowFrontAt(), mode = World.LanternMode.DarkWithLight, walls = true }),
            "shadow_light_front");
        bakeLanternPng(atlas, ui, lightDoc,
            Some({ at = shadowBehindAt(), mode = World.LanternMode.DarkWithLight, walls = true }),
            "shadow_light_behind");
        bakeLanternPng(atlas, ui, lightDoc,
            Some({ at = shadowFrontAt(), mode = World.LanternMode.DarkWithLight, walls = false }),
            "shadow_walls_off")

    // ── Light: 光マップ（ランタン 2 個+影。lightMapPass / lightMapOverlay の手本）──

    /// 光マップデモ 1 枚を焼く。pass（光マップ）を先に焼いてから本編へ Multiply で貼る —
    /// 実機の App.withPasses と同じ順序を renderPngWithPasses が再現する。
    def bakeLightMapPng(atlas: FontAtlas, lightDoc: LightDoc.Spec,
                        a: Vec2.Vec2, b: Vec2.Vec2, name: String): Unit \ IO =
        let cfg = View.lightMapDemoConfig(lightDoc, View.lightMapLanterns(lightDoc, a, b));
        let passSpec = Render.passSpecOf(_ -> None, Light.lightMapPass(cfg));
        let (ds, ps) = Render.draw(View.lightMapDemoItems(cfg));
        Bakery.renderPngWithPasses(config(atlas), passSpec :: Nil, ds, ps, Nil, name)

    /// 2 枚連番: ランタン A が壁の反対側へ回ると、同じ壁の影が別の向きへ倒れる
    /// （GIF にしないのは bakeGif が pass 未対応のため — 影の回りは 2 枚の見比べで示す）。
    /// swing の B を two_lanterns と同じ (66,178) に置かないのは、そこが A の長影の帯の
    /// 真ん中で B の灯りが丸ごと沈み、初見に「バグの絵」と映るため — 帯の外へ出し、
    /// 「B の灯りは生きていて、その裾を A の影が横切る」が読める位置に置く。
    def bakeLightMapPngs(atlas: FontAtlas, lightDoc: LightDoc.Spec): Unit \ IO =
        bakeLightMapPng(atlas, lightDoc,
            { x = 160.0, y = 120.0 }, { x = 66.0, y = 178.0 }, "lightmap_two_lanterns");
        bakeLightMapPng(atlas, lightDoc,
            { x = 238.0, y = 70.0 }, { x = 44.0, y = 72.0 }, "lightmap_swing")

    /// 光が L 字壁の周りを一周する巡回点列（壁の陰が回って見える経路）。
    def shadowPatrolPoints(): List[Vec2.Vec2] =
        { x = 160.0, y = 120.0 } :: { x = 200.0, y = 62.0 } :: { x = 262.0, y = 120.0 } ::
        { x = 200.0, y = 178.0 } :: { x = 160.0, y = 120.0 } :: Nil

    /// 光が壁の周りを一周して影が回る GIF（8 コマ・walls=true）。
    def bakeShadowGif(atlas: FontAtlas, ui: UiStore.UiWorld, lightDoc: LightDoc.Spec): SnapshotSite.Filmstrip \ IO =
        let frames = patrolTimeline(ui, lightDoc, shadowPatrolPoints(), true, 7);
        Bakery.bakeGif(config(atlas), frames, 1, w -> worldCmds(atlas, w), "shadow_walk")

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
        bakeGlowTextures();
        let atlas = Harness.atlas();
        let ui = Harness.ui();
        let lightDoc = Harness.lightDoc();

        let fadeOutFilm = bakeKind(atlas, ui, lightDoc, Transition.Kind.FadeOut, "fade_out");
        let fadeInFilm  = bakeKind(atlas, ui, lightDoc, Transition.Kind.FadeIn, "fade_in");
        let wipeLeftFilm  = bakeKind(atlas, ui, lightDoc, Transition.Kind.WipeLeft, "wipe_left");
        let wipeRightFilm = bakeKind(atlas, ui, lightDoc, Transition.Kind.WipeRight, "wipe_right");

        let (fpsDrawables, fpsPolys) = fpsOverlayScene(atlas, ui, lightDoc);
        Bakery.renderPng(config(atlas), fpsDrawables, fpsPolys, "fps_overlay");

        bakeBlendPng(atlas, ui, lightDoc, DrawCmd.BlendMode.Normal, "blend_normal");
        bakeBlendPng(atlas, ui, lightDoc, DrawCmd.BlendMode.Add, "blend_add");
        bakeBlendPng(atlas, ui, lightDoc, DrawCmd.BlendMode.Multiply, "blend_multiply");

        bakeLanternComparisonPngs(atlas, ui, lightDoc);
        let lanternFilm = bakeLanternGif(atlas, ui, lightDoc);

        bakeShadowPngs(atlas, ui, lightDoc);
        let shadowFilm = bakeShadowGif(atlas, ui, lightDoc);

        bakeLightMapPngs(atlas, lightDoc);

        let hazeFilm = TexDemo.bakeAll(config(atlas));

        bakeCurvePng(atlas, (AudioFade.fadeIn(), risingColor()) :: Nil, "audio_fade_in_curve");
        bakeCurvePng(atlas, (AudioFade.fadeOut(), fadingColor()) :: Nil, "audio_fade_out_curve");
        bakeCurvePng(atlas, (AudioFade.fadeOut(), fadingColor()) :: (AudioFade.fadeIn(), risingColor()) :: Nil,
                     "audio_crossfade_curve");
        bakeWavs();

        run {
            SnapshotSite.generate(
                { outDir = outDir(), title = "feature_lab Gallery", cssScale = 2 },
                catalog({ fadeOut = fadeOutFilm, fadeIn = fadeInFilm,
                          wipeLeft = wipeLeftFilm, wipeRight = wipeRightFilm,
                          lanternPatrol = lanternFilm, shadowWalk = shadowFilm,
                          texHaze = hazeFilm }))
        } with Fs.FileWrite.runWithIO;
        writeText("${outDir()}/audio.html", audioHtml());
        linkAudioFromIndex()

    // ── カタログ（ページとカードの宣言）──

    type alias Films = {
        fadeOut = SnapshotSite.Filmstrip, fadeIn = SnapshotSite.Filmstrip,
        wipeLeft = SnapshotSite.Filmstrip, wipeRight = SnapshotSite.Filmstrip,
        lanternPatrol = SnapshotSite.Filmstrip, shadowWalk = SnapshotSite.Filmstrip,
        texHaze = SnapshotSite.Filmstrip
    }

    def catalog(films: Films): List[SnapshotSite.Item] =
        gif("fade_out", "だんだん黒く覆っていく（t=0 素通し → t=1 全面黒）", "Transition", films#fadeOut) ::
        gif("fade_in", "覆いがだんだん晴れる（t=0 全面黒 → t=1 素通し）", "Transition", films#fadeIn) ::
        gif("wipe_left", "黒い帯が右から左へ画面を覆っていく", "Transition", films#wipeLeft) ::
        gif("wipe_right", "黒い帯が左から右へ画面を覆っていく", "Transition", films#wipeRight) ::
        png("fps_overlay", "debug 有効時に画面右上へ出す fps オーバレイの見本（60fps 固定 dt で計測）", "Debug") ::
        png("blend_normal", "Normal: ふつうの重なり — 後から描いた円が上を覆う（白地の左と暗地の右で同じ）", "Blend") ::
        png("blend_add", "Add: 明るく足す — R+G=黄・3 色の重なりは白へ光る。暗い地ほど映える", "Blend") ::
        png("blend_multiply", "Multiply: 掛けて沈める — 重なりは黒へ。白地は円の色がそのまま・暗地はさらに暗く", "Blend") ::
        png("lantern_bright", "Bright: 部屋+目印がフル輝度（暗闇なし）の対照カット", "Light") ::
        png("lantern_dark_no_light", "Dark: 光源なしの全面暗幕（Light.multiLightItems を lights=Nil で流用）。目印はシルエット程度に残る", "Light") ::
        png("lantern_dark_with_light", "DarkWithLight: 穴あき暗幕（Multiply）+暖色ハロ（Add）で光の周りだけ目印が見える", "Light") ::
        gif("lantern_patrol", "カンテラが目印の間を歩き回る（矢印キー相当の移動を巡回点列で再現）", "Light", films#lanternPatrol) ::
        png("shadow_light_front", "光が壁の手前: 壁の裏の目印（白丸）が影に沈んで見えない（Shadow.itemsFor の Multiply 黒 Poly）", "Shadow") ::
        png("shadow_light_behind", "光が壁の向こう側へ回り込むと同じ目印が照らされて見える（壁と遮蔽ポリゴンは同じ定義から導出）", "Shadow") ::
        png("shadow_walls_off", "対照カット: shadow_light_front と同じ光位置で walls=false。目印が沈まず見える＝暗さは壁の影であって距離減衰ではない", "Shadow") ::
        png("lightmap_two_lanterns", "光マップ方式: ランタン 2 個が同時に照らし、同じ壁から 2 方向へ影が伸びる（Light.lightMapPass + lightMapOverlay。暗幕方式では不可能な絵）", "Shadow") ::
        png("lightmap_swing", "ランタン A が壁の反対側へ回った連番: 同じ壁の影が別の向きへ倒れる（影が光の位置から導かれている証拠）。A の長い影が B の灯りまで消しているのは v1 の割り切りどおり（Light.lightMapPass の doc 参照）", "Shadow") ::
        gif("shadow_walk", "光が L 字壁と柱の周りを一周し、壁の陰が動的に回る（LeftCtrl で walls トグル相当）", "Shadow", films#shadowWalk) ::
        png("tex_blit", "tex 場の素通し: 左=pass をスプライト直貼り・右=Rgb{Tex×3} の面。継ぎ目が見えない=2 経路一致（中央の薄荷線が境界）", "ShaderTex") ::
        png("tex_blur", "3×3 ガウス近似: Shift タップ×9 の加重平均（Tex 読み 27 回 — JSON 合成ぼかしの実用上限の見本）", "ShaderTex") ::
        gif("tex_haze", "陽炎: sin ゆらぎの Shift + Warp のうねりで pass を歪めて読む（10 コマ完全ループ）", "ShaderTex", films#texHaze) ::
        png("tex_shock", "衝撃波: 中心から広がるリング窓の上だけ座標を中心へ引き込む（t=0.8 の瞬間）", "ShaderTex") ::
        png("tex_grade", "色調変換: luma を 1 本の場に畳み Gradient で夕暮れ 3 色へ染め直す", "ShaderTex") ::
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
