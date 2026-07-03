/// UiLayout.computeLayout の 2 パス flex を具体値で固定する。
/// 期待矩形は (posX, posY, sizeX, sizeY) の 4-tuple に落として比較する
/// （record Eq に依存せず、パターンマッチも避ける）。
mod TestUiLayout {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 既定スタイル（Column・pad0・gap0・Auto×Auto・Start/Start）。
    def base(): UiLayout.Style = UiLayout.defaultStyle()

    /// 全 entity 可視（visible 未登録＝可視扱いなので空 Map でよい）。
    def allVisible(): Map[EntityId, Bool] = Map.empty()

    /// 矩形を (posX, posY, sizeX, sizeY) に落とす。
    def rectTuple(rect: Rect2.Rect2): (Float64, Float64, Float64, Float64) =
        (rect#position#x, rect#position#y, rect#size#x, rect#size#y)

    /// 解決結果から entity の矩形 tuple を引く。未確定は None。
    def lookup(id: EntityId, result: Map[EntityId, Rect2.Rect2]): Option[(Float64, Float64, Float64, Float64)] =
        Map.get(id, result) |> Option.map(rectTuple)

    // ════════════════════════════════════════════════════════
    // Column + Px + gap
    // ════════════════════════════════════════════════════════

    /// root(1) Column gap=2。子 c1(2)=Px 10x4・c2(3)=Px 10x6 を縦に積む。
    ///   (0,0) +--------+ c1 10x4
    ///         +--------+
    ///          gap 2
    ///   (0,6) +--------+ c2 10x6
    ///         +--------+
    @Test
    def testColumnTwoChildrenPxWithGap(): Unit \ Assert =
        let rootStyle = {dir = UiLayout.Dir.Column, gap = 2.0 | base()};
        let c1 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(4.0) | base()};
        let c2 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(6.0) | base()};
        let styles = Map#{1 => rootStyle, 2 => c1, 3 => c2};
        let parents = Map#{2 => 1, 3 => 1};
        let order = Map#{2 => 0, 3 => 1};
        let measures = (Map.empty(): Map[EntityId, Vec2.Vec2]);
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 20.0, y = 20.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = allVisible()}, 1, rootRect);
        Assert.assertEq(
            expected = (Some((0.0, 0.0, 10.0, 4.0)), Some((0.0, 6.0, 10.0, 6.0))),
            (lookup(2, result), lookup(3, result)))

    // ════════════════════════════════════════════════════════
    // Auto ヒュッグ（テキスト実寸 + pad）
    // ════════════════════════════════════════════════════════

    /// panel(2) Auto×Auto・pad L/R=3・T/B=2・gap=1。中に text a(3)=10x4・b(4)=14x4。
    ///   panel 幅   = max(10,14) + pad(3+3) = 20
    ///   panel 高さ = 4 + gap1 + 4 + pad(2+2) = 13
    ///   text b は pad+a+gap で content 原点(3,2) から (3,7)、実寸 14x4
    @Test
    def testAutoHugPanelSizeFromText(): Unit \ Assert =
        let rootStyle = base();
        let panel = {dir = UiLayout.Dir.Column, gap = 1.0,
                     padLeft = 3.0, padRight = 3.0, padTop = 2.0, padBottom = 2.0 | base()};
        let leaf = base();
        let styles = Map#{1 => rootStyle, 2 => panel, 3 => leaf, 4 => leaf};
        let parents = Map#{2 => 1, 3 => 2, 4 => 2};
        let order = Map#{2 => 0, 3 => 0, 4 => 1};
        let measures = Map#{3 => {x = 10.0, y = 4.0}, 4 => {x = 14.0, y = 4.0}};
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 100.0, y = 100.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = allVisible()}, 1, rootRect);
        Assert.assertEq(
            expected = (Some((0.0, 0.0, 20.0, 13.0)), Some((3.0, 7.0, 14.0, 4.0))),
            (lookup(2, result), lookup(4, result)))

    // ════════════════════════════════════════════════════════
    // Grow 余り配分
    // ════════════════════════════════════════════════════════

    /// root(1) Column 高さ30。c1(2)=Px 高6、c2(3)=Grow(1)、c3(4)=Grow(2)。
    ///   余り = 30 - 6 = 24 を 1:2 で配る → c2=8, c3=16。y は 6, 14。
    @Test
    def testGrowDistributesLeftover(): Unit \ Assert =
        let rootStyle = {dir = UiLayout.Dir.Column | base()};
        let c1 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(6.0) | base()};
        let c2 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Grow(1.0) | base()};
        let c3 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Grow(2.0) | base()};
        let styles = Map#{1 => rootStyle, 2 => c1, 3 => c2, 4 => c3};
        let parents = Map#{2 => 1, 3 => 1, 4 => 1};
        let order = Map#{2 => 0, 3 => 1, 4 => 2};
        let measures = (Map.empty(): Map[EntityId, Vec2.Vec2]);
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 10.0, y = 30.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = allVisible()}, 1, rootRect);
        Assert.assertEq(
            expected = (Some((0.0, 6.0, 10.0, 8.0)), Some((0.0, 14.0, 10.0, 16.0))),
            (lookup(3, result), lookup(4, result)))

    // ════════════════════════════════════════════════════════
    // SpaceBetween
    // ════════════════════════════════════════════════════════

    /// root(1) Column 高さ30・mainAlign=SpaceBetween。子3つ各高4（合計12）。
    ///   余り18 を 2 隙間へ均等 → 9 ずつ。y = 0, 13, 26。
    @Test
    def testSpaceBetweenSpreadsChildren(): Unit \ Assert =
        let rootStyle = {dir = UiLayout.Dir.Column, mainAlign = UiLayout.MainAlign.SpaceBetween | base()};
        let child = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(4.0) | base()};
        let styles = Map#{1 => rootStyle, 2 => child, 3 => child, 4 => child};
        let parents = Map#{2 => 1, 3 => 1, 4 => 1};
        let order = Map#{2 => 0, 3 => 1, 4 => 2};
        let measures = (Map.empty(): Map[EntityId, Vec2.Vec2]);
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 10.0, y = 30.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = allVisible()}, 1, rootRect);
        Assert.assertEq(
            expected = (Some((0.0, 0.0, 10.0, 4.0)), Some((0.0, 13.0, 10.0, 4.0)), Some((0.0, 26.0, 10.0, 4.0))),
            (lookup(2, result), lookup(3, result), lookup(4, result)))

    // ════════════════════════════════════════════════════════
    // abs フロー外
    // ════════════════════════════════════════════════════════

    /// root(1) Column pad L=3,T=2。flow 子 c1(2)=Px 10x4 は content 原点 (3,2)。
    /// abs 子 c2(3) は abs=(40,5) で content 原点+offset=(43,7)、実寸 8x6。
    /// abs はフロー集計に入らないので c1 は動かない。
    @Test
    def testAbsIsOutOfFlow(): Unit \ Assert =
        let rootStyle = {dir = UiLayout.Dir.Column, padLeft = 3.0, padTop = 2.0 | base()};
        let c1 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(4.0) | base()};
        let c2 = {width = UiLayout.SizeSpec.Px(8.0), height = UiLayout.SizeSpec.Px(6.0),
                  abs = Some({x = 40.0, y = 5.0}) | base()};
        let styles = Map#{1 => rootStyle, 2 => c1, 3 => c2};
        let parents = Map#{2 => 1, 3 => 1};
        let order = Map#{2 => 0, 3 => 1};
        let measures = (Map.empty(): Map[EntityId, Vec2.Vec2]);
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 50.0, y = 50.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = allVisible()}, 1, rootRect);
        Assert.assertEq(
            expected = (Some((3.0, 2.0, 10.0, 4.0)), Some((43.0, 7.0, 8.0, 6.0))),
            (lookup(2, result), lookup(3, result)))

    // ════════════════════════════════════════════════════════
    // Stretch
    // ════════════════════════════════════════════════════════

    /// root(1) Column crossAlign=Stretch 幅20。子 c1(2) 幅Px5 でも Stretch で幅20に広がる。
    @Test
    def testStretchFillsCrossAxis(): Unit \ Assert =
        let rootStyle = {dir = UiLayout.Dir.Column, crossAlign = UiLayout.CrossAlign.Stretch | base()};
        let c1 = {width = UiLayout.SizeSpec.Px(5.0), height = UiLayout.SizeSpec.Px(4.0) | base()};
        let styles = Map#{1 => rootStyle, 2 => c1};
        let parents = Map#{2 => 1};
        let order = Map#{2 => 0};
        let measures = (Map.empty(): Map[EntityId, Vec2.Vec2]);
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 20.0, y = 30.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = allVisible()}, 1, rootRect);
        Assert.assertEq(expected = Some((0.0, 0.0, 20.0, 4.0)), lookup(2, result))

    // ════════════════════════════════════════════════════════
    // display:none（visible=false の子はフローから除外）
    // ════════════════════════════════════════════════════════

    /// root(1) Column gap=2。子 c1(2)=Px 10x4・c2(3)=Px 10x6・c3(4)=Px 10x5。
    /// c2 を visible=false にすると、フローから外れて c1 の直後に c3 が詰まる。
    ///   (0,0) c1 10x4
    ///          gap 2
    ///   (0,6) c3 10x5   ← c2 が居た隙間は空かない（display:none 相当）
    /// c2 は矩形が割り当てられない（None）。
    @Test
    def testDisplayNoneExcludesHiddenChildFromFlow(): Unit \ Assert =
        let rootStyle = {dir = UiLayout.Dir.Column, gap = 2.0 | base()};
        let c1 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(4.0) | base()};
        let c2 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(6.0) | base()};
        let c3 = {width = UiLayout.SizeSpec.Px(10.0), height = UiLayout.SizeSpec.Px(5.0) | base()};
        let styles = Map#{1 => rootStyle, 2 => c1, 3 => c2, 4 => c3};
        let parents = Map#{2 => 1, 3 => 1, 4 => 1};
        let order = Map#{2 => 0, 3 => 1, 4 => 2};
        let measures = (Map.empty(): Map[EntityId, Vec2.Vec2]);
        let visible = Map#{3 => false};
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 20.0, y = 30.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = visible}, 1, rootRect);
        Assert.assertEq(
            expected = (Some((0.0, 0.0, 10.0, 4.0)), None, Some((0.0, 6.0, 10.0, 5.0))),
            (lookup(2, result), lookup(3, result), lookup(4, result)))

    /// Auto ヒュッグの親は隠した子を集計しない（パネル高さが可視項目数に追随する）。
    /// panel(2) Auto×Auto・gap=1。子 a(3)=4高・b(4)=4高・c(5)=4高。b を隠すと
    /// 高さ = 4 + gap1 + 4 = 9（3 項目なら 4+1+4+1+4=14 のところ）。
    @Test
    def testDisplayNoneShrinksAutoParent(): Unit \ Assert =
        let rootStyle = base();
        let panel = {dir = UiLayout.Dir.Column, gap = 1.0 | base()};
        let leaf = base();
        let styles = Map#{1 => rootStyle, 2 => panel, 3 => leaf, 4 => leaf, 5 => leaf};
        let parents = Map#{2 => 1, 3 => 2, 4 => 2, 5 => 2};
        let order = Map#{2 => 0, 3 => 0, 4 => 1, 5 => 2};
        let measures = Map#{3 => {x = 10.0, y = 4.0}, 4 => {x = 10.0, y = 4.0}, 5 => {x = 10.0, y = 4.0}};
        let visible = Map#{4 => false};
        let rootRect = {position = {x = 0.0, y = 0.0}, size = {x = 100.0, y = 100.0}};
        let result = UiLayout.computeLayout({styles = styles, parents = parents, order = order, measures = measures, visible = visible}, 1, rootRect);
        Assert.assertEq(expected = Some((0.0, 0.0, 10.0, 9.0)), lookup(2, result))
}
