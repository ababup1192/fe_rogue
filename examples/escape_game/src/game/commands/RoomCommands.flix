/// 部屋遷移コマンド: `<<room enter <id>>>`。
///
/// `RoomState` の roomId とホットスポット状態テーブルを `RoomCatalog` の初期値で
/// 再構築し、`RoomScene` の背景 Sprite + ホットスポット Area2D も差し替える。
/// catalog に無い id でも `RoomScene.enter` 側で「空っぽ部屋」に整合するので
/// クラッシュさせない。
mod Game.Commands.RoomCommands {

    pub def handle(args: List[String], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {Game.RoomState.Access, Dialogue.Session, IO} =
        match args {
            case "enter" :: roomId :: _ =>
                let initialHs = Game.RoomCatalog.initialHotspots(roomId);
                Game.RoomState.Access.enter(roomId, initialHs);
                let next = RoomScene.enter(roomId, scene);
                Dialogue.Session.submitCommandDone();
                next
            case "enter" :: Nil =>
                println("[RoomCommands] missing room id");
                Dialogue.Session.submitCommandDone();
                scene
            case Nil =>
                println("[RoomCommands] missing action");
                Dialogue.Session.submitCommandDone();
                scene
            case other :: _ =>
                println("[RoomCommands] unknown action: ${other}");
                Dialogue.Session.submitCommandDone();
                scene
        }
}
