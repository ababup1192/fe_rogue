/// セーブ・ロードコマンド: `<<save <slot>>>` と `<<load <slot>>>`。
///
/// - `save <slot>`: 現在ノード名と全変数を `saves/slot{N}.json` に書き出す
/// - `load <slot>`: `Session.restart` で新 VM を建てて旧 VM を破棄
///
/// 失敗時の挙動:
///   - save 失敗 → ログ + submitCommandDone (story を進める)
///   - load 失敗 → ログ + `$_load_failed = true` + submitCommandDone
///                  (story 側で「セーブデータがありません」分岐ができる)
///   - load 成功 → submitCommandDone は呼ばない (新 VM がもう自分の最初の命令まで進んでいる)
mod Game.Commands.SaveCommands {

    pub def handle(name: String, args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Yarn.VariableAccess, Dialogue.Session,
                              Fs.FileRead, Fs.FileWrite, IO} =
        match (name, args) {
            case ("save", slotStr :: _) =>
                match attemptSave(slotStr) {
                    case Ok(_)    => ()
                    case Err(msg) => println("[SaveCommands] ${msg}")
                };
                Dialogue.Session.submitCommandDone();
                scene
            case ("load", slotStr :: _) =>
                match attemptLoad(slotStr) {
                    case Ok(data) =>
                        Dialogue.Session.restart(
                            Game.SaveData.nodeName(data),
                            Game.SaveData.variables(data))
                    case Err(msg) =>
                        println("[SaveCommands] ${msg}");
                        Yarn.VariableAccess.setBool("\$_load_failed", true);
                        Dialogue.Session.submitCommandDone()
                };
                scene
            case _ =>
                println("[SaveCommands] missing slot: ${name}");
                Dialogue.Session.submitCommandDone();
                scene
        }

    /// `<<save N>>` のロジック。失敗時はログ用の文字列を `Err` に詰める。
    /// 各段の `Option` / `Result` を `forM` で 1 列に並べ、ネスト無しで失敗を短絡させる。
    def attemptSave(slotStr: String):
            Result[String, Unit] \ {Yarn.VariableAccess, Fs.FileWrite} =
        forM (
            slot <- Int32.fromString(slotStr)
                      |> Option.toOk("invalid save slot: ${slotStr}");
            node <- Yarn.VariableAccess.currentNode()
                      |> Option.toOk("save: VM not active, skipped");
            _    <- {
                let vars = Yarn.VariableAccess.variableSnapshot();
                let data = Game.SaveData.SaveData.SaveData(node, vars);
                SaveManager.write(slot, data)
                    |> Result.mapErr(error -> "save write failed: ${error}")
            }
        ) yield ()

    /// `<<load N>>` のロジック。成功で `SaveData` を返し、呼び出し元で `Session.restart` に流す。
    /// 失敗時はログ文字列を返す。
    def attemptLoad(slotStr: String):
            Result[String, Game.SaveData.SaveData] \ Fs.FileRead =
        forM (
            slot <- Int32.fromString(slotStr)
                      |> Option.toOk("invalid load slot: ${slotStr}");
            data <- SaveManager.read(slot)
                      |> Option.toOk("load: no save in slot ${slotStr}")
        ) yield data
}
