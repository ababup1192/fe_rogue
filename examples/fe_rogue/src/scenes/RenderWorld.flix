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
    def zUnit(): Int32 = 9999  // 最前面（既存スプライト/ハイライトの上）
    // World レンダのシルエットを cyan で着色＝scene sprite の上に重なって「World 由来で描けている」のが一目で分かる。
    def tintColor(): Color = {r = 0.4f32, g = 1.0f32, b = 1.0f32}

    /// World + scene → ユニットの実 sprite の Drawable list。
    /// m1b sprite: 位置=World.posOf（権威・gridToWorld→camera）／見た目=ノードの現フレーム（texture/region/offset/flip
    /// 全部正しい）を `Renderable.toDrawables` で再利用。検証用に cyan tint で着色して overlay。
    pub def renderUnits(world: World, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        let transform = viewTransform(scene);
        let mapGlobal = Scene.globalPositionAt(MapScene.worldPath(), scene);
        let players = PlayerScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Player(d#id), PlayerScene.spritePath(d#id), world, mapGlobal, transform, scene));
        let enemies = EnemyScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Enemy(d#id), EnemyScene.spritePath(d#id), world, mapGlobal, transform, scene));
        List.append(players, enemies)

    /// アクティブ camera の ViewTransform（render() と同じ算出）。camera 無しは identity。
    def viewTransform(scene: Scene[NodeTag]): Camera2D.ViewTransform \ GameEngine.Game =
        match Scene.findActiveCamera(scene) {
            case Some((cam, gp)) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.getViewTransform(cam, gp, {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Camera2D.identityTransform()
        }

    /// 1 ユニット → Drawable list。World 位置 → world px(セル中央) → camera → ノードの drawable を screen に置く。
    /// `pathToDrawables` と同じ手順（Renderable.toDrawables + applyZoomScale）だが、位置だけ World 由来に差し替え。
    def unitDraw(ref: World.EntityRef, spritePath: NodePath, world: World,
                 mapGlobal: Vec2, transform: Camera2D.ViewTransform,
                 scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        match World.posOf(ref, world) {
            case None    => Nil
            case Some(g) =>
                let worldPx = {x = mapGlobal#x + Int32.toFloat64(g#x) * tile() + tile() / 2.0,
                               y = mapGlobal#y + Int32.toFloat64(g#y) * tile() + tile() / 2.0};
                let screenPos = Camera2D.applyToWorldPos(transform, worldPx);
                match Scene.getEngineNode(spritePath, scene) {
                    case None       => Nil
                    case Some(node) =>
                        GameEngine.Renderable.toDrawables(node, screenPos)
                            |> List.map(d -> { scale = {x = d#scale#x * transform#scale#x, y = d#scale#y * transform#scale#y},
                                               color = tintColor(), zIndex = zUnit() | d })
                }
        }
}
