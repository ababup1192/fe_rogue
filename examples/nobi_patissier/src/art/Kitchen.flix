// Kitchen — キッチン背景と持ち場（ボール・型抜き・オーブン）の候補描画。
// 320×240 の design 座標に直接描く。持ち場3つは三角形の頂点に等間隔で置く:
//   正三角形 = オーブンを上中央（壁ぎわ）、カウンター2つを左下・右下
//   逆三角形 = カウンター2つを上（壁ぎわ）、オーブンを下中央（手前）
// 色調は Palette.KitchenTone で差し替える（クリーム/ミント/木目の3案）。
mod Kitchen {

    /// レイアウト案。
    pub enum Layout with Eq {
        /// オーブンが上中央・カウンターが左下/右下。
        case TriangleUp
        /// カウンターが上・オーブンが下中央。
        case TriangleDown
    }

    /// 持ち場の種類（ゲーム本体でもこの enum を使う予定）。
    pub enum Station with Eq {
        case Bowl
        case Cutter
        case Oven
    }

    /// 持ち場の見た目バリエーション（各2案の比較用）。
    pub enum PropSet with Eq {
        /// 案1: ボール=生地入り金属ボール / 型抜き=生地シート+抜き型 / オーブン=窓に火。
        case Classic
        /// 案2: ボール=たまご添えガラスボール / 型抜き=抜いたクッキーが並ぶ板 / オーブン=焼き上がりの光。
        case Cozy
    }

    /// 持ち場の立ち位置（のびが立つ床座標。三角形の頂点の少し手前）。
    pub def stationSpot(layout: Layout, station: Station): Vec2.Vec2 =
        match (layout, station) {
            case (Layout.TriangleUp, Station.Oven)     => { x = 160.0, y = 118.0 }
            case (Layout.TriangleUp, Station.Bowl)     => { x = 80.0, y = 196.0 }
            case (Layout.TriangleUp, Station.Cutter)   => { x = 240.0, y = 196.0 }
            case (Layout.TriangleDown, Station.Bowl)   => { x = 80.0, y = 130.0 }
            case (Layout.TriangleDown, Station.Cutter) => { x = 240.0, y = 130.0 }
            case (Layout.TriangleDown, Station.Oven)   => { x = 160.0, y = 210.0 }
        }

    /// 背景 + 持ち場一式（320×240 まるごと）。
    pub def scene(tone: Palette.KitchenTone, layout: Layout, props: PropSet,
                  atlas: FontAtlas): List[Render.PlacedItem] =
        List.flatten(
            wall(tone) ::
            floor(tone) ::
            furniture(tone, layout, props, atlas) :: Nil)

    // ── 壁と床 ──

    def wallH(): Float64 = 56.0

    def wall(tone: Palette.KitchenTone): List[Render.PlacedItem] =
        let base = at(0.0, 0.0, Render.box({x = 320.0, y = wallH()}, tone#wall, 0));
        // タイルの目地（縦線 + 中段の横線）と巾木。
        let verticals = List.range(0, 20) |> List.map(i ->
            at(Int32.toFloat64(i) * 16.0, 0.0,
               Render.box({x = 1.0, y = wallH() - 4.0}, tone#wallLine, 1)));
        let horizontal = at(0.0, 26.0, Render.box({x = 320.0, y = 1.0}, tone#wallLine, 1));
        let skirting = at(0.0, wallH() - 4.0, Render.box({x = 320.0, y = 4.0}, tone#trim, 2));
        // 窓（そら色 + 桟）。
        let window =
            at(22.0, 8.0, Render.box({x = 52.0, y = 36.0}, tone#trim, 2)) ::
            at(25.0, 11.0, Render.box({x = 46.0, y = 30.0}, skyColor(), 3)) ::
            at(47.0, 11.0, Render.box({x = 2.0, y = 30.0}, tone#trim, 4)) ::
            at(25.0, 25.0, Render.box({x = 46.0, y = 2.0}, tone#trim, 4)) :: Nil;
        // 右の棚（板 + ジャム瓶 2 つ）。
        let shelf =
            at(248.0, 16.0, Render.box({x = 52.0, y = 4.0}, tone#trim, 2)) ::
            at(256.0, 6.0, Render.box({x = 8.0, y = 10.0}, Palette.heart(), 3) |> Render.rounded(2.0)) ::
            at(272.0, 4.0, Render.box({x = 8.0, y = 12.0}, Palette.star(), 3) |> Render.rounded(2.0)) :: Nil;
        List.flatten((base :: horizontal :: skirting :: Nil) :: verticals :: window :: shelf :: Nil)

    def skyColor(): Color = {r = 0.372549f32, g = 0.803922f32, b = 0.894118f32} // #5fcde4

    def floor(tone: Palette.KitchenTone): List[Render.PlacedItem] =
        let tile = 20.0;
        List.range(0, 16) |> List.flatMap(ix ->
            List.range(0, 10) |> List.map(iy -> {
                let x = Int32.toFloat64(ix) * tile;
                let y = wallH() + Int32.toFloat64(iy) * tile;
                let color = if (Int32.modulo(ix + iy, 2) == 0) tone#floorA else tone#floorB;
                at(x, y, Render.box({x = tile, y = tile}, color, 0))
            }))

    // ── 持ち場の家具 ──

    def furniture(tone: Palette.KitchenTone, layout: Layout, props: PropSet,
                  atlas: FontAtlas): List[Render.PlacedItem] =
        match layout {
            case Layout.TriangleUp =>
                List.flatten(
                    oven(136.0, 18.0, props, atlas) ::
                    counter(tone, 46.0, 148.0, props, Station.Bowl, atlas) ::
                    counter(tone, 206.0, 148.0, props, Station.Cutter, atlas) :: Nil)
            case Layout.TriangleDown =>
                List.flatten(
                    counter(tone, 46.0, 78.0, props, Station.Bowl, atlas) ::
                    counter(tone, 206.0, 78.0, props, Station.Cutter, atlas) ::
                    oven(136.0, 150.0, props, atlas) :: Nil)
        }

    /// カウンター（幅 68）: 天板 + 前面 + 脚元の影。上に持ち場の小物が載る。
    pub def counter(tone: Palette.KitchenTone, x: Float64, y: Float64,
                props: PropSet, station: Station, atlas: FontAtlas): List[Render.PlacedItem] =
        let w = 68.0;
        let body =
            at(x, y + 8.0, Render.box({x = w, y = 26.0}, tone#counter, 4) |> Render.rounded(3.0)) ::
            at(x, y, Render.box({x = w, y = 10.0}, tone#counterTop, 5) |> Render.rounded(3.0)) ::
            at(x + 2.0, y + 34.0, Render.box({x = w - 4.0, y = 3.0}, tone#trim, 3)) :: Nil;
        let stuff = match station {
            case Station.Bowl   => bowlProp(atlas, x, y + 2.0, props)
            case Station.Cutter => cutterProp(tone, atlas, x, y + 2.0, props)
            case Station.Oven   => Nil
        };
        List.append(body, stuff)

    /// ボールの小物: ボール（生地入り・湯気つき）+ この持ち場の正解の品物
    /// （小麦粉・たまご・牛乳）を並べて、何を渡す場所か一目でわかるようにする。
    /// Classic = 金属ボール、Cozy = ガラスボール。
    def bowlProp(atlas: FontAtlas, x: Float64, topY: Float64, props: PropSet): List[Render.PlacedItem] =
        let cx = x + 38.0;
        let rimY = topY - 11.0;
        let bowlColor = match props { case PropSet.Classic => Palette.metal()  case PropSet.Cozy => Palette.sugar() };
        let rimColor = match props { case PropSet.Classic => Palette.metalDark() case PropSet.Cozy => Palette.paper() };
        let bowl = Bezier.convexFill(halfDisc(cx, rimY, 12.0, true), bowlColor, 6);
        let mound = Bezier.convexFill(halfDisc(cx, rimY, 8.8, false)
            |> List.map(p -> ({x = p#x, y = rimY - (rimY - p#y) * 0.55}: Vec2.Vec2)), Palette.dough(), 7);
        let rim = Bezier.polyline({x = cx - 12.0, y = rimY} :: {x = cx + 12.0, y = rimY} :: Nil,
            width = 2.2, rimColor, 8);
        List.flatten(
            bowl :: mound :: rim :: steam(cx, rimY - 8.0) ::
            (Items.icon(Items.Kind.Flour, {x = x + 10.0, y = topY - 7.0}, 14.0, atlas)
                |> List.map(raiseZ(6))) ::
            (Items.icon(Items.Kind.Milk, {x = x + 61.0, y = topY - 8.0}, 13.0, atlas)
                |> List.map(raiseZ(6))) ::
            (Items.icon(Items.Kind.Egg, {x = x + 52.0, y = topY - 2.0}, 8.0, atlas)
                |> List.map(raiseZ(7))) :: Nil)

    /// z を持ち上げる（品物アイコンをカウンター天板より手前に出す）。
    def raiseZ(delta: Int32, placed: Render.PlacedItem): Render.PlacedItem =
        { item = Render.raiseZ(delta, placed#item) | placed }

    /// 下向き（up=true）または上向きの半円の輪郭。
    def halfDisc(cx: Float64, cy: Float64, r: Float64, downward: Bool): List[Vec2.Vec2] =
        List.range(0, 13) |> List.map(i -> {
            let a = 3.14159265 * Int32.toFloat64(i) / 12.0;
            let dy = r * RenderUtil.sinF(a);
            { x = cx - r * RenderUtil.cosF(a), y = if (downward) cy + dy else cy - dy }
        })

    /// ふわりと立ちのぼる湯気 2 本（細いベジエ帯）。
    def steam(cx: Float64, topY: Float64): List[Render.PlacedItem] =
        List.append(
            Bezier.stroke({ spine = Bezier.quadratic(
                {x = cx - 4.0, y = topY}, {x = cx - 8.0, y = topY - 7.0},
                {x = cx - 3.0, y = topY - 13.0}, 8), color = Palette.paper(), z = 9 },
                t -> 1.6 - 0.8 * t),
            Bezier.stroke({ spine = Bezier.quadratic(
                {x = cx + 3.0, y = topY - 2.0}, {x = cx + 7.0, y = topY - 9.0},
                {x = cx + 2.0, y = topY - 15.0}, 8), color = Palette.paper(), z = 9 },
                t -> 1.4 - 0.7 * t))

    /// 型抜き台: 生地シート（抜いた星型の穴あき）+ 抜かれた生地のクッキー + 正解の品物
    /// （星・ハートの抜き型）。Classic = シート広め、Cozy = 抜き済み多め。
    def cutterProp(tone: Palette.KitchenTone, atlas: FontAtlas, x: Float64, topY: Float64,
                   props: PropSet): List[Render.PlacedItem] =
        let cx = x + 30.0;
        let sheet =
            at(cx - 15.0, topY - 7.0, Render.box({x = 30.0, y = 9.0}, Palette.paper(), 6)
                |> Render.rounded(2.0) |> Render.outline(Palette.cookie(), 1.2)) :: Nil;
        // 抜いた跡の穴（天板と同じ色で塗る = 穴に見える）。
        let holes = List.append(
            Bezier.fill(Bezier.star({x = cx - 7.0, y = topY - 2.5}, rOut = 3.4, rIn = 1.5),
                tone#counterTop, 7),
            Bezier.fill(Bezier.star({x = cx + 3.0, y = topY - 4.5}, rOut = 3.4, rIn = 1.5),
                tone#counterTop, 7));
        // 抜かれた生地のクッキー（白い生地の星）を並べる。
        let cutouts = List.append(
            Bezier.fill(Bezier.star({x = cx + 19.0, y = topY - 4.0}, rOut = 4.2, rIn = 1.8),
                Palette.paper(), 7),
            Bezier.fill(Bezier.star({x = cx + 25.0, y = topY + 0.5}, rOut = 3.4, rIn = 1.5),
                Palette.paper(), 7));
        let extra = match props {
            case PropSet.Classic => Nil
            case PropSet.Cozy =>
                Bezier.fill(Bezier.star({x = cx + 13.0, y = topY + 1.0}, rOut = 3.2, rIn = 1.4),
                    Palette.paper(), 7)
        };
        List.flatten(
            sheet :: holes :: cutouts :: extra ::
            (Items.icon(Items.Kind.StarCutter, {x = x + 8.0, y = topY - 10.0}, 13.0, atlas)
                |> List.map(raiseZ(7))) ::
            (Items.icon(Items.Kind.HeartCutter, {x = x + 62.0, y = topY - 9.0}, 12.0, atlas)
                |> List.map(raiseZ(7))) :: Nil)

    /// オーブン（幅 48）: 本体 + 扉窓（火/光）+ 取っ手 + 脚 + 脇に正解の品物（天板・ミトン）。
    pub def oven(x: Float64, y: Float64, props: PropSet, atlas: FontAtlas): List[Render.PlacedItem] =
        let w = 48.0;
        let h = 46.0;
        let glow = match props {
            case PropSet.Classic =>
                at(x + 12.0, y + 26.0, Render.box({x = 10.0, y = 8.0}, Palette.fire(), 8)
                    |> Render.rounded(3.0)) ::
                at(x + 24.0, y + 28.0, Render.box({x = 8.0, y = 6.0}, Palette.fireHot(), 8)
                    |> Render.rounded(3.0)) :: Nil
            case PropSet.Cozy =>
                at(x + 10.0, y + 22.0, Render.box({x = 28.0, y = 14.0}, Palette.fireHot(), 8)
                    |> Render.rounded(4.0) |> Render.fade(0.55f32)) ::
                at(x + 15.0, y + 30.0, Render.box({x = 8.0, y = 5.0}, Palette.cookie(), 9)
                    |> Render.rounded(2.5)) ::
                at(x + 26.0, y + 30.0, Render.box({x = 8.0, y = 5.0}, Palette.cookie(), 9)
                    |> Render.rounded(2.5)) :: Nil
        };
        let sideItems = List.append(
            (Items.icon(Items.Kind.Tray, {x = x - 12.0, y = y + h - 6.0}, 16.0, atlas)
                |> List.map(raiseZ(6))),
            (Items.icon(Items.Kind.Mitten, {x = x + w + 12.0, y = y + h - 8.0}, 14.0, atlas)
                |> List.map(raiseZ(6))));
        List.append(sideItems,
        List.append(
            at(x, y, Render.box({x = w, y = h}, Palette.ovenBody(), 5) |> Render.rounded(4.0)) ::
            at(x + 4.0, y + 4.0, Render.box({x = w - 8.0, y = 6.0}, Palette.ovenDark(), 6)
                |> Render.rounded(2.0)) ::
            at(x + 6.0, y + 18.0, Render.box({x = w - 12.0, y = 22.0}, Palette.ovenDark(), 6)
                |> Render.rounded(3.0)) ::
            at(x + 8.0, y + 20.0, Render.box({x = w - 16.0, y = 18.0}, Palette.ovenWindow(), 7)
                |> Render.rounded(2.0)) ::
            at(x + 4.0, y + 13.0, Render.box({x = w - 8.0, y = 2.5}, Palette.metal(), 6)) ::
            at(x + 4.0, y + h, Render.box({x = 5.0, y = 4.0}, Palette.ovenDark(), 5)) ::
            at(x + w - 9.0, y + h, Render.box({x = 5.0, y = 4.0}, Palette.ovenDark(), 5)) :: Nil,
            glow))

    def at(x: Float64, y: Float64, item: Render.Item): Render.PlacedItem =
        { at = {x = x, y = y}, item = item }
}
