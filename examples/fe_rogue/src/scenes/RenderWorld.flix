// RenderWorld — B1: fe_rogue の render-from-World extract（dodge RenderWorld 相当）。
// World → render component の draw list → Drawable（共有 lib Render に委譲）。scene-tree を介さない。
//
// m1a（このファイルの現状）: 配線実証。ユニットを World 位置に solidBox で描く（camera 無し・固定視点）。
//   目的＝「World 位置 → Render.draw → GameEngine.renderCommands」が fe_rogue ループで動くことの証明。
// m1b（次）: box → 実 sprite（resource 由来 texture・region atlas は Render.drawAtlas で）。
mod RenderWorld {
    use Render.RenderItem
    use Vec2.Vec2

    /// m1 toggle: true で render-from-World（box）・false で従来 scene-tree 描画。実機で切替検証。
    pub def useRenderFromWorld(): Bool = true

    def tile(): Float64 = MapSnapshot.tileSize()
    // ゲーム既存の移動/攻撃範囲ハイライト(青/赤)と区別するため、目立つ色＋小さめ点にする（検証用）。
    def playerColor(): Color = {r = 1.0f32, g = 0.0f32, b = 1.0f32}  // マゼンタ＝味方
    def enemyColor(): Color  = {r = 1.0f32, g = 1.0f32, b = 0.0f32}  // 黄＝敵
    def markerFrac(): Float64 = 0.45  // タイルに対する点のサイズ比（中央に小さく）
    def zUnit(): Int32 = 9999  // 最前面に（既存ハイライトより上）

    /// World + scene（entity 列挙用）→ ユニット box の Drawable list。
    /// m1b: 位置は World.posOf（権威）を gridToWorld（mapGlobal + grid*26+13 中央）→ camera 変換で screen 化。
    /// ＝scene-tree ユニットと同じ座標系に重なる（位置パイプライン実証）。
    pub def renderUnits(world: World, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        let transform = viewTransform(scene);
        let mapGlobal = Scene.globalPositionAt(MapScene.worldPath(), scene);
        let players = PlayerScene.getAll(scene)
            |> List.filterMap(d -> unitItem(World.EntityRef.Player(d#id), world, mapGlobal, transform, playerColor()));
        let enemies = EnemyScene.getAll(scene)
            |> List.filterMap(d -> unitItem(World.EntityRef.Enemy(d#id), world, mapGlobal, transform, enemyColor()));
        Render.draw(List.append(players, enemies))

    /// アクティブ camera の ViewTransform（render() と同じ算出）。camera 無しは identity。
    def viewTransform(scene: Scene[NodeTag]): Camera2D.ViewTransform \ GameEngine.Game =
        match Scene.findActiveCamera(scene) {
            case Some((cam, gp)) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.getViewTransform(cam, gp, {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Camera2D.identityTransform()
        }

    /// 1 ユニット → (screen 左上, box)。World 位置 → world px(中央) → camera 適用 → 左上に補正。
    def unitItem(ref: World.EntityRef, world: World, mapGlobal: Vec2,
                 transform: Camera2D.ViewTransform, color: Color): Option[(Vec2, RenderItem)] =
        World.posOf(ref, world) |> Option.map(g ->
            let worldPx = {x = mapGlobal#x + Int32.toFloat64(g#x) * tile() + tile() / 2.0,
                           y = mapGlobal#y + Int32.toFloat64(g#y) * tile() + tile() / 2.0};
            let screen = Camera2D.applyToWorldPos(transform, worldPx);
            let screenSize = Camera2D.applyToWorldSize(transform, {x = tile() * markerFrac(), y = tile() * markerFrac()});
            let topLeft = {x = screen#x - screenSize#x / 2.0, y = screen#y - screenSize#y / 2.0};
            (topLeft, Render.solidBox(screenSize, color, zUnit())))
}
