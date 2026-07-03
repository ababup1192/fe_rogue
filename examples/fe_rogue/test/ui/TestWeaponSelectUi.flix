/// WeaponSelectUi（武器選択ウィンドウ・World-entity UI 版）の純粋部分を pin する。
///
/// 検証する観点:
///   - weaponSubline / rangeText: 性能 2 行目の表記
///   - weaponBadges: 苦手な武器の行だけ「不得意」バッジが付く
///   - parseWeaponIndex: metadata "w:<idx>" の往復
///   - weaponReachesAnyEnemy: 射程外の武器は選べない（行を disabled にする根拠）
///
/// 可視同期（frameStep）と行流し込みは UiWorldState を要する結線なので、ここでは
/// テキスト/バッジ/到達判定などの純粋部分を直接観測する（旧 refreshWeaponList の項目テストの置換）。
/// 選択カーソルの disabled スキップは `TestUiWidget.selectionMoveSkipping` が別に pin する。
mod TestWeaponSelectUi {

    /// 剣だけを得意とするテスト用 UnitResource（不得意バッジ検証用）。
    /// `testResource` は全タイプ得意なので、`proficientWeaponTypes` を剣のみに絞った版を作る。
    def swordOnlyResource(): UnitCatalog.UnitResource =
        {proficientWeaponTypes = WeaponCatalog.WeaponType.Sword :: Nil
            | TestUnitFixtures.testResource(4, 10)}

    /// 射程 min-max を差し替えたテスト武器（rangeText の範囲表記検証用）。
    def weaponWithRange(min: Int32, max: Int32): UnitCatalog.WeaponResource =
        {range = {min = min, max = max} | TestUnitFixtures.testWeapon()}

    /// (x,y) に居るテスト用 Enemy.Data。`isDying=true` で hp=0（瀕死）扱い。
    /// 射程到達判定 (weaponReachesAnyEnemy) の検証用に位置と生死だけ意味を持たせる。
    def enemyAt(id: Int32, x: Int32, y: Int32, isDying: Bool): EnemyScene.Data = {
        id             = id,
        resourceId     = "test_enemy",
        gridPos        = {x = x, y = y},
        alerted        = false,
        homeModuleIdx  = 0,
        moveTiles      = 3,
        hp             = if (isDying) 0 else 10,
        isDying        = isDying,
        attackTargetId = None,
        resource       = TestUnitFixtures.testEnemyResource(3, 10),
        weapon         = None,
        acted          = false,
        prevPos        = None,
        statuses       = Nil,
        ring           = None,
        followUpUsed   = false,
        bottleUsed     = false
    }

    // ════════════════════════════════════════════════════════
    // weaponSubline / rangeText — 性能 2 行目
    // ════════════════════════════════════════════════════════

    /// サブラインは威力・耐久・重さ（命中・射程は戦闘予報ミニ窓で見せるのでサブラインに出さない）。
    @Test
    def testWeaponSublineSingleRange(): Unit \ Assert =
        // testWeapon: 攻2 耐久10 重さ1.9（命中・射程はサブラインに出さない）
        Assert.assertEq(
            expected = "威力 2 耐久 10 重さ 1.9",
            WeaponSelectUi.weaponSubline(TestUnitFixtures.testWeapon()))

    /// 範囲射程 (min != max) は「射程 min-max」。
    @Test
    def testRangeTextSpan(): Unit \ Assert =
        Assert.assertEq(
            expected = "射程 1-2",
            WeaponSelectUi.rangeText((weaponWithRange(1, 2))#range))

    /// 単射程は範囲なしの「射程 N」表記。
    @Test
    def testRangeTextSingle(): Unit \ Assert =
        Assert.assertEq(
            expected = "射程 1",
            WeaponSelectUi.rangeText((TestUnitFixtures.testWeapon())#range))

    // ════════════════════════════════════════════════════════
    // weaponBadges — 不得意な武器の行にだけバッジを入れる
    // ════════════════════════════════════════════════════════

    /// 剣だけ得意なユニットに [剣, 斧] を持たせると、斧 (index 1) の行だけ「不得意」バッジが付く。
    /// 得意な剣 (index 0) にはキー自体が入らない（バッジ非表示）。
    @Test
    def testWeaponBadgesOnlyOnNonProficient(): Unit \ Assert =
        let sword = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Sword);
        let axe   = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Axe);
        let badges = WeaponSelectUi.weaponBadges(swordOnlyResource(), sword :: axe :: Nil);
        // 斧の行 (index 1) にだけ「不得意」が入り、剣の行 (index 0) には入らない。
        Assert.assertEq(
            expected = (None, Some("不得意")),
            (Map.get(0, badges), Map.get(1, badges)))

    /// 全タイプ得意なユニット (testResource) では、どの武器にもバッジが付かない（空 Map）。
    @Test
    def testWeaponBadgesEmptyWhenAllProficient(): Unit \ Assert =
        let sword = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Sword);
        let axe   = TestUnitFixtures.testWeaponWithType(2, WeaponCatalog.WeaponType.Axe);
        let badges = WeaponSelectUi.weaponBadges(
            TestUnitFixtures.testResource(4, 10), sword :: axe :: Nil);
        Assert.assertEq(expected = 0, Map.size(badges))

    // ════════════════════════════════════════════════════════
    // parseWeaponIndex — metadata "w:<idx>" の往復
    // ════════════════════════════════════════════════════════

    @Test
    def testParseWeaponIndex(): Unit \ Assert =
        Assert.assertEq(expected = Some(3), WeaponSelectUi.parseWeaponIndex("w:3"))

    @Test
    def testParseWeaponIndexUnknown(): Unit \ Assert =
        Assert.assertEq(expected = None, WeaponSelectUi.parseWeaponIndex("s:1"))

    // ════════════════════════════════════════════════════════
    // weaponReachesAnyEnemy — 射程外の武器は選べない（行を disabled にする根拠）
    // ════════════════════════════════════════════════════════

    /// 弓(射程2)と剣(射程1)を持ち、距離2の敵を狙う想定。剣は届かず弓だけ届く。
    /// → 武器選択で剣の行は disabled、弓の行は選択可能、になる根拠を pin する。
    @Test
    def testReachOnlyInRangeWeapon(): Unit \ Assert =
        let pos = {x = 0, y = 0};
        let enemies = enemyAt(5, 2, 0, false) :: Nil;   // 距離 2
        Assert.assertEq(
            expected = (false, true),
            (WeaponSelectUi.weaponReachesAnyEnemy(pos, weaponWithRange(1, 1), enemies),
             WeaponSelectUi.weaponReachesAnyEnemy(pos, weaponWithRange(2, 2), enemies)))

    /// 瀕死(hp 0)の敵は射程内でも到達対象にしない。
    @Test
    def testReachIgnoresDyingEnemy(): Unit \ Assert =
        let pos = {x = 0, y = 0};
        let enemies = enemyAt(5, 1, 0, true) :: Nil;    // 距離 1 だが瀕死
        Assert.assertEq(
            expected = false,
            WeaponSelectUi.weaponReachesAnyEnemy(pos, weaponWithRange(1, 1), enemies))

    // ════════════════════════════════════════════════════════
    // 実 asset の行宣言数 ⇔ maxSlots() の一致（スロット超過防御の前提を pin）
    //   ui.json は row0..row{maxSlots-1} を宣言し、row{maxSlots} は宣言しない。
    // ════════════════════════════════════════════════════════

    /// 実 asset（WeaponSelect.ui.json）を parse し、menu 直下の "row" 名の子の数を数える。
    /// UiWorld は組まず Spec ツリーだけを歩く（読み込み失敗はテストを潰す）。
    def weaponSelectRowCount(): Int32 \ Fs.FileRead =
        match UiSpec.load(WeaponSelectUi.specPath()) {
            case Ok(root) => UiSpec.countPrefixedChildren("panel" :: "menu" :: Nil, "row", root)
            case Err(_)   => bug!("WeaponSelect.ui.json load failed")
        }

    /// 実 asset の row 宣言数が `WeaponSelectUi.maxSlots()` と一致する（宣言過不足を弾く）。
    @Test
    def testRowDeclarationCountMatchesMaxSlots(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(expected = WeaponSelectUi.maxSlots(), weaponSelectRowCount())

    // ════════════════════════════════════════════════════════
    // 幾何: 武器アイコンのチップが選択ハイライト箱に収まる（左はみ出しの回帰防止）
    //   実 asset を parse→spawn し、row0 を可視にして computeLayout を掛け、iconBg（チップ）と
    //   highlight（青枠）の実 rect を突き合わせる。チップは menu 原点フラッシュだと inset ぶん
    //   ハイライトの左へはみ出す（実機バグ）。weaponRow の左 pad でチップをハイライト内へ収める。
    //   UiWorld は spawnRoot（ライブラリ側）が組む（@Test 内の UiWorld リテラル構築は避ける）。
    //   チップ・ハイライトはどちらも Px 系ノードで、text 実寸に依らないので measures は空でよい。
    // ════════════════════════════════════════════════════════

    /// design 空間の rootRect（170×128）。panel は abs で内側に置かれる。
    def designRect(): Rect2.Rect2 =
        {position = {x = 0.0, y = 0.0}, size = {x = 170.0, y = 128.0}}

    /// 実 asset を spawn し、row0 を可視にして computeLayout を掛けた結果（UiWorld 同梱）。
    /// 行テンプレは visible=false 既定なので、row0 を可視化しないとチップがレイアウトされない。
    def weaponSelectLayout(): (UiStore.UiWorld, Map[EntityId, Rect2.Rect2]) \ Fs.FileRead =
        match UiSpec.load(WeaponSelectUi.specPath()) {
            case Err(_)   => bug!("WeaponSelect.ui.json load failed")
            case Ok(spec) =>
                let (rootId, ui0) = UiSpec.spawnRoot(spec, UiStore.empty());
                let ui = UiStore.setVisible("WeaponSelect/panel/menu/row0", true, ui0);
                let layout = UiLayout.computeLayout(
                    {styles = ui#styles, parents = ui#parents, order = ui#order,
                     measures = Map.empty(), visible = ui#visible},
                    rootId, designRect());
                (ui, layout)
        }

    /// 名前パスの rect を (x, y, w, h) tuple で引く。未確定は None。
    def rectAt(path: String, ui: UiStore.UiWorld, layout: Map[EntityId, Rect2.Rect2]):
            Option[(Float64, Float64, Float64, Float64)] =
        UiStore.idOf(path, ui)
            |> Option.flatMap(id -> Map.get(id, layout))
            |> Option.map(r -> (r#position#x, r#position#y, r#size#x, r#size#y))

    /// rect tuple の (x, width) だけ取り出す（横方向の突き合わせ用）。
    def xw(t: (Float64, Float64, Float64, Float64)): (Float64, Float64) =
        let (x, _y, w, _h) = t; (x, w)

    /// inner が outer に 4 辺とも収まるか（左右上下）。
    def contains(outer: (Float64, Float64, Float64, Float64), inner: (Float64, Float64, Float64, Float64)): Bool =
        let (ox, oy, ow, oh) = outer;
        let (ix, iy, iw, ih) = inner;
        ix >= ox and iy >= oy and (ix + iw) <= (ox + ow) and (iy + ih) <= (oy + oh)

    /// 横方向の実 rect を pin する。panel abs(28,40)+pad2 で menu 原点 x=30。
    /// highlight は inset 0.5 で x=30.5・幅47（内側 30.5..77.5）。weaponRow の左 pad 1.5 で
    /// チップ(iconBg 7幅)は x=31.5 から始まり、ハイライトの左内側に 1px 入る（旧: pad なしだと
    /// x=30.0 で 0.5px はみ出していた）。
    @Test
    def testChipXFitsInsideHighlight(): Unit \ {Assert, Fs.FileRead} =
        let (ui, layout) = weaponSelectLayout();
        let chip = rectAt("WeaponSelect/panel/menu/row0/iconBg", ui, layout) |> Option.map(xw);
        let hl   = rectAt("WeaponSelect/panel/menu/highlight", ui, layout) |> Option.map(xw);
        Assert.assertEq(
            expected = (Some((31.5, 7.0)), Some((30.5, 47.0))),
            (chip, hl))

    /// チップの箱がハイライトの箱に上下左右とも完全収容される（左はみ出しの回帰防止）。
    @Test
    def testChipFullyContainedInHighlight(): Unit \ {Assert, Fs.FileRead} =
        let (ui, layout) = weaponSelectLayout();
        let chip = rectAt("WeaponSelect/panel/menu/row0/iconBg", ui, layout);
        let hl   = rectAt("WeaponSelect/panel/menu/highlight", ui, layout);
        Assert.assertEq(
            expected = Some(true),
            forM (h <- hl; c <- chip) yield contains(h, c))
}
