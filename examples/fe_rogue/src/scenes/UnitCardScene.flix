/// UnitCardScene — ユニット簡易情報カード（画面左・「1F」の下、コマンドメニューの上）。
///
/// 2 つの文脈で同じカードを出す:
///   - PlayerCursor（下見）中: カーソルが乗っているユニット（味方/敵）を表示
///   - それ以外で味方を選択中: SelectedPlayer.id の味方を表示
/// どちらでもなければ非表示の常設カード。
///
/// 内容: アイコン / 名前 / Lv（味方のみ・金色）/ HP（バー＋数値）/ 装備（武器・指輪 横並び）。
/// スタイルは ActionMenu と同じ角丸パネル。配色は HTML プロトタイプ準拠。
/// children は process で毎フレーム再構築する。
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
    /// EnemyCardScene も同じテンプレートを PackedScene で別名インスタンス化するため pub。
    pub def sceneJsonPath(): String = AssetPath.resolve("src/scenes/UnitCardScene.scene.json")

    // ── レイアウト（panel ローカル座標、設計解像度 170×128）──
    /// panel の幅（scene.json と一致）。敵カードを画面右端へ寄せる計算に使う（EnemyCardScene）。
    pub def panelW(): Float64 = 70.0
    def iconCenter(): Vec2.Vec2 = {x = 10.0, y = 9.5}
    def iconScale(): Vec2.Vec2  = {x = 0.27, y = 0.27}   // 元の約 1/3
    def nameX(): Float64 = 21.0
    def nameY(): Float64 = 2.5
    def lvGap(): Float64 = 2.0
    // HP 行: 名前のすぐ下に寄せる。バーは細く長く、ラベル/数値はバー中心の縦位置にそろえる。
    def hpLabelPos(): Vec2.Vec2 = {x = 21.0, y = 7.5}
    def hpBarPos(): Vec2.Vec2   = {x = 29.0, y = 8.0}
    def hpBarSize(): Vec2.Vec2  = {x = 26.0, y = 1.5}
    /// HP ラベル / 数値はバーの縦中心に合わせる（VerticalAlignment.Center の基準 y）。
    def hpRowCenterY(): Float64 = hpBarPos()#y + hpBarSize()#y / 2.0
    // EXP ゲージ: HP バー(26×1.5)より細く短く。Lv テキストのすぐ右、Lv 行の縦中心付近に置く。
    def expBarSize(): Vec2.Vec2 = {x = 16.0, y = 1.0}
    def expGap(): Float64       = 2.0           // Lv テキストとゲージの間隔
    def expBarY(): Float64      = nameY() + 1.5  // Lv 行(y≈3.1, fs2.4)の縦中心付近
    /// panel 右内側（右余白ぶん内側）。HP 数値はここを右端に右寄せする。
    def panelInnerRight(): Float64 = 67.0
    def equipY(): Float64 = 12.0       // 装備アイコンの上端（枠から離して上へ）
    def equipTextY(): Float64 = 13.5   // 装備名（アイコン中心に縦合わせ）
    def weaponIconX(): Float64 = 21.0
    def weaponTextX(): Float64 = 28.0  // 色紙の右に少し余白を空ける（色紙を小さくしたぶん左へ寄せた）
    def ringIconX(): Float64 = 44.0    // 色紙を小さくしたぶん右へ寄せ、武器名との間を広げる
    def ringTextX(): Float64 = 51.0
    def equipScale(): Vec2.Vec2 = {x = 0.35, y = 0.35}

    def fsName(): Float64 = 3.2
    def fsSmall(): Float64 = 2.4
    def fsTiny(): Float64 = 2.2

    // ── 配色（HTML プロトタイプの値）──
    def nameColor(): Color    = {r = 0.933f32, g = 0.945f32, b = 0.969f32}  // #eef1f7
    def lvColor(): Color      = {r = 0.961f32, g = 0.773f32, b = 0.259f32}  // #f5c542
    def hpLabelColor(): Color = {r = 0.604f32, g = 0.651f32, b = 0.741f32}  // #9aa6bd
    def hpTrackColor(): Color = {r = 0.031f32, g = 0.043f32, b = 0.063f32}  // #080b10
    def hpTextColor(): Color  = {r = 0.804f32, g = 0.835f32, b = 0.902f32}  // #cdd5e6
    // EXP ゲージ: 薄めの黄色ベース（塗り=淡い黄 / トラック=暗い黄寄り）。
    def expBarColor(): Color   = {r = 0.949f32, g = 0.871f32, b = 0.451f32}  // 淡い黄 ~#f2de73
    def expTrackColor(): Color = {r = 0.063f32, g = 0.059f32, b = 0.031f32}  // 暗い黄寄り
    // カードのアクセント色（枠線 + HP バー）。味方=青 / 敵=赤（スクショ準拠）。
    def allyBorderColor(): Color      = {r = 0.231f32, g = 0.451f32, b = 0.788f32}  // 青枠 #3b73c9
    def allyBarColor(): Color         = {r = 0.314f32, g = 0.580f32, b = 0.902f32}  // 青バー #5094e6
    pub def enemyBorderColor(): Color = {r = 0.812f32, g = 0.306f32, b = 0.267f32}  // 赤枠 #cf4e44
    pub def enemyBarColor(): Color    = {r = 0.871f32, g = 0.337f32, b = 0.282f32}  // 赤バー #de5648
    /// カード枠線の太さ（design px）。少し細めにする。
    def cardBorderWidth(): Float64 = 0.5
    def equipColor(): Color   = {r = 0.706f32, g = 0.745f32, b = 0.820f32}  // 淡い白
    /// 装備アイコンの背後に敷く「明るめの色紙」（枠つきプレート）。暗い武器アートを地色から浮かせる。
    def equipMatColor(): Color  = {r = 0.42f32, g = 0.47f32, b = 0.60f32}  // 明るめスレート
    def equipMatBorder(): Color = {r = 0.62f32, g = 0.67f32, b = 0.78f32}  // 一段明るいフチ
    def equipMatPad(): Float64  = 0.6                       // アイコン周囲に空ける余白（色紙を小さくし詰めた）
    def equipMatSize(): Vec2.Vec2 = {x = 6.8, y = 6.8}      // ~5.6px アイコン + 余白（アイコンは据え置きで色紙だけ縮小）

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
                    \ {GameEngine.Game, SelectedPlayer.State, TurnPhase.State, PlayerData.PartyQuery, World.WorldQuery} =
        let phase = TurnPhase.State.get();
        // 下見（PlayerCursor）中はカーソル上のユニットを出す。
        let cursorActive = phase == TurnPhase.Phase.PlayerCursor;
        let next =
            if (cursorActive) renderHovered(scene)
            else renderSelected(SelectedPlayer.State.get()#id, scene);
        match Scene.getEngineNode(path, next) {
            case Some(latest) => (latest, next)
            case None         => (node, next)
        }

    /// 選択中の味方（id）を表示。未選択なら隠す。
    /// 表示 Data（hp/在庫/装備指輪/level/exp）は PartyQuery（World オーバーレイ）経由で読む。
    def renderSelected(idOpt: Option[Int32], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, PlayerData.PartyQuery} =
        match idOpt {
            case Some(id) => match PlayerData.PartyQuery.get(id) {
                case Some(d) => renderPlayer(d, scene)
                case None    => hidePanel(panelPath(), scene)
            }
            case None => hidePanel(panelPath(), scene)
        }

    /// カーソル上のユニット（敵優先 / フォグ隠れは除外）を表示。空マスなら隠す。
    /// ident（位置/hidden/フォグ）は scene 読み、味方の表示 Data だけ PartyQuery 経由。
    def renderHovered(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, PlayerData.PartyQuery, World.WorldQuery} =
        match hoveredIdent(scene) {
            case Some((kind, id)) =>
                if (kind == "enemy")
                    match EnemyScene.get(id, scene) {
                        case Some(d) => renderEnemy(d, scene)
                        case None    => hidePanel(panelPath(), scene)
                    }
                else
                    match PlayerData.PartyQuery.get(id) {
                        case Some(d) => renderPlayer(d, scene)
                        case None    => hidePanel(panelPath(), scene)
                    }
            case None => hidePanel(panelPath(), scene)
        }

    /// カーソル位置のユニット種別と id（敵優先）。空マスなら None。
    /// フォグで隠れた敵・退場済み(hidden)味方は出さない。
    def hoveredIdent(scene: Scene[NodeTag]): Option[(String, Int32)] \ World.WorldQuery =
        let coord = CursorScene.getGridPos(scene);
        let visibleEnemy = EnemyScene.findIdAt(coord, scene)
                            |> Option.filter(id -> EnemyScene.isVisible(id, scene));
        match visibleEnemy {
            case Some(id) => Some(("enemy", id))
            case None     =>
                PlayerScene.getAllWithWorldPos(scene)
                    |> List.findMap(d ->
                        if (not d#hidden and d#gridPos#x == coord#x and d#gridPos#y == coord#y)
                            Some(("player", d#id))
                        else None)
        }

    def renderPlayer(d: PlayerScene.Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        renderUnitInto(panelPath(), allyBorderColor(), allyBarColor(), d#resource, d#hp, d#weapons,
                       PlayerData.equippedRing(d), Some({level = d#level, exp = d#exp}), scene)

    def renderEnemy(d: EnemyScene.Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        renderUnitInto(panelPath(), enemyBorderColor(), enemyBarColor(), d#resource, d#hp,
                       Option.toList(d#weapon), d#ring, None, scene)

    /// panel 配下の動的 children を全消し（panelPath を引数化して敵カードと共用）。
    def clearContents(panelPath: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] =
        let names = Scene.getChildrenAt(panelPath, scene);
        List.foldLeft(acc -> name ->
            Scene.removeAt(List.append(panelPath, name :: Nil), acc), scene, names)

    /// 指定 panel のカードを隠す（children を消して panel を非表示）。敵カードと共用。
    pub def hidePanel(panelPath: NodePath, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene |> clearContents(panelPath) |> Panel.mapAt(panelPath, CanvasItem.setVisible(false))

    /// ユニット（味方/敵で共通の開きレコード）のカードを `panelPath` 配下に描画する。
    /// `levelOpt` は味方のみ Some（敵は None で Lv 非表示）。味方カード（左）と敵カード（右）で
    /// 同じレイアウトを共有する（敵カードは内容を反転せず、panel 位置だけ右に寄せる）。
    /// `borderColor` / `barColor` で味方=青 / 敵=赤 を出し分ける（枠線と HP バー）。
    pub def renderUnitInto(panelPath: NodePath, borderColor: Color, barColor: Color,
                           res: {description = String, hp = Int32,
                                 sprite = Sprite.SpriteResource | r},
                           currentHp: Int32,
                           weapons: List[UnitCatalog.WeaponResource],
                           ring: Option[Ring.RingResource],
                           levelInfoOpt: Option[{level = Int32, exp = Int32}],
                           scene: Scene[NodeTag]): Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let cleared = clearContents(panelPath, scene);
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
        let withIcon = Scene.addChildAt(panelPath, "Icon",
            EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag), cleared);
        // 名前（+ Lv は味方のみ、名前幅を測って隣に金色で）
        let nameLabel = Label2D.make(res#description, atlas, fsName())
            |> Node2D.setPosition({x = nameX(), y = nameY()})
            |> CanvasItem.setModulate(nameColor());
        let withName = Scene.addChildAt(panelPath, "Name",
            EngineNode.Label2DWithState(nameLabel, NodeTag.NoTag), withIcon);
        let withLv = match levelInfoOpt {
            case Some(info) =>
                let nameW = Label2D.measure(nameLabel)#x;
                let lvX = nameX() + nameW + lvGap();
                let lvLabel = Label2D.make("Lv ${info#level}", atlas, fsSmall())
                    |> Node2D.setPosition({x = lvX, y = nameY() + 0.6})
                    |> CanvasItem.setModulate(lvColor());
                let lvW = Label2D.measure(lvLabel)#x;
                let withLvLabel = Scene.addChildAt(panelPath, "Lv",
                    EngineNode.Label2DWithState(lvLabel, NodeTag.NoTag), withName);
                // Lv の右に EXP ゲージ（HP より細く短く・薄黄）
                let expBar = ProgressBar.make(expBarSize(),
                                Int32.toFloat64(LevelSystem.levelThreshold()), expBarColor())
                    |> Node2D.setPosition({x = lvX + lvW + expGap(), y = expBarY()})
                    |> ProgressBar.setValue(Int32.toFloat64(info#exp))
                    |> ProgressBar.setBackgroundColor(expTrackColor())
                    |> ProgressBar.setBorderWidth(0)
                    |> ProgressBar.setCornerRadius(0.5);
                Scene.addChildAt(panelPath, "ExpBar",
                    EngineNode.ProgressBarWithState(expBar, NodeTag.NoTag), withLvLabel)
            case None => withName
        };
        // HP ラベル + バー + 数値（ラベル/数値はバー中心に縦合わせ）
        let hpLabel = Label2D.make("HP", atlas, fsTiny())
            |> Node2D.setPosition({x = hpLabelPos()#x, y = hpRowCenterY()})
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(hpLabelColor());
        let withHpLabel = Scene.addChildAt(panelPath, "HpLabel",
            EngineNode.Label2DWithState(hpLabel, NodeTag.NoTag), withLv);
        let hpBar = ProgressBar.make(hpBarSize(), Int32.toFloat64(res#hp), barColor)
            |> Node2D.setPosition(hpBarPos())
            |> ProgressBar.setValue(Int32.toFloat64(currentHp))
            |> ProgressBar.setBackgroundColor(hpTrackColor())
            |> ProgressBar.setBorderWidth(0)
            |> ProgressBar.setCornerRadius(0.75);  // 高さ 1.5px → 半径 0.75 でピル状に丸める
        let withBar = Scene.addChildAt(panelPath, "HpBar",
            EngineNode.ProgressBarWithState(hpBar, NodeTag.NoTag), withHpLabel);
        // HP 数値はカード右端に右寄せ（バー右に少し余白）。幅を実測して右端そろえ。
        let hpTextBase = Label2D.make("${currentHp}/${res#hp}", atlas, fsTiny())
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(hpTextColor());
        let hpTextW = Label2D.measure(hpTextBase)#x;
        let hpText = hpTextBase
            |> Node2D.setPosition({x = panelInnerRight() - hpTextW, y = hpRowCenterY()});
        let withHpText = Scene.addChildAt(panelPath, "HpText",
            EngineNode.Label2DWithState(hpText, NodeTag.NoTag), withBar);
        // 装備（武器・指輪を横並び）。未装備はその項目を省略。
        // 名前が隣の項目へ被らないよう、各名前に使える横幅を渡す（収まらなければ "…" で省略）。
        // 武器名は隣の指輪の色紙左端まで、指輪名は panel 右内側まで（小さな安全余白を引く）。
        let weaponMaxW = (ringIconX() - equipMatPad()) - weaponTextX() - 1.0;
        let ringMaxW = panelInnerRight() - ringTextX() - 0.5;
        let withWeapon = match PlayerData.equippedWeapon(weapons) {
            case Some(w) => renderEquipInto(panelPath, "Weapon", w#sprite, w#name,
                                            weaponIconX(), weaponTextX(), weaponMaxW, atlas, withHpText)
            case None    => withHpText
        };
        let withRing = match ring {
            case Some(rr) => renderEquipInto(panelPath, "Ring", rr#sprite, rr#name,
                                             ringIconX(), ringTextX(), ringMaxW, atlas, withWeapon)
            case None     => withWeapon
        };
        // 枠線を味方=青 / 敵=赤 に塗り、少し細める（表示も同時に on）。
        Panel.mapAt(panelPath, p -> p
            |> CanvasItem.setVisible(true)
            |> Panel.setBorderColor(borderColor)
            |> Panel.setBorderWidth(cardBorderWidth()), withRing)

    /// 装備 1 個（アイコン + 名前）を equipY() 行に描く。武器・指輪で共用（sprite は開きレコード）。
    /// アイコンと名前のベースラインがそろうよう、テキストはアイコン中心に縦合わせする。
    def renderEquipInto(panelPath: NodePath, key: String,
                        spr: {texture = String, hframes = Int32, vframes = Int32,
                              frame = Int32, offset = Vec2.Vec2 | s},
                        name: String, iconX: Float64, textX: Float64, maxTextWidth: Float64,
                        atlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
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
            |> Panel.setBorderWidth(0.5)
            |> Panel.setCornerRadius(1.5)
            |> CanvasItem.setZIndex(0);
        let withMat = Scene.addChildAt(panelPath, "${key}Mat",
            EngineNode.PanelWithState(mat, NodeTag.NoTag), scene);
        let icon = Sprite2D.make(spr#texture, iconPos, equipScale())
            |> Sprite2D.setHframes(spr#hframes)
            |> Sprite2D.setVframes(spr#vframes)
            |> Sprite2D.setFrame(spr#frame)
            |> Sprite2D.setCentered(false)
            |> CanvasItem.setZIndex(1);
        let withIcon = Scene.addChildAt(panelPath, "${key}Icon",
            EngineNode.Sprite2DWithState(icon, NodeTag.NoTag), withMat);
        // 隣の項目へ被らないよう、maxTextWidth に収まるところまで詰める（あふれたら "…" で省略）。
        let label = Label2D.make(fitText(name, atlas, fsTiny(), maxTextWidth), atlas, fsTiny())
            |> Node2D.setPosition({x = textX, y = equipTextY()})
            |> CanvasItem.setModulate(equipColor());
        Scene.addChildAt(panelPath, "${key}Text",
            EngineNode.Label2DWithState(label, NodeTag.NoTag), withIcon)

    /// `text` を `fsTiny` で描いて `maxWidth`（panel ローカル px）に収めた文字列を返す。
    /// そのまま収まれば原文。あふれる場合は末尾を削り "…" を付け、収まる最大の prefix を返す。
    def fitText(text: String, atlas: FontAtlas, fontSize: Float64, maxWidth: Float64): String =
        let widthOf = s -> Label2D.measure(Label2D.make(s, atlas, fontSize))#x;
        if (widthOf(text) <= maxWidth) text
        else
            let ell = "…";
            // n-1, n-2, … 1 文字で試し、"…" を足しても収まる最大の prefix を採る。
            List.range(1, String.length(text))
                |> List.reverse
                |> List.findLeft(k -> widthOf(String.take(k, text) + ell) <= maxWidth)
                |> Option.map(k -> String.take(k, text) + ell)
                |> Option.getWithDefault(ell)
}
