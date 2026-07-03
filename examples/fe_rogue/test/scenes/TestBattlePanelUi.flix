/// BattlePanelUi.confirm / cancel のテスト
///
/// 連打バグ回帰防止: Z 連打で `AttackForecast → PlayerAttack → WeaponSelect → AttackForecast`
/// のループが回って攻撃モーションが再起動されないよう、`confirm` 直後のフェーズが
/// **入力を受け付けない `PlayerAttackHold`** であることを保証する。
///
/// 検証する性質:
///   - 状況が揃った状態で `confirm` を呼ぶと TurnPhase.State が `PlayerAttackHold` になる
///   - `cancel` を呼ぶと ActionSelect（行動メニュー）に戻る
///   - `TurnRules.decide` は `PlayerAttackHold + Confirm` で必ず `Stay` を返す
///     (上の遷移先と組み合わせて「攻撃モーション中の Z は無効」が機能することを担保)
mod TestBattlePanelUi {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 武器を装備し攻撃対象を抱えた選択中味方（= AttackForecast に入っている状態）。
    /// 装備中武器は `weapons.head` を自動使用するため、selectedItem は None でよい。
    def fixturePlayer(): PlayerScene.Data = {
        id                = 0,
        classId           = "test_player",
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = Some(1),
        resource          = TestUnitFixtures.testResource(4, 10),
        weapons           = TestUnitFixtures.testWeapon() :: Nil,
        staves            = Nil,
        consumables       = Nil,
        selectedItem      = None,
        moveStepsTaken    = 0,
        facing            = Staff.Direction.Down,
        hidden            = false,
        usedStairs            = false,
        level                     = 1,
        exp                       = 0,
        pendingLevelUp            = None,
        statuses                  = Nil,
        rings          = Nil,
        ringEquipped          = false,
        followUpUsed   = false
    }

    /// 隣接マス (3,2) に立つ生存中の敵。武器持ち（反撃可）。
    def fixtureEnemy(): EnemyScene.Data = {
        id             = 1,
        resourceId     = "test_enemy",
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = Some(TestUnitFixtures.testWeapon()),
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    /// 5x5 床のみの MapSnapshot（Board 構築用、本テストでは isFloor / isWall は使わない）
    def emptySnapshot(): MapSnapshot =
        {
            tileSize     = 16.0,
            usedRect     = {position = {x = 0, y = 0}, size = ({x = 5, y = 5}: {x = Int32, y = Int32})},
            wallCells    = (Set#{}: Set[(Int32, Int32)]),
            mapGlobal    = {x = 0.0, y = 0.0},
            placements   = Nil
        }

    // ════════════════════════════════════════════════════════
    // confirm の遷移先 = PlayerAttackHold（入力ロック相当）
    // ════════════════════════════════════════════════════════

    /// `BattlePanelUi.confirm` を呼んだ直後の TurnPhase が `PlayerAttackHold` であること。
    ///
    /// バグ修正前は `PlayerAttack` に遷移していたため、次フレームの Z が
    /// `TurnRules.decide` の PlayerAttack 分岐で `OpenWeaponMenu` を返してしまい
    /// 連打ループが成立していた。修正後は入力受付の無い `PlayerAttackHold` に
    /// 遷移するため、`attack_lunge` 完了まで Z が無効化される。
    @Test
    def testConfirmTransitionsToInputLockedPhase(): Unit \ Assert =
        region rc {
            let result = run {
                TurnPhase.State.put(TurnPhase.Phase.AttackForecast);
                SelectedPlayer.State.put({
                    id     = Some(0),
                    drafts = Nil,
                    gatherActive = false
                });
                // confirm 経路が World 位置を読む（posOf は None→scene/引数 fallback）。
                let _ = run { BattlePanelUi.confirm(Scene.empty()) }
                    with handler World.WorldQuery { def get(k) = k(World.empty()) };
                TurnPhase.State.get()
            } with handler PlayerData.PartyQuery {
                def get(id, k) =
                    k(if (id == 0) Some(fixturePlayer()) else None)
                def getAll(k) = k(fixturePlayer() :: Nil)
            } with handler EnemyData.RosterQuery {
                def get(id, k) =
                    k(if (id == 1) Some(fixtureEnemy()) else None)
                def getAll(k) = k(fixtureEnemy() :: Nil)
                def findIdAt(coord, k) =
                    k(if (coord#x == 3 and coord#y == 2) Some(1) else None)
                def anyAttacking(k) = k(false)
            } with handler World.Command {
                def emit(_, k) = k()
            }
              with AnimationPlayer.withScheduler(rc)
              with GameLogger.withLogger(rc)
              with SelectedPlayer.withState(rc)
              with CursorState.withState(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(
                expected = TurnPhase.Phase.PlayerAttackHold,
                result)
        }

    // ════════════════════════════════════════════════════════
    // cancel の遷移先 = ActionSelect（行動メニューに戻る / 待機しない）
    // ════════════════════════════════════════════════════════

    /// `BattlePanelUi.cancel` を呼んだ直後の TurnPhase が `ActionSelect` であること。
    /// 攻撃予測を X でキャンセルしたら待機 (commit) や PlayerAttack ではなく行動メニューに
    /// 戻る、という仕様の回帰防止。次フレームの ActionMenuUi.frameStep が
    /// ActionSelect を見てメニューを再表示する。
    @Test
    def testCancelReturnsToActionSelect(): Unit \ Assert =
        region rc {
            let result = run {
                TurnPhase.State.put(TurnPhase.Phase.AttackForecast);
                SelectedPlayer.State.put({
                    id     = Some(0),
                    drafts = Nil,
                    gatherActive = false
                });
                let _ = BattlePanelUi.cancel(Scene.empty());
                TurnPhase.State.get()
            } with handler PlayerData.PartyQuery {
                def get(id, k) =
                    k(if (id == 0) Some(fixturePlayer()) else None)
                def getAll(k) = k(fixturePlayer() :: Nil)
            } with handler World.Command {
                def emit(_, k) = k()
            } with Tween.withScheduler(rc)
              with AnimationPlayer.withScheduler(rc)
              with SelectedPlayer.withState(rc)
              with CursorState.withState(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(
                expected = TurnPhase.Phase.ActionSelect,
                result)
        }

    // ════════════════════════════════════════════════════════
    // PlayerAttackHold は確定キーを無視する（catch-all で Stay）
    // ════════════════════════════════════════════════════════

    /// `confirm` 後のフェーズ (`PlayerAttackHold`) で Z が来ても `Stay` であること。
    /// 上のテストで「confirm が PlayerAttackHold を put する」と保証されているので、
    /// この 2 本を組み合わせて「Z 連打しても再びメニューが開かない」を担保する。
    @Test
    def testAttackHoldConfirmIsStay(): Unit \ Assert =
        let board: Board = {
            map    = emptySnapshot(),
            pieces = (Piece.Player(0), ({x = 2, y = 2}: {x = Int32, y = Int32}))
                  :: (Piece.Enemy(1),  ({x = 3, y = 2}: {x = Int32, y = Int32}))
                  :: Nil
        };
        let context: TurnRules.Context = {
            phase           = TurnPhase.Phase.PlayerAttackHold,
            input           = TurnRules.Input.Confirm,
            board           = board,
            cursor          = ({x = 3, y = 2}: {x = Int32, y = Int32}),
            selected        = Some(0),
            waitedPlayerIds = Nil,
            dyingEnemyIds   = Nil,
            playerBusy      = false
        };
        Assert.assertEq(
            expected = TurnRules.Transition.Stay,
            TurnRules.decide(context))
}
