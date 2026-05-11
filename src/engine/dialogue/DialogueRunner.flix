/// `Dialog` effect の実装。VM を駆動して、Waiting* に到達したら
/// `DialogueView` の対応する操作を呼ぶ。
///
/// 内部状態は呼び出し元から渡された region に閉じる：
///   - `vmRef`         現在の VM（Option：未開始は None）
///   - `variables`     全 session が共有する変数ストレージ。Session.start で VM を
///                     作り直しても storage の identity は保たれ、`$flag_*`,
///                     `$Yarn.Internal.Visiting.*`, ユーザ定義 `$var` がそのまま
///                     残る。明示的にリセットしたい場合 (タイトル → 最初から、
///                     セーブのロード) は `Session.restart(node, Map.empty())` を
///                     呼ぶと initialValues に戻る。
///
/// 1 つの `submit*` 呼び出しは「VM に状態変化を流し込み、次の Waiting* / 完了
/// まで step を回す」を担う。
///
/// `withRunner` はゲームロジック（`Dialog` を `do` する側）から見ると Dialog を
/// 提供する handler。プレゼンター（`DialogueView`）は上流で別途 handler を積む。
///
/// `commandsAreSynchronous` で `<<command>>` を即完了させるか外部完了通知を待つかを
/// 切替える。本番（gameLoop で CommandInbox を処理する）は `false`。テスト
/// （直接 Runner を駆動する）は `true`。
mod Dialogue.Runner {
    use Yarn.Types.YarnProject
    use Yarn.Types.Value
    use Yarn.Types.Value.{BoolV}
    use Yarn.VM.{StepResult}
    use Yarn.VM.StepResult.{Running, WaitingLine, WaitingChoice, WaitingCommand,
                             NodeComplete, DialogueComplete, Failed}
    use Dialogue.{PresentedLine, PresentedChoice}

    /// 1 命令分の暴走防止に十分な大きい数。
    /// `runUntilWaiting` が同じ submit で 1000 命令以上回ったらバグとみなして打ち切る。
    def maxStepsPerSubmit(): Int32 = 1000

    /// `Session` effect を実装する handler。
    /// 呼び出し元は `region rc { withRunner(rc, compiledProject, syncCommands, () -> ...) ... }` で使う。
    /// body の中で `do Session.start("Start")` などが呼べるようになる。
    ///
    /// `syncCommands = true` で `<<command>>` を即完了扱い（外部 `submitCommandDone`
    /// を待たない）。テストで gameLoop なしに Runner を直接駆動する場合に使う。
    /// 本番は `false`。コマンドは `DialogueView.runCommand` で view 側に積まれ、
    /// 外部ルータが完了タイミングで `Session.submitCommandDone` を呼ぶ。
    pub def withRunner(rc: Region[r], compiledProject: YarnProject,
                        syncCommands: Bool, body: Unit -> a \ ef):
                        a \ (ef - Dialogue.Session - Yarn.VariableAccess)
                          + Dialogue.DialogueView
                          + Yarn.BuiltinExtension.Access + r =
        let vmRef: Ref[Option[Yarn.VM.VM[r]], r] = Ref.fresh(rc, None);
        // 全 session が共有する変数ストレージ。VM が破棄されても残るので、
        // Session.start を繰り返しても `$flag_*` や `visited_count(...)` が
        // 維持される。リセットしたければ `Session.restart` で initialValues に戻す。
        let variables = Yarn.VariableStorage.init(rc, compiledProject#program#initialValues);
        run body() with handler Yarn.VariableAccess {

            def setBool(name, value, resume) = {
                Yarn.VariableStorage.set(name, BoolV(value), variables);
                resume()
            }

            def getBool(name, resume) = {
                let result = match Yarn.VariableStorage.get(name, variables) {
                    case Some(BoolV(b)) => Some(b)
                    case _              => None
                };
                resume(result)
            }

            def currentNode(resume) =
                resume(match Ref.get(vmRef) {
                    case Some(vm) => Ref.get(vm#currentNode)
                    case None     => None
                })

            def variableSnapshot(resume) =
                resume(Yarn.VariableStorage.toMap(variables))
        } with handler Dialogue.Session {

            def start(nodeName, resume) = {
                // 共有 storage を渡すだけ。前 session の変数はそのまま。
                // (visit tracker の +1 は `Yarn.VM.init` 内で実行される)
                let vm = Yarn.VM.init(rc, compiledProject, nodeName, variables);
                Ref.put(Some(vm), vmRef);
                runUntilWaiting(vm, compiledProject, syncCommands, maxStepsPerSubmit());
                resume()
            }

            def stop(resume) = {
                Ref.put(None, vmRef);
                Dialogue.DialogueView.dialogueComplete();
                resume()
            }

            def isActive(resume) =
                // VM が起動済みかつ currentNode を持つ (= まだ DialogueComplete に
                // 到達していない) ときだけ active 扱いにする。VM が return/stop で
                // currentNode を None にした後は idle として扱い、探索モードの
                // クリック判定など外側の入力処理を許可する。
                resume(match Ref.get(vmRef) {
                    case None     => false
                    case Some(vm) => Option.nonEmpty(Ref.get(vm#currentNode))
                })

            def submitNext(resume) =
                match Ref.get(vmRef) {
                    case Some(vm) => {
                        Yarn.VM.next(vm);
                        runUntilWaiting(vm, compiledProject, syncCommands, maxStepsPerSubmit());
                        resume()
                    }
                    case None => resume()
                }

            def submitSelect(choiceIndex, resume) =
                match Ref.get(vmRef) {
                    case Some(vm) => {
                        Yarn.VM.selectChoice(choiceIndex, vm);
                        runUntilWaiting(vm, compiledProject, syncCommands, maxStepsPerSubmit());
                        resume()
                    }
                    case None => resume()
                }

            def submitCommandDone(resume) =
                match Ref.get(vmRef) {
                    case Some(vm) => {
                        Yarn.VM.commandComplete(vm);
                        runUntilWaiting(vm, compiledProject, syncCommands, maxStepsPerSubmit());
                        resume()
                    }
                    case None => resume()
                }

            def restart(nodeName, savedVars, resume) = {
                // 共有 storage を initialValues に戻してから savedVars を上書き。
                // 「タイトル → 最初から」は `restart(start, Map.empty())` で十分。
                // セーブのロードは `restart(savedNode, savedVars)` で完全復元される。
                // VM 作成は initialValues 復元後に行う（init が visit tracker を
                // +1 するので、savedVars に同 tracker が入っていれば +1 だけずれる
                // 余地があるが、savedVars が「ロード後に再入場した状態」を表すなら
                // セーブ時点から見て「+1 増えている」のが正しい）。
                Yarn.VariableStorage.reset(variables, compiledProject#program#initialValues);
                Map.forEach((name, value) ->
                    Yarn.VariableStorage.set(name, value, variables), savedVars);
                let vm = Yarn.VM.init(rc, compiledProject, nodeName, variables);
                Ref.put(Some(vm), vmRef);
                runUntilWaiting(vm, compiledProject, syncCommands, maxStepsPerSubmit());
                resume()
            }
        }

    /// VM を 1 つの Waiting* / DialogueComplete に到達するまで step し続ける。
    /// 行・選択肢・コマンドそれぞれに対応する DialogueView 操作を呼ぶ。
    /// VM の暴走を防ぐため最大ステップ数で打ち切る。
    /// `syncCommands = true` のときは `<<command>>` を即完了扱いにして次の命令へ進める。
    ///
    /// 入口でガード: vm が既に Wait* 状態なら何もせず return する。
    /// これは「既に対応する view イベントは前回 emit 済み」だから。ガード無しだと、
    /// stale な submit*（rapid click による二重 submitSelect、WaitQueue 期限切れ後の
    /// submitCommandDone が vm の進んだ先に追いつかない、等）が `vm.step` 経由で
    /// 既存の WaitingState をそのまま返し、`presentLine`/`runCommand` などが二重に
    /// queue へ積まれる = UI 上の行重複や SE 二重再生を起こす。
    def runUntilWaiting(vm: Yarn.VM.VM[r], compiledProject: YarnProject,
                         syncCommands: Bool, remaining: Int32):
                         Unit \ Dialogue.DialogueView
                              + Yarn.BuiltinExtension.Access + r =
        if (Yarn.VM.isWaiting(vm)) ()
        else if (remaining <= 0)
            Dialogue.DialogueView.dialogueComplete()
        else
            match Yarn.VM.step(vm) {
                case Running          => runUntilWaiting(vm, compiledProject, syncCommands, remaining - 1)
                case NodeComplete     => runUntilWaiting(vm, compiledProject, syncCommands, remaining - 1)
                case WaitingLine(lineId, substitutions) =>
                    let line = resolveLine(lineId, substitutions, compiledProject);
                    Dialogue.DialogueView.presentLine(line)
                case WaitingChoice(entries) =>
                    let choices = entriesToChoices(entries, compiledProject);
                    Dialogue.DialogueView.presentChoices(choices)
                case WaitingCommand(commandText) => {
                    Dialogue.DialogueView.runCommand(commandText);
                    if (syncCommands) {
                        Yarn.VM.commandComplete(vm);
                        runUntilWaiting(vm, compiledProject, syncCommands, remaining - 1)
                    } else ()
                }
                case DialogueComplete =>
                    Dialogue.DialogueView.dialogueComplete()
                case Failed(_message) =>
                    // メッセージのロギング層は次フェーズで足す。
                    Dialogue.DialogueView.dialogueComplete()
            }

    /// `Yarn.VM` の ChoiceEntry から view 用の PresentedChoice に整形する。
    /// 表示テキストは StringTable で行 ID を引いて置換解決する。
    def entriesToChoices(entries: List[Yarn.Types.ChoiceEntry], compiledProject: YarnProject):
                            List[PresentedChoice] =
        let toChoice = pair -> {
            let (index, entry) = pair;
            let text = match Yarn.StringTable.resolve(
                            entry#lineId, entry#substitutions, compiledProject#strings) {
                case Ok(resolved) => resolved
                case Err(_)       => entry#lineId
            };
            ({ index = index, text = text, available = entry#available }: PresentedChoice)
        };
        let indexed = List.zip(List.range(0, List.length(entries)), entries);
        List.map(toChoice, indexed)

    /// 行 ID と置換から view 用の PresentedLine に整形する。
    /// 話者は `Dialogue.extractSpeaker`（半角コロン区切り）で抽出する。
    /// 別の表記法を採るシナリオでは、Runner を別実装にするか手前で正規化すること。
    def resolveLine(lineId: String, substitutions: List[String], compiledProject: YarnProject):
                     PresentedLine =
        let text = match Yarn.StringTable.resolve(lineId, substitutions, compiledProject#strings) {
            case Ok(resolved) => resolved
            case Err(_)       => lineId
        };
        { lineId = lineId, text = text, speaker = Dialogue.extractSpeaker(text) }
}
