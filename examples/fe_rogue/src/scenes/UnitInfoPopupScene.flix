/// UnitInfoPopupScene — カーソル上のユニット情報を画面左上に出す HUD ウィンドウ
///
/// PlayerCursor フェーズ中（下見）にカーソルが乗っているマスに味方/敵が居れば
/// 画面左上のパネルに情報を表示する。PlayerAttack(ターゲット選択)中は戦闘予測パネルだけを
/// 出すため、このポップアップは表示しない。表示モードは 2 種類:
///   - Status (デフォルト): スプライト + 名前 + HP + ステータス + HP バー
///   - Items: スプライト名 + 所持武器一覧（アイコン + 名前 + 残耐久）
/// Z (決定) を押すと Status ↔ Items で切替。
/// カーソルが別のマスに移ったら viewMode を Status にリセット、空マスなら非表示。
///
/// ノード構造（layer=4）:
///   UnitInfoPopup (CanvasLayer, NodeTag.UnitInfoPanel({shownUnit, viewMode}))
///     └─ Panel (Panel)
///          ├─ Status view children: Sprite / Name / HpText / HpBar / Stats
///          └─ Items  view children: Name / ItemSprite_<i> / ItemText_<i> ...
mod UnitInfoPopupScene {

    // ─── 状態 ─────────────────────────────────────────────────

    /// 表示モード。Z 押下で flip する。
    pub enum ViewMode with Eq {
        case Status
        case Items
    }

    /// 表示中ユニットの識別子（kind は "enemy" か "player"）と現在の表示モード。
    /// `shownUnit = None` で非表示。
    /// `lastHp` は前フレーム描画時の HP。同じユニットでも HP が変われば再描画する
    /// （杖の回復・1ダメ等で HUD が古いまま残るのを防ぐ）。
    pub type alias PanelState = {
        shownUnit = Option[(String, Int32)],
        viewMode  = ViewMode,
        lastHp    = Option[Int32]
    }

    // ─── 定数 ─────────────────────────────────────────────────

    def rootName(): String = "UnitInfoPopup"
    pub def rootPath(): NodePath = rootName() :: Nil

    /// scene.json の Panel.name と一致させる (lowercase で他 window と統一)
    def panelChildName(): String = "panel"
    def panelPath(): NodePath = rootName() :: panelChildName() :: Nil

    def fontName(): String = "ui"

    /// scene.json のパス
    def sceneJsonPath(): String = "src/scenes/UnitInfoPopupScene.scene.json"

    // Status view 用レイアウト
    def spriteScale(): Vec2.Vec2 = {x = 0.5, y = 0.5}
    def spriteCenterLocal(): Vec2.Vec2 = {x = 7.0, y = 8.0}
    def nameLocalPos(): Vec2.Vec2     = {x = 14.0, y = 4.0}
    def hpTextLocalPos(): Vec2.Vec2   = {x = 14.0, y = 14.0}
    def hpBarLocalPos(): Vec2.Vec2    = {x = 14.0, y = 20.0}
    def hpBarSize(): Vec2.Vec2        = {x = 44.0, y = 4.0}
    def statsLocalPos(): Vec2.Vec2    = {x = 3.0,  y = 28.0}

    // Items view 用レイアウト（種族名ヘッダは表示しないので 1 行目を上に詰める）
    def itemsListStartY(): Float64    = 4.0    // 1 行目の y
    def itemsRowHeight(): Float64     = 6.0    // 行の縦ピッチ
    def itemSpriteX(): Float64        = 4.0
    def itemSpriteScale(): Vec2.Vec2  = {x = 0.35, y = 0.35}   // 17px cell → ~6 px
    def itemTextX(): Float64          = 12.0
    def itemsEmptyText(): String      = "アイテムなし"

    def fontSizeBig(): Float64 = 6.0
    def fontSizeSmall(): Float64 = 4.0

    // 色
    def bgColor(): Color = {r = 0.0f32, g = 0.0f32, b = 0.0f32}
    def borderColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    def textColor(): Color = {r = 1.0f32, g = 1.0f32, b = 1.0f32}
    def hpBarFillColor(): Color = {r = 0.5f32, g = 0.9f32, b = 0.2f32}

    // ─── 構築（初回） ─────────────────────────────────────────

    /// scene.json で外枠 (CanvasLayer + Panel + initial 非表示) を宣言し、
    /// 動的 children は renderForKind が `panelPath()` 配下に追加・削除する。
    /// CanvasLayer に PanelState を後から差し込む (NodeTag.NoTag → UnitInfoPanel(state))
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let initialState: PanelState = {
            shownUnit = None, viewMode = ViewMode.Status, lastHp = None
        };
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                                       SceneLoader.constTagParser(NodeTag.NoTag),
                                       scene)
            |> Scene.setState(rootPath(), NodeTag.UnitInfoPanel(initialState))

    // ─── 公開 API ─────────────────────────────────────────────

    /// popup が現在表示中（カーソルがユニットの上に乗っている）か。
    /// 入力ハンドラから Z の意味を切り替える判定に使う。
    pub def isShown(scene: Scene[NodeTag]): Bool =
        Option.nonEmpty(getShownUnit(scene))

    /// Z 押下時に呼ぶ。表示中なら viewMode を Status ↔ Items で flip して再描画する。
    /// 非表示なら何もしない。
    pub def toggleView(scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        match getState(scene) {
            case None    => scene
            case Some(s) =>
                match s#shownUnit {
                    case None              => scene
                    case Some((kind, id))  =>
                        let nextMode = match s#viewMode {
                            case ViewMode.Status => ViewMode.Items
                            case ViewMode.Items  => ViewMode.Status
                        };
                        let withMode = setState({shownUnit = s#shownUnit,
                                                  viewMode = nextMode,
                                                  lastHp = s#lastHp}, scene);
                        renderForKind(kind, id, withMode)
                }
        }

    // ─── 毎フレーム更新 ───────────────────────────────────────

    /// Game.flix の `Node[NodeTag] instance` の `process` redef から、`UnitInfoPanel` ノードに
    /// 対して dispatch される (panel は 1 個のみなので 1 フレーム 1 回)。
    /// カーソル位置のユニットに変化があれば再描画。空マス / cursor フェーズ外なら隠す。
    /// scene 経由で self (rootPath) と子ノードの両方を更新するため、最後に scene から
    /// self の最新ノードを取り直して返す (古い node で打ち消されないように)。
    pub def process(_delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        // ユニット情報ポップアップは PlayerCursor の下見専用。
        // PlayerAttack(ターゲット選択)中は戦闘予測パネルだけ出すので、ここでは表示しない。
        let cursorActive = phase == TurnPhase.Phase.PlayerCursor;
        let next = if (not cursorActive) {
            if (Option.isEmpty(getShownUnit(scene))) scene
            else hide(scene)
        } else {
            let cursorPos = CursorScene.getGridPos(scene);
            let unitIdent = lookupUnitAtScene(cursorPos, scene);
            let prevIdent = getShownUnit(scene);
            let curHp = match unitIdent {
                case None              => None
                case Some((kind, id))  => currentHp(kind, id, scene)
            };
            let prevHp = getLastHp(scene);
            // ユニットが変わったか、HP が変わったかで再描画する。同一ユニットでも杖の
            // 回復や 1 ダメで HP が変動した場合に古い表示が残らないようにする。
            let needsRedraw = unitIdent != prevIdent or curHp != prevHp;
            if (not needsRedraw) scene
            else match unitIdent {
                case Some((kind, id)) =>
                    // 別ユニットに移ったら viewMode を Status にリセット、同一ユニットの
                    // HP 変動なら viewMode は維持。
                    let mode = if (unitIdent != prevIdent) ViewMode.Status
                                else getViewMode(scene);
                    let withState = setState({shownUnit = Some((kind, id)),
                                               viewMode = mode,
                                               lastHp = curHp}, scene);
                    renderForKind(kind, id, withState)
                case None             => hide(scene)
            }
        };
        match Scene.getEngineNode(path, next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// 指定ユニット種別 / id の現在 HP を、引数 scene から直接読み取る
    /// （PartyQuery / RosterQuery は前フレーム頭の sceneRef を返すため、
    ///  フレーム末の杖発動結果が反映されない）。
    def currentHp(kind: String, id: Int32, scene: Scene[NodeTag]): Option[Int32] =
        if (kind == "enemy")
            EnemyScene.get(id, scene) |> Option.map(d -> d#hp)
        else
            PlayerScene.get(id, scene) |> Option.map(d -> d#hp)

    /// 直前フレームの描画時に記憶した HP を返す（無ければ None）。
    def getLastHp(scene: Scene[NodeTag]): Option[Int32] =
        match getState(scene) {
            case Some(s) => s#lastHp
            case None    => None
        }

    // ─── 内部: state アクセス ─────────────────────────────────

    def getState(scene: Scene[NodeTag]): Option[PanelState] =
        match Scene.getState(rootPath(), scene) {
            case Some(NodeTag.UnitInfoPanel(s)) => Some(s)
            case _                              => None
        }

    def setState(s: PanelState, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), n -> match n {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.UnitInfoPanel(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.UnitInfoPanel(s))
            case other => other
        }, scene)

    def getShownUnit(scene: Scene[NodeTag]): Option[(String, Int32)] =
        match getState(scene) {
            case Some(s) => s#shownUnit
            case None    => None
        }

    def getViewMode(scene: Scene[NodeTag]): ViewMode =
        match getState(scene) {
            case Some(s) => s#viewMode
            case None    => ViewMode.Status
        }

    // ─── ユニット参照 ─────────────────────────────────────────

    /// カーソル位置のユニット種別と id（敵優先）。空マスなら None。
    /// 引数 `scene` から直接読み取る（フレーム末の最新状態を反映するため、
    /// effect 経由の RosterQuery/PartyQuery は使わない）。
    def lookupUnitAtScene(coord: {x = Int32, y = Int32},
                            scene: Scene[NodeTag]): Option[(String, Int32)] =
        match EnemyScene.findIdAt(coord, scene) {
            case Some(id) => Some(("enemy", id))
            case None     =>
                PlayerScene.getAll(scene)
                    |> List.findMap(d ->
                        if (d#gridPos#x == coord#x and d#gridPos#y == coord#y)
                            Some(("player", d#id))
                        else None)
        }

    // ─── 表示/非表示 ──────────────────────────────────────────

    /// Panel 配下の動的 children を全部消す（view 切替時に呼ぶ）。
    def clearContents(scene: Scene[NodeTag]): Scene[NodeTag] =
        let childNames = Scene.getChildrenAt(panelPath(), scene);
        List.foldLeft(acc -> name -> {
            let childPath = List.append(panelPath(), name :: Nil);
            Scene.removeAt(childPath, acc)
        }, scene, childNames)

    /// Panel を非表示にして state をクリア（viewMode は Status にリセット）。
    def hide(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> clearContents
            |> Panel.mapAt(panelPath(), CanvasItem.setVisible(false))
            |> setState({shownUnit = None, viewMode = ViewMode.Status, lastHp = None})

    /// kind / id からそのユニットを引いて現在の viewMode に従って描画する。
    /// scene 直読みで現フレーム末の最新 HP を取り出す。
    def renderForKind(kind: String, id: Int32,
                       scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        if (kind == "enemy") renderEnemy(id, scene)
        else renderPlayer(id, scene)

    /// ステータス画面に出すレベル / 経験値。味方のみ持つので Option で渡す（敵は None）。
    type alias LevelExp = {level = Int32, exp = Int32}

    def renderEnemy(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        match EnemyScene.get(id, scene) {
            case None    => hide(scene)
            case Some(d) =>
                let weapons = Option.toList(d#weapon);
                // 敵はレベル / 経験値の概念が無いので None。
                renderPanel(d#resource, d#hp, weapons, None, scene)
        }

    def renderPlayer(id: Int32, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        match PlayerScene.get(id, scene) {
            case None    => hide(scene)
            case Some(d) =>
                renderPanel(d#resource, d#hp, d#weapons,
                            Some({level = d#level, exp = d#exp}), scene)
        }

    /// viewMode に従って Status または Items view を描く。
    def renderPanel(res: UnitCatalog.UnitResource,
                     currentHp: Int32,
                     weapons: List[UnitCatalog.WeaponResource],
                     levelExp: Option[LevelExp],
                     scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let cleared = clearContents(scene);
        let withContents = match getViewMode(cleared) {
            case ViewMode.Status => renderStatusView(res, currentHp, levelExp, cleared)
            case ViewMode.Items  => renderItemsView(res, weapons, cleared)
        };
        // パネルを可視化
        Panel.mapAt(panelPath(), CanvasItem.setVisible(true), withContents)

    // ─── Status view 描画 ────────────────────────────────────

    def renderStatusView(res: UnitCatalog.UnitResource,
                          currentHp: Int32,
                          levelExp: Option[LevelExp],
                          scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        // offset を sprite center 位置に加算（scale 倍する必要があるので注意: ここは
        // popup の表示用なので半分縮小スケールに合わせて offset も半分にする）
        let off = res#sprite#offset;
        let spritePos: Vec2.Vec2 = {
            x = spriteCenterLocal()#x + off#x * spriteScale()#x,
            y = spriteCenterLocal()#y + off#y * spriteScale()#y
        };
        let sprite = Sprite2D.make(res#sprite#texture, spritePos, spriteScale())
            |> Sprite2D.setHframes(res#sprite#hframes)
            |> Sprite2D.setVframes(res#sprite#vframes)
            |> Sprite2D.setFrame(res#sprite#frame);
        let withSprite = Scene.addChildAt(panelPath(), "Sprite",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag), scene);
        // 味方は名前の隣に Lv、HP 行の隣に EXP を出す（敵は素の名前 / HP のみ）。
        let nameText = match levelExp {
            case Some(le) => "${res#description}  Lv ${le#level}"
            case None     => res#description
        };
        let hpStr = match levelExp {
            case Some(le) => "HP ${currentHp}/${res#hp}  EXP ${le#exp}/100"
            case None     => "HP ${currentHp}/${res#hp}"
        };
        let nameLabel = Label2D.make(nameText, atlas, fontSizeBig())
            |> Node2D.setPosition(nameLocalPos())
            |> CanvasItem.setModulate(textColor());
        let withName = Scene.addChildAt(panelPath(), "Name",
            EngineNode.Label2DWithState(nameLabel, NodeTag.NoTag), withSprite);
        let hpText = Label2D.make(hpStr, atlas, fontSizeSmall())
            |> Node2D.setPosition(hpTextLocalPos())
            |> CanvasItem.setModulate(textColor());
        let withHpText = Scene.addChildAt(panelPath(), "HpText",
            EngineNode.Label2DWithState(hpText, NodeTag.NoTag), withName);
        let hpBar = ProgressBar.make(hpBarSize(),
                                       Int32.toFloat64(res#hp), hpBarFillColor())
            |> Node2D.setPosition(hpBarLocalPos())
            |> ProgressBar.setValue(Int32.toFloat64(currentHp))
            |> ProgressBar.setBackgroundColor(bgColor())
            |> ProgressBar.setBorderColor(borderColor())
            |> ProgressBar.setBorderWidth(1);
        let withBar = Scene.addChildAt(panelPath(), "HpBar",
            EngineNode.ProgressBarWithState(hpBar, NodeTag.NoTag), withHpText);
        let statsText = "ATK ${res#attack}  DEF ${res#defense}\nSPD ${res#speed}  MOV ${res#moveTiles}\nSKL ${res#skill}  LCK ${res#luck}";
        let statsLabel = Label2D.make(statsText, atlas, fontSizeSmall())
            |> Node2D.setPosition(statsLocalPos())
            |> CanvasItem.setModulate(textColor());
        Scene.addChildAt(panelPath(), "Stats",
            EngineNode.Label2DWithState(statsLabel, NodeTag.NoTag), withBar)

    // ─── Items view 描画 ─────────────────────────────────────

    def renderItemsView(_res: UnitCatalog.UnitResource,
                         weapons: List[UnitCatalog.WeaponResource],
                         scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        // weapons 一覧（無ければ "アイテムなし"）。種族名ヘッダは出さない。
        if (List.isEmpty(weapons)) {
            let emptyLabel = Label2D.make(itemsEmptyText(), atlas, fontSizeSmall())
                |> Node2D.setPosition({x = itemTextX(), y = itemsListStartY()})
                |> CanvasItem.setModulate(textColor());
            Scene.addChildAt(panelPath(), "Empty",
                EngineNode.Label2DWithState(emptyLabel, NodeTag.NoTag), scene)
        } else {
            let indexed = List.zipWithIndex(weapons);
            List.foldLeft(acc -> pair -> {
                let (i, w) = pair;
                addItemRow(i, w, atlas, acc)
            }, scene, indexed)
        }

    /// 行 i に武器 1 個ぶんの sprite + text を追加する。
    def addItemRow(i: Int32, w: UnitCatalog.WeaponResource, atlas: FontAtlas,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let rowY = itemsListStartY() + Int32.toFloat64(i) * itemsRowHeight();
        // offset を表示スケールに合わせて加算
        let off = w#sprite#offset;
        let iconPos: Vec2.Vec2 = {
            x = itemSpriteX() + off#x * itemSpriteScale()#x,
            y = rowY + off#y * itemSpriteScale()#y
        };
        // sprite icon
        let iconSprite = Sprite2D.make(w#sprite#texture, iconPos, itemSpriteScale())
            |> Sprite2D.setHframes(w#sprite#hframes)
            |> Sprite2D.setVframes(w#sprite#vframes)
            |> Sprite2D.setFrame(w#sprite#frame)
            |> Sprite2D.setCentered(false);
        let withSprite = Scene.addChildAt(panelPath(), "ItemSprite_${i}",
            EngineNode.Sprite2DWithState(iconSprite, NodeTag.NoTag), scene);
        // 名前 + 残耐久
        let text = "${w#name} ${w#durability}";
        let label = Label2D.make(text, atlas, fontSizeSmall())
            |> Node2D.setPosition({x = itemTextX(), y = rowY})
            |> CanvasItem.setModulate(textColor());
        Scene.addChildAt(panelPath(), "ItemText_${i}",
            EngineNode.Label2DWithState(label, NodeTag.NoTag), withSprite)
}
