/// `<<hotspot {lock|unlock|show|hide} <id>>>` を RoomState に反映するコマンド群。
///
/// 同期コマンド (実行 → submitCommandDone) のみで、scene は変更しない。
/// 不明な action / 引数欠落はログ出力するだけで story を止めない。
mod Game.Commands.HotspotCommands {

    /// CommandRouter からの入口。引数を分解して該当する状態更新を発火する。
    pub def handle(args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Game.RoomState.Access, Dialogue.Session, IO} =
        match args {
            case "lock"   :: id :: _ => Game.RoomState.Access.setLocked(id, true)
            case "unlock" :: id :: _ => Game.RoomState.Access.setLocked(id, false)
            case "show"   :: id :: _ => Game.RoomState.Access.setVisible(id, true)
            case "hide"   :: id :: _ => Game.RoomState.Access.setVisible(id, false)
            case action :: Nil       => println("[HotspotCommands] missing id: ${action}")
            case Nil                 => println("[HotspotCommands] missing action")
            case other :: _          => println("[HotspotCommands] unknown action: ${other}")
        };
        Dialogue.Session.submitCommandDone();
        scene
}
