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

    /// 武器相性による攻撃力補正。有利で +1、不利で -1、中立で 0。
    /// 三竦み（剣 → 斧 → 槍）で有利な側のダメージを底上げする。
    def attackBonus(rel: WeaponTriangle.Relation): Int32 = match rel {
        case WeaponTriangle.Relation.Advantage    => 1
        case WeaponTriangle.Relation.Disadvantage => -1
        case WeaponTriangle.Relation.Neutral      => 0
    }

    /// 武器相性による命中補正。有利で +15、不利で -15、中立で 0。
    def hitBonus(rel: WeaponTriangle.Relation): Int32 = match rel {
        case WeaponTriangle.Relation.Advantage    => 15
        case WeaponTriangle.Relation.Disadvantage => -15
        case WeaponTriangle.Relation.Neutral      => 0
    }

    /// 攻撃側の「攻」と防御側の「防」、武器相性から 1 撃ぶんの素ダメージを返す。
    /// `max(0, attack + 相性補正 - defense)`。相性補正は有利 +1 / 不利 -1 / 中立 0。
    /// 下限 0（補正後でも防御が攻撃以上なら 0 ダメ）。最低 1 保証はしない。
    pub def attackDamage(attack: Int32, defense: Int32, rel: WeaponTriangle.Relation): Int32 =
        Int32.max(0, attack + attackBonus(rel) - defense)

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

    /// 攻撃の命中率（百分率: 0..100）。FE6 の命中・回避式 + 武器相性補正に準拠:
    ///   命中  = 武器命中 + 技×2 + 幸運÷2 + 相性補正（有利 +15 / 不利 -15 / 中立 0）
    ///   回避  = 速さ×2 + 幸運
    ///   命中率 = clamp(0, 100, 命中 - 回避)
    /// 支援・地形・武器重さ／体格は今回スコープ外。
    /// 速さはそのまま攻撃速度として扱う（重さ補正なし）。
    pub def hitRate(
        attackerSkill: Int32, attackerLuck: Int32, weaponHit: Int32,
        defenderSpeed: Int32, defenderLuck: Int32,
        rel: WeaponTriangle.Relation
    ): Int32 =
        let accuracy = weaponHit + attackerSkill * 2 + attackerLuck / 2 + hitBonus(rel);
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
    /// damage = max(0, attack + 相性補正 - defense)、hit = hitRate(...)、kill = willKill(...)。
    /// 命中の内訳は攻撃側の技・幸運・武器命中、防御側の速さ・幸運、武器相性で決まる（FE6 式）。
    /// `rel` は攻撃側武器から見た防御側武器との相性（有利 / 不利 / 中立）。
    /// 攻撃 UI で命中前にプレビューするのに使う想定。
    pub def forecast(
        attacker: {attack = Int32, skill = Int32, luck = Int32, weaponHit = Int32},
        defender: {hp = Int32, defense = Int32, speed = Int32, luck = Int32},
        rel: WeaponTriangle.Relation
    ): {damage = Int32, hit = Int32, kill = Bool} =
        let dmg = attackDamage(attacker#attack, defender#defense, rel);
        {
            damage = dmg,
            hit    = hitRate(attacker#skill, attacker#luck, attacker#weaponHit,
                             defender#speed, defender#luck, rel),
            kill   = willKill(defender#hp, dmg)
        }

    // ────────────────────────────────────────────────────────
    // faction 非依存の戦闘ビュー + 予報
    //   位置×ステータスの結合（味方/敵どちらが攻撃側でも）を 1 経路に集約する。
    //   旧 `EnemyScene.estimateDamage` と BattlePanel のインライン予報がここを通る。
    // ────────────────────────────────────────────────────────

    /// 1 ユニットを faction 非依存で見た戦闘ステータス。攻撃側はオフェンス値 + `weapon`、
    /// 防御側はディフェンス値 + `weapon`（相性判定用）を `estimate` が参照する。
    /// `weapon#isPhysical` は構築時に解決して持つ（`Combat` を `UnitCatalog` 非依存に保つ）。
    pub type alias CombatView = {
        attack = Int32, magicAttack = Int32, defense = Int32, magicDefense = Int32,
        skill = Int32, speed = Int32, luck = Int32, hp = Int32,
        weapon = Option[{weaponType = WeaponCatalog.WeaponType, attack = Int32,
                          hit = Int32, isPhysical = Bool, proficient = Bool}]
    }

    /// 装備武器（Option）から `CombatView#weapon` を組む。`isPhysical` をここで解決する。
    /// `proficient` は「この攻撃側がこの武器タイプを得意とするか」。苦手（false）なら
    /// `estimate` が威力・命中を 80% に下げる。敵は常に true（得意/苦手の概念なし）を渡す。
    pub def weaponView(weapon: Option[WeaponCatalog.WeaponResource], proficient: Bool):
            Option[{weaponType = WeaponCatalog.WeaponType, attack = Int32,
                    hit = Int32, isPhysical = Bool, proficient = Bool}] =
        weapon |> Option.map(w ->
            {weaponType = w#weaponType, attack = w#attack, hit = w#hit,
             isPhysical = WeaponCatalog.isPhysical(w#weaponType), proficient = proficient})

    /// 武器タイプ習熟による補正。得意なら据え置き、苦手なら威力・命中を 80%（整数 ×4/5、切り捨て）に。
    /// 戦闘予報（`estimate`）と実ダメージ（PlayerScene の直接計算）の両方から呼んで一貫させる。
    pub def proficiencyAdjust(attack: Int32, hit: Int32, proficient: Bool): (Int32, Int32) =
        if (proficient) (attack, hit)
        else ((attack * 4) / 5, (hit * 4) / 5)

    /// 攻撃側 → 防御側 1 撃ぶんの予報（faction 非依存）。攻撃側が武器を持たないなら {0, 0, false}。
    /// 武器相性・物理/魔法・攻防の解決は `attackStatFor`/`defenseStatFor`/`WeaponTriangle.relationOpt`/
    /// `forecast` に委譲する（式は不変）。`damage` のみ欲しい呼び出し側は `#damage` を取る。
    pub def estimate(attacker: CombatView, defender: CombatView):
            {damage = Int32, hit = Int32, kill = Bool} =
        match attacker#weapon {
            case None    => {damage = 0, hit = 0, kill = false}
            case Some(w) =>
                let rel = WeaponTriangle.relationOpt(w#weaponType,
                              defender#weapon |> Option.map(dw -> dw#weaponType));
                let atk = attackStatFor(attacker#attack, attacker#magicAttack, w#attack, w#isPhysical);
                let dfn = defenseStatFor(defender#defense, defender#magicDefense, w#isPhysical);
                // 苦手武器は威力・命中を 80% に下げる（得意ならそのまま）。
                let (adjAtk, adjHit) = proficiencyAdjust(atk, w#hit, w#proficient);
                forecast(
                    {attack = adjAtk, skill = attacker#skill, luck = attacker#luck, weaponHit = adjHit},
                    {hp = defender#hp, defense = dfn, speed = defender#speed, luck = defender#luck},
                    rel)
        }

    // ────────────────────────────────────────────────────────
    // 経験値（EXP）— FE7 流のレベル差ベース
    //   命中で必ず得る「戦闘経験値」と、撃破時に上乗せする「撃破経験値」を、
    //   敵と自分のレベル差から導く。攻撃 1 回が生む結果の一部なのでここ（Combat）に置く。
    //   本作には上級職・プレイモード差・ボス/シーフ/瞬殺が無いので、それらの項は 0 / ×1。
    // ────────────────────────────────────────────────────────

    /// クラスの強さ（全ユニット共通の除数・係数）。値が大きいほど 1 戦闘で得る EXP が小さくなる。要調整。
    def classPower(): Int32 = 3

    /// 戦闘経験値の基準値（FE7 の式の「31 +」に相当）。要調整。
    def baseHitExp(): Int32 = 31

    /// 撃破経験値の固定加算（FE7 の式の「+ 20」に相当）。要調整。
    def killFlat(): Int32 = 20

    /// 命中したとき必ず得る「戦闘経験値」。FE7: (31 + 敵Lv − 自Lv) ÷ クラスの強さ。
    /// 整数除算（0 方向に切り捨て）で、自分が高レベルでも最低 1 は得る。
    pub def hitExp(enemyLevel: Int32, selfLevel: Int32): Int32 =
        Int32.max(1, (baseHitExp() + enemyLevel - selfLevel) / classPower())

    /// 撃破時に上乗せする「撃破経験値」。FE7: max(0, クラスの強さ ×(敵Lv − 自Lv) + 20)。
    /// 自分より十分弱い敵を倒しても 0 にクランプ（撃破ボーナスが付かない）。
    pub def killExp(enemyLevel: Int32, selfLevel: Int32): Int32 =
        Int32.max(0, classPower() * (enemyLevel - selfLevel) + killFlat())

    /// 1 回の攻撃で得る EXP。命中したら `hitExp`、さらに撃破なら `killExp` を足す。
    /// ミス（非命中）で 0 にするのは呼び出し側（命中判定の分岐）の責務。
    pub def battleExp(enemyLevel: Int32, selfLevel: Int32, killed: Bool): Int32 =
        hitExp(enemyLevel, selfLevel) + (if (killed) killExp(enemyLevel, selfLevel) else 0)
}

/// WeaponTriangle — 武器の三竦み（剣 → 斧 → 槍 → 剣）の純粋判定。
///
/// 各矢印が「有利」方向を表す: 剣は斧に、斧は槍に、槍は剣に有利。
/// 弓・魔法は三竦みの外で常に中立。
/// Scene[NodeTag] / effect / 数値補正には依存しない（補正値の適用は `Combat` 側）。
/// 戦闘計算の純粋ロジックとして Combat と同居させ、テストも数値だけで書ける。
mod WeaponTriangle {

    use WeaponCatalog.WeaponType

    /// 攻撃側の武器から見た、防御側の武器との相性。
    pub enum Relation with Eq, ToString {
        case Advantage     // 有利（攻撃 +1 / 命中 +15）
        case Disadvantage  // 不利（攻撃 -1 / 命中 -15）
        case Neutral       // 補正なし（同種・弓・魔法が絡む組合せ）
    }

    /// `attacker` の武器が `defender` の武器に対して三竦みで有利か。
    /// 有利な辺は剣 → 斧 → 槍 → 剣 の 3 本だけ。不利は `relation` 側で向きを反転して導く。
    /// 武器種を増やす場合はこの辺の一覧に追記すればよい。
    def beats(attacker: WeaponType, defender: WeaponType): Bool =
        match (attacker, defender) {
            case (WeaponType.Sword, WeaponType.Axe)   => true
            case (WeaponType.Axe,   WeaponType.Lance) => true
            case (WeaponType.Lance, WeaponType.Sword) => true
            case _                                    => false
        }

    /// 三竦みの相性。有利な辺なら `Advantage`、その逆向きなら `Disadvantage`、
    /// それ以外（同種同士・弓・魔法が絡む組合せ）は `Neutral`。
    pub def relation(attacker: WeaponType, defender: WeaponType): Relation =
        if (beats(attacker, defender))      Relation.Advantage
        else if (beats(defender, attacker)) Relation.Disadvantage
        else                                Relation.Neutral

    /// 防御側が武器未装備（`None`）なら `Neutral`。`Option` を剥がす呼び出し側向けヘルパ。
    pub def relationOpt(attacker: WeaponType, defender: Option[WeaponType]): Relation =
        defender |> Option.map(relation(attacker)) |> Option.getWithDefault(Relation.Neutral)
}
