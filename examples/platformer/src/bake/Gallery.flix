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
    // design はゲーム画面と同じ 480×360（カメラ引き後）。出力は等倍 480×360 —
    // 2 倍焼き（960×720）はファイルが約 2.25 倍に膨らむので等倍に留める。
    def design(): Vec2.Vec2 = { x = 480.0, y = 360.0 }
    def scale(): Int32 = 1                    // 出力は 480x360（等倍）
    def pxWidth(): Int32 = 480
    def frameW(): Int32 = 480
    def frameH(): Int32 = 360
    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def outDir(): String = "gallery"
    def gifDelayMs(): Int32 = 33
    def gifFps(): Int32 = 30

    // ── Bakery に渡す設定と投影 ──

    /// Bakery に渡す焼き込み設定（背景は clearColor・テクスチャなし）。
    def config(atlas: FontAtlas): Bakery.BakeConfig =
        { design = design(), scale = scale(), background = Palette.clearColor(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outDir = outDir(), frameW = frameW(), frameH = frameH(),
          gifDelayMs = gifDelayMs(), gifFps = gifFps() }

    /// World を engine の描画コマンドへ投影する（カメラ適用 + HUD 合流 = 本番と同じ合成）。
    def worldCmds(atlas: FontAtlas, world: Field.World):
            (List[GameEngine.Drawable], List[GameEngine.PolygonRenderCmd]) =
        let center = View.cameraCenter(world);
        let design = { x = Field.designW(), y = Field.designH() };
        // App が組むのと同じ ViewCtx（world 側はカメラの見える範囲・hud 側は画面全体）。
        let ctx = { atlas = atlas, visible = App.visibleOf(Some(center), design) };
        let hudCtx = { atlas = atlas, visible = App.visibleOf(None, design) };
        let composed = App.composeScene(
            Some(center), design,
            { world = View.frame(ctx, world), hud = View.hud(hudCtx, world) });
        Render.draw(composed)

    // ── PNG / GIF を焼く（配管は Bakery が担う）──

    /// 1 枚の World を PNG に焼く。
    def shotWorld(atlas: FontAtlas, world: Field.World, name: String): Unit \ IO =
        let (drawables, polygons) = worldCmds(atlas, world);
        Bakery.renderPng(config(atlas), drawables, polygons, name)

    /// レベル全景（3328×480・等倍）の 1 枚を焼く。camX/camY=0 の World を渡せばワールド層はずれない。
    /// 全景は design/scale だけ差し替えた設定で焼く。
    def shotWide(atlas: FontAtlas, world: Field.World, name: String): Unit \ IO =
        let (drawables, polygons) = worldCmds(atlas, { camX = 0.0, camY = 0.0 | world });
        let wide = { design = { x = Level.levelWidth(), y = Level.levelHeight() }, scale = 1 | config(atlas) };
        Bakery.renderPng(wide, drawables, polygons, name)

    /// シナリオ（初期 World + 台本）を Replay.timeline で駆動し、stride 枚ごとに 1 枚描いて
    /// GIF＋コマ別 PNG に焼く。返り値は SnapshotSite 用のフィルムストリップ情報（駒送りビューア）。
    def bakeGif(atlas: FontAtlas, world: Field.World, cues: List[Replay.Cue[Field.Input]],
                stride: Int32, name: String): SnapshotSite.Filmstrip \ IO =
        let film = Replay.timeline(Step.update, Trace.dt(), cues, world);
        Bakery.bakeGif(config(atlas), film, stride, w -> worldCmds(atlas, w), name)

    // ── 全部を焼いてサイトを生成する（Bake.all から呼ぶ）──

    pub def bakeAll(): Unit \ IO =
        discard (new File(outDir())).mkdirs();
        let atlas = Harness.atlas();

        // 画面: classic 地形の全景（スポーン相当・落下中）。
        shotWorld(atlas, Trace.classicWorld(), "screen_field");

        // レベル全景: 本番のワイドレベル（208×30 グリッド・3328×480px）を等倍 1 枚に。
        shotWide(atlas, Field.initialWorld(), "level_overview");

        // 見せ場 1: 満タンジャンプ — 上昇 23f・頂点ふわり・急降下 21f。
        let fullFilm = bakeGif(atlas, Trace.flatWorld(),
            List.append(Trace.holdJump(30), Trace.flight(66)), 2, "full_jump");

        // 見せ場 2: 短押しタップ — 4f で離すと上昇がカットされ低く飛ぶ。
        let tapFilm = bakeGif(atlas, Trace.flatWorld(),
            List.append(Trace.holdJump(4), Trace.flight(60)), 2, "short_hop");

        // 見せ場 3: 浮き床走破 — 助走ジャンプ×2 と走り落ち（台本は Trace の実測値）。
        let acrossFilm = bakeGif(atlas, Trace.runAcrossWorld(), Trace.runAcrossCues(), 2, "run_across");

        // 見せ場 4: B ダッシュ崖越え — 低ホップで浮き床の下をくぐって広い穴を渡る。
        let dashFilm = bakeGif(atlas, Trace.dashGapWorld(), Trace.dashGapCues(), 2, "dash_gap");

        // 見せ場 5: 崖死亡 — 穴の縁（x=190）から歩き出ると落ちて死に、出発点へ戻される。
        let deathFilm = bakeGif(atlas, Trace.gapDeathWorld(), Trace.gapDeathCues(), 2, "gap_death");

        // 見せ場 6: 縦リフト — 乗ると運ばれ、下降でも接地が切れない（carry は位置ベース）。
        let liftFilm = bakeGif(atlas, Trace.liftWorld(), Trace.flight(256), 4, "lift_ride");

        // 見せ場 7: 一方通行のすり抜け降下 — 上からだけ乗れて、下+ジャンプで抜けて降りる。
        let dropCues = List.flatten(
            Trace.flight(20) :: Trace.pressDownJump() :: Trace.flight(50) :: Nil);
        let dropFilm = bakeGif(atlas, Trace.onOneWayWorld(), dropCues, 2, "one_way_drop");

        // 見せ場 8: レベル走破（看板 GIF）— スポーンからゴールの旗まで死なずに走破する
        // （台本は Trace.levelRunCues の実測振り付け・敵踏み/一方通行の棚/P スピードゲート込み）。
        // 長尺なので stride 6 で間引く。
        let clearRunFilm = bakeGif(atlas, Field.initialWorld(), Trace.levelRunCues(), 6, "full_clear_run");

        // 見せ場 9: 45° 坂 — 登りは速度が斜面に沿って接地が途切れず、離すと静止摩擦で停まる。
        let slopeFilm = bakeGif(atlas, Trace.slopeWorld(),
            List.append(Trace.holdRight(70), Trace.flight(20)), 2, "slope_walk");

        // 見せ場 10: 敵 — walker A を踏んで倒し（バウンド）、走り続けて walker B に触れて死ぬ。
        let stompFilm = bakeGif(atlas, Trace.stompPatrolWorld(), Trace.stompPatrolCues(), 2, "stomp_patrol");

        // 見せ場 11: パタパタ踏み — 敵の下で待ち、下降中に重なって踏む（空中でも踏める見本）。
        let flyerBobFilm = bakeGif(atlas, Trace.flyerWorld(), Trace.flyerBobCues(), 2, "flyer_bob");

        // 見せ場 12: トゲ落とし穴 — 走ってトゲへ跳び込むと踏めずに死に、出発点へ戻って着地する。
        let spikyTrapFilm = bakeGif(atlas, Trace.spikyWorld(), Trace.spikyTrapCues(), 2, "spiky_trap");

        // キャラクターラボ: 候補キャラが同じ演技を横並びで踊る比較舞台（1800×260・CharGallery）。
        let paradeFilm = CharGallery.bake(atlas);

        // サイト生成。
        run {
            SnapshotSite.generate(
                // 出力が等倍になったので cssScale も 1（表示 = 実ピクセル 480×360）。
                { outDir = outDir(), title = "Platformer Gallery", cssScale = 1 },
                catalog({ full = fullFilm, tap = tapFilm, across = acrossFilm,
                          dash = dashFilm, death = deathFilm, lift = liftFilm, drop = dropFilm,
                          clearRun = clearRunFilm, slope = slopeFilm, stomp = stompFilm,
                          flyerBob = flyerBobFilm, spikyTrap = spikyTrapFilm,
                          parade = paradeFilm }))
        } with Fs.FileWrite.runWithIO

    // ── カタログ（ページとカードの宣言）──

    /// カタログに並べるフィルムストリップ一式（名前渡しで取り違えを防ぐ）。
    type alias Films = {
        full = SnapshotSite.Filmstrip,
        tap = SnapshotSite.Filmstrip,
        across = SnapshotSite.Filmstrip,
        dash = SnapshotSite.Filmstrip,
        death = SnapshotSite.Filmstrip,
        lift = SnapshotSite.Filmstrip,
        drop = SnapshotSite.Filmstrip,
        clearRun = SnapshotSite.Filmstrip,
        slope = SnapshotSite.Filmstrip,
        stomp = SnapshotSite.Filmstrip,
        flyerBob = SnapshotSite.Filmstrip,
        spikyTrap = SnapshotSite.Filmstrip,
        parade = SnapshotSite.Filmstrip
    }

    def catalog(films: Films): List[SnapshotSite.Item] =
        png("screen_field", "classic 地形の全景: 崖 2 本で 3 分割の地面 + 浮き床 3 枚 + 左右の壁。球体がプレイヤー", "Screens") ::
        pngAt("level_overview", "本番レベルの全景: 208×30 のテキストグリッド（3328×480px・マリオ 1-1 の文法）。丘の坂・P スピードゲートの大穴・敵 8 体・階段とゴールの旗", "Level", 3328) ::
        gif("full_jump", "満タンジャンプ: 24 フレームで頂点 96px、頂点付近はふわり（0.5 倍重力）、下降は 1.8 倍で速い", "Jump", films#full) ::
        gif("short_hop", "短押しタップ（4f）: 離した瞬間に上昇が 0.4 倍へカットされ低く飛ぶ（可変ジャンプ高）", "Jump", films#tap) ::
        gif("run_across", "浮き床走破: 助走つきジャンプで A→B と渡り、走り落ちて C へ。慣性が残ったまま壁で止まる", "Run", films#across) ::
        gif("dash_gap", "B ダッシュ崖越え（Pスピード済みから）: 低ホップで浮き床 B の下をくぐり、広い穴（80px）を渡って浮き床 C へ。素の走りでは届かない", "Gap", films#dash) ::
        gif("gap_death", "崖死亡: 歩いて穴へ出ると落ちて死に、出発点へ戻される（deaths が増える）", "Gap", films#death) ::
        gif("lift_ride", "縦リフト: 乗ると運ばれ、下降でも接地が切れない（carry は位置ベース）", "Moving", films#lift) ::
        gif("one_way_drop", "一方通行: 上からだけ乗れて、下+ジャンプですり抜けて降りる", "Moving", films#drop) ::
        gif("full_clear_run", "レベル走破: スポーンからゴールの旗まで死なずに完走。敵踏み・一方通行の棚・P スピードゲート・階段、カメラは横縦とも不感帯つきで追う", "Level", films#clearRun) ::
        gif("slope_walk", "45° の坂を登る: 速度が斜面に沿い接地は途切れない（下りは 6px の吸着）。離すと静止摩擦でその場に停まる", "Slope", films#slope) ::
        gif("stomp_patrol", "敵: 手前の歩く敵を踏んで倒し（半ジャンプのバウンド）、次の敵に横から触れて死ぬ — 出発点へ戻される", "Enemy", films#stomp) ::
        gif("flyer_bob", "パタパタは空中で踏める: 敵の下で待ち、下降中に重なるとバウンドして倒せる", "Enemy", films#flyerBob) ::
        gif("spiky_trap", "トゲは踏んでも死ぬ→出発点へ: 走って跳び込むと踏めずに死に、出発点へ戻って着地する", "Enemy", films#spikyTrap) ::
        gifAt("charparade", "キャラクターラボ: 候補 15 体が同じ 6 秒の演技（走り→Bダッシュ→スキッド→折り返し→ジャンプ→着地→待機）を横並びで踊る", "Characters", 1800, films#parade) ::
        pngAt("charlineup", "キャラクターラボの整列写真: t=5.0 の待機（呼吸）で全 15 体をラベル付きで並べた 1 枚", "Characters", 1800) :: Nil

    def png(name: String, desc: String, scenario: String): SnapshotSite.Item =
        pngAt(name, desc, scenario, pxWidth())

    def pngAt(name: String, desc: String, scenario: String, px: Int32): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "png",
          pxWidth = px, generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = SnapshotSite.noFilmstrip() }

    def gif(name: String, desc: String, scenario: String, filmstrip: SnapshotSite.Filmstrip): SnapshotSite.Item =
        gifAt(name, desc, scenario, pxWidth(), filmstrip)

    def gifAt(name: String, desc: String, scenario: String, px: Int32,
              filmstrip: SnapshotSite.Filmstrip): SnapshotSite.Item =
        { name = name, desc = desc, scenario = scenario, tags = Nil, ext = "gif",
          pxWidth = px, generateHint = Some("run `make bake` to generate"),
          lint = SnapshotSite.noLint(), filmstrip = Some(filmstrip) }
}
