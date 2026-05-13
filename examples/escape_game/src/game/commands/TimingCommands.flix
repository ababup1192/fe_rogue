/// 時間関連コマンド: `<<wait <sec>>>` と `<<shake <sec>>>`。
///
/// - `wait <sec>`: 指定秒数だけ Yarn VM を待機させる。**非同期コマンド**で
///   `submitCommandDone` を呼ばない (CommandRouter 末尾の `tick` が期限切れ時に発火)
/// - `shake <sec>`: 画面ゆれをアクティブ化。同期コマンドで scene 自体は素通り
///   (毎フレームの `ShakeState.tickAndApply` がオフセットを注入する)
mod Game.Commands.TimingCommands {
    use Duration.Duration

    /// `<<shake <sec>>>` の最大オフセット (design px)。design 480x300 に対して
    /// 4px ぶれる程度が「ガクッ」と感じる範囲。引数で可変にしたくなったら
    /// 2 引数目をパースする形に拡張する。
    def shakeIntensity(): Float64 = 4.0

    /// `<<wait <sec>>>`。**非同期**: submitCommandDone を呼ばずに WaitQueue に Duration を積む。
    /// 数値 parse 失敗時は story が止まらないよう即時 submitCommandDone を発火する。
    pub def handleWait(args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Game.CommandWaitQueue.Access, Dialogue.Session, IO} =
        match args {
            case secStr :: _ =>
                match Float64.fromString(secStr) {
                    case Some(seconds) =>
                        Game.CommandWaitQueue.Access.enqueue(Duration.seconds(seconds))
                    case None =>
                        println("[TimingCommands] invalid wait seconds: ${secStr}");
                        Dialogue.Session.submitCommandDone()
                }
            case Nil =>
                println("[TimingCommands] missing wait seconds");
                Dialogue.Session.submitCommandDone()
        };
        scene

    /// `<<shake <sec>>>`。同期コマンドで ShakeState に Duration + 強度を積むだけ。
    pub def handleShake(args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Game.ShakeState.Access, Dialogue.Session, IO} =
        match args {
            case secStr :: _ =>
                match Float64.fromString(secStr) {
                    case Some(seconds) =>
                        Game.ShakeState.start(Duration.seconds(seconds), shakeIntensity())
                    case None =>
                        println("[TimingCommands] invalid shake seconds: ${secStr}")
                }
            case Nil =>
                println("[TimingCommands] missing shake seconds")
        };
        Dialogue.Session.submitCommandDone();
        scene
}
