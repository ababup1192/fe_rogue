// UiRender — UI 全体を毎フレーム、そのまま描ける絵の列に変換する入口。
// 配置から描画データ化までを一手に引き受けるので、呼び手は出てきた絵をフレームに流し込むだけでよい。
// 利用例: HUD やメニューを毎フレーム描く / 箱と文字と枠線をまとめて出す。
// 注意: 箱・文字・スプライトと、多角形（枠線など）は別チャンネルで返す。UI は画面固定なのでカメラの拡大縮小は掛けない。
// spawn 済みの各 root ごとにレイアウトを解決し、継承可視性を求めてから extract する。
// root の layer は CanvasLayer.layerStride() 倍して zIndex に加算し、CanvasLayer HUD
// （TopBar/Minimap/ItemMenu 等）と同じ z 序列に合流させる。

mod UiRender {

    /// 渡された `ui` の全 UI root を描画データへ射影する。box/text/sprite は Drawable、poly は
    /// PolygonRenderCmd と別チャンネルに出るため、`drawables` と `polygons` の 2 列を一度のレイアウト
    /// 解決でまとめて返す（呼び手が sprite / polygon の各チャンネルへ振り分ける）。
    /// 文字実寸とスプライトのテクスチャ寸法は `GameEngine.Game` から引く。font の atlas や
    /// テクスチャ寸法を別の口から与えたい（画面なしのテストやプレビュー）ときは `renderUiWith` を使う。
    pub def renderUi(ui: UiStore.UiWorld, design: Vec2.Vec2):
                    {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}
                    \ GameEngine.Game =
        renderUiWith(
            name -> GameEngine.Game.getFontAtlas(name),
            name -> GameEngine.Game.getTextureInfo(name),
            ui, design)

    /// `renderUi` の注入版。文字実寸を引く `atlasOf`（font 名→FontAtlas）と、スプライトの
    /// テクスチャ寸法を引く `textureInfoOf`（texture 名→寸法）を呼び側から渡す。両者に副作用が
    /// なければ描画全体が純粋になり、画面なしのテスト/プレビューは `GameEngine.Game` の
    /// ハンドラを組まずに済む（sprite を使わなければ `textureInfoOf` は `_ -> None` でよい）。
    /// `design` は画面固定 HUD の rootRect（原点 0,0・design サイズ）を成す。root ごとに extract した
    /// 後、root の layer 分の zIndex オフセットを sprites・polygon の双方へ加算してから連結する。
    pub def renderUiWith(atlasOf: String -> FontAtlas \ ef,
                         textureInfoOf: String -> Option[GameEngine.TextureInfo] \ ef,
                         ui: UiStore.UiWorld, design: Vec2.Vec2):
                    {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} \ ef =
        let measures = UiExtract.measureTexts(ui#texts, atlasOf);
        let roots = rootsOf(ui);
        let rootRect: Rect2.Rect2 =
            {position = {x = 0.0, y = 0.0},
             size = {x = design#x, y = design#y}};
        let perRoot = roots |> List.map(r -> renderRoot(atlasOf, textureInfoOf, ui, measures, rootRect, r));
        {drawables = perRoot |> List.flatMap(rendered -> rendered#drawables),
         polygons  = perRoot |> List.flatMap(rendered -> rendered#polygons)}

    /// 1 root 分の layout 解決 → extract → drawAtlas / extractPolys → layer オフセット加算。
    /// sprites（Drawable）と polygon（PolygonRenderCmd）を同じ layer オフセットで揃えて返す。
    def renderRoot(atlasOf: String -> FontAtlas \ ef,
                   textureInfoOf: String -> Option[GameEngine.TextureInfo] \ ef,
                   ui: UiStore.UiWorld, measures: Map[EntityId, Vec2.Vec2], rootRect: Rect2.Rect2,
                   root: EntityId): {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} \ ef =
        let rects = UiLayout.computeLayout(
            {styles = ui#styles, parents = ui#parents, order = ui#order, measures = measures, visible = ui#visible},
            root, rootRect);
        let vis = UiHierarchy.resolveInherited(ui#visible, ui#parents, root, ui#order);
        let items = UiExtract.extract(ui, rects, vis, atlasOf, textureInfoOf);
        let offset = layerOffset(ui, root);
        let drawables = Render.drawAtlasWith(textureInfoOf, items) |> List.map(d -> {zIndex = d#zIndex + offset | d});
        let polygons = UiExtract.extractPolys(ui, rects, vis)
            |> List.flatMap(entry -> {
                let (_id, _pos, poly) = entry;
                // 1 サブポリ = 1 PolygonRenderCmd（レンダラは凸多角形しか塗れない）。
                poly#polys |> List.map(sub ->
                    ({vertices = sub, color = poly#color, alpha = poly#alpha,
                      zIndex = poly#zIndex + offset}: GameEngine.PolygonRenderCmd))
            });
        {drawables = drawables, polygons = polygons}

    /// root の layer を layers store から引き、CanvasLayer.layerStride 倍した zIndex 加算量を返す。未登録は 0。
    def layerOffset(ui: UiStore.UiWorld, root: EntityId): Int32 =
        Option.getWithDefault(0, Map.get(root, ui#layers)) * CanvasLayer.layerStride()

    /// 親を持たない entity（＝各サブツリーの root）を列挙する。
    def rootsOf(ui: UiStore.UiWorld): List[EntityId] =
        Map.valuesOf(ui#names) |> List.filter(id -> Option.isEmpty(Map.get(id, ui#parents)))
}
