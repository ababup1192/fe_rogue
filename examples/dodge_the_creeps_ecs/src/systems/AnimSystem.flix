// AnimSystem — スプライトのフレーム送り＋プレイヤーのクリップ選択（純粋）
//
// 旧 AnimatedSprite2D の自動フレーム送りの代替。frameTimer を dt で進め、1/fps を超えたら
// 次フレームへ。プレイヤーは velocity を見て walk/up クリップと flip を切り替える。

mod AnimSystem {

    pub def animSystem(dt: Float64, world: World): World =
        let World.World(w) = world;
        // プレイヤーのクリップを velocity から決めてから、全スプライトをフレーム送りする。
        let withClip = applyPlayerClip(w#player, w#velocities, w#sprites);
        let advanced = Map.map(sc -> advance(dt, sc), withClip);
        World.World({sprites = advanced | w})

    def applyPlayerClip(playerOpt: Option[EntityId],
                        velocities: Map[EntityId, Vec2.Vec2],
                        sprites: Map[EntityId, SpriteComp]): Map[EntityId, SpriteComp] =
        match playerOpt {
            case None      => sprites
            case Some(pid) => updatePlayerClip(pid, velocities, sprites)
        }

    def updatePlayerClip(pid: EntityId,
                         velocities: Map[EntityId, Vec2.Vec2],
                         sprites: Map[EntityId, SpriteComp]): Map[EntityId, SpriteComp] =
        match (Map.get(pid, sprites), Map.get(pid, velocities)) {
            case (Some(sc), Some(vel)) => Map.insert(pid, playerClip(vel, sc), sprites)
            case _                     => sprites
        }

    def playerClip(vel: Vec2.Vec2, sc: SpriteComp): SpriteComp =
        if (vel#x == 0.0 and vel#y == 0.0)
            sc                                   // 停止中はクリップ維持
        else if (vel#x != 0.0)
            {current = "walk", flipH = vel#x < 0.0, flipV = false | sc}
        else
            {current = "up", flipV = vel#y > 0.0, flipH = false | sc}

    /// frameTimer を dt 進め、1/fps に達したら次フレームへ（ループ）。
    /// フレーム送りも「dt を貯めて間隔で発火」なので lib の Clock.tick に揃える。
    def advance(dt: Float64, sc: SpriteComp): SpriteComp =
        let len = clipLen(sc);
        if (len <= 1) sc
        else {
            let interval = if (sc#fps > 0.0) 1.0 / sc#fps else 1.0;
            let r = Clock.tick(sc#frameTimer, dt, interval);
            if (r#fired) {frame = Int32.remainder(sc#frame + 1, len), frameTimer = r#rest | sc}
            else {frameTimer = r#rest | sc}
        }

    def clipLen(sc: SpriteComp): Int32 =
        Map.get(sc#current, sc#clips)
            |> Option.map(List.length)
            |> Option.getWithDefault(0)
}
