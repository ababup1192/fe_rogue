/// SuspendConfirmScene — 中断確認のモーダルウィンドウ
///
/// 空マスメニューの「中断」確定で `show` が呼ばれ、`TurnPhase.Phase.SuspendConfirm` に入って
/// 画面中央に「本当に中断しますか？ / はい / いいえ」を出す。↑↓ で選択、Z/Enter で確定、X でキャンセル。
///   - はい  → `CustomEffects.SuspendRequest.save`（保存成功でタイトルへ。失敗時は PlayerCursor に留まる）
///   - いいえ → `PlayerCursor` に戻る（中断をやめる）
///
/// モーダル構成: dispatchMenuKey 駆動 + refreshItems で phase 連動 visible（scene ノードで組む）。
///
/// ノード構造（visible のとき）:
///   SuspendConfirm (CanvasLayer, layer=3)
///     └─ panel (Panel, NodeTag.SuspendConfirmPanel)
///           ├─ title (Label2D, NoTag)              ← 「本当に中断しますか？」
///           └─ menu  (ItemList, NodeTag.SuspendConfirmMenu)
mod SuspendConfirmScene {

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/SuspendConfirmScene.scene.json")

    def fontName(): String = "ui"

    def rootName(): String = "SuspendConfirm"
    def panelName(): String = "panel"
    def titleName(): String = "title"
    def menuName(): String = "menu"

    /// B: render-from-World が subtree を描く/隠す root（CanvasLayer）。
    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    def titlePath(): NodePath = rootName() :: panelName() :: titleName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil

    /// `onConfirmed` で分岐する選択肢の識別子。
    def yesMeta(): String = "yes"
    def noMeta(): String  = "no"

    /// 選択肢（上から）: はい / いいえ。
    def menuItems(): List[ItemEntry] =
        ({text = "はい", disabled = false, metadata = Some(yesMeta())}: ItemEntry) ::
        ({text = "いいえ", disabled = false, metadata = Some(noMeta())}: ItemEntry) :: Nil

    /// scene.json 内の "tag" → NodeTag 変換。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                        => Ok(NodeTag.NoTag)
            case Some("NoTag")               => Ok(NodeTag.NoTag)
            case Some("SuspendConfirmPanel") => Ok(NodeTag.SuspendConfirmPanel)
            case Some("SuspendConfirmMenu")  => Ok(NodeTag.SuspendConfirmMenu)
            case Some(unknown)               =>
                Err(JsonCompat.jsonError(Root, Set#{"SuspendConfirmScene tag (got: ${unknown})"}))
        }

    /// scene に SuspendConfirm ノードツリーを追加する（初期は非表示）。`addHudAndDrivers` で呼ぶ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 「中断」確定を受けて確認ダイアログを表示し、`SuspendConfirm` フェーズに入る。
    /// 盤面はそのまま（味方ターン中なので driver は元々動いていない）。
    pub def show(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.SuspendConfirm);
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(true))
            |> Label2D.mapAt(titlePath(), CanvasItem.setVisible(true))
            |> ItemList.mapAt(menuPath(), list ->
                list
                    |> CanvasItem.setVisible(true)
                    |> ItemList.setFocused(true)
                    |> ItemList.setItems(menuItems())
                    |> ItemList.setSelectedIndex(0))

    /// per-node process（ItemList）。phase==SuspendConfirm の間だけ表示・フォーカスを維持する。
    /// 非 SuspendConfirm では非表示にしてカーソルを先頭へ戻す（誤確定防止）。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath, scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag]) \ TurnPhase.State =
        let visible = TurnPhase.State.get() == TurnPhase.Phase.SuspendConfirm;
        let updated = scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(titlePath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                if (visible)
                    list |> CanvasItem.setVisible(true) |> ItemList.setFocused(true) |> ItemList.setItems(menuItems())
                else
                    list |> CanvasItem.setVisible(false) |> ItemList.setFocused(false) |> ItemList.setSelectedIndex(0));
        match Scene.getEngineNode(menuPath(), updated) {
            case Some(latest) => (latest, updated)
            case None         => (node, updated)
        }

    /// Z/Enter 確定。はい → 中断保存要求、いいえ → キャンセル（PlayerCursor へ）。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {CustomEffects.SuspendRequest, GameEngine.Audio, TurnPhase.State} =
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case Some(entry) => onConfirmed(entry, scene)
            case None        => scene
        }

    def onConfirmed(entry: ItemEntry, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {CustomEffects.SuspendRequest, GameEngine.Audio, TurnPhase.State} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                if (m == yesMeta()) {
                    AudioStreamPlayer.play("confirm");
                    // 保存失敗時に確認画面へ留まらないよう先に PlayerCursor へ戻す。
                    // 成功時は handler が GamePhase を Title にして画面ごと作り直すので無害。
                    TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
                    CustomEffects.SuspendRequest.save(scene)
                } else {
                    // cancel() が "cancel" 音と PlayerCursor 復帰を担う。
                    cancel(scene)
                }
        }

    /// 中断をやめて味方ターンのカーソルへ戻る（X / いいえ）。次フレームの refreshItems が非表示にする。
    pub def cancel(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Audio, TurnPhase.State} =
        AudioStreamPlayer.play("cancel");
        TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
        scene
}
