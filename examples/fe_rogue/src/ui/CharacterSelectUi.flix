// CharacterSelectUi — ゲーム開始時の出撃メンバー選択画面（World-entity UI 版）。
//
// UI ツリーは CharacterSelect.ui.json（UiSpec）で宣言し、UiWorldState resource に spawn される。
// 見た目は UiRender が毎フレーム描く。ここは「選択状態からカード列・カウンタ・ボタン・説明を
// 毎フレーム組み直す / カルーセルを時間で寄せる / 1 押下ごとの操作を適用する」のゲーム側配線を持つ。
//
// 起動直後（GamePhase.CharacterSelect）に表示する画面。プレイヤーは横スクロールする「しおり」状の
// カード列から出撃メンバーを 3 人選び、そのあとリーダー（集合したときに仲間が合流する先＝ロード）を
// 1 人選ぶ。選び終えると `PartySelection.State` にリーダーを先頭にした並びで保存し、GamePhase を
// Playing に切り替える。ダンジョン構築（`SceneSetup.buildPlaying`）は Playing 突入時に走り、
// `PlayerScene.add` が保存済みの並びをそのまま使う（先頭がロードになる）。
//
// 操作（キーボード）:
//   - メンバー選び（PickingMembers）
//       ← → : カードの注目位置を左右に送る（中央のカードが拡大表示＝立ち絵風）
//       Z    : 注目中のカードを選ぶ / 選択を外す（3 人まで）
//       ↓    : 3 人揃っているとき、注目を下の「出撃」ボタンへ移す
//       ↑    : 注目をカード列に戻す
//       Z（出撃ボタンに注目中）: リーダー選びへ進む
//   - リーダー選び（PickingLeader）
//       ← → : 選んだ 3 人の中でリーダー候補を移す
//       Z    : リーダー確定 → ゲーム開始
//       X    : メンバー選びに戻る
//
// 画面の状態（注目位置・選択リスト・サブモード・カルーセルの横位置）は `CharacterSelectState.State`
// resource が権威。毎フレームの見た目更新は `frameStep`（root 可視のときだけ）、1 押下ごとの操作は
// `onKeyPressed` が担う（どちらも Game.flix から委譲される）。純粋な選択ロジックは effect を持たない
// 関数に切り出してテストする。
//
// ノード構造（CharacterSelect.ui.json / layer=6・独立画面）:
//   CharacterSelect (none, 画面全体)
//     ├─ bg        (box 240×128)                 ← 背景（画面全体を覆う）
//     ├─ frame0..7 (box)                         ← 各カードの枠（注目=白枠 / 選択中=金枠・毎フレ位置/サイズ更新）
//     ├─ card0..7  (sprite)                      ← 各ユニットの絵（毎フレーム位置/拡大/明暗を更新）
//     ├─ descPanel (box) + descTitle/descText (text) + profGlyph0..4 (poly)  ← 右側の特性説明
//     ├─ counter   (text)                        ← 「残り N 人」/ リーダー選びの案内
//     └─ buttonBg (box) + buttonGloss (box) + buttonLabel (text)             ← 出撃ボタン
mod CharacterSelectUi {

    /// 選択画面のサブモード。
    ///   PickingMembers — 出撃する 3 人を選んでいる段階。
    ///   PickingLeader  — 選んだ 3 人からリーダー（ロード）を選んでいる段階。
    pub enum SubMode with Eq, ToString {
        case PickingMembers
        case PickingLeader
    }

    /// 選択画面の状態。
    /// `players`     — 候補ユニット一覧（enter のとき確定。index → 実データの解決に使う）。
    /// `classIds`    — `players` と同じ並び・同じ長さのクラス id。表示は `players` のみで行い、id は
    ///                 確定時 (`orderedParty`) に PartySelection へ resource と対で渡すために保持する。
    /// `mode`        — 今どちらの段階か。
    /// `focus`       — メンバー選び中に注目しているカードの index（0 始まり）。
    /// `onButton`    — メンバー選び中、注目が「出撃」ボタンに移っているか。
    /// `selected`    — 選んだユニットの index を選んだ順に並べたリスト（最大 3）。
    /// `leaderFocus` — リーダー選び中、`selected` の何番目を候補にしているか。
    /// `carouselX`   — カード列の横位置（注目カードが中央に来るよう frameStep で滑らかに寄せる）。
    pub type alias Data = {
        players     = List[UnitCatalog.PlayerResource],
        classIds    = List[String],
        mode        = SubMode,
        focus       = Int32,
        onButton    = Bool,
        selected    = List[Int32],
        leaderFocus = Int32,
        carouselX   = Float64
    }

    // ========================================================================
    // spec 置き場 / 名前パス / 定数
    // ========================================================================

    /// ui.json の置き場。起動時の spawnAsset・F1 リロード台帳の登録に使う。
    pub def specPath(): String = AssetPath.resolve("src/ui/assets/CharacterSelect.ui.json")

    /// root（可視トグルの対象）の名前パス。
    pub def rootPath(): String = "CharacterSelect"
    def counterPath(): String = "${rootPath()}/counter"
    def descTitlePath(): String = "${rootPath()}/descTitle"
    def descTextPath(): String = "${rootPath()}/descText"
    def buttonBgPath(): String = "${rootPath()}/buttonBg"
    def buttonGlossPath(): String = "${rootPath()}/buttonGloss"
    def buttonLabelPath(): String = "${rootPath()}/buttonLabel"
    def framePath(index: Int32): String = "${rootPath()}/frame${index}"
    def cardPath(index: Int32): String = "${rootPath()}/card${index}"
    def profGlyphPath(index: Int32): String = "${rootPath()}/profGlyph${index}"

    /// UI 幅・カルーセル間隔を含む制約から決まる上限。FE シリーズ慣習とも一致。
    def partySize(): Int32 = 3
    /// カードスロットの最大数（ui.json の frame0..7 / card0..7 と一致させること）。
    /// pub: 実 asset のスロット宣言数と一致することをテストが pin する。
    pub def maxCards(): Int32 = 8
    /// 得意武器グリフスロットの最大数（ui.json の profGlyph0..4 と一致）。
    def maxProfGlyphs(): Int32 = 5

    /// project.json の "fonts" エントリで解決される論理名。
    def fontName(): String = "ui"

    // レイアウト（論理解像度 240×128 内）。右側 ~50px を説明パネルに割き、左側でカードを送る。
    def screenWidthF(): Float64 = Int32.toFloat64(Game.designWi())
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
    /// 説明パネルを画面右端から内側へどれだけ離すか（px）。
    def descRightMargin(): Float64 = 4.0
    /// 説明パネル左端 x。画面右端（screenWidthF）から margin + パネル幅 だけ内側＝右端基準で固定。
    def descAnchorX(): Float64 = screenWidthF() - descRightMargin() - descSize()#x
    // 得意武器グリフ行（「得意武器:」の下に白いグリフを横一列）。
    def glyphRowStartX(): Float64 = descAnchorX() + 6.0
    def glyphRowY(): Float64 = 37.0
    def glyphPitch(): Float64 = 9.0
    def glyphScale(): Float64 = 0.52
    // カウンタ/出撃ボタンは画面中央に寄せる。
    def counterCenterX(): Float64 = screenWidthF() / 2.0
    def counterTopY(): Float64 = 88.0
    def buttonLabelCenterX(): Float64 = screenWidthF() / 2.0
    def buttonLabelCenterY(): Float64 = 110.0

    def counterFontSize(): Float64 = 7.5
    def buttonFontSize(): Float64 = 8.0

    // 色（RGB 各 0..1）。説明パネルの地色・枠色は静的なので ui.json 側で宣言する。
    def focusBorderColor(): Color = UITheme.white()
    def selectedColor(): Color = {r = 0.95f32, g = 0.8f32, b = 0.2f32}
    def textColor(): Color = UITheme.white()
    def dimModulate(): Color = {r = 0.45f32, g = 0.45f32, b = 0.45f32}
    /// カード枠の背景色（背景より少し明るい）。
    def frameColor(): Color = {r = 0.16f32, g = 0.17f32, b = 0.22f32}
    /// 注目でも選択中でもないカード枠の控えめな枠線色。
    def frameDimBorder(): Color = {r = 0.4f32, g = 0.4f32, b = 0.5f32}

    // 出撃ボタンの配色（無効 / 有効 / 有効かつ注目中）。参考 UI に寄せた琥珀色グラデ風。
    def buttonDisabledBg(): Color = {r = 0.22f32, g = 0.21f32, b = 0.20f32}
    def buttonDisabledText(): Color = {r = 0.55f32, g = 0.53f32, b = 0.5f32}
    def buttonActiveBg(): Color = {r = 0.82f32, g = 0.42f32, b = 0.10f32}
    def buttonActiveGloss(): Color = {r = 1.0f32, g = 0.72f32, b = 0.28f32}
    def buttonFocusBg(): Color = {r = 0.95f32, g = 0.52f32, b = 0.14f32}
    def buttonFocusGloss(): Color = {r = 1.0f32, g = 0.82f32, b = 0.40f32}
    def buttonFocusBorder(): Color = UITheme.white()

    // ========================================================================
    // 純粋: 状態遷移（テスト対象）
    // ========================================================================

    /// 起動直後の状態。注目は先頭カード、未選択、メンバー選び段階。
    /// `playersWithIds` を表示用 `players`（resource）とクラス id 列 `classIds` に分けて保持する。
    pub def initialState(playersWithIds: List[(String, UnitCatalog.PlayerResource)]): Data =
        {players = List.map(snd, playersWithIds), classIds = List.map(fst, playersWithIds),
         mode = SubMode.PickingMembers, focus = 0, onButton = false,
         selected = Nil, leaderFocus = 0, carouselX = targetCarouselX(0)}

    /// 候補ゼロの空状態。`CharacterSelectState.withState` の初期シード用
    /// （選択画面へ入る前の既定値。`enter` が本物の候補一覧で put し直す）。
    pub def emptyState(): Data =
        {players = Nil, classIds = Nil,
         mode = SubMode.PickingMembers, focus = 0, onButton = false,
         selected = Nil, leaderFocus = 0, carouselX = 0.0}

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

    /// 得意武器の見出し。タイプがあれば「得意武器:」だけ（実体はグリフで示す）、無ければ「得意武器:\nなし」。
    pub def proficiencyHeader(types: List[WeaponCatalog.WeaponType]): String =
        match types {
            case Nil => "得意武器:\nなし"
            case _   => "得意武器:"
        }

    // ========================================================================
    // 画面進入 / 退出（状態初期化 + 可視トグル + 初期描画）
    // ========================================================================

    /// 出撃メンバー選択画面へ入るたびに呼ぶ。候補一覧から初期状態を put し、root を可視化して
    /// 1 度見た目を流し込む（次フレームからは `frameStep` が更新する）。`SceneSetup.buildCharacterSelect`
    /// から呼ばれ、scene はパイプ素通し。
    pub def enter(playersWithIds: List[(String, UnitCatalog.PlayerResource)], scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, CharacterSelectState.State, UiWorldState.State} =
        let data = initialState(playersWithIds);
        CharacterSelectState.State.put(data);
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        UiWorldState.State.put(UiWorldState.State.get()
            |> UiStore.setVisible(rootPath(), true)
            |> writeVisuals(data, atlas));
        scene

    /// ダンジョン / タイトル画面へ出るときに選択画面を隠す。scene はパイプ素通し。
    pub def leave(scene: Scene[NodeTag]): Scene[NodeTag] \ UiWorldState.State =
        UiWorldState.State.put(UiStore.setVisible(rootPath(), false, UiWorldState.State.get()));
        scene

    // ========================================================================
    // 毎フレーム同期（カルーセルの時間発展 + 状態からの描画）
    // ========================================================================

    /// gameLoop が 1 回呼ぶ frame-paced System。root が可視（選択画面中）のときだけ、カルーセルを
    /// 目標へ寄せ、状態からカード・カウンタ・ボタン・説明を作り直して状態を書き戻す。可視でなければ no-op。
    pub def frameStep(delta: Duration.Duration, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Game, CharacterSelectState.State, UiWorldState.State} =
        let ui0 = UiWorldState.State.get();
        if (not isActive(ui0)) scene
        else {
            let stepped = stepCarousel(CharacterSelectState.State.get(), delta);
            CharacterSelectState.State.put(stepped);
            let atlas = GameEngine.Game.getFontAtlas(fontName());
            UiWorldState.State.put(writeVisuals(stepped, atlas, ui0));
            scene
        }

    /// root が可視（選択画面中）か。未 spawn / 不可視なら no-op ゲート。
    def isActive(ui: UiStore.UiWorld): Bool =
        UiStore.idOf(rootPath(), ui)
            |> Option.flatMap(id -> Map.get(id, ui#visible))
            |> Option.getWithDefault(false)

    /// 状態からカード・カウンタ・ボタン・説明をまとめて作り直す。
    def writeVisuals(data: Data, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld \ GameEngine.Game =
        ui
            |> writeCarousel(data)
            |> writeCounter(data, atlas)
            |> writeButton(data, atlas)
            |> writeDesc(data)

    /// 全カードスロットを更新する。候補ぶんは枠・絵を出し、余ったスロットは隠す。
    def writeCarousel(data: Data, ui: UiStore.UiWorld): UiStore.UiWorld \ GameEngine.Game =
        List.foldLeft((acc, index) ->
            match List.nth(index, data#players) {
                case Some(resource) => writeCard(data, index, resource, acc)
                case None           => acc
                    |> UiStore.setVisible(framePath(index), false)
                    |> UiStore.setVisible(cardPath(index), false)
            }, ui, List.range(0, maxCards()))

    /// 1 枚のカード（枠 + 絵）の見た目を更新する。
    /// 枠は中央そろえの絵に合わせて「中心 - サイズ/2」を左上に置く。
    /// 枠線色で「注目（白）/ 選択中（金）/ それ以外（控えめ）」を示し、注目だけ枠を少し大きくする。
    def writeCard(data: Data, index: Int32, resource: UnitCatalog.PlayerResource,
                  ui: UiStore.UiWorld): UiStore.UiWorld \ GameEngine.Game =
        let cardX = data#carouselX + Int32.toFloat64(index) * cardPitch();
        let cardCenter: Vec2.Vec2 = {x = cardX, y = cardCenterY()};
        let scale = cardScale(data, index);
        let tint = cardModulate(data, index);
        let frameSize = cardFrameSize(data, index);
        let frameTopLeft: Vec2.Vec2 =
            {x = cardX - frameSize#x / 2.0, y = cardCenterY() - frameSize#y / 2.0};
        let (frameBorder, frameBorderWidth) = cardFrameBorder(data, index);
        let spriteTopLeft = cardSpriteTopLeft(resource, scale, cardCenter);
        ui
            |> UiStore.setVisible(framePath(index), true)
            |> UiStore.setWidthPx(framePath(index), frameSize#x)
            |> UiStore.setHeightPx(framePath(index), frameSize#y)
            |> UiStore.setAbs(framePath(index), frameTopLeft)
            |> UiStore.setBoxColor(framePath(index), frameColor())
            |> UiStore.setBoxBorderColor(framePath(index), frameBorder)
            |> UiStore.setBoxBorderWidth(framePath(index), frameBorderWidth)
            |> UiStore.setVisible(cardPath(index), true)
            |> UiStore.setSprite({path = cardPath(index), texture = resource#sprite#texture,
                                  hframes = resource#sprite#hframes, vframes = resource#sprite#vframes,
                                  frame = resource#sprite#frame})
            |> UiStore.setSpriteScale(cardPath(index), {x = scale, y = scale})
            |> UiStore.setSpriteTint(cardPath(index), tint)
            |> UiStore.setAbs(cardPath(index), spriteTopLeft)

    /// カードの絵（スプライトシートのセル）を中心 `center` に据えるための左上（top-left）。
    /// texture 実寸から半セルぶん（× scale）左上へ寄せて中心合わせする。texture 未登録は中心そのまま。
    def cardSpriteTopLeft(resource: UnitCatalog.PlayerResource, scale: Float64,
                          center: Vec2.Vec2): Vec2.Vec2 \ GameEngine.Game =
        match GameEngine.Game.getTextureInfo(resource#sprite#texture) {
            case None       => center
            case Some(info) =>
                let cellW = info#width / Int32.toFloat64(resource#sprite#hframes);
                let cellH = info#height / Int32.toFloat64(resource#sprite#vframes);
                {x = center#x - cellW * scale / 2.0, y = center#y - cellH * scale / 2.0}
        }

    /// カードの拡大率（注目=大、その隣=中、それ以外=小）。
    def cardScale(data: Data, index: Int32): Float64 =
        let distance = Int32.abs(index - effectiveFocus(data));
        if (distance == 0) focusScale()
        else if (distance == 1) neighborScale()
        else farScale()

    /// カード枠のサイズ（注目だけ少し大きく）。
    def cardFrameSize(data: Data, index: Int32): Vec2.Vec2 =
        if (index == effectiveFocus(data)) focusFrameSize() else normalFrameSize()

    /// カード枠の枠線（色, 太さ）。選択中=金で太く（常に分かるよう最優先）、
    /// 未選択で注目中=白で太く、それ以外=控えめで細い。
    def cardFrameBorder(data: Data, index: Int32): (Color, Float64) =
        let focused = index == effectiveFocus(data);
        let selected = List.memberOf(index, data#selected);
        if (selected) (selectedColor(), 2.0)
        else if (focused) (focusBorderColor(), 2.0)
        else (frameDimBorder(), 1.0)

    /// カードの色味。リーダー選び中は選んだ 3 人以外を暗くして候補を目立たせる。
    def cardModulate(data: Data, index: Int32): Color =
        match data#mode {
            case SubMode.PickingMembers => textColor()
            case SubMode.PickingLeader  =>
                if (List.memberOf(index, data#selected)) textColor() else dimModulate()
        }

    /// 「残り N 人」/ リーダー選びの案内文を更新し、中央（counterCenterX）へ水平中央そろえで置く。
    def writeCounter(data: Data, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld =
        let text = match data#mode {
            case SubMode.PickingMembers => "残り ${remaining(data)} 人"
            case SubMode.PickingLeader  => "リーダーを えらんでください"
        };
        let width = Label2D.measure(Label2D.make(text, atlas, counterFontSize()))#x;
        ui
            |> UiStore.setText(counterPath(), text)
            |> UiStore.setAbs(counterPath(), {x = counterCenterX() - width / 2.0, y = counterTopY()})

    /// 出撃ボタンの見た目を状態に応じて変える（参考 UI に寄せた琥珀グラデ風）:
    ///   3 人未満       → 沈んだ灰背景・くすんだ文字・つや無し・枠なし（押せないと分かる）
    ///   3 人 + 非注目  → 深いオレンジ＋つや・白文字・枠なし
    ///   3 人 + 注目中  → 明るいオレンジ＋明るいつや・白文字・白枠（カーソルを乗せた時だけ枠が出る）
    def writeButton(data: Data, atlas: FontAtlas, ui: UiStore.UiWorld): UiStore.UiWorld =
        let deployable = canDeploy(data);
        let (background, gloss, label) =
            if (not deployable)
                (buttonDisabledBg(), buttonActiveGloss(), buttonDisabledText())
            else if (data#onButton)
                (buttonFocusBg(), buttonFocusGloss(), textColor())
            else
                (buttonActiveBg(), buttonActiveGloss(), textColor());
        // 枠は注目中だけ出す（通常は太さ 0 = 枠なし）。
        let borderWidth = if (data#onButton) 2.0 else 0.0;
        // ラベルは枠内中央（水平・垂直とも中央そろえ）に置く。
        let measured = Label2D.measure(Label2D.make("出撃", atlas, buttonFontSize()));
        ui
            |> UiStore.setBoxColor(buttonBgPath(), background)
            |> UiStore.setBoxBorderColor(buttonBgPath(), buttonFocusBorder())
            |> UiStore.setBoxBorderWidth(buttonBgPath(), borderWidth)
            |> UiStore.setBoxColor(buttonGlossPath(), gloss)
            |> UiStore.setVisible(buttonGlossPath(), deployable)
            |> UiStore.setTextTint(buttonLabelPath(), label)
            |> UiStore.setAbs(buttonLabelPath(), {x = buttonLabelCenterX() - measured#x / 2.0,
                                                  y = buttonLabelCenterY() - measured#y / 2.0})

    /// 右側の説明（注目キャラ名 + 得意武器）を更新する。
    /// 得意武器は「得意武器:」見出し＋下に武器系統グリフ（WeaponGlyph）を横一列で示す（文字ではなく図）。
    def writeDesc(data: Data, ui: UiStore.UiWorld): UiStore.UiWorld =
        let (name, profTypes) = match List.nth(effectiveFocus(data), data#players) {
            case Some(resource) => (resource#description, resource#proficientWeaponTypes)
            case None           => ("", Nil)
        };
        ui
            |> UiStore.setText(descTitlePath(), name)
            |> UiStore.setText(descTextPath(), proficiencyHeader(profTypes))
            |> writeProficiencyGlyphs(profTypes)

    /// 得意武器グリフ行を貼り直す（注目キャラが変わるたびに呼ぶ）。得意タイプぶんだけ横一列に縮小
    /// グリフの凸ポリゴン列を流し込み、余ったスロットは隠す。タイプ無し（素手系）なら全部隠す。
    def writeProficiencyGlyphs(types: List[WeaponCatalog.WeaponType],
                               ui: UiStore.UiWorld): UiStore.UiWorld =
        let shown = List.take(maxProfGlyphs(), types);
        List.foldLeft((acc, index) -> match List.nth(index, shown) {
            case Some(wt) =>
                let center = {x = glyphRowStartX() + Int32.toFloat64(index) * glyphPitch(), y = glyphRowY()};
                acc
                    |> UiStore.setVisible(profGlyphPath(index), true)
                    |> UiStore.setAbs(profGlyphPath(index), center)
                    |> UiStore.setPolyPolys(profGlyphPath(index), WeaponGlyph.weaponGlyphPolys(wt, glyphScale()))
            case None     => UiStore.setVisible(profGlyphPath(index), false, acc)
        }, ui, List.range(0, maxProfGlyphs()))

    // ========================================================================
    // 入力（1 押下ごと。Game.onKeyPressed が GamePhase.CharacterSelect 中に委譲）
    // ========================================================================

    /// 1 押下ごとの操作。サブモードで分岐する（見た目は次フレームの frameStep が更新する）。
    pub def onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState, PartySelection.State,
                              CharacterSelectState.State} =
        let data = CharacterSelectState.State.get();
        match data#mode {
            case SubMode.PickingMembers => handleMembersKey(key, data, scene)
            case SubMode.PickingLeader  => handleLeaderKey(key, data, scene)
        }

    /// メンバー選び中のキー処理。
    def handleMembersKey(key: GameEngine.Key, data: Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, CharacterSelectState.State} =
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
            Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState, PartySelection.State,
                              CharacterSelectState.State} =
        if (isLeft(key))      { AudioStreamPlayer.play("cursor"); mapData(moveLeaderFocus(-1), scene) }
        else if (isRight(key)) { AudioStreamPlayer.play("cursor"); mapData(moveLeaderFocus(1), scene) }
        else if (isConfirm(key)) { AudioStreamPlayer.play("confirm"); commitLeader(scene) }
        else if (isCancel(key))  { AudioStreamPlayer.play("cancel"); mapData(backToMembers, scene) }
        else scene

    /// 出撃パーティを「リーダー先頭」で `PartySelection` に保存し、GamePhase を Playing へ。
    /// 次フレームの差分検出で `applyPhaseChange(Playing)` が走り、その並びでダンジョンが組まれる。
    def commitLeader(scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GamePhaseState, PartySelection.State, CharacterSelectState.State} =
        let data = CharacterSelectState.State.get();
        PartySelection.State.put(orderedParty(data));
        GamePhaseState.put(GamePhase.Playing);
        scene

    /// 状態を `f` で更新して書き戻す。scene は素通し（view 更新は次フレームの `frameStep` が担う）。
    def mapData(f: Data -> Data, scene: Scene[NodeTag]):
            Scene[NodeTag] \ CharacterSelectState.State =
        CharacterSelectState.State.put(f(CharacterSelectState.State.get()));
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
}
