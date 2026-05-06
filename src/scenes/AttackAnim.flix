/// AttackAnim — 体当たり攻撃モーションの共通ステート
///
/// プレイヤーと敵で同じ「Forward → 重なり → Returning」の 2 段 tween 連鎖を
/// 使うため、状態の型をここに集約する。実体は `PlayerScene.Data` と `EnemyScene.Data`
/// の `attacking: Option[State]` フィールドに格納される。
///
/// フロー:
///   1. handleConfirmInAttack / applyOneStep(Attack):
///      - 攻撃開始時に Forward 用の tween を登録（attacker world pos → defender world pos）
///      - `attacking = Some({phase = Forward, ...})` を立てる
///      - **HP / damage.ogg はまだ適用しない** — 重なる瞬間まで遅延
///   2. tickAttacks（毎フレーム）:
///      - Forward の tween 完了を検知 → attacker と defender が重なった瞬間
///        ・damage.ogg 再生
///        ・defender の HP を 1 減らす（0 なら死亡演出開始）
///        ・Returning 用の tween を登録（defender pos → attacker origin pos）
///        ・`phase = Returning` に更新
///      - Returning の tween 完了を検知 → 攻撃モーション終了
///        ・`attacking = None` をクリア
///        ・プレイヤー攻撃なら commitWaitedAndAdvance（次セレクト or 敵ターンへ）
///        ・敵攻撃なら何もしない（stepEnemyTurn が次フレームでキューを進める）
mod AttackAnim {

    /// 体当たりモーションの実行中 1 サイクル分のステート。
    /// `targetId`: 攻撃対象の id（プレイヤー攻撃なら敵 id、敵攻撃ならプレイヤー id）
    /// `targetPos`: 攻撃対象のグリッド位置（重なりのターゲット）
    /// `originPos`: 攻撃側のグリッド位置（Returning で戻る先）
    pub type alias State = {
        phase     = Phase,
        targetId  = Int32,
        targetPos = Vec2.Vec2i,
        originPos = Vec2.Vec2i
    }

    /// 攻撃モーションのフェーズ。
    pub enum Phase with Eq, ToString {
        /// attacker → defender へ tween 中
        case Forward
        /// defender 重なり後、attacker → origin へ tween 中
        case Returning
    }

    /// 1 フェーズの所要時間（秒）。
    /// 移動 (16/120 ≈ 0.133) より速く、視認できる程度の長さに合わせる。
    pub def phaseDuration(): Float64 = 16.0 / 200.0   // ≈ 0.08 秒
}
