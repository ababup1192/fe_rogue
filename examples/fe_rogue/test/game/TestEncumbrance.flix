/// Encumbrance（重量制）の純粋ロジックのテスト。
///
/// 検証する責務:
///   - 最大積載量の式（体格×1.0 + 力×0.2 + 2.0）
///   - 積載率 → 段階（Tier）の境界（0.8 / 1.0 / 1.1 をちょうどで上の帯に含める）
///   - 段階 → 実効移動力（floor で整数化、Immobile=0）
///   - 武器タイプ別の重量（暗器は最軽量、強武器ほど重い）
///   - 拾得ゲート（拾うと重量過多になるか）
mod TestEncumbrance {

    use Encumbrance.Tier
    use Encumbrance.Load

    /// Float64 の近似比較（積載量は 1.3 等の二進非正確な係数を含むため厳密一致は使わない）。
    def approxEq(actual: Float64, expected: Float64): Bool =
        Float64.abs(actual - expected) < 0.0001

    /// Tier だけ差し替えた Load を作るテスト用ヘルパ（effectiveMoveTiles は tier しか見ない）。
    def loadWithTier(tier: Tier): Load =
        {total = 0.0, capacity = 10.0, ratio = 0.0, tier = tier}

    // ──────────────────────────────────────────────
    // 最大積載量
    // ──────────────────────────────────────────────

    /// capacityOf = 体格×1.0 + 力×0.2 + 2.0。
    /// ファイター(体格7,力6)=10.2 / メイジ(体格5,力0)=7.0 / バーバリアン(体格9,力8)=12.6。
    @Test
    def testCapacityOf(): Unit \ Assert =
        let checks =
            approxEq(Encumbrance.capacityOf(7, 6), 10.2) ::
            approxEq(Encumbrance.capacityOf(5, 0), 7.0) ::
            approxEq(Encumbrance.capacityOf(9, 8), 12.6) :: Nil;
        Assert.assertEq(expected = true :: true :: true :: Nil, checks)

    // ──────────────────────────────────────────────
    // 積載率 → 段階
    // ──────────────────────────────────────────────

    /// tierOf の境界: 0.79=Normal / 0.80=Heavy / 1.0=Overloaded / 1.10=Immobile。
    /// ちょうどの値（0.80 等）は上の帯に含める（>= 判定）。
    @Test
    def testTierBoundaries(): Unit \ Assert =
        Assert.assertEq(
            expected = Tier.Normal :: Tier.Heavy :: Tier.Overloaded :: Tier.Immobile :: Nil,
            Encumbrance.tierOf(0.79) :: Encumbrance.tierOf(0.80) ::
            Encumbrance.tierOf(1.0)  :: Encumbrance.tierOf(1.10) :: Nil)

    // ──────────────────────────────────────────────
    // 段階 → 実効移動力（floor で整数化）
    // ──────────────────────────────────────────────

    /// 素の移動力 5 のユニットの実効移動力:
    ///   Normal=5 / Heavy=floor(5×0.8)=4 / Overloaded=floor(5×0.3)=1 / Immobile=0。
    @Test
    def testEffectiveMoveTiles(): Unit \ Assert =
        Assert.assertEq(
            expected = 5 :: 4 :: 1 :: 0 :: Nil,
            Encumbrance.effectiveMoveTiles(5, loadWithTier(Tier.Normal)) ::
            Encumbrance.effectiveMoveTiles(5, loadWithTier(Tier.Heavy)) ::
            Encumbrance.effectiveMoveTiles(5, loadWithTier(Tier.Overloaded)) ::
            Encumbrance.effectiveMoveTiles(5, loadWithTier(Tier.Immobile)) :: Nil)

    // ──────────────────────────────────────────────
    // 武器タイプ別の重量
    // ──────────────────────────────────────────────

    /// weaponWeight = タイプ基準 + 攻撃力×係数:
    ///   暗器(atk3)=0.8+0.3=1.1 / 剣(atk5)=1.5+0.75=2.25 / 斧(atk13)=2.5+1.95=4.45。
    @Test
    def testWeaponWeightByType(): Unit \ Assert =
        let dagger = TestUnitFixtures.testWeaponWithType(3, WeaponCatalog.WeaponType.Dagger);
        let sword  = TestUnitFixtures.testWeaponWithType(5, WeaponCatalog.WeaponType.Sword);
        let axe    = TestUnitFixtures.testWeaponWithType(13, WeaponCatalog.WeaponType.Axe);
        let checks =
            approxEq(Encumbrance.weaponWeight(dagger), 1.1) ::
            approxEq(Encumbrance.weaponWeight(sword), 2.25) ::
            approxEq(Encumbrance.weaponWeight(axe), 4.45) :: Nil;
        Assert.assertEq(expected = true :: true :: true :: Nil, checks)

    // ──────────────────────────────────────────────
    // 統合: loadOf（武器2本のみのインベントリ）
    // ──────────────────────────────────────────────

    /// loadOf: 剣(atk5)×2=4.5、体格7力6で capacity 10.2 → ratio<0.8 で Normal。
    @Test
    def testLoadOfWeaponsOnly(): Unit \ Assert =
        let sword = TestUnitFixtures.testWeaponWithType(5, WeaponCatalog.WeaponType.Sword);
        let inv = {
            weapons     = sword :: sword :: Nil,
            staves      = (Nil : List[Staff.StaffResource]),
            consumables = (Nil : List[Consumable.ConsumableResource]),
            rings       = (Nil : List[Ring.RingResource])
        };
        let load = Encumbrance.loadOf(7, 6, inv);
        Assert.assertEq(
            expected = (true, Tier.Normal),
            (approxEq(load#total, 4.5), load#tier))

    // ──────────────────────────────────────────────
    // 拾得ゲート（詰み防止）
    // ──────────────────────────────────────────────

    /// wouldExceedImmobile: 現在 ratio 1.05（total 10.5 / cap 10）に対し、
    ///   +0.6 で (11.1/10)=1.11 → 重量過多になる(true)、+0.4 で 1.09 → ならない(false)。
    @Test
    def testWouldExceedImmobile(): Unit \ Assert =
        let load = {total = 10.5, capacity = 10.0, ratio = 1.05, tier = Tier.Overloaded};
        Assert.assertEq(
            expected = true :: false :: Nil,
            Encumbrance.wouldExceedImmobile(load, 0.6) ::
            Encumbrance.wouldExceedImmobile(load, 0.4) :: Nil)

    // ──────────────────────────────────────────────
    // 最低 1 マス保証（Overloaded で floor 0 でも動ける）
    // ──────────────────────────────────────────────

    /// 移動力 3 のユニットが Overloaded(×0.3) だと floor(0.9)=0 だが、最低 1 マス保証で 1。
    /// 重量過多(Immobile) だけは 0（移動不可）。素の移動力を超えないこともあわせて確認。
    @Test
    def testEffectiveMoveMinOneExceptImmobile(): Unit \ Assert =
        Assert.assertEq(
            expected = 1 :: 0 :: 3 :: Nil,
            Encumbrance.effectiveMoveTiles(3, loadWithTier(Tier.Overloaded)) ::  // floor(0.9)=0 → 最低1
            Encumbrance.effectiveMoveTiles(3, loadWithTier(Tier.Immobile)) ::    // 移動不可=0
            Encumbrance.effectiveMoveTiles(3, loadWithTier(Tier.Normal)) :: Nil) // 等倍=3（上限）

    // ──────────────────────────────────────────────
    // 負の重量（浮雲）— 0 下限クランプと符号付き表記
    // ──────────────────────────────────────────────

    /// weightText は負の重量も符号付きで出す（浮雲の効果量表示など）。
    @Test
    def testWeightTextSigned(): Unit \ Assert =
        Assert.assertEq(
            expected = "-4.5" :: "0.0" :: "12.5" :: Nil,
            Encumbrance.weightText(-4.5) :: Encumbrance.weightText(0.0) ::
            Encumbrance.weightText(12.5) :: Nil)

    /// 浮雲（負の重量の指輪）だけを持つと素の合計は負になるが、totalWeight は 0 下限クランプ。
    /// これにより「浮雲ガン積みで積載率が負→常時 Normal＋ゲート無効」の退化を防ぐ。
    /// 浮雲・大(-4.5) は rings.json の effectRule "weight" で表現（実カタログから引く）。
    @Test
    def testFloatCloudClampsTotalToZero(): Unit \ {Assert, Fs.FileRead} =
        let cloud = Ring.lookup("float_cloud_large", Ring.load());
        let inv = {
            weapons     = (Nil : List[WeaponCatalog.WeaponResource]),
            staves      = (Nil : List[Staff.StaffResource]),
            consumables = (Nil : List[Consumable.ConsumableResource]),
            rings       = cloud :: Nil
        };
        // 浮雲単体の重量は -4.5 だが、総重量は 0 にクランプされ、段階は Normal。
        Assert.assertEq(
            expected = (-4.5, 0.0, Tier.Normal),
            (Encumbrance.ringWeight(cloud), Encumbrance.totalWeight(inv),
             Encumbrance.loadOf(5, 0, inv)#tier))
}
