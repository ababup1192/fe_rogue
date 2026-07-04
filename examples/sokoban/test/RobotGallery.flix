// RobotGallery — 目視承認用のロボットデザインギャラリーをヘッドレスに焼き込む
// （engine_tools の SoftRaster + GifEncoder、GL なし）；flix test がファイルを生
// 成する。
//
//   gallery/robots.png            — 元の6候補（参考用に保持）
//   gallery/robot2_directions.png — 選ばれたロボット（候補2、丸い目）x 4方向
//   gallery/robot2_walk.gif       — 4方向がその場で行進する（歩行サイクルの確認）
//
// クレートと同じ手続き的アプローチ: 16ユニットのタイルグリッド上に配置されたボ
// ックスの積み重ね（一部は凸クアッドを併用）を8倍で描画し、見やすくしている。選
// ばれたロボットは src/Robot.flix に住み（Palette のロールと共に）、6候補はロー
// カルな色を保持する。

mod RobotGallery {
    import java.io.File

    // ── キャンバスのレイアウト ──
    // 18ユニットのセルが6個；各ロボットは16ユニットのタイルに1ユニットの余白を
    // 持って収まる。
    def u(): Float64 = 8.0                       // ピクセルアート1ユニット = 8 design px（8倍表示）
    def cellW(): Float64 = 18.0 * u()            // 1セルあたり144px
    def robotTop(): Float64 = 12.0
    def labelY(): Float64 = robotTop() + 16.0 * u() + 6.0
    def designSize(): Vec2.Vec2 = {x = 6.0 * cellW(), y = 184.0}

    // ── 候補用の DB32 の色 ──
    def body(): Color   = {r = 0.356863f32, g = 0.431373f32, b = 0.882353f32}  // #5b6ee1
    def light(): Color  = {r = 0.388235f32, g = 0.607843f32, b = 1.000000f32}  // #639bff
    def pale(): Color   = {r = 0.796078f32, g = 0.858824f32, b = 0.988235f32}  // #cbdbfc
    def accent(): Color = {r = 0.984314f32, g = 0.949020f32, b = 0.211765f32}  // #fbf236
    def dark(): Color   = {r = 0.133333f32, g = 0.125490f32, b = 0.203922f32}  // #222034
    def backdrop(): Color = {r = 0.270588f32, g = 0.156863f32, b = 0.235294f32}  // #45283c

    def ttfPath(): String = "assets/Xolonium-Regular.ttf"
    def outPath(): String = "gallery/robots.png"

    // ── パーツのヘルパー（座標はタイル単位、ロボットのセル原点からの相対値）──

    def box(o: Vec2.Vec2, x: Float64, y: Float64, w: Float64, h: Float64,
            c: Color): (Vec2.Vec2, Render.RenderItem) =
        ({x = o#x + x * u(), y = o#y + y * u()},
         Render.solidBox({x = w * u(), y = h * u()}, c, 0))

    /// 角丸ボックス（cornerRadius はタイル単位）。候補4と候補6の車輪で使う。
    def rbox(o: Vec2.Vec2, x: Float64, y: Float64, w: Float64, h: Float64,
             r: Float64, c: Color): (Vec2.Vec2, Render.RenderItem) =
        let style = { cornerRadius = r * u(), borderWidth = 0.0, borderColor = c,
                      borderAlpha = 0.0f32, stripeColor = c, stripeAlpha = 0.0f32,
                      stripeWidth = 0.0, stripePeriod = 0.0 };
        ({x = o#x + x * u(), y = o#y + y * u()},
         Render.RenderItem.Box({ size = {x = w * u(), y = h * u()}, color = c,
                                 alpha = 1.0f32, style = Some(style), zIndex = 1 }))

    /// タイル単位の凸クアッド（候補5の台形の胴体）。z -1 でボックス群の下に置
    /// き、z 0 で描かれる腕や胸のディテールが胴体の上に見えるようにする。
    def quad(o: Vec2.Vec2, ps: List[(Float64, Float64)], c: Color): GameEngine.PolygonRenderCmd =
        { vertices = List.map(p -> let (x, y) = p; {x = o#x + x * u(), y = o#y + y * u()}, ps),
          color = c, alpha = 1.0f32, zIndex = -1 }

    // ── 6候補 ──

    /// 1. クラシック: ずんぐりした四角い体、2つの目、1本のアンテナ。無難な万人
    /// 受け。
    def robot1(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 7.6, 1.6, 0.8, 2.6, light()) ::          // アンテナの軸
        box(o, 6.8, 0.2, 2.4, 2.0, accent()) ::         // アンテナの先端
        box(o, 3.0, 4.0, 10.0, 9.0, body()) ::          // 体
        box(o, 3.0, 4.0, 10.0, 1.2, light()) ::         // 上部のハイライト
        box(o, 5.2, 6.6, 1.8, 1.8, accent()) ::         // 左目
        box(o, 9.0, 6.6, 1.8, 1.8, accent()) ::         // 右目
        box(o, 6.0, 10.2, 4.0, 0.8, dark()) ::          // 口の格子
        box(o, 1.5, 6.0, 1.4, 4.0, light()) ::          // 左腕
        box(o, 13.1, 6.0, 1.4, 4.0, light()) ::         // 右腕
        box(o, 4.0, 13.0, 3.0, 1.6, light()) ::         // 左足
        box(o, 9.0, 13.0, 3.0, 1.6, light()) :: Nil     // 右足

    /// 2. サイクロプス: 大きな目が1つの、背の高いスラブ状の体。16pxでも十分読め
    /// る。
    def robot2(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 4.5, 2.0, 7.0, 12.0, body()) ::          // 背の高い体
        box(o, 4.5, 2.0, 7.0, 1.0, light()) ::          // 上部のハイライト
        box(o, 6.0, 4.0, 4.0, 4.0, pale()) ::           // 目の輪
        box(o, 7.2, 5.2, 1.6, 1.6, dark()) ::           // 瞳孔
        box(o, 6.0, 9.6, 4.0, 0.7, dark()) ::           // 胸の線
        box(o, 5.4, 11.0, 1.2, 0.6, light()) ::         // 通気口 1
        box(o, 5.4, 12.0, 1.2, 0.6, light()) ::         // 通気口 2
        box(o, 3.0, 5.0, 1.5, 5.0, light()) ::          // 左腕
        box(o, 11.5, 5.0, 1.5, 5.0, light()) ::         // 右腕
        box(o, 5.0, 14.0, 2.5, 1.5, light()) ::         // 左足
        box(o, 8.5, 14.0, 2.5, 1.5, light()) :: Nil     // 右足

    /// 3. 2ピース構成: 頭と胴体が分かれ、脚は短い。最も「押す者」らしい体型。
    def robot3(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 4.5, 1.5, 7.0, 4.5, body()) ::           // 頭
        box(o, 6.0, 3.0, 1.5, 1.5, accent()) ::         // 左目
        box(o, 8.5, 3.0, 1.5, 1.5, accent()) ::         // 右目
        box(o, 7.0, 6.0, 2.0, 1.0, dark()) ::           // 首
        box(o, 3.5, 7.0, 9.0, 6.0, body()) ::           // 胴体
        box(o, 5.5, 8.5, 5.0, 3.0, light()) ::          // 腹部パネル
        box(o, 7.3, 9.8, 1.4, 0.6, dark()) ::           // パネルのスリット
        box(o, 5.0, 13.0, 2.0, 2.0, light()) ::         // 左脚
        box(o, 9.0, 13.0, 2.0, 2.0, light()) ::         // 右脚
        box(o, 4.6, 14.6, 2.8, 0.9, dark()) ::          // 左足パッド
        box(o, 8.6, 14.6, 2.8, 0.9, dark()) :: Nil      // 右足パッド

    /// 4. 丸型: cornerRadius の柔らかい体に、単眼のバイザー。
    def robot4(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        rbox(o, 3.5, 3.0, 9.0, 11.0, 2.5, body()) ::    // 丸みを帯びた体
        rbox(o, 4.5, 5.2, 7.0, 2.8, 1.4, dark()) ::     // バイザーの筐体
        rbox(o, 5.0, 5.8, 6.0, 1.6, 0.8, accent()) ::   // バイザー（目そのもの）
        box(o, 2.6, 6.0, 1.0, 2.0, light()) ::          // 左耳のボルト
        box(o, 12.4, 6.0, 1.0, 2.0, light()) ::         // 右耳のボルト
        rbox(o, 6.0, 10.0, 4.0, 2.2, 1.0, light()) ::   // 腹部のライト
        rbox(o, 4.8, 13.6, 2.6, 1.4, 0.7, light()) ::   // 左足
        rbox(o, 8.6, 13.6, 2.6, 1.4, 0.7, light()) :: Nil  // 右足

    /// 5. ヘビー級: 台形の胴体（凸クアッド）の上に小さな頭 —— 幅広で安定した立ち
    /// 姿勢。
    def robot5Boxes(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 5.5, 1.5, 5.0, 3.5, body()) ::           // 頭
        box(o, 6.5, 2.6, 1.2, 1.2, accent()) ::         // 左目
        box(o, 8.3, 2.6, 1.2, 1.2, accent()) ::         // 右目
        box(o, 7.2, 5.0, 1.6, 0.9, dark()) ::           // 首
        box(o, 6.5, 8.0, 3.0, 1.0, light()) ::          // 胸のストライプ
        box(o, 3.4, 7.0, 1.4, 4.2, light()) ::          // 左腕
        box(o, 11.2, 7.0, 1.4, 4.2, light()) ::         // 右腕
        box(o, 5.0, 13.5, 2.2, 1.4, light()) ::         // 左足
        box(o, 8.8, 13.5, 2.2, 1.4, light()) :: Nil     // 右足

    def robot5Polys(o: Vec2.Vec2): List[GameEngine.PolygonRenderCmd] =
        quad(o, (5.5, 6.0) :: (10.5, 6.0) :: (12.5, 13.5) :: (3.5, 13.5) :: Nil, body()) :: Nil

    /// 6. CRT: 画面上にドット状の目を持つモニターの顔で、車輪付きの台に乗る。
    def robot6(o: Vec2.Vec2): List[(Vec2.Vec2, Render.RenderItem)] =
        box(o, 3.0, 2.5, 10.0, 8.0, body()) ::          // モニターの筐体
        box(o, 4.2, 3.7, 7.6, 5.6, pale()) ::           // 画面
        box(o, 6.2, 5.6, 1.2, 1.2, dark()) ::           // 左のドットの目
        box(o, 8.6, 5.6, 1.2, 1.2, dark()) ::           // 右のドットの目
        box(o, 6.8, 7.6, 2.4, 0.6, dark()) ::           // 笑顔の線
        box(o, 6.0, 10.5, 4.0, 1.5, light()) ::         // 首
        box(o, 4.0, 12.0, 8.0, 2.0, body()) ::          // シャーシ
        rbox(o, 4.6, 13.6, 2.0, 1.6, 0.8, dark()) ::    // 左の車輪
        rbox(o, 9.4, 13.6, 2.0, 1.6, 0.8, dark()) :: Nil  // 右の車輪

    // ── 組み立て ──

    def cellOrigin(i: Int32): Vec2.Vec2 =
        {x = Int32.toFloat64(i) * cellW() + 1.0 * u(), y = robotTop()}

    def label(atlas: FontAtlas, i: Int32): (Vec2.Vec2, Render.RenderItem) =
        let text = "${i + 1}";
        let size = 22.0;
        let w = Label2D.measure(Label2D.make(text, atlas, size))#x;
        let cx = Int32.toFloat64(i) * cellW() + cellW() / 2.0;
        ({x = cx - w / 2.0, y = labelY()}, Render.textTinted(text, atlas, size, pale(), 10))

    def galleryItems(atlas: FontAtlas):
            (List[(Vec2.Vec2, Render.RenderItem)], List[GameEngine.PolygonRenderCmd]) =
        let robots = robot1(cellOrigin(0)) :: robot2(cellOrigin(1)) :: robot3(cellOrigin(2)) ::
                     robot4(cellOrigin(3)) :: robot5Boxes(cellOrigin(4)) :: robot6(cellOrigin(5)) :: Nil;
        let labels = List.map(i -> label(atlas, i), 0 :: 1 :: 2 :: 3 :: 4 :: 5 :: Nil);
        (List.append(List.flatten(robots), labels), robot5Polys(cellOrigin(4)))

    // ── テストエントリー: PNG を焼き込んで健全性を確認する ──

    @Test
    def testRobotGalleryPng(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt");
        let (items, polys) = galleryItems(atlas);
        discard (new File("gallery")).mkdirs();
        SoftRaster.render({
            drawables = Render.draw(items), polygons = polys,
            design = designSize(), scale = 1, background = backdrop(),
            texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
            outPath = outPath()
        });
        // 健全性チェック: ファイルが存在し、すべての候補がパーツを提供している。
        Assert.assertEq(expected = true,
            (new File(outPath())).exists() and List.length(items) > 50 and List.length(polys) == 1)

    // ── ギャラリー v2: 選ばれたロボットの4方向、静止時と歩行時 ──

    def dirDesign(): Vec2.Vec2 = {x = 4.0 * cellW(), y = 184.0}
    def dirOutPath(): String = "gallery/robot2_directions.png"
    def walkOutPath(): String = "gallery/robot2_walk.gif"
    def walkFrameDelayMs(): Int32 = 150

    def robotCenter(i: Int32): Vec2.Vec2 =
        {x = Int32.toFloat64(i) * cellW() + cellW() / 2.0, y = robotTop() + 8.0 * u()}

    def labelAt(atlas: FontAtlas, i: Int32, text: String): (Vec2.Vec2, Render.RenderItem) =
        let size = 22.0;
        let w = Label2D.measure(Label2D.make(text, atlas, size))#x;
        let cx = Int32.toFloat64(i) * cellW() + cellW() / 2.0;
        ({x = cx - w / 2.0, y = labelY()}, Render.textTinted(text, atlas, size, pale(), 10))

    /// 歩行位相 `phase`（0.0 = 静止ポーズ）における、4方向並びの1フレーム。
    def directionItems(atlas: FontAtlas, phase: Float64): List[(Vec2.Vec2, Render.RenderItem)] =
        let one = i -> dir -> name ->
            List.append(Robot.parts(robotCenter(i), 16.0 * u(), dir, phase),
                        labelAt(atlas, i, name) :: Nil);
        List.flatten(
            one(0)(Dir4.Down)("Down") ::
            one(1)(Dir4.Left)("Left") ::
            one(2)(Dir4.Right)("Right") ::
            one(3)(Dir4.Up)("Up") :: Nil)

    def directionsReq(atlas: FontAtlas, phase: Float64, path: String): SoftRaster.RasterReq =
        { drawables = Render.draw(directionItems(atlas, phase)), polygons = Nil,
          design = dirDesign(), scale = 1, background = backdrop(),
          texturePath = Map.empty(), fontTtf = ttfPath(), fontAtlas = atlas,
          outPath = path }

    @Test
    def testRobotDirectionsPng(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt");
        discard (new File("gallery")).mkdirs();
        SoftRaster.render(directionsReq(atlas, 0.0, dirOutPath()));
        Assert.assertEq(expected = true,
            (new File(dirOutPath())).exists() and
            List.length(directionItems(atlas, 0.0)) > 30)

    /// 歩行サイクル: 4拍（静止、一歩、静止、一歩）、すべての向きが歩調を合わせ
    /// る —— Down/Up では足の上げ、Left/Right では歩幅の開閉と腕のスイング。
    @Test
    def testRobotWalkGif(): Unit \ {Assert, IO} =
        HeadlessFont.ensureHeadless();
        let atlas = HeadlessFont.buildUiAtlas(ttfPath(), "assets/joyo.txt");
        discard (new File("gallery")).mkdirs();
        let frames = List.map(p -> SoftRaster.renderToImage(directionsReq(atlas, p, walkOutPath())),
                              0.0 :: 0.25 :: 0.5 :: 0.75 :: Nil);
        GifEncoder.encode(frames, walkFrameDelayMs(), walkOutPath());
        Assert.assertEq(expected = true, (new File(walkOutPath())).exists())
}
