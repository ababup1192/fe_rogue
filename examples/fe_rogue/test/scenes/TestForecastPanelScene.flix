/// ForecastPanelScene.confirm のテスト
///
/// 連打バグ回帰防止: Z 連打で `AttackForecast → PlayerAttack → WeaponSelect → AttackForecast`
/// のループが回って攻撃モーションが再起動されないよう、`confirm` 直後のフェーズが
/// **入力を受け付けない `PlayerAttackHold`** であることを保証する。
///
/// 検証する性質:
///   - 状況が揃った状態で `confirm` を呼ぶと TurnPhase.State が `PlayerAttackHold` になる
///   - `TurnRules.decide` は `PlayerAttackHold + Confirm` で必ず `Stay` を返す
///     (上の遷移先と組み合わせて「攻撃モーション中の Z は無効」が機能することを担保)
mod TestForecastPanelScene {

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 武器を装備し攻撃対象を抱えた選択中味方。`selectedWeaponIdx = Some(0)` で
    /// 武器選択も済んでいる前提（= AttackForecast に入っている状態）。
    def fixturePlayer(): PlayerScene.Data = {
        id                = 0,
        gridPos           = {x = 2, y = 2},
        moveTiles         = 4,
        hp                = 10,
        waited            = false,
        attackTargetId    = Some(1),
        resource          = TestUnitFixtures.testResource(4, 10),
        weapons           = TestUnitFixtures.testWeapon() :: Nil,
        selectedWeaponIdx = Some(0),
        moveStepsTaken    = 0
    }

    /// 隣接マス (3,2) に立つ生存中の敵。武器持ち（反撃可）。
    def fixtureEnemy(): EnemyScene.Data = {
        id             = 1,
        gridPos        = {x = 3, y = 2},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = 10,
        isDying        = false,
        attackTargetId = None,
        resource       = TestUnitFixtures.testResource(3, 10),
        weapon         = Some(TestUnitFixtures.testWeapon())
    }

    /// 5x5 床のみの MapSnapshot（Board 構築用、本テストでは isFloor / isWall は使わない）
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

    // ════════════════════════════════════════════════════════
    // confirm の遷移先 = PlayerAttackHold（入力ロック相当）
    // ════════════════════════════════════════════════════════

    /// `ForecastPanelScene.confirm` を呼んだ直後の TurnPhase が `PlayerAttackHold` であること。
    ///
    /// バグ修正前は `PlayerAttack` に遷移していたため、次フレームの Z が
    /// `TurnRules.decide` の PlayerAttack 分岐で `OpenWeaponMenu` を返してしまい
    /// 連打ループが成立していた。修正後は入力受付の無い `PlayerAttackHold` に
    /// 遷移するため、`attack_lunge` 完了まで Z が無効化される。
    ///
    /// Scene は空のままにしてあるので `PlayerScene.startAttack` は内部 `get(id, scene)`
    /// で None → no-op になるが、phase の書き換えは startAttack 呼び出しより前で
    /// 行われるためアサート対象は変わらない。
    @Test
    def testConfirmTransitionsToInputLockedPhase(): Unit \ Assert =
        region rc {
            let result = run {
                TurnPhase.State.put(TurnPhase.Phase.AttackForecast);
                SelectedPlayer.State.put({
                    id     = Some(0),
                    origin = Some(({x = 2, y = 2}: {x = Int32, y = Int32}))
                });
                let _ = ForecastPanelScene.confirm(Scene.empty());
                TurnPhase.State.get()
            } with handler PlayerScene.PartyQuery {
                def get(id, k) =
                    k(if (id == 0) Some(fixturePlayer()) else None)
                def getAll(k) = k(fixturePlayer() :: Nil)
                def getGridPos(id, k) =
                    k(if (id == 0) fixturePlayer()#gridPos
                      else ({x = 0, y = 0}: {x = Int32, y = Int32}))
                def getMoveTiles(id, k) =
                    k(if (id == 0) fixturePlayer()#moveTiles else 0)
            } with handler EnemyScene.RosterQuery {
                def get(id, k) =
                    k(if (id == 1) Some(fixtureEnemy()) else None)
                def getAll(k) = k(fixtureEnemy() :: Nil)
                def findIdAt(coord, k) =
                    k(if (coord#x == 3 and coord#y == 2) Some(1) else None)
                def anyAttacking(k) = k(false)
            }
              with AnimationPlayer.withScheduler(rc)
              with GameLogger.withLogger(rc)
              with SelectedPlayer.withState(rc)
              with TurnPhase.withState(rc);
            Assert.assertEq(
                expected = TurnPhase.Phase.PlayerAttackHold,
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
