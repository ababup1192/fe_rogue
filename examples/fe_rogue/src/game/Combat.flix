/// Combat — 戦闘ダメージルールの純粋ロジック
///
/// HP に対するダメージ計算（残 HP と「倒れたか」の判定）と、
/// スペック準拠の戦闘 4 値（攻 / 防 / 速）から 1 撃ぶんの「与: N / 命中: P% / 撃破」
/// を導く forecast を集約する。
///
/// 体当たり攻撃モーションの再生は AnimationPlayer + `attack_lunge` Animation
/// （PlayerScene.attackLungeAnimation）が担当し、HP 適用は `attack:hit` メソッド
/// 発火時に GameManager.dispatchAnimationEvents が呼ぶ Player/EnemyScene.applyAttackHit
/// 経由でここの関数を使う。
///
/// Scene[NodeTag] / effect には依存しない。テストは数値だけで書ける。

mod Combat {

    /// `hp` に `amount` のダメージを与えた結果。
    /// `newHp` はダメージ後の HP（負になり得る）。
    /// `isDead` は **このダメージで倒れたかどうか**（newHp <= 0）。
    /// 上位はこの判定で死亡演出 / waited 切替などを発火する。
    pub def damage(hp: {hp = Int32}, amount: {amount = Int32}):
            {newHp = Int32, isDead = Bool} =
        let newHp = hp#hp - amount#amount;
        {newHp = newHp, isDead = newHp <= 0}

    /// 攻撃側の「攻」と防御側の「防」から 1 撃ぶんの素ダメージを返す。
    /// `max(0, attack - defense)` の単純引き算。下限 0（防御が攻撃以上なら 0 ダメ）。
    /// 0 は仕様上ありうる（弱攻撃が硬い相手に通らない）。最低 1 保証はしない。
    pub def attackDamage(attack: Int32, defense: Int32): Int32 =
        Int32.max(0, attack - defense)

    /// 装備武器の `isPhysical` に応じて、攻撃側の素ステ + 武器ボーナスの「総合攻撃力」を返す。
    /// 物理: `attack + weaponAttack`、魔法: `magicAttack + weaponAttack`。
    /// 呼び出し側 (PlayerScene / EnemyScene / BattlePanelScene) で同じ分岐を書かないように
    /// 1 箇所に集約する。`forecast` / `attackDamage` の入力として使う。
    /// Flix のレコード型は exact なので row polymorphism を避けてスカラー引数で受ける。
    pub def attackStatFor(attack: Int32, magicAttack: Int32,
                           weaponAttack: Int32, isPhysical: Bool): Int32 =
        if (isPhysical) attack + weaponAttack
        else magicAttack + weaponAttack

    /// 装備武器の `isPhysical` に応じて、防御側が参照すべきステを返す。
    /// 物理武器に対しては `defense`、魔法武器に対しては `magicDefense`。
    pub def defenseStatFor(defense: Int32, magicDefense: Int32, isPhysical: Bool): Int32 =
        if (isPhysical) defense else magicDefense

    /// 攻撃の命中率（百分率: 0..100）。
    /// 基準 80% に「攻撃側速 - 防御側速」× 5 を加算してクランプ:
    ///   - 速さ同等        → 80%
    ///   - 攻撃側 +4 速い → 100% （上限）
    ///   - 防御側 +4 速い → 60%
    ///   - 防御側 +15 速い → 5%   （下限 5% で常に勝機を残す）
    /// 数値は仮置き。バランス調整時は係数とクランプ範囲だけ触ればよい。
    pub def hitRate(attackerSpeed: Int32, defenderSpeed: Int32): Int32 =
        let raw = 80 + (attackerSpeed - defenderSpeed) * 5;
        // clamp(5, 100, raw) = max(5, min(100, raw))
        Int32.max(5, Int32.min(100, raw))

    /// `damage` 適用で防御側 HP が 0 以下になるか（撃破か）。
    pub def willKill(defenderHp: Int32, dmg: Int32): Bool =
        defenderHp - dmg <= 0

    /// 回復計算。`currentHp` に `amount` を加算した結果を返す。
    /// `maxHp` を超える分はクランプ（過剰回復は無効）。
    /// `amount` が負なら回復量 0 に丸める（ダメージ用途と分離するため負の amount は無視）。
    /// 戻り値の `newHp` は 0..maxHp の範囲に必ず収まる。
    /// 杖の「ライブのつえ」の HP 適用に使う。
    pub def heal(currentHp: Int32, maxHp: Int32, amount: Int32): {newHp = Int32} =
        let effective = Int32.max(0, amount);
        let raw = currentHp + effective;
        {newHp = Int32.min(maxHp, raw)}

    /// 1 撃ぶんの予報。スペックの「与:N 命中:P% 撃破」表示に直接対応する。
    /// damage = max(0, attack - defense)、hit = hitRate(...)、kill = willKill(...)。
    /// 攻撃 UI で命中前にプレビューするのに使う想定（現状はログ出力にのみ流す）。
    pub def forecast(
        attacker: {attack = Int32, speed = Int32},
        defender: {hp = Int32, defense = Int32, speed = Int32}
    ): {damage = Int32, hit = Int32, kill = Bool} =
        let dmg = attackDamage(attacker#attack, defender#defense);
        {
            damage = dmg,
            hit    = hitRate(attacker#speed, defender#speed),
            kill   = willKill(defender#hp, dmg)
        }
}
