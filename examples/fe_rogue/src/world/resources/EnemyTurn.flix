/// EnemyTurn — 敵ターンを「1 マス分の step キュー」で 1 体ずつ進めるための effect
///
/// 設計意図:
///   敵が 1 ターンに複数マス動く場合、`onKeyPressed` で全敵分を即座に Tween 登録すると
///   全敵が同時並行で動き出す（Tween スケジューラはレジスタ済みを毎フレーム並列に進める）。
///   そのうえ複数マスを 1 本の Tween でつなぐと斜め直線スライドになる。
///
///   そこで「1 マス = 1 step」を要素とするキューを Ref で持ち、gameLoop が毎フレーム
///   先頭 step を 1 つだけ処理する形に分解する。Tween がアクティブな間は処理を見送り、
///   完了してから次の step に進む。これで:
///     - 1 体ずつ動く（同じ敵の step は連続して頭に並ぶ）
///     - 1 マスずつ縦横移動（各 step は隣接セルへの単一 Tween）
///   が同時に実現できる。
///
/// 使い方:
///   - `Game.start` で `with EnemyTurn.withQueue(rc)` を 1 行注入する
///   - 敵ターン開始時（プレイヤーが Z 押下）に `Queue.replace([(id, moveTiles), ...])`
///   - gameLoop が毎フレーム `Queue.peekFront()` → step を 1 つ処理 →（Move なら）`pushFront`
///     で残り step 数を戻す → ループ
///   - キューが空 = プレイヤーターン
mod EnemyTurn {

    /// 1 マスぶんの行動権。`id` は `EnemyDriver.Data` の `id` フィールド（連番で割り当てられ、
    /// 同一ターン中に同じ id が複数の step に現れることはない前提。同セル 2 体は想定外）。
    /// remaining は「残り移動マス数」。処理時に 1 マス進み remaining - 1 を pushFront する。
    /// remaining = 0 の step が先頭に来たら移動を終了し捨てる。
    pub type alias Step = { id = Int32, remaining = Int32 }

    /// キューの要素順序: List[Step] の先頭がキュー先頭 (FIFO)。
    /// ただし pushFront で先頭挿入できるため、popFront→pushFront の組み合わせで
    /// 同一敵の継続 step を先頭に戻す LIFO 的な使い方も成立する。
    /// この「継続 step を割り込ませる」仕組みが 1 体ずつ動く順序を保証する。
    pub eff Queue {
        /// キュー先頭の step を取り出して返す。空なら None を返し、キューは変化しない（副作用なし）。
        def popFront(): Option[Step]
        /// キュー先頭に step を積む（同じ敵の継続 step）。
        def pushFront(step: Step): Unit
        /// キュー全体を差し替える（ターン開始時の populate）。
        def replace(steps: List[Step]): Unit
        /// 現在の先頭を覗き見る（キューは変化しない）。
        /// Tween アクティブ判定の前に step 種別（id・remaining）を確認し、
        /// 処理すべき敵・行動か判断してから popFront → Tween 登録する、という用途を想定。
        def peekFront(): Option[Step]
        /// 空かどうか。プレイヤー入力受付の判定に使う。
        def isEmpty(): Bool
    }

    /// `Tween.withScheduler` と同じ流儀の handler 注入。
    /// 注入後は thunk のスコープ内で `Queue` effect が解決される。
    /// スコープを抜けると queueRef は破棄される。
    /// 禁止パターン: 同一 rc を別の withQueue 呼び出しに渡す、withQueue を入れ子にする、
    /// thunk の外側（呼び出し元）で queueRef を保持して後から参照するなど、
    /// 複数スコープ間で同じキュー状態を共有してはならない。
    pub def withQueue(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - Queue) + r =
        thunk -> {
            let queueRef: Ref[List[Step], r] = Ref.fresh(rc, Nil);
            run {
                thunk()
            } with handler Queue {
                def popFront(k) =
                    match Ref.get(queueRef) {
                        case Nil    => k(None)
                        case h :: t =>
                            Ref.put(t, queueRef);
                            k(Some(h))
                    }
                def pushFront(step, k) = {
                    Ref.put(step :: Ref.get(queueRef), queueRef);
                    k()
                }
                def replace(steps, k) = {
                    Ref.put(steps, queueRef);
                    k()
                }
                def peekFront(k) =
                    match Ref.get(queueRef) {
                        case Nil    => k(None)
                        case h :: _ => k(Some(h))
                    }
                def isEmpty(k) = k(List.isEmpty(Ref.get(queueRef)))
            }
        }

    /// World の `enemyTurnQueue` field（単一権威）へ委譲する facade handler。`worldRef` を共有窓口
    /// として受け取り、各 op を World 経由で読み書きする（本番 `Game.start` 用。test は `withQueue`）。
    pub def withWorld(worldRef: Ref[World, r]):
            (Unit -> a \ ef) -> a \ (ef - Queue) + r =
        thunk -> {
            run {
                thunk()
            } with handler Queue {
                def popFront(k) =
                    match World.enemyTurnQueueOf(Ref.get(worldRef)) {
                        case Nil    => k(None)
                        case h :: t =>
                            Ref.put(World.applyCmd(World.Cmd.SetEnemyTurnQueue(t), Ref.get(worldRef)), worldRef);
                            k(Some(h))
                    }
                def pushFront(step, k) = {
                    Ref.put(World.applyCmd(World.Cmd.SetEnemyTurnQueue(step :: World.enemyTurnQueueOf(Ref.get(worldRef))), Ref.get(worldRef)), worldRef);
                    k()
                }
                def replace(steps, k) = {
                    Ref.put(World.applyCmd(World.Cmd.SetEnemyTurnQueue(steps), Ref.get(worldRef)), worldRef);
                    k()
                }
                def peekFront(k) =
                    match World.enemyTurnQueueOf(Ref.get(worldRef)) {
                        case Nil    => k(None)
                        case h :: _ => k(Some(h))
                    }
                def isEmpty(k) = k(List.isEmpty(World.enemyTurnQueueOf(Ref.get(worldRef))))
            }
        }
}
