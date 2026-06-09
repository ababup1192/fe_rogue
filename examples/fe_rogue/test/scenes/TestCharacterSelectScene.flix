/// CharacterSelectScene の純粋な選択ロジックを固定するテスト。
///
/// 観点（画面描画・effect には触れず、選択の振る舞いだけを確認する）:
///   - カードの選択 / 解除と、3 人を超えて選べない上限
///   - 「残り N 人」が選ぶごとに減ること、ちょうど 3 人で出撃できること
///   - 注目カードが両端で反対側へ巻き込むこと
///   - リーダーを先頭に並べ替えること（集合の合流先 = ロードが先頭になる、最重要の性質）
///   - 3 人揃ってからでないとリーダー選びに進めないこと
///   - 注目カードが中央に来るためのカード列の横位置
mod TestCharacterSelectScene {

    use CharacterSelectScene.SubMode

    // ════════════════════════════════════════════════════════
    // フィクスチャ
    // ════════════════════════════════════════════════════════

    /// 本番の units.json から候補プレイヤー一覧（8 人）を読む。
    /// 選択ロジックはこの並び（index）に対して動くので、本物の構築関数を起点にする。
    def testPlayers(): List[UnitCatalog.PlayerResource] \ Fs.FileRead =
        let weaponCatalog = WeaponCatalog.load();
        let catalog = UnitCatalog.load("resources/units.json", weaponCatalog);
        UnitCatalog.pool("players", catalog)

    // ════════════════════════════════════════════════════════
    // 選択 / 解除と上限
    // ════════════════════════════════════════════════════════

    /// 注目カードを Z で選ぶと選択に入り、もう一度押すと外れる。
    @Test
    def testToggleSelectAddsThenRemoves(): Unit \ {Assert, Fs.FileRead} =
        let base = {focus = 2 | CharacterSelectScene.initialState(testPlayers())};
        let added = CharacterSelectScene.toggleSelect(base);
        let removed = CharacterSelectScene.toggleSelect(added);
        // 追加後は [2]、解除後は空
        Assert.assertEq(expected = (2 :: Nil, Nil), (added#selected, removed#selected))

    /// すでに 3 人選んでいるとき、未選択カードを選ぼうとしても増えない（上限）。
    /// 一方、選択済みカードはいつでも外せる。
    @Test
    def testToggleSelectRespectsCap(): Unit \ {Assert, Fs.FileRead} =
        let full = {selected = 0 :: 1 :: 2 :: Nil | CharacterSelectScene.initialState(testPlayers())};
        // 注目が未選択(4)のとき: 上限なので [0,1,2] のまま
        let tryAddNew = CharacterSelectScene.toggleSelect({focus = 4 | full});
        // 注目が選択済み(1)のとき: 外れて [0,2]
        let removeOne = CharacterSelectScene.toggleSelect({focus = 1 | full});
        Assert.assertEq(
            expected = (0 :: 1 :: 2 :: Nil, 0 :: 2 :: Nil),
            (tryAddNew#selected, removeOne#selected))

    // ════════════════════════════════════════════════════════
    // 残り人数と出撃可否
    // ════════════════════════════════════════════════════════

    /// 0,1,2,3 人と選ぶにつれて「残り」が 3,2,1,0 と減る。
    @Test
    def testRemainingCountsDown(): Unit \ {Assert, Fs.FileRead} =
        let s0 = CharacterSelectScene.initialState(testPlayers());
        let s1 = CharacterSelectScene.toggleSelect({focus = 0 | s0});
        let s2 = CharacterSelectScene.toggleSelect({focus = 1 | s1});
        let s3 = CharacterSelectScene.toggleSelect({focus = 2 | s2});
        Assert.assertEq(
            expected = (3, 2, 1, 0),
            (CharacterSelectScene.remaining(s0), CharacterSelectScene.remaining(s1),
             CharacterSelectScene.remaining(s2), CharacterSelectScene.remaining(s3)))

    /// 出撃できるのはちょうど 3 人選んだときだけ（2 人では不可）。
    @Test
    def testCanDeployOnlyWhenThree(): Unit \ {Assert, Fs.FileRead} =
        let two = {selected = 0 :: 1 :: Nil | CharacterSelectScene.initialState(testPlayers())};
        let three = {selected = 0 :: 1 :: 2 :: Nil | CharacterSelectScene.initialState(testPlayers())};
        Assert.assertEq(
            expected = (false, true),
            (CharacterSelectScene.canDeploy(two), CharacterSelectScene.canDeploy(three)))

    // ════════════════════════════════════════════════════════
    // 注目カードの移動（両端で巻き込む）
    // ════════════════════════════════════════════════════════

    /// 先頭で左へ行くと末尾(7)へ、末尾で右へ行くと先頭(0)へ巻き込む（候補は 8 人）。
    @Test
    def testMoveFocusWrapsAtEnds(): Unit \ {Assert, Fs.FileRead} =
        let base = CharacterSelectScene.initialState(testPlayers());
        let wrappedLeft = CharacterSelectScene.moveFocus(-1, base);
        let wrappedRight = CharacterSelectScene.moveFocus(1, {focus = 7 | base});
        Assert.assertEq(expected = (7, 0), (wrappedLeft#focus, wrappedRight#focus))

    // ════════════════════════════════════════════════════════
    // リーダーを先頭に並べ替える（最重要）
    // ════════════════════════════════════════════════════════

    /// 選んだ順が [5,1,3] のとき、リーダー候補(leaderFocus)に応じて先頭が入れ替わる。
    /// リーダー以外は選んだ順を保つ。先頭が集合時の合流先（ロード）になるため重要。
    ///
    ///   selected = [5, 1, 3]
    ///   leaderFocus = 2 (= index 3) → [3, 5, 1]
    ///   leaderFocus = 0 (= index 5) → [5, 1, 3]
    @Test
    def testOrderedIndicesPutsLeaderFirst(): Unit \ {Assert, Fs.FileRead} =
        let players = testPlayers();
        let pickThird = {selected = 5 :: 1 :: 3 :: Nil, leaderFocus = 2 | CharacterSelectScene.initialState(players)};
        let pickFirst = {selected = 5 :: 1 :: 3 :: Nil, leaderFocus = 0 | CharacterSelectScene.initialState(players)};
        Assert.assertEq(
            expected = (3 :: 5 :: 1 :: Nil, 5 :: 1 :: 3 :: Nil),
            (CharacterSelectScene.orderedIndices(pickThird),
             CharacterSelectScene.orderedIndices(pickFirst)))

    // ════════════════════════════════════════════════════════
    // リーダー選びへの遷移
    // ════════════════════════════════════════════════════════

    /// 3 人揃っていればリーダー選び段階に進み、2 人ではメンバー選びのまま。
    @Test
    def testBeginLeaderPickRequiresThree(): Unit \ {Assert, Fs.FileRead} =
        let two = {selected = 0 :: 1 :: Nil | CharacterSelectScene.initialState(testPlayers())};
        let three = {selected = 0 :: 1 :: 2 :: Nil | CharacterSelectScene.initialState(testPlayers())};
        Assert.assertEq(
            expected = (SubMode.PickingMembers, SubMode.PickingLeader),
            ((CharacterSelectScene.beginLeaderPick(two))#mode,
             (CharacterSelectScene.beginLeaderPick(three))#mode))

    // ════════════════════════════════════════════════════════
    // カード列の横位置（注目カードを中央に）
    // ════════════════════════════════════════════════════════

    /// 注目が 0 番なら中央(58.0)、1 番なら 1 ピッチ(40.0)ぶん左(18.0)に寄せる。
    @Test
    def testTargetCarouselXCentersFocus(): Unit \ Assert =
        Assert.assertEq(
            expected = (58.0, 18.0),
            (CharacterSelectScene.targetCarouselX(0), CharacterSelectScene.targetCarouselX(1)))

    // ════════════════════════════════════════════════════════
    // 右パネルの得意武器テキスト
    // ════════════════════════════════════════════════════════

    /// description でユニットを引く（本番カタログ）。
    def unitNamed(name: String): UnitCatalog.PlayerResource \ Fs.FileRead =
        match List.find(u -> u#description == name, testPlayers()) {
            case Some(u) => u
            case None    => bug!("unit with description '${name}' not found")
        }

    /// ロード（全タイプ得意）は「得意武器:\n剣 斧 槍 弓 魔」。
    @Test
    def testProficiencyTextLordAllTypes(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(
            expected = "得意武器:\n剣 斧 槍 弓 魔",
            CharacterSelectScene.proficiencyText(unitNamed("ロード")))

    /// メイジ（魔法のみ）は「得意武器:\n魔」。
    @Test
    def testProficiencyTextMageMagicOnly(): Unit \ {Assert, Fs.FileRead} =
        Assert.assertEq(
            expected = "得意武器:\n魔",
            CharacterSelectScene.proficiencyText(unitNamed("メイジ")))
}
