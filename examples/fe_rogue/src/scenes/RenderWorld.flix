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
    def playerColor(): Color = {r = 0.3f32, g = 0.6f32, b = 1.0f32}
    def enemyColor(): Color  = {r = 1.0f32, g = 0.3f32, b = 0.3f32}
    def zUnit(): Int32 = 10

    /// World + scene（entity 列挙用）→ ユニット box の Drawable list。
    /// m1a: 位置は World.posOf（権威）。grid×tileSize で pixel 化（mapGlobal offset は m1b で）。
    pub def renderUnits(world: World, scene: Scene[NodeTag]): List[GameEngine.Drawable] =
        let players = PlayerScene.getAll(scene)
            |> List.filterMap(d -> unitItem(World.EntityRef.Player(d#id), world, playerColor()));
        let enemies = EnemyScene.getAll(scene)
            |> List.filterMap(d -> unitItem(World.EntityRef.Enemy(d#id), world, enemyColor()));
        Render.draw(List.append(players, enemies))

    /// 1 ユニット → (pixel pos, box)。World に位置が無ければ None。
    def unitItem(ref: World.EntityRef, world: World, color: Color): Option[(Vec2, RenderItem)] =
        World.posOf(ref, world) |> Option.map(p ->
            ({x = Int32.toFloat64(p#x) * tile(), y = Int32.toFloat64(p#y) * tile()},
             Render.solidBox({x = tile(), y = tile()}, color, zUnit())))
}
