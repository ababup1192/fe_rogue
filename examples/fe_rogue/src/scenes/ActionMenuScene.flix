/// ActionMenuScene — 行動選択ウィンドウ
///
/// PlayerMoving / PlayerCursor / GatherMove で Z を押した瞬間に `ActionSelect` フェーズに入り、
/// 画面に出る ItemList。文脈で項目が切り替わる:
///   - PlayerMoving 由来 (SelectedPlayer あり) → こうげき / アイテム / ひろう / たいき
///   - PlayerCursor 由来・空マス (SelectedPlayer なし) → 集合 (確定で行軍開始) / ターンエンド
///   - GatherMove 由来 (gatherActive=true・主人公選択中) → 交換 / 全員待機（キャンセルは X で巻き戻し）
/// ↑↓ で選択、Enter/Z で確定、X/Escape で元のフェーズ (PlayerMoving / PlayerCursor / GatherMove) に戻る。
///
/// ノード構造（visible のとき）:
///   ActionMenu (CanvasLayer, layer=2)  ← layer=2 により HUD/マップより手前に描画
///     └─ panel (Panel, NodeTag.ActionPanel)
///           └─ menu (ItemList, NodeTag.ActionMenu)
///
/// 項目の出現条件 (`refreshItems` で毎フレーム再計算):
///   - 「こうげき」: 選択中プレイヤーの装備武器の射程内に生きている敵が居る
///   - 「ひろう」  : 選択中プレイヤーのセルに床アイテムが落ちている
///   - 「たいき」  : 選択中プレイヤーのセルに別の味方が居ない
///   - 「集合」  : SelectedPlayer が None (PlayerCursor + 空マス) で主人公以外の生存味方が居るとき
/// 全条件不成立なら ItemList は空になり、Z 押下は no-op (X で戻るのみ)。
///
/// 「行動継続」と「行動終了」:
///   - 行動終了 (確定で waited 化 → 次セレクト or 敵ターン)
///       こうげき (PlayerAttack を経由してから commit) / たいき / ターンエンド / 全員待機
///   - 行動継続 (確定後 ActionSelect に戻り、ActionMenu の項目が再構築される)
///       ひろう (拾うとセルから消えるので次フレームの `refreshItems` で項目から外れる)
///       集合 (GatherMove に移って主人公が隊列を率いる。これは別フローの遷移)
///       交換 (集合の隣接メニュー: TradeInventory を抜けると隣接メニューに戻る)
mod ActionMenuScene {

    use JsonCompat.PathTag.Root

    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/ActionMenuScene.scene.json")

    def fontName(): String = "ui"

    def rootName(): String = "ActionMenu"

    pub def panelName(): String = "panel"
    pub def menuName(): String = "menu"
    pub def headerName(): String = "header"
    /// 見出し「コマンド」の背景帯（タイトルバー）。HTML プロトタイプの #11182a 帯に相当。
    pub def headerBgName(): String = "headerBg"
    /// 見出し帯の下半分を四角く塗りつぶす重ね板。Panel は 4 隅一律の角丸しか持てないので、
    /// 角丸の headerBg（上を panel に合わせて丸める）の上に、角丸なしのこの板を底面側へ重ねて
    /// 下辺の角丸を塗りつぶし「上だけ丸・底面は四角」のタイトルバーにする。
    pub def headerBgFillName(): String = "headerBgFill"

    pub def rootPath(): NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath(): NodePath = rootName() :: panelName() :: menuName() :: Nil
    pub def headerPath(): NodePath = rootName() :: panelName() :: headerName() :: Nil
    pub def headerBgPath(): NodePath = rootName() :: panelName() :: headerBgName() :: Nil
    pub def headerBgFillPath(): NodePath = rootName() :: panelName() :: headerBgFillName() :: Nil

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Util.Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ActionPanel")   => Ok(NodeTag.ActionPanel)
            case Some("ActionMenu")    => Ok(NodeTag.ActionMenu)
            case Some(unknown)         =>
                Err(JsonCompat.jsonError(Root, Set#{"ActionMenuScene tag (got: ${unknown})"}))
        }

    /// metadata の値。`onItemConfirmed` で再現するためのアクション識別子。
    def attackMeta(): String    = "attack"
    def exchangeMeta(): String  = "exchange"
    def itemMeta(): String      = "item"
    def waitMeta(): String      = "wait"
    def pickupMeta(): String    = "pickup"
    def openMeta(): String      = "open"
    def gatherMeta(): String    = "gather"
    def turnEndMeta(): String   = "turnEnd"
    /// 中断セーブ（ターンエンドの直下に置く。現フロアを保存してタイトルへ戻る）。
    def suspendMeta(): String   = "suspend"
    def stairsMeta(): String    = "stairs"
    /// 集合（行軍）の隣接メニューの「交換」（主人公＋隣接味方の N 人持ち物交換）。
    /// 通常ターン隣接 2 人交換の `exchangeMeta` とは別物。
    def gatherTradeMeta(): String = "gatherTrade"
    /// 集合（行軍）の隣接メニューの「階段で離脱」（届く味方が順々に階段へ向かい退場）。
    def gatherStairsMeta(): String = "gatherStairs"
    /// 集合（行軍）隣接メニューの「全員待機」。挙動は turnEnd と同一（applyTurnEnd）だが、
    /// turnEndMeta と別識別子にして subtextFor が専用文言「全員を待機」を返せるようにする。
    def waitAllMeta(): String = "waitAll"

    /// scene に ActionMenu ノードツリーを追加する。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// フェーズ遷移時の visibility 適用。
    ///   - Panel : ActionSelect / WeaponSelect フェーズで visible
    ///   - Menu  : ActionSelect / WeaponSelect で visible。focus は ActionSelect のときだけ
    ///             （WeaponSelect 中は focus を武器ウィンドウに譲り、ここは「攻撃」行のハイライトを
    ///              `setHighlightWhenUnfocused(true)` で残す＝カーソル glyph は隠したまま選択枠だけ描く）。
    /// WeaponSelect でも ActionMenu を visible に残すのは、武器選択ウィンドウが右隣に重ねて出る間も
    /// コマンドメニューを表示し続け「攻撃」を選んでいる文脈を見せ続けるため（モックアップ準拠）。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        // WeaponSelect と同様、アイテム窓を開いている間（ItemSelect / ItemActionSelect）も
        // コマンドメニューは表示したまま「アイテム」行のハイライトを残す（focus だけ譲る）。
        // 交換（相手選択 / 持物交換）中もコマンドメニューを表示したまま「交換」行のハイライトを
        // 残す（focus は相手選択カーソル／交換ウィンドウに譲る）。武器・アイテム窓と同じ作法。
        let visible = phase == TurnPhase.Phase.ActionSelect
                    or phase == TurnPhase.Phase.WeaponSelect
                    or phase == TurnPhase.Phase.ItemSelect
                    or phase == TurnPhase.Phase.ItemActionSelect
                    or phase == TurnPhase.Phase.TradeTargetSelect
                    or phase == TurnPhase.Phase.TradeInventory;
        let focused = phase == TurnPhase.Phase.ActionSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> Panel.mapAt(headerBgPath(), CanvasItem.setVisible(visible))
            |> Panel.mapAt(headerBgFillPath(), CanvasItem.setVisible(visible))
            |> Label2D.mapAt(headerPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                list
                    |> CanvasItem.setVisible(visible)
                    |> ItemList.setFocused(focused)
                    |> ItemList.setHighlightWhenUnfocused(not focused))

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から ActionMenu の ItemList
    /// ノードに対して dispatch される (per-node、ItemList は 1 個のみなので 1 フレーム 1 回)。
    /// visibility 更新と items 再計算を同一フレームで行うのは、分離すると phase 変化フレームで
    /// 「表示は ActionSelect だが items はまだ前フェーズの状態」というズレが生じるため。
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State,
                           PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        // ActionMenu は ActionSelect と WeaponSelect の両方で表示し続ける（WeaponSelect 中も
        // コマンドメニューを右隣の武器ウィンドウと一緒に見せ「攻撃」行をハイライト維持する）。
        // どちらでも項目は同じ（SelectedPlayer は不変）なので毎フレーム再構築するが、
        // WeaponSelect 中はカーソル位置（＝直前に確定した「攻撃」行）を動かさない。
        let menuVisible = phase == TurnPhase.Phase.ActionSelect
                        or phase == TurnPhase.Phase.WeaponSelect
                        or phase == TurnPhase.Phase.ItemSelect
                        or phase == TurnPhase.Phase.ItemActionSelect
                        or phase == TurnPhase.Phase.TradeTargetSelect
                        or phase == TurnPhase.Phase.TradeInventory;
        // UX: メニューを開き直すたびに意図しない項目を誤確定しないよう、
        // 非表示中はカーソルを先頭(0)に戻しておく。表示中はリセットしないので
        // ↑↓ のカーソル移動は維持される。
        let withItems = if (not menuVisible)
                withVisibility
                    |> ItemList.mapAt(menuPath(), ItemList.setSelectedIndex(0))
            else {
                let items = buildItems(withVisibility);
                let firstEnabled = firstEnabledIndex(items);
                // 文脈ごとに最長行へ幅を合わせる（中央に無駄な余白を出さない）。
                let cw = ItemList.getAt(menuPath(), withVisibility)
                    |> Option.map(l -> contentWidth(l, items))
                    |> Option.getWithDefault(0.0);
                // ActionSelect では disabled 項目に乗っていたら選択可能項目へ寄せるが、
                // WeaponSelect 中はカーソルを動かさない（「攻撃」行のハイライトを固定するため）。
                let snapCursor = phase == TurnPhase.Phase.ActionSelect;
                withVisibility
                    |> ItemList.mapAt(menuPath(), l -> {
                        let withItems = l
                            |> ItemList.setItems(items);
                        if (snapCursor and selectedIsDisabled(items, withItems))
                            ItemList.setSelectedIndex(firstEnabled, withItems)
                        else withItems
                    })
                    |> fitMenuToItems(List.length(items), cw)
            };
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// ItemList 1 項目の高さ (px)。scene.json の menu `itemHeight` と一致させること。
    /// 行内でテキストは縦中央に置かれるので、fontSize より大きめにして上下 padding を作る。
    def menuItemHeight(): Float64 = 8.0
    /// panel 下端の余白 (px)。最終項目（待機）の下に空ける隙間。
    def menuPadding(): Float64 = 4.0
    /// panel 上端から menu 上端までの距離 (px)。見出し帯（headerBg, 上余白 1 + 高さ 6）+ 2px の隙間。
    /// **scene.json の menu `pos` の y はこの値と一致させること**
    /// （testMenuOriginMatchesHeaderPadding がロード後の menu pos.y と
    ///  この値の一致を test で pin するので、片方だけ変えると赤になる）。
    def menuHeaderPadding(): Float64 = 9.0

    /// 見出し帯（headerBg）を panel 枠の内側に詰めるための左右インセット (px)。
    /// panel の borderWidth (scene.json で 1) と一致させ、帯の角丸が枠と同心に収まるようにする。
    /// scene.json の headerBg `pos.x` もこの値と一致させること。
    def headerBgInset(): Float64 = 1.0

    /// items の最初の「選択可能（not disabled）」項目の index。全部 disabled なら 0。
    def firstEnabledIndex(items: List[ItemEntry]): Int32 =
        items
            |> List.zipWithIndex
            |> List.findLeft(pair -> not snd(pair)#disabled)
            |> Option.map(fst)
            |> Option.getWithDefault(0)

    /// 現在の選択 index が disabled 項目を指しているか。
    def selectedIsDisabled(items: List[ItemEntry], list: ItemList): Bool =
        List.nth(ItemList.getSelectedIndex(list), items)
            |> Option.map(e -> e#disabled)
            |> Option.getWithDefault(false)

    /// menu 左右の内側余白 (px)。menu は panel 内 pos.x=2 なので左右とも 2。
    def menuSideMargin(): Float64 = 2.0

    /// items の各行に必要な幅（左パディング + ラベル幅 + ラベル/サブラベル間隔 + サブラベル幅 + 右余白）
    /// の最大値。文脈ごとに最長行へ幅を合わせ、中央に無駄な余白が出ないようにする。
    /// 中央寄せ項目の左右余白 (px)。最長ラベルの左右にこのぶん空ける。
    /// 文字の左右が空きすぎないよう詰める（窓も内容幅に合わせて狭まり、武器ウィンドウは
    /// `WeaponSelectScene.positionBesideActionMenu` が右端基準で追従＝左に寄る）。
    def menuLabelSidePad(): Float64 = 4.0

    def contentWidth(list: ItemList, items: List[ItemEntry]): Float64 =
        let font = ItemList.getFont(list);
        let fs   = ItemList.getFontSize(list);
        let maxLabelW = items
            |> List.map(e -> Label2D.measure(Label2D.make(e#text, font, fs))#x)
            |> List.foldLeft(Float64.max, 0.0);
        maxLabelW + 2.0 * menuLabelSidePad()

    /// メニュー項目数 `count` と内容幅 `contentW` に合わせて ItemList / Panel / headerBg を詰める。
    /// 高さは行数ぶん、幅は内容（と見出し）に合わせて自動フィットする（中央の無駄余白を出さない）。
    /// 項目 0 でも最低 1 行ぶんの高さは残す (空ウィンドウが潰れて見えないように)。
    def fitMenuToItems(count: Int32, contentW: Float64, scene: Scene[NodeTag]): Scene[NodeTag] =
        let rows   = Int32.max(1, count);
        let menuH  = Int32.toFloat64(rows) * menuItemHeight();
        let panelH = menuHeaderPadding() + menuH + menuPadding();
        // 見出し「コマンド」の幅も考慮（header は menu より x=+2 なので +2 した幅を要求）。
        let headerW = Label2D.getAt(headerPath(), scene)
            |> Option.map(h -> Label2D.measure(h)#x + 2.0)
            |> Option.getWithDefault(0.0);
        let innerW = Float64.max(contentW, headerW);
        let panelW = innerW + 2.0 * menuSideMargin();
        scene
            |> ItemList.mapAt(menuPath(), l -> ItemList.setSize({x = innerW, y = menuH}, l))
            |> Panel.mapAt(panelPath(), p -> Panel.setSize({x = panelW, y = panelH}, p))
            // 見出し帯は内容幅ではなく panel 全幅に広げた「塗りつぶしのタイトルバー」。
            // panel の枠(1px)ぶん左右を内側に詰め、scene.json の pos.x=1 と合わせて
            // 角丸(半径2)が panel の角丸枠(半径3)と同心に収まるようにする。
            // 底面側の角丸を消す重ね板（headerBgFill）も同じ幅にそろえる。
            |> Panel.mapAt(headerBgPath(), p ->
                Panel.setSize({x = panelW - 2.0 * headerBgInset(), y = Panel.getSize(p)#y}, p))
            |> Panel.mapAt(headerBgFillPath(), p ->
                Panel.setSize({x = panelW - 2.0 * headerBgInset(), y = Panel.getSize(p)#y}, p))
            // 見出し「コマンド」を headerBg の横中央に置く（幅は項目数で毎フレーム可変なので追従が要る）。
            // ラベルは scene.json で horizontalAlignment=center なので、x に headerBg の中心を渡す。
            |> Label2D.mapAt(headerPath(), l ->
                Node2D.setPosition({x = menuSideMargin() + innerW / 2.0,
                                    y = Node2D.getPosition(l)#y}, l))

    /// 選択中プレイヤーの状況から「こうげき / こうかん / アイテム / ひろう / たいき」の
    /// うち成立するものだけ返す。
    /// 順序は固定: ひろう → 階段 → こうげき → アイテム → こうかん → たいき。
    /// gatherActive=true のときは集合（行軍）の隣接メニュー（交換 / 全員待機 / キャンセル）、
    /// SelectedPlayer が None のときは空マスメニュー（集合 / ターンエンド）を返す。
    def buildItems(scene: Scene[NodeTag]): List[ItemEntry]
            \ {SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        let sel = SelectedPlayer.State.get();
        // 文脈をタプルで 1 段に分岐する:
        //   (gatherActive=true, _)      → 集合（行軍）の隣接メニュー（交換 / 全員待機 / キャンセル）
        //   (false, None=空マス)        → 空マスメニュー（集合(条件付き) / ターンエンド）
        //   (false, Some(id)=味方選択中) → その味方の行動メニュー
        match (sel#gatherActive, sel#id) {
            case (true, _)         => gatherAdjacentMenuItems(scene)
            case (false, None)     => gatherMenuItems(scene)
            case (false, Some(id)) =>
                PlayerData.PartyQuery.get(id)
                    |> Option.map(player -> selectedPlayerMenuItems(player, scene))
                    |> Option.getWithDefault(Nil)
        }

    /// 移動を終えた味方の行動メニュー項目（こうげき/アイテム/ひろう/階段/あける/こうかん/たいき）。
    /// 成立するものだけ、固定順「ひろう → 階段 → あける → こうげき → アイテム → こうかん → たいき」で返す。
    /// かなしばり（完全停止）中は行動不能なので「待機」だけ出してターンを閉じられるようにする。
    def selectedPlayerMenuItems(player: PlayerScene.Data, _scene: Scene[NodeTag]): List[ItemEntry]
            \ {PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery} =
        if (StatusSystem.isImmobilized(player#statuses)) boundMenuItems()
        else {
            // 「攻撃」は常に表示し、射程内に敵が居るときだけ選択可能（HTML プロトタイプと同じ）。
            // 敵が居なければ disabled=true で淡色表示・カーソルスキップ・確定無効になる。
            let attackItem =
                ({text = "攻撃", disabled = not canAttackFrom(player),
                  metadata = Some(attackMeta())}: ItemEntry) :: Nil;
            // 「交換」も常に表示し、隣接する味方が居るときだけ選択可能。
            // 敵にだけ隣接していて味方が居ない場合は disabled=true（HTML プロトタイプと同じ）。
            let exchangeItem =
                ({text = "交換", disabled = List.isEmpty(PlayerScene.adjacentAllies(player)),
                  metadata = Some(exchangeMeta())}: ItemEntry) :: Nil;
            let itemItem =
                if (not (List.isEmpty(player#weapons) and List.isEmpty(player#staves)))
                    ({text = "アイテム", disabled = false, metadata = Some(itemMeta())}: ItemEntry) :: Nil
                else Nil;
            let pickupItem =
                if (Option.nonEmpty(World.groundItemAtOf(player#gridPos, World.WorldQuery.get())))   // P3-c: World 権威
                    ({text = "拾う", disabled = false, metadata = Some(pickupMeta())}: ItemEntry) :: Nil
                else Nil;
            let stairsItem =
                if (World.stairsPosOf(World.WorldQuery.get())
                        |> Option.exists(c -> c#x == player#gridPos#x and c#y == player#gridPos#y))   // P3-a: World 権威
                    ({text = "階段", disabled = false, metadata = Some(stairsMeta())}: ItemEntry) :: Nil
                else Nil;
            // 宝箱に乗っていれば「あける」を出す。開錠可否(ローグか)は確定時に判定し、
            // 非ローグは「開けることができない」と表示する（=選択は可能・無効化しない）。
            let openItem =
                if (Option.nonEmpty(World.chestAtOf(player#gridPos, World.WorldQuery.get())))   // P3-b: World 権威
                    ({text = "あける", disabled = false, metadata = Some(openMeta())}: ItemEntry) :: Nil
                else Nil;
            let waitItem =
                if (canWaitOn(player))
                    ({text = "待機", disabled = false, metadata = Some(waitMeta())}: ItemEntry) :: Nil
                else Nil;
            List.flatten(pickupItem :: openItem :: stairsItem :: attackItem ::
                           itemItem :: exchangeItem :: waitItem :: Nil)
        }

    /// かなしばり中のメニュー: 行動不能なので「待機」だけ出す（ターンを閉じるため）。
    def boundMenuItems(): List[ItemEntry] =
        ({text = "待機", disabled = false, metadata = Some(waitMeta())}: ItemEntry) :: Nil

    /// 集合（行軍）の交換に参加するメンバーの player id。
    /// 主人公(id 0) を含む「隣接（マンハッタン 1）で連結した生存味方の塊」全員を id 昇順で返す。
    /// 直接隣接だけでなくチェーン（主人公-A-B で B が A 経由でつながる）も同じ塊として拾うので、
    /// 主人公に隣接していない味方でも仲間同士が隣接していれば 3 人で交換できる。
    /// 主人公が誰とも隣接していなければ主人公だけ（< 2 人なので交換は開かれない）。
    def gatherTradeMembers(): List[Int32] \ PlayerData.PartyQuery =
        let living = PlayerData.PartyQuery.getAll() |> List.filter(d -> d#hp > 0);
        PlayerScene.tradeComponent(PlayerScene.lordId(), living)

    /// 集合（行軍）の隣接メニュー項目。固定順「拾う → 階段 → 交換 → 全員待機 → キャンセル」で、
    /// 成立するものだけ返す（全員待機・キャンセルは常に表示）。判定はすべて主人公(リーダー id=0)基準。
    ///   - 拾う   : 主人公の足元に床アイテムがあれば最上段（既存 `pickupMeta` → applyPickup を流用。
    ///              集合中は SelectedPlayer.id=Some(0) なので拾う主体＝主人公として解決される）
    ///   - 階段   : 主人公が階段マスに立っているときだけ（`gatherStairsMeta` → StairsExitScene.begin）
    ///   - 交換   : 主人公＋隣接味方の N 人持ち物交換（`gatherTradeMeta` → openGatherTrade）
    ///   - 全員待機: パーティ全員を行動済みにして敵ターンへ（既存 `turnEndMeta` → applyTurnEnd を流用）
    /// （「キャンセル」項目は廃止。GatherMove 中に X を押せば開始位置へ巻き戻る）
    def gatherAdjacentMenuItems(_scene: Scene[NodeTag]): List[ItemEntry] \ {PlayerData.PartyQuery, World.WorldQuery} =
        // 主人公を 1 度だけ引いて、足元（拾う・階段）と隣接（交換）の文脈項目を組む。
        let lordItems = match PlayerData.PartyQuery.get(PlayerScene.lordId()) {
            case None       => Nil
            case Some(lord) =>
                let adj = PlayerScene.adjacentAllies(lord) |> List.filter(d -> d#hp > 0);
                // 拾う: 主人公の足元に床アイテムがあれば（applyPickup が主人公＝id 0 の足元を解決）。
                let pickup =
                    if (Option.nonEmpty(World.groundItemAtOf(lord#gridPos, World.WorldQuery.get())))   // P3-c: World 権威
                        ({text = "拾う", disabled = false,
                          metadata = Some(pickupMeta())}: ItemEntry) :: Nil
                    else Nil;
                // 階段: 主人公が階段マスに立っているときだけ。
                let stairsExit =
                    if (World.stairsPosOf(World.WorldQuery.get())
                            |> Option.exists(c -> c#x == lord#gridPos#x and c#y == lord#gridPos#y))   // P3-a: World 権威
                        ({text = "階段", disabled = false,
                          metadata = Some(gatherStairsMeta())}: ItemEntry) :: Nil
                    else Nil;
                let trade =
                    if (not List.isEmpty(adj))
                        ({text = "交換", disabled = false,
                          metadata = Some(gatherTradeMeta())}: ItemEntry) :: Nil
                    else Nil;
                List.flatten(pickup :: stairsExit :: trade :: Nil)
        };
        let waitAll =
            ({text = "全員待機", disabled = false,
              metadata = Some(waitAllMeta())}: ItemEntry) :: Nil;
        // 「キャンセル」項目は廃止。GatherMove 中に X を押せば開始位置へ巻き戻る（同じ挙動）。
        List.flatten(lordItems :: waitAll :: Nil)

    /// 「集合」が選べる状況か（主人公以外に生存味方が居る）。空マスメニューの項目可否と
    /// C キー / ゲームパッド Y のショートカット可否で共有する。
    pub def gatherAvailable(): Bool \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.getAll()
            |> List.exists(d -> d#id != PlayerScene.lordId() and d#hp > 0)

    /// 主人公（リーダー）が行動済み(waited)か。
    def lordWaited(): Bool \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(PlayerScene.lordId())
            |> Option.map(d -> d#waited)
            |> Option.getWithDefault(false)

    /// 「集合（行軍）」を開始できるか。生存味方が他に居て、かつ主人公が未行動のとき。
    /// 空マスメニューの「集合」の disabled 判定と C キーショートカット可否で共有する。
    pub def gatherEnabled(): Bool \ PlayerData.PartyQuery =
        gatherAvailable() and not lordWaited()

    /// 通常の空マスメニュー項目。生存している味方が主人公以外に居れば「集合」、常に「ターンエンド」。
    /// 集合は主人公が隊列を率いて動くモードなので、敵検知・合流距離の事前条件は持たない。
    def gatherMenuItems(_scene: Scene[NodeTag]): List[ItemEntry] \ PlayerData.PartyQuery =
        // 「集合」は常に表示し、開始できないとき（味方が他に居ない／主人公が行動済み）は
        // disabled=true で淡色表示・選択スキップ・確定無効にする。
        let gather =
            ({text = "集合", disabled = not gatherEnabled(),
              metadata = Some(gatherMeta())}: ItemEntry) :: Nil;
        let turnEnd =
            ({text = "ターンエンド", disabled = false,
              metadata = Some(turnEndMeta())}: ItemEntry) :: Nil;
        // ターンエンドの直下に「中断」を置く（現フロアを保存してタイトルへ戻る）。
        let suspend =
            ({text = "中断", disabled = false,
              metadata = Some(suspendMeta())}: ItemEntry) :: Nil;
        List.flatten(gather :: turnEnd :: suspend :: Nil)

    /// C キー / ゲームパッド Y のショートカット: メニューを開かず「集合」を直接確定する
    /// （`applyGather` と同じ＝リーダー行動済みガード＆ログ込み）。呼び出し側で PlayerCursor かつ
    /// `gatherAvailable()` のときだけ呼ぶこと（空マスメニューの「集合」確定と同じ帰結）。
    pub def gatherShortcut(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.WorldQuery} =
        applyGather(scene)

    /// Shift 長押しゲージ満了時のショートカット: メニューを開かず「全員待機」と同じ
    /// （`applyTurnEnd` と同一＝全アクティブ味方を待機にして敵ターンへ）。
    /// 呼び出し側（TurnEndHoldScene）で PlayerCursor / GatherMove のときだけ発火する。
    pub def turnEndShortcut(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                              World.Command, World.WorldQuery} =
        applyTurnEnd(scene)

    /// インベントリのいずれかの武器の射程内に生きている敵が居るか。
    /// 装備中(先頭)だけでなく全武器を見る: 射程を変えれば(= 別の武器に持ち替えれば)
    /// 攻撃できる場合も「攻撃」を出すため。武器なし / 全員 isDying / どの武器も射程外なら false。
    /// 持ち替え後の実際の装備は WeaponSelect の確定時に行う。
    def canAttackFrom(player: PlayerScene.Data): Bool \ EnemyData.RosterQuery =
        let enemies = EnemyData.RosterQuery.getAll();
        List.exists(w -> weaponReachesAnyEnemy(player#gridPos, w, enemies), player#weapons)

    /// 指定位置から `weapon` の射程内に生きている敵 (hp > 0 かつ not isDying) が居るか。
    def weaponReachesAnyEnemy(pos: {x = Int32, y = Int32},
                               weapon: UnitCatalog.WeaponResource,
                               enemies: List[EnemyScene.Data]): Bool =
        List.exists(e -> {
            let ev = EnemyScene.unitView(e);
            ev#hp > 0 and not ev#isDying
                and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
        }, enemies)

    /// 自分の現在セルに「自分以外の味方」が居なければたいき可。
    /// 同じセルに別味方が居る (重なり) ときは false。
    def canWaitOn(player: PlayerScene.Data): Bool \ PlayerData.PartyQuery =
        not List.exists(d ->
            d#id != player#id
            and d#gridPos#x == player#gridPos#x
            and d#gridPos#y == player#gridPos#y,
            PlayerData.PartyQuery.getAll())

    /// F1（OOP→ECS 移行・入力→intent seam）: メニュー確定アクションを **「決定(data)」と「適用(effect)」に分離**する。
    /// `ActionIntent` は「何をするか」を表す**純粋なデータ**で、入力分岐は scene を直接 mutate せず intent を返すだけ。
    /// 適用は単一 dispatcher `applyActionIntent` に集約する。これが OOP（分岐が直接ロジック呼び）からの脱却の seam。
    /// 現状は "wait" のみ変換（最小スライス）。他アクションは以後の F で順次 intent 化し、適用先は World System へ寄せていく。
    pub enum ActionIntent {
        case Wait   // その場で waited 確定（ターン進行）
    }

    /// 決定: metadata から `ActionIntent` を引く**純粋関数**（副作用なし＝入力は「データを選ぶ」だけ）。
    /// まだ intent 化していないアクションは None（呼び出し側の既存 if-else にフォールバック）。
    def actionIntentOf(metadata: String): Option[ActionIntent] =
        if (metadata == waitMeta()) Some(ActionIntent.Wait) else None

    /// 適用: `ActionIntent` を scene へ適用する**単一 dispatcher**（intent が effect になる唯一の点）。
    /// 将来はここから World System へ寄せる。現状 Wait は既存 `TurnFlow.commitWaitedAndAdvance` をそのまま呼ぶ（挙動不変）。
    def applyActionIntent(intent: ActionIntent, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, GameLogger.GameLogger,
               EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
               World.Command, World.WorldQuery} =
        match intent {
            case ActionIntent.Wait => TurnFlow.commitWaitedAndAdvance(scene)
        }

    /// ItemList 項目が確定された (Enter) 瞬間に呼ばれる。metadata から
    /// 「attack」/「wait」/「pickup」/「gather」を分岐して、それぞれの帰結を直接適用する。
    ///   - attack: 武器選択ウィンドウへ (`enterWeaponSelect` に委譲)
    ///   - wait:   その場で waited 確定
    ///   - pickup: 床アイテムを拾って waited 確定 (拾うで 1 ターン使う)
    ///   - gather: 集合。GatherMove へ移って主人公が隊列を率いて動き始める (`applyGather`)
    ///   - gatherTrade / gatherCancel: 集合の隣接メニュー（交換 / キャンセル）
    /// 「次セレクトか敵ターンか」の判定は Scene 跨ぎなので `TurnFlow.commitWaitedAndAdvance`
    /// を呼ぶ (Scene → GameManager 方向は許容)。
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                GatherResume.State, PlayerData.PartyQuery,
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio, World.Command, World.WorldQuery, BoardQuery,
                ItemPickupPopupScene.State} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                // F1: intent 化済みのアクション（現状 "wait"）は decide→apply の seam を通す。
                // 未変換アクションは None で下の既存 if-else にフォールバック（strangler-fig）。
                match actionIntentOf(m) {
                    case Some(intent) => applyActionIntent(intent, scene)
                    case None         =>
                if (m == attackMeta())        enterWeaponSelect(scene)
                else if (m == exchangeMeta()) PhaseTransitions.enterTradeTargetSelect(scene)
                else if (m == itemMeta())     openItemMenu(scene)
                else if (m == pickupMeta())   applyPickup(scene)
                else if (m == openMeta())     applyOpenChest(scene)
                else if (m == gatherMeta())   applyGather(scene)
                else if (m == turnEndMeta())  applyTurnEnd(scene)
                else if (m == waitAllMeta())  applyTurnEnd(scene)   // 確定挙動は turnEnd と共有。subtext を分けるため識別子だけ別
                else if (m == suspendMeta())  SuspendConfirmScene.show(scene)
                else if (m == stairsMeta())   applyStairs(scene)
                else if (m == gatherTradeMeta()) openGatherTrade(scene)
                else if (m == gatherStairsMeta()) StairsExitScene.begin(scene)
                else                          scene
                }
        }

    /// 「かいだん」確定。選択中の味方を階段で退場させる。生存味方が全員退場したら
    /// `FloorAdvanceRequest` で次フロアへ、まだ動ける味方が残っていれば `commitWaitedAndAdvance`。
    /// 「階段」項目は選択中の味方メニューからのみ出るので選択なし(None)は来ない想定だが、
    /// 防御的に「パーティごと次フロアへ」を残す。
    def applyStairs(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio,
                World.Command, World.WorldQuery} =
        // 階段を決定した瞬間にフロア移動音を鳴らす
        AudioStreamPlayer.play("change_floor");
        GameLogger.playerLog("階段を降りた");
        match SelectedPlayer.State.get()#id {
            case Some(id) =>
                let exited = PlayerScene.useStairs(id, scene);
                if (PlayerScene.allLivingUsedStairs(exited))
                    CustomEffects.FloorAdvanceRequest.advance(exited)
                else
                    TurnFlow.commitWaitedAndAdvance(exited)
            case None =>
                // 防御的: 選択なしで階段確定が来たらパーティごと次フロアへ。
                CustomEffects.FloorAdvanceRequest.advance(scene)
        }

    /// 「アイテム」確定で ItemMenuScene を開く。選択中味方の id が必要。
    def openItemMenu(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, SelectedPlayer.State, PlayerData.PartyQuery} =
        match SelectedPlayer.State.get()#id {
            case None           => scene
            case Some(playerId) => ItemMenuScene.openFor(playerId, scene)
        }

    /// 「交換」確定 (集合の隣接メニュー): 主人公＋隣接味方の N 人持ち物交換画面を開く。
    /// TradeInventory フェーズ (origin = FromGather) に入り、TradeMenuScene が最大 4 ペイン表示する。
    def openGatherTrade(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {TurnPhase.State, PlayerData.PartyQuery} =
        PhaseTransitions.enterGatherTrade(gatherTradeMembers(), scene)

    /// 「集合」確定: 集合（行軍）モードを開始する (GatherMove フェーズへ)。
    /// 主人公を選択駒に固定し、主人公＋生存味方の開始位置を巻き戻しドラフトに積む。
    /// 以降は主人公を WASD で動かし、味方が 1 歩ずつ追従する（`PlayerScene.beginGather`）。
    /// リーダー（主人公）が既に行動済み(waited)なら開始せず、ログだけ出してメニューに留まる。
    def applyGather(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.WorldQuery} =
        if (leaderWaited())
            { GameLogger.playerLog("リーダーは既に行動済みです。"); scene }
        else {
            GameLogger.playerLog("集合");
            PlayerScene.beginGather(scene)
        }

    /// 主人公(リーダー)が既に行動済み(waited)か。集合確定のガードに使う。
    def leaderWaited(): Bool \ PlayerData.PartyQuery =
        PlayerData.PartyQuery.get(PlayerScene.lordId())
            |> Option.map(d -> d#waited)
            |> Option.getWithDefault(false)

    /// 「ターンエンド」／集合の「全員待機」確定。実体は `TurnFlow.commitAllWaitedAndAdvance`
    /// （ターン確定の単一所有者）に委譲する。`EnemyTurnDriverScene` の強制全員待機と共通の入口。
    def applyTurnEnd(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger, EnemyTurn.Queue,
                              TurnPhase.State, SelectedPlayer.State, GatherResume.State,
                              World.Command, World.WorldQuery} =
        // 自発確定（メニュー「全員待機/ターンエンド」・shift スキップ・階段離脱の残存待機）は allowResume=true。
        // 集合中(gatherActive=true)のときだけ実際に resume が立つ（commitAllWaitedAndAdvance 側で AND）。
        TurnFlow.commitAllWaitedAndAdvance(true, scene)

    /// 「ひろう」確定の本体。床アイテムを取得してインベントリに加え、
    /// ログを出して ActionSelect フェーズに留まる。
    /// 拾うはアクションポイントを使わない設計（FE 原作準拠）のためターン消費しない。
    /// 次フレームの `refreshItems` が「床に何もなくなった」状態を見て自動的に
    /// 「ひろう」をメニューから外す。
    /// 武器なら weapons の末尾に、杖なら staves の末尾に追加する。
    /// 何らかの理由で item が無い場合は no-op（防御的）。
    def applyPickup(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.Command, World.WorldQuery,
                              ItemPickupPopupScene.State} =
        match pickupTarget(scene) {
            case None       => scene
            case Some(info) =>
                // 拾うと重量過多（積載 110%+ ＝ 移動不可）になるなら、床アイテムを取らずに
                // ポップアップだけ出す（ドラフト記録も床撤去もしないので、アイテムは床に残る）。
                // 重さで詰むのを防ぐため、拾う前に「拾ったら動けなくなるか」を判定する。
                if (wouldPickupOverload(info, scene))
                    ItemPickupPopupScene.showFull(scene)
                else
                    // 取得・ドラフト記録・ログは PlayerScene.pickupFloorItem に集約
                    // （移動着地の自動取得と共有する）。cancelSelection で床へ巻き戻せる。
                    // 取得音(get_item)を予約（process が次フレームに鳴らす）。
                    PlayerScene.pickupFloorItem(info#playerId, info#gridPos, scene)
                        |> ItemPickupPopupScene.reserveGetItemSound
        }

    /// 拾う主体が足元の床アイテムを拾うと重量過多になるか。PartyQuery で現フレームの Data を、
    /// `ItemScene.dataAt` で床アイテムを読む。どちらか欠ければ「過多ではない」扱い（防御的）。
    def wouldPickupOverload(info: {playerId = Int32, gridPos = {x = Int32, y = Int32}},
                             _scene: Scene[NodeTag]): Bool \ {PlayerData.PartyQuery, World.WorldQuery} =
        // P3-c: 床アイテムは World store から読む（`groundItemAtOf`）。
        match (PlayerData.PartyQuery.get(info#playerId),
               World.groundItemAtOf(info#gridPos, World.WorldQuery.get())) {
            case (Some(player), Some(floor)) =>
                PlayerScene.wouldOverloadByPicking(player, floor#item)
            case _ => false
        }

    /// 「あける」確定。宝箱に乗った駒で開錠を試みる。`applyPickup` と同じ取得経路を再用するが、
    /// 先に **ローグ判定(`canOpenChests`)** を挟む点が違う:
    ///   - ローグでない → 「開けることができない」を表示して何もしない（宝箱は残る）。
    ///   - 持ち物が満杯 → showFull を出して何もしない（宝箱は残る）。
    ///   - それ以外 → 配置時に確定済みの中身(`content`)を `addPickedItem` で在庫へ入れ、宝箱ノードを消す。
    /// 中身は配置時に抽選済みなので開錠側は Math.Random も catalogs も要さない（決定論的）。
    def applyOpenChest(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameLogger.GameLogger,
                              SelectedPlayer.State, PlayerData.PartyQuery, World.Command, World.WorldQuery,
                              ItemPickupPopupScene.State} =
        match openTarget(scene) {
            case None                      => scene
            case Some((info, player, chest)) =>
                if (not PlayerScene.canOpenChests(player))
                    ItemPickupPopupScene.showMessage("開けることができない", scene)
                else if (PlayerScene.wouldOverloadByPicking(player, chest#content))
                    ItemPickupPopupScene.showFull(scene)
                else
                    PlayerScene.addPickedItem(info#playerId, chest#content, scene)
                        |> ChestScene.takeAt(info#gridPos)
                        |> ItemPickupPopupScene.reserveGetItemSound
        }

    /// 開錠対象を 1 本の Option 連鎖で解決する: 取得主体(`pickupTarget`) → その Data → 足元の宝箱。
    /// どれかが欠けたら None（宝箱が無い / 駒が見つからない場合は何もしない）。
    def openTarget(scene: Scene[NodeTag]):
            Option[({playerId = Int32, gridPos = {x = Int32, y = Int32}},
                    PlayerScene.Data, ChestScene.Data)]
            \ {SelectedPlayer.State, PlayerData.PartyQuery, World.WorldQuery} =
        forM (
            info   <- pickupTarget(scene);
            player <- PlayerData.PartyQuery.get(info#playerId);
            chest  <- World.chestAtOf(info#gridPos, World.WorldQuery.get())   // P3-b: World 権威
        ) yield (info, player, chest)

    /// 拾う主体(playerId)と拾う位置(gridPos)を決める。選択中の味方が足元のアイテムを拾う。
    def pickupTarget(_scene: Scene[NodeTag]):
            Option[{playerId = Int32, gridPos = {x = Int32, y = Int32}}]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        selectedPlayerInfo()

    /// 選択中の味方の id と現在位置をまとめて返す。
    /// SelectedPlayer 未選択 / PartyQuery で見つからないいずれでも None。
    def selectedPlayerInfo():
            Option[{playerId = Int32, gridPos = {x = Int32, y = Int32}}]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        forM (
            playerId <- SelectedPlayer.State.get()#id;
            player   <- PlayerData.PartyQuery.get(playerId)
        ) yield {playerId = playerId, gridPos = player#gridPos}

    /// 「こうげき」確定時の遷移: 武器選択ウィンドウ (WeaponSelect) を開く。
    /// ActionMenu はそのまま表示し続け「攻撃」行のハイライトを残す（focus だけ武器側へ移る）。
    /// 実際の装備と攻撃フェーズ進入は武器を選んだあと `WeaponSelectScene.onConfirmed` が行う。
    /// SelectedPlayer は「攻撃」項目が出ている時点で必ずセット済みなので、ここでは触らない。
    def enterWeaponSelect(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.WeaponSelect);
        scene

    /// PlayerMoving + Z 押下時の遷移: 行動選択ウィンドウを開く (フェーズ = ActionSelect)。
    /// 青マス表示はそのまま維持し、ItemList を visibility 適用で表示する。
    /// 「こうげき / たいき / ひろう」の項目は `refreshItems` が毎フレーム再構築。
    ///
    /// 各 openFrom* (openFromMoving / openFromCursor / openFromGather) の実装は
    /// `TurnPhase.State.put(ActionSelect); scene` と同一だが、呼び出し元フェーズを
    /// コールサイトで明示してファイル内 grep を容易にするために分けている。
    pub def openFromMoving(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// PlayerCursor + Z 押下時 (空マス) の遷移: 集合メニュー (しゅうごう) を開く。
    /// SelectedPlayer は None のままなので `buildItems` がしゅうごうのみを返す。
    /// カーソルは PlayerCursor で visible のまま据え置く。
    /// (openFromMoving の doc に設計意図を記載)
    pub def openFromCursor(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// GatherMove (集合・行軍) + Z 押下時の遷移: 隣接メニュー (交換 / 全員待機 / キャンセル)
    /// を開く。SelectedPlayer は主人公(0) のまま・`gatherActive` も true のままなので
    /// `buildItems` が `gatherAdjacentMenuItems` を返す。X で `onActionCancelled` が GatherMove
    /// に戻す（移動やり直し）。(openFromMoving の doc に設計意図を記載)
    pub def openFromGather(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// X / Escape 押下で呼ばれる。メニューを閉じて元のフェーズに戻る。戻り先フェーズの
    /// overlay / cursor 状態は **`PhaseTransitions.enter*` に委譲**して確立する。ここで
    /// `put` だけして scene を素通しすると、空マスメニュー由来（SelectedPlayer = None）で
    /// 武器 / アイテム / 交換がカーソルを隠したまま PlayerCursor に戻り「カーソル消失・
    /// 操作不能」状態に陥る（既知バグ）。`enter*` がカーソル再表示・snap（None 経路）/
    /// 青マス再構築（Some 経路）まで一手に確立する。
    /// 不変条件: Input.Cancel → ゲームプレイ復帰フェーズの経路は **必ず `enter*` を経由**
    /// する（bare `put` 禁止）。TestActionMenuScene の各分岐テストがこれを封じる。
    ///   - gatherActive          → enterGatherMove   （集合・行軍へ。移動やり直し）
    ///   - SelectedPlayer = Some → enterPlayerMoving （駒操作中。カーソルは設計上非表示）
    ///   - SelectedPlayer = None → enterPlayerCursor （空マス由来。カーソル再表示＋snap）
    pub def onActionCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag] \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                                                TurnPhase.State, SelectedPlayer.State,
                                                PlayerData.PartyQuery, World.Command, World.WorldQuery} =
        let sel = SelectedPlayer.State.get();
        if (sel#gatherActive)
            PhaseTransitions.enterGatherMove(scene)
        else match sel#id {
            case Some(_) => PhaseTransitions.enterPlayerMoving(scene)
            case None    => PhaseTransitions.enterPlayerCursor(scene)
        }

    /// InputHandler の Z 押下から呼ばれる。現在カーソルがある項目を確定する。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler,
                GameLogger.GameLogger,
                EnemyTurn.Queue, TurnPhase.State, SelectedPlayer.State,
                GatherResume.State, PlayerData.PartyQuery,
                CustomEffects.FloorAdvanceRequest, GameEngine.Audio, World.Command, World.WorldQuery, BoardQuery,
                ItemPickupPopupScene.State} =
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            // disabled 項目（例: 敵が射程外の「攻撃」）は確定しても何もしない。
            case Some(entry) => if (entry#disabled) scene else onActionConfirmed(entry, scene)
            case None        => scene
        }
}
