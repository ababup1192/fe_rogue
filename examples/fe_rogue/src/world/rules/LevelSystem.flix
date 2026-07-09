/// LevelSystem — EXP 蓄積・レベルアップ・ステータス成長の純粋ロジック
///
/// `Combat.flix`（戦闘の純粋な計算）と同列の、副作用を持たないモジュール。
/// 乱数や Scene を一切触らず、入力値から結果を計算するだけにしてある。
/// 「成長判定の乱数」は呼び出し側（`PlayerDriver.applyDamageToEnemy`）が振った
/// 0..99 の値を `Rolls` として受け取るので、テストは決め打ちの値だけで完結する。
///
/// 方式:
///   - 1 戦闘で得る EXP の「獲得量」は `Combat.battleExp`（レベル差ベース）が算出する。
///   - EXP は 0..99 で管理し、100 到達でレベルアップ（余剰は繰り越し、`gainExp`）。
///   - レベルアップ時、ステータスごとに 0..99 の乱数を振り `乱数 < 成長率` なら +1（`applyGrowth`）。
mod LevelSystem {

    use UnitCatalog.{UnitResource, GrowthRates}

    /// 成長対象の 9 ステータス。`hp` は最大 HP を指す。`moveTiles` は成長対象外なので含めない。
    /// `constitution`（体格）は最大積載量に効く成長ステータス。
    pub type alias Stats = {
        hp           = Int32,
        attack       = Int32,
        defense      = Int32,
        magicAttack  = Int32,
        magicDefense = Int32,
        speed        = Int32,
        skill        = Int32,
        luck         = Int32,
        constitution = Int32
    }

    /// 成長判定に使う各ステータスの乱数（いずれも 0..99）。呼び出し側が振って渡す。
    pub type alias Rolls = {
        hp           = Int32,
        attack       = Int32,
        defense      = Int32,
        magicAttack  = Int32,
        magicDefense = Int32,
        speed        = Int32,
        skill        = Int32,
        luck         = Int32,
        constitution = Int32
    }

    /// パネル 1 行ぶんのステータス変化。`gained` が true なら上昇（パネルで (+1) を出す）。
    pub type alias StatChange = {
        label  = String,
        before = Int32,
        after  = Int32,
        gained = Bool
    }

    /// レベルアップ結果。ステータス変化パネルが表示にそのまま使う。
    /// `changes` は HP / 力 / 魔力 / 技 / 速さ / 幸運 / 守備 / 魔防 / 体格 の固定 9 行（`buildResult` の並び順と一致）。
    pub type alias Result = {
        unitName  = String,
        fromLevel = Int32,
        toLevel   = Int32,
        changes   = List[StatChange]
    }

    /// SRPG 標準の 100 を採用。1 攻撃の最大獲得量が 100 未満のため、1 戦闘で 2 連続レベルアップは起きない。
    pub def levelThreshold(): Int32 = 100

    /// 現在 EXP に `gain` を足し、100 到達でレベルアップしたかを返す。
    /// レベルアップ時は 100 を引いた余剰を繰り越す。1 回で 2 レベルは想定しない
    /// （1 攻撃の獲得量は 100 未満のため）。
    pub def gainExp(exp: Int32, gain: Int32): {exp = Int32, levelUp = Bool} =
        let total = exp + gain;
        if (total >= levelThreshold())
            {exp = total - levelThreshold(), levelUp = true}
        else
            {exp = total, levelUp = false}

    /// 成長判定 1 つ。乱数が成長率を下回れば成長する（`roll < rate`）。
    /// 成長率 0 なら決して成長せず、100 なら必ず成長する。
    pub def grew(roll: Int32, rate: Int32): Bool = roll < rate

    /// レベルアップ時の成長を適用する。
    /// `grew` を独立した述語として分離したのは、成長判定単体をテスト・再利用できるようにするため。
    /// この関数は乱数を持たず、外から注入された `Rolls` だけで確定的に動く。
    pub def applyGrowth(stats: Stats, rates: GrowthRates, rolls: Rolls): Stats =
        let bump = (value, roll, rate) -> if (grew(roll, rate)) value + 1 else value;
        {hp           = bump(stats#hp,           rolls#hp,           rates#hp),
         attack       = bump(stats#attack,       rolls#attack,       rates#attack),
         defense      = bump(stats#defense,      rolls#defense,      rates#defense),
         magicAttack  = bump(stats#magicAttack,  rolls#magicAttack,  rates#magicAttack),
         magicDefense = bump(stats#magicDefense, rolls#magicDefense, rates#magicDefense),
         speed        = bump(stats#speed,        rolls#speed,        rates#speed),
         skill        = bump(stats#skill,        rolls#skill,        rates#skill),
         luck         = bump(stats#luck,         rolls#luck,         rates#luck),
         constitution = bump(stats#constitution, rolls#constitution, rates#constitution)}

    /// UnitResource から成長対象の 9 ステータスだけを抜き出す（hp は最大 HP）。
    /// UnitResource は成長対象外のフィールド（moveTiles 等）も持つため、
    /// このプロジェクションで成長ロジックが余分なフィールドを誤って触らないようにしている。
    pub def statsOf(res: UnitResource): Stats =
        {hp           = res#hp,
         attack       = res#attack,
         defense      = res#defense,
         magicAttack  = res#magicAttack,
         magicDefense = res#magicDefense,
         speed        = res#speed,
         skill        = res#skill,
         luck         = res#luck,
         constitution = res#constitution}

    /// 全 0 の `Stats`（テスト/プレースホルダ用。`SimEvent.LeveledUp` の `grownStats` ダミー等）。
    pub def zeroStats(): Stats =
        {hp = 0, attack = 0, defense = 0, magicAttack = 0, magicDefense = 0,
         speed = 0, skill = 0, luck = 0, constitution = 0}

    /// 成長後の 9 ステータスを UnitResource に書き戻す（他フィールドは保つ）。
    /// `statsOf` の逆演算として設計されており、`statsOf` → `applyGrowth` → `withStats` で
    /// UnitResource のラウンドトリップが成立する。
    pub def withStats(stats: Stats, res: UnitResource): UnitResource =
        {hp           = stats#hp,
         attack       = stats#attack,
         defense      = stats#defense,
         magicAttack  = stats#magicAttack,
         magicDefense = stats#magicDefense,
         speed        = stats#speed,
         skill        = stats#skill,
         luck         = stats#luck,
         constitution = stats#constitution | res}

    // 漢字表記はパネルの表示文字列と 1 対 1 で対応させる。変更時は UI 側と合わせること。
    def label1Hp(): String           = "HP"
    def labelAttack(): String        = "力"
    def labelDefense(): String       = "守備"
    def labelMagicAttack(): String   = "魔力"
    def labelMagicDefense(): String  = "魔防"
    def labelSpeed(): String         = "速さ"
    def labelSkill(): String         = "技"
    def labelLuck(): String          = "幸運"
    def labelConstitution(): String  = "体格"

    /// 1 行ぶんの変化を作る。`after > before` のときのみ `gained = true`（同値なら false）。
    def change(label: String, before: Int32, after: Int32): StatChange =
        {label = label, before = before, after = after, gained = after > before}

    /// レベルアップ前後のステータスから、パネル表示用の `Result` を組み立てる。
    /// `toLevel` は `fromLevel + 1`。`changes` は固定 9 行（HP→力→魔力→技→速さ→幸運→守備→魔防→体格）。
    /// この並び順はパネルのレイアウト（行の上から下）に対応しており、UI 側と合わせる必要がある（line 108 参照）。
    pub def buildResult(unitName: String, fromLevel: Int32,
                        before: Stats, after: Stats): Result =
        {unitName  = unitName,
         fromLevel = fromLevel,
         toLevel   = fromLevel + 1,
         changes   =
             change(label1Hp(),          before#hp,           after#hp)           ::
             change(labelAttack(),       before#attack,       after#attack)       ::
             change(labelMagicAttack(),  before#magicAttack,  after#magicAttack)  ::
             change(labelSkill(),        before#skill,        after#skill)        ::
             change(labelSpeed(),        before#speed,        after#speed)        ::
             change(labelLuck(),         before#luck,         after#luck)         ::
             change(labelDefense(),      before#defense,      after#defense)      ::
             change(labelMagicDefense(), before#magicDefense, after#magicDefense) ::
             change(labelConstitution(), before#constitution, after#constitution) :: Nil}

}
