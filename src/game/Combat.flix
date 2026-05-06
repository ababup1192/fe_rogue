/// Combat — 戦闘（攻撃モーション + ダメージルール）の純粋ロジック
///
/// 「攻撃の流れ」に関わるデータと判定をまとめる:
///   - mod AttackAnim: 体当たり攻撃モーションの状態型（Forward → Returning の 2 段 tween）
///   - mod Combat:     HP に対するダメージ計算（残 HP と「倒れたか」の判定）
///
/// PlayerScene / EnemyScene の `tickAttacks` で「Forward 完了 → ダメージ適用 →
/// Returning 開始」と連鎖する流れが、両 mod を併せ読みすることで 1 ファイル内で追える。
///
/// Scene[NodeTag] / effect には依存しない。テストは `hp` と `amount` だけで書ける。

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

    /// 1 フェーズの所要時間。
    /// 移動 (16/200 ≈ 0.08 秒) より速く、視認できる程度の長さに合わせる。
    pub def phaseDuration(): Duration.Duration =
        Duration.frames(count = 16, fps = 200)   // ≈ 0.08 秒
}

mod Combat {

    /// `hp` に `amount` のダメージを与えた結果。
    /// `newHp` はダメージ後の HP（負になり得る）。
    /// `isDead` は **このダメージで倒れたかどうか**（newHp <= 0）。
    /// 上位はこの判定で死亡演出 / waited 切替などを発火する。
    pub def damage(hp: {hp = Int32}, amount: {amount = Int32}):
            {newHp = Int32, isDead = Bool} =
        let newHp = hp#hp - amount#amount;
        {newHp = newHp, isDead = newHp <= 0}
}
