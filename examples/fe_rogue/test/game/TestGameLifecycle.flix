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

    // ════════════════════════════════════════════════════════
    // startNewRun — 「はじめから」でフロア進行と前回 party がリセットされる
    // ════════════════════════════════════════════════════════

    /// **想定状況**: 3F で中断してタイトルへ戻り「はじめから」を選ぶ（2026-07-10 注釈チケット
    /// f15755 の再現）。中断でタイトルへ戻っても FloorProgress は中断時の "f03" のまま・
    /// party も前回 run の構成が残っている。`startNewRun` 1 回で
    /// (フロア, party が未抽選に戻ったか) が (先頭フロア "f01", true) になる。
    @Test
    def testStartNewRunResetsFloorAndParty(): Unit \ {Assert, Fs.FileRead} =
        region rc {
            let weapons = WeaponCatalog.load();
            let catalogs: GameLifecycle.Catalogs =
                {weapons     = weapons,
                 players     = UnitCatalog.load(AssetPath.resolve("resources/units.json"), weapons),
                 enemies     = EnemyCatalog.load(),
                 floors      = FloorCatalog.load(),
                 staves      = Staff.load(),
                 consumables = Consumable.load(),
                 chests      = ChestCatalog.load(),
                 rings       = Ring.load()};
            let worldRef = Ref.fresh(rc, World.empty());
            let result = run {
                // 1) 中断直後のタイトル画面を作る（フロア進行 = 3F・前回 run の party 残り）
                FloorProgress.State.put("f03");
                PartySelection.State.put(("test_player", TestUnitFixtures.testResource(5, 18)) :: Nil);
                // 2) 「はじめから」の新規ラン準備を 1 呼び出しで実行
                GameLifecycle.startNewRun(catalogs);
                // 3) (フロア, party が未抽選 None に戻ったか) を 1 タプルで観測
                (FloorProgress.State.get(), Option.isEmpty(PartySelection.State.get()))
            } with FloorProgress.withState(worldRef)
              with PartySelection.withState(worldRef);
            Assert.assertEq(expected = ("f01", true), result)
        }
}
