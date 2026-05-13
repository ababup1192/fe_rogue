/// `<<wait <sec>>>` 命令の残り時間を Duration 単位で持つキュー。
///
/// 設計意図:
///   - 状態は `Game.CommandWaitQueue.Access` effect 経由で操作する。
///     実体（region 内 `MutList[Duration, r]`）は `Game.start` の handler が握る
///   - Yarn VM は 1 つの `WaitingCommand` 状態しか持てないが、設計の素直さを
///     優先して MutList で複数同時 wait に耐える形にしておく
///   - 時間値は **すべて Duration**（Float64 の裸の秒数を扱わない）
///   - `tick(delta)` は「期限切れになった件数」を返す。呼び出し側は受け取った件数だけ
///     `Session.submitCommandDone` を発火する責務を負う
mod Game.CommandWaitQueue {
    use Duration.Duration

    /// 待機キューの操作。実体は `Game.start` の handler で region 内 MutList に
    /// 閉じ込めて注入する。
    pub eff Access {
        /// `<<wait <sec>>>` の Duration を 1 件積む。
        def enqueue(duration: Duration): Unit

        /// `delta` だけ全要素を減算し、期限切れになった件数を返す。
        /// 呼び出し側はその件数ぶん `Session.submitCommandDone` を発火する。
        def tick(delta: Duration): Int32

        /// キューに積まれている件数。テスト・デバッグ用。
        def size(): Int32
    }

    /// `Editor.withState(rc)` と同じ流儀の handler 注入。
    /// `queue` (MutList) は内部 closure に閉じ込められ、呼び出し側からは見えない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Access) + r =
        thunk -> {
            let queue: MutList[Duration, r] = MutList.empty(rc);
            run thunk() with handler Access {
                def enqueue(d, k) = { MutList.push(d, queue); k() }
                def tick(d, k)    = k(tickMut(d, queue))
                def size(k)       = k(MutList.length(queue))
            }
        }

    /// 全要素から `delta` を引き、期限切れ (`Duration.isExpired`) になったものを
    /// MutList から間引いて、その件数を返す。
    /// 残存要素は新 Duration で in-place 更新する（`MutList.put`）。
    def tickMut(delta: Duration, queue: MutList[Duration, r]): Int32 \ r =
        // ステップ 1: 全要素を delta だけ減らして in-place 更新する。
        // ステップ 2: 期限切れ要素を後ろから削除しつつ件数をカウントする
        //   （前から削除すると index がズレるので末尾→先頭の順で走査する）。
        decrementInPlace(delta, queue, 0);
        removeExpiredFromTail(queue, MutList.length(queue) - 1, 0)

    /// `queue` の全要素から `delta` を引いた値で in-place 更新する（再帰）。
    def decrementInPlace(delta: Duration, queue: MutList[Duration, r], i: Int32): Unit \ r =
        if (i >= MutList.length(queue)) ()
        else {
            let next = Duration.subClampedToZero(MutList.get(i, queue), delta);
            MutList.put(next, i, queue);
            decrementInPlace(delta, queue, i + 1)
        }

    /// 末尾から先頭に向かって、期限切れの要素を `MutList.remove` で取り除き、
    /// 取り除いた件数を返す（再帰）。
    def removeExpiredFromTail(queue: MutList[Duration, r], i: Int32, expired: Int32): Int32 \ r =
        if (i < 0) expired
        else {
            let value = MutList.get(i, queue);
            if (Duration.isExpired(value)) {
                MutList.remove(i, queue);
                removeExpiredFromTail(queue, i - 1, expired + 1)
            } else
                removeExpiredFromTail(queue, i - 1, expired)
        }
}
