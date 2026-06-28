/// GatherResume — 集合モードのターン跨ぎ自動継続フラグを保持する effect
///
/// 集合（行軍）モードは `SelectedPlayer.State#gatherActive` で表現されるが、これは敵ターン入口
/// （`TurnFlow.commitAllWaitedAndAdvance` の `SelectedPlayer.cleared()`）で必ず落ちる。
/// 「集合中に全員待機でターンを閉じた」という事実を **敵ターンを跨いで次の味方ターン開始まで**
/// 運ぶには、別の永続 state が要る。それがこのフラグ。
///
/// 立てる: `commitAllWaitedAndAdvance(allowResume=true)` かつ `gatherActive=true` のとき true。
///         （集合中の「全員待機」/「shift スキップ」/「ターンエンド」が該当。集合中に敵へ接敵した
///          強制全員待機は `allowResume=false` で立てない＝集合再突入→即強制待機ループを断つ。）
/// 消す:   味方ターン開始（`EnemyTurnDriverScene.endTurn`）で必ず `put(false)` して消費・再評価。
///
/// 設計指針: `Pacing` / `SelectedPlayer` / `TurnPhase` と同じ Ref ベースの effect handler。
/// `Game.start` で `with GatherResume.withState(rc)` を 1 行注入し、`FrameAef.ProcessT` に
/// `GatherResume.State` を載せて process 経路から読み書きできるようにする。
mod GatherResume {

    /// 単一 Bool の get/put。入れ子ハンドラは想定しない。
    pub eff State {
        /// 次の味方ターン開始時に集合へ自動復帰すべきかを返す。
        def get(): Bool
        /// フラグを上書きする（集合確定で true / ターン開始の消費で false）。
        def put(v: Bool): Unit
    }

    /// Ref を closure に閉じ込め、読み書きを `get` / `put` のみに強制する handler。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let flag: Ref[Bool, r] = Ref.fresh(rc, false);
            run {
                thunk()
            } with handler State {
                def get(k)    = k(Ref.get(flag))
                def put(v, k) = { Ref.put(v, flag); k() }
            }
        }
}
