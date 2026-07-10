// Gallery — 挙動ショーケースを焼く。Replay で純粋な update を駆動してシナリオを再現し、
// SoftRaster で 1 枚ずつ描いて PNG・GIF・フィルムストリップにし、SnapshotSite でページ化する。
// シナリオの初期 World と台本は Trace が供給する（テストと同じデータ）ので、ギャラリーは
// 「テストで固定した挙動」をそのまま絵にしたものになる。
//
// 見せ場:
//   1. 満タンジャンプ: 24 フレームで頂点（ふわり）→ 1.8 倍重力の急降下（非対称が見える）
//   2. 短押しタップ: 同じボタンで低いホップ（可変ジャンプ高）
//   3. 浮き床走破: 助走つきジャンプ×2 と走り落ち（慣性・空中制御・コヨーテの絵）

mod Gallery {
    import java.io.File

    // ── 焼き込み設定 ──
    def design(): Vec2.Vec2 = { x = 320.0, y = 240.0 }
    def scale(): Int32 = 2                    // 出力は 640x480
    def pxWidth(): Int32 = 640
    def frameW(): Int32 = 640
    def frameH(): Int32 = 480
    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def outDir(): String = "gallery"
    def gifDelayMs(): Int32 = 33
    def gifFps(): Int32 = 30

    // ── RasterReq 組み立て ──

    def reqOfWorld(atlas: FontAtlas, world: Field.World, path: String): SoftRaster.RasterReq =
        let (drawables, polygons) = Render.draw(View.frame(atlas, world));
        { drawables = drawables, polygons = polygons,
          design = design(), scale = scale(), background = Palette.clearColor(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas, outPath = path }

    def pathOf(name: String): String = "${outDir()}/${name}.png"
    def gifPathOf(name: String): String = "${outDir()}/${name}.gif"

    // ── PNG / GIF を焼く ──

    /// 1 枚の World を PNG に焼く。
    def shotWorld(atlas: FontAtlas, world: Field.World, name: String): Unit \ IO =
        SoftRaster.render(reqOfWorld(atlas, world, pathOf(name)))

    /// シナリオ（初期 World + 台本）を Replay.timeline で駆動し、stride 枚ごとに 1 枚描いて
    /// GIF＋コマ別 PNG に焼く。返り値は SnapshotSite 用のフィルムストリップ情報（駒送りビューア）。
    def bakeGif(atlas: FontAtlas, world: Field.World, cues: List[Replay.Cue[Field.Input]],
                stride: Int32, name: String): SnapshotSite.Filmstrip \ IO =
        let film = Replay.timeline(Step.update, Trace.dt(), cues, world);
        let sampled = every(stride, film);
        let images = List.map(w ->
            SoftRaster.renderToImage(reqOfWorld(atlas, w, gifPathOf(name))), sampled);
        GifEncoder.encodeWithFrames(images, gifDelayMs(), gifPathOf(name), "${outDir()}/frames/${name}");
        { strip = "frames/${name}/", frameCount = List.length(images),
          frameW = frameW(), frameH = frameH(), fps = gifFps() }

    /// stride 枚ごとに 1 枚を残す（0 番から）。
    def every(stride: Int32, xs: List[a]): List[a] =
        List.zipWithIndex(xs)
            |> List.filterMap(pair -> { let (i, x) = pair; if (Int32.modulo(i, stride) == 0) Some(x) else None })

    // ── 全部を焼いてサイトを生成する（Bake.all から呼ぶ）──

    pub def bakeAll(): Unit \ IO =
        discard (new File(outDir())).mkdirs();
        let atlas = Harness.atlas();

        // 画面: 地形の全景（スポーン直後・落下中）。
        shotWorld(atlas, Trace.platformWorld(), "screen_field");

        // 見せ場 1: 満タンジャンプ — 上昇 23f・頂点ふわり・急降下 21f。
        let fullFilm = bakeGif(atlas, Trace.flatWorld(),
            List.append(Trace.holdJump(30), Trace.flight(66)), 2, "full_jump");

        // 見せ場 2: 短押しタップ — 4f で離すと上昇がカットされ低く飛ぶ。
        let tapFilm = bakeGif(atlas, Trace.flatWorld(),
            List.append(Trace.holdJump(4), Trace.flight(60)), 2, "short_hop");

        // 見せ場 3: 浮き床走破 — 助走ジャンプ×2 と走り落ち（台本は Trace の実測値）。
        let acrossFilm = bakeGif(atlas, Trace.runAcrossWorld(), Trace.runAcrossCues(), 2, "run_across");

        // 見せ場 4: B ダッシュ崖越え — 低ホップで浮き床の下をくぐって広い穴を渡る。
        let dashFilm = bakeGif(atlas, Trace.gapWorld(), Trace.dashGapCues(), 2, "dash_gap");

        // 見せ場 5: 崖死亡 — 歩いて落ちると死に、出発点へ戻される。
        let deathFilm = bakeGif(atlas, Trace.gapWorld(), Trace.gapDeathCues(), 2, "gap_death");

        // サイト生成。
        run {
            SnapshotSite.generate(
                { outDir = outDir(), title = "Platformer Gallery", cssScale = 2 },
                catalog({ full = fullFilm, tap = tapFilm, across = acrossFilm,
                          dash = dashFilm, death = deathFilm }))
        } with Fs.FileWrite.runWithIO

    // ── カタログ（ページとカードの宣言）──

    /// カタログに並べるフィルムストリップ一式（名前渡しで取り違えを防ぐ）。
    type alias Films = {
        full = SnapshotSite.Filmstrip,
        tap = SnapshotSite.Filmstrip,
        across = SnapshotSite.Filmstrip,
        dash = SnapshotSite.Filmstrip,
        death = SnapshotSite.Filmstrip
    }

    def catalog(films: Films): List[SnapshotSite.Item] =
        png("screen_field", "地形の全景: 崖 2 本で 3 分割の地面 + 浮き床 3 枚 + 左右の壁。球体がプレイヤー", "Screens") ::
        gif("full_jump", "満タンジャンプ: 24 フレームで頂点 96px、頂点付近はふわり（0.5 倍重力）、下降は 1.8 倍で速い", "Jump", films#full) ::
        gif("short_hop", "短押しタップ（4f）: 離した瞬間に上昇が 0.4 倍へカットされ低く飛ぶ（可変ジャンプ高）", "Jump", films#tap) ::
        gif("run_across", "浮き床走破: 助走つきジャンプで A→B と渡り、走り落ちて C へ。慣性が残ったまま壁で止まる", "Run", films#across) ::
        gif("dash_gap", "B ダッシュ崖越え: 低ホップ（6f）で浮き床 B の下をくぐり、広い穴（80px）を渡って浮き床 C へ。素の走りでは届かない", "Gap", films#dash) ::
        gif("gap_death", "崖死亡: 歩いて穴へ出ると落ちて死に、出発点へ戻される（deaths が増える）", "Gap", films#death) :: Nil

    def png(name: String, desc: String, scenario: String): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "png",
          pxWidth = pxWidth(), generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def gif(name: String, desc: String, scenario: String, filmstrip: SnapshotSite.Filmstrip): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "gif",
          pxWidth = pxWidth(), generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = Some(filmstrip) }
}
