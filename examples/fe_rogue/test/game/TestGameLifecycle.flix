/// GameOver → リスタートの「リセット手順のセマンティクス」を effect 層で固定する。
///
/// `GameLifecycle.resetForGameOver(catalog)` の処理は 2 段:
///   1. **`resetTurnState()`** — 副作用 effect のみ (Queue / Phase / Selection / Log)
///   2. **`buildAndRecord(catalog)`** — シーンの再構築 + spawn snapshot 更新
///         (LDTK + LWJGL を必要とするためランタイムで担保)
///
/// このテストでは 1) の `resetTurnState` を直接呼び、effect 状態が初期化されることを
/// 観測する。スポーン記録 / シーン構築 (= 2) は実機での動作確認に委ねる。
///
/// `resetTurnState` を切り出した狙い: scene 構築 (LDTK) を経由しないので **テストで純粋に
/// リセット手順だけを観測できる** こと。`Game.start` の GameOverRequest handler が
/// `resetForGameOver` 1 行に痩せたのは、ここで担保される `resetTurnState` の正しさに依存する。
mod TestGameLifecycle {

    // ════════════════════════════════════════════════════════
    // resetTurnState — 敵キュー / フェーズ / 選択駒の 3 effect が初期化される
    // ════════════════════════════════════════════════════════

    /// **想定状況**: 敵ターンで Player(0) が選択されたまま、敵 step が 2 件残り、さらに集合自動継続
    /// フラグ(GatherResume)が立った瞬間に全味方脱落 → GameOverRequest が発火するシナリオ。
    /// `resetTurnState()` 1 回で観測タプル (queue 空か, phase, selection.id, drafts 空か,
    /// resume 解除されたか) が初期値になる。resume の解除は、敵ターン中にゲームオーバーすると
    /// `endTurn` を経ず resume が立ったまま新フロアへ漏れる回帰を防ぐためのもの。
    ///
    /// `GameLogger.gameOverLog` も内部で呼ばれるが、log 内容は別検証範囲 (engine 側の
    /// `GameLogger` テスト) なのでここでは観測しない。logger handler は捨て箱として注入。
    @Test
    def testResetTurnStateClearsQueuePhaseSelectionAndResume(): Unit \ Assert =
        region rc {
            let result = run {
                // 1) 中断状態を作る (敵 step あり / EnemyTurn / Player(0) 選択中 / 集合継続フラグ立ち)
                EnemyTurn.Queue.replace(
                    ({id = 1, remaining = 2}: EnemyTurn.Step) ::
                    ({id = 2, remaining = 1}: EnemyTurn.Step) :: Nil);
                TurnPhase.State.put(TurnPhase.Phase.EnemyTurn);
                SelectedPlayer.State.put({
                    id     = Some(0),
                    drafts = Nil,
                    gatherActive = false
                });
                GatherResume.State.put(true);
                // 2) リセットを 1 呼び出しで実行
                GameLifecycle.resetTurnState();
                // 3) effect の状態を 1 タプルで観測
                // ドラフトスタックも空に戻ることを isEmpty で Bool 化して比較する
                let sel = SelectedPlayer.State.get();
                (EnemyTurn.Queue.isEmpty(),
                 TurnPhase.State.get(),
                 sel#id,
                 List.isEmpty(sel#drafts),
                 GatherResume.State.get())
            } with EnemyTurn.withQueue(rc)
              with TurnPhase.withState(rc)
              with SelectedPlayer.withState(rc)
              with GatherResume.withState(rc)
              with GameLogger.withLogger(rc);
            Assert.assertEq(
                expected = (true,
                            TurnPhase.Phase.PlayerCursor,
                            (None: Option[Int32]),
                            true,
                            false),
                result)
        }
}
