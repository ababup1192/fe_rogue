/// 音響系コマンド: `<<bgm play|fade ...>>` と `<<se <name>>>`。
///
/// - `bgm play <name>`: AudioFader に名前を登録 (前回の fade-out で gain=0 のまま
///   残るのを防ぐためリセット) してから `playAudio` を発火
/// - `bgm fade <sec>`: 現 BGM の音量を 1.0 → 0.0 にフェード。完了で stopAudio
/// - `se <name>`: 効果音をワンショット再生
///
/// すべて同期コマンドで scene は素通り。
mod Game.Commands.AudioCommands {
    use Duration.Duration

    /// CommandRouter からの入口。コマンド名 (`bgm` or `se`) と引数を受け取り処理する。
    pub def handle(name: String, args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, Game.AudioFader.Access,
                              Dialogue.Session, IO} =
        match (name, args) {
            case ("bgm", "play" :: assetName :: _) =>
                Game.AudioFader.setBgm(assetName);
                GameEngine.Audio.playAudio(assetName)
            case ("bgm", "fade" :: secStr :: _) =>
                match Float64.fromString(secStr) {
                    case Some(seconds) =>
                        Game.AudioFader.fadeOutCurrent(Duration.seconds(seconds))
                    case None =>
                        println("[AudioCommands] invalid bgm fade seconds: ${secStr}")
                }
            case ("se", assetName :: _) =>
                GameEngine.Audio.playAudio(assetName)
            case ("bgm", action :: _) =>
                println("[AudioCommands] unknown bgm action: ${action}")
            case ("bgm", Nil) =>
                println("[AudioCommands] missing bgm action")
            case ("se", Nil) =>
                println("[AudioCommands] missing se asset name")
            case _ =>
                println("[AudioCommands] unhandled: ${name} ${args}")
        };
        Dialogue.Session.submitCommandDone();
        scene
}
