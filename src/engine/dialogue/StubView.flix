/// テスト用の `DialogueView` 実装。受け取った操作を `Dialogue.ViewEvent` の
/// ログに蓄積する。
///
/// テスト本体に `run ... with handler DialogueView { ... }` を直書きしないよう、
/// effect 多相な `withRecordingView` を集約している。
mod Dialogue.StubView {
    use Dialogue.ViewEvent
    use Dialogue.ViewEvent.{Line, Choices, Dismiss, Command, Complete}

    /// view 操作を region 内 MutDeque に蓄積し、body 終了時に List で返す。
    /// 他の effect は `ef` で透過する。
    pub def withRecordingView(rc: Region[r], body: Unit -> a \ ef + Dialogue.DialogueView):
                                (a, List[ViewEvent]) \ ef + r =
        let log: MutDeque[ViewEvent, r] = MutDeque.empty(rc);
        let result = run body() with handler Dialogue.DialogueView {
            def presentLine(line, resume) = {
                MutDeque.pushBack(Line(line#text, line#speaker), log);
                resume()
            }
            def presentChoices(choices, resume) = {
                let labels = List.map(choice -> choice#text, choices);
                MutDeque.pushBack(Choices(labels), log);
                resume()
            }
            def dismissLine(resume) = {
                MutDeque.pushBack(Dismiss, log);
                resume()
            }
            def runCommand(commandText, resume) = {
                MutDeque.pushBack(Command(commandText), log);
                resume()
            }
            def dialogueComplete(resume) = {
                MutDeque.pushBack(Complete, log);
                resume()
            }
        };
        (result, MutDeque.toList(log))
}

/// テスト用 facade。本番 `Dialogue.withDialog` と対称な「3 段 handler を 1 行で」の
/// テスト版。`Dialogue.Session` を提供し、view 操作は `ViewEvent` の List として返す。
///
/// 本番との差:
///   - DialogueView は `StubView.withRecordingView`（log に蓄積）
///   - `<<command>>` は同期完了扱い（`Dialogue.Runner.withRunner` の syncCommands=true）
///   - 拡張 builtin は `Yarn.BuiltinExtension.withNoExtension` で握りつぶす
///
/// テスト本体は `body` 内で `Dialogue.Session.start` などを呼ぶだけで良い。
mod Dialogue.Test {
    use Yarn.Types.YarnProject
    use Dialogue.ViewEvent

    /// 1 つの `region rc` 内で stub view + sync runner + no-extension を被せ、body 実行後の
    /// イベントログを返す。`runWithStubs` の置き換え。
    pub def withTestDialog(rc: Region[r], compiledProject: YarnProject,
                            body: Unit -> a \ ef):
                            (a, List[ViewEvent]) \ (ef - Dialogue.Session
                                                       - Dialogue.DialogueView
                                                       - Yarn.VariableAccess
                                                       - Yarn.BuiltinExtension.Access)
                                                  + r =
        Dialogue.StubView.withRecordingView(rc, () -> {
            Yarn.BuiltinExtension.withNoExtension(() -> {
                Dialogue.Runner.withRunner(rc, compiledProject, true, body)
            })
        })
}
