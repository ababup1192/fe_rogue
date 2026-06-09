/// ControlHintScene のテスト
///
/// `hintFor`: 「フェーズ × いま決定で起きる遷移 → {十字, 決定}ボタンの行き先」を検証する。
/// `renderLine`: 行き先レコードを画面 1 行に整える整形を検証する。どちらも純粋関数なので
/// Scene / Board / effect は一切組み立てない。
///
/// ここで保証したいこと:
///   - 同じ PlayerCursor でも「味方の上 (SelectPlayer)」と「空マス (GatherMenu)」で
///     決定ボタンの行き先が変わる ＝ 文脈依存になっている
///   - 押せば自明な行き先 (メニューの確定・戻る) は案内しない
///   - ボタンは物理キー名 (Z/X) でなく役割名 (十字 / 決定) で表示する
///     （キャンセルの案内は出さない方針になったので cancel は持たない）
mod TestControlHintScene {

    use TurnPhase.Phase;
    use TurnRules.Transition;

    /// {dpad, decide} を 1 回の assertEq で比べられるようタプルにそろえる。
    def toTuple(hint: {dpad = String, decide = String}): (String, String) =
        (hint#dpad, hint#decide)

    // ════════════════════════════════════════════════════════
    // hintFor / PlayerCursor: カーソルの下に味方が居るかで決定が変わる
    // ════════════════════════════════════════════════════════

    /// 味方の上 (decide が SelectPlayer) なら決定は「移動・行動」だけ
    /// (カーソルを十字で動かすのは自明なので十字の案内は出さない)。
    @Test
    def testCursorOnAllyShowsMoveAct(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerCursor, Transition.CursorSelectPlayer(0));
        Assert.assertEq(expected = ("", "移動・行動"), toTuple(hint))

    /// 空マスの上 (decide が GatherMenu) なら決定は「メニュー」だけ。
    @Test
    def testCursorOnEmptyShowsMenu(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerCursor, Transition.CursorOpenGatherMenu);
        Assert.assertEq(expected = ("", "メニュー"), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // hintFor / PlayerMoving: 味方を選んで動かしている最中
    // ════════════════════════════════════════════════════════

    /// 移動中は決定=行動だけ案内する (移動が十字なのは自明なので十字の案内は出さない)。
    @Test
    def testMovingShowsActionOnly(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerMoving, Transition.MovingOpenActionMenu);
        Assert.assertEq(expected = ("", "行動"), toTuple(hint))

    /// 移動中は決定が一瞬無効 (Stay。Tween 中など) になっても表示は固定。
    /// 毎歩「行動」が点滅して見えるのを防ぐため、ここは遷移を見ず常に決定=行動。
    @Test
    def testMovingStaysFixedWhenBlocked(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerMoving, Transition.Stay);
        Assert.assertEq(expected = ("", "行動"), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // hintFor / PlayerAttack: 敵の上でだけ決定が「こうげき」
    // ════════════════════════════════════════════════════════

    /// 生きた敵の上 (decide が AttackForecast) なら ←・→ で対象変更 ＋ 決定=こうげき。
    /// (キャンセルの案内は出さない)。
    @Test
    def testAttackOnEnemyShowsAttack(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerAttack,
                                             Transition.OpenAttackForecast(0, 0, 0, 0));
        Assert.assertEq(expected = ("←・→: 攻撃対象の変更", "こうげき"), toTuple(hint))

    /// 敵が居ないマス (decide が Stay) でも ←・→ の対象変更案内は出す（決定は出さない）。
    @Test
    def testAttackOnEmptyShowsTargetChangeOnly(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.PlayerAttack, Transition.Stay);
        Assert.assertEq(expected = ("←・→: 攻撃対象の変更", ""), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // hintFor / メニュー系・入力無効: 自明な決定は案内しない
    // ════════════════════════════════════════════════════════

    /// メニュー表示中 (ActionSelect 等) は項目自体が画面に見えるので案内不要 ＝ 両ボタンとも空。
    @Test
    def testMenuOpenShowsNothing(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.ActionSelect, Transition.Stay);
        Assert.assertEq(expected = ("", ""), toTuple(hint))

    /// ローグ自由移動中は決定=メニューだけ (歩くのが十字なのは自明)。
    @Test
    def testRogueMoveShowsMenuOnly(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.RogueMove, Transition.Stay);
        Assert.assertEq(expected = ("", "メニュー"), toTuple(hint))

    /// 敵ターンは入力を受け付けないので両ボタンとも空 (帯は隠れる)。
    @Test
    def testEnemyTurnShowsNothing(): Unit \ Assert =
        let hint = ControlHintScene.hintFor(Phase.EnemyTurn, Transition.Stay);
        Assert.assertEq(expected = ("", ""), toTuple(hint))

    // ════════════════════════════════════════════════════════
    // renderLine: 役割名つきで整形し、空のボタンは省く
    // ════════════════════════════════════════════════════════

    /// 十字(整形済み)と決定がある場合、「／」連結する。dpad は整形済みをそのまま使う。
    @Test
    def testRenderLineJoinsWithButtonNames(): Unit \ Assert =
        let line = ControlHintScene.renderLine({dpad = "十字ボタン: 移動", decide = "行動"});
        Assert.assertEq(expected = "十字ボタン: 移動 ／ 決定ボタン: 行動", line)

    /// 十字が空・決定だけの場合は、空のボタンを飛ばして決定だけ出す。
    @Test
    def testRenderLineSkipsEmptyDpad(): Unit \ Assert =
        let line = ControlHintScene.renderLine({dpad = "", decide = "こうげき"});
        Assert.assertEq(expected = "決定ボタン: こうげき", line)

    /// すべて空なら空文字 (帯を隠すための合図)。
    @Test
    def testRenderLineAllEmptyIsBlank(): Unit \ Assert =
        let line = ControlHintScene.renderLine({dpad = "", decide = ""});
        Assert.assertEq(expected = "", line)
}
