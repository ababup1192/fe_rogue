/// ItemMenuScene — アイテム選択ウィンドウ（武器 + 杖の統合インベントリ）
///
/// ActionMenu「アイテム」確定で `ItemSelect` フェーズに入り、選択中プレイヤーの
/// `weapons` と `staves` を 1 つの ItemList にまとめて並べる。↑↓ で選択、Enter
/// で確定すると `ItemActionSelect` フェーズに進み、同じ ItemList を「使う / 装備 /
/// 捨てる」のサブメニューに差し替える。
///
/// 表示するサブメニュー項目は選択中アイテムの種別で出し分ける:
///   - 武器: `[装備, 捨てる]`
///   - 杖  : `[使う, 捨てる]`
///
/// 「使う」だけがターン消費アクション（杖発動 → 通常ターン進行）。
/// 「装備」「捨てる」はターン消費せず、ItemMenu に戻って続けて操作できる。
///
/// ノード構造（visible のとき）:
///   ItemMenu (CanvasLayer, layer=2)
///     └─ panel (Panel, NodeTag.ItemPanel)
///           └─ menu (ItemList, NodeTag.ItemMenu)
mod ItemMenuScene {

    use Json.JsonError.JsonError
    use Json.Path.Path.Root

    // ────────────────────────────────────────────────────────
    // (A) 型定義
    // ────────────────────────────────────────────────────────

    /// サブメニューの操作メタ。`onItemConfirmed` がこの値で分岐する。
    def equipMeta(): String = "equip"
    def dropMeta():  String = "drop"
    def useMeta():   String = "use"

    // ────────────────────────────────────────────────────────
    // (B) 定数
    // ────────────────────────────────────────────────────────

    /// scene.json 相対パス。プロジェクトルートから読まれる。
    def sceneJsonPath(): String = "src/scenes/ItemMenuScene.scene.json"

    /// fontManifest で登録した name と一致させる（WeaponMenuScene と同じ "ui"）。
    def fontName(): String = "ui"

    /// CanvasLayer ルート名
    def rootName(): String = "ItemMenu"

    /// Panel 子ノード名
    pub def panelName(): String = "panel"

    /// ItemList 子ノード名
    pub def menuName(): String = "menu"

    pub def rootPath():  NodePath = rootName() :: Nil
    pub def panelPath(): NodePath = rootName() :: panelName() :: Nil
    pub def menuPath():  NodePath = rootName() :: panelName() :: menuName() :: Nil

    /// 武器アイコンの表示サイズ（px）。fontSize 4 / itemHeight 6 の中に収まるよう 5px。
    def iconSize(): Float64 = 5.0

    /// アイコンとテキスト名の間の余白（px）
    def iconTextGap(): Float64 = 1.0

    /// scene.json 内の "tag" 文字列 → NodeTag への変換。
    def tagParser(opt: Option[String]): Result[Json.JsonError, NodeTag] =
        match opt {
            case None                  => Ok(NodeTag.NoTag)
            case Some("NoTag")         => Ok(NodeTag.NoTag)
            case Some("ItemPanel")     => Ok(NodeTag.ItemPanel)
            case Some("ItemMenu")      => Ok(NodeTag.ItemMenu)
            case Some(unknown)         =>
                Err(JsonError(Root, Set#{"ItemMenuScene tag (got: ${unknown})"}))
        }

    // ────────────────────────────────────────────────────────
    // (C) 構築
    // ────────────────────────────────────────────────────────

    /// scene に ItemMenu ノードツリーを追加する。
    /// `loadSceneWithFont` は ItemList を含むので FontAtlas 必須。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas, tagParser, scene)

    /// 「アイテムメニューが現在 visible か」のヘルパー。
    /// gameLoop の Escape→quit 判定で「メニュー表示中は Escape を quit に流さない」用途。
    pub def isVisible(scene: Scene[NodeTag]): Bool =
        Panel.getAt(panelPath(), scene)
            |> Option.map(CanvasItem.isVisible)
            |> Option.getWithDefault(false)

    // ────────────────────────────────────────────────────────
    // (D) ロジック
    // ────────────────────────────────────────────────────────

    /// フェーズ遷移時の visibility 適用（Push モデル）。
    /// `ItemSelect` または `ItemActionSelect` のいずれかで visible + focused、
    /// それ以外のフェーズでは hidden。
    pub def applyVisibility(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Scene[NodeTag] =
        let visible = phase == TurnPhase.Phase.ItemSelect
                    or phase == TurnPhase.Phase.ItemActionSelect;
        scene
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(visible))
            |> ItemList.mapAt(menuPath(), list ->
                list |> CanvasItem.setVisible(visible) |> ItemList.setFocused(visible))

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から ItemMenu の ItemList
    /// ノードに対して dispatch される (per-node、ItemList は 1 個のみなので 1 フレーム 1 回)。
    /// 責務:
    ///   1. Panel + ItemList の visible/focused を毎フレーム phase で再評価
    ///   2. `ItemSelect` フェーズなら weapons + staves を items + icons に同期
    ///   3. `ItemActionSelect` フェーズなら選択中アイテムに応じてサブメニュー項目を組む
    pub def refreshItems(_delta: Duration.Duration, node: EngineNode[NodeTag],
                         _path: NodePath,
                         scene: Scene[NodeTag]):
                        (EngineNode[NodeTag], Scene[NodeTag])
                        \ {SelectedPlayer.State, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        let withVisibility = applyVisibility(phase, scene);
        let withItems = match phase {
            case TurnPhase.Phase.ItemSelect =>
                refreshItemList(withVisibility)
            case TurnPhase.Phase.ItemActionSelect =>
                refreshActionList(withVisibility)
            case _ => withVisibility
        };
        match Scene.getEngineNode(menuPath(), withItems) {
            case Some(latest) => (latest, withItems)
            case None         => (node, withItems)
        }

    /// 選択中プレイヤーの weapons + staves を 1 つの ItemList に並べる（ItemSelect 中）。
    /// 順序は「武器（先頭が装備中）→ 杖」。metadata に種別と index を持たせて確定時に取り出す。
    def refreshItemList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None => scene
            case Some(playerId) =>
                let weapons = PlayerScene.getWeapons(playerId, scene);
                let staves  = PlayerScene.getStaves(playerId, scene);
                let weaponEntries = List.mapWithIndex(idx -> w ->
                    weaponEntry(idx, w), weapons);
                let staffEntries = List.mapWithIndex(idx -> s ->
                    staffEntry(idx, s), staves);
                let items = List.append(weaponEntries, staffEntries);
                let weaponIcons = buildWeaponIcons(weapons);
                let staffIcons  = buildStaffIcons(staves, List.length(weapons));
                let icons = mergeIconMaps(weaponIcons, staffIcons);
                scene |> ItemList.mapAt(menuPath(), list ->
                    list
                        |> ItemList.setItems(items)
                        |> ItemList.setItemIcons(icons)
                        |> ItemList.setIconSize(iconSize())
                        |> ItemList.setIconTextGap(iconTextGap()))
        }

    /// サブメニュー項目を組む（ItemActionSelect 中）。
    /// 選択中アイテムが武器なら `[装備, 捨てる]`、杖なら `[使う, 捨てる]`。
    def refreshActionList(scene: Scene[NodeTag]):
            Scene[NodeTag] \ SelectedPlayer.State =
        match SelectedPlayer.State.get()#id {
            case None => scene
            case Some(playerId) =>
                match PlayerScene.get(playerId, scene) {
                    case None         => scene
                    case Some(player) =>
                        let items = match player#selectedItem {
                            case Some(PlayerScene.ItemKind.Weapon(_)) =>
                                ({text = "そうび",     disabled = false,
                                   metadata = Some(equipMeta())}: ItemEntry) ::
                                ({text = "すてる",     disabled = false,
                                   metadata = Some(dropMeta())}: ItemEntry) :: Nil
                            case Some(PlayerScene.ItemKind.Staff(_)) =>
                                ({text = "つかう",     disabled = false,
                                   metadata = Some(useMeta())}: ItemEntry) ::
                                ({text = "すてる",     disabled = false,
                                   metadata = Some(dropMeta())}: ItemEntry) :: Nil
                            case None => Nil
                        };
                        scene |> ItemList.mapAt(menuPath(), list ->
                            list
                                |> ItemList.setItems(items)
                                |> ItemList.setItemIcons(Map.empty())
                                |> ItemList.setIconSize(iconSize())
                                |> ItemList.setIconTextGap(iconTextGap()))
                }
        }

    /// 武器 1 本ぶんの ItemEntry。metadata は `"w:<idx>"` 形式で種別と index を持つ。
    /// 「武器名 残耐久」の表記は WeaponMenuScene と同じ。
    def weaponEntry(idx: Int32, weapon: UnitCatalog.WeaponResource): ItemEntry = {
        text     = "${weapon#name} ${weapon#durability}",
        disabled = false,
        metadata = Some("w:${idx}")
    }

    /// 杖 1 本ぶんの ItemEntry。metadata は `"s:<idx>"` 形式。
    def staffEntry(idx: Int32, staff: Staff.StaffResource): ItemEntry = {
        text     = "${staff#name} ${staff#durability}",
        disabled = false,
        metadata = Some("s:${idx}")
    }

    /// 武器アイコンを ItemList の itemIcons Map に詰める（行 index → ItemIcon）。
    def buildWeaponIcons(weapons: List[UnitCatalog.WeaponResource]):
            Map[Int32, ItemIcon] =
        List.foldLeft((acc, pair) -> {
            let (idx, w) = pair;
            let icon: ItemIcon = {
                texture = w#sprite#texture,
                hframes = w#sprite#hframes,
                vframes = w#sprite#vframes,
                frame   = w#sprite#frame
            };
            Map.insert(idx, icon, acc)
        }, Map.empty(), List.zipWithIndex(weapons))

    /// 杖アイコンを ItemList の itemIcons Map に詰める。行 index は `weaponCount` でオフセット。
    def buildStaffIcons(staves: List[Staff.StaffResource],
                          weaponCount: Int32): Map[Int32, ItemIcon] =
        List.foldLeft((acc, pair) -> {
            let (idx, s) = pair;
            let icon: ItemIcon = {
                texture = s#sprite#texture,
                hframes = s#sprite#hframes,
                vframes = s#sprite#vframes,
                frame   = s#sprite#frame
            };
            Map.insert(weaponCount + idx, icon, acc)
        }, Map.empty(), List.zipWithIndex(staves))

    /// 2 つのアイコン Map を統合する（key 衝突しない前提）。
    def mergeIconMaps(a: Map[Int32, ItemIcon],
                       b: Map[Int32, ItemIcon]): Map[Int32, ItemIcon] =
        Map.foldLeftWithKey((acc, k, v) -> Map.insert(k, v, acc), a, b)

    /// metadata の `"w:<idx>"` / `"s:<idx>"` を `PlayerScene.ItemKind` にパースする。
    /// 不明形式は `None`。
    pub def parseItemKind(meta: String): Option[PlayerScene.ItemKind] =
        if (String.startsWith({prefix = "w:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerScene.ItemKind.Weapon)
        else if (String.startsWith({prefix = "s:"}, meta))
            String.dropLeft(2, meta) |> Int32.fromString
                                     |> Option.map(PlayerScene.ItemKind.Staff)
        else None

    // ────────────────────────────────────────────────────────
    // (E) 入力ハンドラ
    // ────────────────────────────────────────────────────────

    /// ActionMenu「アイテム」確定で呼ばれる。`ItemSelect` フェーズに遷移する。
    /// PhaseTransitions が overlay 片付け + カーソル非表示も合わせて行う。
    pub def openFor(_playerId: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ TurnPhase.State =
        PhaseTransitions.enterItemSelect(scene)

    /// ItemSelect で項目を Enter 確定したとき。選択中アイテム種別を Data に書いて
    /// `ItemActionSelect` フェーズに進む（サブメニュー表示へ）。
    pub def onItemConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                            Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        match entry#metadata |> Option.flatMap(parseItemKind) {
            case None      => scene
            case Some(kind) =>
                match SelectedPlayer.State.get()#id {
                    case None           => scene
                    case Some(playerId) =>
                        let withItem = PlayerScene.setSelectedItem(playerId, kind, scene);
                        TurnPhase.State.put(TurnPhase.Phase.ItemActionSelect);
                        withItem
                }
        }

    /// ItemSelect で X / Escape 押下: ActionMenu に戻る（= ActionSelect フェーズ）。
    pub def onItemCancelled(scene: Scene[NodeTag]):
                            Scene[NodeTag] \ TurnPhase.State =
        TurnPhase.State.put(TurnPhase.Phase.ActionSelect);
        scene

    /// ItemActionSelect でサブメニュー項目を Enter 確定したとき。
    ///   - 装備: weapons リスト先頭に移動、ItemSelect に戻る（ターン消費なし）
    ///   - 捨てる: 該当アイテム削除、ItemSelect に戻る（ターン消費なし）
    ///   - 使う: 杖の場合のみ。StaffAim フェーズへ（方向選択を待つ）
    pub def onActionConfirmed(entry: ItemEntry, scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State} =
        match entry#metadata {
            case None    => scene
            case Some(m) =>
                match SelectedPlayer.State.get()#id {
                    case None           => scene
                    case Some(playerId) =>
                        match PlayerScene.get(playerId, scene) {
                            case None         => scene
                            case Some(player) =>
                                match player#selectedItem {
                                    case None       => scene
                                    case Some(kind) =>
                                        dispatchAction(m, playerId, kind, scene)
                                }
                        }
                }
        }

    /// サブメニューの metadata 別に処理を分配する。
    def dispatchAction(meta: String, playerId: Int32, kind: PlayerScene.ItemKind,
                        scene: Scene[NodeTag]):
                       Scene[NodeTag]
            \ {GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State} =
        if (meta == equipMeta())
            applyEquip(playerId, kind, scene)
        else if (meta == dropMeta())
            applyDrop(playerId, kind, scene)
        else if (meta == useMeta())
            applyUse(playerId, kind, scene)
        else scene

    /// 「そうび」: 武器の場合のみ実行（杖は装備という概念がないので no-op）。
    /// `equipWeapon` で対象武器を weapons の先頭に移動 → `ItemSelect` フェーズに戻る。
    def applyEquip(playerId: Int32, kind: PlayerScene.ItemKind,
                     scene: Scene[NodeTag]):
                    Scene[NodeTag] \ TurnPhase.State =
        let equipped = match kind {
            case PlayerScene.ItemKind.Weapon(idx) =>
                PlayerScene.equipWeapon(playerId, idx, scene)
            case PlayerScene.ItemKind.Staff(_)    => scene
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, equipped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// 「すてる」: 武器なら `dropWeapon`、杖なら `dropStaff`。
    /// ターン消費せず ItemSelect に戻る（連続して捨てられる）。
    def applyDrop(playerId: Int32, kind: PlayerScene.ItemKind,
                    scene: Scene[NodeTag]):
                   Scene[NodeTag] \ {GameLogger.GameLogger, TurnPhase.State} =
        let dropped = match kind {
            case PlayerScene.ItemKind.Weapon(idx) =>
                let withWeapons = PlayerScene.getWeapons(playerId, scene);
                let name = match List.nth(idx, withWeapons) {
                    case Some(w) => w#name
                    case None    => "?"
                };
                GameLogger.playerLog("P${playerId} は ${name} をすてた");
                PlayerScene.dropWeapon(playerId, idx, scene)
            case PlayerScene.ItemKind.Staff(idx) =>
                let withStaves = PlayerScene.getStaves(playerId, scene);
                let name = match List.nth(idx, withStaves) {
                    case Some(s) => s#name
                    case None    => "?"
                };
                GameLogger.playerLog("P${playerId} は ${name} をすてた");
                PlayerScene.dropStaff(playerId, idx, scene)
        };
        let cleared = PlayerScene.clearSelectedItem(playerId, dropped);
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// 「つかう」: 杖の場合のみ実行（武器の場合は「装備」項目が出るのでここには来ない）。
    /// 杖の発動方向選択フェーズ `StaffAim` に進み、ログに方向キーの操作プロンプトを出す。
    /// selectedItem は保持しておき、`StaffAim` 中の方向入力で
    /// `PlayerScene.applyStaffCast` が読む。
    def applyUse(playerId: Int32, kind: PlayerScene.ItemKind,
                   scene: Scene[NodeTag]):
                  Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State, GameLogger.GameLogger} =
        match kind {
            case PlayerScene.ItemKind.Staff(idx) =>
                let name = staffNameOf(playerId, idx, scene);
                GameLogger.playerLog("P${playerId} は ${name} の方向を選び Z で発射 (X で中止)");
                PhaseTransitions.enterStaffAim(scene)
            case PlayerScene.ItemKind.Weapon(_) => scene
        }

    /// 指定プレイヤーの staves[idx] の名前を返す。範囲外なら "つえ" フォールバック。
    def staffNameOf(playerId: Int32, idx: Int32, scene: Scene[NodeTag]): String =
        match List.nth(idx, PlayerScene.getStaves(playerId, scene)) {
            case Some(staff) => staff#name
            case None        => "つえ"
        }

    /// ItemActionSelect で X / Escape 押下: ItemSelect に戻る（アイテム一覧画面）。
    /// 選択中アイテムをクリアしてサブメニューを抜ける。
    pub def onActionCancelled(scene: Scene[NodeTag]):
                              Scene[NodeTag]
            \ {TurnPhase.State, SelectedPlayer.State} =
        let cleared = match SelectedPlayer.State.get()#id {
            case Some(playerId) => PlayerScene.clearSelectedItem(playerId, scene)
            case None           => scene
        };
        TurnPhase.State.put(TurnPhase.Phase.ItemSelect);
        cleared

    /// InputHandler の Z 押下から呼ばれる。現在のフェーズに応じて
    /// ItemSelect の Enter なら `onItemConfirmed`、ItemActionSelect の Enter なら
    /// `onActionConfirmed` に流す（共通エントリ）。
    pub def confirmCurrentSelection(scene: Scene[NodeTag]):
                                    Scene[NodeTag]
            \ {GameLogger.GameLogger, TurnPhase.State, SelectedPlayer.State} =
        let phase = TurnPhase.State.get();
        match ItemList.getAt(menuPath(), scene) |> Option.flatMap(ItemList.getSelected) {
            case None        => scene
            case Some(entry) =>
                match phase {
                    case TurnPhase.Phase.ItemSelect       => onItemConfirmed(entry, scene)
                    case TurnPhase.Phase.ItemActionSelect => onActionConfirmed(entry, scene)
                    case _                                 => scene
                }
        }
}
