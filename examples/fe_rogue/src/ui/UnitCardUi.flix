// UnitCardUi — ユニット簡易情報カード（World-entity UI 版・味方左 / 敵右の 2 枚共有レンダラ）。
//
// UI ツリーは UnitCard.ui.json（UiSpec）で宣言し、同じアセットを 2 root で spawn する:
//   - "UnitCard"  … 画面左。下見（PlayerCursor）中はカーソル上のユニット、それ以外は選択中の味方。
//   - "EnemyCard" … 画面右。攻撃フロー（WeaponSelect / PlayerAttack）で狙っている敵。panel を右端へ寄せる。
// どちらも 1 枚のカード（アイコン / 名前 / Lv+EXP / HP バー+数値 / 装備 武器・指輪）で、味方=青 / 敵=赤 を
// 枠線・HP バー色で出し分ける。Lv+EXP 行は味方のみ（levelInfo=Some）。
//
// 表示は毎フレーム frameStep が UiStore の setter（setText/setSprite/setBoxColor/setAbs/setWidthPx/
// setVisible）で流し込む。可変レイアウト（名前幅で Lv 位置を決める・HP 数値の右寄せ・アイコンの中心
// 合わせ・装備名の "…" 省略）は実測幅と定数式で毎フレーム算出する。配色は HTML プロトタイプ準拠。
//
// ノード構造（UnitCard.ui.json / layer=2）:
//   <root> (none) → panel (box) → Icon(sprite) / Name / Lv / ExpTrack+ExpFill /
//                    HpLabel / HpTrack+HpFill / HpText / WeaponMat+WeaponIcon+WeaponText /
//                    RingMat+RingIcon+RingText

mod UnitCardUi {

    /// カード 1 枚に流し込む表示データ（味方 / 敵で共通の閉じレコード）。
    /// `levelInfo` は味方のみ Some（敵は None で Lv+EXP 行を隠す）。
    /// `borderColor`/`barColor` で味方=青 / 敵=赤 を出し分ける（枠線と HP バー）。
    type alias CardView = {
        borderColor = Color,
        barColor    = Color,
        sprite      = Sprite.SpriteResource,
        description = String,
        maxHp       = Int32,
        hp          = Int32,
        weapon      = Option[UnitCatalog.WeaponResource],
        ring        = Option[Ring.RingResource],
        levelInfo   = Option[{level = Int32, exp = Int32}]
    }

    /// 装備 1 スロット（武器 / 指輪）へ渡す平坦レコード。sprite の入れ子を開かず 1 段で持つ。
    type alias EquipView = {
        name = String, texture = String,
        hframes = Int32, vframes = Int32, frame = Int32, offset = Vec2.Vec2
    }

    // ========================================================================
    // spec 置き場 / root 名 / 名前パス
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAssetAs・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/UnitCard.ui.json")

    /// 味方カード（左）/ 敵カード（右）の root 名。同じアセットを 2 root で spawn する。
    pub def allyRootName(): String = "UnitCard"
    pub def enemyRootName(): String = "EnemyCard"

    def panelPath(root: String): String = "${root}/panel"
    def childPath(root: String, child: String): String = "${root}/panel/${child}"

    // ========================================================================
    // レイアウト（panel ローカル座標、設計解像度 240×128）
    // ========================================================================

    /// panel の幅（ui.json と一致）。敵カードを画面右端へ寄せる計算に使う。
    def panelW(): Float64 = 70.0
    /// panel の左上（味方カード）。ui.json の abs と一致。
    def panelLeftX(): Float64 = 2.0
    def panelY(): Float64 = 9.0
    /// 画面右端からの余白（design px）。味方カードの左余白(2)と対称にする。
    def rightMargin(): Float64 = 2.0
    /// 敵カード panel の左上 x（デザイン幅の右端から panel 幅と余白を引く）。
    def designRightX(): Float64 = Int32.toFloat64(Game.designWi()) - panelW() - rightMargin()

    def iconCenter(): Vec2.Vec2 = {x = 10.0, y = 9.5}
    def iconScale(): Vec2.Vec2  = {x = 0.27, y = 0.27}
    def nameX(): Float64 = 21.0
    def nameY(): Float64 = 2.5
    def lvGap(): Float64 = 2.0
    def hpLabelX(): Float64 = 21.0
    def hpBarY(): Float64   = 8.0
    def hpBarH(): Float64   = 1.5
    def hpBarW(): Float64   = 26.0
    /// HP ラベル / 数値はバーの縦中心に合わせる（旧 VerticalAlignment.Center 相当の基準 y）。
    def hpRowCenterY(): Float64 = hpBarY() + hpBarH() / 2.0
    def expBarW(): Float64      = 16.0
    def expGap(): Float64       = 2.0
    def expBarY(): Float64      = nameY() + 1.5
    /// panel 右内側（右余白ぶん内側）。HP 数値はここを右端に右寄せする。
    def panelInnerRight(): Float64 = 67.0
    def equipY(): Float64 = 12.0
    def equipTextY(): Float64 = 13.5
    def weaponIconX(): Float64 = 21.0
    def weaponTextX(): Float64 = 28.0
    def ringIconX(): Float64 = 44.0
    def ringTextX(): Float64 = 51.0
    def equipScale(): Vec2.Vec2 = {x = 0.35, y = 0.35}
    def equipMatPad(): Float64  = 0.6

    def fsName(): Float64 = 3.2
    def fsSmall(): Float64 = 2.4
    def fsTiny(): Float64 = 2.2

    /// 武器名 / 指輪名に使える横幅（あふれたら "…" で省略）。隣の項目へ被らせない。
    def weaponMaxW(): Float64 = (ringIconX() - equipMatPad()) - weaponTextX() - 1.0
    def ringMaxW(): Float64   = panelInnerRight() - ringTextX() - 0.5

    // ========================================================================
    // 配色（HTML プロトタイプの値）— 味方=青 / 敵=赤
    // ========================================================================

    def allyBorderColor(): Color = {r = 0.231f32, g = 0.451f32, b = 0.788f32}
    def allyBarColor(): Color    = {r = 0.314f32, g = 0.580f32, b = 0.902f32}
    def enemyBorderColor(): Color = {r = 0.812f32, g = 0.306f32, b = 0.267f32}
    def enemyBarColor(): Color    = {r = 0.871f32, g = 0.337f32, b = 0.282f32}

    // ========================================================================
    // 純粋ヘルパ（テスト対象）
    // ========================================================================

    /// `text` を `fontSize` で描いて `maxWidth`（panel ローカル px）に収めた文字列を返す。
    /// そのまま収まれば原文。あふれる場合は末尾を削り "…" を付け、収まる最大の prefix を返す。
    pub def fitText(text: String, atlas: FontAtlas, fontSize: Float64, maxWidth: Float64): String =
        let widthOf = s -> textWidth(atlas, fontSize, s);
        if (widthOf(text) <= maxWidth) text
        else {
            let ell = "…";
            List.range(1, String.length(text))
                |> List.reverse
                |> List.findLeft(k -> widthOf(String.take(k, text) + ell) <= maxWidth)
                |> Option.map(k -> String.take(k, text) + ell)
                |> Option.getWithDefault(ell)
        }

    /// バーの塗り幅（px）。`value`/`max` の比率を 0..1 にクランプして `size` に掛ける。
    /// 旧 ProgressBar.setValue（value/max ぶんだけ塗る）と同じ挙動。max<=0 は塗りなし。
    pub def barFillWidth(size: Float64, value: Int32, max: Int32): Float64 =
        if (max <= 0) 0.0
        else size * Float64.max(0.0, Float64.min(1.0, Int32.toFloat64(value) / Int32.toFloat64(max)))

    /// テキストの表示幅（px）。engine_world の TextDraw.width（幅測りの唯一の入口）へ委譲する。
    def textWidth(atlas: FontAtlas, fontSize: Float64, text: String): Float64 =
        TextDraw.width(text, atlas, fontSize)

    /// テキストの表示高さ（px）。縦中心合わせ（HP ラベル / 数値）の top-left y 計算に使う。
    /// engine_world の TextDraw.size（寸法測りの唯一の入口）の高さ成分へ委譲する。
    def textHeight(atlas: FontAtlas, fontSize: Float64, text: String): Float64 =
        TextDraw.size(text, atlas, fontSize)#y

    // ========================================================================
    // 毎フレーム System
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。両カードの表示対象を解決して UiStore へ流し込む。
    /// 味方カードは PlayerCursor 中=カーソル上ユニット / それ以外=選択中味方、敵カードは
    /// WeaponSelect / PlayerAttack の対象敵を出す。対象が無ければそのカードを隠す。
    pub def frameStep(_dt: Duration.Duration, scene: Scene[NodeTag]): Scene[NodeTag]
            \ {GameEngine.Game, SelectedPlayer.State, CursorState.State, TurnPhase.State,
               PlayerData.PartyQuery, World.WorldQuery, UiWorldState.State} =
        let phase = TurnPhase.State.get();
        let leftView = resolveLeft(phase, scene);
        let rightView = resolveRight(phase, scene);
        let atlas = GameEngine.Game.getFontAtlas("ui");
        let ui = UiWorldState.State.get()
            |> renderCard(allyRootName(), leftView, false, atlas)
            |> renderCard(enemyRootName(), rightView, true, atlas);
        UiWorldState.State.put(ui);
        scene

    // ========================================================================
    // 表示対象の解決（旧 process / hoveredIdent / targetEnemyId の移植）
    // ========================================================================

    /// 味方カード（左）の表示対象。PlayerCursor 中はカーソル上ユニット、それ以外は選択中の味方。
    def resolveLeft(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Option[CardView]
            \ {PlayerData.PartyQuery, SelectedPlayer.State, CursorState.State, World.WorldQuery} =
        if (phase == TurnPhase.Phase.PlayerCursor) hovered(scene)
        else SelectedPlayer.State.get()#id
            |> Option.flatMap(id -> PlayerData.PartyQuery.get(id))
            |> Option.map(playerView)

    /// カーソル上のユニット（敵優先 / フォグ隠れは除外）を CardView へ。空マスなら None。
    /// ident（位置/hidden/フォグ）は scene 読み、味方の表示 Data だけ PartyQuery 経由。
    def hovered(scene: Scene[NodeTag]): Option[CardView]
            \ {PlayerData.PartyQuery, CursorState.State, World.WorldQuery} =
        let coord = CursorScene.getGridPos();
        let visibleEnemy = EnemyScene.findIdAt(coord, scene)
                            |> Option.filter(id -> EnemyScene.isVisible(id, scene));
        match visibleEnemy {
            case Some(id) => EnemyScene.get(id, scene) |> Option.map(enemyView)
            case None     =>
                PlayerScene.getAllWithWorldPos(scene)
                    |> List.filter(d -> not d#hidden and d#gridPos#x == coord#x and d#gridPos#y == coord#y)
                    |> List.head
                    |> Option.flatMap(d -> PlayerData.PartyQuery.get(d#id))
                    |> Option.map(playerView)
        }

    /// 敵カード（右）の表示対象。狙っている敵（BattlePanel と同じ）を CardView へ。
    ///   - WeaponSelect : カーソル上の（フォグで隠れていない）敵
    ///   - PlayerAttack : 選択中味方の attackTargetId
    /// それ以外のフェーズや対象なしは None。
    def resolveRight(phase: TurnPhase.Phase, scene: Scene[NodeTag]): Option[CardView]
            \ {SelectedPlayer.State, CursorState.State, World.WorldQuery} =
        targetEnemyId(phase, scene)
            |> Option.flatMap(eid -> EnemyScene.get(eid, scene))
            |> Option.map(enemyView)

    /// いま狙っている敵の id（左の予報ミニ窓 BattlePanel と同じ対象）。
    def targetEnemyId(phase: TurnPhase.Phase, scene: Scene[NodeTag]):
            Option[Int32] \ {SelectedPlayer.State, CursorState.State, World.WorldQuery} =
        match phase {
            case TurnPhase.Phase.WeaponSelect =>
                EnemyScene.findIdAt(CursorScene.getGridPos(), scene)
                    |> Option.filter(id -> EnemyScene.isVisible(id, scene))
            case TurnPhase.Phase.PlayerAttack =>
                SelectedPlayer.State.get()#id
                    |> Option.flatMap(pid -> PlayerScene.get(pid, scene))
                    |> Option.flatMap(player -> player#attackTargetId)
            case _ => None
        }

    /// 味方 Data → CardView（青・Lv+EXP あり）。装備は「先頭が装備中」規約で解決。
    def playerView(d: PlayerScene.Data): CardView =
        {borderColor = allyBorderColor(), barColor = allyBarColor(),
         sprite = d#resource#sprite, description = d#resource#description,
         maxHp = d#resource#hp, hp = d#hp,
         weapon = PlayerData.equippedWeapon(d#weapons), ring = PlayerData.equippedRing(d),
         levelInfo = Some({level = d#level, exp = d#exp})}

    /// 敵 Data → CardView（赤・Lv+EXP なし）。
    def enemyView(d: EnemyScene.Data): CardView =
        {borderColor = enemyBorderColor(), barColor = enemyBarColor(),
         sprite = d#resource#sprite, description = d#resource#description,
         maxHp = d#resource#hp, hp = d#hp,
         weapon = d#weapon, ring = d#ring, levelInfo = None}

    // ========================================================================
    // UiStore への流し込み
    // ========================================================================

    /// 1 枚のカードを描く（対象なしは root ごと隠す）。`rightAlign`=true で panel を右端へ寄せる（敵カード）。
    def renderCard(root: String, viewOpt: Option[CardView], rightAlign: Bool,
                   atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld \ GameEngine.Game =
        match viewOpt {
            case None       => UiStore.setVisible(root, false, ui)
            case Some(view) => renderPresent(root, view, rightAlign, atlas, ui)
        }

    /// 対象ユニットを 1 枚のカードへ流し込む（可視化 + panel 位置 + 全フィールド）。
    def renderPresent(root: String, view: CardView, rightAlign: Bool,
                      atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld \ GameEngine.Game =
        let panelX = if (rightAlign) designRightX() else panelLeftX();
        ui
            |> UiStore.setVisible(root, true)
            |> UiStore.setAbs(panelPath(root), {x = panelX, y = panelY()})
            |> UiStore.setBoxBorderColor(panelPath(root), view#borderColor)
            |> setPortrait(root, view#sprite)
            |> UiStore.setText(childPath(root, "Name"), view#description)
            |> setLevel(root, view#levelInfo, view#description, atlas)
            |> setHp(root, view, atlas)
            |> setEquipSlot({root = root, key = "Weapon", iconX = weaponIconX(), textX = weaponTextX(),
                            maxW = weaponMaxW(), atlas = atlas, equipOpt = view#weapon |> Option.map(weaponEquipView)})
            |> setEquipSlot({root = root, key = "Ring", iconX = ringIconX(), textX = ringTextX(),
                            maxW = ringMaxW(), atlas = atlas, equipOpt = view#ring |> Option.map(ringEquipView)})

    /// ユニットアイコン（中央基準・元の約 1/3）。texture 実寸から半セルぶん左上へ寄せて中心合わせする。
    def setPortrait(root: String, sprite: Sprite.SpriteResource, ui: UiStore.UiWorld): UiStore.UiWorld \ GameEngine.Game =
        let path = childPath(root, "Icon");
        ui
            |> UiStore.setSprite({path = path, texture = sprite#texture, hframes = sprite#hframes,
                                  vframes = sprite#vframes, frame = sprite#frame})
            |> UiStore.setAbs(path, portraitAbs(sprite))

    /// アイコンの左上（top-left）。中心 iconCenter に offset を足し、半セル（texW/hframes × scale）ぶん戻す。
    def portraitAbs(sprite: Sprite.SpriteResource): Vec2.Vec2 \ GameEngine.Game =
        let scale = iconScale();
        let center = {x = iconCenter()#x + sprite#offset#x * scale#x,
                      y = iconCenter()#y + sprite#offset#y * scale#y};
        match GameEngine.Game.getTextureInfo(sprite#texture) {
            case None       => center
            case Some(info) =>
                let cellW = info#width / Int32.toFloat64(sprite#hframes);
                let cellH = info#height / Int32.toFloat64(sprite#vframes);
                {x = center#x - cellW * scale#x / 2.0, y = center#y - cellH * scale#y / 2.0}
        }

    /// Lv テキスト + EXP ゲージ（味方のみ）。名前幅で Lv 位置、Lv 幅で EXP 位置を決める。敵は 3 ノードを隠す。
    def setLevel(root: String, levelInfoOpt: Option[{level = Int32, exp = Int32}],
                 description: String, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld =
        match levelInfoOpt {
            case None       =>
                ui
                    |> UiStore.setVisible(childPath(root, "Lv"), false)
                    |> UiStore.setVisible(childPath(root, "ExpTrack"), false)
                    |> UiStore.setVisible(childPath(root, "ExpFill"), false)
            case Some(info) =>
                let lvText = "Lv ${info#level}";
                let lvX = nameX() + textWidth(atlas, fsName(), description) + lvGap();
                let lvW = textWidth(atlas, fsSmall(), lvText);
                let expX = lvX + lvW + expGap();
                let expW = barFillWidth(expBarW(), info#exp, LevelSystem.levelThreshold());
                ui
                    |> UiStore.setVisible(childPath(root, "Lv"), true)
                    |> UiStore.setText(childPath(root, "Lv"), lvText)
                    |> UiStore.setAbs(childPath(root, "Lv"), {x = lvX, y = nameY() + 0.6})
                    |> UiStore.setVisible(childPath(root, "ExpTrack"), true)
                    |> UiStore.setVisible(childPath(root, "ExpFill"), true)
                    |> UiStore.setAbs(childPath(root, "ExpTrack"), {x = expX, y = expBarY()})
                    |> UiStore.setAbs(childPath(root, "ExpFill"), {x = expX, y = expBarY()})
                    |> UiStore.setWidthPx(childPath(root, "ExpFill"), expW)
        }

    /// HP ラベル + バー（track+fill）+ 数値。ラベル / 数値はバー中心に縦合わせ、数値は右端そろえ。
    def setHp(root: String, view: CardView, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld =
        let hpTextStr = "${view#hp}/${view#maxHp}";
        let labelTop = hpRowCenterY() - textHeight(atlas, fsTiny(), "HP") / 2.0;
        let hpTextW = textWidth(atlas, fsTiny(), hpTextStr);
        let hpTextTop = hpRowCenterY() - textHeight(atlas, fsTiny(), hpTextStr) / 2.0;
        ui
            |> UiStore.setText(childPath(root, "HpLabel"), "HP")
            |> UiStore.setAbs(childPath(root, "HpLabel"), {x = hpLabelX(), y = labelTop})
            |> UiStore.setBoxColor(childPath(root, "HpFill"), view#barColor)
            |> UiStore.setWidthPx(childPath(root, "HpFill"), barFillWidth(hpBarW(), view#hp, view#maxHp))
            |> UiStore.setText(childPath(root, "HpText"), hpTextStr)
            |> UiStore.setAbs(childPath(root, "HpText"), {x = panelInnerRight() - hpTextW, y = hpTextTop})

    /// `setEquipSlot` の引数束。
    /// `root`: カード root 名（`allyRootName()` / `enemyRootName()`）。
    /// `key`: スロット種別（"Weapon" / "Ring"。子ノード名 `${key}Mat`/`${key}Icon`/`${key}Text` の接頭辞）。
    /// `iconX`/`textX`: アイコン・名前の x 位置（panel ローカル px）。
    /// `maxW`: 名前を収める最大幅（超えたら "…" 省略）。
    /// `atlas`: 名前の幅計測に使うフォント。
    /// `equipOpt`: 表示する装備（None なら 3 ノードを隠す）。
    type alias EquipSlotSpec = {
        root     = String,
        key      = String,
        iconX    = Float64,
        textX    = Float64,
        maxW     = Float64,
        atlas    = FontAtlas,
        equipOpt = Option[EquipView]
    }

    /// 装備 1 スロット（アイコン + 色紙 + 名前）。未装備は 3 ノードを隠す。
    /// 色紙 / アイコンは off*scale ぶん位置補正、名前は maxW に収まるところまで "…" 省略する。
    def setEquipSlot(spec: EquipSlotSpec, ui: UiStore.UiWorld): UiStore.UiWorld =
        let matPath = childPath(spec#root, "${spec#key}Mat");
        let iconPath = childPath(spec#root, "${spec#key}Icon");
        let textPath = childPath(spec#root, "${spec#key}Text");
        match spec#equipOpt {
            case None        =>
                ui
                    |> UiStore.setVisible(matPath, false)
                    |> UiStore.setVisible(iconPath, false)
                    |> UiStore.setVisible(textPath, false)
            case Some(equip) =>
                let iconPos = {x = spec#iconX + equip#offset#x * equipScale()#x,
                               y = equipY() + equip#offset#y * equipScale()#y};
                let matPos = {x = iconPos#x - equipMatPad(), y = iconPos#y - equipMatPad()};
                ui
                    |> UiStore.setVisible(matPath, true)
                    |> UiStore.setAbs(matPath, matPos)
                    |> UiStore.setVisible(iconPath, true)
                    |> UiStore.setAbs(iconPath, iconPos)
                    |> UiStore.setSprite({path = iconPath, texture = equip#texture, hframes = equip#hframes,
                                         vframes = equip#vframes, frame = equip#frame})
                    |> UiStore.setVisible(textPath, true)
                    |> UiStore.setAbs(textPath, {x = spec#textX, y = equipTextY()})
                    |> UiStore.setText(textPath, fitText(equip#name, spec#atlas, fsTiny(), spec#maxW))
        }

    /// 武器 → 装備スロット表示データ（sprite の入れ子を 1 段に平坦化）。
    def weaponEquipView(weapon: UnitCatalog.WeaponResource): EquipView =
        {name = weapon#name, texture = weapon#sprite#texture,
         hframes = weapon#sprite#hframes, vframes = weapon#sprite#vframes,
         frame = weapon#sprite#frame, offset = weapon#sprite#offset}

    /// 指輪 → 装備スロット表示データ。
    def ringEquipView(ring: Ring.RingResource): EquipView =
        {name = ring#name, texture = ring#sprite#texture,
         hframes = ring#sprite#hframes, vframes = ring#sprite#vframes,
         frame = ring#sprite#frame, offset = ring#sprite#offset}
}
