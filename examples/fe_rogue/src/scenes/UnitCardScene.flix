/// UnitCardScene — ユニット簡易情報カード（画面左・「1F」の下、コマンドメニューの上）。
///
/// 2 つの文脈で同じカードを出す:
///   - PlayerCursor（下見）中: カーソルが乗っているユニット（味方/敵）を表示
///   - それ以外で味方を選択中: SelectedPlayer.id の味方を表示
/// どちらでもなければ非表示。旧 UnitInfoPopupScene を置き換える常設カード。
///
/// 内容: アイコン / 名前 / Lv（味方のみ・金色）/ HP（バー＋数値）/ 装備（武器・指輪 横並び）。
/// スタイルは ActionMenu と同じ角丸パネル。配色は HTML プロトタイプ準拠。
/// children は process で毎フレーム再構築する（UnitInfoPopupScene と同作法）。
///
/// ノード構造（layer=2）:
///   UnitCard (CanvasLayer, NodeTag.UnitCard)
///     └─ panel (Panel)
///          ├─ Icon (Sprite2D) / Name / Lv / HpLabel / HpBar / HpText
///          └─ WeaponIcon / WeaponText / RingIcon / RingText
mod UnitCardScene {

    def rootName(): String = "UnitCard"
    pub def rootPath(): NodePath = rootName() :: Nil
    def panelChildName(): String = "panel"
    def panelPath(): NodePath = rootName() :: panelChildName() :: Nil
    def fontName(): String = "ui"
    def sceneJsonPath(): String = AssetPath.resolve("src/scenes/UnitCardScene.scene.json")

    // ── レイアウト（panel ローカル座標、設計解像度 170×128）──
    def iconCenter(): Vec2.Vec2 = {x = 10.0, y = 9.5}
    def iconScale(): Vec2.Vec2  = {x = 0.27, y = 0.27}   // 元の約 1/3
    def nameX(): Float64 = 21.0
    def nameY(): Float64 = 2.5
    def lvGap(): Float64 = 2.0
    // HP 行: 名前のすぐ下に寄せる。バーは細く長く、ラベル/数値はバー中心の縦位置にそろえる。
    def hpLabelPos(): Vec2.Vec2 = {x = 21.0, y = 7.5}
    def hpBarPos(): Vec2.Vec2   = {x = 29.0, y = 8.0}
    def hpBarSize(): Vec2.Vec2  = {x = 26.0, y = 1.5}
    def hpTextY(): Float64 = 7.5
    /// panel 右内側（右余白ぶん内側）。HP 数値はここを右端に右寄せする。
    def panelInnerRight(): Float64 = 67.0
    def equipY(): Float64 = 12.0       // 装備アイコンの上端（枠から離して上へ）
    def equipTextY(): Float64 = 13.5   // 装備名（アイコン中心に縦合わせ）
    def weaponIconX(): Float64 = 21.0
    def weaponTextX(): Float64 = 29.0  // アイコンの右に少し余白を空ける
    def ringIconX(): Float64 = 41.0
    def ringTextX(): Float64 = 49.0
    def equipScale(): Vec2.Vec2 = {x = 0.35, y = 0.35}

    def fsName(): Float64 = 3.2
    def fsSmall(): Float64 = 2.4
    def fsTiny(): Float64 = 2.2

    // ── 配色（HTML プロトタイプの値）──
    def nameColor(): Color    = {r = 0.933f32, g = 0.945f32, b = 0.969f32}  // #eef1f7
    def lvColor(): Color      = {r = 0.961f32, g = 0.773f32, b = 0.259f32}  // #f5c542
    def hpLabelColor(): Color = {r = 0.604f32, g = 0.651f32, b = 0.741f32}  // #9aa6bd
    def hpTrackColor(): Color = {r = 0.031f32, g = 0.043f32, b = 0.063f32}  // #080b10
    def hpFillColor(): Color  = {r = 0.290f32, g = 0.749f32, b = 0.278f32}  // 緑（#3ba83a→#57d654 の中間）
    def hpTextColor(): Color  = {r = 0.804f32, g = 0.835f32, b = 0.902f32}  // #cdd5e6
    def equipColor(): Color   = {r = 0.706f32, g = 0.745f32, b = 0.820f32}  // 淡い白
    /// 装備アイコンの背後に敷く「明るめの色紙」（枠つきプレート）。暗い武器アートを地色から浮かせる。
    def equipMatColor(): Color  = {r = 0.42f32, g = 0.47f32, b = 0.60f32}  // 明るめスレート
    def equipMatBorder(): Color = {r = 0.62f32, g = 0.67f32, b = 0.78f32}  // 一段明るいフチ
    def equipMatPad(): Float64  = 1.2                       // アイコン周囲に空ける余白
    def equipMatSize(): Vec2.Vec2 = {x = 8.0, y = 8.0}      // ~5.6px アイコン + 余白

    /// scene.json で外枠（CanvasLayer + Panel・初期非表示）を宣言し、CanvasLayer に
    /// NodeTag.UnitCard を差し込む。children は process が panelPath() 配下に動的生成。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        SceneLoader.loadSceneWithFont(sceneJsonPath(), atlas,
                                       SceneLoader.constTagParser(NodeTag.NoTag), scene)
            |> Scene.setState(rootPath(), NodeTag.UnitCard)

    /// Game.flix の process redef から NodeTag.UnitCard ノードに dispatch される。
    /// PlayerCursor 中はカーソル上のユニット、それ以外は選択中の味方を表示。
    pub def process(_delta: Duration.Duration, node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag])
                    \ {GameEngine.Game, SelectedPlayer.State, TurnPhase.State} =
        let phase = TurnPhase.State.get();
        // 下見（PlayerCursor）中はカーソル上のユニットを出す。ターン切替バナー中は隠す。
        let cursorActive = phase == TurnPhase.Phase.PlayerCursor
                            and not PhaseBannerScene.isBusy(scene);
        let next =
            if (cursorActive) renderHovered(scene)
            else renderSelected(SelectedPlayer.State.get()#id, scene);
        match Scene.getEngineNode(path, next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// 選択中の味方（id）を表示。未選択なら隠す。
    def renderSelected(idOpt: Option[Int32], scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        match idOpt {
            case Some(id) => match PlayerScene.get(id, scene) {
                case Some(d) => renderPlayer(d, scene)
                case None    => hide(scene)
            }
            case None => hide(scene)
        }

    /// カーソル上のユニット（敵優先 / フォグ隠れは除外）を表示。空マスなら隠す。
    def renderHovered(scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        match hoveredIdent(scene) {
            case Some((kind, id)) =>
                if (kind == "enemy")
                    match EnemyScene.get(id, scene) {
                        case Some(d) => renderEnemy(d, scene)
                        case None    => hide(scene)
                    }
                else
                    match PlayerScene.get(id, scene) {
                        case Some(d) => renderPlayer(d, scene)
                        case None    => hide(scene)
                    }
            case None => hide(scene)
        }

    /// カーソル位置のユニット種別と id（敵優先）。空マスなら None。
    /// フォグで隠れた敵・退場済み(hidden)味方は出さない（UnitInfoPopupScene と同じ規約）。
    def hoveredIdent(scene: Scene[NodeTag]): Option[(String, Int32)] =
        let coord = CursorScene.getGridPos(scene);
        let visibleEnemy = EnemyScene.findIdAt(coord, scene)
                            |> Option.filter(id -> EnemyScene.isVisible(id, scene));
        match visibleEnemy {
            case Some(id) => Some(("enemy", id))
            case None     =>
                PlayerScene.getAll(scene)
                    |> List.findMap(d ->
                        if (not d#hidden and d#gridPos#x == coord#x and d#gridPos#y == coord#y)
                            Some(("player", d#id))
                        else None)
        }

    def renderPlayer(d: PlayerScene.Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        renderUnit(d#resource, d#hp, d#weapons, PlayerData.equippedRing(d), Some(d#level), scene)

    def renderEnemy(d: EnemyScene.Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        renderUnit(d#resource, d#hp, Option.toList(d#weapon), d#ring, None, scene)

    /// panel 配下の動的 children を全消し。
    def clearContents(scene: Scene[NodeTag]): Scene[NodeTag] =
        let names = Scene.getChildrenAt(panelPath(), scene);
        List.foldLeft(acc -> name ->
            Scene.removeAt(List.append(panelPath(), name :: Nil), acc), scene, names)

    def hide(scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> clearContents |> Panel.mapAt(panelPath(), CanvasItem.setVisible(false))

    /// ユニット（味方/敵で共通の開きレコード）のカードを描画する。
    /// `levelOpt` は味方のみ Some（敵は None で Lv 非表示）。
    def renderUnit(res: {description = String, hp = Int32,
                         sprite = Sprite.SpriteResource | r},
                    currentHp: Int32,
                    weapons: List[UnitCatalog.WeaponResource],
                    ring: Option[Ring.RingResource],
                    levelOpt: Option[Int32],
                    scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let cleared = clearContents(scene);
        // アイコン（中央基準・元の約 1/3）
        let off = res#sprite#offset;
        let spritePos: Vec2.Vec2 = {
            x = iconCenter()#x + off#x * iconScale()#x,
            y = iconCenter()#y + off#y * iconScale()#y
        };
        let sprite = Sprite2D.make(res#sprite#texture, spritePos, iconScale())
            |> Sprite2D.setHframes(res#sprite#hframes)
            |> Sprite2D.setVframes(res#sprite#vframes)
            |> Sprite2D.setFrame(res#sprite#frame);
        let withIcon = Scene.addChildAt(panelPath(), "Icon",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag), cleared);
        // 名前（+ Lv は味方のみ、名前幅を測って隣に金色で）
        let nameLabel = Label2D.make(res#description, atlas, fsName())
            |> Node2D.setPosition({x = nameX(), y = nameY()})
            |> CanvasItem.setModulate(nameColor());
        let withName = Scene.addChildAt(panelPath(), "Name",
            EngineNode.Label2DWithState(nameLabel, NodeTag.NoTag), withIcon);
        let withLv = match levelOpt {
            case Some(lv) =>
                let nameW = Label2D.measure(nameLabel)#x;
                let lvLabel = Label2D.make("Lv ${lv}", atlas, fsSmall())
                    |> Node2D.setPosition({x = nameX() + nameW + lvGap(), y = nameY() + 0.6})
                    |> CanvasItem.setModulate(lvColor());
                Scene.addChildAt(panelPath(), "Lv",
                    EngineNode.Label2DWithState(lvLabel, NodeTag.NoTag), withName)
            case None => withName
        };
        // HP ラベル + バー + 数値
        let hpLabel = Label2D.make("HP", atlas, fsTiny())
            |> Node2D.setPosition(hpLabelPos())
            |> CanvasItem.setModulate(hpLabelColor());
        let withHpLabel = Scene.addChildAt(panelPath(), "HpLabel",
            EngineNode.Label2DWithState(hpLabel, NodeTag.NoTag), withLv);
        let hpBar = ProgressBar.make(hpBarSize(), Int32.toFloat64(res#hp), hpFillColor())
            |> Node2D.setPosition(hpBarPos())
            |> ProgressBar.setValue(Int32.toFloat64(currentHp))
            |> ProgressBar.setBackgroundColor(hpTrackColor())
            |> ProgressBar.setBorderWidth(0)
            |> ProgressBar.setCornerRadius(0.75);  // 高さ 1.5px → 半径 0.75 でピル状に丸める
        let withBar = Scene.addChildAt(panelPath(), "HpBar",
            EngineNode.ProgressBarWithState(hpBar, NodeTag.NoTag), withHpLabel);
        // HP 数値はカード右端に右寄せ（バー右に少し余白）。幅を実測して右端そろえ。
        let hpTextBase = Label2D.make("${currentHp}/${res#hp}", atlas, fsTiny())
            |> CanvasItem.setModulate(hpTextColor());
        let hpTextW = Label2D.measure(hpTextBase)#x;
        let hpText = hpTextBase
            |> Node2D.setPosition({x = panelInnerRight() - hpTextW, y = hpTextY()});
        let withHpText = Scene.addChildAt(panelPath(), "HpText",
            EngineNode.Label2DWithState(hpText, NodeTag.NoTag), withBar);
        // 装備（武器・指輪を横並び）。未装備はその項目を省略。
        let withWeapon = match PlayerData.equippedWeapon(weapons) {
            case Some(w) => renderEquip("Weapon", w#sprite, w#name,
                                         weaponIconX(), weaponTextX(), atlas, withHpText)
            case None    => withHpText
        };
        let withRing = match ring {
            case Some(rr) => renderEquip("Ring", rr#sprite, rr#name,
                                          ringIconX(), ringTextX(), atlas, withWeapon)
            case None     => withWeapon
        };
        Panel.mapAt(panelPath(), CanvasItem.setVisible(true), withRing)

    /// 装備 1 個（アイコン + 名前）を equipY() 行に描く。武器・指輪で共用（sprite は開きレコード）。
    /// アイコンと名前のベースラインがそろうよう、テキストはアイコン中心に縦合わせする。
    def renderEquip(key: String,
                     spr: {texture = String, hframes = Int32, vframes = Int32,
                           frame = Int32, offset = Vec2.Vec2 | s},
                     name: String, iconX: Float64, textX: Float64, atlas: FontAtlas,
                     scene: Scene[NodeTag]): Scene[NodeTag] =
        let off = spr#offset;
        let iconPos: Vec2.Vec2 = {
            x = iconX + off#x * equipScale()#x,
            y = equipY() + off#y * equipScale()#y
        };
        // 明るめの色紙（枠つき角丸プレート）をアイコンの背後に敷く。アイコンより一回り大きく、
        // 暗い武器アートが地色（濃紺パネル）に溶けないよう浮かせる枠にする。
        let mat = Panel.make(equipMatSize(), equipMatColor())
            |> Node2D.setPosition({x = iconPos#x - equipMatPad(), y = iconPos#y - equipMatPad()})
            |> Panel.setBorderColor(equipMatBorder())
            |> Panel.setBorderWidth(1)
            |> Panel.setCornerRadius(1.5)
            |> CanvasItem.setZIndex(0);
        let withMat = Scene.addChildAt(panelPath(), "${key}Mat",
            EngineNode.PanelWithState(mat, NodeTag.NoTag), scene);
        let icon = Sprite2D.make(spr#texture, iconPos, equipScale())
            |> Sprite2D.setHframes(spr#hframes)
            |> Sprite2D.setVframes(spr#vframes)
            |> Sprite2D.setFrame(spr#frame)
            |> Sprite2D.setCentered(false)
            |> CanvasItem.setZIndex(1);
        let withIcon = Scene.addChildAt(panelPath(), "${key}Icon",
            EngineNode.Sprite2DWithState(icon, NodeTag.NoTag), withMat);
        let label = Label2D.make(name, atlas, fsTiny())
            |> Node2D.setPosition({x = textX, y = equipTextY()})
            |> CanvasItem.setModulate(equipColor());
        Scene.addChildAt(panelPath(), "${key}Text",
            EngineNode.Label2DWithState(label, NodeTag.NoTag), withIcon)
}
