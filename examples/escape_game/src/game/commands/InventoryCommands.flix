/// `<<inv add/remove <id>>>` でインベントリを更新するコマンド群。
///
/// `Game.Inventory.Access` を SoT として書き込み、`inv_has(id)` ビルトインは
/// 同じ Access から読むので状態は一貫する。
mod Game.Commands.InventoryCommands {

    pub def handle(args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Game.Inventory.Access, Dialogue.Session, IO} =
        match args {
            case "add"    :: id :: _ => Game.Inventory.Access.add(id)
            case "remove" :: id :: _ => Game.Inventory.Access.remove(id)
            case action :: Nil       => println("[InventoryCommands] missing item id: ${action}")
            case Nil                 => println("[InventoryCommands] missing action")
            case other :: _          => println("[InventoryCommands] unknown action: ${other}")
        };
        Dialogue.Session.submitCommandDone();
        scene
}
