/// 世界 (World) シーン操作コマンド: `<<bg <name>>>` と `<<sprite show/hide <name>>>`。
///
/// - `bg <name>`: 背景テクスチャを差し替える (fade は未実装)
/// - `sprite show <name> [variant]`: キャラ立ち絵を表示
/// - `sprite hide <name>`: 立ち絵を非表示
///
/// すべて scene を変換するコマンド。`WorldScene` の API に委譲。
mod Game.Commands.WorldCommands {

    pub def handle(name: String, args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Dialogue.Session, IO} =
        let next = match (name, args) {
            case ("bg", bgName :: _) =>
                WorldScene.setBackground(bgName, scene)
            case ("sprite", "show" :: spriteName :: _) =>
                WorldScene.showCharacter(spriteName, scene)
            case ("sprite", "hide" :: spriteName :: _) =>
                WorldScene.hideCharacter(spriteName, scene)
            case ("bg", Nil) =>
                println("[WorldCommands] missing bg name");
                scene
            case ("sprite", action :: Nil) =>
                println("[WorldCommands] missing sprite name: ${action}");
                scene
            case ("sprite", Nil) =>
                println("[WorldCommands] missing sprite action");
                scene
            case ("sprite", action :: _) =>
                println("[WorldCommands] unknown sprite action: ${action}");
                scene
            case _ =>
                println("[WorldCommands] unhandled: ${name} ${args}");
                scene
        };
        Dialogue.Session.submitCommandDone();
        next
}
