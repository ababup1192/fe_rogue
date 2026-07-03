// WeaponSelectUi — 武器選択ウィンドウ（World-entity UI 版）。
//
// UI ツリーは WeaponSelect.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「選択中味方の武器一覧から行を組む / 可視・選択・
// disabled 淡色・パネル位置を毎フレーム同期する / 確定・キャンセルのゲームロジックを適用する」の
// ゲーム側配線を持つ。
//
// ActionMenu「攻撃」確定で `WeaponSelect` フェーズに入り、ActionMenu の **右隣に少し重ねて**
// 出る。コマンドメニュー (ActionMenu) は表示したまま「攻撃」行のハイライトを残す。
//
// 各行:
//   - 左          : 武器タイプのアイコン（武器 sprite）
//   - 1 行目       : 武器名。右端のバッジ「不得意」（色付きカプセル背景 + 白文字）は、その武器タイプを
//                    **苦手** とするときだけ出す（得意なら何も出さない＝「得意」バッジは出さない）。
//   - 2 行目(subline): 性能「威力 ${攻} 耐久 ${耐久} 重さ ${重量}」（命中・射程は戦闘予報ミニ窓で見せる）
//
// 操作:
//   - ↑↓ で武器を選び Enter/Z で確定 → 選んだ武器を装備 (weapons 先頭へ移動) してから
//     攻撃フロアに入る（赤マス→敵選択→予報→攻撃）。
//   - X/Escape でウィンドウを閉じて ActionSelect（コマンドメニュー）に戻る。
//
// ノード構造（WeaponSelect.ui.json / layer=7）:
//   WeaponSelect (none, 画面固定 HUD)
//     └─ panel (box, パネル地・ActionMenu 右隣に abs 追従)
//           ├─ header (box) 「武器」＋「◀ 敵選択 ▶」ヒント
//           └─ menu (none, 縦並び・gap 0・行ピッチ 12px 固定)
//                 ├─ highlight (box) 選択行の塗り箱（abs 子・行より背面 z・選択位置へ毎フレ移動）
//                 └─ row0..row7 (none, 固定高 12px) 武器 1 本ぶんの行
//                       （iconBg>icon, info>nameRow>name+badge(box カプセル), info>subline）
//
// 行は最大 8 本（低レベルの積載目安は武器 3〜4 本だが、積載量は体格/力の成長で伸びるため
// 明確な上限が無い。ActionMenu の既知最大 7 項目より少し多い枠を確保した判断値）。
mod WeaponSelectUi {

    // ========================================================================
    // spec 置き場 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/WeaponSelect.ui.json")

    /// root（可視トグルの対象）とパネル / リスト所有 entity の名前パス。
    pub def rootPath(): String = "WeaponSelect"
    def panelPath(): String = "WeaponSelect/panel"
    def menuPath(): String = "WeaponSelect/panel/menu"

    /// 行の最大数（ui.json の row0..row7 と一致させること）。
    /// pub: 実 asset の row 宣言数と一致することをテストが pin するため。
    pub def maxSlots(): Int32 = 8
    def rowPath(i: Int32): String = "${menuPath()}/row${i}"
    def iconPath(i: Int32): String = "${rowPath(i)}/iconBg/icon"
    def namePath(i: Int32): String = "${rowPath(i)}/info/nameRow/name"
    def badgePath(i: Int32): String = "${rowPath(i)}/info/nameRow/badge"
    def sublinePath(i: Int32): String = "${rowPath(i)}/info/subline"
    /// 選択行の塗り箱（menu 直下の abs 子）の名前パス。
    def highlightPath(): String = "${menuPath()}/highlight"

    /// 行ピッチ（px）。ui.json の各行 height と一致させること（旧 ItemList itemHeight=12。
    /// 各行は武器名 + 2 行目性能の 2 段組なのでコマンドメニューより高い）。
    def rowPitch(): Float64 = 12.0
    /// 塗り箱の行セル内マージン（px）。ui.json の highlight abs / 寸法と整合させること（旧 inset=0.5）。
    def highlightInset(): Float64 = 0.5

    /// パネルの design 空間での固定 y（ui.json の panel abs y と一致）。x は毎フレーム
    /// ActionMenu の右端へ追従させる（`applyPanelPosition`）。
    def panelY(): Float64 = 40.0
    /// コマンドメニュー (ActionMenu) に重ねる px 量。右端から少しだけ食い込ませて
    /// 「攻撃」を選んでいる文脈を見せつつ、深く被って読みづらくならないようにする。
    def panelOverlapPx(): Float64 = 5.0

    /// 不得意（苦手）な武器の行に出すバッジ文字（ui.json の badge テキストと一致）。
    def weakBadge(): String = "不得意"

    // ── 文字色（通常 / disabled=淡色。ActionMenu と同じ方式・配色）──
    // 選択は塗り箱ハイライトで示すため選択行も通常色のまま（旧 ItemList は白文字 + 選択塗り箱）。
    def normalColor(): Color = {r = 0.933f32, g = 0.945f32, b = 0.969f32}
    def disabledColor(): Color = {r = 0.36f32, g = 0.40f32, b = 0.47f32}

    // ========================================================================
    // 行データの組み立て（選択中味方の武器一覧 → 表示行）
    // ========================================================================

    /// 1 フレーム分の行データ。items は名前/disabled/metadata（"w:<idx>"）、
    /// sublines/badges は行 index → 文字列（badges は苦手な行だけキーを持つ）、
    /// weapons は items と同順（アイコンの sprite 解決に使う）。
    type alias WeaponListView = {
        items    = List[ItemEntry],
        sublines = Map[Int32, String],
        badges   = Map[Int32, String],
        weapons  = List[UnitCatalog.WeaponResource]
    }

    /// 空の WeaponListView（未選択 / 非表示時に使う）。
    def emptyWeaponListView(): WeaponListView =
        {items = Nil, sublines = Map.empty(), badges = Map.empty(), weapons = Nil}

    /// 選択中味方が居なければ空リスト。居れば所持武器を並び順どおり行データへ変換する。
    def buildWeaponList(_scene: Scene[NodeTag]): WeaponListView
            \ {SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery} =
        match selectedPlayer() {
            case None         => emptyWeaponListView()
            case Some(player) =>
                let enemies = EnemyData.RosterQuery.getAll();
                let weapons = player#weapons;
                let items = List.mapWithIndex(idx -> w ->
                    weaponEntry(idx, w, not weaponReachesAnyEnemy(player#gridPos, w, enemies)), weapons);
                {items = items, sublines = weaponSublines(weapons),
                 badges = weaponBadges(player#resource, weapons), weapons = weapons}
        }

    /// 選択中味方の Data（PartyQuery 経由）。未選択 / 見つからなければ None。
    def selectedPlayer(): Option[PlayerScene.Data]
            \ {SelectedPlayer.State, PlayerData.PartyQuery} =
        forM (
            id     <- SelectedPlayer.State.get()#id;
            player <- PlayerData.PartyQuery.get(id)
        ) yield player

    /// 武器 1 本ぶんの ItemEntry。1 行目は武器名のみ（性能は subline、不得意は badge）。
    /// `disabled` はその武器の射程内に敵が居ないとき true（淡色・選択不可）。
    /// metadata は `"w:<idx>"` 形式で、確定時に weapons 内 index を引くために持つ。
    def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource, disabled: Bool): ItemEntry = {
        text     = weapon#name,
        disabled = disabled,
        metadata = Some("w:${idx}")
    }

    /// 武器の射程表記。min == max なら「射程 ${min}」、違えば「射程 ${min}-${max}」。
    pub def rangeText(range: WeaponCatalog.WeaponRange): String =
        if (range#min == range#max) "射程 ${range#min}"
        else "射程 ${range#min}-${range#max}"

    /// 武器 1 本ぶんの 2 行目（性能）。命中・射程は戦闘予報ミニウィンドウで見せるのでここでは省く。
    /// 例: "威力 2 耐久 10 重さ 1.8"
    pub def weaponSubline(weapon: UnitCatalog.WeaponResource): String =
        "威力 ${weapon#attack} 耐久 ${weapon#durability} 重さ ${Encumbrance.weightText(Encumbrance.weaponWeight(weapon))}"

    /// 行 index → subline 文字列の Map（全行ぶん）。
    def weaponSublines(weapons: List[UnitCatalog.WeaponResource]): Map[Int32, String] =
        List.foldLeft((acc, pair) ->
            let (idx, w) = pair;
            Map.insert(idx, weaponSubline(w), acc),
            Map.empty(), List.zipWithIndex(weapons))

    /// 行 index → バッジ文字の Map。**苦手な武器の行だけ**「不得意」を入れる
    /// （得意な武器はキー自体を入れない＝バッジ非表示）。`UnitCatalog.proficientWith` で判定。
    pub def weaponBadges(resource: UnitCatalog.PlayerResource,
                          weapons: List[UnitCatalog.WeaponResource]): Map[Int32, String] =
        List.foldLeft((acc, pair) ->
            let (idx, w) = pair;
            if (UnitCatalog.proficientWith(resource, w#weaponType)) acc
            else Map.insert(idx, weakBadge(), acc),
            Map.empty(), List.zipWithIndex(weapons))

    /// 指定位置から `weapon` の射程内に生きている敵 (hp > 0 かつ not isDying) が居るか。
    /// ActionMenuUi.canAttackFrom と同じ判定（攻撃可否＝届く武器があるか、を行単位に分解）。
    pub def weaponReachesAnyEnemy(pos: {x = Int32, y = Int32},
                               weapon: UnitCatalog.WeaponResource,
                               enemies: List[EnemyScene.Data]): Bool =
        List.exists(e -> {
            let ev = EnemyScene.unitView(e);
            ev#hp > 0 and not ev#isDying
                and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
        }, enemies)

    /// metadata の `"w:<idx>"` を weapons 内 index にパースする。不明形式は None。
    pub def parseWeaponIndex(meta: String): Option[Int32] =
        if (String.startsWith({prefix = "w:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
        else None

    /// items の最初の「選択可能（not disabled）」行 index。全部 disabled なら 0。
    def firstEnabledIndex(items: List[ItemEntry]): Int32 =
        items
            |> List.zipWithIndex
            |> List.findLeft(pair -> {let (_i, entry) = pair; not entry#disabled})
            |> Option.map(pair -> {let (i, _entry) = pair; i})
            |> Option.getWithDefault(0)

    /// 選択 index が disabled 行を指しているか（範囲外は false）。
    def selectedIsDisabledAt(sel: Int32, items: List[ItemEntry]): Bool =
        List.nth(sel, items)
            |> Option.map(e -> e#disabled)
            |> Option.getWithDefault(false)

    // ========================================================================
    // 毎フレーム同期（可視 + 行流し込み + パネル追従 + 選択ハイライト）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。
    /// WeaponSelect フェーズの間だけ root を可視化し、選択中味方の武器一覧を行へ流し込み、
    /// カーソルが disabled 行に乗っていたら選択可能行へ寄せ、対象の敵へカーソルをスナップする。
    pub def frameStep(_dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery,
               Tween.Scheduler, AnimationPlayer.Scheduler, CursorState.State, World.WorldQuery,
               UiWorldState.State} =
        let phase = TurnPhase.State.get();
        if (phase != TurnPhase.Phase.WeaponSelect) {
            // 非表示中はカーソルを先頭に戻し、全行を隠して meta も消す
            // （UX: 次に開いたとき常に 1 本目の武器から始める）。
            let ui = UiWorldState.State.get();
            UiWorldState.State.put(ui
                |> UiStore.setVisible(rootPath(), false)
                |> fillRows(emptyWeaponListView())
                |> UiStore.putSelection(menuPath(), 0));
            scene
        } else {
            let view = buildWeaponList(scene);
            let ui0 = UiWorldState.State.get();
            let sel0 = UiStore.selectionOf(menuPath(), ui0);
            let itemCount = List.length(view#items);
            // カーソルが届かない武器(disabled)に乗っていたら、選択可能な先頭武器へ寄せる。
            let selResolved = if (selectedIsDisabledAt(sel0, view#items)) firstEnabledIndex(view#items) else sel0;
            // 防御クランプ: 武器本数が減った直後などにカーソルが範囲外に残っても [0, count) へ収める。
            let sel = if (itemCount <= 0) 0 else Int32.max(0, Int32.min(itemCount - 1, selResolved));
            UiWorldState.State.put(ui0
                |> UiStore.setVisible(rootPath(), true)
                |> applyPanelPosition
                |> fillRows(view)
                |> fillIcons(view#weapons)
                |> UiStore.putSelection(menuPath(), sel)
                |> applyTints(view#items, sel)
                |> UiMenu.applyHighlight({listPath = menuPath(), highlightPath = highlightPath(),
                                          sel = sel, rowPitch = rowPitch(), inset = highlightInset()}));
            // 武器フォーカス中、対象の敵へカーソルを寄せる（選択確定後の最新カーソルを読む）。
            snapCursorToTarget(scene)
        }

    /// 武器ウィンドウを ActionMenu（コマンドメニュー）の右端基準で配置する。ActionMenu の design
    /// 右端（`ActionMenuUi.panelDesignRight()`）を基準に `panelOverlapPx()` だけ左に食い込ませる。
    def applyPanelPosition(ui: UiStore.UiWorld): UiStore.UiWorld \ UiWorldState.State =
        let newX = ActionMenuUi.panelDesignRight() - panelOverlapPx();
        UiStore.setAbs(panelPath(), {x = newX, y = panelY()}, ui)

    /// view を行 0..N へ流し込む。武器のある行は名前/性能/バッジ/meta を設定して可視化、
    /// 余った行は meta を消して不可視にする（display:none で窓が縮む＋選択対象から外れる）。
    /// アイコン（sprite）は `fillIcons` が別途、同じ items 並びで流し込む。
    def fillRows(view: WeaponListView, ui: UiStore.UiWorld): UiStore.UiWorld =
        if (List.length(view#items) > maxSlots())
            bug!("WeaponSelect rows (${List.length(view#items)}) exceed slots (${maxSlots()})")
        else
        List.range(0, maxSlots()) |> List.foldLeft((acc, i) ->
            match List.nth(i, view#items) {
                case Some(entry) =>
                    let hasBadge = Option.nonEmpty(Map.get(i, view#badges));
                    acc
                        |> UiStore.setText(namePath(i), entry#text)
                        |> UiStore.setText(sublinePath(i), Option.getWithDefault("", Map.get(i, view#sublines)))
                        |> UiStore.setVisible(badgePath(i), hasBadge)
                        |> UiStore.setMeta(rowPath(i), Option.getWithDefault("", entry#metadata))
                        |> UiStore.setVisible(rowPath(i), true)
                case None =>
                    acc
                        |> UiStore.clearMeta(rowPath(i))
                        |> UiStore.setVisible(rowPath(i), false)
            }, ui)

    /// 行 index → 武器 sprite を icon スロットへ設定する。`view#weapons`（items と同順）で呼ぶこと。
    def fillIcons(weapons: List[UnitCatalog.WeaponResource], ui: UiStore.UiWorld): UiStore.UiWorld =
        List.zipWithIndex(weapons) |> List.foldLeft((acc, pair) ->
            let (idx, w) = pair;
            if (idx >= maxSlots()) acc
            else UiStore.setSprite({path = iconPath(idx), texture = w#sprite#texture, hframes = w#sprite#hframes,
                                    vframes = w#sprite#vframes, frame = w#sprite#frame}, acc),
            ui)

    /// 行の name text tint を塗る。disabled=淡色、それ以外（選択含む）=通常色
    /// （選択は塗り箱ハイライトで示すため文字色は変えない。index は buildWeaponList の並びと同順）。
    def applyTints(items: List[ItemEntry], _sel: Int32, ui: UiStore.UiWorld): UiStore.UiWorld =
        List.range(0, maxSlots()) |> List.foldLeft((acc, i) ->
            match List.nth(i, items) {
                case Some(entry) =>
                    let tint = if (entry#disabled) disabledColor() else normalColor();
                    UiStore.setTextTint(namePath(i), tint, acc)
                case None => acc
            }, ui)

    // ========================================================================
    // 選択 / 確定 / キャンセル
    // ========================================================================

    /// 選択カーソルを delta（±1）動かす（disabled をスキップ・端で回り込む）。
    pub def moveSelection(delta: Int32, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {UiWorldState.State, SelectedPlayer.State, PlayerData.PartyQuery, EnemyData.RosterQuery} =
        let view = buildWeaponList(scene);
        let ui = UiWorldState.State.get();
        let count = List.length(view#items);
        let disabledAt = i -> List.nth(i, view#items) |> Option.map(e -> e#disabled) |> Option.getWithDefault(true);
        let next = UiWidget.selectionMoveSkipping(count, delta, UiStore.selectionOf(menuPath(), ui), disabledAt);
        UiWorldState.State.put(UiStore.putSelection(menuPath(), next, ui));
        scene

    /// カーソルがある武器の weapons 内 index。選択行の meta `"w:<idx>"` を選択位置から読む
    /// （`CursorScene`/`BattlePanelUi` が対象敵の解決に使う）。未登録 / 無選択なら None。
    pub def hoveredWeaponIndex(): Option[Int32] \ UiWorldState.State =
        let ui = UiWorldState.State.get();
        let sel = UiStore.selectionOf(menuPath(), ui);
        UiMenu.metaAtSelection(menuPath(), sel, ui) |> Option.flatMap(parseWeaponIndex)

    /// InputHandler の Z 押下から呼ばれる。現在カーソルがある武器を確定する（disabled は no-op）。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State,
               CursorState.State, EnemyData.RosterQuery, World.Command, World.WorldQuery,
               PlayerData.PartyQuery, UiWorldState.State} =
        let view = buildWeaponList(scene);
        let ui = UiWorldState.State.get();
        let sel = UiStore.selectionOf(menuPath(), ui);
        match List.nth(sel, view#items) {
            case None        => scene
            case Some(entry) => if (entry#disabled) scene else onConfirmed(entry, scene)
        }

    /// 武器を Enter/Z で確定したとき。**選んだ武器を装備して、カーソルが指している敵に
    /// そのまま攻撃を開始する**（武器フォーカスで対象も選べるので、ここから別の対象選択
    /// フェーズには進まず直接バトルへ）。遷移先は入力ロックの `PlayerAttackHold`。
    /// カーソルが敵に乗っていない（届く敵が無い）ときは何もしない。
    pub def onConfirmed(entry: ItemEntry, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {AnimationPlayer.Scheduler, GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State,
               CursorState.State, EnemyData.RosterQuery, World.Command, World.WorldQuery} =
        let started = forM (
            pid   <- SelectedPlayer.State.get()#id;
            idx   <- entry#metadata |> Option.flatMap(parseWeaponIndex);
            eid   <- EnemyScene.findIdAt(CursorScene.getGridPos(), scene);
            enemy <- EnemyData.RosterQuery.get(eid)
        ) yield {
            let equipped = PlayerScene.equipWeapon(pid, idx, scene);
            TurnPhase.State.put(TurnPhase.Phase.PlayerAttackHold);
            GameLogger.playerLog("${PlayerScene.displayName(pid, equipped)}の攻撃");
            CombatDriver.startAttack(Faction.Player, pid, eid, enemy#gridPos, equipped)
        };
        Option.getWithDefault(scene, started)

    /// X / Escape 押下で呼ばれる。武器ウィンドウを閉じて ActionSelect（コマンドメニュー）に戻る。
    /// SelectedPlayer はそのまま（同じ味方の行動選択に戻る）。WeaponSelect 中に対象の敵へ出して
    /// いたカーソルは隠す（ActionSelect / PlayerMoving はカーソル非表示が既定）。
    pub def onCancelled(scene: Scene[NodeTag]): Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        CursorScene.setVisible(false, scene)

    // ========================================================================
    // カーソルの対象敵スナップ（フォーカス武器が届く敵の上へカーソルを置く）
    // ========================================================================

    /// WeaponSelect 中、カーソルを「フォーカス武器が届く敵」の上に置いてカーソルを表示する。
    /// 既に届く敵に乗っているならその位置を保つ（左右での敵選択を維持。`CursorScene` が巡回する）。
    /// 乗っていない（初回 / 武器を切り替えて今の対象が届かなくなった）ときだけ最寄りの敵へスナップ。
    /// 届く敵が居なければカーソルは触らない。戦闘予報はこのカーソル上の敵で出る。
    def snapCursorToTarget(scene: Scene[NodeTag]): Scene[NodeTag]
            \ {Tween.Scheduler, AnimationPlayer.Scheduler, SelectedPlayer.State, CursorState.State,
               PlayerData.PartyQuery, EnemyData.RosterQuery, World.WorldQuery, UiWorldState.State} =
        match focusedPlayerWeapon() {
            case None                   => scene
            case Some((player, weapon)) =>
                if (isReachableEnemyCell(CursorScene.getGridPos(), player#gridPos, weapon, scene))
                    CursorScene.setVisible(true, scene)   // 既に対象上 → 位置は保持（左右選択を維持）
                else match nearestReachableEnemy(player#gridPos, weapon) {
                    case Some(e) => scene |> CursorScene.setVisible(true) |> CursorScene.snapToCell(e#gridPos)
                    case None    => scene
                }
        }

    /// 選択中味方とフォーカス中の武器。揃わなければ None。
    def focusedPlayerWeapon(): Option[(PlayerScene.Data, UnitCatalog.WeaponResource)]
            \ {SelectedPlayer.State, PlayerData.PartyQuery, UiWorldState.State} =
        forM (
            player <- selectedPlayer();
            widx   <- hoveredWeaponIndex();
            weapon <- List.nth(widx, player#weapons)
        ) yield (player, weapon)

    /// `cell` に居る敵が `weapon` の射程内の生存敵か（カーソルが有効な対象に乗っているかの判定）。
    def isReachableEnemyCell(cell: {x = Int32, y = Int32}, pos: {x = Int32, y = Int32},
                             weapon: UnitCatalog.WeaponResource, scene: Scene[NodeTag]):
            Bool \ {EnemyData.RosterQuery, World.WorldQuery} =
        // 敵 Data は RosterQuery overlay（World-fresh の hp/isDying）で読む（scene 直読みは stale）。
        EnemyScene.findIdAt(cell, scene)
            |> Option.flatMap(id -> EnemyData.RosterQuery.get(id))
            |> Option.map(e -> {
                let ev = EnemyScene.unitView(e);
                ev#hp > 0 and not ev#isDying
                    and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
            })
            |> Option.getWithDefault(false)

    /// `pos` から `weapon` の射程内に居る生存敵のうち、最も近い 1 体（マンハッタン最小）。
    /// 届く敵が居なければ None。`weaponReachesAnyEnemy` と同じ到達判定で個体を選ぶ版。
    def nearestReachableEnemy(pos: {x = Int32, y = Int32},
                              weapon: UnitCatalog.WeaponResource):
            Option[EnemyScene.Data] \ EnemyData.RosterQuery =
        EnemyData.RosterQuery.getAll()
            |> List.filter(e -> {
                let ev = EnemyScene.unitView(e);
                ev#hp > 0 and not ev#isDying
                    and Weapon.inRange(Weapon.manhattan(pos, ev#pos), weapon#range)
            })
            |> List.sortBy(e -> Weapon.manhattan(pos, e#gridPos))
            |> List.head
}
