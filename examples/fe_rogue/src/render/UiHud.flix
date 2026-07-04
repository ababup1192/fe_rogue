// UiHud — fe_rogue の UI 描画バインディング。
//
// engine_world の純粋な `UiRender.renderUi(ui, design)` に、fe_rogue 固有の 2 つ
// （UiWorldState resource から読む現在の UiWorld と、Game の design 解像度）を供給するだけの薄い層。
// 描画本体は engine_world 側に持たせ、ここは「どの UiWorld を・どの解像度で」を束ねる合流点。
mod UiHud {

    /// 現在の UiWorldState を Game の design 解像度で描画データへ射影する。
    /// box/text/sprite は `drawables`、poly は `polygons` に分けて返す（呼び手が各チャンネルへ振り分ける）。
    pub def renderUi(): {drawables = List[GameEngine.Drawable], polygons = List[GameEngine.PolygonRenderCmd]}
                    \ {GameEngine.Game, UiWorldState.State} =
        let ui = UiWorldState.State.get();
        let design: Vec2.Vec2 =
            {x = Int32.toFloat64(Game.designWi()), y = Int32.toFloat64(Game.designHi())};
        UiRender.renderUi(ui, design)
}
