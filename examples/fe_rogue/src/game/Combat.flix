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

    /// 攻撃の命中率（百分率: 0..100）。FE6 の命中・回避式に準拠:
    ///   命中  = 武器命中 + 技×2 + 幸運÷2
    ///   回避  = 速さ×2 + 幸運
    ///   命中率 = clamp(0, 100, 命中 - 回避)
    /// 支援・地形・武器相性（→ #3）・武器重さ／体格は今回スコープ外。
    /// 速さはそのまま攻撃速度として扱う（重さ補正なし）。
    pub def hitRate(
        attackerSkill: Int32, attackerLuck: Int32, weaponHit: Int32,
        defenderSpeed: Int32, defenderLuck: Int32
    ): Int32 =
        let accuracy = weaponHit + attackerSkill * 2 + attackerLuck / 2;
        let avoid    = defenderSpeed * 2 + defenderLuck;
        // clamp(0, 100, accuracy - avoid)
        Int32.max(0, Int32.min(100, accuracy - avoid))

    /// 命中ロールの判定。`hitRate` は 0..100 の命中率（百分率）、`roll` は 0..99 の
    /// 一様乱数を渡す想定（乱数生成は呼び出し側の effect で行い、ここは純粋に保つ）。
    /// `roll < hitRate` で命中。hitRate=100 なら常に命中、hitRate=0 なら常に回避。
    pub def isHit(hitRate: Int32, roll: Int32): Bool =
        roll < hitRate

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
    /// 命中の内訳は攻撃側の技・幸運・武器命中、防御側の速さ・幸運で決まる（FE6 式）。
    /// 攻撃 UI で命中前にプレビューするのに使う想定（現状はログ出力にのみ流す）。
    pub def forecast(
        attacker: {attack = Int32, skill = Int32, luck = Int32, weaponHit = Int32},
        defender: {hp = Int32, defense = Int32, speed = Int32, luck = Int32}
    ): {damage = Int32, hit = Int32, kill = Bool} =
        let dmg = attackDamage(attacker#attack, defender#defense);
        {
            damage = dmg,
            hit    = hitRate(attacker#skill, attacker#luck, attacker#weaponHit,
                             defender#speed, defender#luck),
            kill   = willKill(defender#hp, dmg)
        }
}
