// AudioView — 状態の前後差から、一度だけ鳴らす音名を導く。
// 再生処理と分けることで、ゲーム規則を音響APIへ依存させない。
mod AudioView {

    /// project.json の sound 名へ写す純粋な入口。
    pub def cues(worlds: { before = World.World, after = World.World }): List[String] =
        List.flatten(
               backgroundMusic(worlds)
            :: launch(worlds)
            :: acceleration(worlds)
            :: brake(worlds)
            :: boost(worlds)
            :: jump(worlds)
            :: wall(worlds)
            :: collision(worlds)
            :: explosion(worlds)
            :: Nil)

    def backgroundMusic(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(
                worlds#before#audioStarted,
                worlds#after#audioStarted))
            "bgm" :: "engine_low" :: "engine_high" :: Nil
        else
            Nil

    def launch(worlds: { before = World.World, after = World.World }): List[String] =
        if (worlds#before#phase == World.Phase.Countdown
            and worlds#after#phase == World.Phase.Racing)
            "launch" :: Nil
        else
            Nil

    def acceleration(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(
                worlds#before#throttling,
                worlds#after#throttling))
            "accelerate" :: Nil
        else
            Nil

    def brake(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(worlds#before#braking, worlds#after#braking)
            and worlds#before#speed > 12.0)
            "brake" :: Nil
        else
            Nil

    def boost(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(worlds#before#boosting, worlds#after#boosting)
            or InputEdge.pressed(
                worlds#before#trackBoosting,
                worlds#after#trackBoosting))
            "boost" :: Nil
        else
            Nil

    def jump(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(
                TimedHop.isAirborne(worlds#before#jump),
                TimedHop.isAirborne(worlds#after#jump)))
            "jump" :: Nil
        else
            Nil

    def wall(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(
                worlds#before#wallCooldown > 0.0,
                worlds#after#wallCooldown > 0.0))
            "wall" :: Nil
        else
            Nil

    def collision(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(
                worlds#before#collisionCooldown > 0.0,
                worlds#after#collisionCooldown > 0.0))
            "collision" :: Nil
        else
            Nil

    def explosion(worlds: { before = World.World, after = World.World }): List[String] =
        if (InputEdge.pressed(
                worlds#before#phase == World.Phase.Crashed,
                worlds#after#phase == World.Phase.Crashed))
            "explode" :: Nil
        else
            Nil
}
