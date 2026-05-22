/// ActionMenuScene の `applyVisibility` が phase 切替で Panel / ItemList の visible を
/// 仕様どおりに反転することを観測する。
///
/// 検証する観点:
///   - `ActionSelect` 以外のフェーズでは Panel と ItemList のどちらも hidden
///   - `ActionSelect` のときだけ Panel = visible / ItemList = visible + focused
///
/// items の構築 (`buildItems` / `canAttackFrom` / `canWaitOn`) は private 関数なので
/// ここでは直接観測せず、R4 (Menu 基盤共通化) 後に refreshItems 経由で見る方が
/// 構築コストに対するリターンが良い。ここでは visibility 契約だけ pin する。
mod TestActionMenuScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// `ActionMenuScene.add` の {GameEngine.Game, Fs.FileRead} effect を discharge して
    /// pure に見せる test 用ラッパ。`cursorAddPure` と同じ unchecked_cast パターン。
    def actionMenuAddPure(scene: Scene[NodeTag]): Scene[NodeTag] =
        unchecked_cast(
            (run {
                TestUnitFixtures.withMockGame(() -> ActionMenuScene.add(scene))
            } with Fs.FileRead.runWithIO)
            as _ \ {})

    /// Panel と ItemList の (visible, focused) を 1 タプルで観測する。
    /// 親 Panel が hidden になれば子の ItemList も実描画上は出ないが、ここでは
    /// `applyVisibility` が両方明示に setVisible しているかを直接確認する。
    def visibilityState(scene: Scene[NodeTag]): (Bool, Bool, Bool) =
        let panelVisible = match Scene.getEngineNode(ActionMenuScene.panelPath(), scene) {
            case Some(EngineNode.PanelWithState(p, _)) => CanvasItem.isVisible(p)
            case _                                       => bug!("ActionMenu panel not found")
        };
        let (menuVisible, menuFocused) =
            match Scene.getEngineNode(ActionMenuScene.menuPath(), scene) {
                case Some(EngineNode.ItemListWithState(l, _)) =>
                    (CanvasItem.isVisible(l), ItemList.isFocused(l))
                case _ => bug!("ActionMenu ItemList not found")
            };
        (panelVisible, menuVisible, menuFocused)

    // ════════════════════════════════════════════════════════
    // applyVisibility — phase に応じて panel/menu の表示を切り替える
    // ════════════════════════════════════════════════════════

    /// `ActionSelect` 以外のフェーズでは Panel = hidden / ItemList = hidden + 非フォーカス。
    /// PlayerCursor を代表として確認 (他フェーズも同じ「ActionSelect 以外」の集合に入る)。
    @Test
    def testApplyVisibilityHidesPanelOutsideActionSelect(): Unit \ Assert =
        let scene = actionMenuAddPure(Scene.empty());
        let after = ActionMenuScene.applyVisibility(TurnPhase.Phase.PlayerCursor, scene);
        Assert.assertEq(
            expected = (false, false, false),
            visibilityState(after))

    /// `ActionSelect` フェーズでは Panel = visible / ItemList = visible + focused。
    /// メニューに入力フォーカスが当たって engine の MenuEvent が Enter/Escape を拾える状態になる。
    @Test
    def testApplyVisibilityShowsAndFocusesInActionSelect(): Unit \ Assert =
        let scene = actionMenuAddPure(Scene.empty());
        let after = ActionMenuScene.applyVisibility(TurnPhase.Phase.ActionSelect, scene);
        Assert.assertEq(
            expected = (true, true, true),
            visibilityState(after))
}
