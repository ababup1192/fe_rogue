// View — World から絵を作る。背景に薄い格子（覆いが乗ったか一目で分かる目印）を敷き、
// design 領域の縁取りと四隅マーカーで「画面の端がどこか」を目視できるようにし、
// その上にラベル UI（ui.json）と Transition.itemsAt が返す覆いを重ねる。
// 格子・縁取り・覆いは UI ではない純粋な絵なので Render 直書き、ラベルの見た目は ui.json が持つ。

mod View {

    def bgColor(): Color = { r = 0.18f32, g = 0.19f32, b = 0.24f32 }
    def gridColor(): Color = { r = 0.30f32, g = 0.32f32, b = 0.38f32 }
    def coverColor(): Color = { r = 0.0f32, g = 0.0f32, b = 0.0f32 }
    /// 縁取り・十字の色（design の四辺そのものを示す線）。
    def edgeColor(): Color = { r = 0.2f32, g = 0.9f32, b = 0.95f32 }
    /// 四隅 L 字マーカーの色（縁取りと見分けるため別色）。
    def cornerColor(): Color = { r = 0.95f32, g = 0.85f32, b = 0.2f32 }

    /// design 解像度（project.json の designWidth/Height と合わせる）。
    pub def design(): Vec2.Vec2 = { x = 320.0, y = 240.0 }

    /// 縦横 40px 格子の線（背景だけでは覆いの有無が分かりづらいための目印）。
    def gridItems(): List[Render.PlacedItem] =
        let cell = 40.0;
        let cols = List.range(0, 8);
        let rows = List.range(0, 6);
        let verticals = cols |> List.map(i -> {
            let x = Int32.toFloat64(i) * cell;
            { at = { x = x, y = 0.0 }, item = Render.box({ x = 1.0, y = design()#y }, gridColor(), 1) }
        });
        let horizontals = rows |> List.map(i -> {
            let y = Int32.toFloat64(i) * cell;
            { at = { x = 0.0, y = y }, item = Render.box({ x = design()#x, y = 1.0 }, gridColor(), 1) }
        });
        List.append(verticals, horizontals)

    /// design 領域の四辺いっぱいに引く縁取りの太さ（フルスクリーン時に外側の黒帯と見分けやすい太さ）。
    def edgeThickness(): Float64 = 4.0

    /// 四隅 L 字マーカーの一辺の長さ。
    def cornerLen(): Float64 = 20.0

    /// 十字マーカーの半径（中心からの腕の長さ）。
    def crossLen(): Float64 = 12.0

    /// design 四辺いっぱいの縁取り 4 本（上下左右）。フルスクリーン時、この外側が
    /// 黒帯（レターボックス）として見えれば viewport が design 通りに収まっている証拠になる。
    def edgeItems(): List[Render.PlacedItem] =
        let w = design()#x;
        let h = design()#y;
        let t = edgeThickness();
        { at = { x = 0.0, y = 0.0 },     item = Render.box({ x = w, y = t }, edgeColor(), 20) } ::
        { at = { x = 0.0, y = h - t },   item = Render.box({ x = w, y = t }, edgeColor(), 20) } ::
        { at = { x = 0.0, y = 0.0 },     item = Render.box({ x = t, y = h }, edgeColor(), 20) } ::
        { at = { x = w - t, y = 0.0 },   item = Render.box({ x = t, y = h }, edgeColor(), 20) } ::
        Nil

    /// 四隅 1 つぶんの L 字（横棒 + 縦棒）。sign で内向きの方向を決める
    /// （左上=(+1,+1)・右上=(-1,+1)・左下=(+1,-1)・右下=(-1,-1)）。
    def cornerMarker(corner: Vec2.Vec2, sign: Vec2.Vec2): List[Render.PlacedItem] =
        let len = cornerLen();
        let t = edgeThickness();
        let horiz = { x = if (sign#x > 0.0) corner#x else corner#x - len, y = corner#y };
        let vert  = { x = corner#x, y = if (sign#y > 0.0) corner#y else corner#y - len };
        { at = horiz, item = Render.box({ x = len, y = t }, cornerColor(), 21) } ::
        { at = vert,  item = Render.box({ x = t, y = len }, cornerColor(), 21) } ::
        Nil

    /// 四隅の L 字マーカー（スケーリングの歪み・欠けが起きると真っ先にズレて見える位置）。
    def cornerItems(): List[Render.PlacedItem] =
        let w = design()#x;
        let h = design()#y;
        let corners = ({ x = 0.0, y = 0.0 }, { x = 1.0, y = 1.0 }) ::
                      ({ x = w, y = 0.0 },   { x = -1.0, y = 1.0 }) ::
                      ({ x = 0.0, y = h },   { x = 1.0, y = -1.0 }) ::
                      ({ x = w, y = h },     { x = -1.0, y = -1.0 }) :: Nil;
        corners |> List.flatMap(pair -> { let (corner, sign) = pair; cornerMarker(corner, sign) })

    /// 画面中央の小さな十字（design の中心そのものが分かる目印）。
    def crossItems(): List[Render.PlacedItem] =
        let center = { x = design()#x / 2.0, y = design()#y / 2.0 };
        let len = crossLen();
        Render.lineSeg({ x = center#x - len, y = center#y }, { x = center#x + len, y = center#y },
                        2.0, cornerColor(), 21) ::
        Render.lineSeg({ x = center#x, y = center#y - len }, { x = center#x, y = center#y + len },
                        2.0, cornerColor(), 21) :: Nil

    /// フルスクリーン起動確認用の目印一式（縁取り + 四隅 L 字 + 中央十字）。
    /// 縁取りの外側に黒帯が見えれば viewport 正常、四隅マーカーが直角のまま欠けなければ
    /// スケーリングも歪んでいない。
    def viewportMarkerItems(): List[Render.PlacedItem] =
        List.flatten(edgeItems() :: cornerItems() :: crossItems() :: Nil)

    // ── blend デモ（RGB 3 円。Z/X/C で重ね方を切り替える）──

    def blendDemoCenter(): Vec2.Vec2 = { x = 160.0, y = 130.0 }
    def demoRed(): Color = { r = 1.0f32, g = 0.0f32, b = 0.0f32 }
    def demoGreen(): Color = { r = 0.0f32, g = 1.0f32, b = 0.0f32 }
    def demoBlue(): Color = { r = 0.0f32, g = 0.0f32, b = 1.0f32 }
    /// 白い下敷きの色。Add は暗い地で光り Multiply は明るい地で沈むので、
    /// 円を白地（左）と暗地（右）の境界にまたがせて 1 画面で両方の差が見えるようにする。
    def demoPanelColor(): Color = { r = 0.95f32, g = 0.95f32, b = 0.95f32 }

    /// RGB 3 円を三角配置で重ねた絵。Add は重なりが白へ光り（R+G=黄・3 色=白）、
    /// Multiply は重なりが黒へ沈み、Normal は後から描いた円が上を覆う。
    pub def blendDemoItems(blend: DrawCmd.BlendMode): List[Render.PlacedItem] =
        let center = blendDemoCenter();
        let radius = 26.0;
        let spread = 15.0;
        let panel = { at = { x = center#x - 75.0, y = center#y - 50.0 },
                      item = Render.box({ x = 75.0, y = 100.0 }, demoPanelColor(), 30) };
        let coloredCircle = (offset: Vec2.Vec2, color: Color) ->
            Render.circleAt(Vec2.add(center, offset), radius, color, 31)
                |> (placed -> { item = Render.blended(blend, placed#item) | placed });
        panel
            :: coloredCircle({ x = 0.0, y = -1.0 * spread }, demoRed())
            :: coloredCircle({ x = -1.0 * spread, y = spread * 0.8 }, demoGreen())
            :: coloredCircle({ x = spread, y = spread * 0.8 }, demoBlue())
            :: Nil

    // ── カンテラ探索デモ（暗い部屋+目印図形+単一光源。矢印キーで移動・LeftShift で暗闇 on/off）──

    /// 目印図形の zIndex。カンテラの穴あき暗幕（lanternZ）より必ず小さくする
    /// （Render.blended は自分より奥＝小さい zIndex にしか効かないため、逆にすると
    /// 穴を開けても景色が見えない事故になる）。
    def landmarkZ(): Int32 = 25

    /// カンテラ本体（暗幕→ハロ）の zIndex 土台。
    def lanternZ(): Int32 = 40

    def landmarkColors(): List[Color] =
        { r = 0.85f32, g = 0.3f32, b = 0.3f32 } ::
        { r = 0.3f32, g = 0.7f32, b = 0.85f32 } ::
        { r = 0.9f32, g = 0.8f32, b = 0.2f32 } ::
        { r = 0.4f32, g = 0.85f32, b = 0.4f32 } ::
        { r = 0.75f32, g = 0.4f32, b = 0.9f32 } ::
        { r = 0.9f32, g = 0.55f32, b = 0.2f32 } :: Nil

    def landmarkPositions(): List[Vec2.Vec2] =
        { x = 40.0, y = 40.0 } :: { x = 280.0, y = 40.0 } :: { x = 40.0, y = 200.0 } ::
        { x = 280.0, y = 200.0 } :: { x = 160.0, y = 40.0 } :: { x = 160.0, y = 200.0 } :: Nil

    /// 暗い部屋の目印 6 個（box と circle を交互に、色違いで並べる。カンテラの穴あきで
    /// 覗いたときにちゃんと景色として見分けが付くよう、はっきりした色を選んである）。
    def landmarkItems(): List[Render.PlacedItem] =
        List.zip(landmarkPositions(), landmarkColors())
            |> List.zipWithIndex
            |> List.map(pair -> {
                let (i, (pos, color)) = pair;
                if (Int32.modulo(i, 2) == 0) Render.boxAt(pos, { x = 24.0, y = 24.0 }, color, landmarkZ())
                else Render.circleAt(pos, 14.0, color, landmarkZ())
            })

    /// 暗い部屋の下敷き（通常表示より一段暗い色。暗闇 off でもここが「夜の部屋」と分かる）。
    def darkRoomColor(): Color = { r = 0.05f32, g = 0.05f32, b = 0.08f32 }

    /// カンテラの穴半径（design 320×240 の 30% ＝ 穴直径 96px。ホラー成立の要 —
    /// 光の周りだけ見えて最遠隅は完全に黒へ沈む大きさ）。
    def lanternRadius(): Float64 = 48.0

    /// 暗幕の濃さ（0.95＝穴の外はほぼ完全な黒。Light.SingleLightConfig#darkness と
    /// Light.MultiLightConfig#darkness の両方に渡す共通値）。
    def lanternDarkness(): Float64 = 0.95

    /// ハロの強さ（Add alpha。0.30〜0.40 のホラー成立レンジの中央）。
    def lanternHaloAlpha(): Float64 = 0.35

    /// ハロの見た目直径を穴の直径（2×radius）よりひとまわり大きい 2.5×radius にする倍率
    /// （singleLightItems が返す末尾のハロ item だけへ後掛けする — Light.haloScale 自体は
    /// 「直径=2×radius」固定のため、ここでの追加拡大が実寸を 2.5×radius へ引き上げる）。
    def lanternHaloDiameterFactor(): Float64 = 1.25

    /// カンテラの光。暖色（松明の色味）。radius は lanternRadius（穴半径）と揃える。
    def lanternLight(at: Vec2.Vec2): Light.Light =
        { at = at, radius = lanternRadius(), color = { r = 1.0f32, g = 0.75f32, b = 0.4f32 },
          halo = lanternHaloAlpha() }

    // ── 壁と影（Shadow モジュールの手本。LeftCtrl で walls をトグル）──

    /// 壁の色（目印のはっきりした色と紛れない石壁っぽい灰色）。
    def wallColor(): Color = { r = 0.48f32, g = 0.47f32, b = 0.44f32 }

    /// 壁の zIndex。目印（landmarkZ=25）より手前・暗幕（lanternZ=40）より奥に置く
    /// （暗幕より手前だと暗闇でも壁が煌々と見えてしまう）。
    def wallZ(): Int32 = 26

    /// L字の壁 2 枚（中心と大きさ）。見た目の box と遮蔽ポリゴンの両方をここから導く
    /// （二重定義にすると片方だけ動かして影が壁からずれる）。
    /// 画面端に寄せると影の落ち先が「元々暗幕で真っ黒な領域」になり効果が写らないため、
    /// 壁も影の落ち先も光の届く範囲（穴 48px+落ち際）に収まる中央寄りに置く。
    def wallBoxes(): List[(Vec2.Vec2, Vec2.Vec2)] =
        ({ x = 200.0, y = 120.0 }, { x = 12.0, y = 70.0 }) ::
        ({ x = 181.0, y = 161.0 }, { x = 50.0, y = 12.0 }) :: Nil

    /// 柱（円の遮蔽の手本）。中心と半径も見た目・遮蔽の共通ソース。
    def wallPillarCenter(): Vec2.Vec2 = { x = 110.0, y = 90.0 }
    def wallPillarRadius(): Float64 = 10.0

    /// 影デモの証明用の目印（壁のすぐ裏の白丸）。壁の反対側から照らすと影に沈み、
    /// 光が回り込むと照らされる — 距離の減衰では説明できない「影による見え隠れ」の証拠。
    pub def shadowMarkerCenter(): Vec2.Vec2 = { x = 238.0, y = 120.0 }

    def shadowMarkerItem(): Render.PlacedItem =
        Render.circleAt(shadowMarkerCenter(), 6.0, { r = 1.0f32, g = 1.0f32, b = 1.0f32 }, landmarkZ())

    /// 壁の見た目（box 2 枚 + 柱 1 本）。
    def wallItems(): List[Render.PlacedItem] =
        let boxes = wallBoxes() |> List.map(pair -> {
            let (center, size) = pair;
            Render.boxAt(center, size, wallColor(), wallZ())
        });
        List.append(boxes,
            Render.circleAt(wallPillarCenter(), wallPillarRadius(), wallColor(), wallZ()) :: Nil)

    /// 壁の遮蔽ポリゴン（見た目と同じ中心・大きさから導く）。
    def wallOccluders(): List[List[Vec2.Vec2]] =
        let boxes = wallBoxes() |> List.map(pair -> {
            let (center, size) = pair;
            Shadow.occluderOfBox(center, size)
        });
        List.append(boxes,
            Shadow.occluderOfCircle(wallPillarCenter(), wallPillarRadius(), 12) :: Nil)

    /// RadialGlow で焼くテクスチャの元 px サイズ。bake/Gallery.flix の実ファイル生成と
    /// ここのスケール計算が同じ値を見る必要があるため公開する。
    pub def maskSourceSize(): Float64 = 512.0
    pub def haloSourceSize(): Float64 = 256.0

    /// maskTexture の平坦な穴の広さ（RadialGlow.defaultHoleFrac と同じ値）。
    /// bake/Gallery.flix のテクスチャ焼き込みと Light.singleLightItems のスケール計算の
    /// 両方がこの値を見るため、ここに 1 箇所だけ持つ。
    pub def maskHoleFrac(): Float64 = RadialGlow.defaultHoleFrac()

    /// mode に応じて「暗闇の見せ方」を切り替える。Bright は何も足さず素の明るさのまま、
    /// Dark は Light.multiLightItems を lights=Nil で呼ぶ全面暗幕のみ（API ドッグフーディング —
    /// 光源が無いときの見た目を単体光源と同じ関数群で表す）、DarkWithLight は
    /// singleLightItems の穴あき暗幕+ハロにハロだけ追加拡大を後掛けする。
    def lanternDarknessItems(lantern: World.Lantern): List[Render.PlacedItem] =
        match lantern#mode {
            case World.LanternMode.Bright => List.empty()
            case World.LanternMode.Dark =>
                Light.multiLightItems({
                    lights = Nil, darkness = lanternDarkness(), viewport = design(),
                    haloSprite = "glow_halo", haloSourceSize = haloSourceSize(), z = lanternZ() })
            case World.LanternMode.DarkWithLight =>
                let lightItems = Light.singleLightItems({
                    light = lanternLight(lantern#at), viewport = design(),
                    maskSprite = "glow_mask", maskSourceSize = maskSourceSize(), maskHoleFrac = maskHoleFrac(),
                    haloSprite = "glow_halo", haloSourceSize = haloSourceSize(), darkness = lanternDarkness(),
                    z = lanternZ() })
                |> growLastHalo;
                // 影は暗幕と同じ z（同 z 内は list の並び順で描かれるので、暗幕の後ろに
                // 置けば穴で見えた領域を影の形だけ再度沈められる。z+1 のハロは影より手前に残る）。
                let shadows = if (lantern#walls)
                        Shadow.itemsFor(lanternLight(lantern#at), wallOccluders(),
                            { darkness = lanternDarkness(), z = lanternZ(),
                              extrudeLength = Shadow.infiniteExtrude() })
                    else List.empty();
                List.append(lightItems, shadows)
        }

    /// singleLightItems が返す列の末尾（ハロ）だけを lanternHaloDiameterFactor 倍する
    /// （先頭の暗幕・周囲黒帯はそのまま）。
    def growLastHalo(items: List[Render.PlacedItem]): List[Render.PlacedItem] =
        match List.reverse(items) {
            case Nil          => Nil
            case halo :: rest =>
                let grown = { item = Render.scaled(lanternHaloDiameterFactor(), halo#item) | halo };
                List.reverse(grown :: rest)
        }

    /// 部屋の下敷き → 目印図形 → 暗闇モードに応じた覆い、の順。
    /// 下敷きは bg と同じ z=0（格子線 z=1 より奥）に置き、格子が常に見える上に重なるようにする。
    /// None（未出現）のときは何も描かない（他デモの bake に映り込ませないため）。
    pub def lanternDemoItems(lantern: Option[World.Lantern]): List[Render.PlacedItem] =
        lantern
            |> Option.map(l -> {
                let room = { at = Vec2.zero(), item = Render.box(design(), darkRoomColor(), 0) };
                // 白丸は影の証明用の目印なので walls と独立に常置する — walls=false の対照カットで
                // 「同じ目印が沈まず見える」を成立させるため（壁と一緒に消すと対照の意味が無くなる）。
                let walls = if (l#walls) wallItems() else List.empty();
                room :: List.flatten(landmarkItems() :: (shadowMarkerItem() :: walls) :: lanternDarknessItems(l) :: Nil)
            })
            |> Option.getWithDefault(List.empty())

    /// 背景の格子 → viewport 目印 → blend デモ → カンテラ探索 → ラベル UI（ui.json）→
    /// 覆い（Transition）の順に重ねる。覆いは再生中だけ描く（Idle でも描き続けると
    /// FadeOut 後の黒が残り、画面が消えたように見える）。
    pub def frame(ctx: App.ViewCtx, world: World.World): List[Render.PlacedItem] =
        let bg = { at = Vec2.zero(), item = Render.box(design(), bgColor(), 0) };
        let ui = UiRender.itemsWith(_ -> ctx#atlas, _ -> None, world#ui, design());
        let cover = world#playing
            |> Option.map(progress -> Transition.itemsAt({
                   kind = world#kind, t = Transition.tOf(progress),
                   viewport = design(), color = coverColor(), z = Transition.defaultZ() }))
            |> Option.getWithDefault(List.empty());
        let blendDemo = world#blend
            |> Option.map(blendDemoItems)
            |> Option.getWithDefault(List.empty());
        bg :: List.flatten(gridItems() :: viewportMarkerItems() :: blendDemo ::
                            lanternDemoItems(world#lantern) :: ui :: cover :: Nil)
}
