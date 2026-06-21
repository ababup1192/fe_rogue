/// Encumbrance — 重量制インベントリの純粋ロジック
///
/// 各アイテムの重量・ユニットの最大積載量・積載率・移動力ペナルティを計算する。
/// `Combat` / `LevelSystem` と同列の純粋モジュールで、Scene[NodeTag] / effect に依存しない
/// （テストが純粋値で完結する）。積載量の式・段階しきい値はこのモジュールに集約する。
///
/// 設計方針:
///   - 各アイテムの重量は resource の `weight` フィールド（Float64）で**直接指定**する。
///     武器/杖/消費/指輪すべてが weight を持ち、各 *.json / IDE で 1 個ずつ調整できる。
///     浮雲（指輪）は weight に負値を入れて積載を稼ぐ。
///
/// 積載率による移動力ペナルティ（floor で整数化）:
///   <80%: ×1.0(通常) / 80%+: ×0.8(軽量超過) / 100%+: ×0.3(重量オーバー) / 110%+: 0(重量過多)
mod Encumbrance {

    use WeaponCatalog.{WeaponResource}

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// 積載率の段階。移動力に掛ける係数を `tierFactor` で持つ。
    ///   - Normal     : <80%   ×1.0（通常）
    ///   - Heavy      : 80%+    ×0.8（軽量超過）
    ///   - Overloaded : 100%+   ×0.3（重量オーバー）
    ///   - Immobile   : 110%+   ×0  （重量過多・移動不可。攻撃/使用/投擲/破棄は可能）
    pub enum Tier with Eq, ToString {
        case Normal
        case Heavy
        case Overloaded
        case Immobile
    }

    /// 4 種別のインベントリ。row-polymorphic に受けるので `PlayerData.Data` をそのまま渡せる。
    pub type alias Inventory[r: RecordRow] = {
        weapons     = List[WeaponResource],
        staves      = List[Staff.StaffResource],
        consumables = List[Consumable.ConsumableResource],
        rings       = List[Ring.RingResource]
        | r
    }

    /// 1 ユニットの積載状態のまとめ。UI ゲージと移動計算の両方がこれを読む。
    /// `ratio` は total / capacity（capacity <= 0 は防御的に 1.0 とみなす）。
    pub type alias Load = {
        total    = Float64,
        capacity = Float64,
        ratio    = Float64,
        tier     = Tier
    }

    // ────────────────────────────────────────────────────────
    // (B) アイテム重量
    // ────────────────────────────────────────────────────────

    // 重量はどのアイテムも JSON の `weight` フィールドで直接指定する（計算式は使わない）。
    // デザイナが各 *.json / IDE で 1 個ずつ調整できる。浮雲(指輪)は負値で積載を稼ぐ。

    /// 武器の重量。
    pub def weaponWeight(weapon: WeaponResource): Float64 =
        weapon#weight

    /// 杖の重量。
    pub def staffWeight(staff: Staff.StaffResource): Float64 =
        staff#weight

    /// 消費アイテムの重量。
    pub def consumableWeight(item: Consumable.ConsumableResource): Float64 =
        item#weight

    /// 指輪の重量（浮雲は負値）。
    pub def ringWeight(ring: Ring.RingResource): Float64 =
        ring#weight

    /// 床アイテム（種別タグ付き）1 個の重量。拾得ゲートが「拾うと重くなる量」を測るのに使う。
    pub def groundItemWeight(kind: ItemData.GroundItemKind): Float64 = match kind {
        case ItemData.GroundItemKind.WeaponItem(weapon)   => weaponWeight(weapon)
        case ItemData.GroundItemKind.StaffItem(staff)     => staffWeight(staff)
        case ItemData.GroundItemKind.ConsumableItem(item) => consumableWeight(item)
        case ItemData.GroundItemKind.RingItem(ring)       => ringWeight(ring)
    }

    /// Float64 リストの総和（List.foldLeft で畳む）。
    def sumF(xs: List[Float64]): Float64 =
        List.foldLeft((acc, x) -> acc + x, 0.0, xs)

    /// インベントリ全体の総重量。0 で下限クランプする。
    /// 浮雲（負の重量の指輪）を積むと素の合計は負になりうるが、負を許すと
    /// 積載率が負＝常時 Normal かつ拾得ゲートが無効化して「実質無限積載」に退化する。
    /// 0 下限なら、浮雲は「他アイテムの重さを打ち消して実質容量を底上げする」効果に収まる。
    pub def totalWeight(inv: Inventory[r]): Float64 =
        let weaponTotal = sumF(List.map(weaponWeight, inv#weapons));
        let staffTotal = sumF(List.map(staffWeight, inv#staves));
        let consumableTotal = sumF(List.map(consumableWeight, inv#consumables));
        let ringTotal = sumF(List.map(ringWeight, inv#rings));
        Float64.max(0.0, weaponTotal + staffTotal + consumableTotal + ringTotal)

    // ────────────────────────────────────────────────────────
    // (C) 積載量・段階・移動力
    // ────────────────────────────────────────────────────────

    /// 最大積載量 = 体格×1.0 + 力×0.2 + 2.0。レベルアップで体格・力が伸びると増える。
    /// base を絞ってあるので低レベルでは武器 3〜4 本が上限の目安＝武器を選別させる狙い。
    pub def capacityOf(constitution: Int32, attack: Int32): Float64 =
        Int32.toFloat64(constitution) * 1.0 + Int32.toFloat64(attack) * 0.2 + 2.0

    /// 積載率から段階を決める。境界はちょうどの値を上の帯に含める（>=）。
    pub def tierOf(ratio: Float64): Tier =
        if (ratio >= 1.1)      Tier.Immobile
        else if (ratio >= 1.0) Tier.Overloaded
        else if (ratio >= 0.8) Tier.Heavy
        else                   Tier.Normal

    /// 段階から「素の移動力に掛ける係数」を返す。
    pub def tierFactor(tier: Tier): Float64 = match tier {
        case Tier.Normal     => 1.0
        case Tier.Heavy      => 0.8
        case Tier.Overloaded => 0.3
        case Tier.Immobile   => 0.0
    }

    /// 積載ペナルティ込みの実移動マス = floor(素の移動力 × 係数)。
    /// 重量過多(Immobile)だけは 0（移動不可）。それ以外の段階は floor で 0 に落ちても
    /// 最低 1 マスは保証する（「重量オーバー＝移動 30%」表記どおり、這ってでも動けるようにする。
    /// 移動力 3 のユニットが Overloaded で floor(0.9)=0 になって動けなくなるのを防ぐ）。
    /// 素の移動力を上限とするので、ペナルティで増えることはない。
    pub def effectiveMoveTiles(baseMoveTiles: Int32, load: Load): Int32 =
        let scaled = Int32.toFloat64(baseMoveTiles) * tierFactor(load#tier);
        let floored = Float64.floor(scaled) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        match load#tier {
            case Tier.Immobile => 0
            case _             => Int32.min(baseMoveTiles, Int32.max(1, floored))
        }

    /// インベントリ + 体格/力 から積載状態 Load を組む（UI・移動が共用する入口）。
    pub def loadOf(constitution: Int32, attack: Int32, inv: Inventory[r]): Load =
        let total = totalWeight(inv);
        let capacity = capacityOf(constitution, attack);
        let ratio = if (capacity <= 0.0) 1.0 else total / capacity;
        {total = total, capacity = capacity, ratio = ratio, tier = tierOf(ratio)}

    /// 追加重量 addedWeight を足すと重量過多(110%+)になるか。拾得ゲートに使う
    /// （拾うと移動不可になるアイテムは拾わせない＝詰み防止）。
    pub def wouldExceedImmobile(load: Load, addedWeight: Float64): Bool =
        if (load#capacity <= 0.0) true
        else (load#total + addedWeight) / load#capacity >= 1.1

    /// 重量を小数第 1 位までの文字列にする（例 12.5）。重量ゲージ・交換ヘッダの共通書式。
    /// 負の重量（浮雲の効果で総重量が下がった場合など）も符号付きで正しく出す。
    pub def weightText(weight: Float64): String =
        let tenths = Float64.round(weight * 10.0) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        let sign = if (tenths < 0) "-" else "";
        let abs = Int32.abs(tenths);
        "${sign}${abs / 10}.${Int32.remainder(abs, 10)}"

}
