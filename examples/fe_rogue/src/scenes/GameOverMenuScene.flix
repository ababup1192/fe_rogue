/// GameOverMenuScene — 全滅時のモーダル選択ウィンドウ
///
/// 全滅（`CustomEffects.GameOverRequest.request`）で `freezeAndShow` が呼ばれ、盤面をフリーズして
/// `TurnPhase.Phase.GameOver` に入り、画面中央に「最初から / そのフロアの最初から」を出す。
/// ↑↓ で選択、Z/Enter で確定。確定すると `CustomEffects.GameOverRequest` の restart op を emit して
/// run を再構築する。X（キャンセル）は無反応（必ずどちらか選ばせる）。
///
/// ノード構造（visible のとき）:
///   GameOverMenu (CanvasLayer, layer=3)  ← ActionMenu(2) よりさらに手前
///     └─ panel (Panel, NodeTag.GameOverPanel)
///           └─ menu (ItemList, NodeTag.GameOverMenu)
mod GameOverMenuScene {

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/GameOverMenuScene.scene.json")

    def fontName(): String = "ui"

    def rootName(): String = "GameOverMenu"
    def panelName(): String = "panel"
    def menuName(): String = "menu"

    /// B: render-from-World が HUD/メニューサブツリーを描く/隠す root。
    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil

    /// `onConfirmed` で分岐する選択肢の識別子。
    def goddessMeta(): String   = "goddess"
    def floorMeta(): String     = "floor"
    def beginningMeta(): String = "beginning"

    /// 選択肢（上から）: 女神の加護（完全復活）/ そのフロアの最初から / 最初から。常に全て出す。
    /// 「そのフロアの最初から」「女神の加護」はスナップショット未保存でも各 handler 側で
    /// `resetForGameOver` にフォールバックする。
    def menuItems(): List[ItemEntry] =
        ({text = "女神の加護（その場復活）", disabled = false, metadata = Some(goddessMeta())}: ItemEntry) ::
        ({text = "フロアの最初から", disabled = false, metadata = Some(floorMeta())}: ItemEntry) ::
        ({text = "最初から", disabled = false, metadata = Some(beginningMeta())}: ItemEntry) :: Nil

    /// scene.json 内の "tag" → NodeTag 変換。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("GameOverPanel") => Ok(NodeTag.GameOverPanel)
            case Some("GameOverMenu")  => Ok(NodeTag.GameOverMenu)
            case Some(unknown)         =>
                Err(JsonCompat.jsonError(Root, Set#{"GameOverMenuScene tag (got: ${unknown})"}))
        }

    /// scene に GameOverMenu ノードツリーを追加する（初期は非表示）。`buildPlayingScene` /
    /// `rebuildFloorFromSnapshot` の UI 群末尾で呼ぶ。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 全滅を受けて盤面をフリーズし、メニューを表示する。
    ///   - 敵ターンキューを空にして以後の敵 step を止める
    ///   - フェーズを GameOver にして全 driver / 入力ルーティングを no-op 化
    ///   - 進行中アニメ（攻撃 lunge / 死亡演出）を一括キャンセル
    ///   - Panel / ItemList を表示・フォーカス・項目セット
    pub def freezeAndShow(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {EnemyTurn.Queue, TurnPhase.State, AnimationPlayer.Scheduler} =
        EnemyTurn.Queue.replace(Nil);
        TurnPhase.State.put(TurnPhase.Phase.GameOver);
        AnimationPlayer.Scheduler.cancelAll();
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(true))
            |> ItemList.mapAt(menuPath(), list ->
                list
                    |> CanvasItem.setVisible(true)
                    |> ItemList.setFocused(true)
                    |> ItemList.setItems(menuItems())
                    |> ItemList.setSelectedIndex(0))

    /// per-node process（ItemList）。phase==GameOver の間だけ表示・フォーカスを維持する。
    /// 非 GameOver では非表示にしてカーソルを先頭へ戻す（誤確定防止）。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath, scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag]) \ World.PhaseQuery =
        // F2c: GameOver 可視判定を World 由来へ flip（純 3-case ＝ TurnPhase.State 依存を丸ごと置換）。
        let visible = World.PhaseQuery.phase() == SimPhase.GameOver;
        let updated = scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                if (visible)
                    list |> CanvasItem.setVisible(true) |> ItemList.setFocused(true) |> ItemList.setItems(menuItems())
                else
                    list |> CanvasItem.setVisible(false) |> ItemList.setFocused(false) |> ItemList.setSelectedIndex(0));
        match Scene.getEngineNode(menuPath(), updated) {
            case Some(latest) => (latest, updated)
            case None         => (node, updated)
        }

    /// Z/Enter 確定。現在カーソル位置の選択肢を確定し、対応する restart を emit する。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {CustomEffects.GameOverRequest, GameEngine.Audio} =
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case Some(entry) => onConfirmed(entry, scene)
            case None        => scene
        }

    /// 選択肢の metadata で restart 種別を分岐して emit する。
    def onConfirmed(entry: ItemEntry, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {CustomEffects.GameOverRequest, GameEngine.Audio} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                AudioStreamPlayer.play("confirm");
                if (m == goddessMeta())         CustomEffects.GameOverRequest.reviveInPlace(scene)
                else if (m == floorMeta())      CustomEffects.GameOverRequest.restartFloor(scene)
                else if (m == beginningMeta())  CustomEffects.GameOverRequest.restartBeginning(scene)
                else                            scene
        }
}
