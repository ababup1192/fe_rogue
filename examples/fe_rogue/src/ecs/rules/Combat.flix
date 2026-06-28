/// Combat — 戦闘ダメージルールの純粋ロジック
///
/// HP に対するダメージ計算（残 HP と「倒れたか」の判定）と、
/// スペック準拠の戦闘 4 値（攻 / 防 / 速）から 1 撃ぶんの「与: N / 命中: P% / 撃破」
/// を導く forecast を集約する。
///
/// 体当たり攻撃モーションの再生は AnimationPlayer + `attack_lunge` Animation
/// （CombatScene.attackLungeAnimation）が担当し、HP 適用は `attack:hit` メソッド
/// 発火時に CombatScene.process が呼ぶ CombatScene.onAttackHit
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
        Int32.max(0, Int32.min(100, accuracy - avoid))

    /// 命中ロールの判定。`hitRate` は 0..100 の命中率（百分率）、`roll` は 0..99 の
    /// 一様乱数を渡す想定（乱数生成は呼び出し側の effect で行い、ここは純粋に保つ）。
    /// `roll < hitRate` で命中。hitRate=100 なら常に命中、hitRate=0 なら常に回避。
    pub def isHit(hitRate: Int32, roll: Int32): Bool =
        roll < hitRate

    /// 命中確定前に「このダメージで倒せるか」を事前確認する純粋述語。
    /// `damage` と違い HP 状態を変えずに撃破可否だけを問い合わせる（命中前の予報/AI判断で使う）。
    pub def willKill(defenderHp: Int32, dmg: Int32): Bool =
        defenderHp - dmg <= 0

    /// 必殺(クリティカル)発動時のダメージ倍率（FE7 準拠で 3 倍）。
    def critMultiplier(): Int32 = 3

    /// 必殺率（百分率: 0..100）。FE7 式を簡略化（クラス補正なし）:
    ///   必殺率 = 武器必殺 + 攻撃側技÷2 − 防御側幸運（= 必殺回避）
    /// 命中とは独立に実戦闘でロールする（`hitRate` と同様、率を返すだけで乱数は引かない）。
    pub def critRate(weaponCrit: Int32, attackerSkill: Int32, defenderLuck: Int32): Int32 =
        Int32.max(0, Int32.min(100, weaponCrit + attackerSkill / 2 - defenderLuck))

    /// 必殺ロールの判定。`critRate` は 0..100、`roll` は 0..99 の一様乱数。
    /// `isHit` と同じ規約で `roll < critRate` で発動する。
    pub def isCrit(critRate: Int32, roll: Int32): Bool =
        roll < critRate

    /// 必殺確定時のダメージ再計算（純粋）。素ダメージ `baseDmg` を 3 倍し、防御側 HP に適用した
    /// `dmg`(=3倍値) / `newHp` / `killed` を返す。必殺でないときは呼ばない（呼び出し側で分岐）。
    pub def applyCrit(baseDmg: Int32, defenderHp: Int32):
            {dmg = Int32, newHp = Int32, killed = Bool} =
        let critDmg = baseDmg * critMultiplier();
        let result  = damage(hp = defenderHp, amount = critDmg);
        {dmg = critDmg, newHp = result#newHp, killed = result#isDead}

    /// 死神のネックレス(Finisher)発動時のダメージ(純粋)。瀕死の敵を**確実に倒す**。
    /// `applyCrit` と違い防御で 0 ダメージになっても倒せるよう、ダメージ下限を防御側の現 HP に
    /// 引き上げる（= `max(3倍, 現HP)`）。これにより硬い敵にも「必ず必殺」が成立する。
    pub def applyFinisher(baseDmg: Int32, defenderHp: Int32):
            {dmg = Int32, newHp = Int32, killed = Bool} =
        let finDmg = Int32.max(baseDmg * critMultiplier(), defenderHp);
        let result = damage(hp = defenderHp, amount = finDmg);
        {dmg = finDmg, newHp = result#newHp, killed = result#isDead}

    /// アイテム投擲の命中率（百分率）。基本 60%、命中の高い職（レンジャー / ローグ）は 80%。
    /// FE の命中式とは独立した固定値（投げは技量に依らずざっくり当たる想定）。
    pub def throwHitRate(accurate: Bool): Int32 =
        if (accurate) 80 else 60

    /// 武器を投げたときのダメージ。攻撃力（素ステ + 武器攻撃）の 8 割で、防御は無視する。
    /// 最低 1 を保証する（投げ当てれば必ず 1 は入る）。呼び出し側は防御を引かずにそのまま適用する。
    pub def thrownWeaponDamage(attackPower: Int32): Int32 =
        Int32.max(1, (attackPower * 4) / 5)

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
        attacker: {attack = Int32, skill = Int32, luck = Int32, weaponHit = Int32, weaponCrit = Int32},
        defender: {hp = Int32, defense = Int32, speed = Int32, luck = Int32},
        rel: WeaponTriangle.Relation
    ): {damage = Int32, hit = Int32, kill = Bool, crit = Int32} =
        let dmg = attackDamage(attacker#attack, defender#defense, rel);
        {
            damage = dmg,
            hit    = hitRate(attacker#skill, attacker#luck, attacker#weaponHit,
                             defender#speed, defender#luck, rel),
            kill   = willKill(defender#hp, dmg),
            crit   = critRate(attacker#weaponCrit, attacker#skill, defender#luck)
        }

    // ────────────────────────────────────────────────────────
    // faction 非依存の戦闘ビュー + 予報
    //   味方/敵どちらが攻撃側でも同じ経路を通すことで、
    //   物理/魔法・武器相性・習熟補正の分岐を呼び出し側に漏らさない。
    // ────────────────────────────────────────────────────────

    /// 1 ユニットを faction 非依存で見た戦闘ステータス。攻撃側はオフェンス値 + `weapon`、
    /// 防御側はディフェンス値 + `weapon`（相性判定用）を `estimate` が参照する。
    /// `weapon#isPhysical` は構築時に解決して持つ（`Combat` を `UnitCatalog` 非依存に保つ）。
    /// `hitMod` はこのユニット「自身の命中率」への一時補正（目潰し等のデバフは負値）。
    /// 習熟補正後の命中に加算する（`estimate` 参照）。バフ（攻撃・速さ）は `attack`/`speed`
    /// に反映済みの値を構築側（projection）で渡すため、ここに専用フィールドは持たない。
    /// `maxHp` は背水（Desperation）の「HP%」判定用に持つ（hp は現在値）。
    /// 武器サブレコードの `effect`/`effectValue` は背水の威力倍率判定に使う（他効果は CombatScene 側）。
    /// 装備武器の戦闘投影（`CombatView#weapon` の中身）。S-A0 で World read-model に格納するため named alias 化。
    pub type alias WeaponView = {weaponType = WeaponCatalog.WeaponType, attack = Int32,
                                 hit = Int32, crit = Int32, isPhysical = Bool, proficient = Bool,
                                 effect = WeaponCatalog.WeaponEffect, effectValue = Int32}

    pub type alias CombatView = {
        attack = Int32, magicAttack = Int32, defense = Int32, magicDefense = Int32,
        skill = Int32, speed = Int32, luck = Int32, hp = Int32, maxHp = Int32, hitMod = Int32,
        weapon = Option[WeaponView]
    }

    /// 装備武器（Option）から `CombatView#weapon` を組む。`isPhysical` をここで解決する。
    /// `proficient` は「この攻撃側がこの武器タイプを得意とするか」。苦手（false）なら
    /// `estimate` が威力・命中を 80% に下げる。敵は常に true（得意/苦手の概念なし）を渡す。
    pub def weaponView(weapon: Option[WeaponCatalog.WeaponResource], proficient: Bool):
            Option[WeaponView] =
        weapon |> Option.map(w ->
            {weaponType = w#weaponType, attack = w#attack, hit = w#hit, crit = w#crit,
             isPhysical = WeaponCatalog.isPhysical(w#weaponType), proficient = proficient,
             effect = w#effect, effectValue = w#effectValue})

    /// 武器タイプ習熟による補正。得意なら据え置き、苦手なら威力・命中を 80%（整数 ×4/5、切り捨て）に。
    /// 戦闘予報（`estimate`）と実ダメージ（PlayerScene の直接計算）の両方から呼んで一貫させる。
    pub def proficiencyAdjust(attack: Int32, hit: Int32, proficient: Bool): (Int32, Int32) =
        if (proficient) (attack, hit)
        else ((attack * 4) / 5, (hit * 4) / 5)

    /// 攻撃側 → 防御側 1 撃ぶんの予報（faction 非依存）。攻撃側が武器を持たないなら {0, 0, false}。
    /// 武器相性・物理/魔法・攻防の解決は `attackStatFor`/`defenseStatFor`/`WeaponTriangle.relationOpt`/
    /// `forecast` に委譲する（式は不変）。`damage` のみ欲しい呼び出し側は `#damage` を取る。
    pub def estimate(attacker: CombatView, defender: CombatView):
            {damage = Int32, hit = Int32, kill = Bool, crit = Int32} =
        match attacker#weapon {
            case None    => {damage = 0, hit = 0, kill = false, crit = 0}
            case Some(w) =>
                let rel = WeaponTriangle.relationOpt(w#weaponType,
                              defender#weapon |> Option.map(dw -> dw#weaponType));
                let atk = attackStatFor(attacker#attack, attacker#magicAttack, w#attack, w#isPhysical);
                let dfn = defenseStatFor(defender#defense, defender#magicDefense, w#isPhysical);
                // 苦手武器は威力・命中を 80% に下げる（得意ならそのまま）。必殺率は下げない。
                let (adjAtk, adjHit) = proficiencyAdjust(atk, w#hit, w#proficient);
                // 背水（Desperation）: 攻撃側の HP が effectValue% 以下なら威力 1.5 倍。
                // estimate 内で適用するので BattlePanel 予報と実ダメージが自動一致する。
                let despAtk = match WeaponCatalog.desperationThreshold(w#effect, w#effectValue) {
                    case Some(pct) =>
                        if (attacker#hp * 100 <= attacker#maxHp * pct) (adjAtk * 3) / 2 else adjAtk
                    case None      => adjAtk
                };
                // 時限デバフ（目潰し等）の命中補正を習熟補正の「後」に加算する。
                // ×4/5 を通さないことで「-25%」がそのまま -25 として効く（0 未満は 0 に丸める）。
                let adjHit2 = Int32.max(0, adjHit + attacker#hitMod);
                forecast(
                    {attack = despAtk, skill = attacker#skill, luck = attacker#luck,
                     weaponHit = adjHit2, weaponCrit = w#crit},
                    {hp = defender#hp, defense = dfn, speed = defender#speed, luck = defender#luck},
                    rel)
        }

    // ────────────────────────────────────────────────────────
    // 経験値（EXP）— レベル差ベース
    //   命中で必ず得る「戦闘経験値」と、撃破時に上乗せする「撃破経験値」を、
    //   敵と自分のレベル差から導く。攻撃 1 回が生む結果の一部なのでここ（Combat）に置く。
    //   本作には上級職・プレイモード差・ボス/シーフ補正が無いので、それらの項は省略。
    // ────────────────────────────────────────────────────────

    /// クラスの強さ（全ユニット共通の除数・係数）。値が大きいほど 1 戦闘で得る EXP が小さくなる。
    /// 敵ほど高レベル差でも経験値が大きく増えすぎないよう除数を小さく保つ（大きくするほど成長が鈍くなる）。
    def classPower(): Int32 = 2

    /// 戦闘経験値の基準値（計算式の「31 +」に相当）。FE6 本家は 31 固定。
    /// 増やすと同レベル帯でも EXP が増し、減らすと高レベル敵を狩らないと育ちにくくなる。
    /// `hitExp` の最低保証 1 に抵触するのはレベル差が 30 超のとき（baseHitExp - 30 < classPower が目安）。
    def baseHitExp(): Int32 = 31

    /// 撃破経験値の固定加算（計算式の「+ 20」に相当）。FE6 本家は 20 固定。
    /// 増やすと撃破を狙う戦術的インセンティブが強まる。0 にすると撃破ボーナスが式の係数項だけになる。
    def killFlat(): Int32 = 20

    /// 命中したとき必ず得る「戦闘経験値」。(31 + 敵Lv − 自Lv) ÷ クラスの強さ。
    /// 整数除算（0 方向に切り捨て）で、自分が高レベルでも最低 1 は得る。
    pub def hitExp(enemyLevel: Int32, selfLevel: Int32): Int32 =
        Int32.max(1, (baseHitExp() + enemyLevel - selfLevel) / classPower())

    /// 撃破時に上乗せする「撃破経験値」。max(0, クラスの強さ ×(敵Lv − 自Lv) + 20)。
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
