/// `<<phase <nodeName>>>` で旧 VM を破棄して新規 Session を始める高レベル切替コマンド。
///
/// `Session.start` が新しい VM を vmRef に差し替えるので、後続の `<<stop>>` 命令は
/// 旧 VM 上で決して実行されない (旧 VM はそのまま GC される)。
///
/// **submitCommandDone は呼ばない**: 新 VM はもう自分の最初の命令まで進んでおり、
/// 旧 VM の WaitingCommand に対する完了通知は意味を持たない。
mod Game.Commands.PhaseCommands {

    pub def handle(args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Dialogue.Session, IO} =
        match args {
            case nodeName :: _ =>
                Dialogue.Session.start(nodeName)
            case Nil =>
                println("[PhaseCommands] missing node name");
                Dialogue.Session.submitCommandDone()
        };
        scene
}
