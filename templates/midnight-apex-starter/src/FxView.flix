// FxView — 衝突後の爆発など、機体そのものではない短い演出。
// Worldから時間だけを読み、粒の位置は固定方向から決定的に作る。
mod FxView {

    /// Crashed中だけ、広がる光球と8方向の破片を描く。
    pub def crash(world: World.World, center: Vec2.Vec2,
                  z: Int32): List[Render.PlacedItem] =
        if (world#phase != World.Phase.Crashed)
            Nil
        else {
            let progress = Float64.min(1.0, world#crashTime / 0.85);
            let radius = 8.0 + 34.0 * progress;
            let directions =
                { x = -1.0, y = -0.4 }
                :: { x = -0.6, y = -1.0 }
                :: { x = 0.0, y = -1.0 }
                :: { x = 0.7, y = -0.8 }
                :: { x = 1.0, y = -0.2 }
                :: { x = 0.7, y = 0.8 }
                :: { x = 0.0, y = 1.0 }
                :: { x = -0.8, y = 0.7 }
                :: Nil;
               Render.glowAt(
                   center, radius * 1.8, world#theme#danger,
                   { alpha = 0.76 * (1.0 - progress * 0.55),
                     blend = DrawCmd.BlendMode.Add }, z)
            ::: Render.circleAt(
                   center, radius, world#theme#lane, z + 1)
                |> fadePlaced(0.85 * (1.0 - progress))
            :: (directions |> List.map(direction -> {
                let end = {
                    x = center#x + direction#x * radius * 1.55,
                    y = center#y + direction#y * radius * 1.55
                };
                Render.lineSeg(
                    center, end, 2.8,
                    if (direction#x < 0.0)
                        world#theme#player
                    else
                        world#theme#lane,
                    z + 2)
                    |> fadePlaced(1.0 - progress * 0.7)
            }))
        }

    /// PlacedItemの位置を変えず透明度だけを適用する。
    def fadePlaced(alpha: Float64,
                   placed: Render.PlacedItem): Render.PlacedItem =
        { at = placed#at,
          item = placed#item
            |> Render.fade(Float64.truncateToFloat32(alpha)) }
}
