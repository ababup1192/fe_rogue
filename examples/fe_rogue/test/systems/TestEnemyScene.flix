/// EnemyScene の移動 System テスト。
///
/// `stepEnemyMove` は敵 1 歩移動の sim 書き込み口: 合法性判定は EnemyAI が済ませている前提で、
/// `Cmd.Move` を 1 回 emit し、同じ target の `SimEvent.Moved` を返す（view 再生はこの event を消費する）。
mod TestEnemyScene {

    /// F4a: stepEnemyMove（敵移動 System）は target へ `Cmd.Move` を 1 回 emit し、同じ target の
    /// `Moved` を返す（合法性は EnemyAI 決定済みゆえ board 再判定なし＝常に書く）。
    @Test
    def testStepEnemyMoveEmitsAndReturnsMoved(): Unit \ Assert =
        let (event, moves) = TestUnitFixtures.withRecordedMoves(() -> EnemyScene.stepEnemyMove(3, {x = 6, y = 2}));
        let t       = PlayerScene.movedTarget(event);
        let emitted = moves |> List.map(c -> (c#x, c#y));
        Assert.assertEq(expected = ((6, 2), (6, 2) :: Nil), ((t#x, t#y), emitted))
}
