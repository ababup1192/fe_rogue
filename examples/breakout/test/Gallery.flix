// Gallery — 挙動ショーケースを焼く。Replay で純粋な update を駆動してシナリオを再現し、
// SoftRaster で 1 枚ずつ描いて PNG・GIF・フィルムストリップにし、SnapshotSite でページ化する。
// シナリオの初期 World は Trace が供給する（テストと同じデータ）ので、ギャラリーは
// 「テストで固定した挙動」をそのまま絵にしたものになる。
//
// 見せ場:
//   1. パドル反射×5パターン（当たり位置で変わる角度差）— 1 枚の扇形で並べる
//   2. ブロック衝突（横から・下から・角）
//   3. ブロック破壊（破片つき）
//   4. ハードブロックのカメラシェイク（1発目=小・2発目=大）
//   5. ポケット: レベル 3 の中央スリットへ撃ち込むと天井との間で壊れ続ける
//   6. 加速ラリー: パドルヒットのたびに速くなる（SPEED の読みが伸びていく）

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

    def reqOfScene(atlas: FontAtlas, drawables: List[GameEngine.Drawable],
                   polygons: List[GameEngine.PolygonRenderCmd], path: String): SoftRaster.RasterReq =
        { drawables = drawables, polygons = polygons,
          design = design(), scale = scale(), background = Palette.clearColor(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas, outPath = path }

    /// World の絵に注釈（extra）を重ねた 1 枚の焼き込み要求。
    def reqOfWorld(atlas: FontAtlas, world: Field.World,
                   extra: List[Render.Placed], path: String): SoftRaster.RasterReq =
        let (drawables, polygons) = Render.draw(List.append(View.frame(atlas, world), extra));
        reqOfScene(atlas, drawables, polygons, path)

    def pathOf(name: String): String = "${outDir()}/${name}.png"
    def gifPathOf(name: String): String = "${outDir()}/${name}.gif"

    // ── PNG / GIF を焼く ──

    /// 1 枚の World を PNG に焼く。
    def shotWorld(atlas: FontAtlas, world: Field.World, name: String): Unit \ IO =
        SoftRaster.render(reqOfWorld(atlas, world, Nil, pathOf(name)))

    /// 直接組んだ場面（World を介さない扇形など）を PNG に焼く。
    def shotScene(atlas: FontAtlas, drawables: List[GameEngine.Drawable],
                  polygons: List[GameEngine.PolygonRenderCmd], name: String): Unit \ IO =
        SoftRaster.render(reqOfScene(atlas, drawables, polygons, name |> pathOf))

    /// シナリオを Replay.timeline で駆動し、stride 枚ごとに 1 枚描いて GIF＋コマ別 PNG に焼く。
    /// annotate は各フレームの World から重ねる注釈（SPEED の読みなど。不要なら _ -> Nil）。
    /// 返り値は SnapshotSite 用のフィルムストリップ情報（駒送りビューア）。
    def bakeGif(atlas: FontAtlas, world: Field.World, frames: Int32, stride: Int32,
                name: String, annotate: Field.World -> List[Render.Placed]): SnapshotSite.Filmstrip \ IO =
        let film = Replay.timeline(Step.update, Trace.dt(), Trace.flight(frames), world);
        let sampled = every(stride, film);
        let images = List.map(w ->
            SoftRaster.renderToImage(reqOfWorld(atlas, w, annotate(w), gifPathOf(name))), sampled);
        GifEncoder.encode(images, gifDelayMs(), gifPathOf(name));
        // コマ送りビューア用のコマ別 PNG。横連結シートはブラウザが幅 65,535px 超を描けず
        // 真っ黒に落ちるので、全コマをコマ別に焼いてビューアが canvas でめくる。
        discard Filmstrip.bakeFrames(images, "${outDir()}/frames/${name}");
        { strip = "frames/${name}/", frameCount = List.length(images),
          frameW = frameW(), frameH = frameH(), fps = gifFps() }

    /// stride 枚ごとに 1 枚を残す（0 番から）。
    def every(stride: Int32, xs: List[a]): List[a] =
        List.zipWithIndex(xs)
            |> List.filterMap(pair -> { let (i, x) = pair; if (Int32.modulo(i, stride) == 0) Some(x) else None })

    // ── 見せ場 1: パドル反射の扇形（当たり位置で変わる角度差を 1 枚に並べる）──
    // update を介さず Bounce 規則から直接描く: 5 つの当たり位置それぞれの反射方向へ点線を伸ばす。
    // パドルの絵は View と共有（面シェーディング＋ゾーン帯）なので、端のアクセント帯と
    // 鋭角の点線が同じ場所を指すのが一目で分かる。

    def fanScene(atlas: FontAtlas): (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let paddleY = 205.0;
        let center = 160.0;
        let halfW = Field.paddleHalfWidth();
        // 5 ゾーンと色（通常ブロックの行色を流用）。
        let zones =
            (-1.0, Palette.blockRow(0)) :: (-0.5, Palette.blockRow(1)) :: (0.0, Palette.blockRow(2)) ::
            (0.5, Palette.blockRow(3)) :: (1.0, Palette.blockRow(4)) :: Nil;
        let paddleArt = View.paddleItemsAt({ x = center, y = paddleY });
        let rays = List.flatMap(zc -> {
            let (zone, color) = zc;
            let impactX = center + zone * halfW;
            let direction = Bounce.paddleReflect(zone, 1.0);
            dot({ x = impactX, y = paddleY - 5.0 }, 2.5, Palette.ball(), 15) :: fanRay(impactX, paddleY - 5.0, direction, color)
        }, zones);
        let title =
            TextDraw.centered({ text = "PADDLE BOUNCE 5 ZONES", atlas = atlas, size = 12.0,
                                color = Palette.titleText(), z = 100, centerX = center, y = 12.0 }) :: Nil;
        Render.draw(List.flatten(paddleArt :: rays :: title :: Nil))

    /// 当たり位置から反射方向 direction（速さ 1）へ、点を等間隔に並べた点線。
    def fanRay(startX: Float64, startY: Float64, direction: Vec2.Vec2,
               color: Color): List[Render.Placed] =
        List.map(k -> {
            let distance = Int32.toFloat64(k) * 9.0;
            dot({ x = startX + direction#x * distance, y = startY + direction#y * distance }, 2.0, color, 12)
        }, List.range(1, 20))

    // ── 見せ場 6 の注釈: ボールの速さの読み ──

    /// このフレームのボールの速さを「SPEED nnn」で盤の上部に重ねる（ラリー室の空きスペース）。
    def speedNote(atlas: FontAtlas, world: Field.World): List[Render.Placed] =
        let speed = Trace.ballVelOf(world) |> Option.map(v -> Vec2.length(v)) |> Option.getWithDefault(0.0);
        let reading = Float64.floor(speed + 0.5) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        TextDraw.centered({ text = "SPEED ${reading}", atlas = atlas, size = 14.0,
                            color = Palette.ball(), z = 100,
                            centerX = Field.designW() / 2.0, y = 40.0 }) :: Nil

    // ── 描画プリミティブ ──

    def dot(center: Vec2.Vec2, radius: Float64, color: Color, z: Int32): Render.Placed =
        ({ x = center#x - radius, y = center#y - radius }, Render.circle(radius, color, z))

    // ── 全部を焼いてサイトを生成する 1 テスト ──

    @Test
    def testBakeGalleryAndSite(): Unit \ IO =
        discard (new File(outDir())).mkdirs();
        let atlas = Harness.atlas();
        let noNote = _ -> Nil;

        // 画面: タイトル・各レベルの開始盤・少し遊んだ盤。
        let launched = Replay.play(Step.update, Trace.dt(),
            Trace.hold({ launch = true | Trace.idle() }, 1) :: Trace.flight(70), Field.playingWorld(1));
        shotWorld(atlas, Field.titleWorld(), "screen_title");
        shotWorld(atlas, Field.playingWorld(1), "screen_level1");
        shotWorld(atlas, Field.playingWorld(2), "screen_level2");
        shotWorld(atlas, Field.playingWorld(3), "screen_level3");
        shotWorld(atlas, launched, "screen_play");

        // 見せ場 1: パドル反射の扇形（PNG）。
        let (fanDrawables, fanPolys) = fanScene(atlas);
        shotScene(atlas, fanDrawables, fanPolys, "paddle_bounce_fan");

        // 見せ場 2: ブロック衝突（横・下・角）。
        let sideFilm   = bakeGif(atlas, Trace.blockSideWorld(),   52, 2, "block_side", noNote);
        let belowFilm  = bakeGif(atlas, Trace.blockBelowWorld(),  52, 2, "block_below", noNote);
        let cornerFilm = bakeGif(atlas, Trace.blockCornerWorld(), 52, 2, "block_corner", noNote);

        // 見せ場 3: ブロック破壊（破片つき）。
        let breakFilm  = bakeGif(atlas, Trace.blockBreakWorld(),  64, 2, "block_break", noNote);

        // 見せ場 4: ハードブロックのカメラシェイク（1発目=小・2発目=大）。
        let shakeFilm  = bakeGif(atlas, Trace.hardShakeWorld(), 150, 3, "hard_shake", noNote);

        // 見せ場 5: ポケット — 縦通路へ入れて上段を壊し続ける。
        let pocketFilm = bakeGif(atlas, Trace.pocketWorld(), 560, 4, "pocket_rampage", noNote);

        // 見せ場 6: 加速ラリー — SPEED の読みが伸び、残像が冷→温→熱と色を変える。
        // 1450 フレームで 17 ヒットほど、終盤は熱（橙）のトレイルに届く。
        let rampFilm = bakeGif(atlas, Trace.speedRampWorld(), 1450, 10, "speed_ramp",
                               w -> speedNote(atlas, w));

        // サイト生成。
        run {
            SnapshotSite.generate(
                { outDir = outDir(), title = "Breakout Gallery", cssScale = 2 },
                catalog({ side = sideFilm, below = belowFilm, corner = cornerFilm,
                          breaking = breakFilm, shake = shakeFilm,
                          pocket = pocketFilm, ramp = rampFilm }))
        } with Fs.FileWrite.runWithIO

    // ── カタログ（ページとカードの宣言）──

    /// カタログに並べるフィルムストリップ一式（名前渡しで取り違えを防ぐ）。
    type alias Films = {
        side = SnapshotSite.Filmstrip, below = SnapshotSite.Filmstrip,
        corner = SnapshotSite.Filmstrip, breaking = SnapshotSite.Filmstrip,
        shake = SnapshotSite.Filmstrip, pocket = SnapshotSite.Filmstrip,
        ramp = SnapshotSite.Filmstrip
    }

    def catalog(films: Films): List[SnapshotSite.Item] =
        png("screen_title", "タイトル画面", "Screens") ::
        png("screen_level1", "レベル1: 導入のピラミッド（通常ブロックのみ）", "Screens") ::
        png("screen_level2", "レベル2: 不壊の帯（金属）に 2 本のスリット", "Screens") ::
        png("screen_level3", "レベル3: ポケット完備 — 中央スリットの真下が開いている", "Screens") ::
        png("screen_play", "プレイ中の盤（パドル・ボール・破片・HUD）", "Screens") ::
        png("paddle_bounce_fan", "パドルの当たり位置で反射角が変わる（中央=真上・端=鋭角）。パドルの端のアクセント帯 = 鋭角ゾーン。",
            "Paddle") ::
        gif("block_side", "横から当たると x 反転で左右に返る", "Blocks", films#side) ::
        gif("block_below", "下から当たると y 反転で上下に返る", "Blocks", films#below) ::
        gif("block_corner", "角に当たっても破綻しない", "Blocks", films#corner) ::
        gif("block_break", "通常ブロックを壊すと破片が飛ぶ（両脇は残る）", "Break", films#breaking) ::
        gif("hard_shake", "ハードは1発目=耐える+小シェイク、2発目=破壊+大シェイク", "Shake", films#shake) ::
        gif("pocket_rampage", "レベル3の縦通路へ撃ち込むと、天井と不壊の帯の間で壊れ続ける", "Pocket", films#pocket) ::
        gif("speed_ramp", "パドルヒット毎に +2.5% 加速（端当てはさらに +5%・上限 1.6 倍）。残像の色が冷→温→熱と変わり、SPEED の読みも伸びる", "Speed", films#ramp) :: Nil

    def png(name: String, desc: String, scenario: String): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "png",
          pxWidth = pxWidth(), generateHint = Some("run `flix test` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def gif(name: String, desc: String, scenario: String, filmstrip: SnapshotSite.Filmstrip): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "gif",
          pxWidth = pxWidth(), generateHint = Some("run `flix test` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = Some(filmstrip) }
}
