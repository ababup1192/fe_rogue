/// TitleMenuScene — 起動時のタイトル画面（GamePhase.Title）
///
/// 「はじめから」/「中断から再開」の 2 択。中断データ（`SuspendSave`・未使用）が無ければ
/// 「中断から再開」は選べない（淡色で表示）。CharacterSelectScene と同型で、状態は
/// `State` resource に持ち、1 押下ごとの操作は `onKeyPressed` が担う
/// （Game.flix の InputHandler から GamePhase.Title 中に委譲される）。静的画面なので毎フレームの
/// process は持たず、カーソル移動のたび `onKeyPressed` が `writeVisuals` で描き直す。
///
/// 確定:
///   - 「はじめから」   → GamePhase.CharacterSelect（出撃メンバー選択へ）
///   - 「中断から再開」 → `CustomEffects.ResumeRequest.resume`（resumable のときだけ。
///     実 scene 構築は `Game.applyPhaseChange(Playing, from = Title)` が担う）
///
/// ノード構造（drawLayer = 6。独立画面）:
///   Title (CanvasLayer, NodeTag.Title)
///     ├─ bg      (Panel designWi×designHi, NoTag)   ← 背景（画面全体を覆う）
///     ├─ title   (Label2D, NoTag)         ← タイトル文字
///     ├─ newGame (Label2D, NoTag)         ← 「はじめから」
///     └─ resume  (Label2D, NoTag)         ← 「中断から再開」（不可なら淡色）
mod TitleMenuScene {

    /// ルート CanvasLayer に持たせるタイトル画面の状態。
    /// `cursor`    — 0 = はじめから / 1 = 中断から再開。
    /// `resumable` — 中断データが再開可能か（`add` 時に `SaveManager.read` を 1 回見て確定）。
    pub type alias Data = {
        cursor    = Int32,
        resumable = Bool
    }

    /// タイトル画面の状態を持つ resource。
    /// 画面へ入るたび `add` が `State.put` で初期化し直す（resumable の再判定込み）ので、
    /// withState の seed 値は仮初期値で良い。
    pub eff State {
        def get(): Data
        def put(data: Data): Unit
    }

    pub def withState(rc: Region[r]):
            (Unit -> a \ ef) -> a \ (ef - State) + r =
        thunk -> {
            let ref: Ref[Data, r] = Ref.fresh(rc, {cursor = 0, resumable = false});
            run {
                thunk()
            } with handler State {
                def get(k)       = k(Ref.get(ref))
                def put(data, k) = { Ref.put(data, ref); k() }
            }
        }

    def rootName(): String = "Title"
    def bgName(): String = "bg"
    def titleName(): String = "title"
    def newGameName(): String = "newGame"
    def resumeName(): String = "resume"

    def newGamePath(): NodePath = rootName() :: newGameName() :: Nil
    def resumePath(): NodePath = rootName() :: resumeName() :: Nil

    /// project.json の "fonts" エントリで解決される論理名。
    def fontName(): String = "ui"
    /// 描画レイヤー（独立画面なので最前面で良い）。
    def drawLayer(): Int32 = 6

    def screenWidthF(): Float64 = Int32.toFloat64(Game.designWi())
    def screenHeightF(): Float64 = Int32.toFloat64(Game.designHi())
    def centerX(): Float64 = screenWidthF() / 2.0

    def titlePos(): Vec2.Vec2 = {x = centerX(), y = 30.0}
    def newGamePos(): Vec2.Vec2 = {x = centerX(), y = 70.0}
    def resumePos(): Vec2.Vec2 = {x = centerX(), y = 86.0}

    def titleFontSize(): Float64 = 14.0
    def optionFontSize(): Float64 = 8.0

    def bgColor(): Color = {r = 0.06f32, g = 0.07f32, b = 0.11f32}
    def titleColor(): Color = UITheme.white()
    def selectedColor(): Color = {r = 0.95f32, g = 0.8f32, b = 0.2f32}
    def normalColor(): Color = {r = 0.7f32, g = 0.7f32, b = 0.75f32}
    def disabledColor(): Color = {r = 0.35f32, g = 0.35f32, b = 0.4f32}

    def titleText(): String = "遺宝探索記"

    /// 中断データを 1 回読んで `resumable` を確定し、タイトル画面のツリーを scene に追加する。
    /// 初期化は 1 回のみ（`applyPhaseChange(Title)` から呼ばれる）。
    pub def add(scene: Scene[NodeTag]): Scene[NodeTag] \ {GameEngine.Game, Fs.FileRead, TitleMenuScene.State} =
        let atlas = GameEngine.Game.getFontAtlas(fontName());
        let saved: Option[SuspendSave.Save] = SaveManager.read(SuspendSave.slot());
        let data = ({cursor = 0, resumable = Option.nonEmpty(SuspendSave.resumable(saved))}: Data);
        // 画面（再）突入のたび状態を初期化（withState の seed は 1 回きりのため）。
        TitleMenuScene.State.put(data);
        let layer = CanvasLayer.make(drawLayer());
        let built = scene
            |> Scene.addNode(rootName(),
                EngineNode.CanvasLayerWithState(layer, NodeTag.Title))
            |> addBackground
            |> addTitle(atlas)
            |> addOptions(atlas);
        writeVisuals(data, built)

    /// 背景の単色パネル（最背面）。
    def addBackground(scene: Scene[NodeTag]): Scene[NodeTag] =
        let bg = Panel.make({x = screenWidthF(), y = screenHeightF()}, bgColor());
        Scene.addChild(rootName(), bgName(),
            EngineNode.PanelWithState(bg, NodeTag.NoTag), scene)

    /// タイトル文字（中央そろえ）。
    def addTitle(atlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let title = Label2D.make(titleText(), atlas, titleFontSize())
            |> Node2D.setPosition(titlePos())
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> CanvasItem.setModulate(titleColor())
            |> CanvasItem.setZIndex(6);
        Scene.addChild(rootName(), titleName(),
            EngineNode.Label2DWithState(title, NodeTag.NoTag), scene)

    /// 2 択（はじめから / 中断から再開）。色は `writeVisuals` でカーソル・resumable に応じて更新。
    def addOptions(atlas: FontAtlas, scene: Scene[NodeTag]): Scene[NodeTag] =
        let newGame = Label2D.make("はじめから", atlas, optionFontSize())
            |> Node2D.setPosition(newGamePos())
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> CanvasItem.setZIndex(6);
        let resume = Label2D.make("中断から再開", atlas, optionFontSize())
            |> Node2D.setPosition(resumePos())
            |> Label2D.setHorizontalAlignment(HorizontalAlignment.Center)
            |> CanvasItem.setZIndex(6);
        scene
            |> Scene.addChild(rootName(), newGameName(),
                EngineNode.Label2DWithState(newGame, NodeTag.NoTag))
            |> Scene.addChild(rootName(), resumeName(),
                EngineNode.Label2DWithState(resume, NodeTag.NoTag))

    /// カーソル位置と `resumable` に応じて 2 択の色を更新する（選択=金 / 通常=灰 / 不可=淡灰）。
    def writeVisuals(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] =
        let newGameColor = if (data#cursor == 0) selectedColor() else normalColor();
        let resumeColor =
            if (not data#resumable) disabledColor()
            else if (data#cursor == 1) selectedColor()
            else normalColor();
        scene
            |> Label2D.mapAt(newGamePath(), CanvasItem.setModulate(newGameColor))
            |> Label2D.mapAt(resumePath(), CanvasItem.setModulate(resumeColor))

    // ── state アクセサ ──
    def getData(): Data \ TitleMenuScene.State =
        TitleMenuScene.State.get()

    def setState(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] \ TitleMenuScene.State =
        TitleMenuScene.State.put(data);
        scene

    /// 2 択（はじめから=0 / 中断から再開=1）のカーソルを反転する。
    def toggleCursor(data: Data): Data =
        {cursor = if (data#cursor == 0) 1 else 0 | data}

    /// 状態を書き換え、見た目も即座に更新する（静的画面なので process を使わない）。
    def refresh(data: Data, scene: Scene[NodeTag]): Scene[NodeTag] \ TitleMenuScene.State =
        writeVisuals(data, setState(data, scene))

    /// 1 押下ごとの操作（Game.flix の InputHandler から GamePhase.Title 中に委譲）。
    pub def onKeyPressed(key: GameEngine.Key, scene: Scene[NodeTag]):
            Scene[NodeTag] \ {GameEngine.Audio, GamePhaseState, CustomEffects.ResumeRequest,
                              TitleMenuScene.State} =
        let data = getData();
        if (isUp(key) or isDown(key))
            // 中断データが無い / 使用済みなら「はじめから」固定（カーソルを動かさない）。
            if (data#resumable) {
                AudioStreamPlayer.play("cursor");
                refresh(toggleCursor(data), scene)
            } else scene
        else if (isConfirm(key))
            // (カーソル, 再開可否) で確定先を 1 段で分岐する。
            match (data#cursor, data#resumable) {
                case (0, _)    =>
                    AudioStreamPlayer.play("confirm");
                    GamePhaseState.put(GamePhase.CharacterSelect);
                    scene
                case (_, true) =>
                    AudioStreamPlayer.play("confirm");
                    CustomEffects.ResumeRequest.resume(scene)
                case (_, _)    =>
                    // 中断データが無い / 使用済みなら再開できない（カーソル固定で通常来ない）。
                    AudioStreamPlayer.play("cancel");
                    scene
            }
        else scene

    def isUp(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Up or key == GameEngine.Key.W
    def isDown(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Down or key == GameEngine.Key.S
    def isConfirm(key: GameEngine.Key): Bool =
        key == GameEngine.Key.Z or key == GameEngine.Key.Space or key == GameEngine.Key.Enter
}
