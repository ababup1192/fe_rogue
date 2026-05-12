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

    /// 1 マスぶんの行動権。`id` は `EnemyScene.Data#id`。
    /// `remaining` は「この step を処理した後に同じ敵が動ける残りマス数」。
    /// 初期化時は `enemy#moveTiles - 1` を最初の step に入れて、Move のたびに更に -1 する
    /// ……ではなく、本実装では「step を処理する直前の残数 = remaining」とする。
    /// つまり remaining = N の step を処理 → Move で 1 マス進む → remaining = N - 1 を pushFront。
    /// remaining = 0 の step は処理されずに捨てる（または到達しない）。
    pub type alias Step = { id = Int32, remaining = Int32 }

    pub eff Queue {
        /// キュー先頭の step を取り出して返す。空なら None。
        def popFront(): Option[Step]
        /// キュー先頭に step を積む（同じ敵の継続 step）。
        def pushFront(step: Step): Unit
        /// キュー全体を差し替える（ターン開始時の populate）。
        def replace(steps: List[Step]): Unit
        /// 現在の先頭を覗き見る（取り出さない）。
        def peekFront(): Option[Step]
        /// 空かどうか。プレイヤー入力受付の判定に使う。
        def isEmpty(): Bool
    }

    /// `Tween.withScheduler` と同じ流儀の handler 注入。
    /// 内部 Ref `queueRef` は closure に閉じ込められ、外からは見えない。
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
}
