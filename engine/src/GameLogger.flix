/// GameLogger — ゲーム内ログ用 effect
///
/// `playerLog` / `enemyLog` でメッセージを積み上げ、`drainEntries` で
/// 一括取り出しする。`Tween.withScheduler` と同じ流儀で、内部 Ref を
/// closure に隠蔽するハンドラ注入関数 `withLogger` を提供する。
///
/// ノード側（LogScene）が gameLoop の毎フレーム末尾で `drainEntries` を
/// 呼んで蓄積分を取り出し、表示状態を再構築する。
mod GameLogger {

    pub eff GameLogger {
        /// プレイヤー側のメッセージを白色で 1 行積む
        def playerLog(msg: String): Unit
        /// 敵側のメッセージを赤色で 1 行積む
        def enemyLog(msg: String): Unit
        /// ゲームオーバーを濃赤で 1 行積む（プレイヤー HP=0 時の通知）。
        /// 通常の `enemyLog` より目立たせるため別色で扱う。
        def gameOverLog(msg: String): Unit
        /// 1 ターン終わり（味方ターン + 敵ターン = 1 ターン）。
        /// 内部のターン番号を +1 する。次の playerLog/enemyLog から prefix が更新される。
        def endTurn(): Unit
        /// engine 内部用: 蓄積された Entry を古→新の順で返し、内部キューを空にする
        def drainEntries(): List[Entry]
    }

    /// 1 行のログエントリ。色は modulate で Label2D に乗算する。
    pub type alias Entry = { text = String, color = Color }

    /// player 行のデフォルト色（白）
    pub def playerColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}

    /// enemy 行のデフォルト色（赤系・薄め）
    pub def enemyColor(): Color = {r = 1.0f32, g = 0.35f32, b = 0.35f32}

    /// ゲームオーバー行の色（濃赤）。enemyColor の薄赤と区別して際立たせる。
    pub def gameOverColor(): Color = {r = 1.0f32, g = 0.0f32, b = 0.0f32}

    /// `Tween.withScheduler` と同じ流儀の handler 注入。
    /// `entriesRef` は内部 closure に閉じ込められ、外からは見えない。
    pub def withLogger(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - GameLogger) + r =
        thunk -> {
            // 蓄積順は「先頭 = 最新」。drain 時に reverse して古→新で返す
            let entriesRef: Ref[List[Entry], r] = Ref.fresh(rc, Nil);
            // 現在のターン番号。「味方ターン + 敵ターン = 1 ターン」なので、
            // endTurn が呼ばれるたびに +1。1 始まり。
            let turnRef: Ref[Int32, r] = Ref.fresh(rc, 1);
            let push = (text, color) -> {
                let n = Ref.get(turnRef);
                let entry: Entry = { text = "T${n}: ${text}", color = color };
                Ref.put(entry :: Ref.get(entriesRef), entriesRef)
            };
            run {
                thunk()
            } with handler GameLogger {
                def playerLog(msg, k) = {
                    push(msg, playerColor());
                    k()
                }
                def enemyLog(msg, k) = {
                    push(msg, enemyColor());
                    k()
                }
                def gameOverLog(msg, k) = {
                    push(msg, gameOverColor());
                    k()
                }
                def endTurn(k) = {
                    Ref.put(Ref.get(turnRef) + 1, turnRef);
                    k()
                }
                def drainEntries(k) = {
                    let cur = Ref.get(entriesRef);
                    Ref.put(Nil, entriesRef);
                    k(List.reverse(cur))
                }
            }
        }
}
