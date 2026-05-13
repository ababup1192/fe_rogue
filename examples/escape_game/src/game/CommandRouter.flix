/// Yarn の `<<command>>` 文字列を実処理に振り分ける gameLoop 段。
///
/// `Dialogue.SceneView.CommandInbox` に溜まったコマンド文字列をフレーム毎にすべて取り出し、
/// `Dialogue.CommandParser.parse` で `(name, args)` に分解して、コマンド名に応じた
/// 副作用（音再生・変数書き込み・待機キュー登録 等）を発火する。
///
/// 設計の要点:
///   - **同期コマンド**（音・フラグ・アイテム）は処理直後に `Dialogue.Session.submitCommandDone`
///     を呼んで Yarn VM を進める
///   - **非同期コマンド**（`<<wait>>`）は `Game.CommandWaitQueue` に Duration を積む。
///     毎フレーム末尾の `tick` で期限切れになったぶんだけ `submitCommandDone` を発火する
///   - **シーンを変更するコマンド**（`<<bg>>` / `<<sprite>>`）は `WorldScene` の API を呼んで
///     scene を畳んでいき、最後に外へ返す
///   - **未対応コマンド**は `println` でログを出して即完了。story を止めない
mod Game.CommandRouter {
    use Duration.Duration

    /// `Dialogue.SceneView.CommandInbox` から溜まったコマンドをすべて取り出して dispatch し、
    /// `WaitQueue` を `delta` だけ進めて期限切れ件数ぶん `submitCommandDone` を発火する。
    /// `bg` / `sprite` 系コマンドは `scene` を畳み込んでいくため、最終的な scene を返す。
    /// 状態（wait queue / shake / audio fader）は custom effect 経由で参照する。
    /// 実体は `Game.start` で region 内 Ref に閉じ込めて handler 注入される。
    pub def processCommands(delta: {delta = Duration},
                              scene: Scene[NodeTag]):
                              Scene[NodeTag] \ {
                                Dialogue.SceneView.CommandInbox,
                                GameEngine.Audio,
                                Dialogue.Session,
                                Yarn.VariableAccess,
                                Game.CommandWaitQueue.Access,
                                Game.ShakeState.Access,
                                Game.AudioFader.Access,
                                Game.RoomState.Access,
                                Game.Inventory.Access,
                                Fs.FileRead,
                                Fs.FileWrite,
                                IO
                              } =
        let pending = Dialogue.SceneView.CommandInbox.takeAllCommands();
        let afterDispatch =
            List.foldLeft((sc, text) -> dispatchOne(text, sc), scene, pending);
        let expired = Game.CommandWaitQueue.Access.tick(delta#delta);
        completeMany(expired);
        afterDispatch

    /// 1 件のコマンド文字列を parse → ハンドラに振り分け。
    /// 同期コマンドは即 `submitCommandDone`、非同期（wait）は WaitQueue に積むだけで
    /// 完了通知は呼ばない（後続の `tick` が発火する）。
    /// シーンを変えるコマンドは新しい scene を返し、それ以外は受け取った scene をそのまま返す。
    def dispatchOne(text: String, scene: Scene[NodeTag]):
                     Scene[NodeTag] \ {
                       GameEngine.Audio, Dialogue.Session, Yarn.VariableAccess,
                       Game.CommandWaitQueue.Access, Game.ShakeState.Access,
                       Game.AudioFader.Access, Game.RoomState.Access,
                       Game.Inventory.Access,
                       Fs.FileRead, Fs.FileWrite, IO
                     } =
        let (name, args) = Dialogue.CommandParser.parse(text);
        match (name, args) {
            // 音響: bgm play/fade, se
            case ("bgm", _) =>
                Game.Commands.AudioCommands.handle(name, args, scene)
            case ("se", _) =>
                Game.Commands.AudioCommands.handle(name, args, scene)
            // 待機: wait <sec>
            case ("wait", _) =>
                Game.Commands.TimingCommands.handleWait(args, scene)
            // フラグ: flag set/clear <name>
            case ("flag", _) =>
                Game.Commands.VarCommands.handle(args, scene)
            // インベントリ: inv add/remove <id>
            case ("inv", _) =>
                Game.Commands.InventoryCommands.handle(args, scene)
            // 背景: bg <name>
            case ("bg", _) =>
                Game.Commands.WorldCommands.handle(name, args, scene)
            // 部屋遷移: room enter <id>
            case ("room", _) =>
                Game.Commands.RoomCommands.handle(args, scene)
            // ホットスポット状態操作: hotspot {lock|unlock|show|hide} <id>
            // 詳細は `Game.Commands.HotspotCommands.handle` に委譲。
            case ("hotspot", _) =>
                Game.Commands.HotspotCommands.handle(args, scene)
            // キャラ: sprite show/hide <name>
            case ("sprite", _) =>
                Game.Commands.WorldCommands.handle(name, args, scene)
            // 画面ゆれ: shake <sec>
            case ("shake", _) =>
                Game.Commands.TimingCommands.handleShake(args, scene)
            // フェーズ遷移: phase <nodeName>
            case ("phase", _) =>
                Game.Commands.PhaseCommands.handle(args, scene)
            // セーブ・ロード: save / load <slot>
            case ("save", _) =>
                Game.Commands.SaveCommands.handle(name, args, scene)
            case ("load", _) =>
                Game.Commands.SaveCommands.handle(name, args, scene)
            // 空文字（理論上は来ない）
            case ("", _) =>
                Dialogue.Session.submitCommandDone();
                scene
            // 未対応コマンド名 (typo 等)。ログに出して story を進める。
            case _ =>
                println("[CommandRouter] unhandled: ${name} ${args}");
                Dialogue.Session.submitCommandDone();
                scene
        }

    /// `count` 回 `submitCommandDone` を呼ぶ。WaitQueue の期限切れ通知用。
    def completeMany(count: Int32): Unit \ Dialogue.Session =
        if (count <= 0) ()
        else {
            Dialogue.Session.submitCommandDone();
            completeMany(count - 1)
        }

}
