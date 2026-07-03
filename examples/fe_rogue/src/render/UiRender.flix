// UiRender — UiWorldState の UI ツリーを毎フレーム描画データへ射影する合流点。
//
// renderFrame の worldDrawables（sprite チャンネル）と polygon チャンネルの双方に合流する。
// box/text/sprite は Drawable、poly は PolygonRenderCmd と別チャンネルに出るので 2 列で返す。
// UI は画面固定 HUD（camera 免除）なので
// rootRect はデザイン解像度（240×128）を使い、extract は camera scale を掛けない。
// spawn 済みの各 root ごとにレイアウトを解決し、継承可視性を求めてから extract する。
// root の layer は CanvasLayer.layerStride() 倍して zIndex に加算し、CanvasLayer HUD
// （TopBar/Minimap/ItemMenu 等）と同じ z 序列に合流させる。

mod UiRender {

    /// UiWorldState の全 UI root を描画データへ射影する。box/text/sprite は Drawable、poly は
    /// PolygonRenderCmd と別チャンネルに出るため、`drawables` と `polygons` の 2 列を一度のレイアウト
    /// 解決でまとめて返す（renderFrame が sprite / polygon の各チャンネルへ振り分ける）。
    /// 文字実寸は Game.getFontAtlas から measure し、root ごとに extract した後、root の layer 分の
    /// zIndex オフセットを sprites・polygon の双方へ加算してから連結する。
    pub def renderUi(): {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}
                    \ {GameEngine.Game, UiWorldState.State} =
        let ui = UiWorldState.State.get();
        let atlasOf = name -> GameEngine.Game.getFontAtlas(name);
        let measures = UiExtract.measureTexts(ui#texts, atlasOf);
        let roots = rootsOf(ui);
        let rootRect: Rect2.Rect2 =
            {position = {x = 0.0, y = 0.0},
             size = {x = Int32.toFloat64(Game.designWi()), y = Int32.toFloat64(Game.designHi())}};
        let perRoot = roots |> List.map(r -> renderRoot(ui, measures, rootRect, r));
        {drawables = perRoot |> List.flatMap(rendered -> rendered#drawables),
         polygons  = perRoot |> List.flatMap(rendered -> rendered#polygons)}

    /// 1 root 分の layout 解決 → extract → drawAtlas / extractPolys → layer オフセット加算。
    /// sprites（Drawable）と polygon（PolygonRenderCmd）を同じ layer オフセットで揃えて返す。
    def renderRoot(ui: UiStore.UiWorld, measures: Map[EntityId, Vec2.Vec2], rootRect: Rect2.Rect2,
                   root: EntityId): {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]} \ GameEngine.Game =
        let atlasOf = name -> GameEngine.Game.getFontAtlas(name);
        let rects = UiLayout.computeLayout(ui#styles, ui#parents, ui#order, measures, ui#visible, root, rootRect);
        let vis = UiHierarchy.resolveInherited(ui#visible, ui#parents, root, ui#order);
        let items = UiExtract.extract(ui, rects, vis, atlasOf);
        let offset = layerOffset(ui, root);
        let drawables = Render.drawAtlas(items) |> List.map(d -> {zIndex = d#zIndex + offset | d});
        let polygons = UiExtract.extractPolys(ui, rects, vis)
            |> List.map(entry -> {
                let (_id, _pos, poly) = entry;
                ({vertices = poly#points, color = poly#color, alpha = poly#alpha,
                  zIndex = poly#zIndex + offset}: GameEngine.PolygonRenderCmd)
            });
        {drawables = drawables, polygons = polygons}

    /// root の layer を layers store から引き、CanvasLayer.layerStride 倍した zIndex 加算量を返す。未登録は 0。
    def layerOffset(ui: UiStore.UiWorld, root: EntityId): Int32 =
        Option.getWithDefault(0, Map.get(root, ui#layers)) * CanvasLayer.layerStride()

    /// 親を持たない entity（＝各サブツリーの root）を列挙する。
    def rootsOf(ui: UiStore.UiWorld): List[EntityId] =
        Map.valuesOf(ui#names) |> List.filter(id -> Option.isEmpty(Map.get(id, ui#parents)))
}
