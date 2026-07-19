// World → 絵。ページで表示が変わる。
// page=0（水）: 左上に池タイル（毎フレーム Params から組み立て）、右上にマグマ2枚（静的）、
//   下半分に水スライダー。
// page=1（岸）: 上部に岸の合成プレビュー（陸→草の凸凹→土＋石→水）、下半分に岸スライダー。
// camera は使わず design 座標をそのまま描く。

mod View {

    // 池が取りうる最大の領域（左上固定）。背景の草原はここ全体を覆う。
    def pondMaxSize(): Vec2.Vec2 = { x = 300.0, y = 170.0 }
    def pondOrigin(): Vec2.Vec2 = { x = 16.0, y = 16.0 }

    // 池プレビュー矩形。左上を固定し、pondScale で縮む。
    def pondRect(world: World.World): Rect2.Rect2 =
        { position = pondOrigin(),
          size = { x = pondMaxSize()#x * world#pondScale, y = pondMaxSize()#y * world#pondScale } }

    def flowRect(): Rect2.Rect2 = { position = { x = 332.0, y = 16.0 }, size = { x = 212.0, y = 80.0 } }
    def metalRect(): Rect2.Rect2 = { position = { x = 332.0, y = 106.0 }, size = { x = 212.0, y = 80.0 } }

    def labelColor(): Color = { r = 0.90f32, g = 0.92f32, b = 0.95f32 }

    /// 0..1 の Float64 を色成分（Float32）へ。範囲外は 0..1 に丸める。
    def f32(x: Float64): Float32 =
        Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, x)

    /// 全体を描く。ページで水エディタと岸エディタを切り替える。
    pub def frame(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        let body = if (world#page == 0) waterPage(ctx, world) else shorePage(ctx, world);
        List.append(pageHeader(ctx, world), body)

    /// 画面上部のページ名と操作ヒント。
    def pageHeader(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        let name = if (world#page == 0) "page: water" else "page: shore";
        let title = TextDraw.centeredAt({
            text = name, atlas = ctx#atlas, size = 11.0,
            color = { r = 0.85f32, g = 0.90f32, b = 1.0f32 }, z = 120,
            center = { x = 60.0, y = 7.0 } });
        let hint = TextDraw.centeredAt({
            text = "Space: switch page", atlas = ctx#atlas, size = 10.0,
            color = { r = 0.55f32, g = 0.58f32, b = 0.62f32 }, z = 120,
            center = { x = 470.0, y = 7.0 } });
        title :: hint :: Nil

    // ── 水ページ（もとのエディタそのまま）───────────────────────────────

    def waterPage(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        let pondSpec = PondShader.build(world#params);
        let pr = pondRect(world);
        // 最背面(z=-1)=草原色（池の外に見える床）。その上(z=0)=水底の背景色（floor スライダー・
        // opacity を下げるとこの色が透けて見える）。一番上(z=1)=シェーダーの網目。
        let grass = grassBg(world);
        let waterFill = Render.boxAt(
            { x = pr#position#x + pr#size#x / 2.0, y = pr#position#y + pr#size#y / 2.0 },
            pr#size,
            { r = f32(world#floorR), g = f32(world#floorG), b = f32(world#floorB) }, 0);
        let tiles =
            grass :: waterFill ::
                Render.shaderFill(pondSpec, pr, world#time, 1) ::
                Render.shaderFill(world#moltenFlow, flowRect(), world#time, 1) ::
                Render.shaderFill(world#moltenMetal, metalRect(), world#time, 1) :: Nil;
        let tileLabels =
            tileLabel(ctx, "pond (drag sliders)", pr) ::
            tileLabel(ctx, "molten flow", flowRect()) ::
            tileLabel(ctx, "molten metal", metalRect()) :: Nil;
        let sliderItems = allSliderRows(ctx, world);
        let hint = TextDraw.centeredAt({
            text = "drag = edit (auto-saves)   wheel = pond size (net fineness follows)",
            atlas = ctx#atlas, size = 10.0,
            color = { r = 0.55f32, g = 0.58f32, b = 0.62f32 }, z = 100,
            center = { x = 280.0, y = 474.0 } });
        List.append(tiles, List.append(tileLabels, hint :: sliderItems))

    /// 池の下に敷く草原の一枚板（dungeon と同じ床色をスライダーで調整）。
    def grassBg(world: World.World): Render.PlacedItem =
        let sz = pondMaxSize();
        let center = { x = pondOrigin()#x + sz#x / 2.0, y = pondOrigin()#y + sz#y / 2.0 };
        Render.boxAt(center, sz,
            { r = f32(world#bgR), g = f32(world#bgG), b = f32(world#bgB) }, -1)

    /// タイルの下端の中央にラベルを置く。
    def tileLabel(ctx: App.ViewCtx, text: String, rect: Rect2.Rect2): Render.PlacedItem =
        TextDraw.centeredAt({
            text = text, atlas = ctx#atlas, size = 12.0, color = labelColor(), z = 100,
            center = { x = rect#position#x + rect#size#x / 2.0,
                       y = rect#position#y + rect#size#y + 10.0 } })

    // ── 岸ページ（合成プレビュー＋岸スライダー）─────────────────────────

    // プレビューの帯（横長）。上から陸→草の凸凹→土＋石→水を重ねる。
    def shorePreviewRect(): Rect2.Rect2 = { position = { x = 16.0, y = 16.0 }, size = { x = 400.0, y = 150.0 } }

    def shorePage(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        let preview = shorePreview(world);
        let label = TextDraw.centeredAt({
            text = "shore preview (drag sliders)", atlas = ctx#atlas, size = 12.0,
            color = labelColor(), z = 100,
            center = { x = 216.0, y = 176.0 } });
        let sliderItems = allSliderRows(ctx, world);
        List.append(preview, label :: sliderItems)

    /// 岸の合成プレビュー。陸の緑・草の凸凹・土の帯（下端が凸凹する面）・水を上から重ねて描く。
    def shorePreview(world: World.World): List[Render.PlacedItem] =
        let r = shorePreviewRect();
        let x0 = r#position#x;
        let w = r#size#x;
        let sh = world#shore;
        // 帯を縦に区切る。陸(緑)は上部、その下端が「草の生え際」。土は中段（高さはスライダー）、水は最下段。
        let landTop = r#position#y;                 // 16
        let grassLine = landTop + 44.0;             // 草の生え際（凸凹はここから下へ垂れる）
        let dirtTop = grassLine + 4.0;              // 土の帯の上端
        let dirtBottom = dirtTop + sh#dirtH;        // 土の帯の下端（スライダー dirtH で動く）
        let waterBottom = landTop + r#size#y;       // 帯の下端（水の底）
        let grassCol = { r = f32(sh#gColR), g = f32(sh#gColG), b = f32(sh#gColB) };
        let dirtCol = { r = f32(sh#dColR), g = f32(sh#dColG), b = f32(sh#dColB) };
        let outCol = { r = f32(sh#outColR), g = f32(sh#outColG), b = f32(sh#outColB) };
        // 1) 陸の緑（生え際まで）。上=明るめ→下=暗めの縦グラデ。一番奥(z=0)。
        let land = gradientBand(x0, w, landTop, grassLine,
            lighten(grassCol, 0.25f32), darken(grassCol, 0.20f32), 0);
        // 3) 水（最下段・参考用の単純な青）。z=1。
        let water = Render.boxAt(
            { x = x0 + w / 2.0, y = (dirtBottom + waterBottom) / 2.0 },
            { x = w, y = waterBottom - dirtBottom },
            { r = 0.16f32, g = 0.43f32, b = 0.55f32 }, 1) :: Nil;
        // 2) 土の帯。上端はまっすぐ、下端(水との境)が手前(下)に出たり奥(上)に引っ込んだりする凸凹面。
        //    面を縦グラデの短冊で塗り、下端の凸凹プロフィールで各短冊の下端を切る。
        let dirt = dirtBand(world, x0, w, dirtTop, dirtBottom, dirtCol, outCol);
        // 4) 草の凸凹（生え際から下へ垂れるコブの列）。z=3、その下側に縁取り。
        let bumps = grassBumps(world, x0, w, grassLine, grassCol, outCol);
        List.append(land, List.append(water, List.append(dirt, bumps)))

    /// 縦グラデの帯。上端 topY(色 topCol)→下端 botY(色 botCol)を N 段の短冊で塗る。
    /// 各短冊は単色 box なので、段数を増やすほどなめらかに見える。
    def gradientBand(x0: Float64, w: Float64, topY: Float64, botY: Float64,
                     topCol: Color, botCol: Color, z: Int32): List[Render.PlacedItem] =
        let segs = 12;
        let h = (botY - topY) / Int32.toFloat64(segs);
        List.range(0, segs) |> List.map(k -> {
            let t = (Int32.toFloat64(k) + 0.5) / Int32.toFloat64(segs);  // 0..1（段の中央）
            let col = mixCol(topCol, botCol, Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, t));
            let cy = topY + (Int32.toFloat64(k) + 0.5) * h;
            Render.boxAt({ x = x0 + w / 2.0, y = cy }, { x = w, y = h + 0.5 }, col, z)
        })

    /// 色を白へ寄せて明るくする（t=0 でそのまま・1 で真っ白）。
    def lighten(c: Color, t: Float32): Color =
        mixCol(c, { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, t)

    /// 色を黒へ寄せて暗くする（t=0 でそのまま・1 で真っ黒）。
    def darken(c: Color, t: Float32): Color =
        mixCol(c, { r = 0.0f32, g = 0.0f32, b = 0.0f32 }, t)

    /// 2色を t で線形補間する。
    def mixCol(a: Color, b: Color, t: Float32): Color =
        { r = a#r + (b#r - a#r) * t,
          g = a#g + (b#g - a#g) * t,
          b = a#b + (b#b - a#b) * t }

    /// 草の生え際に横一列のコブを並べる。gJagged(0..1)で丸ドーム↔尖り三角を「連続的に」変える。
    /// gBumpH を基準に index ベースの疑似ランダム（sin）で高さを散らす。
    /// コブ本体は草色（上明るめ→下暗めのグラデ2枚重ね）。その下（水側）に gOutline の暗い縁取り。
    def grassBumps(world: World.World, x0: Float64, w: Float64, grassLine: Float64,
                   grassCol: Color, outCol: Color): List[Render.PlacedItem] =
        let sh = world#shore;
        let count = 16;                       // コブの数
        let step = w / Int32.toFloat64(count);
        let jag = sh#gJagged;
        let outW = sh#gOutline;
        let colTop = lighten(grassCol, 0.20f32);
        let colBot = darken(grassCol, 0.25f32);
        List.range(0, count) |> List.flatMap(i -> {
            let fi = Int32.toFloat64(i);
            let cx = x0 + (fi + 0.5) * step;
            // 疑似ランダム: sin の小数部で 0..1。高さは gBumpH の 0.6..1.0 倍。
            let noise = (Vec2.sin(fi * 12.9898) * 43758.5453);
            let frac = noise - Float64.floor(noise);
            let h = sh#gBumpH * (0.6 + 0.4 * frac);
            let halfW = step * 0.55;
            // コブの陰影: 同じ山を「暗い色で少し大きく」→「明るい色で少し小さく」の2枚重ねで縦グラデ風に。
            let vBot = bumpVerts(cx, grassLine, halfW, h, jag);
            let vTop = bumpVerts(cx, grassLine, halfW * 0.86, h * 0.7, jag);
            let bodyBot = { at = Vec2.zero(), item = Render.polygon(vBot, colBot, 3) };
            let bodyTop = { at = Vec2.zero(), item = Render.polygon(vTop, colTop, 4) };
            // 下側の縁取り: 同じ山を outW だけ下にずらした暗い山を裏に敷く。
            if (outW <= 0.0) bodyBot :: bodyTop :: Nil
            else {
                let outVerts = bumpVerts(cx, grassLine + outW, halfW, h, jag);
                let outline = { at = Vec2.zero(), item = Render.polygon(outVerts, outCol, 2) };
                outline :: bodyBot :: bodyTop :: Nil
            }
        })

    /// 1 コブぶんの頂点。jag(0..1)で丸ドーム↔尖り三角を「連続的に」補間する。
    /// top は山の付け根 y（頂点はそこから下へ h）。halfW は左右の広がり。
    /// 弧を折れ線で近似し、各点の「垂れ量」を jag で丸カーブ↔三角（|三角波|）に混ぜる。
    def bumpVerts(cx: Float64, top: Float64, halfW: Float64, h: Float64, jag: Float64):
            List[Vec2.Vec2] =
        let segs = 8;
        List.range(0, segs + 1) |> List.map(k -> {
            let u = Int32.toFloat64(k) / Int32.toFloat64(segs);  // 0..1（左→右）
            let px = cx - halfW + u * (halfW * 2.0);
            // 丸カーブ = sin（真ん中が一番高い半円）。三角 = 中央でとがる山（1-|2u-1|）。
            let round = Vec2.sin(u * 3.14159265358979);
            let tri = 1.0 - Float64.abs(2.0 * u - 1.0);
            // jag=0 で round、jag=1 で tri を採る（連続補間）。
            let prof = round * (1.0 - jag) + tri * jag;
            { x = px, y = top + h * prof }
        })

    /// 土の帯。上端はまっすぐ、下端(水との境)はゆるく波打つだけ。土の「面の中」に、
    /// 手前へ出っ張る塊(明るい)と奥へ引っ込む塊(暗い)の丸い凸凹を散らして立体感を出す。
    /// dirtBumpH が塊の立体感（手前↔奥の明暗差＋ずらし量）、dirtJagged が下端の波の尖り具合。
    /// 下端には outCol の細い縁取りを添える。
    def dirtBand(world: World.World, x0: Float64, w: Float64, dirtTop: Float64, dirtBottom: Float64,
                 dirtCol: Color, outCol: Color): List[Render.PlacedItem] =
        let sh = world#shore;
        let jag = sh#dirtJagged;
        let colTop = lighten(dirtCol, 0.16f32);
        let colBot = darken(dirtCol, 0.20f32);
        let waveAmp = 2.5;                    // 下端の波の高さ（固定・控えめ）
        let cols = 40;                        // 横方向の短冊の数（多いほどなめらか）
        let cw = w / Int32.toFloat64(cols);
        // 1) 面の下地: 上明るめ→下暗めの縦グラデ短冊。下端は jag で丸↔尖りの控えめな波。
        let base = List.range(0, cols) |> List.flatMap(k -> {
            let cx = x0 + (Int32.toFloat64(k) + 0.5) * cw;
            let u = (Int32.toFloat64(k) + 0.5) / Int32.toFloat64(cols);  // 0..1
            let bottom = dirtBottom + edgeProfile(u, jag) * waveAmp;
            let midCol = mixCol(colTop, colBot, 0.5f32);
            let body = Render.boxAt({ x = cx, y = (dirtTop + bottom) / 2.0 },
                { x = cw + 0.5, y = Float64.max(1.0, bottom - dirtTop) }, midCol, 1);
            let upper = Render.boxAt({ x = cx, y = (dirtTop + (dirtTop + bottom) / 2.0) / 2.0 },
                { x = cw + 0.5, y = Float64.max(1.0, (bottom - dirtTop) / 2.0) }, colTop, 1);
            let line = Render.boxAt({ x = cx, y = bottom },
                { x = cw + 0.5, y = 1.5 }, outCol, 2);
            body :: upper :: line :: Nil
        });
        // 2) 塊(クロッド): 面の上に散らす立体的な丸い凸凹。
        let clods = dirtClods(sh, x0, w, dirtTop, dirtBottom, dirtCol);
        List.append(base, clods)

    /// 土の面に散らす立体的な塊(クロッド)。各塊 = 右下へずらした暗い影(奥)＋左上の明るい膨らみ(手前)
    /// の丸2枚重ねで「手前にボコッと出た」ように見せる。dirtBumpH で明暗差もずらし量も増える。
    /// グリッドは間引き＆ジッターでグリッド臭を消す。帯の外へはみ出す塊は描かない。
    def dirtClods(sh: World.Shore, x0: Float64, _w: Float64, dirtTop: Float64, dirtBottom: Float64,
                  dirtCol: Color): List[Render.PlacedItem] =
        let relief = sh#dirtBumpH;                        // 0..20
        if (relief <= 0.1) Nil
        else {
            let t = Float64.min(0.5, relief / 20.0 * 0.5); // 手前↔奥の明暗差（0..0.5）
            let off = 0.6 + relief / 20.0 * 1.8;           // 影と膨らみのずらし量 px
            let litCol = lighten(dirtCol, Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, t * 1.1));
            let shadeCol = darken(dirtCol, Float64.clampToFloat32(min = 0.0f32, max = 1.0f32, t));
            let spacing = 9.0;
            let cols = 44;                                  // w=400/9 ≈ 44 で埋める
            let rows = 8;                                   // dirtH 最大 70/9 ≈ 8。下端超えは描かない
            List.range(0, cols) |> List.flatMap(ci ->
                List.range(0, rows) |> List.flatMap(ri -> {
                    let fi = Int32.toFloat64(ci);
                    let fj = Int32.toFloat64(ri);
                    let n1 = hash01(fi * 1.7 + fj * 3.1);
                    let n2 = hash01(fi * 2.3 + fj * 5.9 + 1.0);
                    let n3 = hash01(fi * 4.1 + fj * 1.3 + 2.0);
                    let cx = x0 + (fi + 0.5) * spacing + (n1 - 0.5) * spacing * 0.8;
                    let cy = dirtTop + (fj + 0.5) * spacing + (n2 - 0.5) * spacing * 0.8;
                    // 22% 間引き＋帯の縁からはみ出す塊は描かない。
                    if (n3 < 0.22 or cy < dirtTop + 1.0 or cy > dirtBottom - 1.0) Nil
                    else {
                        let rr = spacing * 0.5 * (0.7 + 0.5 * n1);
                        let shadow = Render.circleAt({ x = cx + off, y = cy + off }, rr, shadeCol, 3);
                        let bulge = Render.circleAt({ x = cx - off * 0.6, y = cy - off * 0.6 },
                            rr * 0.82, litCol, 4);
                        shadow :: bulge :: Nil
                    }
                }))
        }

    /// sin ベースの疑似乱数 0..1（塊の位置・大きさを散らすのに使う）。
    def hash01(x: Float64): Float64 =
        let n = Vec2.sin(x * 12.9898) * 43758.5453;
        n - Float64.floor(n)

    /// 土の下端の凸凹プロフィール（-1..1）。u は横位置 0..1。
    /// 位相の違う 2 つの波を混ぜて「出たり引っ込んだり」を作り、jag で丸波↔三角波に寄せる。
    def edgeProfile(u: Float64, jag: Float64): Float64 =
        let pi2 = 6.28318530717959;
        // 丸波 = sin の重ね（周期の違う 2 本）。-1..1 に収まるよう 0.6/0.4 で配分。
        let round = 0.6 * Vec2.sin(u * pi2 * 2.3) + 0.4 * Vec2.sin(u * pi2 * 4.7 + 1.3);
        // 三角波 = 丸波と同符号の折れ（|round| を使わず sign(round)*(1-|...|) で尖らせる簡易版）。
        let s = if (round >= 0.0) 1.0 else -1.0;
        let tri = s * (1.0 - Float64.abs(1.0 - Float64.abs(round)));
        round * (1.0 - jag) + tri * jag

    // ── スライダー行（両ページ共通・表示中ページの並びを使う）──────────

    def allSliderRows(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        List.mapWithIndex((i, d) -> sliderRow(ctx, world, i, d), Sliders.defsFor(world#page))
            |> List.flatten

    /// スライダー1行 = トラック＋つまみ＋左のラベル＋右の数値。
    def sliderRow(ctx: App.ViewCtx, world: World.World, i: Int32, d: Sliders.Def):
            List[Render.PlacedItem] =
        let ry = Sliders.rowY(i);
        let track = Render.boxAt(
            { x = Sliders.trackX() + Sliders.trackW() / 2.0, y = ry },
            { x = Sliders.trackW(), y = 4.0 },
            { r = 0.30f32, g = 0.30f32, b = 0.35f32 }, 50);
        let v = Sliders.get(world, d#key);
        let tnorm = (v - d#lo) / (d#hi - d#lo);
        let hx = Sliders.trackX() + tnorm * Sliders.trackW();
        let handle = Render.boxAt(
            { x = hx, y = ry },
            { x = 8.0, y = 14.0 },
            { r = 0.90f32, g = 0.95f32, b = 1.0f32 }, 51);
        let label = TextDraw.centeredAt({
            text = d#label, atlas = ctx#atlas, size = 11.0, color = labelColor(), z = 52,
            center = { x = Sliders.labelX() + 40.0, y = ry } });
        let valText = TextDraw.centeredAt({
            text = fmt(v), atlas = ctx#atlas, size = 11.0, color = labelColor(), z = 52,
            center = { x = Sliders.valX(), y = ry } });
        track :: handle :: label :: valText :: Nil

    /// スライダーの数値表示（3 桁に丸めて見やすく）。
    def fmt(v: Float64): String =
        Float64.toString(Float64.floor(v * 1000.0 + 0.5) / 1000.0)
}
