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

    /// m1c: renderArgs に渡す前に scene 側のユニット sprite を不可視化＝ユニットは World からのみ描かれる
    /// （重複②の一角を scene-tree から剥がす）。不変 scene のコピーを返す（実 scene 状態は不変）。
    pub def hideUnitSprites(scene: Scene[NodeTag]): Scene[NodeTag] =
        let hideOne = (sc, path) -> Scene.mapEngineNode(path, n -> CanvasItem.setVisible(false, n), sc);
        let afterP = List.foldLeft((sc, d) -> hideOne(sc, PlayerScene.spritePath(d#id)), scene, PlayerScene.getAll(scene));
        List.foldLeft((sc, d) -> hideOne(sc, EnemyScene.spritePath(d#id)), afterP, EnemyScene.getAll(scene))

    /// World + scene → ユニットの実 sprite の Drawable list（scene 側 sprite は hideUnitSprites で隠す）。
    /// m1c: 描画は World render System（この関数）が担い、ユニット sprite を scene auto-render から剥がす。
    /// 存在 gate = World.posOf（World が論理位置を持つユニットのみ描く）。
    /// ⚠ 視覚位置は当面 scene の tween 値（武器/HPバー＝同じ marker 上の兄弟と同期して滑らかに動かすため）。
    ///   真の render-from-World（位置も World 由来＋tween を World component 化）は m2。
    pub def renderUnits(world: World, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        let transform = viewTransform(scene);
        let players = PlayerScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Player(d#id), PlayerScene.spritePath(d#id), world, transform, scene));
        let enemies = EnemyScene.getAll(scene)
            |> List.flatMap(d -> unitDraw(World.EntityRef.Enemy(d#id), EnemyScene.spritePath(d#id), world, transform, scene));
        List.append(players, enemies)

    /// アクティブ camera の ViewTransform（render() と同じ算出）。camera 無しは identity。
    def viewTransform(scene: Scene[NodeTag]): Camera2D.ViewTransform \ GameEngine.Game =
        match Scene.findActiveCamera(scene) {
            case Some((cam, gp)) =>
                let vp = GameEngine.Game.getViewportRect();
                Camera2D.getViewTransform(cam, gp, {viewportWidth = vp#size#x, viewportHeight = vp#size#y})
            case None => Camera2D.identityTransform()
        }

    /// 1 ユニット → Drawable list。`pathToDrawables` と同手順（globalPositionAt→camera→Renderable.toDrawables→
    /// applyZoomScale）。視覚位置・modulate・z は scene 由来（兄弟ノードと同期）、存在のみ World.posOf で gate。
    /// posOf×getEngineNode は forM で 1 段に畳む。
    def unitDraw(ref: World.EntityRef, spritePath: NodePath, world: World,
                 transform: Camera2D.ViewTransform, scene: Scene[NodeTag]): List[GameEngine.Drawable] \ GameEngine.Game =
        if (not Scene.effectiveVisibleAt(spritePath, scene)) Nil
        else
            (forM (
                _pos <- World.posOf(ref, world);
                node <- Scene.getEngineNode(spritePath, scene)
            ) yield {
                let screenPos = Camera2D.applyToWorldPos(transform, Scene.globalPositionAt(spritePath, scene));
                // effectiveModulateAt は node 自身の modulate を含む（fog×待機暗転）＝単一適用。d#color へ再掛けしない。
                let color = Scene.effectiveModulateAt(spritePath, scene);
                let z = Scene.effectiveZIndexAt(spritePath, scene);
                GameEngine.Renderable.toDrawables(node, screenPos)
                    |> List.map(d -> {
                        scale = {x = d#scale#x * transform#scale#x, y = d#scale#y * transform#scale#y},
                        color = color, zIndex = z | d })
            }) |> Option.getWithDefault(Nil)
}
