// TexDemo — ShaderDoc の tex 場（Field.Tex / Field.Shift / Shade.Rgb）の実証面 5 枚。
// 「夕暮れの湖岸」を pass "scene" に 1 枚焼き、その絵をシェーダー面がテクスチャとして
// 読み直す（素通し・ぼかし・陽炎・衝撃波・色調変換）。GL 実機と同じ配管（pass → tex 場）を
// SoftRaster + ShaderEval で headless に焼くのが狙い。
//
// 画風は AGENTS.local.md の「この画面の画風」（夕暮れの湖岸・輪郭線を引かない）。

mod TexDemo {

    // ── 色（画風の 3 色 + 導出色）──

    def col(r: Int32, g: Int32, b: Int32): Color =
        { r = Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, Int32.toFloat64(r) / 255.0),
          g = Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, Int32.toFloat64(g) / 255.0),
          b = Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, Int32.toFloat64(b) / 255.0) }

    def navy(): Color      = col(26, 28, 44)     // 下地: 夜の群青
    def duskRose(): Color  = col(122, 62, 74)    // 空の裾の茜がかり
    def sun(): Color       = col(242, 166, 90)   // 主役: 茜の夕日
    def sunCore(): Color   = col(255, 224, 176)  // 夕日の芯
    def hillFar(): Color   = col(35, 39, 65)     // 遠い丘
    def hillNear(): Color  = col(22, 24, 40)     // 近い丘
    def lake(): Color      = col(36, 48, 74)     // 湖面
    def mint(): Color      = col(127, 232, 216)  // 差し色: 薄荷の水明かり

    // ── pass "scene": 夕暮れの湖岸を 1 枚に焼く ──

    def design(): Vec2.Vec2 = { x = 320.0, y = 240.0 }
    def horizonY(): Float64 = 150.0

    /// 湖面のさざなみ線（薄荷と茜の短い横線を交互に散らす）。
    def rippleLines(): List[Render.PlacedItem] =
        List.range(0, 7) |> List.map(i ->
            {
                let fi = Int32.toFloat64(i);
                let y = horizonY() + 12.0 + fi * 11.0;
                let x = 40.0 + Float64.abs(Vec2.sin(fi * 2.3)) * 140.0;
                let w = 26.0 + Float64.abs(Vec2.sin(fi * 1.7)) * 30.0;
                let color = if (Int32.modulo(i, 2) == 0) mint() else sun();
                RawDraw.lineSeg({ x = x, y = y }, { x = x + w, y = y }, 1.5, color, 6)
            })

    /// 夕日の反射帯（湖面に落ちる縦並びの短い横線）。
    def reflectionDashes(): List[Render.PlacedItem] =
        List.range(0, 6) |> List.map(i ->
            {
                let fi = Int32.toFloat64(i);
                let y = horizonY() + 8.0 + fi * 13.0;
                let w = 34.0 - fi * 4.0;
                RawDraw.lineSeg({ x = 240.0 - w / 2.0, y = y }, { x = 240.0 + w / 2.0, y = y },
                               2.5, sun(), 7)
            })

    /// 夕暮れの湖岸 1 枚ぶんの描き物（pass "scene" の中身）。
    /// 層: 空（vgrad）→ 夕日 → 丘 2 層 → 湖面 → 反射とさざなみ。
    def sceneItems(): List[Render.PlacedItem] =
        let sky = { at = Vec2.zero(),
                    item = Render.vgrad({ x = design()#x, y = horizonY() },
                                        { top = navy(), bottom = duskRose() }, 0) };
        let sunHalo = RawDraw.circleAt({ x = 240.0, y = 86.0 }, 30.0, duskRose(), 1);
        let sunBody = RawDraw.circleAt({ x = 240.0, y = 86.0 }, 21.0, sun(), 2);
        let sunGlint = RawDraw.circleAt({ x = 240.0, y = 86.0 }, 9.0, sunCore(), 3);
        let farHill  = RawDraw.ngonAt({ x = 70.0, y = 168.0 }, 24, 70.0, hillFar(), 4);
        let farHill2 = RawDraw.ngonAt({ x = 305.0, y = 178.0 }, 24, 58.0, hillFar(), 4);
        let nearHill = RawDraw.ngonAt({ x = 150.0, y = 196.0 }, 24, 62.0, hillNear(), 5);
        let water = { at = { x = 0.0, y = horizonY() },
                      item = Render.vgrad({ x = design()#x, y = design()#y - horizonY() },
                                          { top = lake(), bottom = navy() }, 5) };
        sky :: sunHalo :: sunBody :: sunGlint :: farHill :: farHill2 :: nearHill :: water
            :: List.append(reflectionDashes(), rippleLines())

    def scenePass(): Bakery.PassSpec =
        let (drawables, polygons) = Render.draw(sceneItems());
        { name = "scene", clear = RenderTarget.LoadOp.Clear(navy()),
          drawables = drawables, polygons = polygons }

    // ── Spec 組み立ての小道具 ──

    def c(v: Float64): ShaderDoc.Field = ShaderDoc.Field.Const(v)
    def add(a: ShaderDoc.Field, b: ShaderDoc.Field): ShaderDoc.Field =
        ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Add, a = a, b = b })
    def sub(a: ShaderDoc.Field, b: ShaderDoc.Field): ShaderDoc.Field =
        ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Sub, a = a, b = b })
    def mul(a: ShaderDoc.Field, b: ShaderDoc.Field): ShaderDoc.Field =
        ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Mul, a = a, b = b })
    def uvU(): ShaderDoc.Field = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.U })
    def uvV(): ShaderDoc.Field = ShaderDoc.Field.Uv({ axis = ShaderDoc.Axis.V })
    def sceneTex(chan: ShaderDoc.TexChan): ShaderDoc.Field =
        ShaderDoc.Field.Tex({ name = "scene", chan = chan })

    /// 3 チャンネルへ同じ組み立てを配る（Rgb 面の定石）。
    def rgbOf(f: ShaderDoc.TexChan -> ShaderDoc.Field): ShaderDoc.Shade =
        ShaderDoc.Shade.Rgb({ r = f(ShaderDoc.TexChan.R), g = f(ShaderDoc.TexChan.G),
                              b = f(ShaderDoc.TexChan.B) })

    def specOf(name: String, shade: ShaderDoc.Shade, alpha: ShaderDoc.Field): ShaderDoc.Spec =
        { name = name, cycleRate = 0.0, bindings = Nil,
          out = ShaderDoc.Out.Fill({ shade = shade, alpha = alpha }) }

    /// design 全面に貼る面 1 枚（uv 0..1 = 画面全体）。
    def fullSurface(spec: ShaderDoc.Spec, time: Float64): SoftRaster.SurfaceCmd =
        { rect = { position = Vec2.zero(), size = design() }, spec = spec, time = time,
          mask = Nil, zIndex = 5, blend = DrawCmd.BlendMode.Normal }

    // ── ① tex_blit: スプライト直貼り（左）と Rgb{Tex×3} 面（右）の見比べ ──

    /// 左半分 = pass をスプライトとして貼った絵・右半分 = 同じ pass を tex 場で素通しした面。
    /// 2 経路が一致していれば継ぎ目は見えない（中央の薄荷の細線が境界の目印）。
    def blitSpec(): ShaderDoc.Spec =
        specOf("tex_blit",
               rgbOf(sceneTex),
               // uv.x >= 0.5 だけ 1（Step は「b が a 以上なら 1」）。
               ShaderDoc.Field.Bin({ op = ShaderDoc.BinOp.Step, a = c(0.5), b = uvU() }))

    def bakeBlit(cfg: Bakery.BakeConfig): Unit \ IO =
        let divider = RawDraw.lineSeg({ x = 160.0, y = 0.0 }, { x = 160.0, y = 240.0 },
                                     1.0, mint(), 10);
        // Render.sprite は中心原点なので design の中央へ置く（左上に置くと 1/4 だけ見える）。
        let (drawables, polygons) =
            Render.draw({ at = Vec2.div(design(), 2.0), item = Render.sprite("scene", 0) }
                        :: divider :: Nil);
        Bakery.renderPngWithPasses(cfg, scenePass() :: Nil, drawables, polygons,
                                   fullSurface(blitSpec(), 0.0) :: Nil, "tex_blit")

    // ── ② tex_blur: 3×3 ガウス近似（Shift タップ×9 の加重平均）──

    /// 3×3 の重み（1-2-1 の積 / 16）とタップ位置。
    def blurTaps(): List[(Float64, Float64, Float64)] =
        List.flatMap(j -> List.map(i -> {
            let w = (if (i == 0) 2.0 else 1.0) * (if (j == 0) 2.0 else 1.0) / 16.0;
            (Int32.toFloat64(i), Int32.toFloat64(j), w)
        }, -1 :: 0 :: 1 :: Nil), -1 :: 0 :: 1 :: Nil)

    /// 1 チャンネルぶんのぼかし場。タップ幅は design px で 3px（Tex 読み 9 回 × 3ch = 27 回 —
    /// 語彙表のコスト試算どおり、これが JSON 合成ぼかしの実用上限あたり）。
    def blurChan(chan: ShaderDoc.TexChan): ShaderDoc.Field =
        let ox = 3.0 / design()#x;
        let oy = 3.0 / design()#y;
        let term = tap -> {
            let (i, j, w) = tap;
            let shifted = ShaderDoc.Field.Shift({ dx = c(i * ox), dy = c(j * oy),
                                                  of = sceneTex(chan) });
            mul(shifted, c(w))
        };
        // 起点は先頭タップ — c(0.0) 起点だと GLSL に「0.0 +」の無駄項が 1 つ残る。
        match blurTaps() {
            case Nil          => c(0.0)
            case first :: rest =>
                List.foldLeft((acc, tap) -> add(acc, term(tap)), term(first), rest)
        }

    def bakeBlur(cfg: Bakery.BakeConfig): Unit \ IO =
        Bakery.renderPngWithPasses(cfg, scenePass() :: Nil, Nil, Nil,
            fullSurface(specOf("tex_blur", rgbOf(blurChan), c(1.0)), 0.0) :: Nil, "tex_blur")

    // ── ③ tex_haze: 陽炎（sin ゆらぎの Shift + Warp のうねり・完全ループ GIF）──

    /// 横ゆらぎ量: sin(uv.y × 50 + t × 2π) × 0.005（1 秒で位相が 1 周 = 10 コマでループが閉じる）。
    def hazeDx(): ShaderDoc.Field =
        mul(ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.Sin,
                of = add(mul(uvV(), c(50.0)),
                         ShaderDoc.Field.Time({ scale = 6.2831853, offset = c(0.0) })) }),
            c(0.005))

    def hazeSpec(): ShaderDoc.Spec =
        specOf("tex_haze",
               rgbOf(chan -> ShaderDoc.Field.Shift({ dx = hazeDx(), dy = c(0.0),
                   of = ShaderDoc.Field.Warp({ amount = 0.012, scale = 6.0, seed = 9,
                                               of = sceneTex(chan) }) })),
               c(1.0))

    /// 陽炎 GIF（10 コマで sin の位相がちょうど 1 周する完全ループ）。
    /// pass は静止画なので 1 回だけ焼き、コマごとは面の time だけ進める。
    def bakeHazeGif(cfg: Bakery.BakeConfig): SnapshotSite.Filmstrip \ IO =
        let passImg = Bakery.bakePassImage(cfg, scenePass(), None);
        let frames = 10;
        let req: SoftRaster.RasterReq =
            { drawables = Nil, polygons = Nil, design = cfg#design, scale = cfg#scale,
              background = cfg#background, texturePath = cfg#texturePath,
              fontTtf = cfg#fontTtf, fontAtlas = cfg#fontAtlas, outPath = "" };
        let images = List.range(0, frames) |> List.map(i -> {
            let t = Int32.toFloat64(i) / Int32.toFloat64(frames);
            let img = SoftRaster.renderToImageFull(req, fullSurface(hazeSpec(), t) :: Nil,
                                                   Map.empty(), Map#{ "scene" => passImg });
            Filmstrip.bakeFrame(img, "${cfg#outDir}/frames/tex_haze/${i}.png");
            img
        });
        GifEncoder.encode(images, cfg#gifDelayMs, "${cfg#outDir}/tex_haze.gif");
        { strip = "frames/tex_haze/", frameCount = frames,
          frameW = cfg#frameW, frameH = cfg#frameH, fps = cfg#gifFps }

    // ── ④ tex_shock: 衝撃波（中心から広がるリング状の歪み）──

    /// リングの窓: 中心距離 r から「時刻とともに広がる半径 (0.12 + 0.25t)」を引き、
    /// 0 の近傍 ±0.06 だけ 1 になる山を作る。
    def shockRing(): ShaderDoc.Field =
        let d = sub(ShaderDoc.Field.Radial({ cx = 0.5, cy = 0.5 }),
                    ShaderDoc.Field.Time({ scale = 0.25, offset = c(0.12) }));
        mul(ShaderDoc.Field.Smoothstep({ lo = -0.06, hi = 0.0, of = d }),
            ShaderDoc.Field.Un({ op = ShaderDoc.UnOp.OneMinus,
                of = ShaderDoc.Field.Smoothstep({ lo = 0.0, hi = 0.06, of = d }) }))

    /// リングの上だけ、中心向きに座標を引き込む（レンズのように絵が寄る）。
    def shockSpec(): ShaderDoc.Spec =
        let dxF = mul(mul(sub(uvU(), c(0.5)), shockRing()), c(-0.15));
        let dyF = mul(mul(sub(uvV(), c(0.5)), shockRing()), c(-0.15));
        specOf("tex_shock",
               rgbOf(chan -> ShaderDoc.Field.Shift({ dx = dxF, dy = dyF, of = sceneTex(chan) })),
               c(1.0))

    def bakeShock(cfg: Bakery.BakeConfig): Unit \ IO =
        // t=0.8 でリング半径 0.32（夕日と丘に掛かる位置）。
        Bakery.renderPngWithPasses(cfg, scenePass() :: Nil, Nil, Nil,
            fullSurface(shockSpec(), 0.8) :: Nil, "tex_shock")

    // ── ⑤ tex_grade: 色調変換（luma → Gradient で夕暮れ 3 色に染め直す）──

    /// 明るさ（BT.601 の重み）を 1 本の場に畳む。
    def lumaField(): ShaderDoc.Field =
        add(add(mul(sceneTex(ShaderDoc.TexChan.R), c(0.299)),
                mul(sceneTex(ShaderDoc.TexChan.G), c(0.587))),
            mul(sceneTex(ShaderDoc.TexChan.B), c(0.114)))

    def gradeSpec(): ShaderDoc.Spec =
        specOf("tex_grade",
               ShaderDoc.Shade.Gradient({
                   stops = (0.0, col(16, 20, 44)) :: (0.55, col(201, 111, 74))
                        :: (1.0, col(255, 233, 196)) :: Nil,
                   field = lumaField() }),
               c(1.0))

    def bakeGrade(cfg: Bakery.BakeConfig): Unit \ IO =
        Bakery.renderPngWithPasses(cfg, scenePass() :: Nil, Nil, Nil,
            fullSurface(gradeSpec(), 0.0) :: Nil, "tex_grade")

    // ── 入口（Gallery.bakeAll から呼ぶ）──

    /// tex 場デモ 5 枚を焼く。返り値は tex_haze のフィルムストリップ（カタログの GIF カード用）。
    pub def bakeAll(cfg: Bakery.BakeConfig): SnapshotSite.Filmstrip \ IO =
        bakeBlit(cfg);
        bakeBlur(cfg);
        bakeShock(cfg);
        bakeGrade(cfg);
        bakeHazeGif(cfg)
}
