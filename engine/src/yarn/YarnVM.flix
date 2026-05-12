/// Yarn 仮想マシン本体。
///
/// region rc に閉じた可変領域に住む。step を呼ぶたびに 1 命令進み、結果を `StepResult` で返す。
/// 行・選択肢・コマンドの待機が発生したら waitingState に印を立て、それぞれ
/// `next` / `selectChoice` / `commandComplete` で解除されるまで step は同じ
/// `StepResult` を返し続ける（同じ命令を二重実行しない）。
///
/// エンジン依存なし。
mod Yarn.VM {
    use Yarn.Types.{Value, Instruction, YarnNode, Program, YarnProject, LineRef,
                    ChoiceEntry, CallFrame}
    use Yarn.Types.Value.{BoolV, FloatV, StringV}
    use Yarn.Types.Instruction.{RunLine, AddChoice, ShowChoices, JumpIfFalse, JumpTo,
                                 PeekAndJump, Pop, Return, Stop, PushString, PushFloat, PushBool,
                                 PushVariable, StoreVariable, CallFunc, RunCommand, RunNode, Detour}
    use Yarn.VariableStorage.VariableStorage

    /// step が外部入力待ちで停止しているときの内部マーカー。
    /// `ChoiceEntry` を含むためレコード由来の Eq が無く、自動派生は付けていない。
    enum WaitingState {
        case ForLineNext(LineRef, List[String])
        case ForChoice(List[ChoiceEntry])
        case ForCommandDone(String)
    }

    /// 1 命令進めた結果。Running は連続して step を呼んで進める。
    /// Waiting* は対応する submit が呼ばれるまで再度同じ値を返す。
    pub enum StepResult {
        case Running
        case WaitingLine(LineRef, List[String])
        case WaitingChoice(List[ChoiceEntry])
        case WaitingCommand(String)
        case NodeComplete
        case DialogueComplete
        case Failed(String)
    }

    /// VM の可変状態。region rc にすべて閉じる。
    pub type alias VM[r: Region] = {
        compiledProject    = YarnProject,
        currentNode        = Ref[Option[String], r],
        instructionPointer = Ref[Int32, r],
        stack              = MutDeque[Value, r],
        callStack          = MutDeque[CallFrame, r],
        variables          = Yarn.VariableStorage.VariableStorage[r],
        pendingChoices     = MutDeque[ChoiceEntry, r],
        waitingState       = Ref[Option[WaitingState], r]
    }

    /// startNode から実行開始する VM を作る。
    ///
    /// `variables` は呼び出し側 (`DialogueRunner` / テスト) が所有する共有ストレージ。
    /// VM はこれを **借りる** だけで、自分では作らない。複数の VM が同じ storage を
    /// 共有することで、Session.start の度に変数 ($flag_*, $Yarn.Internal.Visiting.*,
    /// ユーザ定義 $var) がリセットされない、という仕様が型レベルで担保される。
    /// 単体 VM が欲しいだけのテストは `Yarn.VariableStorage.init` で 1 個作って渡す。
    pub def init(rc: Region[r], compiledProject: YarnProject, startNode: String,
                  variables: Yarn.VariableStorage.VariableStorage[r]): VM[r] \ r =
        // 開始ノードの訪問カウンタを 1 増やす（output.json の規約）
        Yarn.VariableStorage.incrementFloat("\$Yarn.Internal.Visiting.${startNode}", variables);
        {
            compiledProject    = compiledProject,
            currentNode        = Ref.fresh(rc, Some(startNode)),
            instructionPointer = Ref.fresh(rc, 0),
            stack              = MutDeque.empty(rc),
            callStack          = MutDeque.empty(rc),
            variables          = variables,
            pendingChoices     = MutDeque.empty(rc),
            waitingState       = Ref.fresh(rc, None)
        }

    /// 1 命令進める。
    /// `callFunc` 命令は `Yarn.Builtins.call` 経由で `Yarn.BuiltinExtension.Access`
    /// を呼ぶ可能性があるため、step の effect chain にも含まれる。
    pub def step(vm: VM[r]): StepResult \ r + Yarn.BuiltinExtension.Access =
        match Ref.get(vm#waitingState) {
            case Some(state) => stateToResult(state)
            case None        => stepInner(vm)
        }

    /// 行表示の完了を通知する（次の step から再開する）。
    pub def next(vm: VM[r]): Unit \ r =
        match Ref.get(vm#waitingState) {
            case Some(WaitingState.ForLineNext(_, _)) => Ref.put(None, vm#waitingState)
            case _                                       => ()
        }

    /// 選択肢の確定。stack に (destination, true) を積んで再開できる状態にする。
    pub def selectChoice(choiceIndex: Int32, vm: VM[r]): Unit \ r =
        match Ref.get(vm#waitingState) {
            case Some(WaitingState.ForChoice(entries)) =>
                match List.nth(choiceIndex, entries) {
                    case Some(entry) =>
                        // 選択結果はスタックに [destination, true] の順で積む。
                        // top（true）を先に jumpIfFalse が peek し、pop の後 peekAndJump が
                        // destination を見る、という Yarn 標準の流れに合わせる。
                        MutDeque.pushBack(FloatV(Int32.toFloat64(entry#destination)), vm#stack);
                        MutDeque.pushBack(BoolV(true), vm#stack);
                        clearDeque(vm#pendingChoices);
                        Ref.put(None, vm#waitingState)
                    case None => ()  // 範囲外は無視
                }
            case _ => ()
        }

    /// コマンド実行完了の通知。
    pub def commandComplete(vm: VM[r]): Unit \ r =
        match Ref.get(vm#waitingState) {
            case Some(WaitingState.ForCommandDone(_)) => Ref.put(None, vm#waitingState)
            case _                                    => ()
        }

    /// vm が現在何らかの Wait* 状態にあるか。
    /// Runner 側が「stale な submit に対応する view イベントを再 emit してしまう」
    /// race を避けるためのガードとして使う。
    pub def isWaiting(vm: VM[r]): Bool \ r =
        Option.nonEmpty(Ref.get(vm#waitingState))

    // ════════════════════════════════════════════════════════════════════════
    // 内部実装
    // ════════════════════════════════════════════════════════════════════════

    def stateToResult(state: WaitingState): StepResult = match state {
        case WaitingState.ForLineNext(lineRef, substitutions) =>
            StepResult.WaitingLine(lineRef, substitutions)
        case WaitingState.ForChoice(entries) =>
            StepResult.WaitingChoice(entries)
        case WaitingState.ForCommandDone(text) =>
            StepResult.WaitingCommand(text)
    }

    def stepInner(vm: VM[r]): StepResult \ r + Yarn.BuiltinExtension.Access =
        match Ref.get(vm#currentNode) {
            case None           => StepResult.DialogueComplete
            case Some(nodeName) =>
                match Map.get(nodeName, vm#compiledProject#program#nodes) {
                    case None       => StepResult.Failed("node not found: ${nodeName}")
                    case Some(node) => stepInNode(node, vm)
                }
        }

    def stepInNode(node: YarnNode, vm: VM[r]): StepResult \ r + Yarn.BuiltinExtension.Access =
        let ip = Ref.get(vm#instructionPointer);
        match Vector.nth(ip, node#instructions) {
            case None              => StepResult.Failed(
                "instruction pointer out of range: ${ip} in ${node#name}")
            case Some(instruction) =>
                Ref.put(ip + 1, vm#instructionPointer);
                executeInstruction(instruction, vm)
        }

    def executeInstruction(instruction: Instruction, vm: VM[r]): StepResult \ r + Yarn.BuiltinExtension.Access =
        match instruction {
            case RunLine(lineRef, substitutionCount) =>
                let substitutions = popSubstitutions(substitutionCount, vm);
                Ref.put(Some(WaitingState.ForLineNext(lineRef, substitutions)),
                        vm#waitingState);
                StepResult.WaitingLine(lineRef, substitutions)

            case AddChoice(lineRef, destination, substitutionCount, hasCondition) =>
                let substitutions = popSubstitutions(substitutionCount, vm);
                let available =
                    if (hasCondition)
                        match MutDeque.popBack(vm#stack) {
                            case Some(BoolV(b)) => b
                            case _              => true   // 条件式が壊れていたら表示を許す
                        }
                    else true;
                MutDeque.pushBack({
                    lineId        = lineRef,
                    substitutions = substitutions,
                    destination   = destination,
                    available     = available
                }, vm#pendingChoices);
                StepResult.Running

            case ShowChoices =>
                let entries = mutDequeToList(vm#pendingChoices);
                Ref.put(Some(WaitingState.ForChoice(entries)), vm#waitingState);
                StepResult.WaitingChoice(entries)

            case JumpIfFalse(destination) =>
                match MutDeque.peekBack(vm#stack) {
                    case Some(BoolV(false)) =>
                        Ref.put(destination, vm#instructionPointer);
                        StepResult.Running
                    case _ => StepResult.Running
                }

            case JumpTo(destination) =>
                Ref.put(destination, vm#instructionPointer);
                StepResult.Running

            case PeekAndJump =>
                match MutDeque.peekBack(vm#stack) {
                    case Some(FloatV(target)) =>
                        match Float64.tryToInt32(target) {
                            case Some(asInt) =>
                                Ref.put(asInt, vm#instructionPointer);
                                StepResult.Running
                            case None =>
                                StepResult.Failed(
                                    "peekAndJump: target ${target} not representable as Int32")
                        }
                    case _ => StepResult.Failed("peekAndJump: top is not Float")
                }

            case Pop =>
                discard MutDeque.popBack(vm#stack);
                StepResult.Running

            case Return =>
                match MutDeque.popBack(vm#callStack) {
                    case None        =>
                        Ref.put(None, vm#currentNode);
                        StepResult.DialogueComplete
                    case Some(frame) =>
                        Ref.put(Some(frame#nodeName), vm#currentNode);
                        Ref.put(frame#returnInstructionPointer, vm#instructionPointer);
                        StepResult.NodeComplete
                }

            case Stop =>
                clearDeque(vm#callStack);
                Ref.put(None, vm#currentNode);
                StepResult.DialogueComplete

            case PushString(value) =>
                MutDeque.pushBack(StringV(value), vm#stack);
                StepResult.Running

            case PushFloat(value) =>
                MutDeque.pushBack(FloatV(value), vm#stack);
                StepResult.Running

            case PushBool(value) =>
                MutDeque.pushBack(BoolV(value), vm#stack);
                StepResult.Running

            case PushVariable(name) =>
                let resolved = match Yarn.VariableStorage.get(name, vm#variables) {
                    case Some(v) => Some(v)
                    case None    => Map.get(name, vm#compiledProject#program#initialValues)
                };
                match resolved {
                    case Some(v) =>
                        MutDeque.pushBack(v, vm#stack);
                        StepResult.Running
                    case None =>
                        StepResult.Failed("variable not found: ${name}")
                }

            case StoreVariable(name) =>
                match MutDeque.peekBack(vm#stack) {
                    case Some(v) =>
                        Yarn.VariableStorage.set(name, v, vm#variables);
                        StepResult.Running
                    case None =>
                        StepResult.Failed("storeVariable: stack empty")
                }

            case CallFunc(name) =>
                executeCallFunc(name, vm)

            case RunCommand(commandText, substitutionCount) =>
                let substitutions = popSubstitutions(substitutionCount, vm);
                let resolvedText = Yarn.StringTable.applySubstitutions(commandText, substitutions);
                Ref.put(Some(WaitingState.ForCommandDone(resolvedText)), vm#waitingState);
                StepResult.WaitingCommand(resolvedText)

            case RunNode(targetNodeName) =>
                // `<<jump>>` 由来: 戻り先を積まずに currentNode を置き換える。
                Ref.put(Some(targetNodeName), vm#currentNode);
                Ref.put(0, vm#instructionPointer);
                Yarn.VariableStorage.incrementFloat(
                    "\$Yarn.Internal.Visiting.${targetNodeName}",
                    vm#variables);
                StepResult.Running

            case Detour(targetNodeName) =>
                // `<<detour>>` 由来: 戻り先を callStack に積んでから移動。
                let returnNode = match Ref.get(vm#currentNode) {
                    case Some(name) => name
                    case None       => ""
                };
                let returnIp = Ref.get(vm#instructionPointer);
                MutDeque.pushBack({
                    nodeName = returnNode,
                    returnInstructionPointer = returnIp
                }, vm#callStack);
                Ref.put(Some(targetNodeName), vm#currentNode);
                Ref.put(0, vm#instructionPointer);
                Yarn.VariableStorage.incrementFloat(
                    "\$Yarn.Internal.Visiting.${targetNodeName}",
                    vm#variables);
                StepResult.Running
        }

    /// `callFunc`: 直前の `pushFloat` で push された数値が引数の個数。
    /// その数値を pop し、その下から N 個 pop して引数列を作り、関数を呼ぶ。
    /// 結果はスタックに push する。
    def executeCallFunc(name: String, vm: VM[r]): StepResult \ r + Yarn.BuiltinExtension.Access =
        match MutDeque.popBack(vm#stack) {
            case Some(FloatV(countAsFloat)) =>
                match Float64.tryToInt32(countAsFloat) {
                    case None =>
                        StepResult.Failed(
                            "callFunc ${name}: bad argument count ${countAsFloat}")
                    case Some(count) =>
                        let arguments = popArguments(count, vm);
                        match Yarn.Builtins.call(name, arguments, vm#variables) {
                            case Ok(result) =>
                                MutDeque.pushBack(result, vm#stack);
                                StepResult.Running
                            case Err(message) =>
                                StepResult.Failed("callFunc ${name}: ${message}")
                        }
                }
            case _ =>
                StepResult.Failed("callFunc ${name}: argument count not on top of stack")
        }

    /// 直前に push された順に pop し、`{0}` `{1}` ... 用の List に並べ替える。
    /// 例: スタックを下から順に [a, b, c] と push した場合（top=c）、
    /// substitutionCount=3 で popSubstitutions すると [a, b, c] が返る。
    def popSubstitutions(count: Int32, vm: VM[r]): List[String] \ r =
        popValuesAsStrings(count, vm) |> List.reverse

    /// 引数列を pop する。`callFunc` 用に「下から順」に並べる。
    /// 例: スタックを下から [a, b, c] と push（top=c）、count=3 で popArguments すると [a, b, c]。
    def popArguments(count: Int32, vm: VM[r]): List[Value] \ r =
        popValues(count, vm) |> List.reverse

    /// スタック top から count 個 pop して、pop した順（top から下へ）の List で返す。
    def popValues(count: Int32, vm: VM[r]): List[Value] \ r =
        if (count <= 0) Nil
        else match MutDeque.popBack(vm#stack) {
            case None        => Nil
            case Some(value) => value :: popValues(count - 1, vm)
        }

    /// `popValues` の結果を文字列に整形（substitutions 用）。
    def popValuesAsStrings(count: Int32, vm: VM[r]): List[String] \ r =
        popValues(count, vm) |> List.map(valueToText)

    def valueToText(value: Value): String = match value {
        case StringV(text) => text
        case BoolV(b)      => if (b) "true" else "false"
        case FloatV(n)     => formatFloat(n)
    }

    /// 整数なら整数表示、小数なら通常の表示。"0.0" ではなく "0" にする
    /// （Yarn の置換で「HPは 0 ある」と表示したいため）。
    def formatFloat(n: Float64): String =
        let asInt = Float64.tryToInt32(n);
        match asInt {
            case Some(i) =>
                if (Int32.toFloat64(i) == n) Int32.toString(i)
                else Float64.toString(n)
            case None => Float64.toString(n)
        }

    /// MutDeque の中身を「先頭から末尾」の List にコピーする（イベント記録向け）。
    def mutDequeToList(deque: MutDeque[a, r]): List[a] \ r =
        MutDeque.toList(deque)

    /// MutDeque を空にする（標準ライブラリに clear が無いので popFront を回す）。
    def clearDeque(deque: MutDeque[a, r]): Unit \ r =
        if (MutDeque.isEmpty(deque)) ()
        else {
            discard MutDeque.popFront(deque);
            clearDeque(deque)
        }
}
