/// メッセージウィンドウシーン（タイプライター演出つき）。
/// 全シーン常駐設計。`process` で GamePhase を読み:
///   - ルート Panel: Title 以外で visible=true
///   - RichTextLabel: phase に応じてメッセージを差し替え + visibleCharacters を毎フレーム +1
///
/// メッセージ切替は「現在の RichTextLabel.text と phase 期待値の比較」で検出する。
/// 異なれば setText + visibleCharacters=0 でタイプライターを最初からやり直す。
/// 同じテキストなら typewriter 進行（+1/frame、60fps で 60 文字/秒）。
mod MessageScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    def sceneJsonPath(): String = "src/scenes/MessageScene.scene.json"

    pub def name(): String = "message_panel"
    pub def textName(): String = "text"
    /// Panel の絶対パス。 battle CanvasLayer 配下の ui_layer の child として配置される。
    pub def panelPath(): NodePath = BattleScene.uiLayerPath() ::: name() :: Nil
    pub def textPath(): NodePath = panelPath() ::: textName() :: Nil

    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("MessagePanel")  => Ok(NodeTag.MessagePanel)
            case Some("MessageBox")    => Ok(NodeTag.MessageBox)
            case Some(unknown)         => Err(JsonError(Root, Set#{"MessageScene tag (got: ${unknown})"}))
        }

    pub def add(fontAtlas: FontAtlas, scene: Scene[NodeTag]):
                Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        SceneLoader.loadSceneWithFontAt(BattleScene.uiLayerPath(), sceneJsonPath(),
                                        fontAtlas, tagParser, scene)

    /// GamePhase + BattleState から表示するメッセージを生成する。
    /// 空文字 ("") は「メッセージなし」 (Title 中 / コマンド選択中 / じゅもん選択中など)。
    /// Resolving / EnemyActing では lastAction.kind で文体を分岐する。
    pub def messageFor(phase: GamePhase, state: BattleScene.State): String =
        match phase {
            case GamePhase.Title         => ""
            case GamePhase.CommandSelect => ""
            case GamePhase.SpellSelect   => ""
            case GamePhase.ItemSelect    => ""
            case GamePhase.Resolving     => actionMessage(false, state#lastAction)
            case GamePhase.EnemyActing   => actionMessage(true, state#lastAction)
            case GamePhase.Victory       =>
                "${state#enemy#name}を たおした！\nEnter キーで タイトルへ"
            case GamePhase.Defeat        =>
                "${state#hero#name}は ちからつきた…\nEnter キーで タイトルへ"
        }

    /// `ActionResult` 1 件からメッセージ文を組み立てる。 kind で文体を分岐:
    ///   - Attack       : 「X は Y に こうげき！\nY に N の ダメージ！」
    ///   - SpellDamage  : 「X の メラ！\nY に N の ダメージ！」  (actor が「X の メラ！」 形式)
    ///   - SpellHeal    : 「X の ホイミ！\nX の HP が N 回復！」
    ///   - Insufficient : 「X は メラを となえた！\nしかし MP が たりない！」
    def actionMessage(byEnemy: Bool, lastAction: Option[BattleScene.ActionResult]): String =
        match lastAction {
            case None => ""
            case Some(a) =>
                match a#kind {
                    case BattleScene.ActionKind.Attack =>
                        if (byEnemy)
                            // 敵ターン: 「スライムの こうげき！」 (DQ 文体)
                            "${a#actor}の こうげき！\n${a#target}に ${a#damage} の ダメージ！"
                        else
                            // プレイヤーターン: 「ゆうしゃは スライムに こうげき！」
                            "${a#actor}は ${a#target}に こうげき！\n${a#target}に ${a#damage} の ダメージ！"
                    case BattleScene.ActionKind.SpellDamage =>
                        "${a#actor}\n${a#target}に ${a#damage} の ダメージ！"
                    case BattleScene.ActionKind.SpellHeal =>
                        "${a#actor}\n${a#target}の HP が ${a#damage} 回復！"
                    case BattleScene.ActionKind.Insufficient =>
                        "${a#actor}\nしかし MP が たりない！"
                }
        }

    /// メッセージ表示が完了しているか（テキストが空 or visibleCharacters が totalCharCount に達した）。
    /// InputHandler から「タイプライター中 Enter は早送り、完了済み Enter は次フェーズへ」 を判定するために公開。
    pub def isComplete(scene: Scene[NodeTag]): Bool =
        match Scene.getEngineNode(textPath(), scene) {
            case Some(EngineNode.RichTextLabelWithState(label, _)) =>
                let total = RichTextLabel.totalCharCount(label);
                let vc = RichTextLabel.getVisibleCharacters(label);
                total == 0 or vc < 0 or vc >= total
            case _ => true
        }

    /// タイプライターを完了状態に飛ばす（Enter 早送り用）。
    pub def skipTypewriter(scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(textPath(), node -> match node {
            case EngineNode.RichTextLabelWithState(label, tag) =>
                let total = RichTextLabel.totalCharCount(label);
                EngineNode.RichTextLabelWithState(
                    RichTextLabel.setVisibleCharacters(total, label), tag)
            case other => other
        }, scene)

    /// フェーズ遷移時に呼ばれる Push モデルの visibility 適用関数。
    /// メッセージが必要なフェーズ（Resolving / EnemyActing / Victory / Defeat）でだけ visible。
    pub def applyVisibility(phase: GamePhase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = match phase {
            case GamePhase.Resolving   => true
            case GamePhase.EnemyActing => true
            case GamePhase.Victory     => true
            case GamePhase.Defeat      => true
            case _                     => false
        };
        Scene.mapEngineNode(panelPath(), node -> match node {
            case EngineNode.PanelWithState(panel, tag) =>
                EngineNode.PanelWithState(CanvasItem.setVisible(visible, panel), tag)
            case other => other
        }, scene)

    /// RichTextLabel (MessageBox) に対する process。
    /// 期待メッセージと現在の text を比較し、差分があれば setText + visibleCharacters=0、
    /// 一致していれば visibleCharacters を +1（タイプライター進行）。
    pub def processBox(_delta: Duration.Duration, node: EngineNode[NodeTag],
                       _path: NodePath,
                       scene: Scene[NodeTag]): (EngineNode[NodeTag], Scene[NodeTag]) \ GamePhaseState =
        match node {
            case EngineNode.RichTextLabelWithState(label, NodeTag.MessageBox) =>
                let expected = messageFor(GamePhaseState.get(), BattleScene.readState(scene));
                let current = RichTextLabel.getText(label);
                let updated =
                    if (current != expected)
                        label
                            |> RichTextLabel.setText(expected)
                            |> RichTextLabel.setVisibleCharacters(0)
                    else {
                        let total = RichTextLabel.totalCharCount(label);
                        let vc = RichTextLabel.getVisibleCharacters(label);
                        let next = if (vc < 0) total
                                   else if (vc >= total) total
                                   else vc + 1;
                        RichTextLabel.setVisibleCharacters(next, label)
                    };
                (EngineNode.RichTextLabelWithState(updated, NodeTag.MessageBox), scene)
            case _ => (node, scene)
        }
}
