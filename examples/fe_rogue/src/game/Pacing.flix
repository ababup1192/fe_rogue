/// Pacing — 演出のための「溜め」（hold）を一括管理する
///
/// 敵ターンで連続行動が間髪入れず流れると、プレイヤーが「誰が何をした」を追えない。
/// アクション完了後に短い静止時間を挟むことで、移動・攻撃の演出に視覚的な区切りを与える。
///
/// 仕組み:
///   - `hold(duration)` で残り溜め時間 (`Duration`) をセット
///   - `tick(delta)` で毎フレーム残り時間を減らす（commonEpilogue が呼ぶ）
///   - `isHolding()` が true の間、`stepEnemyTurn` 等は処理をスキップ → 見た目上の停止
///
/// 影響範囲:
///   - 敵ターンの `stepEnemyTurn` のキュー消化が gating される
///   - アニメーション (Tween / AnimationPlayer) は Pacing と独立に進行する。
///     tween は Pacing に関係なく走り続けるため、hold 時間は「演出後に確保したい最低静止時間」として設定する
///
/// 設計指針:
///   - `Tween.Scheduler` や `AnimationPlayer.Scheduler` と同じく Ref ベースの effect handler。
///     Game.start で `with Pacing.withState(rc)` を 1 行注入する
///   - 単一の Duration カウンタ。複数同時 hold は最大値で上書きする方針 (新しい hold が
///     より長ければ伸びる、短ければそのまま)。「複数演出が重なるとき長い方を採る」が直感的
mod Pacing {

    pub eff State {
        /// 残り溜め時間を `duration` にセットする（既存値より長ければ上書き、短ければ無視）。
        /// 「攻撃完了 250ms 溜め → その間に別アクションが 100ms 溜めを要求しても 250ms を保持」
        /// という直感に合わせる。
        def hold(duration: Duration.Duration): Unit
        /// 残り時間から `delta` を引く（0 でクランプ）。`commonEpilogue` が毎フレーム呼ぶ。
        def tick(delta: Duration.Duration): Unit
        /// 残り時間が正なら true。`stepEnemyTurn` が処理スキップの判定に使う。
        def isHolding(): Bool
    }

    /// Ref を closure に閉じ込め、外部から残り時間を直接操作させないための handler。
    /// `hold` / `tick` / `isHolding` という意味のある境界のみ公開し、生の Duration を触らせない。
    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let remaining: Ref[Duration.Duration, r] = Ref.fresh(rc, Duration.zero());
            run {
                thunk()
            } with handler State {
                def hold(duration, k) = {
                    let current = Ref.get(remaining);
                    // 既存値より長い hold だけが効く（短い hold で上書きしない）
                    if (Duration.toSeconds(duration) > Duration.toSeconds(current))
                        Ref.put(duration, remaining)
                    else ();
                    k()
                }
                def tick(delta, k) = {
                    Ref.put(Duration.subClampedToZero(Ref.get(remaining), delta), remaining);
                    k()
                }
                def isHolding(k) = k(Duration.isPositive(Ref.get(remaining)))
            }
        }
}
