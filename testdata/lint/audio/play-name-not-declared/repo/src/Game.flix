mod Game {
    pub def onStep(): Unit \ IO =
        Audio.play("step")

    pub def onJump(): Unit \ IO =
        Audio.play("jump")
}
