/// TurnRules.decide のテスト
///
/// `Phase × Input × Board × ... → Transition` の遷移表を Board だけ合成して検証する。
/// Scene[NodeTag] / Tween / 各 effect は一切組み立てない（純粋関数なので必要ない）。
///
/// ここでは「どんな状況で何が起きるか」だけを保証する:
///   - PlayerCursor で味方マスを Z → SelectPlayer
///   - PlayerCursor で空マスを Z → CursorOpenGatherMenu (ActionMenu「しゅうごう」)
///   - PlayerCursor で waited 味方上を Z → Stay（findActiveIdAt が None で、Occupied なので flag も立たない）
///   - PlayerMoving で busy 中の Z / X は Stay（Tween 完了待ちガード）
///   - PlayerAttack で生きてる敵上を Z → AttackHit
///   - PlayerAttack で死亡演出中の敵上を Z → Stay
///   - 入力無効フェーズ（EnemyTurn / PlayerAutoMove）はどんな入力でも Stay
mod TestTurnRules {

    // ════════════════════════════════════════════════════════
    // 共通フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 全マス床の MapSnapshot（5×5）。range 外は壁扱い。
    /// moduleOfCell は使わない（TurnRules は使わない）が record 完備のため None を返す。
    def emptySnapshot(): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < 5 and c#y >= 0 and c#y < 5;
        {
            tileSize     = 16.0,
            usedRect     = {position = Vec2i.zero(), size = ({x = 5, y = 5}: {x = Int32, y = Int32})},
            isWall       = c -> not inB(c),
            isFloor      = c -> inB(c),
            mapToLocal   = _ -> Vec2.zero(),
            gridToWorld  = _ -> Vec2.zero(),
            moduleOfCell = _ -> None
        }

    /// (3, 2) だけ壁、それ以外は床の 5×5 スナップショット
    def wallAtSnapshot(): MapSnapshot =
        let inB = c -> c#x >= 0 and c#x < 5 and c#y >= 0 and c#y < 5;
        let isW = c -> c#x == 3 and c#y == 2;
        {
            tileSize     = 16.0,
            usedRect     = {position = Vec2i.zero(), size = ({x = 5, y = 5}: {x = Int32, y = Int32})},
            isWall       = c -> not inB(c) or isW(c),
            isFloor      = c -> inB(c) and not isW(c),
            mapToLocal   = _ -> Vec2.zero(),
            gridToWorld  = _ -> Vec2.zero(),
            moduleOfCell = _ -> None
        }

    /// 味方 1 人 + 敵 1 体の Board を組む
    def boardWith(player: {x = Int32, y = Int32}, enemy: {x = Int32, y = Int32}): Board =
        {
            map    = emptySnapshot(),
            pieces = (Piece.Player(0), player) :: (Piece.Enemy(0), enemy) :: Nil
        }

    /// 味方 1 人だけの Board（敵なし）
    def boardWithPlayerOnly(player: {x = Int32, y = Int32}): Board =
        {
            map    = emptySnapshot(),
            pieces = (Piece.Player(0), player) :: Nil
        }

    /// (3, 2) 壁の Board に味方 1 人を置く
    def boardWithWall(player: {x = Int32, y = Int32}): Board =
        {
            map    = wallAtSnapshot(),
            pieces = (Piece.Player(0), player) :: Nil
        }

    /// 全要素埋めた Context をデフォルト値で組み立てる。
    /// 各テストは `{ phase = ..., input = ..., ... | ctx }` で必要箇所だけ上書きする。
    def baseContext(board: Board, cursor: {x = Int32, y = Int32}): TurnRules.Context =
        {
            phase           = TurnPhase.Phase.PlayerCursor,
            input           = TurnRules.Input.Confirm,
            board           = board,
            cursor          = cursor,
            selected        = None,
            waitedPlayerIds = Nil,
            dyingEnemyIds   = Nil,
            playerBusy      = false
        }

    def cell(x: Int32, y: Int32): {x = Int32, y = Int32} = {x = x, y = y}

    // ════════════════════════════════════════════════════════
    // PlayerCursor + Confirm: 味方を選択 / 集合メニューを開く / 何もしない
    // ════════════════════════════════════════════════════════

    /// 味方が居るマスで Z → その味方を選択（PlayerMoving に向かう）
    @Test
    def testCursorConfirmOnActiveAllySelectsThatPlayer(): Unit \ Assert =
        let context = baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2));
        Assert.assertEq(
            expected = TurnRules.Transition.CursorSelectPlayer(0),
            TurnRules.decide(context))

    /// 駒が居ない床マスで Z → 空マスメニュー (ActionMenu「しゅうごう / ターンエンド」) を開く。
    @Test
    def testCursorConfirmOnEmptyFloorOpensGatherMenu(): Unit \ Assert =
        let context = baseContext(boardWithPlayerOnly(cell(0, 0)), cell(2, 2));
        Assert.assertEq(
            expected = TurnRules.Transition.CursorOpenGatherMenu,
            TurnRules.decide(context))

    /// 待機済み（waited）の味方上で Z → アクティブ味方が居ないのでメニューを開く。
    /// (しゅうごうはロード合流するだけなので、占有マスでもメニュー自体は開ける。)
    @Test
    def testCursorConfirmOnWaitedAllyOpensGatherMenu(): Unit \ Assert =
        let context = {
            waitedPlayerIds = 0 :: Nil
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.CursorOpenGatherMenu,
            TurnRules.decide(context))

    /// 壁マス上で Z → メニューを開く（しゅうごうはロード合流なので床制限なし）。
    @Test
    def testCursorConfirmOnWallOpensGatherMenu(): Unit \ Assert =
        let context = baseContext(boardWithWall(cell(0, 0)), cell(3, 2));
        Assert.assertEq(
            expected = TurnRules.Transition.CursorOpenGatherMenu,
            TurnRules.decide(context))

    /// 敵マス上で Z → アクティブ味方が居ないのでメニューを開く。
    @Test
    def testCursorConfirmOnEnemyOpensGatherMenu(): Unit \ Assert =
        let context = baseContext(boardWith(cell(0, 0), cell(2, 2)), cell(2, 2));
        Assert.assertEq(
            expected = TurnRules.Transition.CursorOpenGatherMenu,
            TurnRules.decide(context))

    /// PlayerCursor で X → Stay（戻る場所がないのでキャンセルは無効）
    @Test
    def testCursorCancelDoesNothing(): Unit \ Assert =
        let context = {
            input = TurnRules.Input.Cancel
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    // ════════════════════════════════════════════════════════
    // PlayerMoving + Tween 完了待ちガード（playerBusy）
    // ════════════════════════════════════════════════════════

    /// PlayerMoving で busy 中の Z は Stay（Tween 完了まで攻撃フェーズに進めない）
    @Test
    def testMovingConfirmWhileBusyIsBlocked(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerMoving,
            playerBusy = true
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    /// PlayerMoving で !busy + Z → 行動選択ウィンドウ (ActionMenu) を開く
    @Test
    def testMovingConfirmWhenNotBusyOpensActionMenu(): Unit \ Assert =
        let context = {
            phase    = TurnPhase.Phase.PlayerMoving,
            selected = Some(0)
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.MovingOpenActionMenu,
            TurnRules.decide(context))

    /// PlayerMoving で味方と重なっているとき Z → Stay (ActionMenu すら開かない)
    @Test
    def testMovingConfirmWhileOverlappingAllyIsBlocked(): Unit \ Assert =
        let board: Board = {
            map    = emptySnapshot(),
            pieces = (Piece.Player(0), cell(2, 2))
                  :: (Piece.Player(1), cell(2, 2))
                  :: Nil
        };
        let context = {
            phase    = TurnPhase.Phase.PlayerMoving,
            selected = Some(0)
            | baseContext(board, cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    /// PlayerMoving で !busy + X → キャンセル（origin に戻して PlayerCursor へ）
    @Test
    def testMovingCancelWhenNotBusyCancels(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerMoving,
            input = TurnRules.Input.Cancel
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.MovingCancel,
            TurnRules.decide(context))

    /// PlayerMoving で busy 中の X も Stay（移動アニメ中はキャンセルも禁止）
    @Test
    def testMovingCancelWhileBusyIsBlocked(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerMoving,
            input = TurnRules.Input.Cancel,
            playerBusy = true
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    // ════════════════════════════════════════════════════════
    // PlayerAttack + 攻撃成立 / 不成立
    // ════════════════════════════════════════════════════════

    /// PlayerAttack で生きてる敵マスを Z（味方 0 が選択中）→ OpenAttackForecast(0, 0, 3, 2)
    /// 装備中武器を自動使用するので武器選択窓は経由せず AttackForecast に直行する。
    /// 引数: (attackerId, defenderId, defenderX, defenderY)
    @Test
    def testAttackConfirmOnAliveEnemyOpensForecast(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerAttack,
            selected = Some(0)
            | baseContext(boardWith(cell(2, 2), cell(3, 2)), cell(3, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.OpenAttackForecast(0, 0, 3, 2),
            TurnRules.decide(context))

    /// 死亡演出中の敵を Z → Stay（既に倒した敵には届かない）
    @Test
    def testAttackConfirmOnDyingEnemyDoesNothing(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerAttack,
            selected = Some(0),
            dyingEnemyIds = 0 :: Nil
            | baseContext(boardWith(cell(2, 2), cell(3, 2)), cell(3, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    /// PlayerAttack で空マスを Z → Stay（行動も終わらない、再びカーソルを動かせる）
    @Test
    def testAttackConfirmOnEmptyDoesNothing(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerAttack,
            selected = Some(0)
            | baseContext(boardWith(cell(2, 2), cell(3, 2)), cell(0, 0))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    /// PlayerAttack で X → AttackSkip（攻撃せずに waited にする方向）
    @Test
    def testAttackCancelSkipsAttack(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerAttack,
            input = TurnRules.Input.Cancel,
            selected = Some(0)
            | baseContext(boardWith(cell(2, 2), cell(3, 2)), cell(3, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.AttackSkip,
            TurnRules.decide(context))

    // ════════════════════════════════════════════════════════
    // 入力無効フェーズ: 何を押しても Stay
    // ════════════════════════════════════════════════════════

    /// EnemyTurn 中の Confirm → Stay（敵ターン中はプレイヤー入力を無視）
    @Test
    def testEnemyTurnIgnoresInput(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.EnemyTurn
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    /// PlayerAutoMove 中の Confirm → Stay（ロードへ合流中は入力を受け付けない）
    @Test
    def testAutoMoveIgnoresInput(): Unit \ Assert =
        let context = {
            phase = TurnPhase.Phase.PlayerAutoMove
            | baseContext(boardWithPlayerOnly(cell(2, 2)), cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    // ════════════════════════════════════════════════════════
    // TradeTargetSelect: 隣接味方確定 / キャンセル
    // ════════════════════════════════════════════════════════

    /// 味方 2 人 (id=0, id=1) の盤面で、id=0 が selected、カーソルが id=1 の上に
    /// 居て Z → OpenTradeInventory(1)。隣接判定 (manhattan=1) は ActionMenu の
    /// 表示制御と CursorScene の緑マス制限でかかっているので、ここでは
    /// 「カーソル位置に居る他味方を partner として返す」だけを検証する。
    @Test
    def testTradeConfirmOnPartnerCellOpensInventory(): Unit \ Assert =
        let board: Board = {
            map    = emptySnapshot(),
            pieces = (Piece.Player(0), cell(2, 2)) ::
                     (Piece.Player(1), cell(3, 2)) :: Nil
        };
        let context = {
            phase    = TurnPhase.Phase.TradeTargetSelect,
            input    = TurnRules.Input.Confirm,
            selected = Some(0)
            | baseContext(board, cell(3, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.OpenTradeInventory(1),
            TurnRules.decide(context))

    /// カーソルが味方の居ない空マス上で Z → Stay。
    /// (カーソル制限がうまく外れた防御ケース。緑マス制限が正しく動いていれば
    ///  通常は起きないが、ガードとして保持する)
    @Test
    def testTradeConfirmOnEmptyCellStays(): Unit \ Assert =
        let board: Board = {
            map    = emptySnapshot(),
            pieces = (Piece.Player(0), cell(2, 2)) ::
                     (Piece.Player(1), cell(3, 2)) :: Nil
        };
        let context = {
            phase    = TurnPhase.Phase.TradeTargetSelect,
            input    = TurnRules.Input.Confirm,
            selected = Some(0)
            | baseContext(board, cell(4, 4))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))

    /// X キャンセル → TradeCancel (ActionSelect に戻す)
    @Test
    def testTradeCancelReturnsTradeCancelTransition(): Unit \ Assert =
        let board = boardWithPlayerOnly(cell(2, 2));
        let context = {
            phase    = TurnPhase.Phase.TradeTargetSelect,
            input    = TurnRules.Input.Cancel,
            selected = Some(0)
            | baseContext(board, cell(2, 2))
        };
        Assert.assertEq(
            expected = TurnRules.Transition.TradeCancel,
            TurnRules.decide(context))
}
