// ConfigMenuUi — コンフィグ画面の行フォーカス層。
// UiMenu は「どの行が選ばれているか」だけを扱う共通部品なので、「選んだ行の中で
// 左右キー・決定キー・クリック・ドラッグがどう効くか」は行の種類（音量つまみ/on-off/
// 選ぶ/閉じる）ごとに変わる。この解釈だけをここに集める（設計壁打ちの結論:
// 行種類はゲームごとに揺れるので engine_world には上げず feature_lab に置く）。
mod ConfigMenuUi {

    /// 行の種類。meta 文字列（ui.json の "meta"）1 つにつき 1 種類を対応させる。
    enum RowKind with Eq {
        case Slider
        case Toggle
        case Action
    }

    /// meta 文字列 → 行の種類。知らない meta は Action 扱い（無反応にはせず、
    /// 決定キーだけ効く安全側に倒す）。
    def rowKindOf(meta: String): RowKind = match meta {
        case "volume" => RowKind.Slider
        case "bgm"         => RowKind.Toggle
        case "fullscreen"  => RowKind.Toggle
        case "cursor"      => RowKind.Toggle
        case _             => RowKind.Action
    }

    /// 音量スライダーの刻み幅とトラックの見た目寸法（Config.ui.json の track 幅と揃える）。
    def volumeNotch(): Float64 = 0.1
    def trackWidth(): Float64 = 100.0
    def knobY(): Float64 = -3.0

    /// トグルのピル寸法（Config.ui.json の pillTrack/pillKnob と揃える）。
    def pillTrackWidth(): Float64 = 32.0
    def pillKnobDiameter(): Float64 = 12.0
    def pillKnobY(): Float64 = 1.0
    def pillOnColor(): Color = { r = 0.4f32, g = 0.8f32, b = 1.0f32 }
    def pillOffColor(): Color = { r = 0.29f32, g = 0.31f32, b = 0.39f32 }

    def sliderState(volume: Float64): UiSlider.State =
        { value = volume, min = 0.0, max = 1.0, notch = volumeNotch() }

    // ── キー入力 ──

    enum Intent with Eq {
        case Up
        case Down
        case Left
        case Right
        case Confirm
        case Close
    }

    def table(): InputMap.Table[Intent] =
           (GameEngine.Key.Up,     Intent.Up)
        :: (GameEngine.Key.Down,   Intent.Down)
        :: (GameEngine.Key.Left,   Intent.Left)
        :: (GameEngine.Key.Right,  Intent.Right)
        :: (GameEngine.Key.Enter,  Intent.Confirm)
        :: (GameEngine.Key.Escape, Intent.Close)
        :: Nil


    /// 左右キー 1 回ぶんの入力を選択中の行の種類で解釈し、settings を更新する。
    /// Slider は値を notch ぶん動かす、Toggle は無反応（Choice と役目が被らないよう
    /// Enter/クリックだけに反応させる）、Action は無反応。
    def applyAxis(delta: Int32, meta: String, settings: World.Settings): World.Settings =
        match rowKindOf(meta) {
            case RowKind.Slider =>
                { masterVolume = UiSlider.step(delta, sliderState(settings#masterVolume))#value | settings }
            case RowKind.Toggle => settings
            case RowKind.Action => settings
        }

    /// 決定キー・クリックを選択中の行の種類で解釈する。Toggle は on/off を反転、
    /// Slider/Action は settings を変えない（Slider は左右キー/ドラッグの担当、
    /// Action=close 行は呼び側が configMenu#open を閉じる）。
    def applyConfirm(meta: String, settings: World.Settings): World.Settings =
        match rowKindOf(meta) {
            case RowKind.Toggle => toggleByMeta(meta, settings)
            case RowKind.Slider => settings
            case RowKind.Action => settings
        }

    def toggleByMeta(meta: String, settings: World.Settings): World.Settings = match meta {
        case "bgm"        => { bgmOn = UiToggle.toggled(settings#bgmOn) | settings }
        case "fullscreen" => { fullscreen = UiToggle.toggled(settings#fullscreen) | settings }
        case "cursor"     => { cursorVisible = UiToggle.toggled(settings#cursorVisible) | settings }
        case _            => settings
    }

    /// 毎フレームの system。開いていなければ何もしない。開いていれば:
    /// 上下でカーソル移動、左右で選択行の値変更、Enter で決定（Toggle 反転 or close）、
    /// Escape で閉じる。実機反映（setMasterVolume 等）はここでは行わず、World の値だけ進める
    /// （実適用は別 system の責務 — Controls.audioStep / windowStep と同じ分業）。
    /// コンフィグ画面を開くキー。LeftSuper を使う（Tab は GameEngine.Key に無く契約変更しない
    /// 方針のため、feature_lab の既存キー表 22 個のうち唯一空いている単発キーへ振り替えた）。
    def openKey(): GameEngine.Key = GameEngine.Key.LeftSuper

    pub def step(frame: App.Frame, world: World.World): World.World =
        if (not world#configMenu#open)
            (if (App.justPressed(openKey(), frame)) { configMenu = { open = true | world#configMenu } | world }
             else world)
        else {
            let taps = InputMap.taps(table(), frame);
            let closed = List.memberOf(Intent.Close, taps);
            if (closed)
                { configMenu = { open = false | world#configMenu } | world }
            else {
                let rowCount = List.length(World.configRowPaths());
                let movedCursor =
                    if (List.memberOf(Intent.Down, taps)) UiMenu.moveCursor(1, rowCount, world#configMenu#cursor)
                    else if (List.memberOf(Intent.Up, taps)) UiMenu.moveCursor(-1, rowCount, world#configMenu#cursor)
                    else world#configMenu#cursor;
                let meta = World.configRowMeta(movedCursor);
                let axisDelta =
                    if (List.memberOf(Intent.Right, taps)) 1
                    else if (List.memberOf(Intent.Left, taps)) -1
                    else 0;
                let afterAxis = if (axisDelta != 0) applyAxis(axisDelta, meta, world#settings) else world#settings;
                let confirmed = List.memberOf(Intent.Confirm, taps);
                let afterConfirm = if (confirmed) applyConfirm(meta, afterAxis) else afterAxis;
                let closeByAction = confirmed and rowKindOf(meta) == RowKind.Action;
                { settings = afterConfirm,
                  configMenu = { open = not closeByAction, cursor = movedCursor | world#configMenu } | world }
            }
        }

    // ── マウス ──

    /// hover 中の行 index（項目列にヒットしていなければ None）。
    /// hit は一番手前の葉（ラベル文字やピルのつまみ）で返るため、行そのものとの id 比較では
    /// 拾えない。名前パスの前方一致で「どの行の子孫か」を引く。
    def hoverRowIndex(ui: UiStore.UiWorld, hit: Option[EntityId]): Option[Int32] =
        hit |> Option.flatMap(id -> UiStore.pathOf(id, ui))
            |> Option.flatMap(path ->
                World.configRowPaths()
                    |> List.zipWithIndex
                    |> List.findMap(pair -> {
                        let (i, rowPath) = pair;
                        let inside = path == rowPath or String.startsWith({ prefix = "${rowPath}/" }, path);
                        if (inside) Some(i) else None
                    }))

    /// マウスの 1 フレームぶんの入力をコンフィグ画面へ適用する。
    /// hover でカーソルを吸着、クリックで決定、track 上のドラッグでスライダー値を更新する。
    /// ドラッグ中（configMenu#dragging = Some）は他行の hover/click を無視し、
    /// mouseDown が続く限り毎フレーム値を更新し続ける（動かした瞬間だけでなく
    /// 止めて押し続けているフレームも追従させるため mouseMoved は条件に使わない）。
    pub def mouseStep(frame: App.Frame, world: World.World): World.World =
        if (not world#configMenu#open) world
        else match world#configMenu#dragging {
            case Some(rowPath) => dragUpdate(frame, rowPath, world)
            case None          => hoverAndClick(frame, world#ui, world)
        }

    /// ドラッグ中: mouseDown が続く限り値を更新し、離れたら dragging を None に戻す。
    def dragUpdate(frame: App.Frame, _rowPath: String, world: World.World): World.World =
        if (not frame#mouseDown)
            { configMenu = { dragging = None | world#configMenu } | world }
        else {
            let value = UiSlider.dragValue(frame#cursor#x, trackLeftX(), trackWidth(), sliderState(world#settings#masterVolume));
            { settings = { masterVolume = value | world#settings } | world }
        }

    /// track の左端 design x 座標。ラベル列を ui.json 側で固定幅 70 にしてあるので
    /// （テキスト実寸依存だと文言変更で判定がずれる）、menu の abs x=46 + ラベル 70 +
    /// gap 10 で決定的に求まる。
    def trackLeftX(): Float64 = 46.0 + 70.0 + 10.0

    /// 未ドラッグ中: クリックで hover 中の行へ吸着し、その場で決定を実行する。
    /// スライダー行の track をクリックした場合は決定でなくドラッグ開始とする。
    def hoverAndClick(frame: App.Frame, ui: UiStore.UiWorld, world: World.World): World.World =
        let hit = UiFocus.hitTestUi(ui, View.design(), frame#cursor);
        let hoverIdx = hoverRowIndex(ui, hit);
        let cursor = Option.getWithDefault(world#configMenu#cursor, hoverIdx);
        if (not frame#mouseClicked)
            { configMenu = { cursor = cursor | world#configMenu } | world }
        else {
            let meta = World.configRowMeta(cursor);
            match rowKindOf(meta) {
                case RowKind.Slider =>
                    let rowPath = List.nth(cursor, World.configRowPaths()) |> Option.getWithDefault("");
                    { configMenu = { cursor = cursor, dragging = Some(rowPath) | world#configMenu } | world }
                case RowKind.Toggle =>
                    { settings = applyConfirm(meta, world#settings),
                      configMenu = { cursor = cursor | world#configMenu } | world }
                case RowKind.Action =>
                    { configMenu = { open = false, cursor = cursor | world#configMenu } | world }
            }
        }

    // ── 描画投影 ──

    /// 選択行ハイライトの y 座標（menu コンテンツ原点からの相対）。ハイライトは abs で
    /// フロー外なので行を押し下げず、行は y=0 からピッチ（行高 20 + gap 6 = 26）で並ぶ。
    /// UiMenu.applyHighlight は行ピッチ+inset が x/y 共通のグリッド専用で合わないため自前の式。
    def rowPitch(): Float64 = 20.0 + 6.0
    def highlightY(cursor: Int32): Float64 = Int32.toFloat64(cursor) * rowPitch()

    /// ピル型スイッチの投影: knob を左（OFF）/右（ON）へ置き、track の色を切り替える。
    /// 位置と色はここが毎フレーム書くので、ui.json 側の初期値は OFF の見た目にしてある。
    def pillApply(rowName: String, on: Bool, ui: UiStore.UiWorld): UiStore.UiWorld =
        let track = "Config/menu/${rowName}/toggle/track";
        let knobX = if (on) pillTrackWidth() - pillKnobDiameter() - 1.0 else 1.0;
        ui  |> (u -> UiStore.setAbs("${track}/knob", { x = knobX, y = pillKnobY() }, u))
            |> (u -> UiStore.setBoxColor(track, if (on) pillOnColor() else pillOffColor(), u))

    /// 毎フレームの投影 system: ハイライト位置とスライダーの塗り幅・つまみ位置を UiStore へ書く。
    /// 閉じている間は何もしない（開いた瞬間に一度呼べば足りるが、次フレームの通常投影と
    /// 揃えて「開いている間は毎フレーム」にしておくのが単純で事故が少ない）。
    /// trackWidth() は track ノードの子（fill/knob）への相対幅 — trackLeftX()（ドラッグ判定用の
    /// 絶対座標）とは別の値だが、Config.ui.json の track width と同じ 100 を指す。
    pub def projectUi(world: World.World): World.World =
        if (not world#configMenu#open)
            { ui = UiStore.setVisible("Config", false, world#ui) | world }
        else {
            let ui0 = UiStore.setVisible("Config", true, world#ui);
            let ui1 = UiStore.setAbs("Config/menu/highlight", { x = 0.0, y = highlightY(world#configMenu#cursor) }, ui0);
            let ui2 = UiSlider.apply("Config/menu/masterVolumeRow/track", sliderState(world#settings#masterVolume),
                                      trackWidth(), knobY(), ui1);
            let ui3 = ui2 |> (u -> pillApply("bgmRow", world#settings#bgmOn, u))
                          |> (u -> pillApply("fullscreenRow", world#settings#fullscreen, u))
                          |> (u -> pillApply("cursorRow", world#settings#cursorVisible, u));
            { ui = ui3 | world }
        }
}
