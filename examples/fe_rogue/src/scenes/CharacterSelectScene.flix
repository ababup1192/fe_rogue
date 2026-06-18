/// CharacterSelectScene — ゲーム開始時の出撃メンバー選択画面
///
/// 起動直後（GamePhase.CharacterSelect）に表示する画面。プレイヤーは横スクロールする
/// 「しおり」状のカード列から出撃メンバーを 3 人選び、そのあとリーダー（集合したときに
/// 仲間が合流する先＝ロード）を 1 人選ぶ。選び終えると `PartySelection.State` に
/// リーダーを先頭にした並びで保存し、GamePhase を Playing に切り替える。
/// ダンジョン構築（`GameLifecycle.buildCurrentFloor`）は Playing 突入時に走り、
/// `PlayerScene.add` が保存済みの並びをそのまま使う（先頭がロードになる）。
///
/// 操作（キーボード）:
///   - メンバー選び（PickingMembers）
///       ← → : カードの注目位置を左右に送る（中央のカードが拡大表示＝立ち絵風）
///       Z    : 注目中のカードを選ぶ / 選択を外す（3 人まで）
///       ↓    : 3 人揃っているとき、注目を下の「出撃」ボタンへ移す
///       ↑    : 注目をカード列に戻す
///       Z（出撃ボタンに注目中）: リーダー選びへ進む
///   - リーダー選び（PickingLeader）
///       ← → : 選んだ 3 人の中でリーダー候補を移す
///       Z    : リーダー確定 → ゲーム開始
///       X    : メンバー選びに戻る
///
/// 画面の状態（注目位置・選択リスト・サブモード・カルーセルの横位置）は
/// ルート CanvasLayer の `NodeTag.CharacterSelect(Data)` に持たせる。毎フレームの
/// 見た目更新は `process`、1 押下ごとの操作は `onKeyPressed` が担う（どちらも Game.flix の
/// instance から委譲される）。純粋な選択ロジックは effect を持たない関数に切り出してテストする。
///
/// ノード構造（drawLayer=6。ゲーム HUD より前面の独立画面）:
///   CharacterSelect (CanvasLayer, NodeTag.CharacterSelect(Data))
///     ├─ bg        (Panel designWi×designHi, NoTag)   ← 背景（画面全体を覆う）
///     ├─ counter   (Label2D, NoTag)                  ← 「残り N 人」/ リーダー選びの案内
///     ├─ frame0..7 (Panel, NoTag)                    ← 各カードの枠（注目=白枠 / 選択中=金枠）
///     ├─ card0..7  (Sprite2D, NoTag)                 ← 各ユニットの絵（毎フレーム位置/拡大を更新）
///     ├─ descPanel (Panel, NoTag) + descTitle/descText (Label2D)  ← 右側の特性説明
///     └─ buttonBg  (Panel, NoTag) + buttonLabel (Label2D)         ← 出撃ボタン
mod CharacterSelectScene {


    /// 選択画面のサブモード。
    ///   PickingMembers — 出撃する 3 人を選んでいる段階。
    ///   PickingLeader  — 選んだ 3 人からリーダー（ロード）を選んでいる段階。
    pub enum SubMode with Eq, ToString {
        case PickingMembers
        case PickingLeader
    }

    /// ルート CanvasLayer に持たせる選択画面の状態。
    /// `players`     — 候補ユニット一覧（add のとき確定。確定時に index → 実データの解決に使う）。
    /// `mode`        — 今どちらの段階か。
    /// `focus`       — メンバー選び中に注目しているカードの index（0 始まり）。
    /// `onButton`    — メンバー選び中、注目が「出撃」ボタンに移っているか。
    /// `selected`    — 選んだユニットの index を選んだ順に並べたリスト（最大 3）。
    /// `leaderFocus` — リーダー選び中、`selected` の何番目を候補にしているか。
    /// `carouselX`   — カード列の横位置（注目カードが中央に来るよう process で滑らかに寄せる）。
    pub type alias Data = {
        players     = List[UnitCatalog.PlayerResource],
        // `players` と同じ並び・同じ長さのクラス id。表示は `players` のみで行い、id は
        // 確定時 (`orderedParty`) に PartySelection へ resource と対で渡すために保持する
        // （スポーン後の classId 保存に必要）。
        classIds    = List[String],
        mode        = SubMode,
        focus       = Int32,
        onButton    = Bool,
        selected    = List[Int32],
        leaderFocus = Int32,
        carouselX   = Float64
    }

    /// UI 幅・カルーセル間隔を含む制約から決まる上限。FE シリーズ慣習とも一致。
    def partySize(): Int32 = 3

    def rootName(): String = "CharacterSelect"
    def bgName(): String = "bg"
    def counterName(): String = "counter"
    def descPanelName(): String = "descPanel"
    def descTitleName(): String = "descTitle"
    def descTextName(): String = "descText"
    def buttonBgName(): String = "buttonBg"
    def buttonGlossName(): String = "buttonGloss"
    def buttonLabelName(): String = "buttonLabel"

    def frameName(index: Int32): String = "frame${index}"
    def cardName(index: Int32): String = "card${index}"
    /// 得意武器グリフ行の i 番目（親 Marker2D。配下に WeaponGlyph のピースを並べる）。
    def profGlyphName(index: Int32): String = "profGlyph${index}"
    def profGlyphPath(index: Int32): NodePath = rootName() :: profGlyphName(index) :: Nil

    def rootPath(): NodePath = rootName() :: Nil
    def counterPath(): NodePath = rootName() :: counterName() :: Nil
    def descTitlePath(): NodePath = rootName() :: descTitleName() :: Nil
    def descTextPath(): NodePath = rootName() :: descTextName() :: Nil
    def buttonBgPath(): NodePath = rootName() :: buttonBgName() :: Nil
    def buttonGlossPath(): NodePath = rootName() :: buttonGlossName() :: Nil
    def buttonLabelPath(): NodePath = rootName() :: buttonLabelName() :: Nil
    def framePath(index: Int32): NodePath = rootName() :: frameName(index) :: Nil
    def cardPath(index: Int32): NodePath = rootName() :: cardName(index) :: Nil

    /// project.json の "fonts" エントリで解決される論理名。
    def fontName(): String = "ui"

    /// 描画レイヤー（ゲーム HUD の最前面より更に前。独立画面なので上書きで良い）。
    def drawLayer(): Int32 = 6

    // レイアウト（論理解像度 designWi×designHi 内）。右側 ~50px を説明パネルに割き、左側でカードを送る。
    def screenWidthF(): Float64 = Int32.toFloat64(Game.designWi())
    def screenHeightF(): Float64 = Int32.toFloat64(Game.designHi())
    /// カルーセルの中央 x（カード領域 0..116 の中央）。
    def carouselCenterX(): Float64 = 58.0
    /// カード同士の間隔（論理 px）。枠が重ならない程度に空ける。
    def cardPitch(): Float64 = 40.0
    /// カード（枠）の縦中央。
    def cardCenterY(): Float64 = 52.0
    /// 注目カードの拡大率。枠サイズは据え置きなので余白が生まれ、枠の大きさで注目を示す。
    def focusScale(): Float64 = 0.98
    /// 注目の隣のカードの拡大率。
    def neighborScale(): Float64 = 0.77
    /// それ以外（遠い）のカードの拡大率。
    def farScale(): Float64 = 0.63
    /// カルーセルが目標位置へ寄る速さ（1 秒あたりの寄り係数）。
    def lerpSpeed(): Float64 = 12.0

    /// 注目カードの枠サイズ（少し大きく見せる）。キャラは縮小したが枠は据え置きで余白を持たせる。
    def focusFrameSize(): Vec2.Vec2 = {x = 36.0, y = 50.0}
    /// 通常カードの枠サイズ。
    def normalFrameSize(): Vec2.Vec2 = {x = 30.0, y = 42.0}

    def descSize(): Vec2.Vec2 = {x = 48.0, y = 86.0}
    /// 説明パネルを画面右端から内側へどれだけ離すか（px）。右端基準で配置するための余白。
    /// design 幅が変わっても右端からの相対位置を保つ（Anchor.BottomRight 相当）。1 値で右寄せ量を調整。
    def descRightMargin(): Float64 = 4.0
    /// 説明パネル左端 x。画面右端（screenWidthF）から margin + パネル幅 だけ内側＝右端基準で固定。
    def descAnchorX(): Float64 = screenWidthF() - descRightMargin() - descSize()#x
    def descPos(): Vec2.Vec2 = {x = descAnchorX(), y = 14.0}
    def descTitlePos(): Vec2.Vec2 = {x = descAnchorX() + 3.0, y = 18.0}
    def descTextPos(): Vec2.Vec2 = {x = descAnchorX() + 3.0, y = 28.0}
    // 得意武器グリフ行（「得意武器:」の下に白いグリフを横一列）。濃い説明パネル地の上に出す。
    def maxProfGlyphs(): Int32 = 5
    def glyphRowStartX(): Float64 = descAnchorX() + 6.0
    def glyphRowY(): Float64 = 37.0
    def glyphPitch(): Float64 = 9.0
    def glyphScale(): Float64 = 0.52
    /// 親 Marker2D の zIndex。配下グリフ（zIndex 62〜）が説明パネル(150)より前に出るよう底上げする。
    def glyphParentZIndex(): Int32 = 100
    // カウンタ/出撃ボタンは画面中央に寄せる（screenWidthF 基準＝design 幅が変わっても中央を保つ）。
    def counterPos(): Vec2.Vec2 = {x = screenWidthF() / 2.0, y = 88.0}
    def buttonPos(): Vec2.Vec2 = {x = (screenWidthF() - buttonSize()#x) / 2.0, y = 102.0}
    def buttonSize(): Vec2.Vec2 = {x = 46.0, y = 16.0}
    /// つや（擬似グラデ）の明るい層。ボタン上半分に少し内側で重ねる。
    def buttonGlossPos(): Vec2.Vec2 = {x = buttonPos()#x + 2.0, y = 104.0}
    def buttonGlossSize(): Vec2.Vec2 = {x = 42.0, y = 6.0}
    def buttonGlossAlpha(): Float32 = 0.5f32
    /// buttonPos + buttonSize/2 がラベル中心 = 画面中央。H/V 中央そろえと合わせて文字を枠内に収める。
    def buttonLabelPos(): Vec2.Vec2 = {x = screenWidthF() / 2.0, y = 110.0}

    def counterFontSize(): Float64 = 7.5
    def descTitleFontSize(): Float64 = 4.5
    def descTextFontSize(): Float64 = 4.0
    def buttonFontSize(): Float64 = 8.0

    // 色（RGB 各 0..1）。
    def bgColor(): Color = {r = 0.08f32, g = 0.09f32, b = 0.13f32}
    def descBgColor(): Color = {r = 0.12f32, g = 0.13f32, b = 0.18f32}
    def borderColor(): Color = {r = 0.5f32, g = 0.5f32, b = 0.6f32}
    def focusBorderColor(): Color = UITheme.white()
    def selectedColor(): Color = {r = 0.95f32, g = 0.8f32, b = 0.2f32}
    def textColor(): Color = UITheme.white()
    def dimModulate(): Color = {r = 0.45f32, g = 0.45f32, b = 0.45f32}
    /// カード枠の背景色（背景より少し明るい）。
    def frameColor(): Color = {r = 0.16f32, g = 0.17f32, b = 0.22f32}
    /// 注目でも選択中でもないカード枠の控えめな枠線色。
    def frameDimBorder(): Color = {r = 0.4f32, g = 0.4f32, b = 0.5f32}

    // 出撃ボタンの配色（無効 / 有効 / 有効かつ注目中）。参考 UI に寄せた琥珀色グラデ風。
    /// 無効時（3 人未満）の沈んだ背景・枠・文字。
    def buttonDisabledBg(): Color = {r = 0.22f32, g = 0.21f32, b = 0.20f32}
    def buttonDisabledBorder(): Color = {r = 0.38f32, g = 0.36f32, b = 0.34f32}
    def buttonDisabledText(): Color = {r = 0.55f32, g = 0.53f32, b = 0.5f32}
    /// 有効時（3 人）の深いオレンジ地・上側の明るい琥珀つや・金枠。
    def buttonActiveBg(): Color = {r = 0.82f32, g = 0.42f32, b = 0.10f32}
    def buttonActiveGloss(): Color = {r = 1.0f32, g = 0.72f32, b = 0.28f32}
    /// 有効かつ注目中（出撃へカーソルを移した）ときの明るいオレンジと白枠。
    def buttonFocusBg(): Color = {r = 0.95f32, g = 0.52f32, b = 0.14f32}
    def buttonFocusGloss(): Color = {r = 1.0f32, g = 0.82f32, b = 0.40f32}
    def buttonFocusBorder(): Color = UITheme.white()

    def buttonText(): String = "出撃"

    /// 候補一覧を受け取り、選択画面のノードツリーを scene に追加する。
    /// 初期化は 1 回のみ（`applyPhaseChange(CharacterSelect)` から呼ばれる）。
    /// 文字を出すためにフォントを引く（GameEngine.Game）。最後に初期状態の見た目を一度流し込む。
    pub def add(playersWithIds: List[(String, UnitCatalog.PlayerResource)], scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Game =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let data = initialState(playersWithIds);
        let layer = CanvasLayer.make(drawLayer());
        let built = scene
            |> Scene.addNode(rootName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.CharacterSelect(data)))
            |> addBackground
            |> addCards(data#players)
            |> addDescPanel(atlas)
            |> addButton(atlas)
            |> addCounter(atlas);
        writeVisuals(data, built)

    /// 背景の単色パネル（最背面）。
    def addBackground(scene: Scene[NodeTag]): Scene[NodeTag] =
        let bg = Panel.make({x = screenWidthF(), y = screenHeightF()}, bgColor());
        Scene.addChild(rootName(), bgName(),
            EngineNode.PanelWithState(bg, NodeTag.NoTag), scene)

    /// 「残り N 人」/ リーダー案内のカウンタ（テキストは writeVisuals で設定）。
    def addCounter(atlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let counter = Label2D.make("", atlas, counterFontSize())
            |> Node2D.setPosition(counterPos())
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(6);
        Scene.addChild(rootName(), counterName(),
            EngineNode.Label2DWithState(counter, NodeTag.NoTag), scene)

    /// 候補ユニットぶんのカード（絵）と選択印を追加する。位置/拡大は writeVisuals で毎フレーム更新。
    def addCards(players: List[UnitCatalog.PlayerResource], scene: Scene[NodeTag]):
            Scene[NodeTag] =
        List.foldLeft((acc, index) -> match List.nth(index, players) {
            case None           => acc
            case Some(resource) => addOneCard(index, resource, acc)
        }, scene, List.range(0, List.length(players)))

    /// 1 枚のカード = 枠（Panel）+ その上に乗る絵（中央そろえの Sprite2D）。
    /// 枠の枠線で「注目（白）/ 選択中（金）」を示す。位置/サイズ/色は writeVisuals で毎フレーム更新。
    def addOneCard(index: Int32, resource: UnitCatalog.PlayerResource,
                    scene: Scene[NodeTag]): Scene[NodeTag] =
        let frame = Panel.make(normalFrameSize(), frameColor())
            |> Panel.setBorderColor(frameDimBorder())
            |> Panel.setBorderWidth(1)
            |> CanvasItem.setZIndex(1);
        let sprite = Sprite2D.make(resource#sprite#texture, {x = 0.0, y = 0.0}, {x = 1.0, y = 1.0})
            |> Sprite2D.setCentered(true)
            |> Sprite2D.setHframes(resource#sprite#hframes)
            |> Sprite2D.setVframes(resource#sprite#vframes)
            |> Sprite2D.setFrame(resource#sprite#frame);
        scene
            |> Scene.addChild(rootName(), frameName(index),
                EngineNode.PanelWithState(frame, NodeTag.NoTag))
            |> Scene.addChild(rootName(), cardName(index),
                EngineNode.Sprite2DWithState(sprite, NodeTag.NoTag))

    /// 右側の特性説明パネル（枠 + 見出し + 本文）。テキストは writeVisuals で設定。
    def addDescPanel(atlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        // カード（最前面で zIndex 100）より前に出して、右へスクロールしたカードが
        // 説明パネルに重なって見えないようにする。
        let panel = Panel.make(descSize(), descBgColor())
            |> Node2D.setPosition(descPos())
            |> Panel.setBorderColor(borderColor())
            |> Panel.setBorderWidth(1)
            |> CanvasItem.setZIndex(150);
        let descTitle = Label2D.make("", atlas, descTitleFontSize())
            |> Node2D.setPosition(descTitlePos())
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(151);
        let descText = Label2D.make("", atlas, descTextFontSize())
            |> Node2D.setPosition(descTextPos())
            |> CanvasItem.setModulate(textColor())
            |> CanvasItem.setZIndex(151);
        scene
            |> Scene.addChild(rootName(), descPanelName(),
                EngineNode.PanelWithState(panel, NodeTag.NoTag))
            |> Scene.addChild(rootName(), descTitleName(),
                EngineNode.Label2DWithState(descTitle, NodeTag.NoTag))
            |> Scene.addChild(rootName(), descTextName(),
                EngineNode.Label2DWithState(descText, NodeTag.NoTag))

    /// 下部の「出撃」ボタン（背景パネル + 中央そろえの文字）。色/枠/文字色は writeVisuals で状態に応じて変える。
    def addButton(atlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let bg = Panel.make(buttonSize(), buttonDisabledBg())
            |> Node2D.setPosition(buttonPos())
            |> Panel.setBorderColor(buttonDisabledBorder())
            |> Panel.setBorderWidth(1)
            |> CanvasItem.setZIndex(5);
        // 上側に重ねる明るい層。これで「上が明るく下が濃い」グラデ風の見た目にする。
        let gloss = Panel.make(buttonGlossSize(), buttonActiveGloss())
            |> Node2D.setPosition(buttonGlossPos())
            |> Panel.setBackgroundAlpha(buttonGlossAlpha())
            |> CanvasItem.setVisible(false)
            |> CanvasItem.setZIndex(6);
        let label = Label2D.make(buttonText(), atlas, buttonFontSize())
            |> Node2D.setPosition(buttonLabelPos())
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> Label2D.setVerticalAlignment(VerticalAlignment.Center)
            |> CanvasItem.setModulate(buttonDisabledText())
            |> CanvasItem.setZIndex(7);
        scene
            |> Scene.addChild(rootName(), buttonBgName(),
                EngineNode.PanelWithState(bg, NodeTag.NoTag))
            |> Scene.addChild(rootName(), buttonGlossName(),
                EngineNode.PanelWithState(gloss, NodeTag.NoTag))
            |> Scene.addChild(rootName(), buttonLabelName(),
                EngineNode.Label2DWithState(label, NodeTag.NoTag))


    /// 起動直後の状態。注目は先頭カード、未選択、メンバー選び段階。
    /// `playersWithIds` を表示用 `players`（resource）とクラス id 列 `classIds` に分けて保持する。
    pub def initialState(playersWithIds: List[(String, UnitCatalog.PlayerResource)]): Data =
        {players = List.map(snd, playersWithIds), classIds = List.map(fst, playersWithIds),
         mode = SubMode.PickingMembers, focus = 0, onButton = false,
         selected = Nil, leaderFocus = 0, carouselX = targetCarouselX(0)}

    /// 注目中のカードを選ぶ / 選択を外す。
    /// すでに 3 人選んでいて、注目カードが未選択なら何もしない（上限）。
    pub def toggleSelect(data: Data): Data =
        if (List.memberOf(data#focus, data#selected))
            {selected = List.filter(index -> index != data#focus, data#selected) | data}
        else if (List.length(data#selected) >= partySize())
            data
        else
            {selected = List.append(data#selected, data#focus :: Nil) | data}

    /// ちょうど 3 人選べているか（= 出撃できるか）。
    pub def canDeploy(data: Data): Bool =
        List.length(data#selected) == partySize()

    /// あと何人選ぶ必要があるか（0 を下回らない）。
    pub def remaining(data: Data): Int32 =
        Int32.max(0, partySize() - List.length(data#selected))

    /// 注目カードを左右に動かす（端では反対側へ巻き込む）。ボタンへの注目は外す。
    pub def moveFocus(direction: Int32, data: Data): Data =
        let count = List.length(data#players);
        let raw = data#focus + direction;
        let focus =
            if (raw < 0) count - 1
            else if (raw >= count) 0
            else raw;
        {focus = focus, onButton = false | data}

    /// 注目を「出撃」ボタンへ移す / カード列へ戻す。
    /// ボタンへ移せるのは 3 人揃っているときだけ。
    pub def moveToButton(toButton: Bool, data: Data): Data =
        if (toButton)
            if (canDeploy(data)) {onButton = true | data} else data
        else
            {onButton = false | data}

    /// メンバー選び → リーダー選びへ進む（3 人揃っているときだけ）。
    pub def beginLeaderPick(data: Data): Data =
        if (canDeploy(data))
            {mode = SubMode.PickingLeader, leaderFocus = 0, onButton = false | data}
        else
            data

    /// リーダー候補を選んだ 3 人の中で左右に動かす（端では巻き込む）。
    pub def moveLeaderFocus(direction: Int32, data: Data): Data =
        let count = List.length(data#selected);
        if (count <= 0)
            data
        else
            let raw = data#leaderFocus + direction;
            let leaderFocus =
                if (raw < 0) count - 1
                else if (raw >= count) 0
                else raw;
            {leaderFocus = leaderFocus | data}

    /// リーダー選び → メンバー選びへ戻る。
    pub def backToMembers(data: Data): Data =
        {mode = SubMode.PickingMembers, onButton = false | data}

    /// 選んだユニットの index を「リーダーを先頭」に並べ替える。
    /// 例: selected=[5,1,3], leaderFocus=2（=index 3）→ [3,5,1]。
    /// リーダー以外は選んだ順を保つ（先頭がロードとして spawnGrid に配置されるため重要）。
    pub def orderedIndices(data: Data): List[Int32] =
        let leaderIndex = Option.getWithDefault(0, List.nth(data#leaderFocus, data#selected));
        let others = List.filter(index -> index != leaderIndex, data#selected);
        leaderIndex :: others

    /// `orderedIndices` を実データに解決した出撃パーティ（先頭がリーダー）。
    /// 各メンバーを `(クラス id, PlayerResource)` で返し、PartySelection へ id 付きで保存できるようにする。
    pub def orderedParty(data: Data): List[(String, UnitCatalog.PlayerResource)] =
        List.filterMap(index ->
            forM (
                classId  <- List.nth(index, data#classIds);
                resource <- List.nth(index, data#players)
            ) yield (classId, resource),
            orderedIndices(data))

    /// 注目（拡大表示）するカードの index。メンバー選びは `focus`、
    /// リーダー選びは「選んだ 3 人のうち候補にしているカード」。
    pub def effectiveFocus(data: Data): Int32 =
        match data#mode {
            case SubMode.PickingMembers => data#focus
            case SubMode.PickingLeader  =>
                Option.getWithDefault(0, List.nth(data#leaderFocus, data#selected))
        }

    /// 注目カードが中央に来るためのカード列の横位置。
    pub def targetCarouselX(focus: Int32): Float64 =
        carouselCenterX() - Int32.toFloat64(focus) * cardPitch()

    /// カード列の横位置を目標へ少し近づける（時間に応じた滑らかな寄せ）。
    pub def stepCarousel(data: Data, delta: Duration.Duration): Data =
        let target = targetCarouselX(effectiveFocus(data));
        let dtSeconds = Duration.toSeconds(delta);
        let ratio = Float64.min(1.0, lerpSpeed() * dtSeconds);
        {carouselX = lerp(data#carouselX, target, ratio) | data}

    /// 線形補間。`ratio` が 0.0 で `startValue`、1.0 で `endValue`。
    def lerp(startValue: Float64, endValue: Float64, ratio: Float64): Float64 =
        startValue + (endValue - startValue) * ratio

    /// カード列の横位置を目標へ寄せ、状態から見た目を作り直し、状態を書き戻す。
    /// 末尾で `getEngineNode` により最新ノードを取り直す（writeVisuals が内部でノードを差し替えるため）。
    pub def process(delta: Duration.Duration,
                     node: EngineNode[NodeTag],
                     path: NodePath, scene: Scene[NodeTag]):
                    (EngineNode[NodeTag], Scene[NodeTag]) =
        match node {
            case EngineNode.CanvasLayerWithState(_, NodeTag.CharacterSelect(data)) =>
                let stepped = stepCarousel(data, delta);
                let next = scene
                    |> writeVisuals(stepped)
                    |> setState(stepped);
                match Scene.getEngineNode(path, next) {
                    case Some(latest) => (latest, next)
                    case None         => (node, next)
                }
            case _ => (node, scene)
        }

    /// 1 押下ごとの操作（Game.flix の InputHandler から CharacterSelect phase 中に委譲）。
    pub def onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState, PartySelection.State} =
        let data = getData(scene);
        match data#mode {
            case SubMode.PickingMembers => handleMembersKey(key, data, scene)
            case SubMode.PickingLeader  => handleLeaderKey(key, data, scene)
        }

    /// メンバー選び中のキー処理。
    def handleMembersKey(key: GameEngine.Key, data: Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ GameEngine.Audio =
        if (isLeft(key))      { AudioStreamPlayer.play("cursor"); mapData(moveFocus(-1), scene) }
        else if (isRight(key)) { AudioStreamPlayer.play("cursor"); mapData(moveFocus(1), scene) }
        else if (isDown(key))  { AudioStreamPlayer.play("cursor"); mapData(moveToButton(true), scene) }
        else if (isUp(key))    { AudioStreamPlayer.play("cursor"); mapData(moveToButton(false), scene) }
        else if (isConfirm(key))
            if (data#onButton and canDeploy(data)) {
                AudioStreamPlayer.play("confirm");
                mapData(beginLeaderPick, scene)
            } else {
                AudioStreamPlayer.play("confirm");
                mapData(toggleSelect, scene)
            }
        else scene

    /// リーダー選び中のキー処理。確定で出撃パーティを保存して Playing へ進む。
    def handleLeaderKey(key: GameEngine.Key, _data: Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState, PartySelection.State} =
        if (isLeft(key))      { AudioStreamPlayer.play("cursor"); mapData(moveLeaderFocus(-1), scene) }
        else if (isRight(key)) { AudioStreamPlayer.play("cursor"); mapData(moveLeaderFocus(1), scene) }
        else if (isConfirm(key)) { AudioStreamPlayer.play("confirm"); commitLeader(scene) }
        else if (isCancel(key))  { AudioStreamPlayer.play("cancel"); mapData(backToMembers, scene) }
        else scene

    /// 出撃パーティを「リーダー先頭」で `PartySelection` に保存し、GamePhase を Playing へ。
    /// 次フレームの差分検出で `applyPhaseChange(Playing)` が走り、その並びでダンジョンが組まれる。
    def commitLeader(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GamePhaseState, PartySelection.State} =
        let data = getData(scene);
        PartySelection.State.put(orderedParty(data));
        GamePhaseState.put(GamePhase.Playing);
        scene

    // WASD と矢印キーの両方を受け付ける（キーボード配置の違いを吸収するため）。

    def isLeft(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Left or key == GameEngine.Key.A
    def isRight(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Right or key == GameEngine.Key.D
    def isUp(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Up or key == GameEngine.Key.W
    def isDown(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Down or key == GameEngine.Key.S
    def isConfirm(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Z or key == GameEngine.Key.Space or key == GameEngine.Key.Enter
    def isCancel(key: GameEngine.Key): Bool =
        key == GameEngine.Key.X or key == GameEngine.Key.Escape


    /// 状態からカード・カウンタ・ボタン・説明をまとめて作り直す。
    def writeVisuals(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        scene
            |> writeCarousel(data)
            |> writeCounter(data)
            |> writeButton(data)
            |> writeDesc(data)

    /// 全カードの枠・絵を更新する（位置・拡大・前後関係・枠線ハイライト）。
    def writeCarousel(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        List.foldLeft((acc, index) -> writeCard(data, index, acc), scene,
            List.range(0, List.length(data#players)))

    /// 1 枚のカード（枠 + 絵）の見た目を更新する。
    /// 枠は中央そろえの絵に合わせて「中心 - サイズ/2」を左上に置く。
    /// 枠線色で「注目（白）/ 選択中（金）/ それ以外（控えめ）」を示す。
    def writeCard(data: Data, index: Int32, scene: Scene[NodeTag]): Scene[NodeTag] =
        let cardX = data#carouselX + Int32.toFloat64(index) * cardPitch();
        let cardCenter: Vec2.Vec2 = {x = cardX, y = cardCenterY()};
        let scale = cardScale(data, index);
        let zIndex = cardZIndex(data, index);
        let modulate = cardModulate(data, index);
        let frameSize = cardFrameSize(data, index);
        let frameTopLeft: Vec2.Vec2 =
            {x = cardX - frameSize#x / 2.0, y = cardCenterY() - frameSize#y / 2.0};
        let (frameBorder, frameBorderWidth) = cardFrameBorder(data, index);
        scene
            |> Panel.mapAt(framePath(index), panel -> panel
                |> Panel.setSize(frameSize)
                |> Node2D.setPosition(frameTopLeft)
                |> Panel.setBorderColor(frameBorder)
                |> Panel.setBorderWidth(frameBorderWidth)
                |> CanvasItem.setZIndex(zIndex - 1))
            |> Sprite2D.mapAt(cardPath(index), sprite -> sprite
                |> Node2D.setPosition(cardCenter)
                |> Node2D.setScale({x = scale, y = scale})
                |> CanvasItem.setZIndex(zIndex)
                |> CanvasItem.setModulate(modulate))

    /// カードの拡大率（注目=大、その隣=中、それ以外=小）。
    def cardScale(data: Data, index: Int32): Float64 =
        let distance = Int32.abs(index - effectiveFocus(data));
        if (distance == 0) focusScale()
        else if (distance == 1) neighborScale()
        else farScale()

    /// 重なり時に注目カードが他カードに隠れないよう、注目を最前面に固定する。
    def cardZIndex(data: Data, index: Int32): Int32 =
        let distance = Int32.abs(index - effectiveFocus(data));
        if (distance == 0) 100 else 50 - distance

    /// カード枠のサイズ（注目だけ少し大きく）。
    def cardFrameSize(data: Data, index: Int32): Vec2.Vec2 =
        if (index == effectiveFocus(data)) focusFrameSize() else normalFrameSize()

    /// カード枠の枠線（色, 太さ）。選択中=金で太く（常に分かるよう最優先）、
    /// 未選択で注目中=白で太く、それ以外=控えめで細い。
    /// 注目は枠サイズ（`cardFrameSize` で少し大きい）でも示すので、選択中かつ注目でも
    /// 「大きい金枠」で選択と注目の両方が分かる。
    def cardFrameBorder(data: Data, index: Int32): (Color, Int32) =
        let focused = index == effectiveFocus(data);
        let selected = List.memberOf(index, data#selected);
        if (selected) (selectedColor(), 2)
        else if (focused) (focusBorderColor(), 2)
        else (frameDimBorder(), 1)

    /// カードの色味。リーダー選び中は選んだ 3 人以外を暗くして候補を目立たせる。
    def cardModulate(data: Data, index: Int32): Color =
        match data#mode {
            case SubMode.PickingMembers => textColor()
            case SubMode.PickingLeader  =>
                if (List.memberOf(index, data#selected)) textColor() else dimModulate()
        }

    /// 「残り N 人」/ リーダー選びの案内文を更新する。
    def writeCounter(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        let text = match data#mode {
            case SubMode.PickingMembers => "残り ${remaining(data)} 人"
            case SubMode.PickingLeader  => "リーダーを えらんでください"
        };
        Label2D.mapAt(counterPath(), Label2D.setText(text), scene)

    /// 出撃ボタンの見た目を状態に応じて変える（参考 UI に寄せた琥珀グラデ風）:
    ///   3 人未満       → 沈んだ灰背景・くすんだ文字・つや無し・枠なし（押せないと分かる）
    ///   3 人 + 非注目  → 深いオレンジ＋つや・白文字・**枠なし**
    ///   3 人 + 注目中  → 明るいオレンジ＋明るいつや・白文字・**白枠**（カーソルを乗せた時だけ枠が出る）
    /// 枠は通常出さず、カーソルが乗っている（onButton）ときだけ表示する。
    def writeButton(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        let deployable = canDeploy(data);
        let (background, gloss, label) =
            if (not deployable)
                (buttonDisabledBg(), buttonActiveGloss(), buttonDisabledText())
            else if (data#onButton)
                (buttonFocusBg(), buttonFocusGloss(), textColor())
            else
                (buttonActiveBg(), buttonActiveGloss(), textColor());
        // 枠は注目中だけ出す（通常は太さ 0 = 枠なし）。
        let borderWidth = if (data#onButton) 2 else 0;
        scene
            |> Panel.mapAt(buttonBgPath(), panel -> panel
                |> Panel.setBackgroundColor(background)
                |> Panel.setBorderColor(buttonFocusBorder())
                |> Panel.setBorderWidth(borderWidth))
            |> Panel.mapAt(buttonGlossPath(), panel -> panel
                |> Panel.setBackgroundColor(gloss)
                |> CanvasItem.setVisible(deployable))
            |> Label2D.mapAt(buttonLabelPath(), CanvasItem.setModulate(label))

    /// 右側の説明（注目キャラ名 + 得意武器）を更新する。
    /// 得意武器は「得意武器:」見出し＋下に武器系統グリフ（WeaponGlyph）を横一列で示す（文字ではなく図）。
    def writeDesc(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        let (name, profTypes) = match List.nth(effectiveFocus(data), data#players) {
            case Some(resource) => (resource#description, resource#proficientWeaponTypes)
            case None           => ("", Nil)
        };
        scene
            |> Label2D.mapAt(descTitlePath(), Label2D.setText(name))
            |> Label2D.mapAt(descTextPath(), Label2D.setText(proficiencyHeader(profTypes)))
            |> writeProficiencyGlyphs(profTypes)

    /// 得意武器の見出し。タイプがあれば「得意武器:」だけ（実体はグリフで示す）、無ければ「得意武器:\nなし」。
    pub def proficiencyHeader(types: List[WeaponCatalog.WeaponType]): String =
        match types {
            case Nil => "得意武器:\nなし"
            case _   => "得意武器:"
        }

    /// 得意武器グリフ行を貼り直す（注目キャラが変わるたびに呼ぶ）。既存の最大 maxProfGlyphs() 個を
    /// 消してから、得意タイプぶんだけ横一列に縮小グリフを生やす。タイプ無し（素手系）なら消すだけ。
    def writeProficiencyGlyphs(types: List[WeaponCatalog.WeaponType],
                               scene: Scene[NodeTag]): Scene[NodeTag] =
        let cleared = List.foldLeft((acc, i) -> Scene.removeAt(profGlyphPath(i), acc),
            scene, List.range(0, maxProfGlyphs()));
        List.foldLeft((acc, iWt) -> let (i, wt) = iWt; addProficiencyGlyph(i, wt, acc),
            cleared, List.zipWithIndex(List.take(maxProfGlyphs(), types)))

    /// i 番目の得意武器グリフを横位置 i に生やす。親 Marker2D（位置・z 底上げ）配下に
    /// 縮小済みグリフのピースを並べる。
    def addProficiencyGlyph(i: Int32, wt: WeaponCatalog.WeaponType,
                            scene: Scene[NodeTag]): Scene[NodeTag] =
        let pos = {x = glyphRowStartX() + Int32.toFloat64(i) * glyphPitch(), y = glyphRowY()};
        let parent = Marker2D.make(pos) |> CanvasItem.setZIndex(glyphParentZIndex());
        let withParent = Scene.addChild(rootName(), profGlyphName(i),
            EngineNode.Marker2DWithState(parent, NodeTag.NoTag), scene);
        List.foldLeft((acc, ne) ->
                let (cname, node) = ne;
                Scene.addChildAt(profGlyphPath(i), cname, node, acc),
            withParent, WeaponGlyph.weaponGlyphScaled(wt, glyphScale()))

    /// ルートに紐づく選択状態を取り出す。
    def getData(scene: Scene[NodeTag]): Data =
        match Scene.getState(rootPath(), scene) {
            case Some(NodeTag.CharacterSelect(data)) => data
            case _                                   => bug!("CharacterSelect root not found")
        }

    /// getData + setState を必ず組み合わせて使う規約を強制する唯一の窓口。
    def mapData(f: Data -> Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        setState(f(getData(scene)), scene)

    /// 選択状態をルート CanvasLayer に書き戻す。
    def setState(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        Scene.mapEngineNode(rootPath(), node -> match node {
            case EngineNode.CanvasLayerWithState(layer, NodeTag.CharacterSelect(_)) =>
                EngineNode.CanvasLayerWithState(layer, NodeTag.CharacterSelect(data))
            case other => other
        }, scene)
}
