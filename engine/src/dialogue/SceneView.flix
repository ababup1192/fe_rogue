/// Yarn → Scene 統合のための view 側 handler 一式。
///
/// `Dialogue.DialogueView` の本番（Scene 統合用）handler と、
/// 蓄積されたイベントを 1 フレーム単位で取り出す `Inbox` effect を
/// セットで提供する。両者は内部の同じ `MutDeque` を介して受け渡す。
///
/// 設計の意図:
///   - 受信ハンドラ（DialogueView）は scene を直接いじらず queue に push するだけ
///   - 消費は `Inbox.takeAll` を `process` ライフサイクル内で呼ぶ
///   - これにより `handleInput` が返すシーンと「side channel で書き込まれたシーン」
///     がマージされる必要がなくなる（pull 型）
///
/// `withSceneView(rc, body)` は queue 確保と両 handler 連結を内包し、
/// 呼び出し側に queue を露出しない。
mod Dialogue.SceneView {
    use Dialogue.ViewEvent
    use Dialogue.ViewEvent.{Line, Choices, Dismiss, Complete}

    /// SceneView が貯めた `ViewEvent` を取り出す effect。
    /// `process` の中で呼ばれ、handler 側が region 内 `MutDeque` を List に変換して返す。
    /// gameLoop に scene 操作を漏らさず、フレーム毎の queue 消化を Node ライフサイクルに閉じる。
    /// 注意: `runCommand` は別キュー（`CommandInbox`）に流すので、ここには Line / Choices /
    /// Dismiss / Complete のみが入る。
    pub eff Inbox {
        def takeAll(): List[ViewEvent]
    }

    /// `runCommand` 由来のコマンド文字列だけを取り出す effect。
    /// `Inbox` と分離してあるのは、`DialogueScene.process` が `Inbox.takeAll` で
    /// view 系イベントを drain するため、command 系を同じキューに混ぜると
    /// 別フレームの Router が読めなくなるから。
    pub eff CommandInbox {
        def takeAllCommands(): List[Dialogue.CommandText]
    }

    /// `DialogueView` の各操作を 2 つの `MutDeque` に振り分ける handler セット。
    /// view 系（Line/Choices/Dismiss/Complete）と command 系（runCommand 由来の文字列）を
    /// 別キューに分離して、別の consumer がそれぞれ独立に消費できるようにする。
    /// queue はどちらも region 内に確保するので呼び出し側は触らない。
    pub def withSceneView(rc: Region[r], body: Unit -> a \ ef):
                           a \ (ef - Dialogue.DialogueView - Inbox - CommandInbox) + r =
        let viewQueue: MutDeque[ViewEvent, r] = MutDeque.empty(rc);
        let commandQueue: MutDeque[Dialogue.CommandText, r] = MutDeque.empty(rc);
        run body() with handler Dialogue.DialogueView {
            def presentLine(line, resume) = {
                MutDeque.pushBack(Line(line#text, line#speaker), viewQueue);
                resume()
            }
            def presentChoices(choices, resume) = {
                let labels = List.map(choice -> choice#text, choices);
                MutDeque.pushBack(Choices(labels), viewQueue);
                resume()
            }
            def dismissLine(resume) = {
                MutDeque.pushBack(Dismiss, viewQueue);
                resume()
            }
            def runCommand(commandText, resume) = {
                MutDeque.pushBack(commandText, commandQueue);
                resume()
            }
            def dialogueComplete(resume) = {
                MutDeque.pushBack(Complete, viewQueue);
                resume()
            }
        } with handler Inbox {
            def takeAll(resume) = resume(drainView(viewQueue, Nil))
        } with handler CommandInbox {
            def takeAllCommands(resume) = resume(drainCommands(commandQueue, Nil))
        }

    /// view キューから先頭 → 末尾の順で全要素を取り出して List で返す（破壊的）。
    def drainView(queue: MutDeque[ViewEvent, r], acc: List[ViewEvent]):
                  List[ViewEvent] \ r =
        match MutDeque.popFront(queue) {
            case Some(event) => drainView(queue, event :: acc)
            case None        => List.reverse(acc)
        }

    /// command キューから先頭 → 末尾の順で全文字列を取り出して List で返す（破壊的）。
    def drainCommands(queue: MutDeque[Dialogue.CommandText, r],
                       acc: List[Dialogue.CommandText]):
                  List[Dialogue.CommandText] \ r =
        match MutDeque.popFront(queue) {
            case Some(text) => drainCommands(queue, text :: acc)
            case None       => List.reverse(acc)
        }
}
