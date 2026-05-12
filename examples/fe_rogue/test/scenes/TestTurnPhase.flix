/// TurnPhase の handler 注入で得られる「フェーズ状態」が、効果操作 put / get で
/// 一貫して読み書きできることを検証する。
///
/// 効果を持つ単一値の Ref-backed handler は典型的に「put したら次の get に反映される」
/// 「複数回の put は最新だけが残る」という性質しか持たない。テストではその 2 性質と、
/// 起動直後に **PlayerCursor がデフォルト** であること（味方ターン開始時のサブフェーズ）
/// だけ確認する。Phase enum 自体の Eq は `with Eq` の自動導出に任せる。
mod TestTurnPhase {

    // ════════════════════════════════════════════════════════
    // 初期値: PlayerCursor から始まる
    // ════════════════════════════════════════════════════════

    /// `withState` 直後の get は `PlayerCursor` を返す
    /// （ゲーム起動時に味方が動かせる「カーソル選択フェーズ」に居る、という不変条件）
    @Test
    def testWithStateStartsInPlayerCursor(): Unit \ Assert =
        region rc {
            let result = run {
                TurnPhase.State.get()
            } with TurnPhase.withState(rc);
            Assert.assertEq(expected = TurnPhase.Phase.PlayerCursor, result)
        }

    // ════════════════════════════════════════════════════════
    // put / get の順序: 最後の put だけが残る
    // ════════════════════════════════════════════════════════

    /// 3 つの異なるフェーズを順に put した後、最後の値だけが get で観測できる
    /// （途中の値は捨てられ、フェーズは「最新書き込みを反映する」セルとして振る舞う）
    @Test
    def testPutOverridesPreviousPhase(): Unit \ Assert =
        region rc {
            let result = run {
                TurnPhase.State.put(TurnPhase.Phase.PlayerMoving);
                TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
                TurnPhase.State.put(TurnPhase.Phase.PlayerCursor);
                TurnPhase.State.get()
            } with TurnPhase.withState(rc);
            Assert.assertEq(expected = TurnPhase.Phase.PlayerCursor, result)
        }

    /// put で書いたフェーズは後続の get に反映される
    /// （味方ターン → 敵ターン遷移を InputHandler が `put(EnemyTurn)` で記録し、
    ///  次フレームの gameLoop が `get()` で読み取って分岐できる、というシナリオ）
    @Test
    def testPutEnemyTurnIsObservable(): Unit \ Assert =
        region rc {
            let result = run {
                TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
                TurnPhase.State.get()
            } with TurnPhase.withState(rc);
            Assert.assertEq(expected = TurnPhase.Phase.EnemyTurn, result)
        }
}
