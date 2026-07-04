/// EnemyRangeScene のクエリ（足し引き）が一貫していることを検証する。
///
/// 範囲内セル列挙の正しさ自体は `Board.reachableCells` が担っており、
/// `TestBoard` が網羅しているので、ここでは「範囲 resource に入る／出る」
/// プラミングのみ検証する。具体的には:
///   - 何も無い状態で `clear` を呼んでも壊れない（保険動作）
///   - `currentEnemyId` / `reachable` は EnemyRange 未設定なら None / Nil を返す
///   - 範囲 resource に直接差し込めば、上記クエリで観測できる
///   - `clear` を呼ぶと EnemyRange が resource から消える
///
/// 敵ホバー範囲は `RangeOverlayState` resource の `enemyRange` に載る単一真実源で、
/// `refreshFor` は `MapScene.getMapLayer` を要求する重い統合テストになるため
/// ここでは扱わず、実機（描画あり）の確認に委ねる。
mod TestEnemyRangeScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// EnemyRange を範囲 resource へ直接差し込む（refreshFor を使わずテスト用に組む）。
    def putEnemyRange(enemyId: Int32,
                       reachable: List[{x = Int32, y = Int32}]): Unit \ RangeOverlayState.State =
        let data: EnemyRangeScene.Data = { enemyId = enemyId, reachable = reachable };
        RangeOverlayState.State.put({enemyRange = Some(data) | RangeOverlayState.State.get()})

    // ════════════════════════════════════════════════════════
    // 未登録時のクエリは「居ない」を返す
    // ════════════════════════════════════════════════════════

    /// EnemyRange を一度も足していない状態では、currentEnemyId は None、
    /// reachable は空リストを返す（ホバー前の初期状態を観測するためのクエリ契約）
    @Test
    def testQueriesReturnEmptyWhenAbsent(): Unit \ Assert =
        region rc {
            TestUnitFixtures.withRangeOverlay(rc, () -> {
                let scene = Scene.empty();
                let id = EnemyRangeScene.currentEnemyId(scene);
                let cells = EnemyRangeScene.reachable(scene);
                Assert.assertEq(expected = (None, 0), (id, List.length(cells)))
            })
        }

    /// 何もない状態で `clear` を呼んでも例外にはならず、空を返す
    /// （カーソルが敵 → 床 → 床 と動いた場合、2 回目の床遷移でも安全に clear を呼べる）
    @Test
    def testClearOnEmptySceneIsSafe(): Unit \ Assert =
        region rc {
            TestUnitFixtures.withRangeOverlay(rc, () -> {
                let after = EnemyRangeScene.clear(Scene.empty());
                Assert.assertEq(expected = (None, 0),
                    (EnemyRangeScene.currentEnemyId(after),
                     List.length(EnemyRangeScene.reachable(after))))
            })
        }

    // ════════════════════════════════════════════════════════
    // 追加した状態の観測
    // ════════════════════════════════════════════════════════

    /// 手で差し込んだ EnemyRange は currentEnemyId / reachable から見える。
    /// reachable は与えたセル一覧と同じ件数になる（並びは将来変えても良いので件数で確認）
    @Test
    def testManuallyAddedRangeIsObservable(): Unit \ Assert =
        region rc {
            TestUnitFixtures.withRangeOverlay(rc, () -> {
                let cells = ({x = 1, y = 1}: {x = Int32, y = Int32})
                            :: ({x = 2, y = 1}: {x = Int32, y = Int32})
                            :: ({x = 3, y = 1}: {x = Int32, y = Int32}) :: Nil;
                putEnemyRange(7, cells);
                let scene = Scene.empty();
                Assert.assertEq(expected = (Some(7), 3),
                    (EnemyRangeScene.currentEnemyId(scene),
                     List.length(EnemyRangeScene.reachable(scene))))
            })
        }

    /// `clear` は登録済みの EnemyRange を resource から取り除き、
    /// 後続のクエリで「居ない」状態に戻る（カーソルが敵から離れたフレームの動作）
    @Test
    def testClearRemovesExistingRange(): Unit \ Assert =
        region rc {
            TestUnitFixtures.withRangeOverlay(rc, () -> {
                let cells = ({x = 0, y = 0}: {x = Int32, y = Int32}) :: Nil;
                putEnemyRange(2, cells);
                let after = EnemyRangeScene.clear(Scene.empty());
                Assert.assertEq(expected = (None, 0),
                    (EnemyRangeScene.currentEnemyId(after),
                     List.length(EnemyRangeScene.reachable(after))))
            })
        }
}
