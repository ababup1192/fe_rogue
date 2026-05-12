/// Combat — 戦闘ダメージルールの純粋ロジック
///
/// HP に対するダメージ計算（残 HP と「倒れたか」の判定）を集約する。
/// 体当たり攻撃モーションの再生は AnimationPlayer + `attack_lunge` Animation
/// （PlayerScene.attackLungeAnimation）が担当し、HP 適用は `attack:hit` メソッド
/// 発火時に GameManager.dispatchAnimationEvents が呼ぶ Player/EnemyScene.applyAttackHit
/// 経由でこの Combat.damage を使う。
///
/// Scene[NodeTag] / effect には依存しない。テストは `hp` と `amount` だけで書ける。

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
