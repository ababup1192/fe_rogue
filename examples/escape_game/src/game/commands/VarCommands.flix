/// `<<flag set/clear <name>>>` で yarn 変数を直接読み書きするコマンド群。
///
/// `$flag_<name>` という命名規約で `Yarn.VariableAccess` の Bool スロットに格納する。
/// yarn 側は `<<if $flag_<name>>>` で読み出す前提。
mod Game.Commands.VarCommands {

    pub def handle(args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Yarn.VariableAccess, Dialogue.Session, IO} =
        match args {
            case "set"   :: name :: _ => Yarn.VariableAccess.setBool("\$flag_${name}", true)
            case "clear" :: name :: _ => Yarn.VariableAccess.setBool("\$flag_${name}", false)
            case action :: Nil        => println("[VarCommands] missing flag name: ${action}")
            case Nil                  => println("[VarCommands] missing action")
            case other :: _           => println("[VarCommands] unknown action: ${other}")
        };
        Dialogue.Session.submitCommandDone();
        scene
}
