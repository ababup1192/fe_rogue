/// ControlHintScene のテスト
///
/// `hintFor`: 「フェーズ × いま決定で起きる遷移 → {十字, 決定, キャンセル}ボタンの行き先」を検証する。
/// `renderLine`: 行き先レコードを画面 1 行に整える整形を検証する。どちらも純粋関数なので
/// Scene / Board / effect は一切組み立てない。
///
/// ここで保証したいこと:
///   - 同じ PlayerCursor でも「味方の上 (SelectPlayer)」と「空マス (GatherMenu)」で
///     決定ボタンの行き先が変わる ＝ 文脈依存になっている
///   - 押せば自明な行き先 (メニューの確定・戻る) は案内しない
///   - ボタンは物理キー名 (Z/X) でなく役割名 (十字 / 決定 / キャンセル) で表示する
mod TestControlHintScene {

    use TurnPhase.Phase;
    use TurnRules.Transition;

    /// {dpad, decide, cancel} を 1 回の assertEq で比べられるようタプルにそろえる。
    def toTuple(hint: {dpad = String, decide = String, cancel = String}): (String, String, String) =
        (hint#dpad, hint#decide, hint#cancel)

    // ════════════════════════════════════════════════════════
    // hintFor / PlayerCursor: カーソルの下に味方が居るかで決定が変わる
    // ════════════════════════════════════════════════════════

    /// 味方の上 (decide が SelectPlayer) なら決定は「移動・行動」だけ
    /// (カーソルを十字で動かすのは自明なので十字の案内は出さない)。
    @Test
    def testCursorOnAllyShowsMoveAct(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerCursor, Transition.CursorSelectPlayer(0));
        Assert.assertEq(expected = ("", "移動・行動", ""), toTuple(hint))

    /// 空マスの上 (decide が GatherMenu) なら決定は「メニュー」だけ。
    @Test
    def testCursorOnEmptyShowsMenu(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerCursor, Transition.CursorOpenGatherMenu);
        Assert.assertEq(expected = ("", "メニュー", ""), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // hintFor / PlayerMoving: 味方を選んで動かしている最中
    // ════════════════════════════════════════════════════════

    /// 移動中は決定=行動だけ案内する (移動が十字なのは自明なので十字の案内は出さない)。
    @Test
    def testMovingShowsActionOnly(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerMoving, Transition.MovingOpenActionMenu);
        Assert.assertEq(expected = ("", "行動", ""), toTuple(hint))

    /// 移動中は決定が一瞬無効 (Stay。Tween 中など) になっても表示は固定。
    /// 毎歩「行動」が点滅して見えるのを防ぐため、ここは遷移を見ず常に決定=行動。
    @Test
    def testMovingStaysFixedWhenBlocked(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerMoving, Transition.Stay);
        Assert.assertEq(expected = ("", "行動", ""), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // hintFor / PlayerAttack: 敵の上でだけ決定が「こうげき」
    // ════════════════════════════════════════════════════════

    /// 生きた敵の上 (decide が AttackForecast) なら決定=こうげき・キャンセル=こうげきせず。
    @Test
    def testAttackOnEnemyShowsAttack(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerAttack,
                                             Transition.OpenAttackForecast(0, 0, 0, 0));
        Assert.assertEq(expected = ("", "こうげき", "こうげきせず"), toTuple(hint))

    /// 敵が居ないマス (decide が Stay) では決定を出さず「こうげきせず」だけ案内する。
    @Test
    def testAttackOnEmptyShowsSkipOnly(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerAttack, Transition.Stay);
        Assert.assertEq(expected = ("", "", "こうげきせず"), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // hintFor / メニュー系・入力無効: 自明な決定/キャンセルは案内しない
    // ════════════════════════════════════════════════════════

    /// メニュー表示中 (ActionSelect 等) は項目自体が画面に見えるので案内不要 ＝ 3 ボタンとも空。
    @Test
    def testMenuOpenShowsNothing(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.ActionSelect, Transition.Stay);
        Assert.assertEq(expected = ("", "", ""), toTuple(hint))

    /// ローグ自由移動中は決定=メニューだけ (歩くのが十字なのは自明)。
    @Test
    def testRogueMoveShowsMenuOnly(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.RogueMove, Transition.Stay);
        Assert.assertEq(expected = ("", "メニュー", ""), toTuple(hint))

    /// 敵ターンは入力を受け付けないので 3 ボタンとも空 (帯は隠れる)。
    @Test
    def testEnemyTurnShowsNothing(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.EnemyTurn, Transition.Stay);
        Assert.assertEq(expected = ("", "", ""), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // renderLine: 役割名つきで整形し、空のボタンは省く
    // ════════════════════════════════════════════════════════

    /// 十字と決定がある場合、役割名つきで「／」連結する (物理キー名 Z/X は使わない)。
    @Test
    def testRenderLineJoinsWithButtonNames(): Unit \ Assert =
        let line = ControlHintScene.renderLine({dpad = "移動", decide = "行動", cancel = ""});
        Assert.assertEq(expected = "十字ボタン: 移動 ／ 決定ボタン: 行動", line)

    /// 決定とキャンセルがある場合 (十字は空) は、空のボタンを飛ばして連結する。
    @Test
    def testRenderLineSkipsEmptyDpad(): Unit \ Assert =
        let line = ControlHintScene.renderLine({dpad = "", decide = "こうげき", cancel = "こうげきせず"});
        Assert.assertEq(expected = "決定ボタン: こうげき ／ キャンセルボタン: こうげきせず", line)

    /// すべて空なら空文字 (帯を隠すための合図)。
    @Test
    def testRenderLineAllEmptyIsBlank(): Unit \ Assert =
        let line = ControlHintScene.renderLine({dpad = "", decide = "", cancel = ""});
        Assert.assertEq(expected = "", line)
}
