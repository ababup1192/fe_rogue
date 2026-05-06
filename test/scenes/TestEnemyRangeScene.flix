/// EnemyRangeScene のシーン操作（足し引き）が一貫していることを検証する。
///
/// 範囲内セル列挙の正しさ自体は `BoardLogic.reachableCells` が担っており、
/// `TestBoardLogic` が網羅しているので、ここでは「scene にノードが入る／出る」
/// プラミングのみ検証する。具体的には:
///   - 何も無いシーンで `clear` を呼んでも壊れない（保険動作）
///   - `currentEnemyId` / `reachable` は EnemyRange 未登録なら None / Nil を返す
///   - 直接 EnemyRange ノードを差し込めば、上記クエリで観測できる
///   - `clear` を呼ぶと EnemyRange ノードが scene から消える
///
/// `refreshFor` 自体は `MapScene.getMapLayer` を要求するため、TileMapLayer を
/// 構築する重い統合テストになる。ここでは扱わず、実機（描画あり）の確認に委ねる。
mod TestEnemyRangeScene {

    // ════════════════════════════════════════════════════════
    // ヘルパー
    // ════════════════════════════════════════════════════════

    /// EnemyRange ノードを直接 scene に差し込む（refreshFor を使わずテスト用に組む）
    def addEnemyRangeManually(enemyId: Int32,
                                reachable: List[Vec2.Vec2i],
                                scene: Scene[NodeTag]): Scene[NodeTag] =
        let parent = Marker2D.make(Vec2.zero());
        let data: EnemyRangeScene.Data = { enemyId = enemyId, reachable = reachable };
        Scene.addNode("EnemyRange",
            EngineNode.Marker2DWithState(parent, NodeTag.EnemyRange(data)),
            scene)

    // ════════════════════════════════════════════════════════
    // 未登録時のクエリは「居ない」を返す
    // ════════════════════════════════════════════════════════

    /// EnemyRange を一度も足していないシーンでは、currentEnemyId は None、
    /// reachable は空リストを返す（ホバー前の初期状態を観測するためのクエリ契約）
    @Test
    def testQueriesReturnEmptyWhenAbsent(): Unit \ Assert =
        let scene = Scene.empty();
        let id = EnemyRangeScene.currentEnemyId(scene);
        let cells = EnemyRangeScene.reachable(scene);
        Assert.assertEq(expected = (None, 0), (id, List.length(cells)))

    /// 何もないシーンに `clear` を呼んでも例外にはならず、空シーンを返す
    /// （カーソルが敵 → 床 → 床 と動いた場合、2 回目の床遷移でも安全に clear を呼べる）
    @Test
    def testClearOnEmptySceneIsSafe(): Unit \ Assert =
        let scene = Scene.empty();
        let after = EnemyRangeScene.clear(scene);
        Assert.assertEq(expected = (None, 0),
            (EnemyRangeScene.currentEnemyId(after),
             List.length(EnemyRangeScene.reachable(after))))

    // ════════════════════════════════════════════════════════
    // 追加した状態の観測
    // ════════════════════════════════════════════════════════

    /// 手で組んだ EnemyRange ノードは currentEnemyId / reachable から見える。
    /// reachable は与えたセル一覧と同じ件数になる（並びは将来変えても良いので件数で確認）
    @Test
    def testManuallyAddedRangeIsObservable(): Unit \ Assert =
        let cells = ({x = 1, y = 1}: Vec2.Vec2i)
                    :: ({x = 2, y = 1}: Vec2.Vec2i)
                    :: ({x = 3, y = 1}: Vec2.Vec2i) :: Nil;
        let scene = addEnemyRangeManually(7, cells, Scene.empty());
        Assert.assertEq(expected = (Some(7), 3),
            (EnemyRangeScene.currentEnemyId(scene),
             List.length(EnemyRangeScene.reachable(scene))))

    /// `clear` は登録済みの EnemyRange ノードを scene から取り除き、
    /// 後続のクエリで「居ない」状態に戻る（カーソルが敵から離れたフレームの動作）
    @Test
    def testClearRemovesExistingRange(): Unit \ Assert =
        let cells = ({x = 0, y = 0}: Vec2.Vec2i) :: Nil;
        let scene  = addEnemyRangeManually(2, cells, Scene.empty());
        let after  = EnemyRangeScene.clear(scene);
        Assert.assertEq(expected = (None, 0),
            (EnemyRangeScene.currentEnemyId(after),
             List.length(EnemyRangeScene.reachable(after))))
}
